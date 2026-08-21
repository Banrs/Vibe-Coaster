# Return macro layout and geometric FVD contracts (2026-08-22)

## 1. Decision

Replace the monolithic return closure with two explicit levels:

1. a deterministic macro layout stage chooses the ordered return story, spatial corridors,
   endpoint frames, terrain relationships, and length allocation; and
2. small local element solves author force-and-roll histories that fit those assignments.

The centreline remains the output of force-vector integration. Macro geometry is a target and a
feasibility contract, never a replacement spline fitted over a failed physical trajectory.

The design does not hard-code one S-return or one role order. `RidePlanner` supplies a legal ordered
list of return roles; the layout stage consumes that list without assuming a particular permutation.
Terrain and energy feasibility decide whether that plan is buildable. A seed may choose among
certified story decisions through existing named streams, but no seed receives a special case,
fallback topology, warm start, tolerance, or retry path.

This is a redesign, not another seed-4096 repair. Seed 4096 remains one member of the same fleet.

## 2. Evidence and rejected local fixes

The 2026-08-21 CI matrix evaluated the optional act-one swap on all fifteen canonical seeds at
normalized finite-difference steps 0.005, 0.0025, and 0.001. The three settings produced only 2,
2, and 3 solver convergences respectively. Seed 4096 improved at 0.001 but still failed. The failure
is therefore not a poorly chosen fixed difference step.

The same matrix found `return-height-b` inside its declared 450--590 m band on all 45 builds
(521.655--589.444 m). Adding a height-B duration and residual would enlarge the same coupled solve
without addressing the fleet-wide cause.

The characteristic failure is aggregate route length high while several independently declared
roles are short. Source inspection explains it: `RideReturnSolve._solve_return()` currently lets one
12-control solve spend local banks, transition durations, two upstream prefix durations, role lengths,
total route length, entry speed, and station pose against one another. Exact terminal capture is then
performed by a separate five-variable solve. Macro allocation, element identity, and terminal
alignment have no clean ownership boundary.

The following alternatives are rejected:

- Removing the total-length residual merely turns a controlled quantity into a late contract failure.
- Replacing it with `height_b_length_band_m` does not create route-allocation authority.
- Adding more return controls or residuals makes the monolith larger.
- A post-hoc geometric spline, Bezier fit, or point edit would make the displayed track disagree with
  the force history and is forbidden.
- Building the repository's complete generic element framework before fixing the return is broader
  than this design requires. The return contracts below are deliberately small and may later become
  that framework's first concrete implementation.

## 3. Non-negotiable physical model

`Motion.integrate()` remains the only authority that creates moving track. In its transported rider
frame, let

- **t** be the unit tangent;
- **u** be rider-up;
- **r** = **t** x **u** be rider-right;
- `n` and `l` be commanded normal and lateral proper acceleration in g;
- `d` be commanded longitudinal drive in g;
- `omega` be commanded roll rate about **t**; and
- **g** be gravitational acceleration.

For moving track `v > 0`, **t**, **u**, and **r** are orthonormal and the curvature vector is
perpendicular to **t**. The production equations remain:

```text
g_perp = g - t (g dot t)
a_perp = g_perp + g0 (n u + l r)
dx/dt = v t
dt/dt = a_perp / v
du/dt = -t ((dt/dt) dot u) + omega r
dv/dt = g dot t + g0 d - rolling - aero v^2
ds/dt = v
kappa_vector = a_perp / v^2
```

The equations are integrated together at every RK stage. Position, orientation, speed, energy,
curvature, and load therefore remain mutually consistent. Unpowered return roles set `d = 0`;
gravity and the existing resistance model determine their speed. Braking remains owned by the
terminal brake stage, not hidden as negative drive inside a return element.

An element authors signed curvature components in its evolving rider-frame normal plane,
`kappa(s) = kappa_u(s) u + kappa_r(s) r`, so `kappa dot t = 0` by construction. Its speed-aware FVD
commands are derived from the same equation rather than from a constant-speed approximation:

