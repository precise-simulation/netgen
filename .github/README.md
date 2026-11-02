# Netgen native SDK workflows

This directory contains the CI used to build, qualify, and publish the FEATool
Netgen native SDKs. The workflows intentionally pin the Netgen upstream
baseline, the immutable OCCT SDK release, zlib input, and producer toolchains so
a published SDK can be traced back to exact source and dependency revisions.

The current release line is based on Netgen `v6.2.2608` and the lean OCCT SDK
selected by `.github/occt-sdk-release.txt`.
The reference published bundle for this line is
`netgen-sdk-1254bcb88ebd-r1`, built from
`1254bcb88ebd98ea1ce40706f82d9f22d18e3cef` by release workflow run
`41376331026`. GitHub release assets are the canonical distributable SDKs;
Actions artifacts are qualification/staging outputs.

Earlier SDK releases used Netgen `v6.2.2604` with OCCT `7.9.3`; the historical
values are recorded below because future dependency upgrades should follow the
same migration pattern rather than changing only one workflow.

## Workflow map

| Workflow | Purpose | Normal trigger |
| --- | --- | --- |
| `workflows/windows-netgen-sdk.yml` | Build and qualify the Windows x64 MSVC SDK | push to `netgen-featool`, manual dispatch, reusable workflow call |
| `workflows/linux-netgen-sdk.yml` | Build and qualify the Linux x86_64 SDK and external consumers | push to `netgen-featool`, manual dispatch, reusable workflow call |
| `workflows/macos-netgen-sdk.yml` | Build and qualify thin arm64 and x86_64 macOS SDKs | push to `netgen-featool`, manual dispatch, reusable workflow call |
| `workflows/release-netgen-sdk.yml` | Rebuild all platforms, verify the exact release inventory, and publish one combined GitHub release | `netgen-sdk-*` tag or manual dispatch |

The platform workflows are qualification workflows first. A normal branch push
must succeed before a release tag is created. During a tagged release the
combined workflow calls the same platform workflows with `bundle_release=true`;
those jobs verify that the tagged SHA already has a successful branch
qualification run.

## Current dependency line

Netgen baseline:

```text
tag:    v6.2.2608
commit: 96e5682f6ea43ba77ba3bb2ae4bb4bd1791f506e
```

OCCT is pinned by release tag only:

```text
.github/occt-sdk-release.txt
```

`.github/resolve-occt-release.py` resolves the matching Windows, Linux, or macOS
shared/static asset from that exact GitHub release. The resolver requires the
release to be immutable and uses GitHub's published asset ID, name, size, URL,
and SHA-256 digest. The workflows download that exact asset through GitHub's
authenticated asset API, then verify the downloaded bytes and the SDK's
embedded manifest; the full OCCT source SHA comes from that manifest and is
recorded in Netgen's `producer-info.json`. Asset filenames, byte sizes, hashes,
URLs, and the OCCT source SHA are therefore not duplicated as Netgen pins.

Netgen's `BUILD_OCC=ON` superbuild separately pins the upstream OCCT source
archive `V8_0_1.zip` with MD5 `5b0b171d7028cf73bd9369997091347a`.

## Historical dependency line: Netgen v6.2.2604 + OCCT 7.9.3

The previous SDK release line used:

```text
Netgen tag:    v6.2.2604
Netgen commit: 3ee489c7d58fdbc2a6708cca3cbaefaae506dc17
OCCT release:  occt-sdk-7.9.3
OCCT commit:   a016080bf6738d6aeae020badee4e888ad1540a5
```

Historical OCCT inputs:

| Platform | OCCT input | SHA-256 |
| --- | --- | --- |
| Windows | Open-Cascade-SAS `V7_9_3` `opencascade-7.9.3-vc14-64-combined.zip` | `afbef3457fbc4a2bdca0608e0fe284392f51e4c2c42ccbfb9df7168d8e4eb9b3` |
| Linux x86_64 | `opencascade-7.9.3-linux-x86_64-glibc2.17-shared-a016080bf673.tar.gz` | `a98315bfe2198dc08572a9fa792240d913ed08d08a50a53b643595d4a8eddb0d` |
| macOS arm64 | `opencascade-7.9.3-macos13-arm64-shared-a016080bf673.tar.gz` | `aea81a9f2c15e83ee9ce96229610b03bd8e6d8b420e6f283475a65e92463bed7` |
| macOS x86_64 | `opencascade-7.9.3-macos13-x86_64-shared-a016080bf673.tar.gz` | `8c6f81794a0a50429e1fd120650e74fa0c658aeb4d8a742ec41234b3d2dfd081` |

