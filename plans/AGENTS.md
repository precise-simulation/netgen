# Plan organization and lifecycle

These instructions supplement the [root development instructions](../AGENTS.md).
Use the root rules to decide whether a plan or independent review is needed;
creating a plan does not itself require another agent or a review cycle.

## Organization

- A **plan** is one coherent, independently implementable and verifiable task.
  Keep required source, test, documentation, and manifest changes together;
  do not split work by file count or agent session length.
- An **epic** coordinates multiple plans with sequencing or shared invariants.
  Keep shared contracts and integration criteria in the epic, local decisions
  in child plans, and list every required child in `children`.
- Store plans under `plans/draft/`, `plans/ready/`, `plans/in-progress/`,
  `plans/blocked/`, `plans/deferred/`, or `plans/done/`. The first directory
  below `plans/` is the status; do not repeat it in frontmatter. Topic
  subdirectories may appear below a status directory.
- Keep filenames unique and stable. Dependencies and epic children refer to
  filenames so status moves do not change identity. Repair affected links
  when moving plans. Don't include `plan` in the filename, like `example-plan.md`.
- `AGENTS.md` is the only Markdown file that belongs directly under `plans/`;
  every plan and epic belongs below a status directory.

## Repository integration

Read the root instructions for repository structure, compatibility requirements,
version-control rules, and build and validation commands. Plans describe intended
changes; they do not establish that a capability, command, dependency, or
validation facility already exists.

Before selecting or changing plan work, and after changing plan metadata or
locations, use the repository's documented plan validator when available.
Otherwise inspect metadata, references, dependency/containment cycles, affected
paths, and lifecycle consistency directly. Report the method and its limitations;
metadata validation does not establish design correctness or implementation.

Keep platform versions, dependency pins, and executable commands in the owning
build configuration or repository instructions. Include them in a plan when
changing them is part of the task.

## Frontmatter

Every plan and epic starts with exactly these fields:

```yaml
---
kind: plan
title: Short display title
summary: One sentence describing the delivered outcome.
area: subsystem-name
priority: P2
depends_on:
  - prerequisite.md
children: []
affected_files:
  - src/component.ext
  - test/component_test.*
---
```

- `kind` is `plan` or `epic`; `title` and `summary` are single-line display text.
- `area` is lowercase kebab-case, such as `gui`, `modeling`, or `testing`.
- `priority` is `P0` (blocking repository work), `P1` (high), `P2` (normal,
  default), or `P3` (low). Priority expresses urgency, not difficulty.
- `depends_on` lists unique prerequisite filenames; use `[]` for none.
- `children` is `[]` for a plan and a nonempty list of unique child filenames
  for an epic. Dependency and containment references must exist, exclude
  self-references, and each form an acyclic graph.
- `affected_files` contains expected repository-relative paths or narrow globs
  using forward slashes. It supports coordination without prohibiting necessary
  caller, generator, or test changes discovered later. Put external paths in
  the body instead. Use `[]` when no files in this repository are expected to
  change, and identify the external owner and scope in the body.

Use only this compact YAML subset: no aliases, folded text,
inline maps, or additional frontmatter keys.

## Content and planning depth

After frontmatter, cover these five essentials with only as much detail as
needed. Combine headings or omit inapplicable material; add sections only when
useful.

1. **Goal and scope:** the observable outcome, intended operating conditions,
   and meaningful exclusions.
2. **Necessary decisions:** public behavior, numerical invariants, defaults,
   error behavior, compatibility, ownership, and dependencies where relevant.
3. **Ordered changes:** concrete steps and the behavior or surfaces affected.
4. **Acceptance and validation:** checkable outcomes, appropriate focused
   checks, required hosts/dependencies, and the evidence that establishes them.
5. **Progress and evidence:** completed work, remaining work, material review
   outcomes, checks actually run, and any blockers or skipped checks.

Distinguish user-requested behavior and existing compatibility requirements from
agent-proposed guarantees or extensions. Keep unaccepted proposals outside the
required acceptance criteria; a review suggestion alone does not expand scope.
Where a design adds mechanisms beyond the direct approach, briefly explain which
required behavior the simpler approach cannot satisfy. Apply the root scope and
simplicity rules during planning as well as implementation.

Ground decisions in current source. Include exact signatures, data shapes,
formulas, or examples when they define a necessary contract. Leave private
helper organization to implementation and omit speculative extension points.
Stop elaborating when implementation can proceed without unresolved
consequential decisions. Record future work only when a concrete exclusion or
known limitation needs a revisit trigger.

### Design from requirements and ownership

Start with the required behavior and operating conditions, then choose the least
machinery that fully satisfies them. Inspect what already exists before deciding
whether to extend an existing path, add a focused component, extract shared code,
or change an architectural boundary. These are possible solutions, not goals in
themselves. For a new feature, a small new component may be appropriate; for a
refactor, extracting duplicated mechanics may be sufficient. Explain a broader
design by the current requirement the simpler approach cannot satisfy, not
unspecified future reuse or uniformity. Keep this reasoning brief in the plan;
do not add a separate design document or exhaustive alternatives exercise.

