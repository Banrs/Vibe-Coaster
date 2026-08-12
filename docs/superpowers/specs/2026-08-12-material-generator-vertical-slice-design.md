# Material Generator Vertical Slice Design

> **Status:** execution addendum to the approved FVD-informed configurable-generator design. The
> user's 2026-08-12 direction stops evidence-baseline remediation and authorizes material generator
> work now. This document changes implementation sequence and trims speculative architecture; it
> does not weaken the approved product, physics, safety, determinism, or diagnostic contracts.

## 1. Problem

The current implementation can pass its gates while still producing the same poor ride. Its
2,604-line generator and 1,452-line element library mix force-authored sections, separately authored
grades, trial integrations, alignment helpers, beat omission, and a degree-nine Bezier closure. The
earlier four-plan sequence would first add adapters, types, and a dormant candidate pipeline, leaving
the public ride materially unchanged for most of the program. That is the wrong risk order.

The next checkpoint must visibly change the route produced by `RideGenerator.build`: element shape,
speed history, proper-force history, pacing, terrain relationship, transitions, and station return.
It must also be a smaller and sounder base for a spectrum from one-click presets to a guided
medium/high-level generator that can produce a coherent desired ride in under ten minutes.

## 2. Decision

Build one thin, complete vertical slice and cut it into the public generator atomically:

```text
validated config + seed
  -> deterministic story plan
  -> one ordered physical motion program
  -> bounded local recipe/capture solves at coarse resolution
  -> exactly one accepted 100 Hz integration
  -> existing packed route contract
  -> verifier, viewer, audit, and diagnostic images
```

There is no legacy adapter, selectable second generator, candidate hidden behind the old ride,
post-generated repair, or fitted display route. The current packed route dictionary remains the
consumer boundary because every surviving consumer already uses it efficiently. It receives a
strict schema validator and explicit semantic windows; preserving that useful boundary is not
preserving legacy generation.

## 3. Lean ownership

Production code has four responsibilities, implemented in four focused source files with one-way
dependencies:

```text
route/config catalog -> planner/program compiler -> pure motion kernel -> route contract
```

- `generator.gd`: public facade, strict version-1 configuration, deterministic named decision
  streams, and high-level story planning against the catalog exposed by `ride_program.gd`. It
  contains no numerical integration or geometry repair.
- `motion.gd`: the small physical profile vocabulary, immutable span records, time-domain dynamics,
  frame transport, central resistance, packed output buffers, and focused numerical helpers.
- `ride_program.gd`: the default preset's recipe/grammar catalog, gesture compilation, bounded
  recipe solves, reserved-corridor capture solve, and compilation report. It receives no RNG and
  never imports the planner.
- `route_contract.gd`: route construction/schema validation, the authoritative integration result,
  and semantic sample/time/distance windows. It owns the dynamics-derived dense-output coefficients
  or handle used by every sampler and adaptive verifier; no consumer fits a second trajectory.

Do not create one class per noun from the old plans. Tests may be split by behavior, but production
abstractions must earn their existence through multiple real callers or hot-loop clarity.

After runtime cutover, delete the old authoring and repair implementation. Move the seven row offsets
to the verifier/route contract before deleting `elements.gd`. Keep only independent verification,
sampling, terrain, viewer, and diagnostic code.

## 4. Configuration foundation

Version 1 deliberately supports the useful bounded subset already approved for schema version 1:

- `preset`, `seed` for one-click generation;
- preferred global targets for duration and top speed;
- catalogued, unit-bearing, slot-scoped preferences for structure height, intensity, and airtime
  character, but only where the owning recipe has a measured conservative capability range;
- preset-declared optional-slot enablement;
- recipe choice/pin only in catalog-declared story slots.

Omitted controls resolve to the preset. Unknown keys, impossible combinations, unsupported recipes,
scope/unit mismatches, required conflicts, and targets outside measured capability ranges are
errors. Resolution order is preset, named seed decision, then explicit user constraint; required
values conflict rather than silently merge, while preferred values report any bounded adjustment.
Every accepted value records stable ID, units, scope, source layer, and list position before
canonical ordering and hashing. No arbitrary node graph, raw spline control, raw force key editing,
or unrestricted sequence permutation is added.

Every supported control must have a material-response test: two valid configurations differing only
in that control must change the intended physical measurement monotonically while remaining valid.
A config field that does not drive the generated route is dead API and must be removed.
Inversion character, terrain relationship, pacing density, arbitrary ordering, and any other guided
control remain unavailable in schema version 1 until a later design version explicitly admits them.

## 5. Physical motion model

The authoritative integration domain is time. For tangent `T`, rider up `U`, right
`R = T cross U`, speed `v`, gravity `g`, and dimensionless authored controls, use:

