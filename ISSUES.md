# Vibe-Coaster — Geometry, Ride Quality, Pacing, and Presentation Defect Register

> **Replacement source of truth.** This document is intended to replace `docs/ISSUES.md` and any separate “suggested fixes” notes. It records current defects, their verified mechanisms, the required remedy, and the evidence needed before closure. Historical experiments belong in dated design/experiment documents, not in this issue register.
>
> **Audit revision:** 2026-08-16  
> **Repository:** `Banrs/Vibe-Coaster`  
> **Audited branch:** `main`  
> **Audited commit:** `2686fcb53fa95a65a19456251741672453ea21bc`

## 1. Purpose and audit basis

The current ride can be numerically valid while still looking and feeling wrong. The reported symptoms—incorrect geometry, transitions that are technically joined but perceptually micro-stitched, apparently arbitrary banks, poor terrain use, weak pacing, and a horrendous sense of speed—are not isolated tuning mistakes. They are the visible result of several architectural choices reinforcing one another.

This audit examined the project from macro to micro along five tracks:

1. route story, terrain placement, role lengths, and global closure;
2. element morphology, banking intent, and transition construction;
3. the motion integrator, force profiles, interpolation, and validation gates;
4. POV camera, rendering, scenery density, and speed cues;
5. test coverage, evidence handling, and issue-management quality.

The audit is based on the source, committed diagnostics, telemetry, and the previous issue log at the commit above, together with the user’s direct visual observations. No fresh executable render was produced in this review environment. Consequently:

- **Confirmed** means directly established by source or committed measurements.
- **Corroborated** means the source mechanism and the user-visible symptom agree.
- **Needs capture** means the mechanism is confirmed, but a new deterministic visual baseline is still required to quantify the result after changes.

The central conclusion is firm even without a new render: the current system optimises force traces and exact endpoint closure more strongly than it preserves coherent track geometry.

## 2. Executive verdict

The generator is currently a **time-domain force-program compiler with global endpoint solves**, not yet a robust geometric coaster generator.

Its high-level failure chain is:

```text
fixed story + hard role-length bands + sparse terrain anchors
                         ↓
global solvers spend durations and banks to satisfy placement/closure
                         ↓
local element silhouettes and bank narratives drift
                         ↓
short self-contained force/roll pulses stop and restart inside transitions
                         ↓
seam checks pass because endpoint jets match, while the shape still looks stitched
                         ↓
linear rendered chords + sparse high-AGL scenery weaken speed and expose faceting
```

The problem is **not FVD itself**. Force-vector design can produce excellent geometry. The problem is that this implementation authors generic loads and roll rate primarily over **time**, lacks explicit geometric element contracts, and then lets global solvers alter local timings and banks. A transition can therefore be mathematically smooth at every named seam and still be visually incoherent, over-segmented, or unrelated to the intended element.

The correct response is not another magic-number pass. The required direction is:

- retain the physically integrated rider-frame kernel where it remains useful;
- move element authoring to arc length or geometric phase;
- give every element an explicit entry/exit and silhouette contract;
- make one continuous roll function own each intentional bank transition;
- solve macro layout before local geometry, not by deforming finished elements;
- make geometry and terrain fidelity hard acceptance gates;
- fix rendered interpolation and speed cues only after the actual track is honest.

## 3. Priority definitions

| Priority | Meaning |
|---|---|
| **P0 — Architectural blocker** | Prevents trustworthy geometry or makes later tuning disposable. Fix before adding content or polish. |
| **P1 — Major ride-quality defect** | Materially damages element identity, pacing, terrain use, or POV quality. |
| **P2 — Validation/maintainability gap** | Allows regressions or makes defects difficult to diagnose and close. |
| **P3 — Operational/polish issue** | Worth retaining, but not a reason to delay the geometry rewrite. |

## 4. Root causes that must be fixed, not worked around

### RC-A — The independent variable is wrong for reusable geometry

`godot/motion.gd` samples normal G, lateral G, drive G, and roll rate at normalised **span time**. Spatial curvature then follows from the current speed:

```text
curvature_vector = transverse_acceleration / speed²
```

The same time profile therefore produces a different spatial shape when entry speed, gravity projection, drag, or an upstream element changes. A local element is not geometrically local: small upstream changes can reshape and reposition everything downstream.

### RC-B — Elements have names, but not complete geometric contracts

Roles and diagnostic windows identify an “Immelmann”, “cutback”, “wave”, “camelback”, and so on, but the compiler does not require each one to meet declared entry/exit pitch, heading, bank, curvature, torsion, planarity, height, width, or apex conditions. Most current contracts are force bounds, role-length bands, terrain checks on a few anchors, and terminal closure.

### RC-C — Global closure is allowed to consume local aesthetic variables

The prefix solve changes four authored durations to hit dive/tunnel/summit/speed targets. The return solve changes large banks, durations, airtime timing, and peak load to reach the station corridor. The final capture then solves five pose residuals in 1.05 seconds. These are powerful numerical tools, but their objective functions do not include coherent element shape.

### RC-D — “Smooth at a seam” is mistaken for “smooth as a ride”

The compiler checks C2 continuity of control signals at span boundaries. `verify.gd` samples curvature derivatives at those same boundaries. Neither test prevents a span from containing a complete pulse that rises, falls, and returns to zero, followed immediately by another complete pulse. The result is legal at the seam but perceptually reads as roll → pause → roll or turn → straighten → turn.

### RC-E — Most of the route is placed above terrain rather than designed through it

The terrain model is a useful seeded escarpment heightfield, but the planner constrains only a small subset of the route against it. The route is not laid out through terrain corridors. Committed measurements show long high-AGL sections, especially in the return, which removes near-field optic flow and makes extreme numerical speeds feel slow.

### RC-F — The viewer does not faithfully sample the integrated trajectory

The motion kernel contains Hermite dense-position sampling. The viewer instead linearly interpolates positions between samples and independently slerps orientation. Camera position thus follows short chords while the camera faces a separately interpolated frame. This can add subtle faceting or detachment even when the underlying trajectory is acceptable.

---

## 5. Current issue register

### Architecture and macro layout

#### VC-001 — Element geometry is authored in time rather than arc length or geometric phase

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `godot/motion.gd`, `godot/ride_program.gd`

**Observed defect**

Element shape changes unpredictably when speed changes. Scaling a launch, moving an upstream beat, changing drag, or solving a duration can alter downstream radii, heading, height, and bank progression even when the nominal element recipe is unchanged.

**Verified mechanism**

All four controls are sampled using `u = elapsed / duration`. Tangent curvature is then derived from transverse acceleration divided by speed squared. A force curve that is coherent in time is not a fixed curve in space. Current comments already document extreme sensitivity of the prefix to tiny force perturbations.

**Required fix**

Introduce a geometric authoring layer. Each thrill element should be parameterised over arc length `s` or a normalised geometric phase whose mapping to `s` is explicit. Speed and force are then solved/evaluated on that geometry, or FVD is integrated with geometric endpoint constraints and a spatially defined profile.

Retain time-domain profiles for genuine infrastructure where time is the physical intent—launch acceleration, brakes, station motion—not as the default shape language for every element.

**Closure test**

For each element family, perturb entry speed across its certified range while holding its geometry parameters fixed. Height, width, heading change, apex location, exit frame, and sampled centreline must remain within declared geometric tolerances. Force traces may change; the element identity must not.

---

#### VC-002 — There is no first-class element boundary-state and silhouette contract

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `godot/ride_program.gd`, `godot/route_contract.gd`, `godot/geometry_metrics.gd`

**Observed defect**

Named elements can exit with unintended bank, heading, pitch, curvature, or torsion and still pass. A “camelback” can become a tilted three-dimensional manoeuvre; a “wave” can finish with residual frame twist; an inversion can be assembled from stopped half-rolls.

**Verified mechanism**

The plan declares role identity and length bands, but recipes do not publish and the route contract does not enforce a complete element state. Geometry metrics are post-hoc and report-only. Entry/exit control values being `1.0 G / 0 lateral / 0 roll rate` does not imply level bank, neutral torsion, desired heading, or a correct silhouette.

**Required fix**

Add an `ElementSpec`/`ElementResult` contract with, at minimum:

- input frame and speed range;
- exit pitch, heading, bank, curvature, and torsion targets/tolerances;
- intended planarity class;
- height, width, length, and heading-change bands;
- apex/inflection landmarks and monotonic phases;
- bank narrative and allowed roll reversals;
- terrain corridor and AGL intent;
- force and onset envelopes.

