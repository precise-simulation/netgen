This is a local copy of the
https://github.com/precise-simulation/netgen fork for building release
artifacts.

No local/host compilation is allowed unless explicitly asked.

All building, compilation, and implementation should be performed on the
remote GitHub Actions workflows/runners.

# Development instructions

These instructions apply to the entire repository unless a nested
`AGENTS.md` or `AGENTS.override.md` provides more specific guidance.

Keep every `AGENTS.md` and `AGENTS.override.md` in this repository LF-only.

The development, validation, and review principles below are reusable across
projects. The repository profile records this checkout's technical requirements.

## Match the process to the task

Select the task from the user's request; combine tasks only when requested.

| Task | Permitted changes | Completion |
| --- | --- | --- |
| Planning | Planning documents only; inspect relevant source to ground decisions. | Scope, behavior, key decisions, and acceptance criteria are implementable. |
| Coding | Source and supporting tests, documentation, or metadata needed for the requested change. | Requested behavior and required focused validation are complete; report any remaining gaps. |
| Review code | Read-only unless corrections are requested. | Report evidenced defects, regressions, and unmet requirements, or no material findings. |
| Review plan | Read-only unless corrections are requested. | Assess feasibility, scope, decisions, dependencies, and validation; report material gaps or readiness. |
| Investigate / explain | Read-only unless changes are requested. | Answer the question with supporting evidence and remaining uncertainty. |

For a small, well-scoped change:

1. Inspect the implementation and affected callers.
2. Make the smallest coherent change.
3. Run the smallest relevant validation.
4. Report the result.

Do not create a plan, delegate work, add abstractions, add files, or add tests
unless they materially help establish correctness.

Use formal planning for substantial changes where ordering, design choices,
compatibility, or validation need to be established before implementation.
File count alone does not justify formal planning.
When creating, reviewing, or implementing a plan, also read `plans/AGENTS.md`.

Use one main agent for implementation and corrections. Use independent
reviewers when they materially improve confidence in an architectural,
compatibility-sensitive, numerical, or otherwise high-risk change.
Reviewers should remain read-only.

Continue within the authorized scope without routine confirmation. Ask only
when an unresolved decision materially changes requirements or behavior.

## Implementation principles

Before choosing a solution, understand the task and trace the affected execution
path. For development on existing code, apply these priorities in order:

1. Preserve the public API, including signatures, defaults, data layouts, and
   documented behavior, unless the user explicitly requests an API change.
2. Do not change code when the requested behavior is already satisfied; verify
   it and report the evidence. When a change is required, prefer the smallest
   coherent diff that establishes the requested behavior and its correctness.
3. Reuse an existing implementation, helper, or established pattern.
4. Use compatible language, standard-library, or platform functionality.
5. Use an existing dependency where appropriate.
6. Add only the smallest clear custom implementation that meets the requirement.

Implement the smallest complete solution for the stated operating conditions.
Treat diff size as a constraint: prefer fewer changed lines, files, APIs, and
mechanisms when correctness, clarity, and required behavior are otherwise equal.
Do not refactor, generalize, or expand interfaces merely for internal uniformity
or future use cases. Avoid unrelated cleanup and broad formatting changes.

During implementation, check consequential assumptions when they influence a
change. For a changed contract, inspect affected producers and consumers; for
changed state or side effects, inspect relevant failure and cleanup paths; for
validation, confirm that the check exercises the behavior claimed. Use evidence
from supported inputs and reachable states. Resolve issues revealed by these
checks before handing off; do not defer known defects to independent review.
Disclose any blocked verification explicitly. Keep this proportional to the
change and record only material conclusions or remaining uncertainty in the
existing plan, progress update, or handoff.

Before adding an abstraction, persistent state, configuration, dependency,
fallback, recovery mechanism, or cross-cutting change, briefly identify the
current requirement or concrete failure that makes the simpler approach
insufficient. General claims of robustness or future flexibility are not enough;
use the task update or existing plan, not a separate justification document.

If a small task spreads into additional subsystems, reconsider the approach and
scope before extending it. First seek a narrower solution within the authorized
requirements; do not weaken required behavior or add a routine approval gate.
Do not silently promote agent-suggested guarantees or future use cases into
requirements.

- For bug fixes, identify the root cause and inspect affected callers before
  choosing the fix location. Prefer one fix at the shared boundary when it
  correctly covers the affected paths.
- Match the surrounding source style and update affected help text.
- Preserve domain meaning, data invariants, units, indexing, and tolerances.
  Apply the repository-specific compatibility rules below.
- Do not weaken assertions, loosen tolerances, or replace reference results
  merely to make a failing test pass.
- Edit generator inputs or generators rather than patching generated output.
  Regenerate affected artifacts when required by the task.