```text
n = (v^2 kappa_u - g_perp dot u) / g0
l = (v^2 kappa_r - g_perp dot r) / g0
omega = v d(phi)/ds
```

Here `phi(s)` is intentional twist relative to the minimal-rotation transported frame and `s` is
actual integrated arc length. The existing time-normalized profile API cannot represent that identity
by relabelling elapsed time as distance. `Motion` therefore receives the smallest internal extension
needed for a moving spatial span: it samples profiles at
`u = (stage_distance - span_start_distance) / declared_span_length` and terminates at that physical
length. The final RK step is bounded to the distance event rather than clamping a profile that ended
early or letting one finish late. Temporal spans remain unchanged for launches, brakes, and station
motion. Spatial duration is an integration result, not an independent shape control.

Each local solve integrates its candidate and observes the resulting speed, frame, curvature, and
endpoint. It may not calculate a geometric curve once and attach decorative G values afterward. The
integrated curvature and endpoint residuals, not the nominal profile, decide acceptance.

This keeps the useful openFVD principles already cited by the repository: force projection into
curvature, transported frames, roll as twist, and smooth transition shoulders. It does not copy
openFVD's constant-speed mode, mixed geometric/forced section handoff, export fitting, or roll
smoothing.

## 4. Geometric transition obligations

Element identity is expressed over arc length or normalized geometric phase, even when the kernel
ultimately samples commands in time.

For a regular centreline parameterized by one common arc-length coordinate, fourth-order geometric
continuity at an element seam means the integrated position derivatives `x^(j)(s)` agree for
`j = 0..4`. That direct condition is the acceptance definition. Curvature jets are a construction
tool, not a substitute definition: when curvature is stored as rider-frame components, world-space
derivatives must include derivatives of the evolving basis. Matching component values alone is not
sufficient. The construction and seam checks therefore require:

- position and tangent agree;
- world-space curvature vector agrees;
- the first and second arc-length derivatives of the world-space curvature vector agree;
- rider-up and the twist angle `phi`, `d(phi)/ds`, and `d^2(phi)/ds^2` agree.

A transition from curvature `kappa_0` to `kappa_1` uses a normalized arc-length shoulder such as

```text
h(u) = 10u^3 - 15u^4 + 6u^5,  0 <= u <= 1
kappa_q(u) = kappa_q0 + (kappa_q1 - kappa_q0) h(u),  q in {u, r}
d(kappa_q)/ds = (kappa_q1 - kappa_q0) h'(u) / shoulder_length
d^2(kappa_q)/ds^2 = (kappa_q1 - kappa_q0) h''(u) / shoulder_length^2
```

The component profile is evaluated in the evolving normal plane, not by linearly interpolating two
fixed world vectors. Because `h'` and `h''` vanish at both ends, adjacent constant or straight phases
can be constructed to match curvature value, spatial slope, and spatial acceleration when the frame
and twist jets also match. The direct integrated `x^(0..4)` seam check remains authoritative. The same
endpoint conditions and shoulder-length scaling apply to intentional twist angle.

Spatial `phi`, `d(phi)/ds`, and `d^2(phi)/ds^2` continuity becomes time-domain roll-rate and
roll-acceleration continuity only when speed and tangential acceleration also agree at the seam;
those state/control conditions are therefore checked. A different polynomial basis is acceptable
only if it proves the same endpoint jets. The existing `staged` profile container does not prove
derivative continuity merely because its segments are adjacent, so the builder must validate every
internal knot analytically.

The transition belongs to the whole semantic element. Internal numerical knots may not reset a
force or roll pulse, introduce a neutral pause, or create a micro-span. Force onset is checked after
the spatial profile is converted through the actual speed history; the chain rule makes onset depend
on both spatial slope and speed.

