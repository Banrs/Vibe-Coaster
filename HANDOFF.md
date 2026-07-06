# Claude-Coaster — Handoff for next agent

Procedural roller-coaster voxel game. OpenGL backend under `opengl/src/`.
Direction: **arcadey but grounded in realism** — every element anchored to a researched
real-world record, sized AT-AND-ABOVE it (1.0–1.75x band, small→big taper), entered at
~1.5–2.2x its real entry speed, felt g ~1–2x real sustained / ≤4x peak, transits ~1x the
real element's time, banked elements ≤1 per 3 slots. See `REALISM.md` for the full rule
table and WR anchors; `RESEARCH.md` for the records behind them.

## Repo / build / test
- Primary build (all platforms, fetches raylib 5.5 automatically):
  `cmake -B opengl/build -S opengl && cmake --build opengl/build -j`
  → `opengl/minecoaster`. On Linux, GLFW needs the X11 dev packages
  (libxrandr/xinerama/xcursor/xi/libgl1-mesa-dev). macOS: `opengl/build.sh` or the
  `MINECOASTER.command` double-click wrapper.
- Headless verification (primary): `--simtest` (stall=0f on ALL seeds is a hard gate; a
  per-seed `^ stall inside ELEM` line prints when violated; `MC_STALLDBG=1` dumps the cp
  neighbourhood), `--gaudit N` (raw + HUD + SUSTAINED + jerk tables), `--profile N`
  (per-element vDelta/net/clr/hSpan + SVG side view), `--elemsust ELEM SPEED` (isolated
  element), `--pacing` (per-mode time shares, transit seconds, flat share, element
  density, genuine-splashdown count).
- **A next agent should actually run the game** to visually confirm the carve-aware
  terrain culling (tunnel interiors) and a splashdown (banner + wheel spray over water)
  — everything else is verified headless.

## DONE 2026-07-06 later pass (honest element names, real splashdowns, WR-scale sizing)
User feedback: (a) element names are often FAKE -- SPLASHDOWN shown on non-low, non-water
track; splashdowns should be over water with spray; (b) sizes should sit AT-AND-ABOVE the
record ([1.0x, recCapMul] band), which also lands transits at ~1x the real element's time.
- **`rideElemName()` in coaster_track.cpp**: the ONE shared HUD-name diagnosis both
  renderers now call (OpenGL main.cpp HUD banner + vulkan/src/main.cpp rideCamView, whose
  static RIDE_NM table is gone). Names come from tag + ACTUAL geometry: SPLASHDOWN only
  when skimming water (<3 m over a water tile), a valley-guarded high DIP relabels by
  pitch, M_TURN reads BANKED TURN (overbanks were removed, "OVERBANKED" was fake too).
