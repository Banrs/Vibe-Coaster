# Material Generator Vertical Slice Implementation Plan

> **For agentic workers:** use `superpowers:subagent-driven-development`,
> `superpowers:test-driven-development`, and `superpowers:systematic-debugging`. One bounded Sol
> implementer owns one task at a time; independent read-only reviews may run in parallel. Do not use
> Graphify before the final hygiene task.

**Goal:** Replace the public legacy generator with a materially different, force-informed,
configurable, physically continuous ride while shrinking the authoring code and preserving the
independent verifier, viewer, and diagnostic outputs.

**Architecture:** strict config and deterministic planning in `generator.gd`; compact physical
profiles and one time-domain kernel in `motion.gd`; complete gesture compilation and bounded station
capture in `ride_program.gd`; the existing packed route schema retained and explicitly validated.
No adapter, dormant candidate, post-hoc geometry repair, smoothing, or hidden propulsion.

**Verification policy:** the user has prohibited uncontrolled local Godot launches after a prior PC
crash. Open a draft pull request at the first implementation commit. Its GitHub Actions workflow runs
each focused script explicitly, full import/smoke, viewer runtime, and uploads bounded diagnostic
artifacts; a failing test-only commit supplies RED evidence before implementation is pushed GREEN.
Local work is limited to static inspection until the final controlled rebuild, using the pinned
console binary, isolated app-data directories, one process, and an explicit timeout.

## Global acceptance

- Seed 42 is materially different in raw position, speed, and proper-force channels.
- All 15 fixed seeds generate once, deterministically, and pass structural checks.
- Deep seeds 11, 42, and 20260809 pass loads and produce the complete diagnostic pack.
- Exactly three explicit positive-drive zones; no hidden drive on climb/return.
- One accepted 100 Hz full-route integration; no repair/smoothing/fitted path.
- Runtime production authoring code is materially smaller than the deleted 4,056 legacy lines.
- Final GitHub import, focused suites, smoke, viewer runtime, repeated audit, and controlled local
  rebuild are green.

---

### Task 1: Lock the physical kernel and CI feedback path

**Files:**
- Create: `godot/motion.gd`, `godot/motion_tests.gd`
- Modify: `.github/workflows/ci.yml`
- Modify: `godot/project.godot` only if script-class registration requires it

**RED:** add analytic tests for straight coast/launch, pitched straight gravity cancellation,
zero-gravity circular motion, banked lateral curvature, roll-only frame twist, resistance and its
derivatives, low-speed station handoff, C2 quintic endpoints, analytic boundary jets, exact
span-boundary splitting, degeneracy rejection, RK convergence rate, and dense-output consistency.
Prove gravity is applied once and `longitudinal_g` excludes it. Add a manifest-driven focused-test
runner to CI: a checked-in newline-delimited list of scripts is the sole inventory, CI fails on a
missing/nonexistent entry, and later tasks update the manifest whenever they add a suite. Add a
bounded diagnostic artifact upload, push the test-only commit, open a draft PR, and retain its
expected failing check/log.

**GREEN:** implement only immutable control evaluation, explicit
`rolling_mps2 + aero_per_m * v^2` resistance, projected RK4, exact boundary splitting, rider-frame
transport/roll, explicit straight station mode, analytic boundary jets, packed native trajectory,
and dynamics-derived dense output. No compiler, catalog, viewer migration, smoothing, radius clamp,
constant-speed mode, or geometry control points belong here.

**Verify:** focused suite green on the draft PR and source audit clean. Commit and push. This is a
verified numerical dependency, not a product checkpoint.

---

### Task 2: Cut over the first complete material public ride

**Files:**
- Create: `godot/ride_program.gd`, `godot/ride_program_tests.gd`, `godot/generator_tests.gd`,
  `godot/route_contract.gd`
- Rewrite: `godot/generator.gd`
- Modify: `.github/focused-tests.txt`, `.github/workflows/ci.yml`, `godot/smoke.gd`,
  `godot/verify.gd`, `godot/main.gd`, `godot/route_sampling.gd`, `godot/fidelity.gd`,
  `godot/fidelity_artifacts.gd`, `godot/fidelity_tests.gd`, `godot/fidelity_artifact_tests.gd`,
  `godot/_inspect.gd`, `CLAUDE.md`, `README.md`, `docs/ISSUES.md`,
  `docs/superpowers/plans/2026-08-10-fvd-first-program-roadmap.md`
