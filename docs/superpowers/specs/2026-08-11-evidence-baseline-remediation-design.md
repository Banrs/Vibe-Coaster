# Evidence Baseline Remediation Design

**Status:** recommended approach approved in conversation; written-spec review pending.

## Authority and purpose

This design corrects the completed evidence-audit baseline at commit `6d5716e` before the program
starts `2026-08-09-route-config-foundation.md`. It is governed by root `CLAUDE.md`, the approved
FVD-first generator design, the evidence-audit plan, issues 1–16 in `docs/ISSUES.md`, and the global
AGENTS.md simplicity rules.

GitHub Actions run 70 proves that commit imports, passes smoke, and exercises the viewer. That green
run does not prove the standalone audit's full failure contract or justify the duplicated validation
and rendering added in the final artifact slice. Independent review found no Critical defect, but
found Important correctness defects and unreviewed production growth from 750 to 1,296 lines in
`fidelity_artifacts.gd`.

The remediation must leave the legacy generator's same-seed route arrays and generated ride
behavior unchanged. It repairs the diagnostic boundary, makes its documentation truthful, and
reduces code before Plan 2 introduces the final typed route contract.

## Goals

- Make `RideFidelity` the single semantic catalog-validation authority.
- Make a stale or failed artifact pack impossible to mistake for a successful current pack.
- Validate render requests against retained generated routes before ordinary artifact writes.
- Implement the contracted diagnostic POV near and far planes in camera space.
- Apply the same physical-consistency policy in smoke and the standalone audit.
- Give all sixteen issues their real text and relevant generated review artifacts.
- Preserve the channel, top, elevation, element-profile, POV, phase, and element-stat diagnostics
  while rendering each canonical image only once.
- Finish with a material net deletion, honest line-count disposition, and reproducible GitHub-only
  verification including two byte-identical complete audits.

## Non-goals

- No generator, element-authoring, force target, geometry, pacing, propulsion, terrain, closure, or
  viewer behavior change.
- No evidence promotion, invented video alignment, new external research, or ride-quality gate.
- No Plan 2 route/configuration type is introduced in this remediation.
- No generic schema framework, filesystem abstraction, dependency injection layer, sanitizer
  library, renderer registry, or cosmetic file split.
- No local Godot process. Godot execution remains GitHub-only because of the prior workstation
  crash. The existing Graphify graph is queried during design to check ownership seams and is run
  again at the final whole-branch hygiene gate after the implementation has changed the graph.

## Approaches considered

### A. Single-owner contraction and coherent pack preflight — selected

Reuse `RideFidelity`, `Verify`, `CanonicalData`, and `RouteSampling` as the existing owners. Delete
shadow validation, validate and render the complete pack before publication, and correct the audit
and documentation together. This fixes the defects and reduces code that Plan 2 would otherwise
have to migrate.

### B. Add guards to the current artifact implementation

Adding stale-manifest cleanup, route checks, far clipping, titles, and extra audit calls in place is
faster, but preserves two catalog validators and pushes the already oversized artifact file further
past 1,300 lines. It conflicts with AGENTS.md and is rejected.

### C. Revert the Claude continuation and rebuild Tasks 7B–9

This would discard sound work: route-sampling parity, checked reopened-byte manifests, deterministic
CPU rendering, fixed fleet orchestration, and documentation. It adds risk and time without a better
boundary. It is rejected.

## Architecture

### 1. One semantic validation owner

`RideFidelityArtifacts.build_report` accepts public `Variant` inputs, so it retains report-boundary
checks for the base commit, exact fleet correspondence, generation counts, canonical JSON safety,
unique projected paths, and the unique center-row/window resolution used by POV intents.

For a catalog Dictionary it calls `RideFidelity.validate_catalog` exactly once and returns an
`invalid-input` report when that authority reports errors. A non-Dictionary catalog is rejected
before the typed call. The artifact layer then projects an already-valid catalog into the evidence
snapshot, POV map, checklist, and issue coverage. It must not reimplement schema-v2 field sets,
source/selector/transform links, observation/target promotion rules, auxiliary issue ranges, or
artifact provenance rules.

