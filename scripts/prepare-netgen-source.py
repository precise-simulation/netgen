#!/usr/bin/env python3
"""Materialize the pinned upstream Netgen source and apply the ordered patch set."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

from netgen_source import SourceError, expected_source_provenance, load_manifest, load_patch_series, run_git


def prepare(repo_root: Path, destination: Path, provenance_path: Path, upstream_override: str | None) -> None:
    manifest = load_manifest(repo_root)
    patches = load_patch_series(repo_root)

    if destination.exists():
        raise SourceError(f"destination already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    provenance_path.parent.mkdir(parents=True, exist_ok=True)

    upstream_repository = manifest["repository"]
    if upstream_override is not None:
        if os.environ.get("NETGEN_SOURCE_TESTING") != "1":
            raise SourceError("test upstream override is disabled")
        upstream_repository = upstream_override

    try:
        run_git(["init", "--quiet", str(destination)])
        run_git(["remote", "add", "origin", upstream_repository], cwd=destination)
        run_git(
            [
                "-c",
                "protocol.version=2",
                "fetch",
                "--quiet",
                "--depth=1",
                "--no-tags",
                "origin",
                f"refs/tags/{manifest['tag']}:refs/tags/{manifest['tag']}",
            ],
            cwd=destination,
        )
        resolved = run_git(["rev-parse", f"refs/tags/{manifest['tag']}^{{commit}}"], cwd=destination).lower()
        if resolved != manifest["commit"]:
            raise SourceError(
                f"upstream tag {manifest['tag']} resolved to {resolved}, expected {manifest['commit']}"
            )
        run_git(["checkout", "--quiet", "--detach", manifest["commit"]], cwd=destination)

        for patch in patches:
            patch_path = str(patch["absolute_path"].resolve())
            run_git(["apply", "--check", patch_path], cwd=destination)
            run_git(["apply", patch_path], cwd=destination)
        run_git(["diff", "--check"], cwd=destination)
    except Exception:
        if destination.exists():
            shutil.rmtree(destination, ignore_errors=True)
        raise

    provenance = expected_source_provenance(repo_root)
    provenance_path.write_bytes((json.dumps(provenance, indent=2, sort_keys=True) + "\n").encode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="thin producer repository root",
    )
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--provenance", type=Path, required=True)
    parser.add_argument("--test-upstream-repository", help=argparse.SUPPRESS)
    args = parser.parse_args()

    try:
        prepare(
            args.repo_root.resolve(),
            args.destination.resolve(),
            args.provenance.resolve(),
            args.test_upstream_repository,
        )
    except SourceError as exc:
        print(f"prepare-netgen-source: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