- **Assign responsibilities before introducing mechanisms.** Identify which
  component owns each affected decision, validation, state transition, and side
  effect. Preserve useful existing ownership unless the requested behavior needs
  it to change. Shared infrastructure should handle common mechanics while domain
  components retain domain decisions. Prefer returning explicit data/results to
  the owner over a generic callback executor unless an existing contract or
  concrete requirement needs that control flow. Preserve required failure
  propagation and cleanup across component boundaries.
- **Make behavior and compatibility explicit.** Trace affected current paths and
  relevant tests. Distinguish behavior to preserve from behavior the feature must
  add or change, including defaults and failure cases where relevant. Do not
  collapse distinct cases into a convenient general rule or treat proposed
  behavior as already implemented. For new paths, define inputs, outputs, and
  ownership only to the depth needed to implement and verify the requirement.
- **Keep optional work conditional.** Adjacent cleanup, broader centralization,
  and extension points are not required merely because the change makes them
  possible. Include optional simplification only when it demonstrably reduces
  complexity without changing required behavior. Omitting it must not block the
  requested outcome. If additional architecture is necessary, connect it to a
  concrete requirement instead of labeling it optional cleanup.
- **Plan contract changes explicitly.** When an interface, payload, or state model
  changes, identify affected producers, consumers, and tests and migrate them
  together. Preserve behavioral assertions rather than retaining unnecessary
  production machinery solely for an old test representation. Inspect consumers
  before removing state. Add dual formats, fallback paths, or migration machinery
  only when an actual compatibility or rollout requirement needs them.
- **Sequence and validate the required outcome first.** Order necessary changes
  and focused checks before optional cleanup. Include a concrete representative
  end-to-end scenario when integration behavior is affected. List only actual
  prerequisites as dependencies; related historical plans are references. Do not
  expand acceptance criteria to qualify unrequested future capabilities.

Apply the root review and validation rules. Include integration or release
verification only when that milestone is in scope; a plan does not authorize
running the full test suite. Keep proposed checks distinct from checks run.

### Author check before plan handoff

For substantial plans, use the existing acceptance section to connect critical
requirements to concrete cases, expected outcomes, the responsible component or
boundary, and the verification that will establish them. Include relevant failure
and non-default cases derived from supported inputs and reachable states; do not
invent an exhaustive edge-case matrix or a separate checklist document.

Before handing off, trace a representative case through every changed boundary
and challenge the consequential assumptions against current source and callers.
Check that the proposed validation can distinguish the intended behavior from a
plausible incorrect implementation. Record material unknowns explicitly; resolve
them through inspection or a scoped probe when authorized, or leave the affected
decision open in draft. A prose assertion or passing metadata check is not evidence
that the design works. Ensure the scope, ordered changes, and acceptance criteria
agree before asking an independent reviewer to assess them.

For epics, use the same essentials for shared contracts, child sequencing,
dependencies, and integration completion. Keep child progress consistent with
status directories; do not duplicate child-local steps or acceptance criteria.

## Lifecycle

| Status | Meaning |
| --- | --- |
| `draft` | Requirements, behavior, ownership, or design decisions remain unsettled. |
| `ready` | Scope, decisions, affected surfaces, acceptance criteria, validation, and any required design review are settled; every dependency is `done`. |
| `in-progress` | Implementation, validation, review, or corrections are underway. |
| `blocked` | Required work remains and no useful scoped work can continue until a recorded condition changes. |
| `deferred` | Work is intentionally parked until a concrete recorded trigger. |
| `done` | Acceptance criteria and required review and verification are satisfied, with evidence recorded. |

Pending verification normally remains `in-progress`. Use `blocked` when an
unavailable prerequisite, decision, or external dependency prevents progress
and no useful scoped work remains. Record the condition, evidence, and exact
action or external change needed to resume.

The usual progression is `draft` -> `ready` -> `in-progress` -> `done`. Move a
plan backward if findings invalidate readiness or completion; reassess deferred
work before resuming. Inspect the plan and current implementation before status
changes rather than inferring completion from age, checkboxes, or old notes.
A plan-only deliverable may be `done` when its planning work and any required
review are complete; this does not mean its proposed implementation exists.

Epic status also accounts for child and integration work:

- `draft` while shared design, child scope, sequencing, or ownership is unsettled,
  or no child is ready before implementation starts.
- `ready` when shared design and child specifications are settled, dependencies
  are explicit, at least one incomplete child is ready, and none is in progress.
- `in-progress` when a child is in progress or done, required child or integration
  work remains, and useful work can continue.
- `blocked` only when neither incomplete children nor integration work can
  progress; one blocked child does not block the whole epic.
- `deferred` when the whole epic is parked until its recorded trigger.
- `done` only when every required child and the epic's own integration,
  acceptance, required review, and verification are complete.

## Work selection

When the user asks you to choose work, select the highest-priority ready plan
whose dependencies are done, breaking ties by the smallest coherent scope.
A user-selected task takes precedence.