The element builder must either return a result satisfying the contract or fail with a structured diagnostic. A role name alone must never be evidence that the geometry is correct.

**Closure test**

Every material role has a reviewed specification and executable checks against the whole role. No role can be accepted solely because its constituent control seams are continuous.

---

#### VC-003 — Global solvers deform local elements to satisfy layout and closure

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `godot/ride_prefix_solve.gd`, `godot/ride_return_solve.gd`

**Observed defect**

Transitions, banks, and element proportions appear arbitrary because they are paying for distant endpoint constraints rather than expressing local track intent.

**Verified mechanism**

The prefix solve adjusts climb-core duration, pull-over duration, crest hold, and dive approach to satisfy dive span, tunnel span, summit rise, record exit speed, and dive arc length. The return solve adjusts turn banks of roughly 50–66° and 60–80°, core durations, recovery durations, airtime timing, and peak G to hit station/corridor residuals. Neither objective contains an element-shape cost.

**Required fix**

Split planning into two levels:

1. **Macro layout solve:** choose anchors, corridors, headings, elevations, reserved transition lengths, station approach, and terrain relationships.
2. **Local element solve:** fit each element inside its assigned corridor while preserving its own geometric contract.

The macro solve may move anchors or allocate length. It must not reach inside a completed element and arbitrarily alter its roll/bank narrative. If the assigned corridor cannot host the requested element, the plan is infeasible and must be redrawn at the macro level.

**Closure test**

A closure perturbation changes route anchors or neutral connectors, not the silhouette metrics of already accepted elements beyond their explicit parameter ranges.

---

#### VC-004 — The hard 7.8–8.2 km route band and fixed nominal role allocations encourage geometric bloat

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `godot/ride_program.gd`, `godot/ride_planner.gd`

**Observed defect**

Elements and returns are stretched to consume distance, creating oversized, weakly articulated geometry and long high-altitude travel. The nominal role lengths sum to approximately the lower edge of the total route band, so the length target is effectively designed into every build before terrain or element quality is considered.

**Required fix**

Make total length an outcome of the chosen story and site, with a broad design range rather than a closure target that every role must fill. Give roles semantic minimum/maximum geometry bands derived from their element family. Allocate uncommitted distance only to deliberately designed terrain runs or infrastructure—not by inflating turn cores, recovery holds, or return loops.

**Closure test**

Removing or substituting an optional element changes total route length naturally. No solver has to stretch unrelated roles to restore an arbitrary exact band.

---

#### VC-005 — Terrain is used as a backdrop and anchor check, not as a full-route design constraint

**Priority:** P0  
**Evidence:** Confirmed and corroborated  
**Primary code:** `godot/generator.gd`, `godot/terrain.gd`, `godot/route_contract.gd`

**Observed defect**

The route spends too much distance on stilts or in open air. Fast sections do not skim terrain, so the site contributes little to pacing or speed sensation. The return is especially detached from the landscape.

**Committed baseline**

The previous audit reports only about 20–27% of samples within 20 m AGL, roughly 2.8–3.2 km above 40 m AGL, return median AGL around 101–175 m, and the nominal tunnel role around 16–52 m AGL. The fastest decile reportedly never reaches 20 m AGL.

**Verified mechanism**

The generator fits the authored prefix to the escarpment and proves selected dive/tunnel relationships. It does not reserve or solve terrain corridors for every material role. The analytic terrain exists under the entire route, but most roles have no AGL or terrain-following objective.

**Required fix**

Perform terrain-aware macro routing before element generation. Every role receives a corridor with horizontal bounds, elevation/AGL intent, and clearance envelope. Distinguish:

- terrain-hugging speed runs;
- exposed height/suspense beats;
- structural record elements;
- tunnel/trench segments;
- station/maintenance infrastructure.

Do not apply one universal low-AGL target; use the contrast deliberately. The fastest sustained ground-run roles should be close enough to terrain to create optic flow, while designated scenic/suspense roles may remain high.

**Closure test**

Publish AGL distributions per role and speed decile. Designated terrain-hugging roles meet reviewed median and percentile bands, and the fastest decile includes a sustained near-terrain interval rather than being entirely elevated.

---

#### VC-006 — The drag and energy model is too permissive, flattening the pace

**Priority:** P1  
**Evidence:** Confirmed by current constants and committed audit  
**Primary code:** `godot/ride_program.gd`, `godot/motion.gd`

**Observed defect**

The ride maintains extreme speed too easily, reducing contrast between launches, drops, valleys, and recovery beats. High average speed does not automatically feel exciting; when almost everything is fast and elevated, acceleration cues and proximity contrast disappear.

**Verified mechanism**

Resistance is a simple rolling term plus `aero_per_m × v²`. The committed audit identifies the current aerodynamic coefficient as several times too low for an honest train model. An earlier honest-drag experiment failed to re-close the route, showing that the current geometry and closure depend on the permissive energy model.

**Required fix**

Derive drag from explicit train mass, rider mass, frontal area, drag coefficient, rolling resistance, wind assumptions, and any claimed fairing credit. Rebaseline the ride around that physical model. Retune launches, elevations, and element geometry afterwards; do not preserve canonical bytes or current endpoint timing at the expense of honest energy.

**Closure test**

The accepted route closes using the documented physical resistance model, with no hidden positive drive outside declared launch zones and no coefficient selected merely because it preserves the old route.

---

#### VC-007 — Seed variation is narrow, while the architecture is not actually composable

**Priority:** P2  
**Evidence:** Confirmed  
**Primary code:** `godot/ride_planner.gd`, `godot/generator.gd`

**Observed defect**

The project presents itself as a seeded generator, but the current sequence is canonical and most geometry is fixed. Variation is concentrated in terrain/placement and a few return targets. Attempts to reorder or perturb upstream cells often break prefix placement or return closure.

**Verified mechanism**

`_draw_sequence()` currently returns the fixed role order. Only a small set of return target values are drawn. Source comments document that most legal story orders do not build end-to-end and that tiny upstream target changes can move downstream geometry dramatically.

**Required fix**

Do not expand random draws yet. First make element outputs contract-stable and give the macro planner a real corridor/anchor model. Once cells are composable, allow sequence and dimensions to vary only over certified combinations. A seed should choose meaningful design decisions, not merely perturb a globally coupled trajectory.

**Closure test**

A matrix of legal element substitutions and orders builds without changing unrelated element geometry beyond declared entry-speed adaptation. Failed combinations are rejected at planning time with a clear corridor/energy reason, not after a distant return solve exhausts its budget.

---

#### VC-008 — The final capture is a hidden five-degree-of-freedom correction manoeuvre

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `godot/ride_return_solve.gd`

**Observed defect**

The return can finish with a short, visually unmotivated steering/roll correction before the brakes. It is a mathematically exact closure but not a recognisable coaster transition.

**Verified mechanism**

The capture consists of 0.45 s early steering, 0.45 s late steering, and a 0.15 s terminal shoulder. Five coefficients solve cross-track, height, yaw, pitch, and roll residuals. At the accepted 70–80 m/s entry band, this is only about 74–84 m of track in which to erase the remaining pose error.

**Required fix**

Eliminate pose repair from the final ride. Reserve a long, explicit station-approach corridor in the macro plan. The return must enter that corridor already within a narrow position/heading/elevation envelope. Use a recognisable sequence—return turn, straight or gently curving brake approach, brakes, station alignment—with geometric transitions sized before the solve.

A tiny numerical capture may remain only as an internal tolerance correction whose displacement and angle are below render/engineering significance and which cannot add a visible bank or lateral manoeuvre.

**Closure test**

Disabling the capture correction does not materially change the rendered centreline. The pre-brake route already satisfies the station approach contract, and the final visible approach contains no solver-authored steering pulse.

---

#### VC-009 — Geometry diagnostics are report-only and cannot reject a bad ride

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `godot/geometry_metrics.gd`, `godot/fidelity.gd`, `godot/verify.gd`

**Observed defect**

The repository can measure roll segmentation, planarity, and shape ratios yet still publish geometry known to be wrong. Passing load, clearance, and seam checks is treated as route validity even when the element silhouette is visibly unacceptable.

**Required fix**

Promote reviewed geometry intent into route acceptance. Keep exploratory metrics report-only while thresholds are being established, but every production material role must eventually have adopted gates. At minimum, gate:

- whole-element boundary frame;
- intended planarity/non-planarity;
- height/width/length and heading change;
- roll segment count and allowed reversals;
- curvature/torsion continuity and extrema count;
- key landmarks such as apex pitch and drop steepness;
- role-specific AGL/corridor compliance.

**Closure test**

A deliberately distorted camelback, split-roll Immelmann, over-segmented wave, and elevated “terrain run” each fail the production validation suite for a specific geometric reason.

---

#### VC-010 — The current issue log is not a usable source of truth

**Priority:** P2  
**Evidence:** Confirmed  
**Primary document:** `docs/ISSUES.md` at the audited commit

**Observed defect**

The existing file is a long chronological laboratory notebook. Current defects, stale measurements, attempted fixes, superseded hypotheses, solver refusals, and partial closures are interleaved. A reader cannot reliably determine what remains open, what mechanism is proven, or what fix is authorised.

**Required fix**

Replace it with this register. Keep one current record per defect. Move experiments and rejected approaches into dated files under `docs/superpowers/specs/` or an `experiments/` directory. Every issue must contain a current status, evidence, required fix, and closure test. Closing an issue requires an artifact or test, not prose saying it “should” be fixed.

**Closure test**

A new contributor can identify the P0 work, understand its dependency order, and locate the evidence for every open issue without reading git history or several thousand lines of chronology.

---

### Element morphology and banking

#### VC-011 — The opener drop exits through a four-fragment micro-unbank

**Priority:** P1  
**Evidence:** Confirmed and corroborated  
**Primary code:** `RideProgram._add_opener()` in `godot/ride_program.gd`

**Observed defect**

The twisted drop does not resolve in one coherent roll/load transition. It visibly feels assembled from small corrective pieces before the teardrop begins.

**Verified mechanism**

The exit is split into approximately:

- 0.115 s `drop/unbank-in`;
- 0.185 s `drop/unbank-recover`;
- about 0.035 s `drop/unbank-hold`;
- 0.115 s `drop/unbank-out`.

Normal load recovery and roll-rate shaping are distributed differently across those fragments. The shortest semantic “hold” is only a few hundredths of a second and has no perceptible design meaning.

**Required fix**

Replace the sequence with one continuous exit transition defined by the intended drop exit bank, curvature, and next-element entry state. It may have internal spline knots for numerical evaluation, but those knots must not represent separate stop/start motions or independent semantic spans.

**Closure test**

Roll rate, roll acceleration, curvature, and torsion remain continuous and single-lobed across the whole drop exit. No interior flat-roll interval appears while the bank change is incomplete.

---

#### VC-012 — The Immelmann half-roll is split into two self-contained stopped pulses

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `RideProgram._add_act_one_immelmann()`

**Observed defect**

The inversion reads as two stitched roll events rather than one continuous 180° rotation through a coherent Immelmann top and recovery.

**Verified mechanism**

`immelmann-roll` and `immelmann-recover` each carry a compact pulse integrating to approximately 90°. A compact pulse returns roll rate to zero at both ends, so the roll stops at the internal seam before restarting for the second half.

**Required fix**

Author one continuous 180° roll schedule over the inversion’s geometric top/recovery phases. The rate may accelerate, hold, and decelerate, but it must not return to zero halfway unless a deliberate, visibly held orientation is part of the design—which it is not here. Couple the roll to an explicit exit heading and bank contract.

**Closure test**

The whole-element roll profile has one rolling segment, no unintended zero-rate plateau, and one approved direction. Orthographic and POV captures show a recognisable Immelmann silhouette and continuous top rotation.

---

#### VC-013 — The cutback is assembled from four roll pulses and has no proven neutral exit bank

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `RideProgram._add_act_one_cutback()`

**Observed defect**

The cutback banks repeatedly and appears to wobble or “choose” bank directions without a clear geometric narrative.

**Verified mechanism**

Entry and arc each use a positive compact roll pulse; reverse and release each use a negative compact pulse. Every pulse returns to zero independently. The commanded rider-frame roll-rate integral across the cell is not zero (approximately +34.6° for the authored hand), although that integral is not identical to published world-bank change because curve transport also rotates the frame. The important defect is that the recipe does not prove the desired exit bank.

The final 0.3 s normal-G recover and 0.3 s settle add another short load bump after the nominal cutback shape.

**Required fix**

Define the cutback by its intended centreline and bank sequence: entry roll, sustained/reversing curvature, apex/reversal landmark, and continuous exit roll. Solve the complete roll schedule to the declared exit bank. Remove post-element G bumps that exist only to restore a control value.

**Closure test**

One continuous bank narrative is visible in plan/elevation/POV. The exit frame matches the next cell contract, and the whole-element roll integral/transport resolves to the declared bank within tolerance.

---

#### VC-014 — The loop’s lateral and roll pulses make its geometry under-specified

**Priority:** P1  
**Evidence:** Confirmed; visual classification needs capture  
**Primary code:** `RideProgram._add_act_one_loop()`

**Observed defect**

The nominal loop can become an uncontrolled helical or skewed inversion rather than a deliberately shaped vertical or helical loop.

**Verified mechanism**

The rise and entry include lateral compact pulses. The fall and release include additional opposite lateral pulses and two independent roll pulses. No whole-element plane, torsion, heading, or exit-bank contract says what kind of loop should result.

**Required fix**

Choose and name the design:

- for a vertical loop, require near-planarity, controlled heading drift, and a bank schedule consistent with the loop plane;
- for a helical loop, explicitly specify torsion, heading change, and roll progression.

Then author a continuous spatial curvature/torsion profile rather than relying on lateral/roll pulse combinations to produce an emergent shape.

**Closure test**

The loop meets its declared planarity class and silhouette bands over the whole material role, not only per diagnostic sub-window.

---

#### VC-015 — The wave turn crosses bank through repeated stop-start pulses

**Priority:** P1  
**Evidence:** Confirmed and corroborated  
**Primary code:** `RideProgram._add_act_one_wave()`

**Observed defect**

The wave turn contains too many bank events and feels micro-stitched through its crest and recovery.

**Verified mechanism**

The cell rolls to roughly one side, then distributes the cross-over through separate compact pulses in unload, crest, and recovery—each returning roll rate to zero—before another two-pulse exit roll. A transition that should read as one flowing bank cross-over is represented by several self-contained lobes.

**Required fix**

Use one continuous cross-over function spanning unload → crest → recovery, with the bank zero-crossing and peak opposite bank tied to geometric landmarks. Use a second continuous exit function only if the design intentionally changes again after the wave. Remove pulse boundaries as design events.

**Closure test**

The roll profile contains the reviewed number of segments and reversals; the zero-crossing occurs once at the declared landmark; no banked-flat interval interrupts the cross-over.

---

#### VC-016 — The marquee camelback is non-planar by construction and contains a 0.01 s pseudo-hold

**Priority:** P0  
**Evidence:** Confirmed and corroborated  
**Primary code:** `RideProgram._add_camelback()`

**Observed defect**

The marquee hill is tilted, turns sideways, and does not read as a clean large camelback. Its pullout also contains a meaningless micro-segment.

**Committed baseline**

The previous geometry audit reports substantial fitted-plane tilt across camelback phases (approximately 24.5° on the rise, 10.1° at the crest, and 16.3° on the exit) and about 42.5° of heading change during the climb.

**Verified mechanism**

The recipe injects lateral pulses and alternating ±18° roll excursions across rise, unload, crest, and fall. A clean planar hill is therefore not the default result. `camelback/pullout-hold` lasts 0.01 s—one production integration step and around a metre at record speed—before a separate release.

**Required fix**

Rewrite the default camelback as a true planar or near-planar element:

- pin a pitch-zero apex;
- specify rise/fall planes and allowed heading drift;
- use speed-aware spatial curvature to shape the ascent and descent;
- make any intentional 3D variant a separately named family;
- remove the 0.01 s hold and use one continuous pullout/release profile.

**Closure test**

The default camelback satisfies a reviewed whole-element plane-tilt and out-of-plane RMS gate, has an apex pitch near zero, and contains no unexplained bank reversal or micro-hold.

---

#### VC-017 — The clifftop sequence is too short and semantically under-authored

**Priority:** P1  
**Evidence:** Confirmed by committed comparison; visual result corroborated  
**Primary code:** `RideProgram._add_story_prefix()`

**Observed defect**

The clifftop does not establish a convincing slow suspense beat. It compresses a complex real-world sequence into a small number of generic bank/hold operations, so the subsequent dive lacks anticipation and site scale.

**Committed baseline**

