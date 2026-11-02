# FEATool Netgen native SDK producer

This repository is a thin build and release producer for the FEATool Netgen
native SDKs. It does not keep an editable checkout of the complete Netgen source
tree in the active branch.

The source built by GitHub Actions is reconstructed from two repository-owned
inputs:

- `upstream/netgen.json` pins the canonical NGSolve Netgen repository, release
  tag, and exact full commit SHA.
- `patches/netgen/series` lists the FEATool patch files in the exact order in
  which they are validated and applied.

`scripts/prepare-netgen-source.py` shallow-fetches the configured upstream tag,
verifies that it resolves to the pinned commit, applies the canonical LF patch
series, checks the resulting diff, and writes `source-provenance.json`. Windows,
Linux, and macOS producers all build from that reconstructed source and record
the upstream identity plus ordered patch SHA-256 values in each SDK archive.

The active tree primarily contains:

- `.github/` producer, qualification, OCCT-update, and release automation;
- `patches/netgen/` and `upstream/netgen.json` source-reconstruction inputs;
- `scripts/` source, provenance, and release validation helpers;
- `tests/windows-native-sdk/` and `tests/unix-native-sdk/` external SDK consumer
  fixtures;
- `plans/` engineering plans and execution records;
- `AUTHORS` and `LICENSE` attribution/licensing material.

All Netgen compilation and runtime qualification is performed by GitHub Actions.
The release process and upstream-port procedure are documented in
`.github/README.md`.

Historical Git objects and release tags still contain the old full source fork
by design. Reducing physical Git history or clone storage is a separate repository
migration and is not part of the thin active-tree model.

