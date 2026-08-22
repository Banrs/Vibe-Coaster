# Full Ride Geometry Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit and correct the generated ride’s element geometry and transitions while preserving the record-scale route and using the FVD integrator as the only physical authority.

**Architecture:** Extend the existing whole-material-role contract with deterministic spatial and transition evidence. Centralize continuous transition schedules in the current FVD span authoring, correct the camelback and the shared roll/lateral patterns that affect other element families, and add a terrain-relative audit for return beats. CI remains the runtime authority.

**Tech Stack:** Godot 4.7.1, typed GDScript, existing `Motion` RK4 FVD integrator, GitHub Actions on Ubuntu.

**Spec:** `docs/superpowers/specs/2026-08-20-full-ride-geometry-audit.md`

## Global Constraints

- Keep `godot/motion.gd` as the sole physical integrator; do not post-edit route vertices.
- All authored geometry must flow through normal/lateral/drive/roll controls consumed by FVD.
- All material roles must publish finite audit evidence, even when their status remains `unadopted`.
- Camelback prominence stays 245–255 m; camelback apex AGL targets 140–170 m, nominal 155 m.
- Camelback uses zero lateral force, zero bank intent, 0° crest pitch, and no semantic hold span.
- Preserve the README’s speed, route-length, dive, terrain-clearance, capture, and load contracts.
- Do not run Godot locally; verification is performed through GitHub Actions only.
- Do not stage or modify the existing checkout’s unrelated README, launcher, `.claude`, or Telemetry edits.

---

### Task 1: Add the all-role spatial and transition audit

**Files:**
- Modify: `godot/element_contract.gd`
- Modify: `godot/route_contract.gd`
- Modify: `godot/geometry_metrics.gd`
- Create: `godot/geometry_audit_tests.gd`
- Modify: `.github/focused-tests.txt`

**Interfaces:**
- `ElementContract.measure()` consumes the accepted trajectory plus aligned speed, force,
  distance, and terrain channels when present.
- `RouteContract.build()` produces `element_contracts[role_id].measurement` and a top-level
  deterministic `geometry_audit` record for every material role.
- `GeometryMetrics.transition_audit()` consumes authored spans and returns seam rows with
  boundary control values, derivative continuity, and repeated-pulse/short-hold findings.

- [ ] **Step 1: Write failing synthetic audit tests.** Add cases covering a planar hill, a
  laterally shifted hill, a roll that stops and restarts inside one role, missing terrain
  samples, and a semantic span shorter than 0.30 s. Assert that every result names the role or
  span responsible and that the same input produces canonical-identical output.
- [ ] **Step 2: Add role-level measurements.** Extend `ElementContract.measure()` with finite
  distance/shape/force/roll/AGL fields without changing the existing planarity API. Keep terrain
  optional so synthetic contract fixtures remain valid.
- [ ] **Step 3: Add transition auditing.** Implement the smallest deterministic scan over
  adjacent authored spans; treat matching transition IDs as one gesture and flag an internal
  return-to-zero roll/lateral schedule or an unnamed sub-30 m semantic connector. Do not infer
  design family from geometry.
- [ ] **Step 4: Publish the audit from `RouteContract`.** Preserve unadopted evidence, fail only
  malformed records and adopted-contract violations, and include all roles in deterministic
  order.
- [ ] **Step 5: Add the suite to the focused manifest.** Do not run it locally; the first red
  result is expected from GitHub CI after the branch is pushed.
- [ ] **Step 6: Commit.**

```powershell
git add godot/element_contract.gd godot/route_contract.gd godot/geometry_metrics.gd godot/geometry_audit_tests.gd .github/focused-tests.txt
git commit -m "test: add all-role geometry and transition audit"
```

### Task 2: Correct FVD transition ownership and element authoring

**Files:**
- Modify: `godot/motion.gd` only if a small reusable profile helper is required
- Modify: `godot/ride_program.gd`
- Modify: `godot/ride_return_solve.gd`
- Modify: `godot/ride_program_tests.gd`
- Modify: `godot/geometry_audit_tests.gd`

**Interfaces:**
- `RideProgram._add_camelback()` emits one continuous planar FVD gesture with no hold spans.
- Shared roll schedules return boundary bank/rate state to their callers so normal force and roll
  remain authored as one transition.
- Existing solver vector dimensions and capture residual IDs remain stable unless a new terrain
  authority is proven necessary by the failing tests.

