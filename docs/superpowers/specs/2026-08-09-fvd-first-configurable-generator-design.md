# FVD-First Configurable Generator and Fidelity System Design

**Status:** Approved on 2026-08-09.

This design supersedes the diagnostic-only scope in
`2026-08-09-ride-fidelity-audit-design.md`. The shared fidelity work already committed remains
useful, but its measurements, catalog, and runner must be corrected or rewritten where the wider
design proves them wrong. The old generator's behavior is not a compatibility target.

## 1. Product outcome

Vibe-Coaster remains a deterministic engineering simulation with a deliberately generic viewer.
The default demo is a near-future fictional ride inspired by, but not a replica of, Falcon's
Flight and Tormenta: Rampaging Run. Its documented dramatic structure is product intent; the
current generated geometry, timings, force profiles, smoke bands, and connective sections are not.

The polished demo preserves this arc:

1. station and a violent compressed-air or hydraulic launch;
2. an unpowered opener crest and twisted non-inverting side drop;
3. one cohesive, terrain-conscious first act combining a giant inversion-scale gesture,
   helical/looping motion, a cutback, airtime, and a wave turn without connector filler;
4. a short cliff-base LSM boost and visibly decelerating unpowered climb;
5. one deliberate slow crest beat, compact reference-scale clifftop suspense, and an
   outward-banked rim turn;
6. monotonic commitment into the cliff dive, a short tunnel, and the record LSM boost;
7. a record-scale camelback and a long return raceway whose energy bleeds honestly while force and
   release beats keep it active;
8. final brakes and a physically continuous station return.

The demo has exactly three short propulsion zones: the station launch and two LSM boosts. It has no
lift, powered climb, mid-course brake, late return boost, standalone connector turn, or geometry
repair. Marquee gestures own the fictional record scale; the clifftop suspense remains small and
light. The intended feel alternates force, airtime, release, suspense, and recovery rather than
holding the maximum envelope continuously.

## 2. Authority and skepticism

The implementation uses this authority order:

1. explicit user decisions in the current design cycle;
2. reproducible physical derivation and verified external evidence;
3. the creative ride vision in `CLAUDE.md`, `docs/RESEARCH.md`, and `docs/PLAN.md`;
4. current code and existing generated behavior.

Repository prose is neither copied verbatim nor presumed factual. In particular:

- the 2041 force envelope and its multipliers are fictional design decisions, not predictions;
- sustained, cross-recorded telemetry outranks isolated spikes and single-device extrema;
- real POV outranks CGI or simulation for geometry, pacing, and phase order;
- video-derived speeds remain estimates unless an independent speed source supports them;
- `docs/ISSUES.md` is a symptom report and discovery agenda, not a numeric specification;
- a passing smoke threshold is not evidence that the ride feels or flows correctly.

Unsupported claims are removed, downgraded to caveated observations, or represented as evidence
gaps. A target may enter executable data only when its source window, axis, row, transform, and
confidence are reviewable.

## 3. One public configuration model

The eventual authoring experience is a spectrum served by one engine and one versioned intent
document:

- **Preset:** preset ID and seed produce a coherent ride in one click.
- **Guided:** riders choose medium/high-level duration, speed, height, terrain, intensity, pacing,
  element palette, inversion/airtime character, ordering preferences, and selected pins.
- **Sandbox:** a future interface arranges or pins whole ride acts and gestures and edits their
  physical intent. It writes the same configuration; it is not a node graph, spline editor, or
  full manual path authoring system.

Version 1 exposes only proven controls:

```yaml
ride_config_version: 1
preset: future-hybrid@1
seed: 42

sequence:
  pinned:
    preset-story-slot-id: recipe-id

constraints:
  required:
    - {id: inversion_recipe, scope: act1.giant_inversion, key: slot.recipe, value: giant_immelmann}
  preferred:
    - {id: ride_duration, scope: ride, key: ride.duration_s, target: 205.0, tolerance: 15.0}
```

The real schema is JSON-compatible plain data and carries explicit units. Public IDs are
preset-versioned story slots such as `act1.giant_inversion`, not output-dependent beat IDs. The
compiler separately emits immutable gesture-instance IDs for measurements and reports. Guided
command-line or file inputs create or overlay this document; they do not become a second API. The
resolved plan is inspectable compiler output, not another hand-authored format.