- Preserve unrelated user changes.

## Validation

Choose validation proportional to the change.

For source changes:

1. Select the applicable build and checks using the repository profile below.
2. Run the smallest affected existing test, suite, or selector.
3. Add a focused regression test only when it materially protects changed
   nontrivial behavior.

Do not run the full test suite unless the user explicitly requests it.

Documentation, plans, metadata, and similar non-code changes do not require
runtime tests unless they affect generated or executable behavior.

Inspect test results and failure summaries. A successful process exit or
the runner printing `DONE` alone does not establish that tests passed.

Derive expected behavior from the requirements and existing compatibility contract,
not only from the new implementation. For each critical changed behavior, verify
that its check exercises the boundary being claimed and would detect a plausible
incorrect implementation. A test that injects final state or mocks an adapter does
not validate the bypassed user-input, conversion, or integration path. Use focused
cases from supported inputs and reachable states rather than adding blanket tests.

Validate changed user-facing behavior through the affected interface. Validate
native and external integration paths with their actual dependencies.

If a required runtime or dependency is unavailable, report validation as
blocked or incomplete rather than silently substituting another environment.

Honor explicit source-only or no-test instructions.

## Review

Before requesting independent review of substantial work, the author must check
the complete agreed scope against the current artifact. For implementation, map
critical acceptance cases to the responsible code and checks actually run; for
plans, follow the author check in `plans/AGENTS.md`. Resolve known defects and
contradictions first, and disclose remaining assumptions or validation gaps. Use
the existing plan/progress section or handoff message; do not create a separate
review dossier. Passing available tests does not replace this contract check.

Reviews should focus on material issues:

- incorrect behavior
- regressions
- compatibility problems
- unmet requirements
- unsafe state or cleanup behavior
- validation gaps that could allow the intended failure to recur

Review findings must identify the location, consequence, supporting evidence,
and triggering condition within the agreed operating conditions, or a
demonstrably unnecessary mechanism. Distinguish defects against the agreed
contract from proposals to expand it. A stronger guarantee is a scope proposal,
not a blocking defect unless required by the user's request or an existing
compatibility contract; do not silently add it to acceptance criteria.

Do not report style preferences, speculative hardening, or alternative designs
without a concrete failure mode or demonstrably unnecessary complexity.
For code and plan reviews, recommend removal only when evidence shows that it
preserves requested behavior and required contracts. Keep findings within the
reviewed scope; do not turn reviews into general cleanup.

If there are no material findings, say so and finish.

Review the complete agreed scope and report the material findings together,
including any portion not inspected. Identify the revision or working-tree state
reviewed; do not treat a review of an earlier artifact as validation of later edits.
Keep required corrections distinct from optional proposals under the rules above.

When corrections are authorized, triage the full report before editing. Fix the
root cause and check directly related cases within the affected paths, rather than
patching only the reported example. Validate the correction and report how each
finding was resolved or why evidence does not support it. If it changes an agreed
requirement, update the plan's contract and acceptance criteria explicitly.

Follow-up review should verify the corrections, their affected paths, and any
previously unreviewed agreed scope. Report newly evidenced material defects, but
do not restart architectural preference discussions or add stronger requirements
without a concrete contract basis. Additional full-scope review is warranted only
when the correction changes the design or invalidates earlier review coverage.

Do not continue review/correction cycles after the requested behavior is
established unless a material issue remains.

## Completion

Before handing back work, make one pass over the task's additions for mechanisms
whose removal preserves required behavior and compatibility. Remove those that
are demonstrably unnecessary, and run the affected checks after any corrections.
Inspect the final changes for unintended edits. Once the requested behavior and
required validation are complete, stop unless a material issue remains; do not
start an open-ended simplification or review cycle.
Report concisely:

- What changed and why.
- Checks actually run, runtime versions, and results.
- Remaining material findings, skipped checks, and blockers.

Claim only the level of validation actually performed.

## Repository profile: Netgen

This checkout is a thin producer for FEATool Netgen native SDK release artifacts.
The active branch does not contain the full upstream Netgen source tree. GitHub
Actions reconstructs the exact source from a pinned canonical upstream release and
an ordered repository-owned patch set before each build.

- `upstream/netgen.json`: the only executable Netgen upstream repository/tag/full
  commit pin.
- `patches/netgen/series`: authoritative patch order; every listed patch must exist
  exactly once and every `*.patch` file must be listed exactly once.
- `scripts/prepare-netgen-source.py`: validates the manifest and LF patch bytes,
  shallow-fetches the exact upstream tag, verifies its commit, applies the ordered
  patch set, checks the result, and writes source provenance.