- [ ] **Step 1: Add failing production-path assertions.** Assert that camelback spans contain no
  lateral or roll profile, contain no `hold` IDs, reach 0° crest pitch, and do not show an
  internal roll restart. Add representative assertions for opener, inversion, wave, dive, and
  return transition ownership.
- [ ] **Step 2: Replace camelback pulses and holds.** Use continuous quintic/constant FVD control
  segments for pull-up → unload → crest → pullout; keep semantic spans at least 0.30 s and let
  the existing return solve adapt only through its declared authority.
- [ ] **Step 3: Replace shared pulse/restart patterns.** Make one schedule own the full roll for
  each affected gesture, preserving intentional bank and lateral values where the element
  requires them. Remove convenience micro-spans, not the deliberate slow crest.
- [ ] **Step 4: Re-run the focused production assertions in CI and adjust only the smallest
  profile/solver values needed to retain canonical speed, length, closure, and load bands.**
- [ ] **Step 5: Commit.**

```powershell
git add godot/motion.gd godot/ride_program.gd godot/ride_return_solve.gd godot/ride_program_tests.gd godot/geometry_audit_tests.gd
git commit -m "fix: author ride elements as continuous FVD gestures"
```

### Task 3: Add terrain-relative macro height authority

**Files:**
- Modify: `godot/generator.gd`
- Modify: `godot/ride_return_solve.gd` only if the failing route audit proves a new bounded
  return degree of freedom is required
- Modify: `godot/route_contract.gd`
- Modify: `godot/generator_material_tests.gd`
- Modify: `godot/route_contract_tests.gd`

**Interfaces:**
- The plan publishes explicit `agl_intents` for the camelback apex and sustained high-speed
  return beats.
- Placement/return diagnostics include measured minimum and maximum AGL per selected role.
- Existing terrain clearance remains a lower bound; the new AGL target is an upper/shape intent,
  not a render-time clamp.

- [ ] **Step 1: Add failing terrain fixtures.** Create deterministic synthetic terrain and route
  cases proving that a route can satisfy minimum clearance while still violating its maximum AGL
  intent, and that the violation names the correct role.
- [ ] **Step 2: Publish and measure AGL intents.** Add the camelback 140–170 m band and a bounded
  return speed-perception corridor. Keep evidence gaps explicit for roles without terrain data.
- [ ] **Step 3: Give the existing macro placement/return authority the smallest control needed to
  satisfy the band.** Do not lower station Y blindly, alter terrain height, or clamp published
  vertices. If closure is infeasible, return a refusal with diagnostics rather than inserting a
  lateral correction.
- [ ] **Step 4: Preserve record-scale prominence and existing route contracts.** Add assertions
  for 245–255 m camelback prominence, 140–170 m apex AGL, route length, speed, clearance, and
  capture closure.
- [ ] **Step 5: Commit.**

```powershell
git add godot/generator.gd godot/ride_return_solve.gd godot/route_contract.gd godot/generator_material_tests.gd godot/route_contract_tests.gd
git commit -m "fix: constrain ride geometry against local terrain"
```

### Task 4: Make GitHub CI measure startup and runtime health

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/focused-tests.txt` if a focused suite was added by earlier tasks
- Modify: `README.md` only if the verification contract needs one concise update

- [ ] **Step 1: Add a failing CI timing assertion** around project import and first live viewer
  frame, with bounded thresholds documented in the workflow output.
- [ ] **Step 2: Keep the existing focused-test, smoke, and viewer-live-frame jobs intact.**
- [ ] **Step 3: Upload timing and geometry diagnostics on every run.**
- [ ] **Step 4: Commit.**

```powershell
git add .github/workflows/ci.yml .github/focused-tests.txt README.md
git commit -m "ci: measure startup and geometry health on runner"
```

### Task 5: Review and GitHub-only verification

- [ ] **Step 1: Generate the task review package for each completed task and dispatch a fresh
  reviewer with the task brief, implementation report, and diff package.**
- [ ] **Step 2: Fix every Critical/Important review finding through the task implementer and
  re-review the scoped diff.**
- [ ] **Step 3: Dispatch the whole-branch reviewer against the merge base.**
- [ ] **Step 4: Push the branch only when the focused implementation is ready, then inspect the
  GitHub Actions run, job steps, logs, and artifacts.**
- [ ] **Step 5: Claim completion only when the fresh CI run passes all required gates and the
  startup/runtime measurements are present.**
