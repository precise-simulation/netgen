#!/usr/bin/env python3
"""Find an accepted exact-SHA producer qualification without local fork history."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def github_json(repository: str, endpoint: str, token: str) -> Any:
    url = f"https://api.github.com/repos/{repository}/{endpoint}"
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "thin-netgen-release-qualification",
        },
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def branch_contains(compare: dict[str, Any], producer_sha: str) -> bool:
    base = compare.get("base_commit", {})
    return (
        str(base.get("sha", "")).lower() == producer_sha.lower()
        and compare.get("status") in {"ahead", "identical"}
    )


def accepted_runs(runs: dict[str, Any], producer_sha: str, branch: str) -> list[dict[str, Any]]:
    accepted: list[dict[str, Any]] = []
    for run in runs.get("workflow_runs", []):
        if str(run.get("head_sha", "")).lower() != producer_sha.lower():
            continue
        if run.get("conclusion") != "success":
            continue
        event = run.get("event")
        if event == "workflow_dispatch" or (event == "push" and run.get("head_branch") == branch):
            accepted.append(run)
    return sorted(accepted, key=lambda item: int(item.get("run_number", 0)), reverse=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--workflow", required=True)
    parser.add_argument("--producer-sha", required=True)
    parser.add_argument("--branch", default="netgen-featool")
    parser.add_argument("--runs-json", type=Path)
    parser.add_argument("--compare-json", type=Path)
    args = parser.parse_args()

    sha = args.producer_sha.lower()
    if len(sha) != 40 or any(ch not in "0123456789abcdef" for ch in sha):
        print("producer SHA must be 40 hexadecimal characters", file=sys.stderr)
        return 1

    if bool(args.runs_json) != bool(args.compare_json):
        print("runs and compare fixtures must be supplied together", file=sys.stderr)
        return 1

    try:
        if args.runs_json:
            runs = load_json(args.runs_json)
            compare = load_json(args.compare_json)
        else:
            token = os.environ.get("GH_TOKEN", "")
            if not token:
                raise RuntimeError("GH_TOKEN is required")
            compare_base = urllib.parse.quote(sha, safe="")
            compare_head = urllib.parse.quote(args.branch, safe="")
            compare = github_json(args.repository, f"compare/{compare_base}...{compare_head}", token)
            query = urllib.parse.urlencode(
                {"status": "completed", "head_sha": sha, "per_page": 100}
            )
            workflow = urllib.parse.quote(args.workflow, safe="")
            runs = github_json(
                args.repository,
                f"actions/workflows/{workflow}/runs?{query}",
                token,
            )
    except Exception as exc:
        print(f"release qualification lookup failed: {exc}", file=sys.stderr)
        return 1

    if not branch_contains(compare, sha):
        print(f"producer commit {sha} is not contained in {args.branch}", file=sys.stderr)
        return 1

    qualified = accepted_runs(runs, sha, args.branch)
    if not qualified:
        print(f"no accepted successful qualification exists for exact commit {sha}", file=sys.stderr)
        return 1
    print(qualified[0]["id"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
