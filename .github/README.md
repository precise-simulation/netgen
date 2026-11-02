# Netgen native SDK workflows

This repository is the thin producer for FEATool Netgen native SDKs. The active
branch owns release automation, source pins, FEATool patches, and external native
SDK consumer tests. It does not own a checked-in copy of the upstream Netgen
source tree.

## Source identity

`upstream/netgen.json` is the only executable Netgen baseline pin. It records the
canonical NGSolve repository, release tag, and full commit SHA. Do not duplicate
the current tag, SHA, or semantic version in platform workflows or build scripts.

`patches/netgen/series` is the authoritative ordered FEATool patch list. Every
listed patch must exist exactly once, every `*.patch` file must be listed exactly
once, and patch/series bytes must use LF line endings. Their exact SHA-256 values
are release provenance.

Every producer invokes `scripts/prepare-netgen-source.py` into a fresh runner
temporary directory. The helper:

1. validates `upstream/netgen.json`;
2. shallow-fetches only the configured upstream release tag;
3. requires the tag to resolve to the configured full commit;
4. checks out that commit detached;
5. validates, hashes, checks, and applies each patch in `series` order;
6. runs `git diff --check`; and
7. writes runner-owned `source-provenance.json`.

The deterministic CMake version identity is derived from the manifest as
`<tag>-0-g<upstream-sha12>` and passed through `NETGEN_VERSION_GIT`. The public
Netgen semantic version therefore stays aligned with the upstream release while
the exact FEATool reconstruction is identified by the producer commit, full
upstream commit, and ordered patch hashes.

## Producer workflows

The supported producer workflows are:

- `workflows/windows-netgen-sdk.yml`: Windows x64 Visual Studio 2022 shared and
  static SDKs using the `/MD` runtime contract;
- `workflows/linux-netgen-sdk.yml`: Linux x86_64 shared and static SDKs using the
  pinned manylinux2014/GCC 10 compatibility profile;
- `workflows/macos-netgen-sdk.yml`: macOS x86_64 and arm64 shared/static SDKs with
  the pinned Xcode and macOS deployment-target profile.

All three workflows shallow-checkout the producer revision, reconstruct Netgen in
runner temporary storage, and build only from that staged source. Repository-owned
consumer fixtures remain under `tests/windows-native-sdk/` and
`tests/unix-native-sdk/`; they are never copied into the reconstructed source.

The platform build profiles continue to run Netgen's patched Catch regression
surface, including the triangle-to-three-quads and ordinary quad-refinement
cases. The external SDK consumers additionally require the installed
`NetgenConfig.cmake` semantic version and the runtime Netgen library version to
match the manifest-derived release version.

No Netgen compilation is performed on maintainers' local hosts for this
repository. Build and runtime qualification belong on GitHub Actions runners.

## Immutable OCCT input

`.github/occt-sdk-release.txt` pins one immutable `precise-simulation/OCCT`
release tag. `.github/resolve-occt-release.py` resolves the platform/linkage asset
from that release and verifies its immutable release metadata, asset identity,
size, URL, and SHA-256 digest. The full OCCT source commit is read from the SDK's
embedded manifest and carried into Netgen `producer-info.json`.

The Windows shared/static, Linux shared/static, and macOS shared/static producers
retain their existing OCCT and zlib linkage, relocation, toolchain, and runtime
checks. Changing the thin source model does not weaken those package contracts.

## Producer provenance

Every SDK archive contains `producer-info.json` schema version 2. Its source
identity includes:

```json
{
  "schema_version": 2,
  "upstream": {
    "repository": "<canonical upstream repository>",
    "tag": "<upstream release tag>",
    "commit": "<full upstream commit>",
    "version_git": "<deterministic Netgen version identity>",
    "version": "<semantic Netgen version>"
  },
  "source": {
    "repository": "<producer repository>",
    "ref": "<producer ref>",
    "commit": "<full producer commit>",
    "patches": [
      {"path": "patches/netgen/<patch>.patch", "sha256": "<exact patch hash>"}
    ]
  }
}
```

