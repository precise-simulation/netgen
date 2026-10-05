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

This checkout contains the Netgen 6.x mesh generator, native libraries, command-line
and GUI executable, and Python bindings. Inspect the current source and build options
before relying on upstream documentation, historical branches, or old build recipes.

- `libsrc/`: core containers, geometry kernels, meshing algorithms, import/export,
  OpenCascade support, and the native meshing implementation.
- `nglib/`: public native library interface used by embedded/downstream consumers.
- `ng/`: Netgen executable and GUI integration.
- `python/`: Python bindings and package support for `netgen` and `pyngcore`.
- `tests/catch/`: C++ Catch-based unit tests, enabled with `ENABLE_UNIT_TESTS=ON`.
- `tests/pytest/`: Python integration and meshing tests; slow cases require the
  pytest `--runslow` option.
- `CMakeLists.txt` and `cmake/SuperBuild.cmake`: primary native build definitions.
  The superbuild is enabled by default and configures the real Netgen project in a
  nested `netgen` build directory.
- `setup.py`: scikit-build packaging path for the Python wheel, using the CMake
  superbuild and the separately packaged OpenCascade dependency.
- `.gitlab-ci.yml` and `tests/build_*`: current platform build/test examples; treat
  them as environment-specific references rather than universally portable commands.
- `external_dependencies/pybind11`: git submodule used by Python-enabled builds.
- `plans/`: proposals and execution records, governed by `plans/AGENTS.md`.

### Compatibility and ownership

- Preserve public C++, `nglib`, Python, CLI, file-format, and mesh semantics unless
  the task explicitly changes their contract.
- Preserve geometric and meshing meaning, including topology, entity/region and
  boundary mappings, orientation, connectivity, element types, units, and tolerances.
- Account for affected optional profiles such as `USE_OCC`, `USE_GUI`, `USE_PYTHON`,
  `USE_MPI`, `USE_CGNS`, and `ENABLE_UNIT_TESTS`; do not assume one profile proves
  another configuration works.
- Keep compiler, architecture, C/C++ runtime, Python ABI, OpenCascade, Tcl/Tk, zlib,
  and downstream native consumers compatible across binary boundaries. On Windows,
  do not mix MinGW and MSVC artifacts or incompatible MSVC runtime-library choices.
- Keep dependency pins and producer settings in their owning CMake, packaging, CI,
  or migration-plan files. A target version in a draft plan is not proof that the
  corresponding native artifacts have been built or qualified.
- Changes in sibling repositories or downstream consumers must follow their own
  instructions and the authorized task scope.

### Build and validation

- Inspect the current CMake options, installed dependencies, compiler, Python, and
  target architecture before choosing commands. Use explicit executable paths when
  tool identity matters and record the build profile actually validated.
- Prefer an out-of-source CMake build. `USE_SUPERBUILD=ON` is the default; with it,
  dependency setup happens in the outer build and the actual Netgen project is built
  under `<build>/netgen`. Run Netgen's CTest checks from that nested build directory.
  A `USE_SUPERBUILD=OFF` build is a different profile and requires its dependencies
  to be supplied directly.
- Initialize `external_dependencies/pybind11` for Python-enabled builds when needed.
  Do not assume a source checkout has populated submodules merely because CMake can
  attempt to update them automatically.
- Match dependencies to the feature under test. `USE_OCC=ON` requires a compatible
  OpenCascade installation or `BUILD_OCC=ON`; GUI builds require Tcl/Tk; Python builds
  require the selected Python interpreter/development ABI. `BUILD_ZLIB` and other
  superbuild dependency choices are part of the build identity when they affect a
  produced binary.
- On Windows, use one coherent MSVC toolchain and runtime across Netgen and native
  dependencies. Record architecture, configuration, generator/compiler, and runtime
  choice when qualifying distributable or downstream-consumed libraries.
- Enable `ENABLE_UNIT_TESTS=ON` when validating affected C++ unit-test coverage.
  CTest registers the Catch tests as `unit_*` and also registers pytest when
  `USE_PYTHON=ON`; use `ctest -R <pattern> --output-on-failure` for focused checks.
  Pass the configuration (for example `-C Release`) when using a multi-config build.
- For direct Python tests, use the Python interpreter and Netgen package produced by
  the build being validated. Install the test-only dependencies required by the
  selected tests (for example `pytest-check`) and do not count tests skipped because
  an optional module such as OCC, NGSolve, MPI, or mpi4py is absent as validation of
  that integration.
- The pytest suite skips tests marked `slow` unless invoked with `--runslow`. MPI
  coverage is registered separately only when the corresponding MPI/Python support
  is enabled. Run these profiles only when the change affects them.
- For meshing or geometry changes, exercise the actual affected generator/import path
  on representative geometry and verify mesh validity plus the relevant element
  types, connectivity, region/material and boundary mappings, and geometric meaning.
  For OCC changes, use the real OpenCascade integration rather than a substitute path.
- For native interface or packaging changes, validate the produced library/package
  through the affected consumer surface (`nglib`, Python import, executable, or wheel)
  in addition to compiling it. Wheel builds through `setup.py` use scikit-build and
  have dependency assumptions that differ from a plain native CMake build.
- Compare semantic results within justified tolerances. Require identical bytes,
  entity numbering, or mesh ordering only where the existing contract requires it.
- Proposed scripts in draft plans are not available validation commands until
  implemented. Report unavailable compilers, dependencies, runtimes, or optional
  integrations as validation gaps.
- Documentation and plan-only changes need no native build or runtime tests.

### Plan validation

This checkout currently has no repository-local plan metadata validator. Until
one is added, inspect frontmatter, references, dependency/containment cycles,
status consistency, and repository-relative affected paths directly, following
`plans/AGENTS.md`. Report whether checks were manual or automated. Do not make
this repository depend on a script in another checkout.