The previous audit compares the current roughly 7–11 s/one-main-bank treatment with a reference sequence around 21 s and multiple distinct bank gestures, including a longer crest crawl/hold narrative.

**Required fix**

Design the clifftop as a sequence of geometric beats, not a longer scalar hold:

1. powered climb release;
2. crest compression and sightline reveal;
3. deliberate crawl/hold;
4. edge traverse with terrain exposure;
5. outward rim turn;
6. clean commitment into the drop.

Each beat needs speed, bank, heading, AGL, and duration intent. The slow section must create contrast without inserting dead, featureless track.

**Closure test**

A deterministic POV review can identify every intended beat without the HUD. Timing and sightline artifacts show a clear build of suspense into the dive.

---

#### VC-018 — The dive begins with a long, nearly level banked approach instead of committing at the edge

**Priority:** P1  
**Evidence:** Confirmed and corroborated  
**Primary code:** `RideProgram._add_story_prefix()`, prefix closure controls

**Observed defect**

The track appears to “pretend” to begin a drop while still travelling along a mostly level, banked segment. This weakens both geometry and pacing.

**Committed baseline**

The previous audit measured the commit block at about 3.684 s and 64.111 m with only about +0.258 m net rise before the actual vertical development.

**Verified mechanism**

The dive has an outward bank, a solver-controlled face approach, an outward release, and then separate commit/vertical-entry/core phases. The approach duration is one of the global prefix closure controls, so the solve can spend a visually obvious pre-drop stretch to hit terrain span targets.

**Required fix**

Move the macro anchor so the element’s geometric commitment begins at the intended rim location. The dive element should own one continuous pitch/curvature development from edge traverse into descent. The macro solver may place the edge anchor; it may not lengthen an almost-flat internal approach to repair the terrain chord.

**Closure test**

The declared dive start landmark coincides with the visual/kinematic onset of sustained descent within a reviewed distance. No solver-controlled neutral run exists inside the dive role.

---

#### VC-019 — Return banks and counter-banks are closure devices rather than a coherent ride narrative

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `RideReturnSolve._return_spans()`

**Observed defect**

The return contains large and apparently random bank changes, including counter-banked transfer behaviour, because its primary job is to unwind heading and close the station.

**Verified mechanism**

Turn A and B bank are solver controls with large bounds. The source explicitly describes the counter-banked sweep as a way to spend distance while unwinding heading and keeping the loaded arc short. The implementation has improved from one pulse per span to shared roll ramps, but the macro shape is still selected for residual closure rather than terrain/ride-story clarity.

**Required fix**

Plan the return as a small number of named terrain and pacing elements with fixed corridor intent. Give the macro route a heading/elevation path to the station before building its turns. Permit the return solve to vary radii and neutral connector lengths within those corridors, but not to invent counter-banks unless the element specification explicitly calls for them and they are force-balanced.

**Closure test**

A plan-view render and bank plot tell the same story: each bank direction corresponds to a signed curvature/element intent, and no large counter-bank exists solely to satisfy terminal residuals.

---

#### VC-020 — Act-one cells are control-seam composable, not geometrically composable

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `RideProgram._add_story_act_one()`, `RidePlanner`

**Observed defect**

The code treats cells as reorderable because they enter and leave at nominal `1.0 G`, but alternate orders frequently fail placement or return closure and may create bad frame handoffs.

**Verified mechanism**

A zero lateral/roll-rate control seam and 1.0 normal G do not define position, heading, pitch, bank, curvature, torsion, energy, or available corridor. Source comments document that most grammar-legal permutations are not end-to-end buildable.

**Required fix**

Define a cell interface in geometric state space. A composable cell must advertise accepted input-state bands and guaranteed output-state bands. The planner must connect compatible cells through explicit transitions or reject the sequence before integration.

**Closure test**

All certified sequences pass an interface compatibility check before building. Reordering two compatible cells does not require unrelated prefix/return magic-number changes.

---

#### VC-021 — The “tunnel” is not proven to be a tunnel through terrain

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `godot/route_contract.gd`, `godot/verify.gd`, `godot/main.gd`

**Observed defect**

A visually enclosed rock-box section may be floating above or insufficiently embedded in the terrain. The scenery can disguise a corridor that is not physically bored through the heightfield.

**Verified mechanism**

Terrain clearance validation skips tunnel samples. The terrain proof checks boundary crossing, monotonic direction, exit, and drop, but does not require roof cover and side cover around a full tunnel envelope. The viewer then places crude rock boxes around the track regardless of actual terrain cover.

**Required fix**

Define a tunnel excavation envelope and verify terrain cover above and to both sides at regular cross-sections, with portal transition rules. Render the actual cut/excavation or terrain-intersection geometry rather than an unconditional decorative shell.

**Closure test**

Every non-portal tunnel cross-section has positive reviewed roof and side cover outside the train/clearance envelope. Removing the decorative boxes still leaves a route visibly passing through terrain.

---

#### VC-022 — Track and support placement is visually and structurally naive

**Priority:** P2  
**Evidence:** Confirmed and corroborated  
**Primary code:** `godot/main.gd`

**Observed defect**

Supports overlap, appear implausible, disappear on steep sections, or fail to communicate scale. Generic rail/support geometry also makes the ride look procedural and weakens speed cues.

**Verified mechanism**

Supports are attempted at fixed 32 m spacing, skipped above a tangent-slope threshold, and placed as simple two-leg cylinders based on local height. They do not reason about element loads, neighbouring supports, terrain footings, track crossings, tunnel zones, structural spans, or sightline rhythm.

**Required fix**

Keep structural art separate from centreline correctness, but replace fixed-spacing placement with a support planner that uses curvature, bank, elevation, terrain, crossings, and exclusion volumes. At minimum, prevent collisions and unsupported long spans; later, provide element-appropriate support families.

**Closure test**

Automated support/track/train clearance passes, maximum unsupported spans are bounded by context, and deterministic overview captures contain no obvious overlaps or floating structures.


### Transition construction, interpolation, and validation

#### VC-023 — The project’s “C4 seams” do not prove perceptually smooth transitions

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `RideProgram._validate_control_seams()`, `RideVerify.validate_seams()`

**Observed defect**

Transitions look stitched even though the route passes seam continuity tests.

**Verified mechanism**

The compiler compares value, first derivative, and second derivative of the four **control profiles** at named span boundaries. The verifier estimates first and second spatial derivatives of curvature only around those boundaries. These tests answer “does the signal jump at this seam?” They do not answer:

- does the signal form several complete pulses inside one intended transition?
- does roll rate stop and restart between adjacent spans?
- does curvature reverse unnecessarily?
- is torsion coherent?
- does the complete element have the intended silhouette?
- does a tiny semantic span create a visible kink or pause?

A C4 centreline is also not automatically a well-paced or well-banked coaster. Continuity order is necessary, not sufficient.

**Required fix**

Retain seam checks, but add continuous whole-transition analysis. Evaluate curvature, torsion, bank, roll rate, roll acceleration, and their extrema over each intended transition. A transition is a semantic object that may contain evaluation knots, not a list of independently validated pulses.

**Closure test**

A synthetic roll → flat → roll transition with perfectly matching endpoint jets is rejected. A single coherent analytic roll with internal knots passes.

---

#### VC-024 — Semantic micro-spans and hidden connector stubs are permitted

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `godot/ride_program.gd`, `godot/motion.gd`

**Observed defect**

Tiny fragments are used to settle, hold, recover, unbank, or close a state. They are too short to read as intentional track and instead appear as micro-stitching.

**Examples**

- camelback pullout hold: 0.01 s;
- opener unbank hold: roughly 0.035 s;
- opener unbank fragments: 0.115–0.185 s;
- capture terminal shoulder: 0.15 s;
- several 0.3–0.45 s recover/settle spans.

At high speed, even 0.1 s can be around 9–10 m; at low speed it can be a tiny visual bump. The defect is not simply “short duration.” It is that these fragments are separate semantic control events rather than invisible knots on one continuous profile.

**Required fix**

Enforce two different concepts:

1. **Semantic transition/connector:** must have a reviewed geometric purpose and sufficient spatial length; preserve the existing design rule against sub-30 m connective stubs unless a named infrastructure exception is approved.
2. **Numerical knot:** may be arbitrarily close for evaluation, but cannot reset profile derivatives, create a separate role, or change the semantic state machine.

Delete micro-holds and settle spans whose only purpose is restoring convenient endpoint values.

**Closure test**

