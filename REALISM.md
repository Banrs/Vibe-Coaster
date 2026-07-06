# Realism scaling — how to size MINECOASTER

MINECOASTER is **arcadey but grounded in realism**. Every quantity is anchored to a
**researched real-world record**, then scaled by a fixed design rule:

| Rule | Value |
|---|---|
| **Element size/height** | 1.0–1.75x the element's WR, scaling **inversely with size**: small elements (corkscrew ~6 m radius) may reach 1.75x, the biggest (Immelmann 66 m, top hat 139 m) cap at ~1.25x. `recCapMul()` in `opengl/src/coaster_track.cpp` implements the taper. |
| **Entry speed per element** | ~1.5–2.2x that element's REAL entry speed (not the ride's top speed). Enforced by `invVMax()`/`invVMinFrac()` entry windows + the slow-window scheduler in `nextMode`. |
| **Sustained felt g** | ~1.4–2x the element's real sustained value (measured via `--gaudit` SUSTAINED table). The duration rule below binds FIRST: where holding ≥1.75x would need a longer bank/coil than the transit multiple allows (helix), the g multiple yields, not the duration. |
| **Peak felt g** | ≤ ~4x the element's real peak; in practice lands 2.2–3x. Vertical HUD peaks ≈ +9..+11, airtime ≥ −4, lateral ≤ ~6. |
| **Jerk / transitions** | curvature + jerk budgets derived from ~2x the ~15 g/s real onset guideline (clothoid-style linear curvature ramps via `jlim`/`dlimPos`/`dlimNeg` in `stepGeneric`). |
| **Element transit time** | ~1x the element's real transit, achieved by sizing AT-AND-ABOVE the record (the [1.0x, cap] band): a WR-scale element at the game's speeds inherently takes about the real element's time (for ballistic humps transit ∝ √h and speed cancels). The pathology to avoid isn't record size — it's record size × record count × double-humps stacking into 9–18 s instances. |
| **Banked-element cadence** | ≤ 1 banked/tilted element (turn, helix, S-curve, dive turn, banked hill, wave, Stengel) per 3 element slots — `bankCool` in `coaster_track.cpp` — so every banked stretch is followed by low-tilt track (straight hills, dips, drops), like a real layout alternating lateral and vertical force events. Lands ~3 banked/min at 2–4 s each (real rides run ~1–2/min). |
| **Re-power cadence** | boosts are FEWER but LONGER (`boostCool` 3 element slots, 8–12 cps each): discharge arcs like a real multi-launch coaster, not a dead-flat straight every ~14 s. Flat-ish track (FLAT+LAUNCH+BOOST+station) ~14% of ride time (real block sections total 25–40%). |
| **Top speed** | ~350–370 km/h (≈1.7–1.8x Kingda Ka's 206), average ~245–255 km/h. |

## WR anchor table (researched 2026-07, in `invSpec`/init functions)

| Element | Real record | Anchor in code |
|---|---|---|
| Vertical loop | Full Throttle 48.8 m (Tormenta 54.6 m claimed 2026) | rMaxRec 22 (height ≈ 2.6x lR as built) |
| Immelmann | Tormenta Rampaging Run 66.4 m | rMaxRec 33 |
| Dive loop | Steel Curtain 60 m | rMaxRec 28 |
| Pretzel loop | Tatsu 38 m | rMaxRec 19 |
| Corkscrew/roll | ~5–6 m radius real | rMaxRec 6, hardcoded 6–10 m ranges |
| Drop (tallest) | Falcon's Flight ~200 m (Six Flags Qiddiya) | mega climbTop frnd(200, 250) |
| Top hat tower | tallest operating towers ~128-139 m (TT2 class) | non-mega climbTop frnd(100, 139) |
| Airtime hill | tallest real camelbacks ~60 m | hillH frnd(60, 78) = 1.0–1.3x WR, SINGLE hump (doubles only when the ballistic budget shaves it below record height) |
| Zero-g stall | RMC (Goliath SFGA 2014; ArieForce One ~4.5 s hang) | quartic ballistic crest, hang ~2.5–4.5 s (up to the record) |
| Helix | Goliath SFMM 585°, 4.5 g sustained 6 s | 1.6–1.9 rev (585–680°, ~6–7 s) = 1.0–1.16x WR rotation, once per lap |
| Splashdown | B&M dive-coaster water brake (Griffon/SheiKra), skim ~1 s | water-seeking DIP: 5x pick weight near water, dip bottom AIMED at the pond, held skim at WATER_Y+0.9 (inside the wheel-spray window); HUD says SPLASHDOWN only when genuinely skimming (`rideElemName`) |
| g standards | ASTM F2291 ≈ +6 g <1 s, ~−2 g, ±2 lat; ~15 g/s onset | budgets at ~2x |

Removed from generation per user (roll overload): banana roll, heartline roll,
overbanked turn (WINGOVER). New roll-free thrills: DOUBLE-DOWN two-stage drops,
inclined LSM boosts (+4-8°, Falcon's Flight style). Full per-element data: `RESEARCH.md`.

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

```sh
./minecoaster --simtest    # MUST be stall=0f on all 8 seeds; avg ~245-255, max ~350-370
./minecoaster --gaudit 4   # HUD peaks: vert <= ~+11 / >= ~-5, lat <= ~6; SUSTAINED ~1.4-2x real per element
./minecoaster --profile N  # hills: vDelta ~60-78 (or budget-shaved) with hSpan ~300-450, net ~0
./minecoaster --pacing     # banked elems <= ~1/3 of picks (~3/min, means 2-4.5 s); flat-ish <= ~15%; HILLS mean ~6 s; ~1 genuine SPLASHDOWN/ride
```
`MC_STALLDBG=1 ./minecoaster --simtest` dumps the cp neighbourhood of any crawl-stall.