- `scripts/netgen_source.py`: shared manifest, patch, version, and provenance logic.
- `scripts/check-release-qualification.py`: exact-SHA workflow qualification and
  GitHub compare-API branch-containment decision.
- `scripts/verify-netgen-sdk-release.py`: combined eight-archive release verifier.
- `tests/windows-native-sdk/` and `tests/unix-native-sdk/`: repository-owned
  external SDK consumer fixtures. These are not copied into reconstructed source.
- `.github/`: platform producer, OCCT update, combined qualification, and release
  automation. `.github/README.md` is the release/upstream-port procedure.
- `plans/`: proposals and execution records, governed by `plans/AGENTS.md`.

Historical Git objects and release tags still contain the old full source fork by
design. Do not treat their presence in history as active source ownership.

### Compatibility and ownership

- Preserve the public native SDK behavior represented by the reconstructed Netgen
  source unless the task explicitly changes that contract. This includes geometry,
  meshing, topology, connectivity, entity/region and boundary mappings, units,
  tolerances, and exported native interfaces affected by repository patches.
- Preserve the current Windows, Linux, and macOS toolchain, runtime, architecture,
  OpenCascade, zlib, linkage, relocation, and archive contracts unless the task
  explicitly changes them. On Windows, keep one coherent MSVC toolchain/runtime.
- Keep source identity in `upstream/netgen.json` and `patches/netgen/`; do not add
  independent current-baseline tag, SHA, or semantic-version constants to platform
  workflows, producer scripts, or release logic.
- Patch hashes are release provenance. Preserve canonical LF bytes in
  `patches/netgen/*.patch` and `patches/netgen/series`.
- Catch regressions that must run inside Netgen belong in the patch set. External
  SDK consumer fixtures belong in this repository's retained native test folders.
- Keep OCCT release identity in `.github/occt-sdk-release.txt` and platform producer
  settings in their owning workflow/build scripts.
- Changes in sibling repositories or downstream consumers must follow their own
  instructions and the authorized task scope.

### Upstream release ports

- Follow `.github/README.md`. Do not merge an upstream Netgen release tag into the
  active producer branch. Select the exact canonical tag/commit in
  `upstream/netgen.json`, then rebase only the repository-owned patches needed by
  FEATool onto that baseline.
- Preserve the triangle-to-quad behavior/regression, native SDK CMake/export
  contract, and any other still-required patch behavior while adapting patches to
  upstream API changes.
- Inspect upstream changes that affect native interfaces, OpenCascade integration,
  compiler/runtime requirements, package exports, or dependency compatibility.
- Update one coherent producer revision and require the documented Windows, Linux,
  and macOS qualification plus non-publishing combined release verification before
  creating an SDK release tag.

### Build and validation

- Do not compile or build Netgen on the local host. Platform builds, Catch runtime
  tests, relocation checks, and native SDK consumer builds/runs execute on GitHub
  Actions runners through the repository workflows.
- Local non-build validation may inspect files, run Python contract fixtures,
  validate YAML/shell/PowerShell syntax, reconstruct source for content inspection,
  run `git apply --check`/`git diff --check`, and audit manifest/patch provenance.
- All producers must call `scripts/prepare-netgen-source.py` and pass the resulting
  manifest-derived `NETGEN_VERSION_GIT` to CMake. A staged patched checkout's
  `git describe --dirty` is not a valid public version identity.
- When producer behavior changes, qualify the actual affected platform profile and
  native consumer surface. Do not treat source reconstruction or static syntax
  checks as evidence that a Windows/Linux/macOS SDK compiled or ran successfully.
- Release changes require the same combined archive verifier used by publication.
  A non-publishing `release-netgen-sdk.yml` dispatch is the supported end-to-end
  combined verification path.
- Release-tag eligibility remains exact-SHA based. Accepted qualification is a
  successful `netgen-featool` branch push or exact-SHA workflow dispatch plus
  compare-API containment in the current branch line; do not reintroduce a deep
  checkout of historical fork ancestry for this decision.
- Auto-OCCT coordination may retain full producer-branch history where its merge
  safety algorithm requires it. That is separate from Netgen upstream provenance.
- Compare semantic results within justified tolerances. Require identical bytes,
  entity numbering, or mesh ordering only where the existing contract requires it.
- Report unavailable runners, external dependencies, workflow permissions, or
  blocked GitHub integration as validation gaps rather than substituting a local
  native build.
- Documentation and plan-only changes need no native build or runtime tests.

### Plan validation

This checkout currently has no repository-local plan metadata validator. Until
one is added, inspect frontmatter, references, dependency/containment cycles,
status consistency, and repository-relative affected paths directly, following
`plans/AGENTS.md`. Report whether checks were manual or automated. Do not make
this repository depend on a script in another checkout.