```text
a_transverse = g - dot(g,T)T + g0(normal_g U + lateral_g R)
dr/dt         = v T
ds/dt         = v
dv/dt         = dot(g,T) + g0 drive_g - q(v)
dT/dt         = a_transverse / v
longitudinal_g = drive_g - q(v) / g0
```

The integrator carries and re-orthonormalizes the rider frame, applies authored roll as twist about
`T`, and records the same reference point the rider occupies. Gravity is applied once. Rolling and
quadratic aerodynamic loss come from one documented resistance function. Propulsion and braking
exist only in `drive_g`; no constant-speed mode, energy reset, per-section drag override, or hidden
target-speed correction exists.

The resistance magnitude for nonnegative forward speed is the explicit C-infinity law
`q(v) = rolling_mps2 + aero_per_m * v^2`, with nonnegative preset constants and analytic first and
second derivatives. It does not depend on an absolute or clamped load channel. Station mode uses the
same law; braking and drive commands remain explicit, and integration rejects negative speed rather
than changing resistance direction through an unmodelled reverse state.

Use projected deterministic RK4 with stage validation and a native production step of 0.01 s. Split
steps exactly at every span and station/moving-mode boundary; an RK stage never changes owning span.
Coarse recipe solves use the same equations. Step-halving against analytic cases must demonstrate
the expected convergence rate. Any dynamics-derived dense output is explicitly a numerical
approximation and must reproduce native nodes, preserve monotone distance inversion, and quantify
the defect in `dr/dt = vT`; neither it nor a rendered polyline independently claims C4. The hot loop
uses typed locals and pre-sized packed arrays, not per-sample dictionaries or RefCounted objects.
The accepted program is integrated once at production resolution; read-only rendering samples never
feed physics or verification.

Below 2 m/s, only an explicit straight station span is legal. It keeps the frame fixed, has
analytically zero transverse acceleration and its first two derivatives, and zero roll rate and roll
acceleration. It changes speed through longitudinal drive/brake only. Speed may be zero only at the
initial stage. Every later stage must be finite and nonnegative and every accepted interval must
advance distance. Moving spans fail before division if any stage crosses the speed floor. Tangent or
frame degeneracy is always an error.

The profile vocabulary is intentionally small: constant and normalized quintic C2 transitions,
plus fixed compact pulse bases composed from them. Adjacent gesture shoulders match control values
and their first two time derivatives. Freeform lookup curves and post-hoc smoothing are forbidden.

## 6. FVD-informed, not dogmatic

Most flown elements are authored in rider-frame force and roll because that directly controls ride
feel. Analytic layout calculations may reserve corridors, seed bounded solves, and reject impossible
plans before integration. They may not replace the generated position history.

The openFVD source at commit `4482a15b388f76158c0b189068be96b4a45c2509` supports four reusable
ideas: proper-force projection into curvature, transported rider frames, roll as twist, and quintic
shoulders. Its mixed forced/geometric/Bezier section architecture, order-dependent discrete
rotations, constant-speed escape hatch, freeform lookup profiles, export fitting, and roll smoothing
are not copied.

Bezier and C4 are not competing kinds: a Bezier curve can satisfy C4 endpoint constraints only when
enough control-point jets are constrained. The current closure does not establish the full physical
boundary-jet contract and acts as a large repair. It is deleted. A Bezier or Hermite basis is allowed
only as a dynamics-derived numerical interpolant whose defect is measured; independently authored or
post-hoc position geometry is forbidden. No continuity claim follows merely from degree or appearance.

## 7. Complete default ride

The first authoritative program is a complete coherent ride, not a disconnected element demo:

1. straight station launch with a high-speed, roughly 4 g-class entry acceleration;
2. fast opener crest and twisted non-inverting side drop;
3. one flowing act-one arc with giant inversion, cutback, hills, and wave-turn character;
4. explicit LSM2 followed by an unpowered, visibly decelerating escarpment climb;
5. the ride's single slow crest beat and compact outward-rim suspense;
6. monotonic cliff dive with no lip pause;
7. explicit tunnel LSM3 to the top-speed class;
8. a genuinely scaled marquee camelback;
9. one energy-bleeding raceway return with embedded airtime/release beats;
10. honest brakes and continuous station capture.

Exactly three contiguous positive-drive zones appear in order. The climb and return have no positive
drive. Small connective changes are owned by neighboring gestures' shoulders; there are no `GRADE`,
`CLOSURE`, `_level`, `_align`, filler-turn, or dropped-short-section runtime types.

## 8. Reserved station capture

The planner reserves the station-local approach tube, capture interval, brake distance, and incoming
capability envelope before choosing upstream variation. The return is a fixed-topology C2 force/roll
profile with five bounded coefficients:

- early and late lateral pulse coefficients;
- early and late normal pulse coefficients;
- signed roll-pulse area.

Those five controls solve the generic five equality residuals after along-track capture is freed:
cross-track, height, yaw, pitch, and terminal frame roll. Pulse bases have zero value and first two
derivatives at their outer boundaries; the terminal shoulder is structurally level, straight, and
unrolled. Along-track interval, brake-entry speed, speed floor, corridor containment, force limits,
and roll limits are inequalities, never hidden residual relaxation.

Use an analytic linearized seed and one deterministic box-constrained root solve with at most 40
unique coarse trajectory evaluations, including one finer-step comparison. Cache identical vectors.
On failure, compilation stops with bounds, residuals, margins, and evaluation counts—no retry,
fallback, beat deletion, translation, frame reset, positive return drive, or position-space closure.
The final 100 Hz trajectory rechecks capture and endpoint invariants without reintegration.

After capture, a separate deterministic straight-span construction consumes the recorded remaining
along-track distance. A bounded C2 longitudinal brake profile reaches exactly 2 m/s at a native
moving/station boundary, then a straight station-mode C2 brake/creep profile reaches the fixed
endpoint at the preset's positive terminal creep speed. Its distance integrals are solved directly
from duration/profile area and the central resistance law, screened at coarse/fine resolution, and
use `drive_g <= 0` throughout. An infeasible distance or speed is a planning/recipe failure, not a
sixth capture variable, fourth positive-drive zone, retry, or endpoint overwrite.

## 9. Material acceptance

A runtime cutover is accepted only when all of these are true for seed 42 and structurally true for
the full 15-seed fleet:

- the route's position, speed, and proper-force hashes differ from the preserved legacy baseline,
  and committed baseline measurements show nontrivial changes in geometry, speed, force, pacing,
  and terrain relationship rather than a one-bit hash change;
- all ten story beats resolve to non-empty semantic windows in order;
- propulsion zone IDs are exactly `[1, 2, 3]` and no other positive drive exists;
- LSM2 ends before the climb, and speed then decreases to the one slow crest beat;
- the dive loses height monotonically through its core;
- LSM3 materially increases speed and the camelback follows immediately at marquee scale;
- unpowered return mechanical energy and speed trend downward apart from gravity exchange;
- every gesture owns smooth entry/core/exit shoulders; no flat connector exists between gestures;
- raw curvature and force channels show no clamp, smoothing, fitted replacement, or viewer-only path;
- capture, clearance, self-clearance, frames, load envelope, determinism, and one-integration work
  counters pass.

Existing smoke assertions that encode the old `FVD`/`GRADE`/`CLOSURE` taxonomy or poor dimensions
are replaced by these physical/story assertions. Independent safety and human-tolerance checks stay.

## 10. Diagnostics and evidence

The legacy diagnostic pack is preserved under ignored `out/baselines/legacy-audit-2a891d2` with
SHA-256 `d828a09d00e78de564b8a2165343e051bf63a2af856a0b375cdae444e2f420ff`.
Post-cutover generation must retain:

- per-gesture side/profile views;
- whole-route top and elevation views;
- speed, vertical/lateral/longitudinal proper g, pitch, roll, AGL, curvature/radius, roll
  acceleration, and jerk channels;
- POV landmarks and an unscored human review checklist.

Geometry comparisons use generated dimensions directly. POV timing uses explicit local
entry/apex/exit landmarks and uncertainty, never a global warp. Until a raw RideForcesDB recording
with digest, cadence, row, and axis mapping is actually acquired, its reviewed ranges appear as
separate source bands—not fabricated source traces. Fictional per-axis multipliers create a separate
target lane and never alter observed durations.

## 11. Efficiency and deletion budget

The final implementation must reduce production authoring code materially. At this checkpoint, the
target is fewer than 2,500 combined non-test lines across every production file serving config,
planning, recipes, integration, route construction, and their helpers—not merely the four named
files—and deletion of the current 4,056 generator/element lines. This is a checkpoint review budget,
not a permanent cap on future additive preset modules or permission to compress unreadable code.
There is no full-route candidate loop, full-resolution solve iteration, duplicate sampler,
generalized optimizer, or abstraction used only once.

## 12. Out of scope for this checkpoint

- a node editor or unrestricted track drawing;
- arbitrary user-authored force keys;
- a general-purpose optimizer or multiple ride presets;
- restraint, support-structure, train-flex, or suspension simulation;
- treating unverified web traces as hard gates;
- visual polish unrelated to reading the generated ride.

The resulting contracts must make additional presets and guided controls additive, but no dormant
framework is built for them now.