The inspector continues to call `validate_catalog_artifacts` before generation because that adds
repository-file/digest checks to semantic validation. `build_report` independently calls the
semantic validator because it is a public pure boundary and must not label an invalid catalog
`valid` merely because the inspector happened to preflight one caller.

The focused artifact fixture becomes a genuinely valid schema-v2 catalog. Catalog-negative cases
already owned by `fidelity_tests.gd` are deleted from the artifact suite; artifact-specific
projection, alias-isolation, POV, output, and canonical-golden tests remain. No interim generic
measurement-validator API is added: the current narrow fleet/measurement checks stay until Plan 2
migrates them atomically to `RideRoute`, avoiding an API created only to be removed in the next plan.

### 2. Preflighted, manifest-last artifact publication

The artifact owner exposes one narrow `invalidate_pack(root: String) -> PackedStringArray` operation.
It accepts only a nonempty absolute root, creates that exact directory when necessary, removes only
an existing `manifest.json`, and verifies that the success marker is absent. The inspector validates
the root and invokes this operation before catalog validation or generation, so any later
operational failure cannot leave a previous run advertised as current. Failures before an output
root can be validated cannot safely invalidate an unknown location.

`write_pack` invokes the same invalidation again as a public-boundary defense and then follows one
deterministic pipeline:

1. Validate the output root, invalidate its prior success marker, and validate a completed canonical
   report. Unrelated files are never deleted.
2. Validate every render request's exact keys, types, kind, seed, canonical path, required route,
   generated time, and raw beat ID. Reject absolute paths, URI schemes, backslashes, parent
   traversal, and path collisions rather than repairing them.
3. Perform narrow assertion-safe render-input shape checks on every retained route referenced by
   any request before calling channel reconstruction, fidelity, or sampling helpers. For routes
   used by element or POV requests, additionally call `RideFidelity.element_bands(route, 0.0)` once,
   index unique raw beat IDs, and require request ID, kind, and ordered in-range
   native/time/distance span parity. The report's copied span is not the rendering authority.
4. Build the fixed text payloads and in-memory images, including channel data calculated once. Sort
   jobs by audit-relative forward-slash path.
5. Write each job, reopen its bytes, compare exact UTF-8 bytes for text, decode PNGs and verify their
   dimensions, then calculate size and SHA-256 from those reopened bytes. Channel Markdown is
   projected from the reopened canonical legend JSON.
6. If any step fails, ensure `manifest.json` is absent and return `artifact_write:` errors. Partial
   ordinary artifacts may remain for diagnosis but cannot masquerade as a successful pack.
7. Only after every file reopens and verifies, write and reverify `manifest.json` last. The manifest
   excludes itself and copies the report's validated generation counters verbatim.

No writer injection, transactional filesystem abstraction, cleanup of unrelated files, generator
call, or route fallback is introduced.

### 3. Correct diagnostic POV clipping

The fixed camera remains 1440×900, vertical FOV 72 degrees, near 0.08 m, far 5000 m, eye offset
0.35 m, and viewer-equivalent interpolated pose with no speed-dependent FOV widening.

Segments are transformed into camera space and parametrically clipped by positive camera depth
`-z` against `[near, far]` before perspective division and existing screen/frustum clipping. A
segment wholly outside either depth plane draws nothing; a crossing segment is clipped to the
plane. Euclidean endpoint radius is never used as a far-plane substitute.

Tests include wholly-before-near, crossing-near, wholly-beyond-far, and crossing-far segments, plus
the existing camera metadata, basis, rail/terrain pixel, and no-dynamic-FOV checks. No fixed PNG hash
is added.

### 4. One physical-consistency policy

