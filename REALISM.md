# Realism scaling — how to size MINECOASTER

MINECOASTER is **arcadey but grounded in realism**. Every quantity is anchored to a
**researched real-world record**, then scaled by a fixed design rule:

| Rule | Value |
|---|---|
| **Element size/height** | 1.0–1.75x the element's WR, scaling **inversely with size**: small elements (corkscrew ~6 m radius) may reach 1.75x, the biggest (Immelmann 66 m, top hat 139 m) cap at ~1.25x. `recCapMul()` in `opengl/src/coaster_track.cpp` implements the taper. |
| **Entry speed per element** | ~1.5–2.2x that element's REAL entry speed (not the ride's top speed). Enforced by `invVMax()`/`invVMinFrac()` entry windows + the slow-window scheduler in `nextMode`. |
| **Sustained felt g** | ~1–2x the element's real sustained value (measured historically via the now-retired `--gaudit` SUSTAINED table: TURN 6.1 ≈ 2x, HELIX 8.1 ≈ 1.8x, LOOP 6.7 ≈ 1.5x, IMMEL 4.3 ≈ 1.0x, DIVELOOP 4.0 ≈ 0.95x; `--audit`'s gate G tracks the surviving multiplier bands — hat drop / hill height / helix rotation). |
| **Peak felt g** | ≤ ~4x the element's real peak; in practice lands 2.2–3x. Vertical HUD peaks ≈ +9..+11, airtime ≥ −4, lateral ≤ ~6. |
| **Jerk / transitions** | curvature + jerk budgets derived from ~2x the ~15 g/s real onset guideline (clothoid-style linear curvature ramps via `jlim`/`dlimPos`/`dlimNeg` in `stepGeneric`). |
| **Element transit time** | ~1x the element's real transit, achieved by sizing AT-AND-ABOVE the record (the [1.0x, cap] band): a WR-scale element at the game's speeds inherently takes about the real element's time (for ballistic humps transit ∝ √h and speed cancels). The pathology to avoid isn't record size — it's record size × record count × double-humps stacking into 9–18 s instances. |
| **Banked-element cadence** | ≤ 1 banked/tilted element (turn, helix, S-curve, dive turn, banked hill, wave, Stengel) per 3 element slots — `bankCool` in `coaster_track.cpp` — so every banked stretch is followed by low-tilt track (straight hills, dips, drops), like a real layout alternating lateral and vertical force events. Lands ~3 banked/min at ~2–5 s each (real rides run ~1–2/min). |
| **Re-power cadence** | boosts are FEWER but LONGER (`boostCool` 3 element slots, 8–12 cps each): discharge arcs like a real multi-launch coaster, not a dead-flat straight every ~14 s. Flat-ish track (FLAT+LAUNCH+BOOST+station) ~14% of ride time (real block sections total 25–40%). |
| **Top speed** | ~350–370 km/h (≈1.7–1.8x Kingda Ka's 206), average ~245–255 km/h. |

## WR anchor table (researched 2026-07, in `invSpec`/init functions)

| Element | Real record | Anchor in code |
|---|---|---|
| Vertical loop | Full Throttle 48.8 m (Tormenta 54.6 m claimed 2026) | rMaxRec 22 (height ≈ 2.6x lR as built) |
| Immelmann | Tormenta Rampaging Run 66.4 m | rMaxRec 33 |
| Dive loop | Steel Curtain 60 m | rMaxRec 28; now a genuine REVERSE-Immelmann shape (climb + half-twist to inverted, then a half-loop down) that reverses heading ~180 deg, antiparallel exit to entry (the old full-360 loop shape only netted ~67 deg) |
| Pretzel loop | Tatsu 38 m | rMaxRec 19 |
| Corkscrew/roll | ~5–6 m radius real | rMaxRec 6, hardcoded 6–10 m ranges; entry window (`invVMax`) raised 54 -> 62 m/s so ROLL actually overlaps the run-down speeds LOOP/IMMEL/DIVELOOP were monopolizing — at 54 the window sat entirely below cruise and ROLL never spawned |
| Drop (tallest) | Falcon's Flight: 158 m drop element, ~195-200 m cliff-assisted elevation change (Six Flags Qiddiya) | MEGA climbTop 250±25(speed)±15(rand), clamped [40, 285], first-launch hat hardcoded frnd(240, 275); MID-tier climbTop frnd(90, 165) (~40% of laps, per HEIGHT-TIER VARIETY); crest is HARD-CAPPED at the SAMPLED spline peak < 300 m (not just the control point), enforced by `ceilNow`/`ceilY` in `coaster_track.cpp` and audited by `--audit` gate B |
| Top hat tower | tallest operating towers ~128-139 m (TT2 class; Kingda Ka demolished 2025) | MID-tier (non-mega) climbTop frnd(90, 165) |
| Airtime hill | tallest real camelbacks ~60 m | hillH frnd(46, 62) = 1.0–1.3x WR, SINGLE hump; chain (bunny-hop) hills frnd(18, 30) per hop, demoted from a single hill when the chain would climb rising ground (doubles only when the ballistic budget shaves it below record height) |
| Zero-g stall | RMC (Goliath SFGA 2014; ArieForce One ~4.5 s hang) | quartic ballistic crest, hang ~2.5–4.5 s (up to the record) |
| Helix | Goliath SFMM 585°, 4.5 g sustained 6 s | rotation target 1.6–1.9 rev (1.0–1.16x WR); a speed-scaled ~7 s duration ceiling binds on the hottest entries (~1.3–1.5 rev built) — duration outranks rotation per user. ~4–7 s, once per lap |
| Splashdown | B&M dive-coaster water brake (Griffon/SheiKra), skim ~1 s | water-seeking DIP: 5x pick weight near water, dip bottom AIMED at the pond, held skim at WATER_Y+0.9 (inside the wheel-spray window); ~0.6/ride when water is on the route; HUD says SPLASHDOWN only when genuinely skimming (`rideElemName`, same `submergedGround()` predicate as the spray) |
| g standards | ASTM F2291 ≈ +6 g <1 s, ~−2 g, ±2 lat; ~15 g/s onset | budgets at ~2x |

Removed from generation per user (roll overload): banana roll, heartline roll,
overbanked turn (WINGOVER). New roll-free thrills: DOUBLE-DOWN two-stage drops,
inclined LSM boosts (+4-8°, Falcon's Flight style). Full per-element data: `RESEARCH.md`.

## Occurrence rules (2026-07-08)

How often each element/family shows up per lap, real-anchor × multiplier idiom (`invBudget`,
`chooseElement`/`rollElementPick`, `coaster_track.cpp`):

- **Inversions: 2–4/lap total**, enforced by `invBudget = irnd(2, 4)` (re-rolled every lap in
  `startLaunch`/`reset`). The audit's gate I fails a seed if the 3-lap average falls outside
  [2, 4].
- **Type shares are NOT yet real-life-weighted.** Current measured census (8 seeds × 3 laps,
  `--census 8`): IMMEL ~37%, ROLL ~18%, LOOP ~19%, DIVELOOP ~24%, STALL ~3%. A real-anchored
  share scheduler was built targeting ROLL ~40% / LOOP ~30% / IMMEL ~10% / DIVELOOP ~10% (all
  ≈1.0x their real installed-base share, renormalized over the kept types) / STALL ~10% (~6x
  its ~1.5% real share — deliberate RMC-signature boost). It was measured, but it destabilized
  the layout generator (it fights the eligibleSafety-bypass and layout-reshuffle instability
  classes — see `opengl/COASTER_TODO.md`) and was **reverted/deferred**. This is the known
  open item.
- **Cliff dive: ≥1/lap GUARANTEED**, re-arms same-lap on apex fizzle (`cliffFizzles` counter,
  bounded to 6 re-arms so a massif that can never hold a sub-300 crest can't loop the lap into
  all-climbs). Measured census: 24/24 laps across 8 seeds (`cliffMiss=0`).
- **Quota families ≥1/lap**: top hat / HILLS / TURN are HARD-enforced per census lap (gate I
  fails the seed if any is absent); HELIX / DIP / banked-airtime group (WAVE|BANKAIR|STENGEL)
  are WARN-only (terrain-gated — a pathological seed's terrain can make one genuinely
  unreachable for a lap without that being a generator bug).

## Hard rules (do not break)

1. **Earth-real gravity.** `GRAV = 9.81`; 1 voxel = 1 m. Felt g is true Earth g.
2. **Speed dictates size.** Elements are sized from live entry speed (`genV`):
   `r = v²/((gT−1)·G·gMul)` clamped to the WR band. Loop family also carries a
   **top-speed constraint** (`invRAt` lossPerR): the crest must still carry ≥30 m/s.
3. **Never brake for g.** g is managed by geometry (radius, entry windows, crest-g-sized
   hill lengths), never by trimming speed. The only assists are powered (LSM/boost/kicker).
4. **No unpowered 100 m+ climbs.** Terrain walls ≥55 m convert FLAT/DROP into a powered
   CLIMB; an anti-stall kicker (real friction-tire practice) holds ≥~30 m/s everywhere
   outside stations.
5. **Elements live near the ground.** `maxTrickHeight` bands + cliff/canyon footprint
   gates in `eligibleElem`; height comes from terrain and the once-per-lap top hat.

## Verify (headless, no GPU)

Legacy `--simtest`/`--gaudit`/`--elemgtest`/`--cobratest`/`--divelooptest`/`--stationtest`/
`--elemsust` modes are REMOVED; `--audit` supersedes them (gates A–I, one SVG side-profile per
seed in `opengl/audit/`, gitignored).

```sh
./minecoaster --audit 8     # gates A-I: A=stall(MUST be 0f x8) B=crest<300 C=hat-crown D=HILLS
                             # E=pitch-continuity(warn) F=roll-continuity G=multiplier-conformance(warn)
                             # H=cliffdive I=census(quota+inversions); writes opengl/audit/seedN.svg
./minecoaster --census 8    # per-lap element-occurrence counts; MUST be cliffMiss=0, invOutOfRange=0
./minecoaster --rollingdump 2   # actually laps the ride (station cycle) so it also reaches the
                             # ~2/3-lap CLIFFDIVE and later-lap elements the fixed --audit window can't
./minecoaster --profile N   # hills: vDelta ~46-62 (or budget-shaved) with hSpan ~300-450, net ~0
./minecoaster --pacing      # banked elems <= ~1/3 of picks (~3/min, means 2-4.5 s); flat-ish <= ~15%; HILLS mean ~6 s; ~0.5-1 genuine SPLASHDOWN/ride
```
`MC_DUMP_ELEM=<NAME|ALL> MC_DUMP_SEEDS=<N> ./minecoaster --audit <seeds>` dumps every control
point of `--audit`'s static 470-cp window (per-cp kind/pos/heading/dy/terrain/roll/v) alongside
the gate reports, exiting after the last dumped seed — see `opengl/COASTER_HANDOFF.md` for the
full invocation and field layout.
