# Netgen native SDK workflows

This directory contains the CI used to build, qualify, and publish the FEATool
Netgen native SDKs. The workflows intentionally pin the Netgen upstream
baseline, OCCT inputs, zlib input, producer toolchains, and artifact names so a
published SDK can be traced back to exact source and dependency revisions.

The current release line is based on Netgen `v6.2.2608` with OCCT `8.0.1`.
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

## Current dependency line: Netgen v6.2.2608 + OCCT 8.0.1

Netgen baseline:

```text
tag:    v6.2.2608
commit: 96e5682f6ea43ba77ba3bb2ae4bb4bd1791f506e
```

OCCT source revision used by the Linux/macOS SDK release:

```text
release: occt-sdk-8.0.1
commit:  b8f597c677811d1f9f4d8a97f5ae2825c0353a42
```

Pinned OCCT inputs:

| Platform | OCCT input | SHA-256 |
| --- | --- | --- |
| Windows | Open-Cascade-SAS `V8.0.1` `occt-combined-release-no-pch.zip` | `afe36b6abcc7964d0f8b0404ccb16e7c1f6ddd8e43b450c865f7e7f092440e9d` |
| Linux x86_64 | `opencascade-8.0.1-linux-x86_64-glibc2.17-shared-b8f597c67781.tar.gz` | `d68d32c088c5c0cceac7600182d55cf896df7be0ff8a19c79eddfff456ef44e4` |
| macOS arm64 | `opencascade-8.0.1-macos13-arm64-shared-b8f597c67781.tar.gz` | `042347367185726ad16124f465c0654aef4455b247127834e4011e70ed548e1d` |
| macOS x86_64 | `opencascade-8.0.1-macos13-x86_64-shared-b8f597c67781.tar.gz` | `b7c00fea5c7d3a1ff64b367e7d7780f323e00044748c9b57dfe400a206c653ab` |

The Windows `8.0.1` asset is an outer archive. It contains
`opencascade-8.0.1-vc14-64-combined.zip`, which the Windows workflow explicitly
extracts before locating `OpenCASCADEConfig.cmake`, `inc`, `win64/vc14`, and
`3rdparty-vc14-64`.

The Linux and macOS OCCT archives come from the immutable
`precise-simulation/OCCT` `occt-sdk-8.0.1` release. The workflows first verify
the release metadata, asset size, digest, and URL. macOS prefers the authenticated
GitHub asset API and falls back to the already-verified public asset URL if the
asset API returns an access error; the downloaded bytes must still match the
pinned SHA-256.

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
2. Windows changed from a directly consumable OCCT combined ZIP to the nested
   `8.0.1` Release/no-PCH wrapper described above.
3. Linux/macOS changed to the `occt-sdk-8.0.1` assets and source commit.
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

The Windows SDK is built with Visual Studio 2022, x64, Release, and `/MD`. The
workflow:

1. verifies and normalizes the pinned OCCT archive;
2. builds a pinned zlib;
3. configures/builds Netgen with native SDK settings;
4. runs focused refinement and Catch tests;
5. installs and constructs the compact SDK;
6. audits DLL dependencies and producer metadata;
7. builds/runs an external native OCC consumer;
8. archives, re-extracts, relocates, and re-runs the consumer;
9. uploads the archive and SHA-256 sidecar.

### Linux

The Linux producer runs in the pinned `manylinux2014_x86_64` image. The SDK is a
shared x86_64 build with glibc 2.17 / GCC 10 compatibility. The build script
checks symbol-version ceilings, RPATH/RUNPATH relocatability, disabled runtime
dependencies, CMake metadata, and an external native OCC consumer before and
after archive relocation.

The uploaded SDK is then consumed independently on Ubuntu 20.04, 22.04, and
24.04. Ubuntu 20.04 intentionally installs GCC/G++ 10 because OCCT 8.0.1 and the
SDK are qualified against a GCC 10 baseline rather than Ubuntu 20.04's default
GCC 9.

### macOS

The matrix produces separate arm64 and x86_64 archives with Xcode 16.4 and a
macOS 13 deployment target. Each architecture uses its matching OCCT SDK, then
builds, packages, relocates, and qualifies the native consumer before uploading
the archive and checksum sidecar.

## Artifact names

Artifact filenames include the upstream Netgen baseline, the first 12 characters
of the fork source SHA, and the OCCT version. For the current line:

```text
netgen-featool-v6.2.2608-<sha12>-occt8.0.1-win64-msvc.zip
netgen-featool-v6.2.2608-<sha12>-occt8.0.1-linux-x86_64-glibc2.17-gcc10.tar.gz
netgen-featool-v6.2.2608-<sha12>-occt8.0.1-macos13-x86_64-clang.tar.gz
netgen-featool-v6.2.2608-<sha12>-occt8.0.1-macos13-arm64-clang.tar.gz
```

Every archive has a sibling `.sha256` file. Each SDK also contains
`producer-info.json`, which records the full source SHA, Netgen baseline,
toolchain/producer identity, OCCT provenance, and dependency hashes.

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
   revision.
5. Push the tag to `origin`.
6. `release-netgen-sdk.yml` calls all three platform workflows again with
   `bundle_release=true`. Each platform verifies the tag format, that the tag SHA
   is contained in `origin/netgen-featool`, and that the same SHA has a successful
   branch qualification run.
7. The release job requires exactly four archives plus four checksum sidecars,
   verifies every checksum and `producer-info.json`, creates a draft release,
   verifies the uploaded GitHub asset digests, and then changes the release to
   `draft=false`.

**A matching `netgen-sdk-*` tag therefore publishes the GitHub release
automatically. It is not a draft-only trigger.**

The Windows workflow also retains the older `netgen-featool-sdk-*` tag trigger,
but combined cross-platform releases should use `netgen-sdk-*` and the release
workflow above.

## Updating Netgen or OCCT again

When moving to a new Netgen baseline or OCCT version, update the complete set of
pins rather than only changing artifact filenames:

- `BASELINE_TAG` / `BASELINE_SHA` in all three platform workflows;
- `NETGEN_BASELINE_TAG` / `NETGEN_BASELINE_SHA` in the release workflow;
- Windows OCCT URL, SHA-256, archive extraction/normalization assumptions, and
  producer metadata;
- Linux OCCT asset name, size, SHA-256, URL, source commit, and build-script
  producer metadata;
- both macOS OCCT asset names, sizes, SHA-256s, release tag/source commit, and
  build-script producer metadata;
- expected artifact names in every platform workflow and the release workflow;
- `cmake/SuperBuild.cmake` if Netgen's source-built OCCT version also changes;
- this README's current/historical dependency table.

After any dependency migration, qualify the real dependency packages on all
platforms and run the external native consumer. A successful compile alone is
not sufficient evidence for a distributable SDK.
