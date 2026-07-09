# Coaster generator — session handoff (2026-07-08)

Handoff for a fresh agent/chat continuing the coaster realism work. Read this first,
then `opengl/COASTER_TODO.md` (authoritative residual/blocked-work list).

## How to build & verify (this Mac, no cmake)
```
cd /Users/danielho/Documents/Coding/VSC/mythostest/opengl && \
clang++ -std=c++17 -O2 -o minecoaster src/main.cpp \
  -I../src/vendor/raylib/src -L../src/vendor/raylib/src -lraylib \
  -framework Cocoa -framework IOKit -framework CoreVideo -framework OpenGL \
  -framework CoreAudio -framework AudioToolbox
```
- `coaster_track.cpp`, `coaster_elements_ext.cpp`, `render_fx.cpp` are `#include`d INTO
  `main.cpp`. Editor/LSP "undeclared identifier" errors on them are FALSE POSITIVES — only
  the clang build above is truth.
- **All legacy headless test modes are REMOVED** (`--simtest`, `--gaudit`, `--elemgtest`,
  `--cobratest`, `--divelooptest`, `--stationtest`, `--elemsust`, and the `Track::forcedElem`
  hook they used). `--audit` is now the sole acceptance harness; `--census` and `--rollingdump`
  remain as focused companions. Non-test utility modes (`--profile`, `--pacing`,
  `--exporttrack`, `--orbitshot`/`--rastershot`/`--frames`/`--watershot`/`--cobrashot`/
  `--elementshot`, `--gtest`/`--gtrace`/`--bench`, `--rttest`) are unchanged.
- **HARD GATE:** `./minecoaster --audit [seeds]` (default 8). Prints a per-seed gate report
  + an SVG side-profile per seed (`opengl/audit/seedN.svg`, gitignored) + a gate×seed matrix +
  gate G/I summary tables. Exit code is nonzero if any HARD gate fails on any seed — that's
  expected right now. Known-fails at this checkpoint (see COASTER_TODO.md): gate C on all 8
  seeds (first-hat faces ~46-52° vs the 55-58° band), gate F on ~5 seeds (residual
  banked→banked dead spots the roll carry-through didn't cover), gate H on ~5 seeds (the
  static-window face measurement, not the real per-lap dive — census cliffMiss=0). The run
  must still complete and print the full matrix (18 gate-failures at this checkpoint).
  - Gate **A** = bounded rolling-sim stall (MUST be `stall=0f` every seed).
  - Gate **B** = sampled-spline crest < 300 m (every top-hat / wall-climb).
  - Gate **C** = hat crown quality (no apex shelf, no >1 dy turning point, climb/drop face
    best-3 pitch within [55°, 58°] of target — currently FAILS, known issue, see TODO).
  - Gate **D** = HILLS integrity (no interior flat run ≥3 cps, troughs must descend).
  - Gate **E** (WARN) = pitch-continuity 2nd-difference reversal density per kind.
  - Gate **F** = no banked→banked "dead spot" (a held near-zero-roll run bridging two
    banked stretches).
  - Gate **G** (WARN) = multiplier conformance vs REALISM.md bands (hat drop, hill height,
    helix rotation).
  - Gate **H** = signature cliff dive: static-geometry face/drop bounds AND per-lap census
    presence (≥1/lap, hard).
  - Gate **I** = census (quota families ≥1/lap where hard-gated, inversions/lap ∈ [2,4],
    no single inversion type > 50% of the seed-set total).
- `./minecoaster --census [seeds]` — generation-only occurrence census (no physics sim): per
  lap, per seed, prints inversion-type counts + quota-family counts + WARNs. Acceptance line:
  `laps=N invOutOfRange=0 cliffMiss=0`.
- `./minecoaster --rollingdump [seeds]` — actually LAPS the ride (station cycle, real
  popFront/genPoint streaming) instead of building one frozen window, so it's the only mode
  that reaches the ~⅔-lap signature CLIFFDIVE and any later-lap element. `MC_ROLL_STATIC=1`
  makes it dump the same static window `--audit` does (prefix diff-checkable against it).