The main migration differences from `7.9.3` to `8.0.1` were:

1. Netgen moved from upstream `v6.2.2604` to `v6.2.2608`, which already contains
   the upstream OCCT 8 compatibility work, including the `python_occ_shapes.cpp`
   integer-size fix.
2. Windows shared and static consume the project-built lean vc143 /MD SDKs from
   the same immutable release.
3. Linux/macOS consume the `occt-sdk-8.0.1-r3` assets from the same source
   commit.
4. Upstream `v6.2.2608` appends an absolute OCCT library path for ordinary
   installs; `NETGEN_NATIVE_SDK=ON` suppresses that fallback so the packaged SDK
   remains relocatable.
5. The Linux SDK remains a GCC 10 / glibc 2.17 baseline. Ubuntu 20.04 consumer
   qualification therefore explicitly uses `gcc-10`/`g++-10`; Ubuntu 22.04 and
   24.04 use their default compilers.

## What each platform workflow verifies

All platform workflows verify the exact producer commit and the pinned Netgen
baseline before building. They also retain the `tri2quad` regression coverage
used by this fork.

### Windows

The Windows shared and static SDKs are built with Visual Studio 2022, x64,
Release, and `/MD`. Both variants consume the matching project-built lean vc143
`/MD` SDK from the selected immutable OCCT release. Netgen qualification does
not rebuild OCCT from source. The workflow:

1. verifies and extracts the matching pinned shared or static OCCT archive;
2. builds a pinned zlib;
3. configures/builds Netgen with matching shared or static native SDK settings;
4. runs focused refinement and Catch tests;
5. installs and constructs the compact SDK;
6. audits DLL dependencies and producer metadata;
7. builds/runs an external native OCC consumer;
8. archives, re-extracts, relocates, and re-runs the consumer;
9. uploads the archive and SHA-256 sidecar.

### Linux

The Linux producer runs in the pinned `manylinux2014_x86_64` image. It builds
shared and static x86_64 SDKs with glibc 2.17 / GCC 10 compatibility, using the
matching shared or static OCCT SDK. The build script checks the linkage-specific
library shape, CMake metadata, and an external native OCC consumer before and
after archive relocation. The shared package additionally checks symbol-version
ceilings, RPATH/RUNPATH relocatability, and disabled runtime dependencies; the
static package contains the pinned `libz.a` needed by its exported target.

The uploaded SDK is then consumed independently on Ubuntu 20.04, 22.04, and
24.04. Ubuntu 20.04 intentionally installs GCC/G++ 10 because OCCT 8.0.1 and the
SDK are qualified against a GCC 10 baseline rather than Ubuntu 20.04's default
GCC 9.

### macOS

The matrix produces arm64 and x86_64 shared and static archives with Xcode 16.4
and a macOS 13 deployment target. Each variant uses the matching OCCT SDK, then
builds, packages, relocates, and qualifies the native consumer before uploading
the archive and checksum sidecar. Static packages include the pinned `libz.a`.

## Artifact names

Artifact filenames include the upstream Netgen baseline, the first 12 characters
of the fork source SHA, and the OCCT version resolved from the selected release:

```text
netgen-featool-v6.2.2608-<sha12>-occt<occt-version>-win64-msvc.zip
netgen-featool-v6.2.2608-<sha12>-occt<occt-version>-win64-msvc-static.zip
netgen-featool-v6.2.2608-<sha12>-occt<occt-version>-linux-x86_64-glibc2.17-gcc10.tar.gz
netgen-featool-v6.2.2608-<sha12>-occt<occt-version>-linux-x86_64-glibc2.17-gcc10-static.tar.gz
netgen-featool-v6.2.2608-<sha12>-occt<occt-version>-macos13-x86_64-clang.tar.gz
netgen-featool-v6.2.2608-<sha12>-occt<occt-version>-macos13-x86_64-clang-static.tar.gz
netgen-featool-v6.2.2608-<sha12>-occt<occt-version>-macos13-arm64-clang.tar.gz
netgen-featool-v6.2.2608-<sha12>-occt<occt-version>-macos13-arm64-clang-static.tar.gz
```

