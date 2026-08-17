# Geometry-Truth Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a trustworthy geometry/rendering measurement path, then use it to replace the first visibly wrong whole element without hiding defects behind filtering, camera effects, or closure repairs.

**Architecture:** The first slice separates three concerns. `route_sampling.gd` becomes the one internally consistent distance-domain sampler used by the viewer and deterministic artifacts. `motion.gd` publishes independent dense-output consistency residuals rather than a tautology. Whole-material-role geometry contracts are introduced before the camelback is rewritten, so the new element must prove its spatial identity instead of merely passing force and endpoint checks.

**Tech Stack:** Godot 4.7.1, pure GDScript, existing headless focused-test scripts, GitHub Actions.

## Global Constraints

- Same seed and resolved configuration must remain deterministic.
- No new runtime dependency or native extension.
- No viewer-only geometry path: camera, train, artifacts, and engineering checks must sample the same accepted route.
- Human-response filtering remains separate from raw engineering smoothness.
- No new semantic micro-span or connector stub below 30 m without a named infrastructure exception.
- No closure solver may gain an element-shaping control in this slice.
- Tests are written and observed failing before production code is changed.
- The current route is not a golden geometry baseline; changed route bytes are allowed only when accompanied by explicit re-certification evidence.

---

## File Structure

- Modify `godot/route_sampling.gd`: consistent distance-domain Hermite position/tangent sampler and orthonormal rider frame.
- Create `godot/route_sampling_tests.gd`: endpoint identity, derivative/tangent consistency, wrap, and time/distance tests.
- Modify `.github/focused-tests.txt`: run the new focused suite.
- Modify `godot/motion.gd`: replace the tautological dense-output metric with independent position, distance, and velocity-channel residuals.
- Modify `godot/motion_tests.gd`: negative and positive tests proving the metric can fail.
- Create `godot/element_contract.gd`: intent-aware whole-role boundary and planarity contract evaluation.
- Create `godot/element_contract_tests.gd`: synthetic planar-pass, planar-drift-fail, and exit-frame-fail fixtures.
- Modify `godot/ride_program.gd`: publish the camelback's adopted geometry intent and replace its pseudo-hold when the element rewrite lands.
- Modify `godot/route_contract.gd`: evaluate adopted whole-role contracts after accepted integration.
- Modify `godot/ride_program_tests.gd`: contract publication and malformed-contract tests.
- Modify `godot/geometry_metrics.gd`: reuse the same whole-role measurement primitive rather than maintaining a second definition.
- Modify `godot/geometry_metrics_tests.gd`: prove contract/diagnostic measurements agree.
- Modify `docs/ISSUES.md`: record which VC issues the slice addresses and what remains open.
- Delete root `ISSUES.md`: remove the accidental duplicate after `docs/ISSUES.md` is confirmed canonical.

---

### Task 1: Consistent Route Sampling

**Files:**
- Create: `godot/route_sampling_tests.gd`
- Modify: `godot/route_sampling.gd`
- Modify: `.github/focused-tests.txt`

**Interfaces:**
- Produces: `RouteSampling.sample_at_distance(route: Dictionary, distance_m: float) -> Dictionary`
- Produces: `RouteSampling.pose_at_distance(route: Dictionary, distance_m: float) -> Transform3D`
- Guarantees returned `tangent == d(position)/ds` within numerical tolerance.

- [ ] **Step 1: Write the failing focused test**

Create a synthetic two-node curved interval whose endpoint tangents are not parallel to its chord. Assert that a central finite difference of sampled position aligns with the transform's `-basis.z` tangent. The current linear-origin/quaternion-frame sampler must fail this assertion.

- [ ] **Step 2: Run CI and verify RED**

Run through the pull-request focused manifest.

Expected: `route_sampling_tests.gd` fails with a position-derivative/tangent alignment error while pre-existing suites remain unchanged.

- [ ] **Step 3: Implement the minimal consistent sampler**

Use cubic Hermite position interpolation over distance with endpoint derivatives equal to accepted route tangents. Derive the sampled tangent from the analytic Hermite derivative. Interpolate rider orientation only to obtain an up candidate, then project and re-orthonormalise it against the derived tangent.

- [ ] **Step 4: Run focused and full CI; verify GREEN**

Expected: route-sampling tests pass, then import, all focused suites, smoke, and viewer runtime pass.

- [ ] **Step 5: Review the diff**

Confirm no caller keeps a second pose interpolator and no presentation-only smoothing enters the engineering sampler.

---

### Task 2: Independent Dense-Output Consistency Metrics

**Files:**
- Modify: `godot/motion_tests.gd`
- Modify: `godot/motion.gd`

**Interfaces:**
- Produces `trajectory.dense_output` fields:
  - `max_position_velocity_defect_mps`
  - `max_distance_speed_defect_mps`
  - `max_velocity_channel_defect_mps`
- Retains `max_kinematic_defect_mps` only as a compatibility alias for the maximum of the three real residuals during migration.

- [ ] **Step 1: Add a failing negative test**

Construct a copied trajectory with one independently published channel perturbed while native positions remain unchanged. Call the measurement helper and assert the corresponding defect becomes materially non-zero. The current tautological implementation must fail by reporting round-trip noise.

- [ ] **Step 2: Run `motion_tests.gd`; verify RED**

Expected: the corruption-detection assertion fails for the existing metric.