The compiler lists every semantic span with built arc length. No unnamed connector violates the reviewed spatial floor, and splitting an analytic profile into additional numerical knots leaves route bytes/geometry invariant within numerical tolerance.

---

#### VC-025 — `compact_pulse` encourages roll → flat → roll authoring

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `RideMotion.compact_pulse()`, multiple element recipes

**Observed defect**

Banking repeatedly starts, stops, and starts again across one intended transition. This is the most direct code-level explanation for the reported “cheated” micro-stitching.

**Verified mechanism**

A compact pulse is deliberately zero, with zero first and second derivatives, at both endpoints. It is useful for a single isolated event. It becomes harmful when each neighbouring span receives its own pulse: every span guarantees a complete roll acceleration and deceleration cycle, even where the intended motion should continue through the boundary.

The return has already partly acknowledged this problem by introducing shared `_roll_ramp()` profiles across multiple spans. Other elements still use pulse-per-span authoring.

**Required fix**

Make roll transitions first-class objects. One transition owns a continuous roll-rate spline across all of its geometric phases. Provide reusable profiles such as:

- ramp-up → hold → ramp-down;
- monotone cross-over through level;
- one-direction inversion roll;
- reviewed reversal with a declared zero-crossing.

`compact_pulse` should remain available only for truly isolated roll impulses and should be flagged when adjacent to another same-transition pulse.

**Closure test**

The geometry audit reports one roll segment for every transition specified as continuous. Adjacent compact pulses in the same semantic transition fail lint/validation.

---

#### VC-026 — Normal load, lateral load, and roll are authored independently, so bank is not reliably force-balanced

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `godot/motion.gd`, `godot/ride_program.gd`, `godot/ride_return_solve.gd`

**Observed defect**

Banks can look arbitrary or produce unintended lateral behaviour because roll angle is not the primary geometric quantity and the normal/lateral loads do not necessarily match the instantaneous bank/curvature state.

**Verified mechanism**

The motion kernel accepts four independent channels. It contains `bank_balance(from_bank, to_bank)`, which computes the exact proper normal load required for a level compact-pulse bank transition, but production recipes do not use it. Even the improved return roll ramps approximate normal load with a quintic between endpoint `sec(bank)` values rather than evaluating the exact load along the actual bank schedule.

This does not mean every turn must be perfectly balanced; deliberate lateral G and outward banking are valid. The defect is that the intended relationship is not declared or enforced.

**Required fix**

For each transition, declare one of:

- balanced turn/bank transition;
- specified lateral-G manoeuvre;
- inversion/free-roll transition;
- intentionally outward/counter-banked element.

Generate normal/lateral targets from the geometric curvature and bank intent where possible. Use exact bank-balance mathematics for level balanced transitions. Where imbalance is intentional, gate the signed lateral profile and explain its role.

**Closure test**

A bank-versus-signed-curvature/lateral-G report shows that every large bank has a declared purpose. Unexplained large bank with near-zero or opposite curvature fails.

---

#### VC-027 — There are no hard gates for torsion, curvature extrema, or bank/curvature coherence

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `godot/verify.gd`, `godot/geometry_metrics.gd`

**Observed defect**

A centreline can contain excessive wiggles, accidental helical drift, needless inflections, or rapid bank reversals without violating current structure/load checks.

**Required fix**

Add whole-element spatial metrics:

- signed curvature in a stable local frame;
- curvature magnitude and derivative over arc length;
- torsion and torsion derivative;
- number and location of curvature extrema/zero crossings;
- bank extrema, roll segments, and reversals;
- correlation between bank sign and horizontal curvature sign;
- integrated heading/pitch/bank change;
- minimum osculating radius and transition length.

Thresholds must come from each element specification, not one global “smoothness” number.

**Closure test**

Known bad synthetic shapes—wiggle, corkscrew drift in a planar hill, needless S-bank, and repeated curvature pulses—are rejected while intended inversions and wave turns pass their own role-specific rules.

---

#### VC-028 — The 5 Hz filtered validation chain can hide brief raw micro-transients

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `godot/verify.gd`

**Observed defect**

Short load or banking defects can feel sharp or visually abrupt while filtered onset and duration envelopes remain acceptable.

**Verified mechanism**

Force series are resampled to 100 Hz and passed through a four-pole single-pass 5 Hz Butterworth filter before onset/envelope analysis. Filtering is appropriate for human-response standards, but it attenuates high-frequency defects. The project also gates raw force peaks and raw roll rate, yet does not gate raw roll acceleration, raw curvature-rate, raw jerk, or short spatial oscillation.

**Required fix**

Keep the filtered safety/comfort chain, but add a separate engineering-quality chain on native/dense spatial data. Gate raw or lightly filtered:

- roll acceleration and jerk;
- curvature derivative and second derivative over distance;
- angular velocity/acceleration of the rider frame;
- short-lived reversals and pulse counts.

Do not use a safety filter as a geometry-smoothing filter.

**Closure test**

A sub-0.2 s roll or load stitch that is attenuated below the filtered onset limit still fails the engineering-quality gate.

---

#### VC-029 — The dense-output defect metric is tautological and cannot detect a bad interpolant

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `RideMotion._measure_dense_defect()`

**Observed defect**

The route publishes a reassuring dense-output defect value that does not test the claimed property.

**Verified mechanism**

The metric compares a velocity vector with `velocity.normalized() × velocity.length()`, which is algebraically the same vector apart from degenerate floating-point cases. It therefore cannot reveal whether dense position, tangent, speed, and distance agree with the integrated dynamics.

**Required fix**

Replace it with independent residuals, for example:

- derivative of dense position minus dense `speed × tangent`;
- derivative of dense distance minus dense speed;
- derivative of dense tangent minus curvature × speed;
- dense frame orthogonality and angular-rate consistency;
- coarse/fine trajectory convergence over representative elements.

**Closure test**

Deliberately corrupting dense position or tangent causes a non-zero failure. The metric has synthetic positive and negative tests rather than only checking the canonical route.

---

#### VC-030 — The planarity diagnostic can self-exempt a badly distorted planar element

**Priority:** P2  
**Evidence:** Confirmed  
**Primary code:** `RideGeometryMetrics.planarity_of()`

**Observed defect**

A role intended to be planar can become distorted enough to be classified “three-dimensional,” after which its vertical-plane tilt is marked not meaningful. The diagnostic describes the output instead of judging it against the intended class.

**Required fix**

Move planarity intent into `ElementSpec`. A camelback, conventional vertical loop, straight drop, or planar airtime hill remains subject to planarity gates no matter how badly the generated output misses them. Only explicitly three-dimensional families may opt out.

**Closure test**

Injecting lateral drift into a planar-role fixture makes the test fail; it cannot escape by changing its measured classification.

---

#### VC-031 — Per-window metrics can hide whole-element morphology

**Priority:** P2  
**Evidence:** Confirmed  
**Primary code:** `godot/geometry_metrics.gd`, gesture/role-window mapping

**Observed defect**

A camelback split into rise/crest/fall/exit or a dive split into commit/vertical-entry/core/pullout can look acceptable in local windows while the whole material role has a wrong plane, heading drift, or proportion.

**Required fix**

Produce both:

- phase metrics for local diagnosis;
- mandatory whole-material-role metrics for acceptance.

The whole-role geometry must own entry/exit state, global best-fit plane, height/width ratio, total heading change, torsion budget, and landmark ordering.

**Closure test**

A defect distributed across several individually mild phases is caught by the whole-role gate.

---

#### VC-032 — Clearance validation does not model the complete moving and structural envelope

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** `godot/verify.gd`, `godot/route_contract.gd`, `godot/main.gd`

**Observed defect**

Centreline/rail clearance can pass while the train, rider envelope, supports, tunnel shell, or adjacent banked track conflicts. Tunnel samples are skipped by normal terrain clearance.

**Required fix**

Validate swept volumes rather than centreline points:

- train/rider dynamic clearance envelope along the frame;
- both rails and spine;
- adjacent track and train envelopes;
- supports and footings;
- tunnel excavation and portal envelopes;
- terrain clearance at banked cross-sections.

Use adaptive sampling based on curvature and proximity, not every second native sample in a fixed 4 m grid.

**Closure test**

Synthetic near-miss fixtures fail for train-to-terrain, train-to-track, track-to-support, and tunnel-side/roof clearance even when the centreline separation alone would pass.

---

#### VC-033 — The canonical fleet and scalar tests do not provide a visual geometry regression gate

**Priority:** P1  
**Evidence:** Confirmed  
**Primary code:** smoke/material tests and fidelity artifacts