Turn banking is force-balanced from the actual local resultant. Define
`f = v^2 kappa - g_perp`, the proper-force vector required in the rider normal plane. Balanced banking
requires `f dot r = 0`, `f dot u > 0`, and `n = (f dot u) / g0`; a deliberate nonzero lateral load must
instead be named and bounded by the element contract. For a level, constant-radius, unaccelerated
turn, define signed horizontal curvature as
`kappa_h = e_y dot (t cross d(t)/ds)`. The review check is the signed relation
`phi = atan2(v^2 kappa_h, g0)`, with positive bank into positive horizontal curvature. Large
counter-bank is legal only when a named element explicitly asks for it and its resultant force and
lateral-G contract remain valid. It is never a closure device.

Height elements are vertical-plane by default. In the plane spanned by a fixed horizontal unit vector
**h** and world-up **e_y**, write `t = cos(theta) h + sin(theta) e_y`. Then
`dy/ds = sin(theta)` and `d(theta)/ds = kappa_plane` with the declared sign convention. A crest apex
is the downward crossing `theta = 0`, `d(theta)/ds < 0`; climb samples before it must have
`dy/ds > 0`, and descent samples after it must have `dy/ds < 0`. Prominence is
`y_apex - max(y_entry, y_exit)`. The existing reviewed plane-fit and out-of-plane tolerances define
planarity; entry/exit pitch and pullout are explicit endpoint conditions. A symmetric force history
is not assumed to create symmetric geometry because radius scales with `v^2` and speed changes across
the element.

## 5. Ownership

### `RidePlanner`

Owns seeded design intent and the legal ordered return story. It may select meaningful certified
choices, including role order and turn narrative, through named decision streams. It does not inspect
solver failure or choose a second story after compilation begins.

### `generator.gd`

Owns the site, station frame, terminal approach, terrain and exclusion data, route-length band, role
bands, and energy/launch intent. These remain plan facts rather than solver observations.

### New `ride_return_layout.gd`

Owns only macro return layout. It receives the actual accepted post-camelback state plus immutable
plan facts and returns ordered assignments. It contains no RNG and authors no force profile.

Calling it after prefix integration is deliberate: the true camelback exit frame and speed are then
known, so the generator does not need another approximate prefix model. It still runs before any
return element is authored.

Record release and camelback are complete prefix facts at this boundary. Their own builders and route
contracts own release length, camelback prominence, planarity, and terrain evidence. The return layout
cannot vary their duration or re-integrate candidates through them.

### Local return element builders

Own their force, spatial-curvature, twist, and transition parameters. Each builder fits one assigned
role and either publishes a compliant `ElementResult` or fails locally with named margins. It cannot
move another role's anchor or spend another role's length.

### `RideProgram.compile()`

Orchestrates the stages and carries the accepted end state from one assignment into the next. It does
not solve layout itself.

### Capture and brakes

The capture stage remains an exact numerical closer, but the planned final return assignment must
already enter the existing reserved corridor with a near-neutral frame. With capture coefficients set
to zero, the integrated route must remain inside the tight pre-capture pose corridor required by
VC-008. Any retained correction must remain below the reviewed curvature, torsion, roll, and
lateral-load visibility thresholds. Capture may correct only sub-tolerance numerical error; it may not
remain a visible 1.05-second steering element. Brakes retain their physical deceleration and exact
station contract even if their implementation is rewritten.

### `RouteContract`

Remains final authority for role ownership and lengths, total route length, loads, geometry,
clearance, terrain intent, and exact terminal state. Macro and local success never bypass it.

## 6. Minimal data contracts

Use dictionaries matching current project style; do not introduce a class hierarchy.

The layout request contains:

```text
start_state                 # actual post-camelback position/frame/speed/distance
station_frame
reserved_terminal_corridor
route_length_band_m
ordered_role_specs          # planner order; no order assumed by layout code
terrain
exclusion_corridors
```

Each role spec contains only facts needed by layout:

```text
role_id
family                      # overbanked turn, height beat, or deliberate terrain run
length_band_m
entry_speed_band_mps
exit_speed_band_mps
heading_change_band_rad
elevation_change_band_m
planarity_intent
terrain_intent
force_envelope
```