- [ ] **Step 3: Implement independent residuals**

At each dense probe:

1. compare analytic derivative of dense position with the independently interpolated `speed × tangent` channel;
2. compare analytic derivative of dense distance with independently interpolated speed;
3. compare analytic Hermite velocity with independently interpolated velocity-channel endpoints.

Do not compare a vector with its own normalisation and length.

- [ ] **Step 4: Run `motion_tests.gd`; verify GREEN**

Expected: analytic straight-motion fixtures remain near zero, curved fixtures stay within a measured tolerance, and channel corruption fails decisively.

- [ ] **Step 5: Run full CI and record fleet values**

Use the resulting canonical values to set a justified gate; do not guess a tolerance before measurement.

---

### Task 3: Whole-Material-Role Geometry Contract

**Files:**
- Create: `godot/element_contract.gd`
- Create: `godot/element_contract_tests.gd`
- Modify: `godot/ride_program.gd`
- Modify: `godot/route_contract.gd`
- Modify: `godot/ride_program_tests.gd`
- Modify: `.github/focused-tests.txt`

**Interfaces:**
- Produces: `ElementContract.measure(route_or_trajectory, first: int, last: int) -> Dictionary`
- Produces: `ElementContract.validate(intent: Dictionary, measurement: Dictionary) -> PackedStringArray`
- Consumes an adopted intent with exact keys: `planarity`, `max_plane_tilt_deg`, `max_out_of_plane_ratio`, `max_heading_drift_deg`, `entry`, and `exit`.

- [ ] **Step 1: Write failing synthetic fixtures**

Add one planar hill that passes, the same hill with lateral drift that fails planarity, and a planar hill with a wrong exit tangent/bank that fails its boundary state.

- [ ] **Step 2: Run `element_contract_tests.gd`; verify RED**

Expected: missing preload/API failure.

- [ ] **Step 3: Implement the minimal contract evaluator**

Use one whole-role least-squares plane fit and direct entry/exit frame measurements. Contract intent, not generated classification, decides whether planarity is required.

- [ ] **Step 4: Publish adopted intent with compiled material roles**

The compiler attaches geometry intent to the accepted program; the route contract evaluates it only after the full production trajectory exists.

- [ ] **Step 5: Run focused tests; verify GREEN**

Malformed or missing adopted intent fails fixtures. Existing roles without adopted intent remain explicitly `unadopted`, not silently passed as reviewed.

---

### Task 4: Planar Camelback Proving Element

**Files:**
- Modify: `godot/ride_program.gd`
- Modify: `godot/ride_program_tests.gd`
- Modify: `godot/geometry_metrics.gd`
- Modify: `godot/geometry_metrics_tests.gd`
- Modify: generator/return tests only where the route legitimately re-certifies.

**Interfaces:**
- Consumes the Task 3 whole-role contract.
- Produces the default camelback as a near-planar element with an adopted spatial contract.

- [ ] **Step 1: Add a failing production-path camelback test**

Assert on the built whole material role, not phase windows:

- vertical-plane tilt ≤ 3°;
- out-of-plane RMS ratio ≤ 0.02;
- heading drift ≤ 5°;
- pitch-zero apex exists in the crest window;
- entry and exit bank are near neutral;
- there is no semantic span shorter than the reviewed connector floor and no `pullout-hold` pseudo-span.

Expected: current route fails tilt/heading and pseudo-span assertions.

- [ ] **Step 2: Verify RED on seed 42 and deep seeds**

Capture current measured failures in CI output before changing the recipe.

- [ ] **Step 3: Replace the camelback recipe**

Remove lateral and alternating roll pulses from the default family. Use a single planar force/curvature narrative with a pinned pitch-zero apex and continuous pullout/release. Keep any future three-dimensional hill as a separately named family, not an implicit variant.

- [ ] **Step 4: Re-close only through existing macro authority**

Allow the existing return solve to adapt to the changed handoff inside its current bounds. Do not add a camelback-shaping residual or new return control. If the macro route cannot close, stop and revise anchor/corridor planning rather than reintroducing sideways hill geometry.

- [ ] **Step 5: Verify GREEN and re-certify**

Run the camelback contract test, full focused manifest, smoke fleet, and viewer runtime. Record changed route length, duration, top speed, return margins, load margins, and deterministic hashes as an explicit re-certification.

---

### Task 5: Documentation and Duplicate Cleanup

**Files:**
- Modify: `docs/ISSUES.md`
- Delete: `ISSUES.md`

- [ ] **Step 1: Update issue status without false closure**

Mark VC-029 and VC-038 addressed only after their tests and CI are green. Mark VC-016 addressed only after whole-role artifacts and human POV review; otherwise record it as implemented-awaiting-review.

- [ ] **Step 2: Remove the accidental root duplicate**

Delete root `ISSUES.md`; `docs/ISSUES.md` remains the sole active register.

- [ ] **Step 3: Run reference checks**

Search repository references to both paths and update live documentation that still points at the deleted root file.

---

## Plan Self-Review

- Scope is intentionally a vertical slice, not all 43 issues.
- Each production change has an explicit RED test before implementation.
- Route sampling and dense metrics can land independently of the camelback rewrite.
- The camelback is not allowed to close by adding new solver authority.
- No placeholder thresholds remain except the dense residual gate, which is deliberately measured before adoption rather than guessed.
- Legacy issue compatibility remains intact while the root duplicate is removed.