Platform-specific toolchain, Netgen linkage, OCCT/zlib identity, workflow
qualification identifiers, and artifact hashes remain in the same metadata.

## Qualification and release

A push to `netgen-featool` runs the three platform qualification workflows for
that exact producer commit. A successful qualification is release-eligible when
it is either a successful branch-push run for that exact SHA or a successful
`workflow_dispatch` run for that exact SHA, such as the temporary immutable ref
used by OCCT automation.

For release-tag builds, `scripts/check-release-qualification.py` uses GitHub's
workflow-run API plus the compare API. It requires an accepted successful run for
the exact producer SHA and requires that commit to be identical to or contained
in the current `netgen-featool` line. Producer jobs therefore do not fetch the old
full fork history merely to prove ancestry.

`workflows/release-netgen-sdk.yml` always runs all three producer workflows and
downloads the complete eight-archive inventory. Its combined verification runs
for both manual dispatches and release tags. `scripts/verify-netgen-sdk-release.py`
requires matching schema-v2 producer identity, upstream identity, ordered patch
hashes, OCCT identity, linkage, and checksum sidecars across the same bytes that
would be published.

A normal `workflow_dispatch` with `publish_release=false` is the non-publishing
combined qualification path. It must finish after all eight archives pass the
shared verifier and must not create a tag or release.

Publishing uses an immutable tag of the form:

```text
netgen-sdk-<producer-sha12>-rN
```

For an eligible tag run, release creation/upload occurs only after the same
downloaded archive set has passed the combined verifier. A failed or superseded
attempt for the same producer revision uses the next `rN`; do not move an
existing release tag.

## Automatic OCCT SDK updates

`workflows/auto-occt-netgen-release.yml` and
`.github/auto-occt-netgen-release.sh` retain the current coordinator contract.
When a newer immutable OCCT SDK release is selected, automation updates only
`.github/occt-sdk-release.txt`, qualifies the exact update commit, merges it into
`netgen-featool`, qualifies the exact merge commit through a temporary ref,
removes that ref, and then drives the combined Netgen SDK release flow.

The release-eligibility lookup is intentionally SHA-based, so a successful
workflow-dispatch qualification remains valid after the temporary ref is deleted.
The coordinator's local Git history operations are still required for its branch
update/merge safety checks; those are independent of the removed upstream-Netgen
ancestry gate.

## Updating the Netgen baseline

Do not merge a new upstream Netgen tag into `netgen-featool`. Port the thin source
definition instead:

1. Select an exact canonical NGSolve Netgen release tag and resolve its full
   commit SHA.
2. Update only `upstream/netgen.json` for the new upstream identity.
3. Run source preparation and identify which FEATool patches no longer apply.
4. Rebase the repository-owned patches onto the new release, preserving the
   triangle-to-quad regression and `NETGEN_NATIVE_SDK` package behavior. Keep the
   logical patch groups separate unless a real dependency requires another order.
5. Inspect upstream CMake/OCC/native-interface changes for dependency, ABI,
   compiler, runtime, and package-export effects.
6. Ensure artifact names, deterministic version identity, producer metadata, and
   release verification all derive from the updated manifest; do not add a second
   version or SHA constant.
7. Push one coherent producer commit and require Windows, Linux, and macOS
   qualification for that exact SHA.
8. Run the non-publishing combined release verification before creating a new
   `netgen-sdk-<producer-sha12>-rN` tag.

An upstream port is complete only when the manifest, ordered patch set, generated
version metadata, SDK consumer version checks, producer provenance, and all three
qualification workflows agree on the same source reconstruction.

For an OCCT-only update, change `.github/occt-sdk-release.txt` to an already
published immutable compatible OCCT SDK release and run the same producer and
combined release qualifications. Do not change the Netgen manifest unless the
Netgen baseline itself changes.

## Repository history

The active branch is thin, but historical commits and existing release tags still
contain the old complete Netgen fork. That history is retained for provenance.
Removing historical objects or reducing full-clone storage requires a separate
repository/history migration; it is not part of routine upstream ports or SDK
releases.
