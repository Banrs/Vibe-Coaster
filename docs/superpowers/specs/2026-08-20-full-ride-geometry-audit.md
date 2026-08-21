# Full Ride Geometry Audit — Bounded Design

## Goal

Make the generated ride read like a deliberately designed, record-breaking coaster across
all material elements, with FVD remaining the sole physical source of truth.

## Current failure

The compiled route currently proves control-profile seams and role ownership, but not the
spatial identity of the whole elements. Several families use independent roll or lateral
pulses, so a transition can be numerically smooth while the centreline visibly changes plane,
restarts a roll, or acquires an unintended heading change. The return solve can also alter
height-beat controls without an explicit terrain-relative objective. The camelback is the
clearest failure, but the same authoring pattern appears in the opener, inversion, wave, dive,
and return families.

## Design

1. Extend the existing whole-role geometry contract so every material role publishes the same
   measured evidence: arc length, vertical and plan extents, entry/exit pitch and bank, heading
   drift, planarity, local terrain AGL where terrain is available, and force/roll transition
   continuity. A role with no researched target remains explicitly unadopted, but its evidence
   is still emitted and CI rejects missing or malformed audit coverage.
2. Keep `godot/motion.gd` as the only FVD integrator. Geometry changes are made by changing the
   authored normal, lateral, drive, and roll controls that the integrator consumes. No route
   vertices are post-edited and no camera/FOV effect is used to hide excessive clearance.
3. Give each intended roll or lateral transition one owner spanning its complete geometric
   gesture. Replace adjacent pulse/restart patterns with shared smooth schedules. A short
   numerical knot may remain, but it cannot be a semantic hold or a second independent gesture.
4. Re-author the camelback as one vertical-plane FVD gesture: zero lateral force, zero bank
   intent, a continuous pull-up/crest/pullout load narrative, and a tangent pitch of 0° at the
   apex. There is no `rise-hold` or `pullout-hold` semantic span.
5. Preserve the record scale from the README while improving ground-relative perception:
   camelback prominence remains 245–255 m above its local endpoints/valley reference, while
   its apex AGL is targeted at 140–170 m with 155 m as the nominal value. The placement/terrain
   contract, not a render-time clamp, owns this relationship. The rest of the return gets an
   explicit AGL audit so high-speed beats cannot silently float above the terrain.
6. Preserve researched ride principles: hills are predominantly vertical-plane unless their
   real element requires otherwise; turns use an intentional bank schedule; inversions own one
   continuous roll; deliberate slow crest remains the one intentional slow beat; launch/brake
   timing remains time-domain because time is the physical intent there.

## In scope

- Whole-role audit and transition evidence for all material roles.
- Shared transition authoring/validation and the highest-impact broken element families.
- Planar camelback and terrain-relative height targets.
- GitHub CI focused suites, startup/import timing, smoke runtime, and diagnostics.
- README/issue/spec references needed to make the new contracts discoverable.

## Out of scope

- Replacing the existing FVD kernel with a second solver.
- Rebuilding the terrain renderer, camera, scenery, or audio system.
- Inventing precise geometry targets where the repository has no trustworthy counterpart
  evidence.
- Changing the record-breaking route envelope, launch speed, dive, or capture contract merely
  to make a metric convenient.

## Acceptance criteria

- Every generated material role has a finite, deterministic audit record and an explicit status.
- Every role-to-role seam reports boundary state and does not hide a control or roll discontinuity.
- The camelback has no lateral or roll control, no semantic hold span, zero-degree crest pitch,
  vertical-plane metrics within the existing contract thresholds, and the stated prominence/AGL
  bands.
- Canonical ride speed, route-length, terrain-clearance, dive, capture, and load gates remain
  green.
- CI proves project import, focused tests, ride smoke, viewer live frames, and a measured
  startup budget on the GitHub runner. Local Godot execution is intentionally not part of this
  acceptance run.
