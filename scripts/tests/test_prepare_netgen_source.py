#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PREPARE = REPO_ROOT / "scripts" / "prepare-netgen-source.py"
CANONICAL_REPOSITORY = "https://github.com/NGSolve/netgen.git"
TAG = "v1.2.3"
GOOD_PATCH = b"""diff --git a/tracked.txt b/tracked.txt
--- a/tracked.txt
+++ b/tracked.txt
@@ -1 +1 @@
-base
+patched
"""


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout.strip()


class PrepareNetgenSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.upstream = self.root / "fixture-upstream"
        self.thin = self.root / "thin"
        self.patch_dir = self.thin / "patches" / "netgen"
        (self.thin / "upstream").mkdir(parents=True)
        self.patch_dir.mkdir(parents=True)
        self.upstream.mkdir()
        git(self.upstream, "init", "--quiet")
        git(self.upstream, "config", "user.name", "Thin Netgen Test")
        git(self.upstream, "config", "user.email", "thin-netgen@example.invalid")
        (self.upstream / "tracked.txt").write_bytes(b"base\n")
        git(self.upstream, "add", "tracked.txt")
        git(self.upstream, "commit", "--quiet", "-m", "baseline")
        git(self.upstream, "tag", TAG)
        self.commit = git(self.upstream, "rev-parse", "HEAD")
        self.write_manifest(self.commit)
        (self.patch_dir / "0001.patch").write_bytes(GOOD_PATCH)
        (self.patch_dir / "series").write_bytes(b"0001.patch\n")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_manifest(self, commit: str) -> None:
        data = {"repository": CANONICAL_REPOSITORY, "tag": TAG, "commit": commit}
        (self.thin / "upstream" / "netgen.json").write_bytes(
            (json.dumps(data, indent=2) + "\n").encode("utf-8")
        )

    def run_prepare(self) -> subprocess.CompletedProcess[str]:
        destination = self.root / "prepared"
        provenance = self.root / "source-provenance.json"
        env = os.environ.copy()
        env["NETGEN_SOURCE_TESTING"] = "1"
        return subprocess.run(
            [
                sys.executable,
                str(PREPARE),
                "--repo-root",
                str(self.thin),
                "--destination",
                str(destination),
                "--provenance",
                str(provenance),
                "--test-upstream-repository",
                self.upstream.resolve().as_uri(),
            ],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def assert_rejected(self) -> None:
        result = self.run_prepare()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_prepares_exact_source_and_provenance(self) -> None:
        result = self.run_prepare()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "prepared" / "tracked.txt").read_bytes(), b"patched\n")
        provenance = json.loads((self.root / "source-provenance.json").read_text(encoding="utf-8"))
        self.assertEqual(provenance["upstream"]["commit"], self.commit)
        self.assertEqual(provenance["upstream"]["version_git"], f"{TAG}-0-g{self.commit[:12]}")
        self.assertEqual([item["path"] for item in provenance["patches"]], ["patches/netgen/0001.patch"])

    def test_rejects_unlisted_patch(self) -> None:
        (self.patch_dir / "extra.patch").write_bytes(GOOD_PATCH)
        self.assert_rejected()

    def test_rejects_duplicate_series_entry(self) -> None:
        (self.patch_dir / "series").write_bytes(b"0001.patch\n0001.patch\n")
        self.assert_rejected()

    def test_rejects_missing_patch(self) -> None:
        (self.patch_dir / "series").write_bytes(b"missing.patch\n")
        self.assert_rejected()

    def test_rejects_crlf_series(self) -> None:
        (self.patch_dir / "series").write_bytes(b"0001.patch\r\n")
        self.assert_rejected()

    def test_rejects_crlf_patch(self) -> None:
        (self.patch_dir / "0001.patch").write_bytes(GOOD_PATCH.replace(b"\n", b"\r\n"))
        self.assert_rejected()

    def test_rejects_manifest_tag_sha_mismatch(self) -> None:
        self.write_manifest("0" * 40)
        self.assert_rejected()

    def test_rejects_patch_that_does_not_apply(self) -> None:
        bad = GOOD_PATCH.replace(b"-base\n", b"-different\n")
        (self.patch_dir / "0001.patch").write_bytes(bad)
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