- Delete after successful cutover: `godot/elements.gd` and its UID if present
- Modify: `godot/motion.gd` only when a failing physical test demonstrates a kernel defect

**RED:** add two focused subroute fixtures and one complete public-route test:

1. `cliff climb -> slow crest -> outward rim -> monotonic dive -> tunnel boost -> marquee camelback`;
2. varied incoming return state -> energy-bleeding raceway -> bounded capture -> straight brakes ->
   fixed station endpoint;
3. `RideGenerator.build(42)` -> all ten ordered story windows -> verifier and viewer mesh consumers.

Commit baseline metrics and fingerprints for geometry extents/shape, speed landmarks/time shares,
proper-force extrema/held values, pacing, and AGL. Every material assertion states units and a
minimum effect size; hash inequality alone is insufficient. Assert smooth shoulders, no hidden
drive, one integration, zero repairs, exact capture residuals, structural terminal jets, and fixed
endpoint/frame. Cover reachable, mirrored/rotated, nonzero-holonomy, and impossible captures with at
most 40 unique coarse evaluations.

**GREEN:** implement the smallest complete default program, strict default config, deterministic
plan, gesture-owned shoulders, and five-coefficient bounded capture. Atomically replace
`RideGenerator.build` with `config -> plan -> program -> one integration -> packed route`. Implement
all ten story beats; delete old authoring/repair code immediately after no consumer imports it. No
partial append, adapter, hidden candidate, fallback, or standalone connector is allowed.

Execute this material acceptance boundary as four bounded briefs, each with its own RED/GREEN
evidence and review, but make no intermediate product-completion claim:

- 2A: hero sequence recipes and quantitative subroute artifacts;
- 2B: opener and flowing act-one recipes;
- 2C: raceway return, five-residual capture, and analytic brake/station spans;
- 2D: full story assembly, public cutover, every necessary semantic-window consumer/diagnostic and
  repository-contract migration, CI artifact generation, and legacy deletion.

**Verify:** focused suites, import, smoke, and viewer runtime green in GitHub. Download the uploaded
seed-42 top, elevation, channels, and representative element views; reject visually flat,
oversmoothed, spiky, or radius-cheated output even if numeric assertions pass. This task is
incomplete if the public ride calls old authoring code or the old files remain. Commit and push the
first material checkpoint.

---

### Task 3: Finish consumer and diagnostic semantic-window coverage

**Files:**
- Modify: `.github/focused-tests.txt`, `godot/route_contract.gd`, `godot/route_sampling.gd`, `godot/fidelity.gd`,
  `godot/fidelity_artifacts.gd`, `godot/fidelity_tests.gd`, `godot/fidelity_artifact_tests.gd`,
  `godot/_inspect.gd`, `godot/generator_tests.gd`

**RED:** characterize every consumer against the same generated route and assert it cannot mutate,
reintegrate, refit, or widen a semantic gesture role. Require native-node identity, one
dynamics-derived dense trajectory, consistent sample/time/distance windows, and unchanged hashes
after verifier, viewer, audit, and artifact consumption.

**GREEN:** harden the semantic-window segmentation and sampling already migrated in Task 2D. Remove
any residual compatibility assumption exposed by the characterization tests. Validate the closed
route-dictionary fields and authoritative trajectory ownership, and verify the audit's bounded CI
artifact set. Do not defer a known old-section dependency to this task or rewrite working
measurement logic.

**Verify:** all focused suites and CI green; the audit pack is complete and no consumer references
old section kinds or owns a second interpolation/geometry representation. Commit and push.

---

### Task 4: Add only configuration controls that materially work

**Files:**
- Modify: `.github/focused-tests.txt`, `godot/generator.gd`, `godot/ride_program.gd`,
  `godot/generator_tests.gd`, `README.md`