**Observed defect**

A change can preserve all numerical contracts and still make the ride look worse. Conversely, a necessary geometry rewrite may be blocked because it changes canonical bytes even when quality improves.

**Required fix**

Add deterministic review artifacts for a small canonical set, including seed 42:

- plan, front elevation, side elevation, and isometric centreline renders;
- bank/roll/curvature/torsion/speed/AGL plots over distance;
- per-element close-ups with landmarks;
- fixed-camera and POV clips at native speed;
- before/after difference summaries.

Use numeric image/curve comparisons only for gross regressions. Human approval remains required for ride morphology until the geometric targets are sufficiently complete.

**Closure test**

Every geometry-affecting pull request publishes the artifacts and records a human visual verdict. “All unit tests pass” is not sufficient evidence of ride quality.

---

#### VC-034 — The authoring code is a magic-number monolith with historical commentary embedded in production

**Priority:** P2  
**Evidence:** Confirmed  
**Primary code:** `godot/ride_program.gd`, solve files

**Observed defect**

Many decimal constants encode previous closure experiments, and long comments narrate measurements that are difficult to distinguish from current invariants. Editing one element requires understanding global solver history.

**Required fix**

After the representation and contracts are settled, split element families into focused modules. Store reviewed parameters in named immutable specs with units and provenance. Move experiment history to dated documents. Production comments should explain invariant intent, not preserve a chronological debate.

**Closure test**

A contributor can change one element’s geometric parameters and run its isolated fixtures without reading the return solver or historical issue log.

---

### Sense of speed, pacing, and viewer fidelity

#### VC-035 — The fastest track is too high above terrain to generate strong optic flow

**Priority:** P0 for the ride experience  
**Evidence:** Corroborated by committed measurements and user observation  
**Primary code:** macro planner/terrain placement

**Observed defect**

The HUD can show extreme speed while the POV feels slow. Distant terrain moves little across the retina; elevated open-air sections lack rapid near-field parallax.

**Committed baseline**

The prior audit reports a fastest-decile minimum AGL around 37 m and median around 49–58 m, with no fastest-decile samples within 20 m of terrain.

**Required fix**

Create deliberate speed-cue corridors. At least one sustained high-speed role should run near terrain, trench walls, tunnel surfaces, or other close fixed structure. Use terrain exposure strategically: a high drop can feel enormous, but its exit and record-speed run need proximity and texture.

**Closure test**

Speed-decile/AGL overlap plots meet reviewed role-specific targets, and a fixed-FOV POV review clearly distinguishes 150, 250, and 340 km/h sections without reading the HUD.

---

#### VC-036 — The scene lacks dense near-field references, audio, and physical motion cues

**Priority:** P1  
**Evidence:** Confirmed and corroborated  
**Primary code:** `godot/main.gd`

**Observed defect**

Rails over smooth terrain, 4 m ties, 32 m supports, sparse station/tunnel boxes, and a placeholder train provide weak scale and optic-flow information. There is no wind/rail audio, motion blur, vibration tied to track texture, or visible train nose/seat reference.

**Required fix**

After geometry and interpolation are corrected, add a restrained presentation baseline:

- denser near-field track detail with physically consistent spacing;
- terrain texture and small-scale relief;
- close structure in designated speed corridors;
- speed- and surface-dependent wind/rail audio;
- optional physically plausible motion blur;
- visible train/seat/nose reference in POV;
- vibration derived from speed and track/vehicle model, not generic screen shake.

These cues must reveal speed, not conceal geometry.

**Closure test**

A/B captures with a fixed camera transform show improved speed discrimination without changing playback rate or using extreme FOV tricks.

---

#### VC-037 — The POV lens and look-ahead stabilisation damp useful motion cues

**Priority:** P1  
**Evidence:** Confirmed; magnitude needs capture  
**Primary code:** `RideMain.pov_transform()`

**Observed defect**

The POV feels detached from the track and rapid pitch/yaw changes are softened. The large baseline FOV also makes additional speed-linked widening less perceptually meaningful and can reduce object scale.

**Verified mechanism**

The camera uses a very wide horizontal FOV range (about 106.5–123.8°), looks 0.6 s ahead clamped to 8–45 m, and slerps 22% toward that future look direction. The rider frame is therefore partially stabilised toward the upcoming track rather than rigidly representing a head/seat model.

**Required fix**

Define a physical camera model:

- seat/eye location and visible vehicle reference;
- base lens chosen for the target display, with restrained or no speed-FOV modulation;
- optional head dynamics driven by angular acceleration and restraint compliance;
- look-ahead only as a subtle biological gaze model, not a generic smoothing filter.

Provide a strict engineering POV that follows the track frame exactly and a presentation POV only after the engineering view is approved.

**Closure test**

The engineering POV reproduces route angular motion without damping. The presentation POV’s additional head model has bounded, documented lag and cannot hide a transition defect.

---

#### VC-038 — Rendered position follows linear chords while orientation follows a separate slerp

**Priority:** P0  
**Evidence:** Confirmed  
**Primary code:** `godot/route_sampling.gd`, `godot/motion.gd`

**Observed defect**

The camera and train can feel subtly faceted, detached, or micro-jittery even if the integrated centreline is smooth.

**Verified mechanism**

`pose_at_distance()` linearly interpolates `p0 → p1` for origin and quaternion-slerps the two frames for orientation. The derivative of the linear chord generally does not equal the slerped tangent. At roughly 95 m/s with 0.01 s native steps, samples can be about 0.95 m apart and the route changes chord about 100 times per second while typical display is 60 fps.

**Required fix**

Use one consistent dense trajectory sampler for position, tangent, frame, speed, and distance. Prefer a cubic Hermite or higher-order spatial interpolant whose derivative defines the tangent, with a rotation-minimising/banked frame sampled from the same continuous state. Build rail mesh and camera poses from this sampler or from an adaptive arc-length resample.

**Closure test**

At arbitrary sub-sample distances, the derivative of rendered position aligns with rendered tangent within a tight angular tolerance. Playback at 30, 60, 120, and 240 fps produces the same path without cadence-dependent wobble.

---

#### VC-039 — Pacing is numerically fast but insufficiently contrasted

**Priority:** P1  
**Evidence:** Corroborated  
**Primary causes:** energy model, hard role lengths, high AGL, simplified clifftop

**Observed defect**

The ride feels leisurely or monotonous despite extreme top speed. There are too many long, broad, steady-force sections and too little contrast between crawl, acceleration, plunge, near-ground speed, inversion, airtime, and recovery.

**Required fix**

Design pacing as a story graph with measurable beat intent. For every role, declare ranges for:

- entry/exit speed and acceleration character;
- duration and distance;
- AGL/proximity;
- positive/negative/lateral load character;
- visual scale and sightline reveal;
- transition into the next beat.

Optimise contrast, not average speed. A slow beat must be purposeful and visually rich; a fast beat must have near-field reference; a record element must have setup and release.

**Closure test**

Publish speed, acceleration, G, AGL, and curvature plots with beat boundaries. Human reviewers can identify the intended rhythm from both plots and POV without relying on labels.

---

#### VC-040 — Fixed repetitive track spacing weakens scale and can alias motion

**Priority:** P2  
**Evidence:** Confirmed  
**Primary code:** `godot/main.gd`

**Observed defect**

Uniform 4 m ties and sparse 32 m supports provide limited high-frequency motion reference. Repetition can also alias at high speed and frame rates, making motion look slower or stroboscopic rather than continuous.

**Required fix**

Use physically plausible sleeper/fastener spacing and richer but non-distracting track detail. Vary support rhythm by structure while preserving deterministic layout. Validate temporal frequencies at target speeds/frame rates so repeated geometry does not create obvious alias bands.

**Closure test**

High-speed captures at supported frame rates retain continuous forward motion and clear scale without visible tie/support strobing.

---

### Operational and inspection issues retained from the previous register

#### VC-041 — Generation latency and close/rebuild behaviour remain poor for iteration

**Priority:** P3  
**Evidence:** Confirmed by code comments and prior log  
**Primary code:** `godot/main.gd`, bounded solves

**Defect and fix**

Generation runs on a worker thread and the UI can remain in a long “Generating” state; closing waits for the build. Geometry work needs rapid inspection, so preserve deterministic solving but add cached canonical builds, progress stages, cancellable non-publish builds, and profiling. Do not sacrifice numerical correctness merely to make CI green.

**Closure test**