`Verify` gains one pure route-level entry point shared by smoke and `_inspect.gd`:

```gdscript
Verify.validate_physical_consistency(
	route: Dictionary,
	row_offsets: Array,
	include_loads: bool,
) -> Dictionary # {"issues": PackedStringArray, "analysis": Dictionary}
```

It runs structure, seams, terrain clearance, self-clearance, then optional analysis/load validation
in that deterministic order. A structure failure returns immediately because later validators
assume valid route arrays; once structure is sound, the remaining checks run so one pass reports all
independent physical defects. `analysis` is empty when `include_loads` is false. Terrain and tunnel
inputs remain owned by the generated route rather than being copied into another policy object.
Specifically, it calls:

- structure, seams, terrain clearance, and self-clearance for all fifteen canonical audit seeds;
- `analyze` plus load validation only for deep seeds 11, 42, and 20260809.

The helper returns the deep analysis when requested so smoke does not analyze the same route twice.
Seed scheduling remains in smoke and the inspector. It does not include ride-shape aspirations,
length/top-speed bands, determinism repeats, template probes, or other smoke-only policy. The
inspector prefixes resulting failures with `physical_consistency`, records catalog version and seed,
and exits 1. Fidelity `under`/`over` findings remain diagnostic and exit 0.

Focused tests exercise the pure helper with structurally valid synthetic clearance and load
failures, including the deterministic result shape and early structure stop. The existing
`_run_audit` one-build-per-seed callable spy stays unchanged; no validator injection seam or test
hook is added. Inspector mapping from returned issues to operational errors is a direct caller
responsibility and is verified in the final GitHub audit. No production tolerance, filter, or seed
exception changes.

### 5. Complete issue traceability

The artifact owner contains the exact sixteen issue titles from `docs/ISSUES.md`, not generic
`Issue N` placeholders. Generated paths are derived from the canonical render requests and assigned
by review need:

- force, pacing, speed, airtime, and transition questions link channel sheets;
- terrain/AGL questions link channels, top, and elevation views;
- shaping, oversmoothing, support-overlap, and multidimensional-scale questions link top,
  elevation, and the available seed-42 element profiles;
- ride-feel and speed-perception prompts additionally link a generated POV only when a reviewed
  source alignment actually authorizes one.

All lists are sorted and unique. An absent authorized POV remains an explicit gap and never creates
a fallback frame. The JSON and Markdown share one projection.

### 6. Render canonical diagnostics once

The checked `review/...` pack is the canonical output. It retains the old channel calculations,
side/profile projection, top view, elevation view, phase tables, and element statistics, including
the force/angle/speed/AGL/curvature/radius/roll-acceleration/jerk channels needed to judge shaping,
flow, and thrill after later ride changes. The inspector stops separately rendering undocumented
root-level duplicates such as `top.png`, `elevation.png`, and `channels_<seed>.png`; this removes
repeated CPU work without removing any diagnostic capability or canonical review artifact. Console
diagnostics remain.

No alias-copy layer is added. If a legacy filename later proves to be an external public contract,
that compatibility decision requires evidence and a separate design; current README/CLAUDE output
contracts name only the checked review paths.

### 7. Documentation and line-count disposition

README, CLAUDE, ISSUES, and the Plan 1 closeout must state only freshly verified behavior:

- all fifteen seeds gate structure/seams/clearance/self-clearance; only the three deep seeds gate
  loads;
- checked-pack text uses reopened byte equality and checked-pack PNGs are decoded before manifest
  publication;
- route-sampling delegates are the allowed behavior-preserving `main.gd` diff;
- full-audit repeat equality and visual inspection cite the new GitHub run/artifact evidence;
- the known radius-scale and unavailable-POV evidence gaps remain explicit.

