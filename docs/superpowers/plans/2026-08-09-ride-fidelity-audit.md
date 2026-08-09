# Ride Fidelity Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic, diagnostic-only, fifteen-seed fidelity audit that turns the repository's measured telemetry into separate evidence scorecards and one evidence-qualified follow-up recommendation.

**Architecture:** A pure-GDScript `RideFidelity` module measures and compares routes against a curated `RideFidelityReferences` catalog. The existing inspector becomes the audit runner, while smoke reuses only the shared segmentation and held-value primitives so enforcement behavior does not change.

**Tech Stack:** Godot 4.7.1, typed GDScript, built-in JSON and Image APIs.

## Global Constraints

- Remote `Banrs/Vibe-Coaster` `main` is authoritative; fast-forward a clean checkout only.
- Do not change generator, element-authoring, verification-envelope, viewer, or CI behavior.
- Fidelity findings never fail the audit; operational errors do.
- Use only the existing repository telemetry corpus in this iteration.
- Generate all reports beneath the ignored `/out/fidelity/` directory.
- Build exactly the approved fifteen seeds once per audit run.

---

### Task 1: Shared fidelity primitives and catalog validation

**Files:**
- Create: `godot/fidelity.gd`
- Create: `godot/fidelity_references.gd`
- Create: `godot/fidelity_tests.gd`
- Modify: `godot/smoke.gd`

**Interfaces:**
- Produces: `RideFidelity.element_bands(route, row_offset := 0.0) -> Array`
- Produces: `RideFidelity.held(values, polarity, seconds) -> float`
- Produces: `RideFidelity.validate_catalog(catalog) -> PackedStringArray`

- [ ] Add failing synthetic tests for held-value semantics, composite grouping, malformed catalog records, duplicate IDs, invalid ranges, missing sources, and unsupported metrics.
- [ ] Run the Godot import and smoke script and confirm the new tests fail because `RideFidelity` is absent.
- [ ] Implement the minimum shared primitives and catalog validator needed by the tests.
- [ ] Re-run import and smoke until the new tests and all existing checks pass.
- [ ] Replace smoke's private grouping/held implementations with delegating wrappers and verify representative seed-42 band values remain within float tolerance.
- [ ] Commit the tested shared foundation.

### Task 2: Route measurements and reference catalog

**Files:**
- Modify: `godot/fidelity.gd`
- Modify: `godot/fidelity_references.gd`
- Modify: `godot/fidelity_tests.gd`

**Interfaces:**
- Consumes: shared beat windows and held-value functions from Task 1.
- Produces: `RideFidelity.measure_route(route, row_offsets) -> Dictionary`

- [ ] Add failing tests for rear-row boundary attribution and literal load, geometry, pacing, terrain, and transition measurements on a hand-built route.
- [ ] Implement row-aware beat windows and the five measurement dimensions without modifying route data.
- [ ] Encode the reviewed catalog subset with stable source IDs, selectors, confidence, raw and target bands, transforms, hold durations, and issue mappings.
- [ ] Add a catalog-coverage test requiring every issue 1-16 to map to a target, review prompt, or evidence gap.
- [ ] Run import and smoke and commit the measured-route/catalog increment.

### Task 3: Fleet comparison and recommendation

**Files:**
- Modify: `godot/fidelity.gd`
- Modify: `godot/fidelity_tests.gd`

**Interfaces:**
- Consumes: per-seed dictionaries from `measure_route` and the validated reference catalog.
- Produces: `RideFidelity.compare_fleet(seed_measurements, catalog) -> Dictionary`

- [ ] Add failing table-driven tests for `within`, `under`, `over`, `observed_only`, and `evidence_gap` outcomes.
- [ ] Add failing tests for the eight-of-fifteen eligibility rule, normalization formula, confidence filter, tie-breaking, and explicit no-recommendation result.
- [ ] Implement deterministic comparison, aggregation, coverage, finding, and recommendation output.
- [ ] Sort every emitted seed, beat, row, target, source, issue, and finding collection by stable keys.
- [ ] Run import and smoke and commit the comparison engine.

### Task 4: Audit runner and artifacts

**Files:**
- Modify: `godot/_inspect.gd`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/ISSUES.md`

**Interfaces:**
- Consumes: `RideGenerator.build`, `RideElements.ROW_OFFSETS`, `RideFidelityReferences.CATALOG`, and the Task 3 APIs.
- Produces: `/out/fidelity/audit.json`, `/out/fidelity/audit.md`, and `/out/fidelity/review/*`.

- [ ] Add a failing runner self-check for the exact fifteen-seed order, complete report keys, and diagnostic-only exit behavior.
- [ ] Build each approved seed once, measure it, release the route after use, and pass all measurements to `compare_fleet`.
- [ ] Serialize canonical JSON and deterministic Markdown without timestamps or absolute paths.
- [ ] Render the three deep-seed channel/top/elevation views and seed-42 element views, then write the human-review checklist.
- [ ] Update repository guidance with the command, outputs, provenance policy, non-gating status, and gate-promotion rule.
- [ ] Run the audit twice and compare JSON and Markdown byte for byte; verify the expected review artifacts exist.
- [ ] Run the required import and smoke commands and commit the completed audit.

### Task 5: Final review

**Files:**
- Review all changed files and generated ignored artifacts.

- [ ] Compare the completed implementation against every approved design requirement.
- [ ] Confirm no placeholders, absolute paths, timestamps, overall score, or unintended behavior changes remain.
- [ ] Run fresh full verification and inspect the final git diff/status.
- [ ] Use `superpowers:finishing-a-development-branch` to present the verified integration choices.