- **MC_DUMP_ELEM/MC_DUMP_SEEDS test instrument — REHOMED into `--audit`'s static window.**
  It used to live in the now-deleted `--gaudit`; it now runs inside `audit_mode::auditSeed()`
  immediately after the same 470-cp `while ((int)t.cp.size() < 470) t.ensureAhead(...)` window
  build, same env-var interface, same `[dump]` line format (`seedN cpK kind=NAME
  pos=(x,y,z) heading=H dy=+D terr=T roll=+R v=V`). **New invocation:**
  ```
  MC_DUMP_ELEM=<NAME|ALL> MC_DUMP_SEEDS=<N> ./minecoaster --audit <seeds>
  ```
  e.g. `MC_DUMP_ELEM=HELIX MC_DUMP_SEEDS=2 ./minecoaster --audit 2` or
  `MC_DUMP_ELEM=ALL MC_DUMP_SEEDS=1 ./minecoaster --audit 1`. Dumps every cp of the matching
  kind (or every cp if `ALL`) for seeds 1..dumpSeeds, printing `--- run end ---` between
  non-contiguous runs, then `exit(0)`s once `seed >= dumpSeeds` — i.e. seeds at/after the last
  requested one are dumped but never reach their own gate report (same short-circuit the old
  `--gaudit` had). Parse with python3; pitch between cps = `atan2(dy, horizontal_dist)` deg.
- **Gotcha:** `--audit`'s (and hence the rehomed dump's) window is a FIXED 470-cp static build
  that never rolls, so it structurally can't reach the ⅔-lap signature CLIFFDIVE or any
  later-lap element — use `--rollingdump` for that (it also drives gate H's per-lap census
  corroboration internally, via the same `census()`/`rollingSim()` helpers `--audit` uses).

## Design rules (user spec, final as of 2026-07-08)
- Element heights **1.25–1.75× real world-record** (small elems near 1.75×, biggest taper
  to 1.25×; never below 1.25×).
- Radii: size-multiplier "plus a bit", HARD cap **2.0× WR radius (smaller elems) / 1.5× WR
  (larger elems)**. Do NOT balloon radii by v²/entry-speed scaling. **User ACCEPTS high g**
  from tight radii — never soften geometry / g-cap to hide it; stability (no stalls/NaN/
  exploding geometry) still matters.
- Entry speeds 1.5–2.2× real; sustained g ≥1.75× real per element; peak g ≤4× real.
- **Top hat (normal launch hat):** CREST height (absolute crestY, SAMPLED spline peak, not
  just the control point) **< 300 m HARD** (the cap is on the crest, NOT the drop). MEGA hats
  (~60% of laps) run climbTop 250±25(speed)±15(rand) clamped [40,285] (first-launch hat
  hardcoded 240–275); MID hats (~40%) run climbTop 90–165, so a ride shows a genuine spread of
  drop sizes (not one identical giant per lap).
- **Top-hat angles:** climb AND drop both ~65° (±) SUSTAINED (not single-segment spikes) —
  BUT a smooth clothoid/parabolic CROWN over the apex takes priority over hitting a strict
  65°; NO flat shelves on top. Currently sits at ~46–52° on first hats (audit gate C
  known-fail — crest containment was prioritized over the steeper face this batch; see TODO).
- **Signature cliff dive** is the ONLY near-90° (85+°) element: `CD_FACE_P = -88°`. Fires
  ~⅔-lap, GUARANTEED ≥1/lap (re-arms same-lap on apex fizzle, census 24/24 laps across 8
  seeds). Crest < 300, total drop ~250–275 (≥150 floor), face over ≥60 m, wall-hug within
  ≤8.5 m of the registered rim plane (was drifting 30–60 m out before this batch).
