#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import io
import json
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
from netgen_source import expected_source_provenance  # noqa: E402


VERIFY = SCRIPTS / "verify-netgen-sdk-release.py"
QUALIFY = SCRIPTS / "check-release-qualification.py"
PRODUCER_SHA = "a" * 40
PRODUCER_REPOSITORY = "precise-simulation/netgen"
OCCT_SOURCE_SHA = "b" * 40


class ReleaseVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.assets = self.root / "assets"
        self.provenance = expected_source_provenance(REPO_ROOT)
        self.occt_release = (REPO_ROOT / ".github" / "occt-sdk-release.txt").read_text(encoding="utf-8").strip()
        self.occt_version = self.occt_release.removeprefix("occt-sdk-").split("-r", 1)[0]
        self.release_assets: list[dict[str, object]] = []
        self.infos: dict[str, dict[str, object]] = {}
        self.build_archives()
        self.release_json = self.root / "occt-release.json"
        self.write_release_json()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def specs(self) -> list[tuple[str, str, str, bool]]:
        version = self.provenance["upstream"]["version"]
        prefix = f"netgen-featool-v{version}-{PRODUCER_SHA[:12]}-occt{self.occt_version}"
        return [
            (f"{prefix}-win64-msvc.zip", "windows", "shared", False),
            (f"{prefix}-win64-msvc-static.zip", "windows", "static", True),
            (f"{prefix}-linux-x86_64-glibc2.17-gcc10.tar.gz", "linux", "shared", False),
            (f"{prefix}-linux-x86_64-glibc2.17-gcc10-static.tar.gz", "linux", "static", False),
            (f"{prefix}-macos13-x86_64-clang.tar.gz", "macos", "shared", False),
            (f"{prefix}-macos13-x86_64-clang-static.tar.gz", "macos", "static", False),
            (f"{prefix}-macos13-arm64-clang.tar.gz", "macos", "shared", False),
            (f"{prefix}-macos13-arm64-clang-static.tar.gz", "macos", "static", False),
        ]

    def make_info(self, index: int, linkage: str, bundled: bool) -> dict[str, object]:
        asset_name = f"occt-{index}.tar.gz"
        digest = hashlib.sha256(asset_name.encode()).hexdigest()
        asset_url = f"https://example.invalid/{asset_name}"
        self.release_assets.append(
            {
                "id": index,
                "name": asset_name,
                "browser_download_url": asset_url,
                "digest": f"sha256:{digest}",
            }
        )
        occt: dict[str, object] = {
            "version": self.occt_version,
            "release": self.occt_release,
            "commit": OCCT_SOURCE_SHA,
            "linkage": linkage,
            "asset_id": index,
            "asset_name": asset_name,
            "asset_url": asset_url,
            "sha256": digest,
        }
        if bundled:
            occt["bundled"] = True
        return {
            "schema_version": 2,
            "upstream": copy.deepcopy(self.provenance["upstream"]),
            "source": {
                "repository": PRODUCER_REPOSITORY,
                "ref": "refs/heads/netgen-featool",
                "commit": PRODUCER_SHA,
                "patches": copy.deepcopy(self.provenance["patches"]),
            },
            "netgen": {"linkage": linkage},
            "occt": occt,
        }

    def write_archive(self, name: str, directory: str, info: dict[str, object]) -> None:
        folder = self.assets / directory
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / name
        payload = (json.dumps(info, sort_keys=True) + "\n").encode()
        if name.endswith(".zip"):
            with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("producer-info.json", payload)
        else:
            with tarfile.open(path, "w:gz") as archive:
                member = tarfile.TarInfo("sdk/producer-info.json")
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        path.with_name(path.name + ".sha256").write_text(f"{digest}  {name}\n", encoding="utf-8")

    def build_archives(self) -> None:
        for index, (name, directory, linkage, bundled) in enumerate(self.specs(), 1):
            info = self.make_info(index, linkage, bundled)
            self.infos[name] = info
            self.write_archive(name, directory, info)

    def write_release_json(self) -> None:
        self.release_json.write_text(
            json.dumps(
                {
                    "tag_name": self.occt_release,
                    "draft": False,
                    "immutable": True,
                    "assets": self.release_assets,
                }
            ),
            encoding="utf-8",
        )

    def run_verify(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(VERIFY),
                "--assets-root",
                str(self.assets),
                "--producer-sha",
                PRODUCER_SHA,
                "--producer-repository",
                PRODUCER_REPOSITORY,
                "--occt-release",
                self.occt_release,
                "--occt-release-json",
                str(self.release_json),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def mutate_first(self, mutation) -> None:
        name, directory, _, _ = self.specs()[0]
        info = copy.deepcopy(self.infos[name])
        mutation(info)
        self.write_archive(name, directory, info)

    def test_accepts_complete_valid_archive_set(self) -> None:
        result = self.run_verify()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejects_provenance_tampering(self) -> None:
        mutations = {
            "producer commit": lambda info: info["source"].__setitem__("commit", "c" * 40),
            "upstream tag": lambda info: info["upstream"].__setitem__("tag", "v0.0.0"),
            "upstream commit": lambda info: info["upstream"].__setitem__("commit", "d" * 40),
            "upstream version": lambda info: info["upstream"].__setitem__("version_git", "v0.0.0-0-g000000000000"),
            "patch order": lambda info: info["source"].__setitem__("patches", list(reversed(info["source"]["patches"]))),
            "patch hash": lambda info: info["source"]["patches"][0].__setitem__("sha256", "0" * 64),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label):
                self.mutate_first(mutation)
                result = self.run_verify()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                name, directory, _, _ = self.specs()[0]
                self.write_archive(name, directory, self.infos[name])


class QualificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.runs = self.root / "runs.json"
        self.compare = self.root / "compare.json"
        self.good_run = {
            "id": 123,
            "run_number": 9,
            "head_sha": PRODUCER_SHA,
            "head_branch": "automation/occt-qualify-test",
            "event": "workflow_dispatch",
            "conclusion": "success",
        }
        self.write([self.good_run], "ahead")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write(self, runs: list[dict[str, object]], status: str) -> None:
        self.runs.write_text(json.dumps({"workflow_runs": runs}), encoding="utf-8")
        self.compare.write_text(
            json.dumps({"status": status, "base_commit": {"sha": PRODUCER_SHA}}),
            encoding="utf-8",
        )

    def run_check(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(QUALIFY),
                "--repository",
                PRODUCER_REPOSITORY,
                "--workflow",
                "windows-netgen-sdk.yml",
                "--producer-sha",
                PRODUCER_SHA,
                "--runs-json",
                str(self.runs),
                "--compare-json",
                str(self.compare),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_accepts_exact_sha_dispatch_after_temporary_ref_is_gone(self) -> None:
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "123")

    def test_rejects_wrong_sha_event_conclusion_and_branch_containment(self) -> None:
        cases = {
            "wrong sha": ({**self.good_run, "head_sha": "c" * 40}, "ahead"),
            "unsupported event": ({**self.good_run, "event": "pull_request"}, "ahead"),
            "failed conclusion": ({**self.good_run, "conclusion": "failure"}, "ahead"),
            "outside branch": (self.good_run, "diverged"),
        }
        for label, (run, status) in cases.items():
            with self.subTest(label=label):
                self.write([run], status)
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
