---
kind: plan
title: Build and publish the Windows Netgen SDK on GitHub Actions
summary: Build and publish a relocatable VS2022 x64 Netgen SDK on GitHub-hosted Windows runners against pinned OCCT 7.9.3 and zlib inputs.
area: windows-build
priority: P2
depends_on: []
children: []
affected_files:
  - .github/workflows/windows-netgen-sdk.yml
  - CMakeLists.txt
  - nglib/CMakeLists.txt
  - cmake/NetgenNativeConfig.cmake.in
  - tests/windows-native-sdk/*
---
# Build and publish the Windows Netgen SDK on GitHub Actions

## Goal and scope

Add a GitHub Actions producer for the `precise-simulation/netgen`
`netgen-featool` branch that builds, qualifies, packages, and optionally publishes
a native Windows Netgen SDK. All compilation and runtime qualification in this
plan happens on GitHub-hosted Windows runners; no local Windows build is part of
the implementation or acceptance path.

The produced SDK must contain the native shared `ngcore`/`nglib` consumer surface
and be usable with the exact official OCCT 7.9.3 binary release pinned below.

This plan does not build OCCT, produce a Python wheel, or add GUI/Tcl/Tk support.
The Netgen SDK does not bundle OCCT DLLs; runtime users must supply the same pinned
OCCT binary family. Downstream application integration and packaging are outside
this plan. No sibling checkout, external repository plan, or local folder outside
this repository is an input, dependency, or acceptance requirement.

The source baseline is upstream `v6.2.2604` at
`3ee489c7d58fdbc2a6708cca3cbaefaae506dc17` plus the retained full-quad patch
and its regression coverage in this Git repository. This repository is the sole
source and provenance authority for the Windows SDK producer.

Before the first release-tag publication:

1. retain only the required full-quad patch and regression coverage on top of the
   pinned upstream baseline, excluding unrelated historical changes and
   source-tree stripping;
2. commit and push that Git state to the `netgen-featool` branch and record its
   full Git SHA;
3. let the GitHub Actions branch-push qualification run the focused full-quad and
   baseline refinement source/behavior checks and the complete Windows SDK
   qualification on that exact Git commit; and
4. only after that branch-push run succeeds, create the release tag pointing to
   the same Git commit.

At planning time, the remote `netgen-featool` branch is
`f416530e7105c8ca053d23a0300fb7cfbc23a0f4`. It contains the retained full-quad
patch and regression coverage and has been committed and pushed. No GitHub
Actions producer workflow exists yet, so this commit has not received the
required branch-push source/behavior or Windows SDK qualification.

A publication run must prove that its exact full `GITHUB_SHA` already has a
successful `push` qualification run of this workflow for the `netgen-featool`
branch. The workflow must obtain that evidence from GitHub Actions metadata rather
than embedding the qualified SHA in the source commit. A later source commit is
eligible only after its own branch-push qualification succeeds. Release
qualification therefore remains attached to the exact Git commit that GitHub
Actions built and tested without requiring a commit to contain its own SHA.

## Producer contract

Use this exact native build profile:

| Setting | Required value |
| --- | --- |
| GitHub runner | `windows-2022` |
| Generator | `Visual Studio 17 2022` |
| Architecture | x64 |
| Configuration | Release |
| C/C++ runtime | `/MD`, enforced with `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL` |
| Netgen language level | C++17 |
| Netgen configure mode | `USE_SUPERBUILD=OFF` |
| Netgen shared libraries | `NGLIB_LIBRARY_TYPE=SHARED`, `NGCORE_LIBRARY_TYPE=SHARED` |
| OpenCascade | `USE_OCC=ON` |
| GUI | `USE_GUI=OFF` |
| Python | `USE_PYTHON=OFF` |
| MPI | `USE_MPI=OFF` |
| CGNS | `USE_CGNS=OFF` |
| JPEG/FFmpeg | `USE_JPEG=OFF`, `USE_MPEG=OFF` |
| STL geometry | `USE_STLGEOM=ON` |
| Native interface | `USE_INTERFACE=ON` |
| CSG geometry | `USE_CSG=ON` |
| 2-D geometry | `USE_GEOM2D=ON` |
| Native CPU specialization | `USE_NATIVE_ARCH=OFF` |
| OCCT | official 7.9.3 vc14-64 combined binary asset below |
| zlib | 1.3.1, static x64 Release `/MD`, exact source archive below |

Use `windows-2022` rather than `windows-latest`. The former is the stable
GitHub-hosted VS2022 image; `windows-latest` can move to a newer Windows/Visual
Studio family and is not part of this producer contract.

The OCCT `vc14` label does not require building Netgen with the old v140
toolset. Microsoft guarantees binary compatibility across the MSVC 14.x toolsets
from VS2015 onward when a same-or-newer linker consumes the inputs. The producer
therefore uses the runner's VS2022/v143 compiler and linker with the OCCT
VS2015-family import libraries, while keeping the shared `/MD` runtime model.
Record the actual VS2022/MSVC minor toolset in producer metadata, but do not make
that local minor revision part of the dependency configuration identity.

## Pinned dependencies

Download OCCT directly from the upstream V7_9_3 GitHub release:

```text
asset:
  https://github.com/Open-Cascade-SAS/OCCT/releases/download/V7_9_3/opencascade-7.9.3-vc14-64-combined.zip
sha256:
  afbef3457fbc4a2bdca0608e0fe284392f51e4c2c42ccbfb9df7168d8e4eb9b3
```

Verify the SHA-256 before extraction. Normalize the extracted combined package so
the selected OCCT root contains the upstream OCCT distribution directly, with
`cmake/OpenCASCADEConfig.cmake`, `inc`, `win64/vc14/{lib,bin}`, and the
`3rdparty-vc14-64` runtime tree beneath the same managed root. Configure Netgen
with the selected OCCT package directory explicitly and disable CMake package
registry fallback so another runner installation cannot win discovery.

Before using the package as a producer dependency, inspect the PE imports/runtime
metadata of the OCCT DLLs in Netgen's link/runtime closure, or equivalent package
evidence, and establish that the pinned vc14-64 binaries use the dynamic MSVC
CRT/UCRT family compatible with the producer's `/MD` contract. Record the observed
runtime family in producer evidence and reject evidence of a statically linked or
otherwise incompatible CRT model. MSVC 14.x toolset binary compatibility does not
replace this runtime-model check.

Use this exact zlib producer input:

```text
source:
  https://zlib.net/fossils/zlib-1.3.1.tar.gz
sha256:
  9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
build:
  Visual Studio 17 2022, x64, Release, static, /MD
```

Verify the archive before extraction. Configure zlib with
`CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL` and build only the
`zlibstatic` target. Stage `zlib.h`, the generated `zconf.h`, and
`zlibstatic.lib` into temporary runner-owned SDK state, then pass those paths to
Netgen through `ZLIB_INCLUDE_DIRS`, `ZLIB_LIBRARIES`, and
`ZLIB_LIBRARY_RELEASE`. Do not publish zlib in the Netgen SDK. Inspect the
static archive directives or equivalent build evidence to confirm the objects use
the DLL runtime and reject a `LIBCMT`/`/MT` build.

Cache only checksum-addressed downloaded dependency archives. Rebuild zlib and
Netgen for each producer run so a stale compiled cache cannot silently change the
qualified toolchain state.

## Relocatable native SDK install mode

The current general-purpose installed `NetgenConfig.cmake` records
`PROJECT_SOURCE_DIR` and absolute OCCT/zlib locations. The current
`nglib/CMakeLists.txt` also exports the `netgen_cgns` interface target even
when CGNS is disabled. Copying the ordinary install tree into a ZIP would
therefore fail this SDK's relocation and surface-area contract.

Add an opt-in `NETGEN_NATIVE_SDK` CMake mode, defaulting to `OFF`, so the
existing Netgen install/package API remains unchanged. When this mode is enabled
for the producer profile:

1. Reject incompatible producer settings at configure time: GUI, Python, MPI,
   CGNS, JPEG, MPEG, or native-architecture specialization enabled; OCC, STL
   geometry, native interface, CSG geometry, or 2-D geometry disabled; or
   `ngcore`/`nglib` requested as non-shared libraries.
2. Export/install only the native `ngcore` and `nglib` targets. Do not export
   the disabled `netgen_cgns` interface target.
3. Configure `cmake/NetgenNativeConfig.cmake.in` as the installed
   `cmake/NetgenConfig.cmake`. Derive package roots only from
   `CMAKE_CURRENT_LIST_DIR`, preserve the existing imported target names
   `ngcore` and `nglib`, and include the generated
   `netgen-targets*.cmake` files.
4. Keep version and feature information needed by a native consumer, but omit
   producer source/build paths and absolute OCCT, zlib, Python, GUI, or other
   dependency locations. The exact OCCT/zlib producer identities belong in
   `producer-info.json`, not in relocatable CMake path variables.

The workflow must audit the generated CMake files before packaging and fail if
they contain the runner checkout/build directories, absolute producer OCCT/zlib
paths, Python/GUI targets, `netgen_cgns`, or `/arch:AVX*` requirements.

## GitHub Actions workflow

Create `.github/workflows/windows-netgen-sdk.yml` with three entry modes:

- a push to the `netgen-featool` branch builds and qualifies that exact Git
  commit and uploads a temporary GitHub Actions artifact. It never publishes a
  release. This is the normal implementation/iteration path and allows the SDK
  producer to be developed and qualified entirely through GitHub Actions without
  invoking a local compiler;
- `workflow_dispatch` performs the same non-publishing qualification for an
  explicitly selected repository revision when manual reruns are useful. It is
  optional for chat-driven iteration because branch pushes already provide a
  directly triggerable path;
- a pushed tag matching `netgen-featool-sdk-*` performs the same clean build and
  qualification after first verifying that the tagged commit already has a
  successful branch-push qualification run, then publishes the ZIP and SHA-256
  sidecar through a new draft GitHub Release. Grant `contents: write` only to
  this publication job.

Keep branch-push and manual runs read-only with respect to GitHub Releases and
repository contents. The workflow needs `contents: read` and `actions: read` so a
tag run can verify prior qualification evidence; only the tag-gated publication
job receives `contents: write`. A branch push may produce a GitHub Actions artifact
for inspection, but that artifact is not a released SDK and must never be treated
as a published release asset.

Use a release tag naming form
`netgen-featool-sdk-<12-char-source-sha>-rN`. Name the archive
`netgen-featool-v6.2.2604-<12-char-source-sha>-occt7.9.3-win64-msvc.zip`.
The 12-character source component in both names must equal the first 12
characters of the verified full `GITHUB_SHA`.

Publication is one-shot. Before creating the draft release, require that no
GitHub Release, including a draft, already exists for the tag. Upload both
already-qualified assets to the new draft, verify the expected asset names and
ZIP checksum, and only then make that draft public. Never overwrite, replace, or
complete an existing release for the same tag. If a run fails after draft
creation, that tag/revision is spent; resolve the abandoned draft separately and
use a new `rN` revision for another publication attempt. An intentional rebuild
or producer-contract change likewise uses a new release revision and a downstream
pin update.

The build job performs these ordered steps:

1. Check out the exact workflow commit and record `GITHUB_SHA`. Verify the
   pinned `v6.2.2604` commit is an ancestor. For a branch-push qualification run,
   require the ref to be `refs/heads/netgen-featool` and treat all resulting
   source/behavior and SDK checks as qualification of that exact `GITHUB_SHA`.
   For a publication run, require the tag's 12-character source component to
   equal the prefix of the full `GITHUB_SHA`, fetch `origin/netgen-featool`, and
   require the tagged commit to be reachable from that branch. Query this
   workflow's GitHub Actions runs and require at least one completed successful
   `push` run for `refs/heads/netgen-featool` whose `head_sha` equals the exact
   `GITHUB_SHA`; a manual run or a successful run for another commit is not
   sufficient publication evidence. Require producer metadata/evidence to name
   that prior qualification run and the exact Git SHA being built, then enumerate
   and record every Git source/build-input commit after the pinned upstream
   baseline. Require the committed full-quad regression source and its test
   registration before continuing. Publishing any later source commit first
   requires its own successful branch-push qualification.
2. Record the runner image, `cmake --version`, and `cl /Bv`. Configure only
   with the VS2022 x64 generator; do not use Ninja, MinGW, or artifacts from the
   existing pip/Netgen-OCCT CI path.
3. Download, checksum, extract, normalize, and validate the exact OCCT combined
   release asset.
4. Download, checksum, configure, and build the pinned static zlib producer input.
5. Configure Netgen into a fresh build directory with at least:

   ```text
   -G "Visual Studio 17 2022"
   -A x64
   -DCMAKE_BUILD_TYPE=Release
   -DCMAKE_INSTALL_PREFIX=<runner install root>
   -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL
   -DUSE_SUPERBUILD=OFF
   -DUSE_GUI=OFF
   -DUSE_PYTHON=OFF
   -DUSE_MPI=OFF
   -DUSE_CGNS=OFF
   -DUSE_JPEG=OFF
   -DUSE_MPEG=OFF
   -DUSE_STLGEOM=ON
   -DUSE_INTERFACE=ON
   -DUSE_CSG=ON
   -DUSE_GEOM2D=ON
   -DUSE_NATIVE_ARCH=OFF
   -DUSE_OCC=ON
   -DNGLIB_LIBRARY_TYPE=SHARED
   -DNGCORE_LIBRARY_TYPE=SHARED
   -DNETGEN_NATIVE_SDK=ON
   -DENABLE_UNIT_TESTS=ON
   -DOpenCascade_DIR=<qualified OCCT root>/cmake
   -DZLIB_INCLUDE_DIRS=<staged zlib include>
   -DZLIB_LIBRARIES=<staged zlib>/lib/zlibstatic.lib
   -DZLIB_LIBRARY_RELEASE=<staged zlib>/lib/zlibstatic.lib
   ```

   Disable user/system package registries and constrain package search to the
   selected OCCT/zlib inputs. Keep the existing C++17 setting and ordinary
   STL/CSG/geometry functionality.
6. Build `Release` and the native C++ Catch test targets. For release-tag
   publication, run the normal native Catch unit surface available in this
   GUI/Python/MPI-disabled profile as a baseline-health check, including
   `test_refinement`/`unit_refinement`. The refinement cases must separately
   prove the retained full-quad conversion and ordinary upstream quad refinement.
   Only after those source/behavior checks pass may the exact tagged commit be
   treated as qualified and installed into fresh runner-owned staging state.
7. Construct the compact SDK from the installed native consumer surface and
   generate `producer-info.json`.
8. Qualify the staged SDK, then ZIP that exact staged tree. Extract the ZIP into
   a second fresh directory and repeat the package/consumer checks against the
   extracted copy so the archive itself, rather than only the pre-archive staging
   directory, is proven usable.
9. Compute the ZIP SHA-256, emit the sidecar file, and upload the build artifact.
   A tag run then attaches those same bytes to the GitHub Release.

## SDK layout and producer metadata

The archive root is:

```text
include\...
lib\ngcore.lib
lib\nglib.lib
bin\ngcore.dll
bin\nglib.dll
cmake\NetgenConfig.cmake
cmake\netgen-targets.cmake
cmake\netgen-targets-release.cmake
producer-info.json
```

Do not include Python modules, Tcl/Tk, the Netgen GUI/executable, zlib headers or
libraries, zlib DLLs, OCCT DLLs/import libraries, build trees, test binaries, or
source files.

`producer-info.json` records at least:

- upstream baseline tag and commit;
- exact fork/source Git commit and the commits after the baseline that form the
  qualified local patch set;
- GitHub repository/ref and workflow run identity;
- runner image, generator, compiler/MSVC toolset, x64 architecture,
  Release configuration, C++17, and `/MD`;
- all material Netgen producer options, including
  `USE_NATIVE_ARCH=OFF`;
- exact OCCT asset URL and SHA-256;
- observed OCCT MSVC CRT/UCRT runtime family and the inspection/evidence used to
  establish compatibility with the `/MD` producer contract;
- exact zlib source URL and SHA-256; and
- hashes of `ngcore.dll`, `nglib.dll`, their import libraries, and the
  installed CMake metadata.

Do not record transient runner checkout/build/cache paths as dependency identity.

## Qualification and acceptance

Add a small native consumer fixture under `tests/windows-native-sdk/`. It
configures with only the extracted Netgen SDK and the selected official OCCT SDK,
and links through the installed Netgen imported targets. Compile representative
installed C++ headers from the supported native SDK surface:
`stlgeom.hpp`, `occgeom.hpp`, `meshing.hpp`, and
`nginterface_v2.hpp`. The translation unit that includes `occgeom.hpp` must define
`OCCGEOMETRY` and compile with the pinned OCCT `inc` directory so the guarded OCC
C++ declarations and their OCCT includes are actually compiled; merely including
the header without that definition is not a valid check. The fixture need not call
the OCCT API directly. For the OCC-backed C nglib boundary, include `nglib.h` and
`nglib_occ.h` explicitly rather than relying on the build-tree-only `OCCGEOMETRY`
definition to make the latter visible through `nglib.h`. Load a small deterministic
BREP fixture through `Ng_OCC_Load_BREP`, check success, and clean up the Netgen
geometry. This establishes the installed native C++ header surface, import
libraries/DLLs, and the OCCT-backed public nglib boundary.

The GitHub runner must establish all of the following before artifact upload:

- `ngcore.dll` and `nglib.dll` are AMD64 PE images with matching
  `.lib` import libraries.
- The DLLs use the shared MSVC runtime expected by the `/MD` contract.
- The OCCT DLLs in Netgen's link/runtime closure have inspected runtime metadata
  or equivalent package evidence establishing the compatible dynamic MSVC
  CRT/UCRT model required by the `/MD` contract.
- `nglib.dll` has no `zlib1.dll`, Python, Tcl/Tk, MPI, or CGNS runtime
  dependency; `ngcore.dll` likewise has no disabled-feature runtime baggage.
- Every non-system OCCT DLL imported by Netgen exists in the exact pinned OCCT
  7.9.3 binary family used for the producer build.
- The native build/export metadata contains no `/arch:AVX`,
  `/arch:AVX2`, or `/arch:AVX512` requirement.
- The focused refinement regression proves both
  `Refine(mesh, true)` triangle-to-three-quads behavior and ordinary quad
  uniform refinement before any release is published, and the remaining native
  Catch unit surface for the producer profile passes on the same tagged commit.
- Producer evidence records the exact Git producer commit and successful GitHub
  Actions execution of the focused full-quad and baseline refinement checks
  against that Git commit.
- A push to `netgen-featool` can perform the complete producer build and runtime
  qualification on GitHub-hosted `windows-2022` without any local compilation;
  the run's artifact remains non-release evidence until a later eligible tag run.
- A publication run finds a completed successful branch `push` qualification run
  of this workflow whose `head_sha` equals its full `GITHUB_SHA`, and the
  tag/archive 12-character source component equals that commit prefix.
- The SDK CMake package configures after relocation with the original install
  directory unavailable and resolves all Netgen imported artifacts inside the
  relocated SDK.
- The OCC-backed consumer configures, links, and runs from that relocated SDK.
  For its runtime launch, remove Netgen/zlib build directories and unrelated
  dependency directories from `PATH`; expose only the relocated Netgen
  `bin`, the exact OCCT/third-party runtime directories required by the
  official combined package, and normal Windows runtime locations.
- Auditing `NetgenConfig.cmake` and `netgen-targets*.cmake` finds no
  producer checkout/build path, absolute OCCT/zlib path, Python/GUI target, or
  imported artifact outside the SDK root.
- Re-extracting the final ZIP and repeating structural, relocation, and native
  consumer checks succeeds.
- Release publication starts only when no release exists for that tag; both
  qualified assets are verified on a new draft release before it is made public,
  and an existing or partially created release is never mutated by a retry.

The producer is complete when the published GitHub Release contains the qualified
ZIP and matching SHA-256 sidecar built from the pinned Git source and dependency
inputs, and the release assets match the bytes that passed the workflow's archive
re-extraction and native consumer checks. Downstream application integration is
outside this plan.

## Progress and evidence

Planning inspection on 2026-10-05 established:

- the remote `netgen-featool` branch is currently
  `f416530e7105c8ca053d23a0300fb7cfbc23a0f4`; the retained full-quad patch and
  Catch regression coverage are committed and pushed, with pinned upstream
  `v6.2.2604` at `3ee489c7d58fdbc2a6708cca3cbaefaae506dc17` in its ancestry;
- the branch currently has no `.github` workflow directory;
- Netgen already sets `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL` and C++17,
  supports the required shared `ngcore`/`nglib` profile, and accepts an
  externally selected OpenCascade package with `USE_SUPERBUILD=OFF`;
- the ordinary installed `NetgenConfig.cmake` currently embeds producer source
  and OCCT/zlib paths, so a dedicated opt-in native SDK config is required for
  the SDK relocation contract;
- the official OCCT V7_9_3 GitHub release publishes
  `opencascade-7.9.3-vc14-64-combined.zip` with the exact SHA-256 pinned above;
  and
- the GitHub `windows-2022` image supplies Visual Studio 2022, while Microsoft's
  documented MSVC 14.x binary-compatibility contract permits a VS2022 consumer
  to link against the older vc14-family OCCT binary distribution.

Plan review on 2026-10-05 also established that the rebased Netgen install
exports `nginterface_v2.hpp`, not the historical `interface.hpp`, and that
`nglib_occ.h` must be included explicitly by an installed C API consumer
because `OCCGEOMETRY` is currently a build-tree directory definition rather
than exported target metadata. A valid installed `occgeom.hpp` smoke test must
likewise define `OCCGEOMETRY` and use the selected OCCT headers so its guarded C++
surface is actually compiled. The release contract was tightened at the same time
to publish both verified assets through a fresh draft release with no same-tag
retry mutation.

Follow-up review on 2026-10-05 clarified that this Git repository is the sole
source/provenance repository for the producer. The retained full-quad patch and
regression coverage are now committed at `f416530e7105c8ca053d23a0300fb7cfbc23a0f4`.
The source/behavior and Windows producer qualification will run on the exact Git
commit through GitHub Actions once the producer workflow is implemented. A push to
`netgen-featool` is the normal non-publishing trigger so the implementation can be
built and tested from this chat interface without a local compiler or a manual
`workflow_dispatch` action. Publication will verify an earlier successful branch
qualification run for the same `GITHUB_SHA`; no workflow-embedded self-SHA pin is
used.

No build or runtime validation has been performed for this plan. The production
publication gate remains successful GitHub Actions source/behavior and SDK
qualification of the exact committed/pushed producer Git SHA on the
`netgen-featool` branch, followed by a release tag pointing to that same SHA.

Implementation started on 2026-10-05. The opt-in native SDK CMake mode,
relocatable package config, installed native consumer fixture, and GitHub Actions
producer/publication workflow have been implemented in the working tree. Local
build, compile, test, and runtime execution remain intentionally unused; the
first implementation validation will be the branch-push workflow on GitHub
Actions.