Canonical inspection routes load quickly from validated artifacts, a live build reports meaningful stages, and cancellation does not publish a partial route or leave the worker in an invalid state.

---

#### VC-042 — Camera and HUD inspection tools are insufficient for geometry review

**Priority:** P3  
**Evidence:** Retained from previous register  
**Primary code:** `godot/main.gd`

**Defect and fix**

The viewer has useful POV/chase/overview/fly cameras, but geometry review needs element stepping, freeze-at-landmark, frame overlays, curvature/bank/torsion plots, orthographic views, and deterministic capture commands. Add inspection tooling as an engineering interface, not as presentation polish.

**Closure test**

A reviewer can jump to any material role, inspect its local frame and metrics, and export standard views without manually flying the camera.

---

#### VC-043 — CI and audit cost are too high and not layered by purpose

**Priority:** P3  
**Evidence:** Retained from previous register and source comments  
**Primary code:** smoke/fleet/material/fidelity tests

**Defect and fix**

The full canonical fleet and bounded solves are expensive, encouraging developers either to skip review or to preserve fragile cached assumptions. Split validation into:

1. fast isolated element/unit fixtures;
2. medium canonical seed-42 integration and artifacts;
3. full fleet/compatibility matrix;
4. scheduled evidence and visual-regression runs.

**Closure test**

A local geometry edit receives useful element feedback quickly, while CI still runs the complete acceptance matrix before merge.

---

## 6. Specific micro-stitches and suspicious bank constructions to remove

The table below identifies concrete current patterns. “Commanded roll integral” means the integral of authored rider-frame roll-rate controls; it is a diagnostic flag, **not** a direct claim about final world-bank change, because curvature transport also rotates the rider frame.

| Area | Current construction | Why it is suspect | Required replacement |
|---|---|---|---|
| Opener drop exit | Four unbank/recover/hold/out fragments, including ~0.035 s hold | Semantic micro-stitch; separate load and roll repairs | One continuous drop-exit profile to declared next-state |
| Immelmann | Two compact pulses of roughly 90° each | Roll rate returns to zero at the midpoint | One continuous 180° inversion roll |
| Cutback | Four compact roll pulses; commanded integral ≈ +34.6° | Repeated stop/start and no proven neutral exit | One reviewed entry/reversal/exit bank schedule |
| Loop | Lateral pulses plus two release-side roll pulses; commanded integral ≈ −25° | Emergent helix/skew; no declared plane/torsion | Explicit vertical or helical loop family |
| Wave | Three-pulse bank cross-over plus two-pulse exit; commanded integral ≈ +17.4° | Multiple zero-rate stops inside one flowing wave | One cross-over spline tied to crest landmarks |
| Camelback | Alternating ±18° roll excursions and lateral turn | Default hill is intentionally non-planar | Planar default; separate named 3D variant |
| Camelback pullout | 0.01 s hold | One-step pseudo-feature | Delete; continuous pullout/release |
| Dive approach | Solver-controlled near-level banked run before vertical development | Terrain closure is paid inside the element | Move macro rim anchor; start descent at declared commit |
| Return | 50–80° solved banks plus counter-bank used to unwind heading | Banking serves terminal residuals | Plan return corridors/elements first |
| Capture | 1.05 s, five solved pose residuals | Hidden exact correction at 70–80 m/s | Long pre-aligned station approach; no visible repair |

A useful automated lint rule is: **two adjacent roll profiles that belong to one declared transition may not both return to zero at their shared boundary unless a deliberate held-bank phase is specified there.**

## 7. Replacement architecture and implementation order

The following sequence is intentionally dependency-ordered. Skipping ahead to element retuning or camera polish will produce disposable work.

### Phase 0 — Freeze an honest failure baseline

Before rewriting geometry, produce deterministic artifacts for seed 42 and a small representative fleet:

- route plan, side, front, and isometric views;
- whole-route and per-element plots of speed, AGL, pitch, heading, bank, roll rate, curvature, torsion, and G;
- semantic-span arc lengths and durations;
- engineering POV with fixed lens and no look-ahead smoothing;
- current presentation POV;
- 30/60/120 fps playback samples;
- issue-linked snapshots of opener, Immelmann, cutback, loop, wave, camelback, clifftop/dive, return, and capture.

These artifacts are evidence of failure, not a golden route that future geometry must match byte-for-byte.

### Phase 1 — Repair measurement and rendering truth

1. Replace the tautological dense-output metric.
2. Make route sampling use a continuous position/tangent/frame interpolant.
3. Build track mesh, train, and cameras from that sampler.
4. Add raw spatial derivative metrics alongside filtered human-response metrics.
5. Add whole-material-role measurement and intent declarations.
6. Add deterministic geometry artifact generation.

This phase makes later improvements observable. It must not try to beautify the old element recipes.

### Phase 2 — Introduce a geometric element contract

Create a focused element layer, for example:

```text
godot/elements/element_spec.gd
godot/elements/element_result.gd
godot/elements/transition_profile.gd
godot/elements/<family>.gd
```

A practical contract should resemble:

```gdscript
ElementSpec {
    id
    family
    entry_state_band
    exit_state_target
    corridor
    spatial_length_band
    planarity_intent
    landmarks
    curvature_profile
    bank_profile
    force_envelopes
    terrain_intent
}

ElementResult {
    centreline/frame samples or analytic segments
    achieved entry/exit state
    landmarks
    geometry metrics
    force metrics
    feasibility margins
}
```

The exact API may differ, but the separation is mandatory: geometry intent, generated geometry, and validation evidence cannot remain implicit inside one list of time-domain spans.

### Phase 3 — Replace pulse-per-span transitions

Build continuous transition primitives over arc length/geometric phase:

- curvature ramp and blend;
- bank ramp with optional held rate;
- monotone bank cross-over;
- inversion roll;
- force-balanced level turn;
- pull-up/pullout with apex/inflection landmarks;
- neutral connector with explicit minimum length and endpoint state.

Internal spline knots are allowed. They must not create semantic pauses or reset motion.

### Phase 4 — Rewrite elements from highest leverage to lowest

Recommended order:

1. **Camelback** — it is the clearest whole-element geometry failure and a good planar fixture.
2. **Immelmann** — proves continuous inversion roll and boundary contracts.
3. **Wave and cutback** — prove cross-over/reversal handling.
4. **Loop** — proves declared planar versus helical families.
5. **Opener** — removes the four-fragment unbank and establishes drop-transition patterns.
6. **Clifftop and dive** — integrates element landmarks with terrain anchors.
7. **Return** — replace closure-driven banks with planned elements/corridors.
8. **Station approach/capture** — remove the visible exact-pose repair.

Do not rewrite all roles simultaneously. Each family should land with isolated fixtures and standard artifacts.

### Phase 5 — Move layout solving to anchors and corridors

The planner should first choose:

- station pose and reserved approach;
- terrain corridors and exclusion zones;
- major element anchors and headings;
- elevation/AGL story;
- energy budget and launch locations;
- approximate lengths/radii required by each family;
- return route and crossing topology.

It then asks element builders to fit those assignments. Failure means the layout is infeasible. The solver may change anchors/corridor allocation and retry at the planning level under a bounded, deterministic strategy; it must not hide the problem in a 0.01 s hold or 70° counter-bank.

### Phase 6 — Rebaseline energy and pacing

After spatial geometry is stable:

- derive rolling and aerodynamic resistance honestly;
- retune launches and heights;
- preserve the intended record-speed objective only if the physical energy budget supports it;
- tune beat contrast using speed, acceleration, G, AGL, and sightlines;
- certify slow beats as deliberate rather than accidental flat travel.

### Phase 7 — Improve visual speed cues without hiding geometry

Only after the engineering POV is approved:

- choose a restrained presentation lens;
- add a physical head/seat model;
- add near-field track/terrain detail and structure;
- add wind/rail audio and optional motion blur;
- improve train and support visuals;
- validate across frame rates and aspect ratios.

## 8. Proposed production quality gates

These are the minimum categories. Numeric thresholds should be adopted per element family and committed with their rationale.

### 8.1 Whole-route gates

- honest resistance model and declared propulsion only;
- route closes without visible pose-repair geometry;
- complete swept-volume terrain/track/support/tunnel clearance;
- designated terrain-hugging and exposed-height roles meet separate AGL bands;
- no hidden semantic connector below its reviewed spatial minimum;
- deterministic plan/elevation/POV artifacts produced for canonical seeds;
- rendered position derivative aligns with rendered tangent;
- no frame-rate-dependent path wobble.