**RED:** for each proposed version-1 control, add low/mid/high material-response tests across at
least the three deep seeds. Each test names its measured metric, expected direction, units, minimum
effect size, and valid capability interval. Assert stable IDs, units/scopes, deterministic precedence,
required/preferred conflict behavior, strict unknown-key rejection, and identical output for the same
normalized config and seed.

**GREEN:** implement strict normalization/provenance, bounded capability checks, stable named
decision streams, and `build_config`. If a control cannot demonstrate monotonic material response,
remove it from version 1 rather than weaken the assertion or accept a no-op.

**Verify:** focused config suite and public default fleet green in GitHub; concise README examples
cover one-click and guided generation. Commit and push.

---

### Task 5: Enforce deletion, documentation, and line-count boundaries

**Files:**
- Rewrite/delete obsolete portions of: `godot/generator.gd`, `godot/smoke.gd`
- Modify: `CLAUDE.md`, `docs/ISSUES.md`, `README.md`

**RED:** add source-boundary assertions forbidding runtime `FVD`/`GRADE`/`CLOSURE`, `append_closure`,
`_level`, `_align`, old `author_*`, short-section drops, route cloning, smoothing, fitted replacement,
and positive drive outside the three propulsion windows.

**GREEN:** remove obsolete fixtures, comments, or helpers left by cutover and document the real
runtime/config workflow. Count every production line serving config, planning, recipes, integration,
route construction, and helpers so code cannot be displaced into uncounted files. Preserve independent
verification and diagnostics; do not rewrite them for style.

**Verify:** `rg` finds no forbidden runtime path; the checkpoint line budget is met; all focused
suites and CI green. Commit and push.

---

### Task 6: Fleet, evidence overlay, and visual ride review

**Files:**
- Modify only on demonstrated defect: shared recipe/config values and their focused tests
- Modify evidence records only when backed by captured source material and provenance
- Generated output remains beneath ignored `out/`

Run the exact 15-seed fleet once per audit and the three deep seeds through load verification.
Generate the complete post-change pack twice and require byte-identical JSON/Markdown and identical
recommendation. Compare it directly with the preserved legacy pack.

Review the supplied Falcon's Flight POVs and telemetry-overlay POV using explicit local landmarks.
Acquire RideForcesDB raw only if the site produces the actual recording; otherwise retain honest
source bands and the `raw_fetch_unavailable` gap. Apply the approved force multipliers only in a
separate target lane and retain source durations.

Accept recipe/value changes only when a focused failing test and the raw diagnostic channels show a
real defect. Never tune to a seed, inflate tolerances, smooth geometry, clamp radius, hide drive, or
substitute a viewer-only path. At most one coherent shared value/refactor batch is in flight at once.

**Verify:** artifacts complete; issue 1–16 prompts map to relevant channel/geometry views; reviewer
records explicitly address flow, thrill, speed perception, shaping, support overlap, terrain, and
oversmoothing/undersmoothing.

---

### Task 7: Adversarial review, controlled rebuild, and cleanup

Run bounded independent Sol reviews for physics/numerics, configuration/architecture, ride
behavior/artifacts, tests/failure paths, and code deletion. Use Luna only for narrow mechanical
inventories or deterministic report comparisons. Verify every suggestion before changing code;
implement accepted corrections centrally with a new failing test.

Use Graphify once for the final whole-repository dependency/hygiene review. Specifically flag line
inflation, duplicate kernels/samplers/catalogs, dead authoring paths, cycles, orphaned tests, and
unnecessary abstractions. Re-run reviews after accepted fixes until no material issue remains.

Run fresh GitHub import, all focused suites, smoke, viewer runtime, and audit. Then perform one
controlled local import/build with the pinned console binary, isolated app-data, no visible editor,
one process, and a hard timeout; do not launch an uncontrolled Godot window. Rebuild the locally
checkable game artifacts beneath `out/`.

Finally inventory obsolete local worktrees, temporary branches, duplicated downloads, and unneeded
generated files while preserving the legacy baseline and final review pack. Delete only task-owned
or explicitly approved targets, never unrelated user work. Confirm a clean working tree, push the
final green commit, and merge/clean the implementation branch only through the
finishing-a-development-branch workflow.
