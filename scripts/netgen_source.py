#!/usr/bin/env python3
"""Shared validation for the thin Netgen source manifest and patch series."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any


CANONICAL_REPOSITORY = "https://github.com/NGSolve/netgen.git"
_TAG_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
_SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")
_PATCH_RE = re.compile(r"^[A-Za-z0-9._-]+\.patch$")


class SourceError(RuntimeError):
    pass


def _read_lf_bytes(path: Path, label: str) -> bytes:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise SourceError(f"cannot read {label}: {path}") from exc
    if b"\r" in data:
        raise SourceError(f"{label} must use LF line endings: {path}")
    return data


def load_manifest(repo_root: Path) -> dict[str, str]:
    path = repo_root / "upstream" / "netgen.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SourceError(f"invalid upstream manifest: {path}") from exc
    if not isinstance(data, dict) or set(data) != {"repository", "tag", "commit"}:
        raise SourceError("upstream/netgen.json must contain only repository, tag, and commit")
    if data["repository"] != CANONICAL_REPOSITORY:
        raise SourceError(f"unexpected upstream repository: {data['repository']!r}")
    if not isinstance(data["tag"], str) or not _TAG_RE.fullmatch(data["tag"]):
        raise SourceError(f"invalid upstream tag: {data['tag']!r}")
    if not isinstance(data["commit"], str) or not _SHA_RE.fullmatch(data["commit"]):
        raise SourceError(f"invalid upstream commit: {data['commit']!r}")
    return {
        "repository": data["repository"],
        "tag": data["tag"],
        "commit": data["commit"].lower(),
    }


def load_patch_series(repo_root: Path) -> list[dict[str, Any]]:
    patch_dir = repo_root / "patches" / "netgen"
    series_path = patch_dir / "series"
    series_bytes = _read_lf_bytes(series_path, "patch series")
    try:
        text = series_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise SourceError("patch series must be UTF-8") from exc

    names: list[str] = []
    for raw_line in text.split("\n"):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if not _PATCH_RE.fullmatch(line) or Path(line).name != line:
            raise SourceError(f"invalid patch series entry: {line!r}")
        if line in names:
            raise SourceError(f"duplicate patch series entry: {line}")
        names.append(line)

    listed = set(names)
    actual = {path.name for path in patch_dir.glob("*.patch") if path.is_file()}
    missing = [name for name in names if name not in actual]
    unlisted = sorted(actual - listed)
    if missing:
        raise SourceError(f"patch series references missing patch: {missing[0]}")
    if unlisted:
        raise SourceError(f"unlisted patch file: {unlisted[0]}")

    patches: list[dict[str, Any]] = []
    for name in names:
        path = patch_dir / name
        data = _read_lf_bytes(path, "patch")
        patches.append(
            {
                "name": name,
                "path": f"patches/netgen/{name}",
                "sha256": hashlib.sha256(data).hexdigest(),
                "absolute_path": path,
            }
        )
    return patches


def version_git(manifest: dict[str, str]) -> str:
    return f"{manifest['tag']}-0-g{manifest['commit'][:12]}"


def semantic_version(manifest: dict[str, str]) -> str:
    return manifest["tag"][1:]


def expected_source_provenance(repo_root: Path) -> dict[str, Any]:
    manifest = load_manifest(repo_root)
    patches = load_patch_series(repo_root)
    return {
        "upstream": {
            **manifest,
            "version_git": version_git(manifest),
            "version": semantic_version(manifest),
        },
        "patches": [
            {"path": patch["path"], "sha256": patch["sha256"]}
            for patch in patches
        ],
    }


def run_git(args: list[str], cwd: Path | None = None) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise SourceError(f"git {' '.join(args)} failed: {detail}")
    return result.stdout.strip()