This is a simplify decision, not permission to keep the 1,296-line implementation unchanged.
Deleting duplicate validation and rendering must outweigh all new correctness code. Acceptance
requires deletion of the artifact-side schema-v2 validator, its duplicate catalog-negative tests,
and the inspector's duplicate root renders. Across touched production files the remediation is
net-negative, with no new production file whose purpose is relocation. Physical line counts are
reported as evidence, not optimized as a quota; packing, golden hashes, fixture-to-oracle coupling,
and cosmetic splitting do not count as reduction. Deterministic output, failure, raster, manifest,
and alias-isolation tests remain. If a named duplicate block remains or production is not
net-negative, implementation stops for another lean review.

The baseline files over the evidence plan's review thresholds receive these explicit dispositions:

- `fidelity_artifacts.gd` (1,296 production lines): simplify in place through the named deletions;
- `fidelity.gd` (2,333 production lines): keep scoped as the cohesive measurement, comparison,
  reconstruction, and authoritative validation owner; do not refactor unrelated proven behavior;
- `fidelity_tests.gd` (2,218 test lines): keep scoped as the authoritative semantic and numerical
  suite while deleting only cases duplicated in the artifact suite.

The final lean reviewer rechecks these decisions against the resulting diff. Any newly identified
semantic duplication is actionable and blocks completion; file size alone does not license an
unrelated rewrite immediately before Plan 2 changes the route contract.

## Error model

- Report input defects return deterministic sorted `invalid-input` diagnostics.
- Catalog/artifact provenance, artifact root, generation, shared physical validation, rendering,
  reopen, and manifest failures are operational and exit 1 in the inspector.
- Fidelity classifications never alter process exit status.
- The writer never catches or hides an assertion by weakening validation; it validates public input
  before calling assertion-bearing helpers.

## Implementation sequence

Each slice follows RED → GitHub-observed expected failure → minimum GREEN → scoped spec/quality
review. No two implementers edit the shared artifact files concurrently.

1. Authoritative catalog validation and deletion of shadow checks/tests.
2. Run-level invalidation, pack preflight, route/beat binding, and exact reopened-byte text checks.
3. Camera-space near/far clipping.
4. Shared physical validation and inspector operational handling.
5. Exact issue text and review-artifact traceability projection.
6. Duplicate-render deletion and truthful documentation.
7. Full branch review, line-count decision, and remote acceptance.

## Verification

The permanent CI configuration remains unchanged. Normal GitHub runs must pass import, smoke, and
viewer runtime after every GREEN slice.

For final acceptance, a temporary verification-only CI commit runs `_inspect.gd` twice into clean
directories using the pinned Godot 4.7.1 runner, compares the complete directories byte for byte,
checks exact fifteen-seed generation counters, manifest membership/hashes/dimensions, issue 1–16
coverage, expected review artifacts, and the explicit no-eligible-finding result. It uploads one
pack for visual inspection of channel, top, elevation, and seed-42 element views. The temporary
workflow change is then reverted and the unchanged permanent CI runs green again; the completed
GitHub run and uploaded artifact remain the evidence.

The temporary job also captures both inspector logs, extracts deterministic `PHASE`, `ELEM`, and
`CHANNEL` characterization lines, and requires those extracts to be byte-identical. It asserts that
phase rows remain present; element rows retain length, entry/exit speed, pitch range, bank, normal-G,
width, height, apex radius, and valley radius fields; and all documented channel IDs remain present
for each deep seed. The extracts are uploaded with the pack. This preserves the old shaping,
force/angle, and flow-review diagnostics without retaining duplicate root-level PNG aliases.

Focused GitHub tests start with a pre-existing manifest and prove that explicit run invalidation,
invalid-report publication, render failure, and final-manifest failure all leave that marker absent.
The inspector's invalidation call is ordered before catalog validation and generation. This covers
both the early-run and writer-level stale-success paths without adding dependency injection.

Final acceptance also requires independent correctness, lean/line-count, and documentation reviews.
The final Graphify full rebuild runs once at the whole-branch gate, after Plan 2 work or before
handoff if work stops here.
