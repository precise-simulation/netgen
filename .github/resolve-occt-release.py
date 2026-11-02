#!/usr/bin/env python3
import argparse
import json
import os
import re
import urllib.request
from pathlib import Path


RELEASE_FILE = Path(__file__).with_name("occt-sdk-release.txt")


def release_tag_and_version():
    tag = RELEASE_FILE.read_text(encoding="utf-8").strip()
    match = re.fullmatch(r"occt-sdk-(\d+\.\d+\.\d+)(?:-r\d+)?", tag)
    if not match:
        raise SystemExit(f"invalid OCCT SDK release tag in {RELEASE_FILE}: {tag!r}")
    return tag, match.group(1)


def asset_pattern(platform, architecture, linkage, version):
    version = re.escape(version)
    sha = r"(?P<source_prefix>[0-9a-fA-F]{12})"
    if platform == "windows":
        return re.compile(
            rf"^opencascade-{version}-windows-x86_64-vc143-{linkage}-lean-{sha}\.zip$"
        )
    if platform == "linux":
        return re.compile(
            rf"^opencascade-{version}-linux-x86_64-glibc2\.17-{linkage}-{sha}\.tar\.gz$"
        )
    return re.compile(
        rf"^opencascade-{version}-macos13-{re.escape(architecture)}-{linkage}-{sha}\.tar\.gz$"
    )


def github_release(tag):
    request = urllib.request.Request(
        f"https://api.github.com/repos/precise-simulation/OCCT/releases/tags/{tag}",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "precise-simulation-netgen-sdk",
        },
    )
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def append_env(values):
    env_path = os.environ.get("GITHUB_ENV")
    if not env_path:
        raise SystemExit("GITHUB_ENV is not set")
    with open(env_path, "a", encoding="utf-8") as stream:
        for key, value in values.items():
            stream.write(f"{key}={value}\n")


def append_output(values):
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        raise SystemExit("GITHUB_OUTPUT is not set")
    with open(output_path, "a", encoding="utf-8") as stream:
        for key, value in values.items():
            stream.write(f"{key.lower()}={value}\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("windows", "linux", "macos"), required=True)
    parser.add_argument("--architecture", choices=("x86_64", "arm64"), default="x86_64")
    parser.add_argument("--linkage", choices=("shared", "static"), required=True)
    parser.add_argument("--github-env", action="store_true")
    parser.add_argument("--github-output", action="store_true")
    args = parser.parse_args()

    if args.platform != "macos" and args.architecture != "x86_64":
        raise SystemExit(f"{args.platform} only supports x86_64 OCCT SDKs")

    tag, version = release_tag_and_version()
    release = github_release(tag)
    if release.get("tag_name") != tag:
        raise SystemExit(f"OCCT release tag mismatch: {release.get('tag_name')!r}")
    if release.get("draft"):
        raise SystemExit(f"OCCT release {tag} is still a draft")
    if not release.get("immutable"):
        raise SystemExit(f"OCCT release {tag} is not immutable")

    pattern = asset_pattern(args.platform, args.architecture, args.linkage, version)
    matches = []
    for asset in release.get("assets", []):
        match = pattern.fullmatch(asset.get("name", ""))
        if match:
            matches.append((asset, match.group("source_prefix").lower()))
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one {args.platform}/{args.architecture}/{args.linkage} "
            f"OCCT asset in {tag}, found {len(matches)}"
        )

    asset, source_prefix = matches[0]
    digest = asset.get("digest") or ""
    if not digest.startswith("sha256:") or len(digest) != len("sha256:") + 64:
        raise SystemExit(f"OCCT asset {asset['name']} has no usable SHA-256 digest")
    if not isinstance(asset.get("size"), int) or asset["size"] <= 0:
        raise SystemExit(f"OCCT asset {asset['name']} has no usable size")
    if not isinstance(asset.get("id"), int) or asset["id"] <= 0:
        raise SystemExit(f"OCCT asset {asset['name']} has no usable asset id")

    resolved = {
        "OCCT_RELEASE": tag,
        "OCCT_VERSION": version,
        "OCCT_ASSET_ID": str(asset["id"]),
        "OCCT_ASSET": asset["name"],
        "OCCT_ASSET_SIZE": str(asset["size"]),
        "OCCT_SHA256": digest.removeprefix("sha256:").lower(),
        "OCCT_URL": asset["browser_download_url"],
        "OCCT_SOURCE_PREFIX": source_prefix,
    }
    if args.github_env:
        append_env(resolved)
    if args.github_output:
        append_output(resolved)
    print(json.dumps(resolved, sort_keys=True))


if __name__ == "__main__":
    main()