Version 1 starts with preset, seed, preset-declared optional-slot enablement, and recipe pins. It
then adds only these guided controls after the owning recipe demonstrates a conservative capability
range:

| key | type/unit | scope | form | feasibility phase |
| --- | --- | --- | --- | --- |
| `slot.recipe` | recipe ID | story slot | required equality | planning |
| `slot.enabled` | boolean | optional story slot | required equality | planning |
| `ride.duration_s` | seconds | ride | preferred target/tolerance | compilation |
| `ride.peak_speed_mps` | m/s | ride | preferred target/tolerance | compilation |
| `slot.structure_height_m` | metres | story slot | preferred target/tolerance | compilation |
| `slot.intensity` | catalogued enum | story slot | preferred choice | planning |
| `slot.airtime_character` | catalogued enum | compatible story slot | preferred choice | planning |

Each registry entry declares value type, unit, legal scope, legal operator, domain, owner, and
feasibility phase. A key is absent from the public schema until tests prove that contract; there is
no generic `catalog-key` escape hatch.

Only catalogued keys are accepted. There is no expression language, weighted global objective,
arbitrary dictionary path, raw FVD key array, transition control point, or integrator switch in the
public contract. New keys are added only for a demonstrated authoring need.

Required constraints never move and version 1 restricts them to properties certified during
discrete or analytic planning, before any integration. The compiler rejects an infeasible
requirement with its scope, conservative capability range or choices, and the conflicting pin or
rule. It does not claim an exact feasible range for coupled geometry. Preferred constraints have
explicit precedence. A preference is either achieved inside its declared tolerance or reported as
unresolved; it is never represented as achieved outside that tolerance. The resolution report
records the request, achieved value when any, delta, status, and reason.

Only properties that can be conservatively certified are accepted as pre-generation requirements.
Discrete inclusion, exclusion, order, recipe choice, and declared capability ranges qualify.
State-dependent requirements such as exact clearance, station closure, duration, peak speed, or an
exact measured force are not version-1 required keys. They may be preferred targets handled by a
bounded physical solve and then reported, or non-configurable safety invariants verified after
generation. The compiler must not disguise a global optimizer as constraint handling.

Configuration overlay algebra is deliberately small:

1. the versioned preset is the base, the config file overlays it, and CLI overrides overlay last in
   argument order;
2. omitted fields inherit the lower layer, explicit `null` is invalid, and version 1 has no reset
   operator;
3. scalar fields replace and pins replace by story-slot ID;
4. each constraint has a stable `id`; duplicate IDs inside one layer are errors, a later layer with
   the same ID replaces the earlier record only when scope and key are unchanged, and two effective
   IDs for the same `(scope, key)` are rejected as ambiguous;
5. required constraints resolve before all preferences; preferences resolve by source layer from
   highest to lowest precedence (last CLI override, earlier CLI overrides, file, preset), then by
   their original list position, with stable ID as the final tie-breaker;
6. unknown slots, incompatible pins, and grammar contradictions are errors rather than merge rules;
7. every effective value retains its source layer and list position, and normalization emits one canonical ordering
   before hashing or compilation.

The future sandbox may permute and pin only inside preset-declared grammar cells and a finite recipe
compatibility graph. `sequence.order` is reserved for that future version and is rejected by the
version-1 validator; version 1 never promises unrestricted whole-ride ordering.

## 4. Pipeline and ownership

The complete pipeline is:

```text
RideConfig
  -> normalize and validate
  -> RidePlanner
  -> immutable CompiledRidePlan
  -> GestureCompiler
  -> immutable MotionProgram
  -> one time-domain MotionIntegrator
  -> Route
  -> verification, fidelity audit, viewer, and review artifacts
```

### RidePlanner

The planner owns story grammar, configuration resolution, terrain/corridor budgets, stable recipe
selection, and all seeded variation. It uses conservative analytic capability ranges before any
dynamic solve. It reserves the return and station-approach degrees of freedom from the beginning
rather than hoping a final patch can close an arbitrary route.