Every archive has a sibling `.sha256` file. Each SDK also contains
`producer-info.json`, which records the full source SHA, Netgen baseline,
toolchain/producer identity, OCCT provenance, and dependency hashes.

## Actions artifact retention and cleanup

GitHub release assets are the long-lived distribution record. Actions artifacts
exist only to move qualified SDKs between workflow jobs and to aid short-term
debugging.

After a combined release has been published and independently verified:

- keep the published GitHub release, its tag, archives, checksum sidecars, and
  workflow-run history;
- it is safe to delete older or superseded Actions artifacts, including
  artifacts from failed/intermediate qualification heads;
- keeping the latest successful branch-qualification artifacts and the latest
  release-run artifacts for a short post-release window is useful but not
  required for reproducibility, because the release assets contain the final
  archives and `producer-info.json`;
- routine artifact cleanup must not delete or replace published release assets
  or move an existing release tag.

The platform workflows currently retain Actions artifacts for 30 days, so
periodic cleanup is optional storage hygiene rather than part of release
correctness.

## Normal qualification and release procedure

1. Make and commit the source/workflow changes on `netgen-featool`.
2. Push `netgen-featool` to `origin`. This automatically starts Windows, Linux,
   and macOS qualification for that exact SHA.
3. Do not create a release tag until all three platform workflows succeed on the
   same SHA.
4. Form the release tag as:

   ```text
   netgen-sdk-<first-12-hex-of-source-sha>-rN
   ```

   `r1` is the first SDK release for that source revision; increment `N` only
   when republishing the same source revision with a new SDK packaging/release
   revision. Treat a pushed `netgen-sdk-*` tag as immutable: if another release
   attempt is needed for the same source revision, use the next `rN` instead of
   moving or reusing the existing tag.
5. Push the tag to `origin`.
6. `release-netgen-sdk.yml` calls all three platform workflows again with
   `bundle_release=true`. Each platform verifies the tag format, that the tag SHA
   is contained in `origin/netgen-featool`, and that the same SHA has a successful
   branch qualification run.
7. The release job requires exactly eight archives plus eight checksum sidecars,
   verifies every checksum and `producer-info.json`, creates a draft release,
   verifies the uploaded GitHub asset digests, and then changes the release to
   `draft=false`.

**A matching `netgen-sdk-*` tag therefore publishes the GitHub release
automatically. It is not a draft-only trigger.**


## Merging a new upstream Netgen release

The SDK baseline must come from an exact NGSolve Netgen release tag. The
`netgen-featool` branch is a long-lived fork, so retain the upstream release as a
real merge parent instead of rebasing or replaying the release as individual
commits. The `v6.2.2608` migration is the reference shape: merge commit
`9ec924e2` has fork commit `5300263c` as its first parent and exact upstream
`v6.2.2608` commit `96e5682f` as its second parent.

Use a clean integration checkout. Configure the canonical upstream remote once,
then fetch the fork and upstream refs:

```text
git remote add upstream https://github.com/NGSolve/netgen.git
git fetch origin --prune
git fetch upstream --tags --prune
```

If `upstream` already exists, verify its URL with `git remote -v` instead of
adding it again. Do not rely on `origin/master` or the fork's local tag set being
current when selecting a newly published NGSolve release.

Before changing the fork, record and inspect the release boundary:

```text
git rev-parse "<current-baseline-tag>^{commit}"
git rev-parse "<new-baseline-tag>^{commit}"
git merge-base --is-ancestor <new-baseline-tag> upstream/master
git log --oneline <current-baseline-tag>..<new-baseline-tag>
git diff --stat <current-baseline-tag>..<new-baseline-tag>
git diff --name-status <current-baseline-tag>..origin/netgen-featool
```

The last command records the current fork-owned tree delta that must be accounted
for during the port. At minimum, check the FEATool triangle-to-quad refinement
implementation and `tests/catch/refinement.cpp`, together with the
`NETGEN_NATIVE_SDK` CMake/install path and native SDK consumer/workflow files.