The accepted layout contains:

```text
assignments[]               # same order and cardinality as ordered_role_specs
  role_id
  entry_frame
  exit_frame
  target_length_m
  corridor
  terrain_intent
  curvature_sign            # when meaningful; never inferred later from closure error
terminal_gate
length_budget_margin_m
terrain_margins
energy_margins
```

No arbitrary world-space control points are passed to `Motion.integrate()`. Corridors are bounded
regions and endpoint contracts against which integrated results are measured.

## 7. Macro layout calculation

### 7.1 Terminal gate

The station frame and existing approach partition determine the capture-entry gate. The final return
assignment must approach that gate along the station tangent, close to level and neutral bank, inside
the unchanged 70--80 m/s entry-speed band.

### 7.2 Length allocation

Choose one total target inside the unchanged 7.8--8.2 km band before local element solving. Subtract
the accepted prefix distance and reserved capture/brake distance. The remainder is the return budget
`S_return`.

Allocate role targets by projecting their nominal lengths onto the bounded sum:

```text
L_i(lambda) = clamp(N_i + lambda w_i, lower_i, upper_i)
sum L_i(lambda) = S_return
```

Each flexibility weight `w_i` is finite and strictly positive. The sum is therefore monotone in the
single scalar `lambda`, so deterministic bisection or bounded water-filling finds the allocation. If
the sum of role minima exceeds the budget or the sum of maxima cannot reach it, the plan is infeasible
before any FVD solve. No element is stretched outside its semantic band.

### 7.3 Anchors and corridors

The layout stage fits the ordered role families between the real start and terminal gate using
geometric variables only: anchor positions, signed heading changes, radii/curvature bounds, elevation
bands, and deliberate connector allocation where the story declares a terrain run. It may use a
small bounded geometric solve, but that solve cannot see bank-profile knots, G-profile durations,
camelback timing, or local recovery timing.

The layout is not tied to one plan-view template. A turn-height-turn-height order may form an offset
S, while another legal order or terrain relationship may form a dogbone or terrace path. Those are
outcomes of the same contracts, not seed-named implementations. The planner evaluates declared
choices by the same feasibility and scoring rules for every seed.

Every turn corridor reserves enough arc for entry curvature ramp, loaded core, and exit curvature
ramp. Every height corridor reserves its pull-up, crest, and pullout distances. Straight-line chord
distance, heading change, curvature/radius bounds, elevation change, and the allocated arc length
must be mutually feasible before local authoring.

Terrain scoring is role-specific: fast terrain runs receive low-AGL intent and clearance envelopes;
height/suspense beats may remain exposed; the camelback terrace relationship remains explicit. One
universal low-AGL rule is not introduced.

Energy feasibility follows the arc-length form of the production speed equation:

```text
d(v^2 / 2)/ds = g dot t + g0 d - rolling - aero v^2
```

For return assignments `d = 0`. Macro feasibility uses a declared conservative envelope for tangent,
elevation, length, and speed rather than pretending elevation and distance alone determine drag loss.
The local production integration then supplies the authoritative speed history and must prove the
2 m/s moving floor at every RK stage and the unchanged 70--80 m/s final-gate band. Any disagreement
between the macro bound and integrated result rejects the plan; the bound is not substituted for the
physical trajectory.

If several declared layouts are feasible, choose by a deterministic score made only from normalized
contract margins: clearance, corridor slack, role-length slack, energy slack, and intended terrain
proximity. Seeded randomness may break a true score tie through an existing named planner stream;
failure feedback may not alter the choice.

## 8. Local element calculation

Each local builder receives one assignment and the integrated entry state. Its unknowns are limited
to that element's own physical shape, for example:

- a turn may vary peak spatial curvature, curvature-ramp length, and intentional twist phase;
- a height beat may vary pull-up curvature, crest-unload length, and pullout curvature; and
- a declared terrain run may vary only its own connector curvature within its corridor.