Randomness exists only in planning. A plan records all selected recipe IDs and resolved physical
targets; compilation and generation receive no RNG. Stable, named decision streams prevent solver
iterations or optional branches from consuming hidden random state.

The plan and audit persist the normalized-config hash, exact preset, recipe-catalog and evidence-
catalog content hashes, compiler/kernel and decision-stream versions, and the provenance of every
resolved decision. The same inputs are byte-identical on the pinned Godot build and platform.
Across supported platforms, discrete topology, identifiers, ordering, and canonical rounded reports
are identical; raw floating arrays are compared with declared numeric tolerances rather than a false
cross-platform byte-identity promise.

### Gesture recipes

A recipe is a high-level FVD gesture: family and story role, duration range, proper-force
character, roll character, longitudinal drive, scale class, terrain relationship, and terminal
intent. It does not own a separate geometry representation.

Each gesture owns its entry shoulder, core, exit shoulder, and any propulsion coincident with it.
There are no `GRADE`, `CLOSURE`, `_level`, `_align`, short-section drops, or standalone connector
types in the final runtime. Grade, height, heading, and endpoint pose are outcomes or residuals
compiled through the same physical law.

Recipes may use small, declared, bounded root solves over their own duration or profile parameters.
They may evaluate the same integrator at a coarser step while solving. They may not move arbitrary
track points, search an open-ended route space, silently relax a target, or append a repair after
the route is generated. Failure returns the recipe, seed, variables, bounds, and residuals before
the candidate route is committed.

### MotionProgram

The only flown-track intermediate representation is an ordered sequence of serializable physical
profile spans. Profiles use a small fixed polynomial vocabulary and carry explicitly named units:

- dimensionless `normal_g`, `lateral_g`, and `longitudinal_g` proper-acceleration channels;
- `roll_rate_rad_s` in radians per second;
- `duration_s` and stable gesture metadata.

Integrator position, velocity, acceleration, time, and distance are SI. Resistance returns m/s2.
Any degrees-per-second authoring input is converted once at configuration/catalog ingestion.

Profiles are piecewise smooth in time. Adjacent spans match the required endpoint values and first
and second derivatives; transition shoulders are compiled as part of the owning gesture. Internal
polynomial or Bézier mathematics is permitted as a representation of a force profile or as a solver
seed. It may never author an independent position-space track.

## 5. One time-domain FVD kernel

Time is the sole integration domain. It directly represents measured force duration, roll rate,
launch onset, pacing, and the requested ride duration, and it avoids the `1/v` clock and roll
singularities of an arc-length kernel.

For unit tangent `T`, rider up `U`, rider right `R = T x U`, speed `v`, position `r`, accumulated
distance `s`, gravity vector `g`, standard gravity `g0`, dimensionless proper controls `normal_g`,
`lateral_g`, and `longitudinal_g`, roll rate `omega_rad_s`, and the central resistance acceleration
`drag_mps2`, the governing law is:

```text
a_perp = g - dot(g, T) T + g0 (normal_g U + lateral_g R)
dr/dt  = v T
ds/dt  = v
dv/dt  = dot(g, T) + g0 longitudinal_g - drag_mps2(v, configuration)
dT/dt  = a_perp / v
```

The rider frame is parallel-transported with the changing tangent and rotated about `T` by
`omega`. Every numerical step re-orthonormalizes the frame. Gravity acts once: longitudinal proper
drive is not allowed to double-count grade acceleration.

At rest or arbitrarily low speed, FVD cannot robustly define curvature. The kernel therefore defines
`MIN_MOVING_SPEED = 2.0 m/s`. Below that speed, only explicit station launch/hold mode is legal:
controls must make transverse inertial acceleration zero within the integrator tolerance,
`roll_rate_rad_s` must be zero, tangent and frame remain fixed, and longitudinal acceleration alone
advances speed. The moving law begins only after a transition shoulder reaches the threshold with
zero curvature jet. Any later candidate falling below the threshold outside station mode is
rejected. This is not a second bootstrap integrator and contains no epsilon-dependent geometry.