### 8.2 Whole-element gates

- accepted entry-state range and achieved exit-state tolerance;
- reviewed height/width/length/heading bands;
- declared planarity/torsion class;
- landmark order and location;
- curvature and torsion extrema/zero-crossing counts;
- bank extrema, roll segments, reversals, and zero-crossings;
- signed bank/curvature/lateral-G relationship;
- role-specific force and onset envelopes;
- terrain corridor and AGL compliance.

### 8.3 Transition gates

- one continuous analytic motion per declared transition;
- no interior zero roll-rate stop while a bank change remains incomplete, unless explicitly designed;
- no curvature or torsion impulse hidden by a filtered safety channel;
- no semantic micro-hold or settle span;
- continuity checked over the entire transition, not only at authored knots;
- adaptive spatial sampling proves convergence.

### 8.4 Suggested initial guardrails for review

These are starting points, not immutable standards:

- planar-role best-fit vertical-plane tilt: target ≤3° unless the spec says otherwise;
- planar-role out-of-plane RMS: target ≤2% of bounding diagonal;
- default camelback heading drift: target ≤5° and bank near neutral unless a 3D variant is selected;
- no standalone neutral connector below 30 m without an approved infrastructure exception;
- no semantic transition whose only purpose is a control-value repair;
- designated terrain-hugging role: median AGL target ≤10 m and 90th percentile ≤20 m where terrain/clearance permits;
- rendered tangent/position-derivative alignment: target sub-degree, tightened after numerical study;
- continuous-roll transitions: one segment and the specified number of reversals exactly.

## 9. File-by-file remediation map

| File/area | Required direction |
|---|---|
| `godot/motion.gd` | Keep physical integration; add spatial/geometric profile support, real dense residuals, continuous state sampler, raw derivative metrics. |
| `godot/ride_program.gd` | Stop being the monolithic element library; migrate recipes into element families and compile accepted element results. |
| `godot/ride_prefix_solve.gd` | Solve macro anchors/corridors or a small set of geometric parameters; stop using internal beat duration as terrain-repair authority. |
| `godot/ride_return_solve.gd` | Plan a return path and station approach; remove large closure-driven bank invention and visible capture correction. |
| `godot/ride_planner.gd` | Draw meaningful story/layout decisions only after cell interfaces are composable; reject infeasible combinations early. |
| `godot/generator.gd` | Perform terrain-aware macro routing and energy budgeting before local element construction. |
| `godot/route_contract.gd` | Validate whole-element geometry intent, full terrain/tunnel/swept-envelope constraints, and solver provenance. |
| `godot/verify.gd` | Separate human-response filtering from raw engineering smoothness; add whole-transition/element gates. |
| `godot/geometry_metrics.gd` | Make metrics intent-aware; add torsion, signed curvature, extrema, bank coherence, whole-role aggregation. |
| `godot/route_sampling.gd` | Replace chord-origin + slerp-frame sampling with a consistent continuous trajectory sampler. |
| `godot/main.gd` | Provide strict engineering POV and deterministic inspection tools; improve physical speed cues after geometry is fixed. |
| tests/artifacts | Add isolated family fixtures, bad-shape negative tests, standard renders/plots, and layered CI. |

## 10. Fixes that are explicitly forbidden

The following approaches can make screenshots or scalar tests look better while preserving the underlying defect:

1. **Do not add more short spans** to “smooth” a transition. More self-contained pulses usually create more stitching.
2. **Do not increase camera look-ahead, shake, FOV, or motion blur** to conceal bad geometry.
3. **Do not filter geometry or roll channels more aggressively** so onset tests pass.
4. **Do not zero every bank.** The problem is unjustified bank, not banking itself.
5. **Do not give closure solvers more local element controls** before element contracts exist.
6. **Do not loosen role-length, load, clearance, or seam gates** to preserve the current route.
7. **Do not preserve byte-identical canonical routes** when the accepted geometry is the thing being replaced.
8. **Do not tune isolated decimal constants without before/after shape and POV artifacts.**
9. **Do not call a role “three-dimensional” after generation merely to exempt it from a planar design requirement.**
10. **Do not treat a passing safety envelope as evidence of a good element.** Safety, physical consistency, morphology, and presentation are separate requirements.

## 11. Required regression artifacts for every geometry-affecting change

A pull request changing any element, solver, motion profile, route sampling, terrain layout, or camera must attach or generate:

- commit/config/seed identifiers;
- affected material roles;
- pre/post plan, side, front, and isometric views;
- pre/post whole-role centreline overlay;
- bank, roll rate, curvature, torsion, speed, AGL, and G plots over distance;
- entry/exit state and landmark table;
- semantic span durations and built arc lengths;
- engineering POV clip with fixed lens and no smoothing;
- presentation POV clip if presentation code changed;
- automated gate results and any changed thresholds;
- a brief human visual verdict naming remaining defects.

A numerical improvement with a worse silhouette is not an improvement. A prettier POV with a less faithful engineering camera is not an improvement.

## 12. Legacy issue migration

The old numeric issue list is retired. Its useful content maps as follows:

| Old issue | Disposition in this register |
|---:|---|
| 1 — Missing micro-elements | Folded into VC-004, VC-017, VC-039; add content only after P0 geometry architecture. |
| 2 — Cheated pacing / near-zero-loss coasting | VC-006 and VC-039. |
| 3 — Underused G envelope | VC-009 and VC-039; proportional use belongs in element specs, not universal maximisation. |
| 4 — Oversmoothing | VC-023, VC-025, VC-028. |
| 5 — Poor FVD implementation | VC-001–VC-003 and VC-026. |
| 6 — Poor terrain awareness | VC-005 and VC-035. |
| 7 — Supports/poor shaping | VC-022 and VC-032. |
| 8 — Poor speed sense | VC-035–VC-040. |
| 9 — Launch speed low | Treat as a stale scalar symptom; re-evaluate only after VC-006 and spatial rewrite. |
| 10 — Bank → flat → bank | VC-023–VC-026. |
| 11 — Leisurely ride | VC-006, VC-017, VC-035, VC-039. |
| 12 — Flats | VC-004, VC-018, VC-024, VC-039. |
| 13 — Tame airtime | Element-spec force targets under VC-002/VC-009; do not increase G before geometry is correct. |
| 14 — Scale/geometry wrong | VC-001–VC-005 and element issues VC-011–VC-020. |
| 15 — Jerky transitions | VC-023–VC-029 and VC-038. |
| 16 — Nebulous feel gaps | Resolved into explicit geometry, pacing, terrain, and presentation issues above. |
| 17 — App loading | VC-041. |
| 18 — Camera/HUD | VC-037 and VC-042. |
| 19 — CI speed | VC-043. |
| 20 — Roll sections cheat | VC-011–VC-016 and VC-023–VC-026. |
| 21 — Terrain drift | VC-005 and VC-035. |
| 22 — Dive starts too far from edge | VC-018. |
| 23 — Camelback distortion | VC-016 and VC-030–VC-031. |
| 24 — FVD gets G but not geometry | VC-001–VC-003, VC-009, VC-020. |
| 25 — Speed sense is mainly AGL | VC-035, with viewer contributors VC-036–VC-040. |
| 26 — Clifftop under-declared | VC-017. |
| 27 — Dense-output metric tautological | VC-029 and rendered sampler VC-038. |

## 13. Closure policy

An issue may be closed only when all of the following are true:

1. the root mechanism is removed, not hidden;
2. the relevant automated negative and positive tests pass;
3. standard geometry plots and views are attached;
4. an engineering POV at native speed has been reviewed;
5. the change does not create an undocumented solver repair elsewhere;
6. any new threshold has a stated design rationale;
7. the issue record links to the evidence and names any consciously deferred limitation.

“C2/C4 passes,” “G is within the envelope,” “the route closes,” “the canonical bytes match,” and “the camera looks smoother” are each insufficient on their own.

## 14. Immediate next milestone

The next milestone should **not** be a full visual polish or a route-wide retune. It should be a geometry-truth vertical slice:

1. correct dense/rendered sampling;
2. introduce the element contract and whole-role gates;
3. rewrite the camelback as a planar spatial element;
4. generate standard before/after artifacts;
5. prove that its geometry remains stable across certified entry speeds;
6. then use the same infrastructure for the Immelmann’s continuous 180° roll.

That vertical slice tests the new foundation against the two clearest current failures: wrong whole-element geometry and micro-stitched roll construction. Once those are solved honestly, the remaining elements can migrate without another architectural reset.