The local residual contains only that element's exit-frame error, target-length error, named
landmarks, and geometric/force margins. It contains no total-route residual, station residual before
the last assignment, or another role's length. Solves stay small; an analytic or one-dimensional
solution is preferred whenever it exists.

The integrated result must prove:

- endpoint position, tangent, rider-up, speed, curvature, and twist jets;
- assigned corridor and target-length compliance;
- turn direction and bank/resultant agreement;
- height-beat apex, prominence, planarity, and monotonic phases;
- normal, lateral, longitudinal, onset, roll-rate, and roll-acceleration envelopes;
- terrain/AGL intent and clearance; and
- positive margins at production resolution.

An infeasible element returns a structured local failure. It does not perturb upstream accepted
geometry, select another story, or enlarge a solve.

## 9. Rewrite boundary and deletion target

The affected return and terminal path should be rewritten as a coherent unit rather than incrementally
patched around the existing 12-variable solve. Existing code has no preservation entitlement merely
because one path currently passes. Physics, authored intent, public behavior, and verified contracts
survive; implementation lines do not. If the same obligations can be expressed with fewer controls,
branches, files, or lines, the smaller implementation wins.

The intended source boundary is:

- replace `ride_return_solve.gd` in full; its return, capture, and brake responsibilities may be
  redistributed or rewritten rather than copied;
- create one focused `ride_return_layout.gd` for the macro calculation;
- create one focused `ride_return_elements.gd` for local geometric/FVD element construction; and
- replace the return-specific test owner with contract-led tests for allocation, layout, local
  elements, terminal entry, and fleet integration.

Exact filenames and file count are implementation-plan decisions. Separate ownership must be obvious,
but a one-use wrapper or a file that merely forwards dictionaries is deleted. Three responsibilities
do not automatically require three classes or three files.

`motion.gd`, `bounded_solver.gd`, `generator.gd`, `ride_planner.gd`, `ride_program.gd`, and
`route_contract.gd` are all available to simplify where the accepted design directly changes their
responsibility. No file is protected because it is old or currently green. Conversely, evidence still
governs scope: the numeric matrix did not indict the bounded LM mathematics or the RK/FVD equations,
so replacing those equations would require new evidence. The spatial-profile capability may rewrite
the relevant `Motion` path completely if that is leaner than branching around the time-profile path.

Two existing fixed-order seams must change narrowly: `RidePlanner.RETURN_CELL` legality/selection and
`RideProgram._add_raceway()` emission. The planner publishes the order once; the compiler iterates it
without family-specific positional assumptions.

Once the new path is accepted, delete the current monolithic return ownership rather than retaining
two competing systems:

- the 12-entry global `RETURN_SCALAR_IDS`, bounds, seed-completion branches, and global LM call;
- global use of `record_release_core_duration_s` and `camelback_fall_duration_s` as return controls;
- total-route, station-pose, and cross-role length residuals from `_return_observation()`;
- prefix candidate re-integration and prefix caches inside `_solve_return()`; and
- comments and tests that describe a square global return solve.

Reusable span/profile construction may move into the local builders. Capture and brake behavior must
retain their contracts, but their implementation may be replaced when the result is demonstrably
smaller and equally physical.

The final implementation should contain materially less cross-role solver code and less total
accidental complexity than the current path. New files are justified only by ownership they make
clear and code they let us delete. They must not become abstraction layers around unchanged
monolithic behavior.

## 10. Verification obligations

No local Godot execution is permitted. All executable verification runs through GitHub CI.

Before production migration, pure tests must establish:

- the FVD projection identities above against known level-turn, vertical-loop, and zero-curvature
  cases;
- spatial curvature and twist shoulders satisfy analytic endpoint value/first/second-derivative
  conditions;