Update the local fork branch and merge the exact release tag:

```text
git switch netgen-featool
git pull --ff-only origin netgen-featool
git merge --no-ff <new-baseline-tag> -m "Merge upstream <new-baseline-tag> baseline"
```

Resolve conflicts by adapting the fork changes to the upstream APIs now present in
the release. Do not choose an entire conflicted file from one side. The
`v6.2.2608` merge, for example, had to preserve `tri2quad` while converting it
to upstream's newer indexed arrays, point-index helpers, surface-element access,
and sorting types.

Before pushing, verify the merge and re-audit the resulting fork delta:

```text
git merge-base --is-ancestor <new-baseline-tag> HEAD
git show -s --format="%H %P %s" HEAD
git diff --check <new-baseline-tag>..HEAD
git diff --name-status <new-baseline-tag>..HEAD
```

Immediately after the merge, the second parent shown by `git show` must be the
commit resolved by `<new-baseline-tag>`. If baseline/dependency updates are made
as follow-up commits, record the merge commit first and perform the parent check on
that commit.

Complete the version/dependency migration below before pushing the branch. This is
important because an SDK qualification run builds the current source tree while
also publishing baseline information in artifact names and `producer-info.json`.
Do not push an intermediate merge-only revision that still identifies the previous
baseline. Push the coherent branch head once the merge, pin changes, metadata, and
focused regression updates all agree.

The first focused behavioral check after an upstream port is the refinement
regression (`unit_refinement` / `test_refinement`), because the fork's
triangle-to-quad implementation has historically conflicted with upstream
refinement changes. Also run focused checks for every upstream change that touches
the native SDK build or exported interface. The pushed coherent head must then pass
the Windows, Linux, and macOS qualification workflows before any
`netgen-sdk-*` tag is created.

## Updating Netgen or OCCT again

A new Netgen upstream release does **not** automatically require a new OCCT
release. Keep the currently qualified OCCT SDK line when it remains compatible;
change the OCCT release only when the new Netgen baseline requires a different
OCCT API/build contract or when an OCCT upgrade is an explicit goal.
Even for a Netgen-only bump, inspect upstream changes to
`CMakeLists.txt`, `cmake/SuperBuild.cmake`, `libsrc/occ/`, and
`python/` for dependency or exported-interface changes.

For an OCCT-only SDK update that keeps the qualified platform contract (Windows
VC143 `/MD`, Linux x86_64/glibc 2.17, and macOS 13 native architectures), change
exactly one Netgen pin:

```text
.github/occt-sdk-release.txt
```

Set it to the already-published immutable lean `occt-sdk-*` release. The
platform workflows resolve its assets and provenance automatically. Push the
coherent change and require Windows, Linux, and macOS qualification before
creating a Netgen SDK release tag.

When moving to a new Netgen upstream baseline, the Netgen baseline metadata still
requires the normal source-port updates:

- `BASELINE_TAG` / `BASELINE_SHA` in all three platform workflows;
- shared and static artifact names in `windows-netgen-sdk.yml`;
- `NETGEN_BASELINE_TAG` / `NETGEN_BASELINE_SHA`, all expected archive names,
  and the release title in `release-netgen-sdk.yml`;
- the SDK-name version and `upstream` producer metadata in
  `linux-netgen-sdk/build-sdk.sh`;
- the SDK-name version and `upstream` producer metadata in
  `macos-netgen-sdk/build-sdk.sh`;
- `cmake/SuperBuild.cmake` if upstream's source-built OCCT pin or integration
  changed;
- this README's historical/reference material when the Netgen baseline itself changes.

Before pushing the coherent migration head, perform a stale-pin sweep for the
old baseline tag, full SHA, and version string, for example:

```text
git grep -n -E '<old-tag>|<old-full-sha>|<old-version>' -- .github cmake CMakeLists.txt
```

Any remaining match must be intentionally historical documentation. Also review
the upstream release delta in the areas most likely to affect this fork:

```text
git diff <current-baseline-tag>..<new-baseline-tag> -- CMakeLists.txt cmake libsrc/occ python tests/catch/refinement.cpp
```

After any dependency migration, qualify the real dependency packages on all
platforms and run the external native consumer. A successful compile alone is
not sufficient evidence for a distributable SDK.