- **Real splashdowns**: DIP gets a 5x pick-weight boost when water lies ahead
  (`waterAhead`), initDip stretches the dip so its BOTTOM lands on the pond, and the
  M_DIP floor targets WATER_Y+0.9 (inside the wheel-spray window) while the next few
  steps are open water -- per-step, so the far shore doesn't hold the dip up. The
  water-aimed profile flattens the sine bottom (sin^0.4) into a held skim. Measured
  ~0.9/ride, ~0.5-1 s skim (pond width is the limiter, matching Griffon's ~1 s contact).
  The existing wheel-spray system (main.cpp SplashContact) fires as-is.
- **WR-side sizing (re-tune per user)**: HILLS frnd(60,78) single-hump (doubles only when
  budget-shaved below record); HELIX 1.6-1.9 rev (585-680 deg, ~6-7 s ~= 1.0-1.16x WR);
  STALL hang up to ~4.5 s (cap 16); BANKAIR 35-49 / WAVE 35-46 (bonus dropped); IMMEL/
  DIVELOOP radius draws 0.92-1.0 of the WR-capped value; TURN 10-14/7-10, DIVE 7-10.
  Cadence rules (bankCool/boostCool) unchanged -- record scale WITHOUT the old stacking.
- **--pacing gained a splashdown metric** (genuine water-skim instances + seconds).
- **LESSON (cost a full 8-seed stall regression)**: sinf(PI*1.0f) rounds to a TINY
  NEGATIVE float, and powf(negative, frac) = NaN -- which poisoned every cp after it.
  Guard any powf(sinf(...)) with fmaxf(.., 0).
- Verified: 8/8 seeds stall=0f; avg 243 km/h, max ~360-370; ~11/ride inversions (8.3-min
  window); gaudit BROKEN points 0 (baseline had 1), jerk 2 frames (known IMMEL seam);
  banked ~3/min means 2.1-5.3 s; HILLS mean 5.9 s max 7.2 (record-height singles);
  flat-ish 13.7%.

## DONE 2026-07-06 (banked-element cadence, real-typical durations, vulkan physics sync)
User feedback: bank/tilt elements too often vs real life AND too long (few flat/low-tilt
sections left); many elements take too long; too many dead-flat powered straights.
Measured baseline via the NEW `--pacing` tool (per-mode time accounting on the simtest
loop): banked elements ~4.7/min / 30% of ride time (BANKAIR mean 6.4 s, max 11 s; HILLS
mean 9.1 s, max 18.8 s), 36 BOOST straights/ride (one every ~14 s).
- **`--pacing` headless tool added** (main.cpp, after --simtest): per-tag instances/ride,
  mean/max transit seconds, %time, flat-ish share, element density. Use it for any pacing work.
- **Banked cadence `bankCool`**: after any banked element (TURN/HELIX/DIVE/SCURVE/BANKAIR/
  WAVE/STENGEL — `isBankedElem`), the next 2 element slots offer only low-tilt elements.
  Feel gate in eligibleElem; eligibleSafety ignores it. Plus weights trimmed (TURN 2->1.5,
  SCURVE 1.8->1.1, DIVE 1.8->1.3, WAVE 1.8->1.0, BANKAIR 1.5->0.9, DIP 1.2->1.6) and the
  fast-slot pref tamed (0.40+1.20*spd, was 0.12+2.60 -- banked turns were ~half of cruise
  picks). Result: banked ~3/min / ~17% of time, means 2.2-4.3 s.
- **Real-typical durations** (key physics: at fixed crest-g, hump transit ∝ sqrt(h), speed
  cancels -- all-record heights = record-long transits at ANY speed): HILLS 65% 26-42 m /
  35% 52-78 m (record band always single-hump; doubles only on standard band, 25%);
  BANKAIR/WAVE single hump; HELIX 1.05-1.45 rev (~4-5.5 s); STALL hang 2-3.5 s (cap 13);
  ROLL doubles 50%->25%; TURN big 9-13 / small 6-9 cps; DIVE 6-9; SCURVE cap 30;
  DIVELOOP lead-in 14->9 cps + radius draw 0.78-0.95x cap; MCBR 7-10 cps.
- **Boost cadence `boostCool`**: a boost holds the next 3 element slots un-powered
  (survival override genV<58); each boost longer (8-12 cps). 36 -> ~20 boosts/ride,
  flat-ish 15.9% -> 14.3% with proper discharge arcs.
- **Vulkan physics sync** (vulkan/src/GameCompat.h + Physics.h): the mirrored constants
  were BADLY stale (DRAG 0.0011 vs 0.00028, LAUNCH_V 100 vs 108, CLIMB_V 40 vs 27,
  BOOST_V 79 vs 62, BOOST_TRIG 48 vs 84) -- since the SHARED generator reads these, the
  Vulkan build generated a different, slower, inversion-starved ride (likely why the user
  saw no improvement there). Thrust model also synced to the current ride loop (asymptotic
  LSM launch, 160-punch boost, anti-stall kicker, V_GUARD floor only, NO top cap).
- Docs: REALISM.md rule table (+transit-time, banked-cadence, re-power rows; sustained
  now honestly ~1.4-2x -- baseline IMMEL was 4.15 not the documented 5.7); RESEARCH.md
  durations table rewritten to real-typical + new cadence section.
- Verified: 8/8 seeds stall=0f; avg 247 km/h, max 356-367; inversions ~11.5/ride on the
  8.3-min simtest window (~5/lap); gaudit HUD peaks vert <=+10.1 / >=-2.9 / lat 5.1,
  sustained TURN 5.8 HELIX 6.2 IMMEL 3.97 (baseline 4.15); jerk profile unchanged (the
  IMMEL-entry seam, open item #4, is pre-existing).

## Earlier milestones (2026-07-04 and before, compressed — details in git history)
- **g-budget geometry engine** (stepGeneric): directional curvature limits from the
  felt-g envelope (dlimPos/dlimNeg per side) + jerk budget ~2x the 15 g/s guideline;
  DROP runs a continuous height-proportional pullout; hills sized from a crest-g target
  via `hillLenFor` (killed the old ±25 g spike hills).
- **WR anchors + entry windows**: `invSpec`/`recCapMul` radii pinned to researched
  records; `invVMax`/`invVMinFrac` entry-speed windows back-solved from a 4x-real top-g
  cap; inversions scheduled into natural run-down windows (nextMode wantBoost hook,
  `invSlotUsed`); loop family carries a crest-carry constraint (`invRAt` lossPerR).
- **Stall elimination** (was chronic, now a hard 0/8 gate): quartic stall profile,
  in-CLIMB crest rounding with apex handoff, FLAT/DROP→powered-CLIMB conversion at
  ≥55 m walls, offer-time footprint gates for closed-form elements, anti-stall kicker
  tires (60·(1−v/34) under 30 m/s) in ALL hand-duplicated physics copies.
- **Roll cull per user** (disorienting): BANANA/HEARTLINE/WINGOVER/COBRA out of
  generation (rarity 0, init/step code kept for --elemsust); zero-g STALL is the one
  inverting-crest roll kept. Roll-free thrills added instead: DOUBLE-DOWN two-stage
  drops (`ddKnuckle`), inclined LSM boosts (+4-8 deg, ~45%).
- **Pacing grammar**: lap-phase energy arcs (~2.5/lap) in pickFromPool; once-per-lap
  HELIX; flat-impostor hills gated by affordability (>=36 m or the slot goes elsewhere);
  powered-flat seams eased (dy decay + seamEaseN); station cadence 205 s.
- **Carve-aware terrain culling** (main.cpp `effCol`): interval-based side-face exposure
  fixed the tunnel/cliff VOIDs. Needs the visual pass below.

## Current measured state (all 8 seeds, 2026-07-06 later pass)
- stall=0f everywhere; avg ~243 km/h; max ~360–370; LAUNCH-HAT drops ~180–270 m;
  inversions ~11 per 8.3-min simtest window (~5/lap).
- Pacing (`--pacing`): banked elems ~3/min, ~18% of time, means 2.1–5.3 s; HILLS mean
  5.9 s max 7.2 (60–78 m record singles); flat-ish 13.7%; density ~9.2 elements/min;
  genuine SPLASHDOWNs ~0.9/ride (~0.5–1 s skim + wheel spray).
- gaudit: BROKEN points 0; HUD peaks in envelope; jerk 2 frames >200 (known IMMEL seam).
- SUSTAINED: TURN ~5.8, HELIX ~6.2, ROLL ~5.0, IMMEL ~4.0, DIVELOOP ~4.0.

## OPEN / TENTATIVE
1. **Visual pass**: carve-aware culling (tunnel interiors), record-height parabolic
   hills, rounded hat crowns, and a SPLASHDOWN (banner + wheel spray over water) are
   verified by numbers/logic only — run the game and look.
2. Jerk table peaks (~80–160 g/s at seams, 2 frames >200 at IMMEL entry) still above
   the 30 threshold the audit prints — sub-cp spline granularity; only fixable with
   denser cps or seam-specific easing.
3. DIVE frequency structurally low (~1/ride); genuine splashdowns depend on water on
   the route (~0.9/ride average, 0 on dry seeds) — could bias track heading toward
   lakes if the user wants more.
4. Vulkan port outstanding items live in `vulkan/WORK_HANDOFF.md` (CSM, split-sum IBL,
   DLSS seam, async streaming, station stops); win-rtx is still a scaffold.

## Key code map (opengl/src/coaster_track.cpp unless noted)
- WR anchors/sizing: `invSpec` ~523, `recCapMul` ~562, `invVMax` ~574, `invRAt` ~617.
- `hillLenFor` ~641, `initHills` ~658; banked/roll inits above and around it.
- Cadence state: `bankCool`/`boostCool` members ~42-45; applied in `rememberElement`,
  `eligibleElem` (~982), and nextMode's wantBoost.
- Water-seeking DIP: `waterAhead` + `initDip` ~810-840; M_DIP `waterRun` floor in
  stepGeneric's dy switch.
- Slow-window inversion hook + wall-aware launch/boost: `nextMode` ~1258.
- g budgets + crest lead + wall→CLIMB conversion: `stepGeneric` ~1473.
- Shared HUD name diagnosis: `rideElemName` ~2388 (used by opengl main.cpp HUD banner
  AND vulkan/src/main.cpp rideCamView — change it once, both HUDs follow).
- Terrain skin culling: main.cpp `effCol` ~2821 + interval emission after it.
- Anti-stall kicker: FIVE copies now (simtest ~1284, pacing ~1382, gaudit ~1830,
  bench ~2024, ride ~2410) — keep in sync BY HAND like the thrust lines around them.
  vulkan/src/Physics.h carries a sixth (synced 2026-07-06).
- SegMode enum main.cpp:973; physics constants main.cpp:36-55 (mirrored in
  vulkan/src/GameCompat.h — keep in sync BY HAND).

## Lessons
- Don't give edit-capable subagents the same file concurrently.
- The generator's genV floor MUST equal the ride's operative assist floor (now the
  kicker's ~30): higher hides run-down (loops offered that crawl), lower under-sizes
  elements the assisted train overflies.
- Closed-form elements need OFFER-time footprint checks; the shared clearance floor will
  otherwise drag their rigid shapes up any hillside (66 m loop → 134 m climb stall).
- Python str.replace on code: beware substring matches across indentation variants (a
  12-space pattern matched inside 16-space lines and double-inserted the kicker).
- `--simtest` stall attribution + `MC_STALLDBG` cp dumps found every root cause fast;
  felt-g numbers alone would have misled.
- `sinf(PI*1.0f)` rounds to a tiny NEGATIVE float; `powf(negative, frac)` = NaN and
  one NaN cp poisons the whole track. Guard `powf(sinf(...))` with `fmaxf(.., 0)`.
- Mirror constants (vulkan/src/GameCompat.h) drift silently and the SHARED generator
  reads them — a stale BOOST_TRIG made the Vulkan build a different ride. When tuning
  opengl/src/main.cpp constants, sync GameCompat.h in the same commit.