- Element mix target (Falcon's Flight / Formula Rossa refs): airtime hills most common,
  turns second; inversions 2–4/lap (not yet real-life type-weighted — see REALISM.md's new
  "Occurrence rules" section for the census numbers and the deferred share scheduler).

## What this batch did (all UNCOMMITTED in the working tree at the time of this handoff)
A wave of realism/stability fixes (now on local `main`, commits `5b29ebd`..`0295049`, NOT yet
pushed to origin) plus a legacy-mode cleanup pass (this session, still uncommitted on top):

- **Hat crown latch/pin/bleed** (`coaster_track.cpp`): a 3-part fix for the mega-CLIMB→DROP
  crest handoff. `crownLatched` keeps the crest-lead descent target asserted every step
  through the apex (the old `genPrevDy>0` gate un-fired exactly at the vertex, causing a
  spurious 1-step re-climb the crest clip then flipped into a 267–326 m crest bust / 5-cp
  apex shelf). `crownY` PINS the post-crest DROP's hard ceiling (`crownY + margin`) so the
  residual +dy can't re-climb above the crest it fell off. `crownDrop` BLEEDS the post-crest
  DROP's effective speed (`fminf(genV, 54)`) so its crest budget opens up and the crown turns
  over instead of re-climbing. Net effect: crestY held <300 on every seed, no apex shelves.
- **Hills arrest trough allowance + chain demotion**: the terrain dive-arrest lookahead used
  to scan a full 14 steps (196 m) ahead for ANY rising ground and freeze whole hill-chain
  middles flat (dy≈0) even over locally-flat terrain. HILLS now scans a short 4-step corridor
  and floors the arrest gap at 12 m, so a bunny-hop's natural ballistic trough (~-6/step) is
  preserved. Bunny-hop CHAINS auto-DEMOTE to a single bigger hill (`hillH = frnd(46,62)`)
  when routed up rising ground (`riseF > 0.35*hillH`) instead of paying hillH + terrain rise
  per hop.
- **Jitter smoothing** (several independent fixes converging on "no per-cp hitching"):
  - `genFloorY` terrain-floor ratchet EASE: accel cap 1.8 → 0.9 m/cp² so the floor climbs
    rising terrain smoothly instead of in visible steps.
  - `M_TURN` adopted `M_FLAT`'s 7-sample forward-average ground target (`gtAvg`) in place of
    chasing the raw voxel height directly — killed a pitch/heading wobble the bare
    proportional gain was ringing through the 3-D relax passes.
  - `M_FLAT`'s ground-follow gain is now a CONTINUOUS proportional band (0 at `ferr=0` ramping
    to 0.40 by `|ferr|~4m`) replacing a hard 2 m dead-band that snapped dy between 0 and ~0.8
    at the edge (a micro-jitter of its own).
  - **CAP-VS-ARREST**: the post-hoc 2nd-difference vertical-g cap used to fight the terrain
    dive-arrest — when the arrest clamped dy UP to clear rising ground, the cap's delta
    swung hard negative and dragged the track back down into the exact dive the arrest just
    prevented. `diveArrestedUp` now forbids a negative g-cap delta the same step the arrest
    fired.
  - **STENGEL guard**: `eligibleElem` now requires ≥30 m of real corridor clearance before
    offering STENGEL — offered at ground level its dive collapsed to the clearance floor and
    became a climbing hump instead of a dive (measured: net +16 m "Stengels").
- **Roll carry-through** (`genGeomUp`/`genPrevUp` split, `bankHold`, `easeUpVec`): a banked
  element's exit lean is now HELD across a short FLAT/DROP/DIP gap (capped by `bankHoldMax`)
  so a re-banking next element meets it via a shortest-path slew instead of dipping through
  dead-level first. `genGeomUp` (the baseline, always-unwound track) still feeds the g-cap
  gate unchanged, so a carried lean can't spuriously disable that safety check on genuinely
  level geometry — only the RENDERED track (`genPrevUp`) carries the lean.
