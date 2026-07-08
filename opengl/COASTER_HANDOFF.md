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
- **HARD GATE:** `./minecoaster --simtest` must print `stall=0f` for all 8 seeds. It also
  prints per-seed `crestY / bottomY / dropH`.
- `./minecoaster --gaudit 8` → prints `BROKEN-geometry points ... N total` (per-cp
  2nd-difference arc-collapse metric). Keep N ≤ ~4. NOTE: this metric is oversensitive vs
  the HUD 6 Hz lowpass — a few points ≥16 g on inversion seams are felt as acceptable;
  don't over-chase it, but a helix/loop at 20–77 g climbing terrain is a real bust.
- `MC_DUMP_ELEM=<NAME> ./minecoaster --gaudit 3` → dumps `[dump] seedN cpK kind=NAME
  pos=(x,y,z) heading=H` for seeds 1–3 (runs split by `--- run end ---`). Parse with
  python3; pitch between cps = `atan2(dy, horizontal_dist)` deg. NAMES incl. CLIMB, DROP,
  HILLS, HELIX, LOOP, TURN, DIP, CLIFFDIVE, etc.
- **Gotcha:** the fixed `--gaudit`/`--simtest` windows are 470 cps and never roll, so they
  structurally can't reach the ⅔-lap signature CLIFFDIVE. A rolling-window scratch binary
  (mimics game popFront+regen) was used to measure the dive — rebuild it fresh from current
  src under the session scratchpad if needed.
- **Gotcha:** in the simtest line, `drop[min/mean/max]` is SPEED in km/h (×3.6), NOT height.
  The only height metric is `dropH` (= crestY − bottomY).

## Design rules (user spec, final as of 2026-07-08)
- Element heights **1.25–1.75× real world-record** (small elems near 1.75×, biggest taper
  to 1.25×; never below 1.25×).
- Radii: size-multiplier "plus a bit", HARD cap **2.0× WR radius (smaller elems) / 1.5× WR
  (larger elems)**. Do NOT balloon radii by v²/entry-speed scaling. **User ACCEPTS high g**
  from tight radii — never soften geometry / g-cap to hide it; stability (no stalls/NaN/
  exploding geometry) still matters.
- Entry speeds 1.5–2.2× real; sustained g ≥1.75× real per element; peak g ≤4× real.
- **Top hat (normal launch hat):** CREST height (absolute crestY) **< 300 m HARD** (the cap
  is on the crest, NOT the drop). DROP height **200–270 m** (target band ~225–270) WITH
  VARIETY driven by entry speed / sustained g (faster entry → taller hat/deeper drop; do NOT
  clamp all to one band). Include HEIGHT-GROUP VARIETY: not every hat is a mega — mid tier
  ~120–200 m crest too, so a ride shows a spread of drop sizes.
- **Top-hat angles:** climb AND drop both ~65° (±) SUSTAINED (not single-segment spikes) —
  BUT a smooth clothoid/parabolic CROWN over the apex takes priority over hitting a strict
  65°; NO flat shelves on top (see regression note below).
- **Signature cliff dive** is the ONLY near-90° (85+°) element. Fires ~⅔-lap, once/lap, off
  a real rim. Crest < 300, total drop ~250–275 (≥150 floor), 85° face over ≥60 m.
