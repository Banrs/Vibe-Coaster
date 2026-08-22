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

An element authors signed curvature components in the **world-referenced pitch/yaw basis**, not in
the rolling rider frame. At every station of the centreline define

```text
yaw_normal   = normalize(t cross e_y)          # horizontal, perpendicular to the tangent
pitch_normal = yaw_normal cross t              # in the vertical plane containing t
kappa(s)     = kappa_pitch(s) pitch_normal + kappa_yaw(s) yaw_normal
```

so `kappa dot t = 0` by construction. This is the basis the production kernel integrates, and it is
the one authoritative curvature basis for this design: `kappa_pitch` and `kappa_yaw` are the two
authored geometric channels, while rider-up and twist are a separate channel that decides how that
one geometry is *felt*. Because the basis is referenced to world-up rather than to rider-up, twist
changes the rider's load split without tilting the planned turn plane — an element can be rolled to
any bank and still trace the same horizontal arc.

Sign convention, declared once and used everywhere below: positive `kappa_yaw` turns the tangent
toward positive horizontal curvature about world-up, and **`kappa_pitch < 0` at a crest** (the
tangent pitches downward). With track pitch `theta` measured from horizontal, plan-view heading
follows

```text
d(theta)/ds = kappa_pitch
d(psi)/ds   = kappa_yaw / cos(theta)
```

The `1 / cos(theta)` factor is not decorative: on pitched track a given `kappa_yaw` produces more
heading change than the flat approximation, and the macro feasibility bound of §7.3 is stated in
heading, not in yaw curvature. The basis itself is singular where the tangent is vertical
(`t cross e_y -> 0`). No return or prefix family is permitted to approach that singularity; the
integrator rejects a span whose tangent is too close to world vertical. The margin is comfortable —
the steepest prefix pitch handed to this basis is the camelback's ~33.6°, and return families are
shallower still.

Its speed-aware FVD commands are derived by projecting that world curvature into the rider frame
rather than from a constant-speed approximation:

```text
kappa_u = kappa dot u
kappa_r = kappa dot r
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
`j = 0..4`. That is the physical definition of the obligation. It is not, on its own, a measurable
acceptance test: published positions are float32 `Vector3`, and at the production sample spacing
`h ~ 0.75 m` a fourth-order finite difference of position amplifies float32 quantisation to roughly
`3e-3 m^-3` of noise against a signal of order `2.25e-6 m^-3`. Differencing the route arrays at that
order measures rounding, not geometry, so a seam check built on it would be noise with a threshold
attached.

Acceptance therefore splits by order:

- **`x^(0..2)` are compared directly** from the integrated route on both sides of the seam:
  position, tangent, and the world-space curvature vector. Starting tolerances, to be confirmed by
  measurement once the first fleet is green: position `1e-3 m`, tangent `1e-4` (unit-vector
  distance), curvature `1e-5 m^-1`.
- **`x^(3)` and `x^(4)` are analytic**, derived from each side's commanded curvature jets through
  the frame ODE rather than by differencing positions. With arc length as the parameter,
  `x' = t`, `x'' = kappa`, `x''' = kappa'`, and `x'''' = kappa''`, where `kappa'` and `kappa''` are
  arc-length derivatives of the **world-space** curvature vector and therefore include derivatives
  of the evolving pitch/yaw basis, not only the commanded component slopes. Matching component
  values alone is not sufficient. Each element publishes these jets from its own profile definition,
  and the seam requires the two published jets to agree.
- **Finite differencing of the higher orders is demoted to a coarse sanity check.** It may flag an
  order-of-magnitude disagreement between the analytic jets and the integrated path; it never
  decides acceptance and carries no tight tolerance.

The construction and seam checks therefore require:

- position and tangent agree, measured directly;
- the world-space curvature vector agrees, measured directly;
- the first and second arc-length derivatives of the world-space curvature vector agree, computed
  analytically on both sides;
- rider-up and the twist angle `phi`, `d(phi)/ds`, and `d^2(phi)/ds^2` agree.

A transition from curvature `kappa_0` to `kappa_1` uses a normalized arc-length shoulder such as

```text
h(u) = 10u^3 - 15u^4 + 6u^5,  0 <= u <= 1
kappa_q(u) = kappa_q0 + (kappa_q1 - kappa_q0) h(u),  q in {pitch, yaw}
d(kappa_q)/ds = (kappa_q1 - kappa_q0) h'(u) / shoulder_length
d^2(kappa_q)/ds^2 = (kappa_q1 - kappa_q0) h''(u) / shoulder_length^2
```

The component profile is evaluated against the evolving pitch/yaw basis, not by linearly
interpolating two fixed world vectors. Because `h'` and `h''` vanish at both ends, adjacent constant
or straight phases can be constructed to match curvature value, spatial slope, and spatial
acceleration when the frame and twist jets also match. These same profile derivatives are what feed
the analytic `x^(3)`/`x^(4)` seam jets above. The direct `x^(0..2)` comparison plus those analytic
jets remains authoritative. The same endpoint conditions and shoulder-length scaling apply to
intentional twist angle.

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

Turn banking is authored from the actual local resultant, and for the `return_turn` family it is
authored **overbanked**, not balanced. `CLAUDE.md` names two overbanked turns on the return; that is
the contract, and a balanced turn would not satisfy it. Define `f = v^2 kappa - g_perp`, the proper
force required in the rider normal plane. Balanced banking is the reference case
(`f dot r = 0`, `f dot u > 0`, `n = (f dot u) / g0`), useful as a zero point and as the
identity the projection tests check — it is not the return's default.

The `return_turn` contract is a named **counter-lateral band**, derived from the measured Falcon's
Flight counterpart. For a level turn at bank `phi` the two loads are tied by

```text
n = (v^2 / (R g0)) sin(phi) + cos(phi)
l = (n cos(phi) - 1) / sin(phi)
```

Falcon's turn B holds `phi = 77°` at `n = 2.39 g`. Its balanced bank at that speed and radius would
be `atan(v^2 / (R g0)) = 65.8°`, so the real turn is eleven degrees overbanked, and the identity
above gives `l ~ -0.47 g`: the rider is pressed down the bank, toward the inside of the turn, not
held laterally neutral. That measured excess is the shape being reproduced. The band for this family
is therefore

```text
0.2 g <= |l_peak| <= 0.6 g,  signed down the bank (toward the turn centre)
```

Twist is solved so that the integrated lateral load lands **inside** that band, not at zero. Zero
lateral is a band violation for this family, exactly as an out-of-band value is, and lateral of the
opposite sign — outward, an underbank — is rejected outright. The bound stays far inside the
±4.7 Gy envelope, so this band is a shape contract, not a safety one.

Balanced banking remains the default for any element that does not name a band. For a level,
constant-radius, unaccelerated turn, define signed horizontal curvature as
`kappa_h = e_y dot (t cross d(t)/ds)`. The review check is the signed relation
`phi = atan2(v^2 kappa_h, g0)` for the balanced reference, with positive bank into positive
horizontal curvature; the overbanked turn sits beyond that angle, on the same side. Bank on the
wrong side of the horizontal curvature is rejected. Neither the bank angle nor the counter-lateral
band is ever a closure device: the macro solve may not spend them to reach the gate.

Height elements are vertical-plane by default. In the plane spanned by a fixed horizontal unit vector
**h** and world-up **e_y**, write `t = cos(theta) h + sin(theta) e_y`. Then
`dy/ds = sin(theta)` and `d(theta)/ds = kappa_plane`, where `kappa_plane` is `kappa_pitch` under the
sign convention declared in §3. A crest apex
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
plan facts and returns ordered assignments. Its solve is the five bounded controls of §7.4 against
four station-frame residuals; it owns no force-profile, bank, or timing control. It contains no RNG
and authors no force profile.

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
to zero, the integrated route must remain inside the pre-capture pose corridor required by VC-008 —
±150 m cross, ±75 m height, 8° yaw, 5° pitch, 30° roll. Any retained correction must remain below the
reviewed curvature, torsion, roll, and lateral-load visibility thresholds. Capture may correct only
sub-tolerance numerical error; it may not remain a visible 1.05-second steering element.

Brakes retain their physical deceleration and exact station contract even if their implementation is
rewritten. The brake is a one-dimensional solve on peak brake g against the moving-boundary speed,
bisected inside the existing `[0, 3.6] g` bound, and it needs two things stated:

- **Evaluation cap 32.** The one-dimensional bracket must be allowed to converge on the widened
  70–80 m/s entry band without a retry path; 32 unique evaluations is the cap.
- **`F(peak)` is defined on integration failure.** Above the bracket's operating point the train
  stops before the span ends and the integration terminates early — at 3.6 g it stops in about 90 m
  of the 147 m moving span. That is not an error case to abort on: the residual is then the
  **stopping shortfall**, returned as a positive value (metres of span left unused, or the
  equivalent signed speed deficit), so the function stays monotone and the bracket stays valid
  across the whole `[0, 3.6]` range.

The operating point is well inside the bound: closing 80 m/s over the 147 m moving span needs a mean
of 2.19 g, and the shouldered profile peaks at roughly 2.0–2.6 g across the entry band against the
3.6 g bound. That is deliberately above real magnetic practice — measured eddy-current brake runs sit
at 1.0–1.5 g — because this is a **held friction/hydraulic deceleration profile**, whose retardation
does not decay with speed the way an eddy-current brake's does. The profile is honest about what it
models; it is not an eddy-current brake wearing a larger number.

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
  heading_change_rad
  elevation_change_m
terminal_gate
target_total_length_m       # the accepted S_return, the fifth macro control
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

Subtract the accepted prefix distance and the reserved capture/brake distance from a total route
length inside the unchanged 7.8--8.2 km band. The remainder is the return budget `S_return`.

`S_return` is a **band, not a number**: the route band gives it a lower and an upper bound once the
prefix is fixed, and §7.4 makes it the fifth bounded control of the macro solve rather than a value
chosen once up front. Allocation therefore runs inside each macro evaluation, water-filling role
targets to whatever `S_return` the solver is currently proposing.

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

#### Heading-change feasibility

A turn's heading change is not free. Its allocated arc, its entry speed, and the maximum bank the
family will accept bound it, and that bound is a **macro feasibility contract** checked before any
local element is authored:

```text
|delta_psi| <= 0.8 L g0 tan(phi_max) / v^2
```

`L` is the allocated role length, `v` the entry speed, and `phi_max` the family's bank ceiling; the
`0.8` is the fraction of the allocated arc that carries loaded curvature once the two quintic
shoulders are reserved. At the declared role-length bands and the 70--80 m/s entry band this admits
roughly **75--111° for turn A and 77--102° for turn B**. A layout that asks for more is rejected at
the macro stage, with the shortfall named, rather than handed to a local solve that would have to
break the bank or force envelope to deliver it.

The layout is not tied to one plan-view template. A turn-height-turn-height order may form an offset
S, while another legal order or terrain relationship may lean the path toward the terrain instead.
What the contract above **excludes** is a 180° reversal: a dogbone plan-view is not an allowed
topology here, because reversing heading inside these role lengths at 70--80 m/s needs 3.3--6.2 g of
normal load against a 4.0 g held limit. It is refused by the bound, not by taste. The allowed
topologies are those the bound admits. Those are
outcomes of the same contracts, not seed-named implementations. The planner evaluates declared
choices by the same feasibility and scoring rules for every seed.

Every turn corridor reserves enough arc for entry curvature ramp, loaded core, and exit curvature
ramp. Every height corridor reserves its pull-up, crest, and pullout distances. Straight-line chord
distance, heading change, curvature/radius bounds, elevation change, and the allocated arc length
must be mutually feasible before local authoring.

Terrain scoring is role-specific: fast terrain runs receive low-AGL intent and clearance envelopes;
height/suspense beats may remain exposed; the camelback's declared `apex_agl_m` band remains
explicit. One universal low-AGL rule is not introduced.

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

### 7.4 Macro solve dimension

The obvious control set — signed heading change for the two turns and signed net elevation for the
two heights — is **rank-deficient** against the four station-frame residuals, and saying so is part
of the design rather than something to discover in CI. The degeneracy is structural: the terminal yaw
residual fixes only the sum `psi_a + psi_b`, which leaves the cross-track and forward residuals both
depending on `psi_a` alone; and the two elevation controls enter only the vertical residual, so they
are indistinguishable from each other in the Jacobian. Four controls, four residuals, rank three.

**Decision: `S_return` is the fifth control.** It is already a bounded quantity — the 7.8--8.2 km
route band gives it a band once the prefix is accepted — and it is the one variable that moves the
plan-view chord without touching heading. The macro solve is therefore:

```text
controls (5, all bounded):  delta_psi_a, delta_psi_b, delta_h_a, delta_h_b, S_return
residuals (4):              cross-track, vertical, forward, terminal yaw
```

Each evaluation water-fills the role allocation of §7.2 to the currently proposed `S_return`, so
length allocation stays a deterministic function of the control vector rather than a separate stage.
Five bounded controls against four residuals is underdetermined, which is the correct shape here: it
is solved by the existing damped bounded least-squares `BoundedSolver`, regularised toward the
nominal control vector so the extra freedom resolves deterministically rather than drifting. The two
elevation controls split the vertical residual by their nominal weights, which removes their mutual
degeneracy without inventing a fifth residual.

**Pitch and roll at the terminal gate are deliberately not residuals.** They are closed by
construction: every height family's exit-frame contract ends at zero pitch, and every turn family's
exit-frame contract ends at zero bank. Whatever the last return role is, it hands the gate a level,
unbanked frame because its own contract says so. Adding gate pitch and roll residuals would ask the
macro solve to re-derive something the element contracts already guarantee, and would reintroduce
exactly the cross-role coupling this design removes.

Residual scales are declared, not implied, so that the shared convergence language means one thing:

```text
cross    5 m
vertical 5 m
forward  5 m
yaw      0.02 rad
```

A "scaled residual at or below 0.02" therefore means 0.1 m of position error and 0.0004 rad of yaw
error at the gate.

The evaluation cap follows the same derivation the repository already uses for bounded solves,
`1 + K(n + 1) + R` — one initial evaluation, then per iteration one Jacobian probe per control plus
the trial step, plus retry evaluations. With `n = 5` the layout solve uses the repository's existing
`MAX_RETURN_EVALUATIONS = 88`; no new cap is introduced and no existing cap moves.

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

Local Godot may be used freely for iteration. GitHub Actions CI is the RED/GREEN verdict: a claim of
red or green that is not backed by a CI run is not evidence.

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
solver caps, terrain intent, and the CI-is-the-verdict constraint. It requires:

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
declared `apex_agl_m` band of 140--170 m remain required, along with its rise/fall symmetry
tolerance of |rise arc - fall arc| <= 5 m.

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

### Honest physics is inherited, not validated

One boundary deserves naming because the rewrite will be measured against it. The frozen
`AERO_PER_M = 7.5e-5` corresponds to `CdA ~ 1.73 m^2` for a 12 t train, roughly 2.8x under-damped
against the derivation in
`docs/superpowers/specs/2026-08-15-honest-drag-derivation.md`. That single constant is the sole
reason the return arrives at the station at 70--80 m/s and therefore the sole reason a ~2.2 g mean
brake is needed to stop it inside 150 m. Under honest drag the terminal would be slower and the
brake milder.

The rewrite **inherits** that terminal condition; it does not test it, and a green fleet under this
design is not evidence that the frozen drag constant is right. Nothing in this design may be
described, in code comments, reports, or reviews, as validating `AERO_PER_M`. Correcting the drag
constant is separate work with its own measured consequences, tracked in `docs/ISSUES.md` issue 2.

## 12. Global `CLAUDE.md` implementation gate

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