- **Cliff dive ≥1/lap + inversion budget/shares**: `invBudget = irnd(2,4)` re-rolled every
  lap; `cliffFizzles` re-arms the signature dive same-lap (bounded to 6) whenever the apex
  comes out too low or too tall for a sub-300 crest, guaranteeing ≥1 cliff dive/lap (census:
  24/24 laps, 8 seeds). A real-anchored TYPE-SHARE scheduler (targeting the real-life
  installed-base mix, ROLL~40/LOOP~30/IMMEL~10/DIVELOOP~10/STALL~10-boosted) was built,
  measured, found to destabilize the layout generator, and REVERTED/deferred — see
  REALISM.md's "Occurrence rules" section and COASTER_TODO.md for the open item and the
  lesson learned (fix the BROKEN seam/attractor classes first).
- **Dive-loop reworked to a genuine ~180° heading reversal**: climb + half-twist to inverted,
  then a half-loop DOWN whose pitch alone reverses heading, diving out low antiparallel to
  entry — replacing the old full-360° loop shape that only netted ~67°.
- **New `--audit` + removed legacy modes**: `--audit` (gates A–I, SVG profiles) is now the
  sole acceptance harness. `--simtest`, `--gaudit`, `--elemgtest`, `--cobratest`,
  `--divelooptest`, `--stationtest`, `--elemsust` and the `Track::forcedElem` hook are DELETED
  (dead code confirmed by grep — nothing else referenced `forcedElem`). The MC_DUMP_ELEM/
  MC_DUMP_SEEDS instrument was REHOMED into `--audit`'s static window pass (see the build/
  verify section above for the new invocation). Build verified byte-identical `--audit 8`
  output before/after the removal (the deleted `forcedElem` branches were provably dead in
  every surviving code path).

## Current verified state (checkpoint at the end of this batch)
- Build clean (no warnings), `--audit 8` runs to completion (exit code nonzero — gates B/C
  known-fail, see TODO), `--census 8` and `--rollingdump` both exit 0.
- Sampled crestY < 296 m on all 8 audit seeds; 0 CLIMB/DROP churn stubs.
- `--census 8`: `cliffMiss=0`, `invOutOfRange=0` across 24 laps (some `quotaMiss` WARNs on
  terrain-gated HELIX only — not a hard failure).