- local transition output is invariant to numerical knot subdivision within tolerance;
- role-order permutations are consumed generically rather than through order-specific branches;
- bounded length allocation respects every band and either sums exactly or rejects infeasibility;
- layout selection is deterministic and independent of local-solver failure feedback; and
- impossible geometry, terrain, and energy requests fail at the owning boundary.

A forced local-element failure must return one structured failure while leaving the accepted layout
bytes unchanged. It must not select another story, retry with another seed, change a warm start,
widen a tolerance, or invoke a fallback topology.

Integration acceptance retains all existing audit bands, force limits, convergence tolerances,
solver caps, terrain intent, and no-local-Godot constraints. It requires:

- import/startup budget and the complete focused manifest;
- six-seed fast return-budget regression;
- fifteen-seed smoke fleet, including seed 4096 without special handling;
- every scaled residual at or below 0.02 with positive true-band margins;
- exact station closure, capture corridor, clearance, diversity, geometry, role-length, route-length,
  load, and energy compliance;
- viewer first-frame and runtime checks; and
- clean visual-audit artifacts for seeds 42, 11, and 20260809.

Visual review must cover plan/elevation/channel summaries and opener, Immelmann, dive, camelback,
return, and station element/POV shots. The return specifically needs coherent curvature/bank intent,
continuous transitions, terrain relationship, clearance, and speed cues. Camelback planarity and its
155 m AGL terrace relationship remain required.

Artifact data must also produce sample- and time-weighted normal/resultant-G summaries and compare
them with the existing envelope and telemetry. No new average-G gate is invented.

Independent solver-math, code-diff, and visual reviews remain mandatory before merge. PR #14 stays
unmerged if the architecture cannot close the canonical fleet honestly within the existing budgets.

## 11. Scope boundaries

- No public generator API change is required.
- Existing physics constants, audit bands, tolerances, terrain intent, and evaluation caps do not move
  to make the redesign pass.
- The design does not add positive drive, a midcourse brake, unnamed distance filler, or post-hoc
  centreline smoothing.
- It does not require a fixed return order or one visual topology.
- It does not expand general story randomness until the affected element contracts are certified.
- It does not merge PR #14 on partial CI or on a seed-specific success.

## 12. Global `AGENTS.md` implementation gate

The implementation plan and every review must refer back to all four global rules:

1. **Think Before Coding.** State physical and architectural assumptions, identify ambiguous
   ownership, compare the simpler alternative, and stop for a material uncertainty before editing.
   In particular, derive the layout and FVD equations before selecting controls or residuals.
2. **Simplicity First.** Prefer a closed-form result, bounded water-filling, or a one-dimensional
   physical solve over a general optimizer. Add no configurability, fallback, or abstraction that the
   accepted return needs do not require. Passing legacy code may be replaced when the same verified
   obligations become materially shorter or clearer. If a rewrite recreates the old complexity across
   more files, it fails this gate.
3. **Surgical Changes.** Treat the whole affected code path as editable, but keep every change
   traceable to the return architecture, physical kernel support, terminal behavior, or verification.
   Surgical describes scope, not loyalty to existing lines. Unrelated cleanup is reported, not
   included.
4. **Goal-Driven Execution.** Every step names its observable success criterion, begins with a failing
   contract or regression test, and loops until CI evidence satisfies it. "Cleaner architecture" is
   not completion; physically integrated geometry, fleet closure, margins, visuals, and force
   evidence are.

These are acceptance criteria, not introductory prose. A code-diff reviewer must explicitly report
PASS or FAIL against each rule before PR #14 can merge.

## 13. Sources of truth

- `godot/motion.gd` is authoritative for the production FVD/RK equations.
- `docs/ISSUES.md` VC-001 through VC-005, VC-007, VC-008, and VC-019 define the architectural and
  visual defects this design must close.
- `docs/superpowers/ledgers/2026-08-20-full-ride-geometry-audit.md` owns the current audit evidence.
- openFVD commit `4482a15b388f76158c0b189068be96b4a45c2509` is a comparative implementation reference, not a
  dependency or authority over this repository's equations.
