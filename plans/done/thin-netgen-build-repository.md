---
kind: plan
title: Convert the Netgen fork into a thin build and patch repository
summary: Replace the checked-in upstream Netgen source tree with a pinned upstream checkout, an ordered local patch set, and CI that builds and qualifies the reconstructed source.
area: release-engineering
priority: P2
depends_on: []
children: []
affected_files:
  - .clang-format
  - .git-blame-ignore-revs
  - .gitattributes
  - .gitignore
  - .github/README.md
  - .github/auto-occt-netgen-release.sh
  - .github/linux-netgen-sdk/*
  - .github/macos-netgen-sdk/*
  - .github/occt-sdk-release.txt
  - .github/resolve-occt-release.py
  - .github/windows-netgen-sdk/*
  - .github/workflows/auto-occt-netgen-release.yml
  - .github/workflows/linux-netgen-sdk.yml
  - .github/workflows/macos-netgen-sdk.yml
  - .github/workflows/release-netgen-sdk.yml
  - .github/workflows/thin-netgen-validation.yml
  - .github/workflows/windows-netgen-sdk.yml
  - AGENTS.md
  - README.md
  - upstream/netgen.json
  - scripts/netgen_source.py
  - scripts/prepare-netgen-source.py
  - scripts/check-release-qualification.py
  - scripts/verify-netgen-sdk-release.py
  - scripts/tests/**
  - patches/netgen/*
  - tests/**
  - CMakeLists.txt
  - cmake/**
  - doc/**
  - external_dependencies/**
  - libsrc/**
  - ng/**
  - nglib/**
  - python/**
  - py_tutorials/**
  - rules/**
  - tutorials/**
  - windows/**
  - pyproject.toml
  - .gitlab-ci.yml
  - .gitmodules
  - CLA.pdf
  - CONTRIBUTING.md
  - ChangeLog
  - INSTALL
  - NEWS
  - TODO
  - depcomp
  - mkinstalldirs
  - netgen.icns
---
# Convert the Netgen fork into a thin build and patch repository

## Goal and scope

Convert the active `netgen-featool` tree from a long-lived source fork into a
thin producer repository. The repository will own the GitHub Actions workflows,
native SDK consumer tests, upstream source pin, and the small Netgen patch set
required by FEATool. It will no longer keep an editable copy of the complete
upstream Netgen source tree.

Every producer workflow will materialize its build source on the GitHub runner
from the exact canonical NGSolve Netgen release tag and commit recorded by this
repository, apply the repository's ordered patch series, then build and qualify
that reconstructed source. Existing Windows, Linux, and macOS SDK behavior,
artifact inventory, release gating, and native consumer contracts remain the
compatibility target.

The initial thin baseline remains:

```text
upstream repository: https://github.com/NGSolve/netgen.git
tag:                 v6.2.2608
commit:              96e5682f6ea43ba77ba3bb2ae4bb4bd1791f506e
```

The expected source delta against `v6.2.2608` is small enough to preserve as
patches. It consists primarily of the FEATool triangle-to-quad refinement and
Catch regression, the native SDK CMake/install/export changes, and the GCC 10
archive reader compatibility fix. The exact delta must be regenerated from the
synchronized active `netgen-featool` head before this plan returns to `ready`;
the earlier audit at `88ed7e45` is not an implementation baseline.

The active remote branch observed during review was `9b56af11`. Relative to the
earlier local planning point, it integrates Windows shared and static production
in `.github/workflows/windows-netgen-sdk.yml`, adds immutable-OCCT resolution and
automatic OCCT release-update automation, and changes native SDK CMake/source
files. Those current producer, release, and automation paths are part of this
migration. SDK producer workflows, release logic, consumer tests, documentation,
and plans remain normal files in the thin repository.

This plan does not rewrite Git history, delete historical release tags, or move
existing releases to a new GitHub repository. The active checkout and CI become
thin, but old source objects remain reachable through existing history and tags.
If physical repository storage or default full-clone size later needs to be
reduced, handle that as a separate history/repository migration with its own
release-provenance requirements.

No local or host compilation is part of the implementation or acceptance path.
All Netgen builds and runtime qualification continue to run on GitHub Actions.

## Source and patch contract

Add `upstream/netgen.json` as the single executable source of truth for the
Netgen upstream identity. It contains only the canonical repository URL, release
tag, and full commit SHA. Platform workflows and the release workflow must read
this file instead of carrying independent `BASELINE_TAG`, `BASELINE_SHA`,
`NETGEN_BASELINE_TAG`, or `NETGEN_BASELINE_SHA` constants.

All current-baseline executable version text must derive from that manifest as
well. Producer scripts and workflows derive the artifact version component from
the manifest tag, and the release workflow uses the same derived value for its
expected archive inventory, release title, notes, and provenance checks. The
Linux/macOS build scripts and Windows producer must not carry an independent
`v6.2.2608` or `6.2.2608` baseline literal for artifact naming or producer
metadata. Historical examples in documentation may retain explicit old version
text when they are clearly non-executable reference material.

Keep the Netgen modifications under `patches/netgen/` with an explicit
`series` file. The migration should create patches from the final tree delta
against `v6.2.2608` after the active branch has been synchronized and re-audited,
grouped by current ownership rather than preserving historical commit
boundaries. The expected groups are:

1. `0001-tri2quad.patch` contains the current meshing implementation and
   `tests/catch/refinement.cpp` registration/regression coverage.
2. `0002-native-sdk.patch` contains the current `NETGEN_NATIVE_SDK` CMake,
   install, package-config, exported-header, shared/static library, and
   relocatability changes needed by the SDK producers.
3. `0003-gcc10-archive-reader.patch` contains the current GCC 10 compatibility
   fix in `libsrc/core/archive.hpp`.

If final-delta inspection shows that one of these groups has an unavoidable
ordering dependency on another, record that order in `series`; do not split
patches further merely to reproduce old Git commits. Conversely, do not combine
unrelated source changes into one patch when keeping them separate makes the
upstream-port failure location materially clearer.

`series` is authoritative. Every non-comment, non-empty entry must name one
existing patch exactly once, and every `*.patch` file in the directory must be
listed exactly once. Patch provenance in release artifacts uses this order.

Patch bytes must also be canonical across producer operating systems because
their SHA-256 values are release provenance. Add `.gitattributes` entries that
force `patches/netgen/*.patch` and `patches/netgen/series` to LF in every working
tree. The source-preparation script must reject carriage returns in those files
and hash the exact LF bytes it applies. This makes a given producer commit yield
the same ordered patch hashes on Windows, Linux, and macOS.

The native SDK consumer tests under `tests/windows-native-sdk/` and
`tests/unix-native-sdk/` remain repository-owned files and are not copied into
the staged Netgen source. Producer scripts must reference them through the thin
repository checkout. Catch tests that must participate in Netgen's own test
build remain in the patch series because they have to exist inside the
materialized Netgen tree.

## Source preparation

Add one cross-platform `scripts/prepare-netgen-source.py` used by all producer
workflows. The script owns only source materialization and provenance; platform
build decisions remain in the existing producer workflows/scripts.

Given the thin repository root and a fresh runner-owned destination, the script
must:

1. Read and validate `upstream/netgen.json`.
2. Initialize/fetch from the canonical NGSolve Netgen repository without
   fetching unrelated upstream history.
3. Resolve the configured tag to a commit and require an exact match with the
   configured full SHA before any patch is applied.
4. Check out that commit detached in the runner-owned destination.
5. Validate `patches/netgen/series`, require canonical LF bytes, compute SHA-256
   for each exact patch file, run `git apply --check` in series order, and apply
   each patch.
6. Run `git diff --check` after application.
7. Write a runner-owned `source-provenance.json` containing the upstream
   repository/tag/commit, deterministic Netgen version identity, and ordered
   patch `{path, sha256}` entries for use by the platform producer metadata.

The script must fail rather than fall back to another branch, tag, cached source
tree, patch order, or network source. It must not create a synthetic Git commit;
the producer repository commit plus the recorded upstream commit and patch
hashes are the source identity.

The producer checkout itself should use a shallow `actions/checkout` whenever a
workflow does not require local repository history. The old full-depth checkout
was needed to prove the upstream baseline was an ancestor of the fork source;
that invariant disappears in the thin model because the upstream baseline is
fetched and verified independently.

## Netgen version contract

Do not let reconstructed source derive its public version from the staged Git
working tree. The source is checked out at the upstream release commit and then
modified by uncommitted patches, so `git describe --dirty` would describe the
upstream checkout state rather than the thin producer revision and would make
the build appear dirty.

For each pinned upstream baseline, derive one deterministic
`NETGEN_VERSION_GIT` value from the manifest as
`<tag>-0-g<first-12-hex-of-upstream-commit>`. For the initial baseline this is:

```text
v6.2.2608-0-g96e5682f6ea4
```

Every producer must pass that exact value to CMake with
`-DNETGEN_VERSION_GIT=...`. Netgen's public semantic version therefore reports
the pinned upstream release (`6.2.2608` for the initial baseline), while the
exact FEATool reconstruction identity remains the producer repository commit,
upstream full commit, and ordered patch hashes in `producer-info.json`. Record
the derived `NETGEN_VERSION_GIT` in `source-provenance.json` and producer
metadata so all platforms can verify the same version contract. This explicitly
replaces the old fork-descendant `git describe` semantics.

## Provenance and release contract

Keep `GITHUB_SHA` as the producer revision. Artifact names and release tags may
continue to use the first 12 characters of that SHA, so downstream naming does
not change:

```text
netgen-featool-v6.2.2608-<producer-sha12>-...
netgen-sdk-<producer-sha12>-rN
```

The meaning becomes explicit: the SHA identifies the thin producer repository
revision; `v6.2.2608` and its full upstream commit identify the Netgen baseline.

Bump `producer-info.json` to schema version 2 on all platforms. Replace
`source.commits_after_baseline` with source reconstruction data derived from
`source-provenance.json`. At minimum, every archive records:

```json
{
  "schema_version": 2,
  "upstream": {
    "repository": "https://github.com/NGSolve/netgen.git",
    "tag": "v6.2.2608",
    "commit": "96e5682f6ea43ba77ba3bb2ae4bb4bd1791f506e",
    "version_git": "v6.2.2608-0-g96e5682f6ea4"
  },
  "source": {
    "repository": "<producer GitHub repository>",
    "ref": "<producer Git ref>",
    "commit": "<full producer GITHUB_SHA>",
    "patches": [
      {
        "path": "patches/netgen/0001-tri2quad.patch",
        "sha256": "<sha256>"
      }
    ]
  }
}
```

Existing workflow/run qualification identifiers and platform toolchain,
dependency, linkage, and artifact hashes remain present as they are today.

Update `release-netgen-sdk.yml` so the combined release verifies that all eight
archives report:

- schema version 2;
- the same producer repository and exact producer `GITHUB_SHA`;
- the upstream repository, tag, full commit, and derived version identity from
  `upstream/netgen.json` and source preparation;
- an identical ordered patch list and hashes;
- the existing platform-specific linkage, OCCT, dependency, and artifact
  invariants.

Separate combined-archive verification from the publication steps inside the
post-producer release job in `release-netgen-sdk.yml`. That job must run on both
`workflow_dispatch` and release-tag runs, download all eight archives once, and
perform the complete inventory/checksum/schema/provenance consistency checks
unconditionally. Manual dispatch with publication disabled must stop after
successful verification. Release-creation/upload steps then run conditionally
only for an eligible `netgen-sdk-*` tag plus the existing explicit publication
condition, using the exact archive files already verified in that job. This
provides a real non-publishing qualification path without introducing a second
copy or handoff of release bytes.

Release eligibility remains attached to an exact producer commit that already
passed the producer qualification workflows. Preserve both qualification
sources accepted by the current release automation: a successful push run for
that exact SHA on `netgen-featool`, or a successful `workflow_dispatch` run for
that exact SHA such as the temporary `automation/occt-qualify-<sha>` ref used by
the automated OCCT release flow. The tag-triggered producer workflows no longer
use local Git ancestry to prove that the producer commit is contained in
`netgen-featool`, because doing so would force a deep checkout of the old fork
history. Use the GitHub API/compare surface already available to the workflows
to require that the tagged producer commit is identical to or an ancestor of
the current `netgen-featool` branch tip, and keep the exact-SHA successful
qualification lookup independent of whether the qualifying run was a branch
push or an explicit dispatch.

## Ordered migration

### 0. Synchronize the active branch and refresh the planning baseline

Before generating patches or editing producer workflows, synchronize with the
current `origin/netgen-featool` head and create one exact migration-baseline
commit. The two local-only commits have explicit dispositions:

- Do not replay `f3de0c66` (`ci: add Windows static Netgen SDK`). Its static
  SDK implementation is superseded by the integrated remote implementation
  introduced at `0b2b2f06` and the subsequent remote fixes.
- Carry forward the repository build-policy text from `88ed7e45`
  (`docs: clarify release build guidance`) into the synchronized baseline.
  `origin/netgen-featool` does not contain those nine `AGENTS.md` lines, and
  the no-local-compilation/GitHub-Actions-only contract remains applicable to
  the thin producer repository.

Do not otherwise replay either local commit wholesale, and do not generate the
thin representation from the stale `88ed7e45` tree.

On the synchronized head:

1. record the exact producer commit used as the migration baseline;
2. re-run the final tree diff against exact upstream `v6.2.2608` and confirm or
   revise the expected tri2quad, native-SDK, and GCC-10 patch groups;
3. re-audit the actual producer/release topology, including the shared and
   static Windows jobs in `windows-netgen-sdk.yml`, immutable-OCCT resolution,
   and `auto-occt-netgen-release.yml`;
4. confirm the root-file disposition fixed by this plan: retain `AUTHORS`,
   `LICENSE`, `.editorconfig`, and the thin-repository documentation/config;
   rewrite `.gitignore` and `.gitattributes` for the thin layout; remove
   `.clang-format`, `.git-blame-ignore-revs`, `CLA.pdf`,
   `CONTRIBUTING.md`, `ChangeLog`, `INSTALL`, `NEWS`, `TODO`,
   `depcomp`, `mkinstalldirs`, and `netgen.icns` with the checked-in
   upstream source/build trees; and
5. update this plan's affected paths and progress evidence if that audit changes
   the concrete scope.

If the synchronized remote head changes before implementation begins, repeat
the source/workflow audit before patch extraction and update the plan only if
that newer head changes the settled scope or contracts.

### 1. Add source reconstruction while the fork tree still exists

Create the upstream manifest, patch series, and source-preparation script without
removing the current Netgen tree. Generate each patch from the current final
delta against the exact `v6.2.2608` commit so the patch representation describes
the code being shipped now rather than an earlier intermediate revision.

Update `.gitignore` at the same time so the new executable source inputs are
trackable. Remove or narrow the current broad `*.json` and `*.patch` ignores
so `upstream/netgen.json` and every `patches/netgen/*.patch` file cannot be
silently omitted from a commit.

Add a temporary transition check on GitHub Actions that materializes upstream
plus patches and compares the reconstructed upstream-owned build/test paths with
the corresponding paths in the current fork checkout. The comparison must cover
the source and CMake files that contribute to the SDK build, including:

```text
CMakeLists.txt
cmake/NetgenNativeConfig.cmake.in
libsrc/core/
libsrc/meshing/
nglib/
tests/catch/CMakeLists.txt
tests/catch/refinement.cpp
```

Compare final file content, not Git commit shape. Any intentional difference
must be resolved before moving to the next step; the transition is meant to
prove that patch extraction did not lose a current source change.

Add focused non-build validation for the source-preparation contract. Using
disposable fixtures or temporary copies, require the same preparation command
used by producers to fail for each of: an unlisted patch, duplicate series
entry, missing patch, CRLF patch/series bytes, manifest tag/SHA mismatch, and a
patch that does not apply. These checks run on GitHub Actions and do not compile
Netgen.

### 2. Make every producer build the reconstructed source

Update the Windows shared and static jobs in
`.github/workflows/windows-netgen-sdk.yml`, plus the Linux and macOS producers,
to:

1. shallow-checkout the thin producer commit;
2. run `prepare-netgen-source.py` into a fresh runner temporary directory;
3. configure/build Netgen from that directory;
4. run the existing focused refinement qualification from that build;
5. run native SDK consumer tests from the thin repository's `tests/` directory;
6. generate schema-version-2 producer metadata using
   `source-provenance.json`.

The native configure profiles, OCCT/zlib identities, shared/static outputs,
runtime checks, relocation checks, and archive layout remain unchanged unless a
path must change because source and producer files now live in different roots.
The immutable-OCCT resolver and automated OCCT update/release flow must continue
to consume the same producer workflow outputs and qualify the same exact
producer commit after this path change.

Run the complete existing branch qualification matrix on the transition commit.
This is the behavioral proof that upstream-plus-patches is equivalent to the
current fork for the supported SDK producer profiles.

### 3. Update release validation and tag provenance

Update `release-netgen-sdk.yml` and the tag-gating logic in each producer to the
thin source/provenance contract. Remove checks that require the upstream Netgen
commit/tag to exist in the producer checkout or be an ancestor of
`GITHUB_SHA`.

Keep release tags bound to the exact producer commit and keep the requirement
that this commit already passed an accepted exact-SHA qualification: either the
normal `netgen-featool` branch-push run or an explicit `workflow_dispatch` run
used by the OCCT automation. Verify branch containment without fetching the
historical fork graph locally.

Run `release-netgen-sdk.yml` through the new non-publishing manual verification
path. It must rebuild/download the complete eight-archive inventory and execute
the same combined schema/provenance verifier used before publication, while
creating no tag or GitHub release.

Make the combined provenance verification reusable by its non-publishing
validation path, then exercise negative fixtures derived from a valid archive
set. At minimum, mutate the producer commit, upstream tag/commit/version
identity, patch order, and one patch hash independently and require the same
verifier used for publication to reject every mutation.

Also exercise the OCCT automation's distinctive qualification path without
publishing: point a temporary qualification ref at an exact producer commit,
dispatch the Windows, Linux, and macOS producer workflows on that ref, require
all three exact-SHA runs to succeed, then run the same qualification lookup used
by release-tag gating and require it to accept those dispatch runs after the
temporary ref is removed. This check must establish that release eligibility is
based on the immutable producer SHA and successful workflow result rather than
the continued existence or name of the temporary ref.

Add focused negative gate checks for the release-eligibility decision as well:
an otherwise successful run with the wrong `head_sha`, an unsupported event or
failed conclusion, and a producer commit reported by the compare API as outside
the `netgen-featool` line must all be rejected. The test may use deterministic
API-response fixtures for the decision logic, but the positive temporary-ref
case above continues to exercise the real GitHub API/workflow integration.

### 4. Remove the checked-in upstream tree

After all producers build and qualify from reconstructed source, remove the
upstream-owned Netgen source/build/documentation material from the active tree.
This includes the current native source directories, upstream CMake/project
files, Python/GUI/tutorial trees, upstream test infrastructure, submodule
metadata, GitLab CI file, and other files that exist only because this repository
currently carries the Netgen source checkout. Remove the checked-in upstream
`tests/` tree except for the repository-owned `tests/windows-native-sdk/` and
`tests/unix-native-sdk/` directories; the Catch refinement regression is retained
through `patches/netgen/` and exists only in the reconstructed Netgen source.

Apply the settled root-file disposition from step 0. Keep `LICENSE` and
`AUTHORS` as licensing/attribution inputs, plus the repository configuration
that still governs the thin tree. Remove the upstream source-development and
contribution artifacts that no longer describe this repository, including
`.clang-format`, `.git-blame-ignore-revs`, `CLA.pdf`, `CONTRIBUTING.md`,
`ChangeLog`, `INSTALL`, `NEWS`, `TODO`, `depcomp`, `mkinstalldirs`, and
`netgen.icns`.

Retain:

- `.github/` producer/release automation and supporting scripts;
- `patches/netgen/`;
- `scripts/prepare-netgen-source.py`;
- `upstream/netgen.json`;
- thin-repository `tests/windows-native-sdk/` and
  `tests/unix-native-sdk/`;
- repository instructions and planning records;
- the applicable repository license/attribution files.

Rewrite the top-level `README.md`, root `AGENTS.md`, and `.github/README.md` so
they describe the thin source model and no longer instruct maintainers to merge
upstream Netgen release tags into `netgen-featool`.

Remove the temporary source-parity comparison once the checked-in source it
compares against is gone.

### 5. Replace the upstream upgrade procedure

Document the new release-port workflow:

1. select an exact canonical NGSolve Netgen release tag;
2. resolve and record its full commit in `upstream/netgen.json`;
3. run source preparation and identify patches that no longer apply;
4. rebase only those repository-owned patches onto the new baseline, preserving
   their required behavior and regression coverage;
5. inspect the resulting patch delta and dependency/binary compatibility
   changes;
6. run the focused refinement/native SDK checks followed by the Windows, Linux,
   and macOS qualification workflows on one coherent producer commit;
7. create a `netgen-sdk-<producer-sha12>-rN` release tag only after that exact
   producer commit has passed an accepted exact-SHA qualification run.

An upstream update is complete only when the manifest, patch set, artifact
naming/version metadata, producer metadata, and qualification workflows all
identify the same new baseline.

## Acceptance and validation

The implementation is complete when all of the following are established.

### Source reconstruction

- `upstream/netgen.json` is the only executable Netgen baseline pin used by the
  producer/release workflows.
- Artifact names, expected release inventory, release title/notes, and producer
  metadata derive their Netgen baseline version from `upstream/netgen.json`;
  producer/release code contains no independent current-baseline tag, SHA, or
  semantic-version literal.
- A clean GitHub runner can materialize `v6.2.2608` at
  `96e5682f6ea43ba77ba3bb2ae4bb4bd1791f506e` and apply the complete patch series
  with no fallback source.
- The patch-series validator rejects an unlisted patch, duplicate entry, missing
  patch, non-LF patch/series bytes, tag/SHA mismatch, or patch that does not
  apply, and focused non-build CI cases demonstrate each rejection.
- The same producer commit yields identical ordered patch SHA-256 values on
  Windows, Linux, and macOS checkouts.
- During the transition, the reconstructed source matches the current fork for
  all upstream-owned files participating in the SDK build and focused
  regression.

### Version identity

- Every producer passes the manifest-derived deterministic
  `NETGEN_VERSION_GIT` value; no producer relies on staged-source
  `git describe --dirty`.
- For the initial baseline, generated/installed Netgen version metadata and the
  runtime library version report semantic version `6.2.2608`, while producer
  metadata records `v6.2.2608-0-g96e5682f6ea4` plus the full producer/upstream
  and patch reconstruction identity.
- The native SDK consumer qualification checks the installed CMake version and
  runtime Netgen version through the produced SDK so an accidental dirty or
  fork-descendant version cannot pass unnoticed.

### Producer behavior

- Windows x64 MSVC shared qualification succeeds from reconstructed source.
- Windows x64 MSVC static qualification succeeds from reconstructed source.
- Linux x86_64 shared and static qualification succeeds from reconstructed
  source with the current glibc/GCC compatibility requirements.
- macOS x86_64 and arm64 shared/static qualification succeeds from
  reconstructed source with the current deployment/toolchain requirements.
- The focused triangle-to-three-quads regression and ordinary upstream quad
  regression still run from the patched Netgen test tree.
- The staged SDK consumer tests still compile and run from the thin
  repository-owned test directories.
- Existing SDK archive contents, linkage contracts, OCCT/zlib dependency
  identities, relocation checks, and expected eight-archive release inventory
  remain satisfied.

### Provenance and release gating

- Every produced archive contains schema-version-2 `producer-info.json` with the
  exact upstream repository/tag/commit, producer commit, and ordered patch
  hashes.
- The combined release rejects archives whose producer commit, upstream pin, or
  patch list/hash differs across platforms; focused tamper cases demonstrate
  rejection of each provenance class.
- A non-publishing `workflow_dispatch` run executes the same combined
  eight-archive schema/provenance verification and creates no release; release
  creation/upload steps use those same verified files and run only under an
  eligible publication trigger.
- Release-tag publication requires a successful accepted qualification for the
  exact producer commit: either a `netgen-featool` branch-push run or an exact-SHA
  `workflow_dispatch` run. The tagged commit must also belong to the
  `netgen-featool` line without fetching the old full fork history.
- A temporary-ref `workflow_dispatch` qualification succeeds on all three
  producer workflows, and the release eligibility lookup still recognizes those
  exact-SHA successful runs after the temporary ref is deleted, matching the
  automated OCCT update/release path.
- Release-eligibility negative cases reject a wrong `head_sha`, unsupported
  event or failed conclusion, and a compare result that places the producer
  commit outside the `netgen-featool` line.
- `netgen-sdk-<producer-sha12>-rN` and existing archive naming remain valid for
  the same producer revision semantics.

### Thin active tree

- The active repository tree no longer contains the full upstream Netgen
  source, CMake project, Python package, GUI, tutorials, upstream test
  infrastructure, or upstream CI files.
- The remaining active tree contains only producer/release automation, source
  pinning and patches, SDK consumer tests, repository documentation/plans, and
  required licensing/metadata.
- Under `tests/`, only the thin-repository native SDK consumer test directories
  remain; upstream Catch/pytest/build-test infrastructure is absent from the
  active producer tree, with required Catch regression changes represented in
  the Netgen patch series.
- The settled root-file disposition is applied: `.clang-format`,
  `.git-blame-ignore-revs`, `CLA.pdf`, `CONTRIBUTING.md`, `ChangeLog`,
  `INSTALL`, `NEWS`, `TODO`, `depcomp`, `mkinstalldirs`, and
  `netgen.icns` are absent; `AUTHORS`, `LICENSE`, `.editorconfig`, and
  required thin-repository configuration remain.
- `.gitignore` no longer broadly ignores the tracked manifest or patch inputs,
  and `.gitattributes` enforces the canonical patch/series line endings.
- Producer workflows no longer use `fetch-depth: 0` solely to establish the
  upstream baseline ancestry relationship.
- Repository documentation explains that historical Git objects remain by
  design and that reducing physical Git history is a separate migration.

## Progress and evidence

Initial planning inspection covered the local `netgen-featool` source/workflow
state through `88ed7e45`. Review then found that checkout two commits ahead and
nineteen commits behind `origin/netgen-featool`, whose observed tip was
`9b56af11`. The remote changes materially alter the migration surface: Windows
static production is integrated into `windows-netgen-sdk.yml`, immutable-OCCT
resolution and automatic OCCT update/release automation were added, and native
SDK CMake/source files changed. Inspection of that remote tip confirmed the
current source delta still fits the tri2quad, native-SDK, and GCC-10 patch
ownership described above.

The two local-only commits now have settled dispositions. `f3de0c66` is
superseded by the remote integrated Windows static implementation and subsequent
fixes, so it is not replayed. `88ed7e45` contains only the nine-line root
`AGENTS.md` build-policy addition; those rules are absent from
`origin/netgen-featool` and remain applicable, so that content is carried
forward when implementation creates the synchronized migration baseline.

The current baseline is `v6.2.2608` at
`96e5682f6ea43ba77ba3bb2ae4bb4bd1791f506e`. Current workflows build directly
from `GITHUB_WORKSPACE`, verify baseline ancestry in the fork history, and record
post-baseline commits in producer metadata. The current release workflow verifies
eight SDK archives and binds them to the exact producer `GITHUB_SHA`.

Review also found cross-platform/release details that are now explicit in the
contract: patch hashes require canonical LF bytes, reconstructed source must
override Git-derived Netgen version identity deterministically, and combined
release verification needs a real non-publishing manual path. A later review of
the current remote workflows also corrected three material scope points: exact-SHA
`workflow_dispatch` qualification must remain release-eligible for automated
OCCT publishing, all executable baseline/version literals must derive from the
manifest, and the thin-tree deletion audit must include upstream `tests/`
infrastructure while retaining only the repository-owned native SDK consumer
tests. The automated temporary-ref qualification path now has an explicit
acceptance check.

Final review also found that the plan's rejection guarantees needed explicit
negative evidence. The ordered validation now covers malformed patch-series and
source-identity inputs, tampered cross-platform provenance, wrong-SHA/event/
conclusion qualification results, and failed branch-containment decisions.

Implementation re-fetched `origin/netgen-featool` and confirmed the reviewed tip
was still `9b56af11f29b1daf8ecae13f57c05efa0826df55`. The stale local branch was
synchronized to that tip, only the settled nine-line build-policy text was
carried forward, and migration baseline
`ffe3a8b078785c492b86e7a0e2add96a12284148` was created. The final source delta
against exact upstream `96e5682f6ea43ba77ba3bb2ae4bb4bd1791f506e` covered
exactly the planned 13 upstream-owned paths with no patch-group overlap or
ordering dependency.

Commit `d6eded77c6c95ed72dac243b468e334cdb0b1cd4` added the manifest, ordered
three-patch source representation, shared source/provenance helper, preparation
script, focused non-build contract fixtures, and temporary source-parity workflow
while the checked-in source tree still existed. Local non-build validation
materialized the real pinned NGSolve tag and compared the reconstructed SDK build
and regression inputs byte-for-content against the synchronized fork paths with
no differences. The source-preparation fixture suite passed all eight positive
and required rejection cases.

Commit `64050b14ce7918157e7f5a24e92ed6ff7550e373` converted Windows
shared/static, Linux shared/static, and macOS x86_64/arm64 shared/static producers
to reconstructed source, deterministic manifest-derived version identity, and
schema-version-2 producer provenance. It also introduced exact-SHA GitHub API
qualification/containment logic, reusable combined release verification, the
non-publishing release path, provenance tamper fixtures, qualification negative
fixtures, and installed/runtime SDK version assertions. Final review found that
the separate Linux compatibility matrix also needed the required semantic version
at CMake configure and runtime invocation. That correction was moved before the
thin-tree deletion, producing initial full-source transition candidate
`105081a09141ea8cb5698bb9ca92f3e205ce26b2`. Local non-build checks passed both
Python contract suites, Bash syntax checks, PowerShell parsing, YAML loading,
`git diff --check`, a complete native-consumer invocation sweep, and a stale
executable baseline/version sweep.

The first remote qualification attempt at `105081a09141ea8cb5698bb9ca92f3e205ce26b2`
proved that source reconstruction itself was working but exposed a retained
consumer-boundary defect. Thin-source validation run `41419295577` succeeded.
Linux run `41419295505` failed in both shared and static staged consumers because
`core/version.hpp` declares `std::map` without including `<map>` and the expanded
runtime-version smoke consumer included that header directly. Windows run
`41419295499` likewise reached the staged SDK consumer after its build,
refinement, Catch, install, audit, and metadata steps had passed, then failed at
that consumer step. The consumer fixtures now include `<map>` before
`core/version.hpp`; the exact Windows compiler message from the superseded run was
not retained and is not inferred here.

That fix produced second full-source transition candidate
`65517caa5974454f65225fa1666f61516a9706fc`. Its thin-source validation run
`41420297382` succeeded, and Linux run `41420297413` proved both shared and static
producer jobs successful, including source reconstruction and the in-producer SDK
qualification. The subsequent Ubuntu compatibility-consumer matrix then exposed
a second retained-fixture issue: the new call to `ngcore::GetLibraryVersion`
failed to link from an external consumer. Explicitly linking exported target
`ngcore` in addition to `nglib` produced third transition candidate
`2cc1c15a8b04ac4edd70ae2c7d5c54e98448dd6f`; its Thin Netgen source validation
run `41421548232` succeeded and both Linux producer jobs in run `41421548401`
succeeded, but Ubuntu 20.04 and 24.04 shared compatibility consumers still failed
with the same undefined `GetLibraryVersion` reference. Direct inspection of the
produced shared SDK showed that `nglib` already transitively links `ngcore`, while
`libngcore.so` exports `GetLibraryVersion(std::string const&)` using the old
libstdc++ string ABI and the Ubuntu consumers compiled the call with the new
`std::__cxx11::basic_string` ABI. This was therefore an ABI-crossing test defect,
not a missing library dependency. The producer/relocated consumer still checks
the runtime version in its ABI-matched producer environment; only the cross-distro
Linux compatibility matrix disables that C++ runtime-version call while retaining
the installed CMake version assertion and C API build/run smoke. The superseded
Windows run `41421548228` was cancelled; Linux run `41421548401` completed with
failure from its compatibility matrix and macOS run `41421548217` was cancelled.

The current full-source transition qualification target is therefore
`ef3d4e2bfee116a0346e40f6c163b6174bbce4c0`. Its push-triggered qualification
runs are Windows `41423168236`, Linux `41423168157`, macOS `41423168204`, and
Thin Netgen source validation `41423168143`. Windows completed successfully with
both shared and static producer/consumer qualification jobs green. Linux completed
successfully with shared/static producers plus all Ubuntu 20.04, 22.04, and 24.04
shared/static compatibility-consumer jobs green. Thin-source validation also
succeeded. The first macOS attempt completed both x86_64 shared/static jobs but a
queued arm64 job was cancelled by GitHub with the annotation that no hosted runner
acquired it after multiple attempts and that macOS arm64 capacity was constrained;
this was runner-capacity evidence, not a source/build failure. GitHub reruns of the
same push run eventually completed as attempt 4, with all four x86_64/arm64
shared/static jobs successful. The transition branch qualification matrix is
therefore fully green at the exact `ef3d4e2b` producer commit.
The rebased unpublished thin-tree commit on top is
`b939fba93d8d911e79f3c9e96a686ce10888715b`.

Local non-build validation of that committed thin tree passes the 12 focused
Python contract fixtures, `git diff --check`, Bash syntax checks, and workflow
YAML parsing. The active tree contains 44 files; under `tests/` only the two
repository-owned native SDK consumer fixtures remain. The removed upstream source,
build, Python, GUI, tutorial, upstream-test, and settled root-only paths are absent.
The manifest and patch inputs are not ignored, every patch/series file resolves to
`eol: lf`, and the only retained `fetch-depth: 0` is the OCCT automation checkout
whose full producer-branch history is still required for its merge-safety logic.
A fresh non-build source preparation from the committed thin tree also succeeded,
resolving semantic version `6.2.2608`, deterministic version identity
`v6.2.2608-0-g96e5682f6ea4`, and the ordered patch SHA-256 values recorded by the
preparation script; its disposable reconstructed checkout was removed afterward.
An independent read-only review of exact thin-tree HEAD `b939fba9` found no
material acceptance defect in the active-tree disposition, manifest/version
single-source contract, producer reconstruction paths, retained SDK consumers,
qualification lookup, or combined-release verifier. The pending remote gates were
left as validation work rather than treated as implementation defects.

The positive exact-SHA automation path also succeeded against the same transition
commit using temporary ref `automation/occt-qualify-ef3d4e2bfee1`. Its
workflow-dispatch runs are Windows `41471922388`, Linux `41471929802`, and macOS
`41471936777`. Windows completed shared/static qualification successfully. Linux
completed shared/static production plus every Ubuntu 20.04, 22.04, and 24.04
shared/static compatibility consumer successfully. macOS completed both x86_64
linkages and both arm64 linkages successfully on attempt 9. Earlier failed-only
reruns were cancelled after 15 minutes when GitHub never assigned a hosted arm64
runner; those attempts executed no failing build/test step and were annotated as
macOS arm64 capacity constraints. The temporary ref was then deleted. Running the
real release-eligibility lookup after deletion accepted the exact-SHA dispatches
and returned Windows `41471922388`, Linux `41471929802`, and macOS `41471936777`,
establishing that eligibility is bound to the immutable producer SHA and successful
workflow results rather than continued existence of the temporary ref.

The final active-tree deletion was initially unpublished. Non-publishing combined
release workflow-dispatch run `41493354033` at exact transition SHA
`ef3d4e2bfee116a0346e40f6c163b6174bbce4c0` initially completed with failure
because the macOS arm64 static producer never acquired a hosted runner and was
cancelled before executing any step; all jobs that did execute were successful,
and the dependent combined verifier was skipped. A failed-job rerun on the same
workflow run and exact SHA completed as attempt 5. The macOS arm64 static producer
then built, qualified, and uploaded successfully, after which the combined job
downloaded all eight SDK archives and passed the exact inventory/provenance
verification. Its publication-tag and release-creation steps were skipped as
required by `publish_release=false`. The non-publishing combined release gate is
therefore satisfied.

Thin-tree commit `b939fba93d8d911e79f3c9e96a686ce10888715b` was then pushed
to `origin/netgen-featool`. Its push-triggered Thin Netgen source validation run
`41553064999` succeeded, and Windows qualification run `41553064992` succeeded
on its first attempt with both shared and static producer/consumer qualification
green. Starting the required non-publishing combined release run while the
push-triggered Linux and macOS runs were still active caused those two branch-ref
concurrency groups to cancel their original attempts. This was a workflow
sequencing interaction rather than a build failure. After the combined run's
reusable Linux/macOS jobs had completed, the cancelled push runs were rerun.
Linux run `41553064987` attempt 2 succeeded with shared/static production and all
Ubuntu 20.04, 22.04, and 24.04 shared/static compatibility consumers green.
macOS run `41553064996` attempt 2 succeeded with all x86_64/arm64 shared/static
jobs green.

Non-publishing combined release workflow-dispatch run `41553132397` at exact
thin-tree SHA `b939fba93d8d911e79f3c9e96a686ce10888715b` also succeeded. Its
Windows shared/static, Linux shared/static plus compatibility consumers, and all
four macOS architecture/linkage producer jobs succeeded; the final combined job
downloaded and verified the complete eight-archive inventory and provenance, while
publication-tag and release-creation steps were skipped as required by
`publish_release=false`. A final local non-build check of the published thin tree
passed the 12 focused Python contract fixtures, `git diff --check`, Bash syntax
checks, PowerShell parsing, and workflow YAML loading. The implementation,
producer/runtime qualification, release-verification acceptance, and plan review
requirements are therefore complete.