The final route uses a deterministic 100 Hz integration step so verification reads native time
semantics and the fastest intended speed still advances roughly one metre per step. Bounded recipe
solves use the same kernel at a coarser step; the accepted program receives one full-resolution
integration. Selected convergence tests compare against a finer step.

The integrator also emits the one authoritative continuous `Trajectory`: per-step dense output
derived from the same integration state and derivatives, with a documented local error bound. All
sampling evaluates this trajectory; no consumer fits another curve. Safety checks use adaptive
subdivision or conservative swept enclosures from the authoritative segments, including integration
error. Uniform-arc samples are views for rendering and reporting only and never feed clearance,
self-intersection, force reconstruction, or other verification.

## 6. Boundary and closure contract

At every moving gesture boundary, the compiler and verifier derive an arc-length boundary jet from
the actual physical state:

- position and tangent;
- curvature vector;
- first and second arc-length derivatives of curvature;
- rider-frame orientation;
- roll rate and roll acceleration;
- speed and tangential acceleration;
- normal, lateral, and longitudinal proper acceleration and their bounded rates.

Matching force values alone is insufficient because speed, gravity projection, and frame
orientation also determine curvature. The C4 guarantee requires C2 physical controls and resistance
law, C2-compatible frame transport, matching time-domain control derivatives, and speed bounded by
`MIN_MOVING_SPEED` at every moving seam. The compiler propagates time derivatives through the
dynamics and converts them to arc-length curvature derivatives with the chain rule. It does not use
finite differences as proof. Under those explicit hypotheses curvature is C2 in arc length and the
centerline is C4; numerical samples only validate convergence against the analytic boundary jet.

Station return targets a planner-reserved capture manifold rather than an arbitrary pose. The
manifold is a bounded interval on the station centreline, at station height, with station yaw,
level pitch and roll, a structurally zero curvature jet, and a brake-entry speed band. A straight
FVD brake/transfer span then reaches the fixed station endpoint.

The return recipe has five bounded variables: lateral pulse amplitude and timing skew, normal pulse
amplitude and timing skew, and authored roll-pulse area. Its five normalized residuals are
cross-track offset, height, yaw, pitch, and terminal frame roll; along-track capture position is free
inside the manifold interval. C2 terminal shoulders make the zero curvature jet structural, while
the roll residual accounts for both the incoming frame and parallel-transport holonomy. Brake-entry
speed must fall inside the manifold band and is not tuned with hidden return propulsion.

A deterministic box-constrained trust-region root solve receives at most 40 coarse trajectory
evaluations, including error-estimate evaluations. The authoritative integrator supplies a
conservative coarse-to-100-Hz error bound for every capture residual, derived from its local error
enclosures and checked by step-doubling tests. Coarse acceptance requires `abs(residual) + bound` to
fit inside the final manifold tolerance. The preset capability envelope is a conservative tested
subset of this parameter box, and upstream pins outside its finite compatibility graph are rejected
during planning. Failure to capture is reported before the one full-resolution integration; a
full-resolution miss inside the certified margin is an integrator correctness failure, never a cue
to retry or repair. No position-space Bézier, frame reset, alignment turn, or post-hoc translation
is accepted as closure.

## 7. Honest longitudinal dynamics

One central resistance model owns rolling and aerodynamic loss. Propulsion and braking are explicit
profile channels, never hidden energy corrections. Changing propulsion may change the resulting
geometry through the physically changed speed, but it does not change the geometry law.

The default ride's unpowered climb and return must visibly lose speed. No per-section drag override
may prop up average speed, and elapsed average speed is an observed result. The resistance model,
vehicle assumptions, and any calibration evidence appear in the audit. If evidence cannot support a
parameter, the report labels it as a design assumption.

## 8. Evidence catalog and alignment

The deterministic audit is offline. Web and browser research produces reviewed, committed evidence
records; normal generation and CI never depend on YouTube, RideForcesDB, or live network state.

Every evidence source records URL or recording ID, retrieval context, row/seat, device, sample rate,
axis mapping, reliability, processing, caveats, and applicable ride/element windows. Executable
targets retain both the raw observed band and the separate fictional design transform.

Initial reviewed sources include:

- Falcon's Flight real forward and backward POVs for sequence, geometry, pacing, terrain, and flow;
- the continuous CoasterTalk Source telemetry POV `0UaOSBGSx20` for synchronized three-axis
  landmarks, with its unknown row/device/sample-rate limitations preserved;
- the separate edited CoasterTalk review `seNRpi4wP-s` only for sparse, element-visible landmarks
  and whole-run extrema, never an absolute ride timeline;
- RideForcesDB 4804 only where its unreliable wrist recording can be corroborated;
- RideForcesDB 6383 and the Tormenta element order with explicit attribution caveats;
- the I305 synchronized overlay as element-family force/duration evidence;
- the unobstructed simulation POV only as model-to-model visual evidence, never measured truth.

RideForcesDB traces are matched to an element using named sequence, POV landmarks, trace order, and
where available angle/orientation channels before comparison. The audit preserves physical seconds
and also emits phase-normalized overlays; phase normalization cannot replace or conceal a duration
miss. Row effects remain separate.

Only explicitly approved transforms are applied: positive/negative vertical, lateral, and negative
longitudinal are separate axes. No positive-longitudinal multiplier is inferred from another axis.
Each transform has an immutable ID, formula, approval provenance, and applicable axes. Transforms
scale the force target, not source duration, geometry, or time. Unknown mappings remain evidence
gaps.

Evidence records move through explicit states: `review_pending`, `observation_only`,
`corroborative`, and `executable`. Only executable records can define comparison bands. Promotion
requires a committed source artifact or content digest, retrieval date, exact window, axis mapping,
transform ID, confidence rationale, and corroborating links where the source is not independently
reliable. Unknown device/sample-rate video never becomes a fabricated dense executable trace.

Video evidence without a machine-readable calibrated trace contributes timestamped landmarks,
visible values, phase order, geometry, flow, and human-review prompts. It is never converted into a
fabricated dense signal. The review output links real timestamps to corresponding generated beats
and POV frames.

## 9. Fidelity audit and retained diagnostics

The audit measures the fixed fifteen-seed fleet and keeps loads, geometry/scale, pacing/energy,
terrain/AGL, and flow/transitions separate. It emits `within`, `under`, `over`, `observed-only`, and
`evidence-gap` findings and never collapses them into an overall fidelity score.

The existing diagnostic generator is retained as a product capability, not as frozen code. It must
continue to emit:

- per-element side/profile images;
- whole-route top and elevation images;
- whole-ride force, speed, pitch, roll, and AGL channels.

It is extended with longitudinal proper acceleration, curvature, radius, roll acceleration, and
jerk; actual RideForcesDB element overlays; source/target bands; synchronized POV review mappings;
and the unscored shaping, feel, speed-perception, and support-overlap checklist. PNG remains the
default because it is already supported; SVG is added only if a concrete review need justifies the
extra path.

The audit measures time-weighted pacing, correct exact-duration held values, meaningful
non-coincident transition windows, stable beat identities, row-shifted element attribution, and
checked artifact writes. The current fidelity implementation is characterized first and then
refactored or rewritten wherever it violates these semantics.

## 10. Curvature and smoothing integrity

Generated positions are direct integrator output. No geometry smoothing, fitted replacement curve,
radius clamp, or viewer-only path may feed physics or verification.

The audit independently reconstructs inertial acceleration and rider-frame proper acceleration
from position, time, speed, gravity, and frame. It compares:

- authored force against reconstructed force;
- geometric curvature against the force/speed-derived curvature;
- raw curvature and curvature derivatives across every boundary;
- normal integration against a finer-step convergence run;
- unsmoothed generated channels against explicitly labelled source-filtered channels.

Filtering is allowed only for a documented evidence comparison or the existing human-tolerance
verification model. It never changes the generated route. A force target cannot be reached by
tightening an unreported radius, and a visual shape cannot be improved by smoothing away its
physical loads.

## 11. Efficiency contract

The medium/high-level workflow must support several useful iterations inside a ten-minute design
session. Correctness is measured with deterministic work counters before wall-clock budgets:

- no full-resolution integration during discrete planning;
- no RNG or route search during generation;
- bounded, reported coarse evaluations per recipe;
- exactly one full-resolution integration of the accepted MotionProgram;
- no full-route candidate loops, post-processing passes, or duplicate time/distance kernels;
- packed typed sample buffers and no per-step dictionaries in the hot loop.

The audit generates each seed exactly once per run. Local and CI timings are recorded after the work
shape is correct; GitHub Actions remains the performance verdict environment.

## 12. Error handling and observability

Configuration, planning, recipe compilation, integration, verification, catalog validation,
generation, and artifact writing have distinct failures. Every failure includes the config/preset
version, seed, story-slot and gesture/recipe IDs, failed invariant, and relevant bounds or
residuals. There is no silent skip, generic fallback element, automatic target relaxation, or
partial route success.

Resolution reports expose every preferred adjustment. Compile reports expose solver evaluation
counts and terminal residuals. Audit reports expose provenance and evidence gaps. Fidelity misses
remain diagnostic; malformed data, failed generation, physical inconsistency, or failed writes are
operational errors.

## 13. Migration and cutover

Implementation is test-first. The new motion kernel and recipe compiler are built behind focused
tests while the legacy generator remains available only as a characterization oracle. The runtime
does not ship with two selectable geometry systems.

The stable consumer boundary is defined first. `Route` owns the authoritative `Trajectory`, native
time samples, distance, position, tangent, rider-up, speed, three proper-g channels, roll rate,
gesture windows/metadata, terrain reference, configuration and catalog fingerprints, resolution
report, solver counters, and verification inputs. Viewer, verifier, smoke, and audit consume only
this contract. Uniform-distance views are derived read-only data and never replace the trajectory.

Cutover proceeds through independently verified gates:

1. final `Route` contract and consumer characterization;
2. configuration normalization, overlay, planner, hashes, and conflict reporting;
3. time-domain kernel, analytic boundary jets, authoritative trajectory, and proven capture
   manifold/closure envelope;
4. complete default recipe set and evidence-backed demo behavior;
5. corrected evidence catalog, overlays, audit, POV and PNG review pack;
6. runtime cutover and deletion of legacy `FVD`/`GRADE`/`CLOSURE` execution paths and connector
   repairs.

Each gate has deterministic, correctness, and work-counter acceptance criteria before the next
becomes authoritative. Existing tests that encode safety, physics, determinism, or stable external
commands are retained. Tests that merely freeze poor ride behavior are replaced with evidence-backed
assertions.

Failure during implementation triggers systematic diagnosis. If the failed abstraction caused the
problem, it is refactored or rewritten; the implementation does not accumulate compatibility shims,
special-case seed fixes, or tolerance inflation.

## 14. Verification and review gates

The implementation plan must include failing tests before each behavior change and, at minimum:

- analytic straight, launch, constant-curvature, banked-turn, and inversion kernel cases;
- rest-boundary validation and gravity/no-double-counting tests;
- profile C2 and derived arc-length C4 boundary-jet tests;
- frame, roll-rate, roll-acceleration, force, onset, and jerk continuity tests;
- deterministic config normalization, preset resolution, required/preferred conflicts, and stable
  plan generation;
- bounded recipe and station-return solve tests, including explicit impossible cases;
- central drag/rolling-loss and unpowered energy-bleed tests;
- terrain, clearance, self-intersection, and support-overlap review coverage;
- evidence catalog schema, provenance, axis transform, row, duration, and element-alignment tests;
- corrected held-value, time-weighted pacing, transition-window, aggregation, and deterministic
  ranking tests;
- the fifteen-seed audit twice with byte-identical JSON and Markdown and complete review artifacts;
- proof that each seed is generated once per audit and each accepted route is integrated once at
  full resolution;
- required Godot import and smoke commands plus fresh generated-POV and PNG inspection.

Final review is adversarial. Independent reviewers must challenge physical equations, numeric
stability, source attribution, transforms, catalog claims, boundary continuity, smoothing integrity,
constraint semantics, deterministic ordering, performance counters, failure paths, and unnecessary
code. Review suggestions are verified rather than accepted performatively. Completion requires
fresh evidence from the verification commands and inspection of the final diff and generated
artifacts.