- BROKEN-geometry point count (the arc-collapse 2nd-difference metric, >16g vert/13g lat):
  **14**, last measured via the now-retired `--gaudit` in the integration pass immediately
  preceding this batch's legacy-mode removal. No current mode reproduces that exact scalar;
  `--audit` gates B/C/D/F are the surviving structural proxies (plus gate A's stall=0f and
  gate H's cliff-face bounds). Re-measuring BROKEN precisely would need a small ad hoc
  instrument in the same shape as the retired table — not rebuilt this batch (out of scope
  for a docs+cleanup pass).
- `stall=0f` on all 8 audit seeds (gate A).
- Signature cliff dive: `-88°` face, wall-hug within `≤8.5 m` of the registered rim (was
  30–60 m before this batch).
- Shadows: 2 of 3 reported symptoms FIXED this batch (see below); symptom 2 (white-pillar
  inversion) got a defensive mitigation only, not a verified root-cause fix.

## Shadow bugs (render_fx.cpp shaders + main.cpp ShadowSys) — 2 of 3 symptoms FIXED
All shadow code is in `render_fx.cpp` (SHADOW_FS string literal, the `shadowCascadeN`/`shadow`
GLSL functions) and the setup in `main.cpp` (`ShadowSys`/`computeLightVP`, `render_fx.cpp`
~lines 460-556; per-frame bind + shadow-anchor clamp in `main.cpp`). Three cascaded shadow
maps (`SHADOW_CASCADE_R = {32, 100, 256}` m half-extents), selected per-fragment by distance
from the shadow focus. `main.cpp` has a SECOND, single-map `struct ShadowSys` inside `#if 0`
(dead code) — the live system is the 3-cascade one in `render_fx.cpp`.

### Symptom 1 (PRIMARY, dark disc around the train) — FIXED
Root cause: cascade0 (nearest, 0.031 m/texel) resolved dense sub-metre voxel micro-relief
(grass/flower voxels) as PCSS occluders and smeared them into a uniform grey carpet over open
ground within its ~27 m band. **Fix shipped:** `CASCADE0_BIAS_MULT = 16.0` (`render_fx.cpp`
~line 183), multiplying cascade0's bias so only occluders taller than ~6 m cast in the near
cascade — matches what forcing the near band onto cascade1 did in the diagnostic capture, but
keeps cascade0's own resolution for real object shadows. Cascade1/2 are byte-identical to
before (unaffected far field).

### Symptom 2 — shadow color INVERTED to WHITE on pillars against a dark mountainside — NOT FIXED (defensive mitigation only)
Still not reproduced/verified against a live capture. A defensive change was made this batch:
the metal-reflection/`skyReflect` term is gated by `mix(0.35, 1.0, rawSh)` (`render_fx.cpp`
~line 433, "Gate the sky-reflection weight by the shadow factor") so a mis-shadowed metal
pillar's reflection term is at least dampened in full shadow rather than unconditionally
bright. This is a HARDENING, not a confirmed root-cause fix — the original hypothesis (a
`pcfTap`/`shadowCascadeN` out-of-bounds early-out returning 1.0 = fully lit, painting a pillar
past the cascade edge "whiter" than its correctly-shadowed backdrop) has NOT been re-verified
with a fresh screenshot capture this batch. Keep this open — see COASTER_TODO.md.

### Symptom 3 — shadows DISAPPEAR when the caster is higher up — FIXED
Root cause: the high-caster fade (`SHADOW_FADE_NEAR`/`SHADOW_FADE_FAR` + `worldZDiff` in each
`shadowCascadeN`) faded shadows to fully-lit too early. **Fix shipped:** pushed the thresholds
out from `{40, 110}` to `SHADOW_FADE_NEAR = 120.0, SHADOW_FADE_FAR = 400.0` (`render_fx.cpp`
~lines 171-172) — a train on a 100–200 m top-hat now keeps a visible (softened) ground shadow;
near-ground shadows (small `worldZDiff`) are unaffected as before.

## Known residual bugs / blocked work (see COASTER_TODO.md for detail)
- Top-hat 65° symmetric climb (still baseline ~46-52° on first hats, audit gate C known-fail)
  — blocked on the same Catmull-Rom crest-bulge / regen-cascade knife-edge as before.
- Type-share scheduler (real-life-weighted inversion mix) — reverted/deferred; the lesson
  learned (fix the BROKEN seam/attractor classes first) is now the lead item in TODO.
- Hills 45° flanks, general kink-flattening pass, STALL radius violation, SCURVE
  terrain-follow, LOOP top radius, DIVELOOP/HELIX rotation-vs-WR gate G bands, shadow symptom
  2 (white pillar) — all carried forward, see COASTER_TODO.md for current specifics.

## Commit & push
The 2026-07-08/09 batch (physics/stability fixes `5b29ebd`..`0295049` + the docs refresh /
legacy-mode removal commit on top) is committed to `main` and pushed to both `origin/main`
and `origin/claude/windows-rtx-ray-tracing-pkif4h` (user-authorized dual push — keep both in
sync on future pushes):
```
# from repo root, on branch main
git push origin main
git push origin main:claude/windows-rtx-ray-tracing-pkif4h
```
Remote: github.com/Banrs/Claude-Coaster. `minecoaster`, `minecoaster_orbit`,
`src/vk/minecoaster_vk`, `opengl/audit/`, and `opengl/minecoaster_*` are gitignored build
artifacts (don't commit them).

## Memory
Durable rules/gotchas are in the user's auto-memory (`coaster-build-and-verify.md`,
`coaster-queued-work.md`, `delegate-to-opus-sonnet.md`). Delegate mechanical/impl work to
sonnet/opus subagents to conserve the main model's usage.