- Element mix target (Falcon's Flight / Formula Rossa refs): airtime hills most common,
  turns second; inversions ~6–8/ride (user-tuned, intentional beyond the 0-inversion refs).

## What this session did (all UNCOMMITTED in the working tree)
Full realism audit (all elements) + a batch of fixes. Verified-good at last checkpoint:
- **Signature cliff dive** reworked: new closed-form `M_CLIFFDIVE` scripted mode +
  synthetic track-registered rim terrain (`registerMesa` before `terrainH` in main.cpp).
  85° face, fires every lap off a real rim, crest sits on the rim, drop capped.
- **BOOST +40 g explosion FIXED** (was a real bug, not inherent): every g-budget used
  coasting speed but a boost thrusts to ~86 m/s cruise; on mountain sites the budgets
  opened wide while the ride hit seams at cruise. 3-part fix + a general terrain-lift guard
  extended to HELIX/SCURVE/TURN/DIVE (ends a banked element before the clearance floor
  ratchets its coil up a steep wall). Cleared the latent "element climbing a mountain at
  20–77 g" class. broken 191→4.
- **crest < 300** enforced; **dropH variety** + mid/mega height tiers shipped.
- Loop/Immelmann geometry confirmed good in audit.

## Geometry agent — FINISHED (final state below)
Tree is green: build clean, `simtest stall=0f ×8`, crestY 144–293 (all <300), dropH 98–261
(varied), gaudit broken=4.
- **HELIX exit ease-out: DONE** (`coaster_track.cpp:1683-1691`) — helix now holds turn-rate
  to its final cp, C1 handoff, no seam kink.
- **Top-hat CROWN REGRESSION: RESOLVED by revert** — the two-flat crown was from an
  experimental symmetric-65 build; fully reverted. Crown is now a verified single-vertex
  smooth parabola (apex dy steps continuous, no shelf). Climb face ~60°, drop face −65 to
  −68° (asymmetric but smooth crown, per "smooth crown wins").
- **NOT done, fully documented in COASTER_TODO.md** (no half-applied edits left): top-hat
  65° symmetric (TASK 1, blocked on the Catmull crest-bulge knife-edge), hills 45° (TASK 2),
  terrain-follow softening (ISSUE B), roll-to-roll transition (TASK 4), kink-flatten pass
  (TASK 5). Each has mechanism + exact file/function + proposed approach.

## Shadow bugs (render_fx.cpp shaders + main.cpp ShadowSys) — 3 symptoms, NOT yet fixed
The shadow agent could not verify via screenshot (GUI capture failing) and was told to
diagnose by code reasoning / revert to a clean build. **Rebuild + check `git diff` on
render_fx.cpp/main.cpp and COASTER_TODO.md for its result before committing** — if mid-edit,
verify or revert its render changes first. Three user-reported symptoms to fix (all in the
3-cascade shadow system):
1. **Near-train dark patch** — fine outside a ~10–15 m sphere around the train, but a wrong
   dark blob WITHIN it. Maps to cascade0 (nearest cascade); suspect depth bias too small
   (near-field acne/over-darken), a spurious PCSS blocker at the focus, or the train's own
   mesh self-shadowing the ground with bad bias.
2. **Inverted (WHITE) shadow on pillars** — track-support pillar shadows render WHITE
   (inverted) when cast against the DARK side of a mountain. Suspect a sign/contrast issue
   in the shadow term where it composites over already-in-shade (low-lit) receivers — the
   shadow factor is brightening instead of darkening there.
3. **Shadows disappear when caster is higher** — they vanish too early with caster height;
   should persist much longer (fade out far later, retain high-caster shadows). This is the
   `SHADOW_FADE_NEAR`/`SHADOW_FADE_FAR` + `worldZDiff` fade in render_fx.cpp (~line 171):
   push `SHADOW_FADE_FAR` way out (currently 110) so tall casters keep casting.

## Known residual bugs / blocked work (see COASTER_TODO.md for detail)
- **Top-hat 65° climb** blocked on a Catmull-Rom crest-bulge vs downstream-regen-cascade
  knife-edge; proposed fix = a crest-bulge compensator (cap crest cp at `300 −
  predictedBulge`). Left at baseline ~60.5° face otherwise.
- **Fast-DIP-into-rising-ground**: a dip at 86 m/s bottoms below a terrain rise (−66 g,
  ~3 of the 4 broken pts). Proposed: a DIP-specific dive-arrest (mirror the DROP one).
- **Hills 45° flanks**: needs a deeper smoothing-pipeline change (clothoid flank + rounded
  crest), not just wavelength/amplitude knobs — those reintroduce shelves/crest busts.
- Audit also flagged (NOT yet addressed): DIVELOOP only ~67° heading vs real ~180°; HELIX
  ~445° vs real ~585° (duration-capped); STALL radius 306 m (7.6× real, v² balloon — the
  one radius that violates the "no balloon" rule); SCURVE vertical terrain-follow; LOOP top
  radius marginally over 1.5×; ROLL effectively dead (entry window 54 m/s vs ~78 m/s cruise
  — raise invVMax to ~59–62 to make it spawn).

## Commit & push (user AUTHORIZED both; do AFTER verifying the tree is green)
User explicitly approved pushing to **main AND** the handoff branch. Do NOT commit a
broken/mid-edit tree — first confirm build clean + `simtest stall=0f ×8` + gaudit broken
≤~4 + top-hat crown is smooth (no flat shelves).
```
# from repo root, on branch main
git add -A
git commit -m "Coaster realism: cliff dive, BOOST fix, top-hat sizing/variety, terrain+shadow polish"   # end with the Co-Authored-By line
git push origin main
git push origin main:claude/windows-rtx-ray-tracing-pkif4h
```
Remote: github.com/Banrs/Claude-Coaster. `minecoaster`, `minecoaster_orbit`,
`src/vk/minecoaster_vk`, and `opengl/minecoaster_*` are gitignored build artifacts (don't
commit them).

## Memory
Durable rules/gotchas are in the user's auto-memory (`coaster-build-and-verify.md`,
`coaster-queued-work.md`, `delegate-to-opus-sonnet.md`). Delegate mechanical/impl work to
sonnet/opus subagents to conserve the main model's usage.
