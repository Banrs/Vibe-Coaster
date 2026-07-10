# Prompt: finish MINECOASTER V2 — render/host rewrite (copy-paste for a fresh session)

Continue the MINECOASTER V2 rewrite in `/Users/danielho/Documents/Coding/VSC/mythostest`
(GitHub: `Banrs/Vibe-Coaster`, branch `claude/minecoaster-v2-rewrite-5f7f00` — work on this
branch; it is pushed to origin). This is a fresh context with no memory of prior sessions —
everything you need is in the repo. Read in this order before writing any code:

1. `README.md` — repo layout and status.
2. `docs/V2_NEXT_SESSION_PLAN.md` — overall status: the V2 **track generator rewrite is DONE**
   (migration steps 1–7; the live game runs only `opengl/src/track/`), with loose ends listed.
3. `docs/RENDER_REWRITE_INVENTORY.md` — **the authoritative spec for THIS session.** A six-
   subsystem audit with file:line evidence of what is still V1, what a prior agent broke
   (reflections gutted-but-bound, cascade0 rendered-but-never-sampled, shadow distance hardcoded
   ~256 m, frozen tree wind, tonemap duplicated 4×, pale/sheen color heuristics), and what is
   sound and worth keeping (PCSS math, cascade 1–2 split logic, sky scattering, HDR composite
   structure).
4. `opengl/COASTER_REWRITE.md` — how the track rewrite was run: docs-as-law, a new module built
   ALONGSIDE the old, primitives one at a time, an honest acceptance harness, a migration
   sequence, switch at the end, old code archived. **This session applies the same method to the
   render layer.** Also read its "Process rule: no patching" section — it is binding.
5. `docs/REALISM_SCALE.md` "Core philosophy" — the look target: **"shader Minecraft"** — voxel
   world with a modern shader-quality look (dynamic lighting, atmospheric fog/sky, PBR-ish
   materials), arcadey but grounded.

## Where things stand

- **Track generation (V2) is complete and frozen-green.** `opengl/src/track/` — do not modify it
  except for the named loose ends below; any change there must keep
  `./opengl/build/v2track_tests` at PASS, 0 failures.
- **V1 is archived in `opengl/legacy/`** (generator + old diagnostics, byte-identical,
  unbuilt). Do not modify, re-include, or consult it as a reference — same quarantine rule the
  track rewrite used.
- **The render/host layer is the remaining V1-era code** — `render_fx.cpp` (churned/broken),
  `pathtrace.cpp` (drifting second renderer), the render regions of `main.cpp` (terrain/track
  drawing, cameras, HUD), `voxel_render.cpp`, `spline.cpp` (~78% dead), `environment.cpp`,
  `coaster_car.cpp`, `presentation.cpp`. The inventory doc classifies each with evidence.
- Build: `cmake -B opengl/build -S opengl && cmake --build opengl/build -j`. Verify stack:
  `./opengl/build/v2track_tests` (geometry harness, must stay 270/0) and
  `./opengl/minecoaster --v2audit 8` (headless ride audit).
- **This dev environment cannot open a GL context** (`InitWindow` segfaults — environmental, no
  WindowServer session; affects every shell/agent variant). You cannot render a frame yourself.
  Verification of visuals works like this: ask the user to launch `./opengl/minecoaster`
  (interactive) or `./opengl/minecoaster --shot` (fixed seed 1337; writes `shot1-4.png` at
  frames 200/500/900/1200 into the working directory) — **then Read the PNGs yourself as
  images** and assess them with your own vision. Budget a human-launch checkpoint at the end of
  every migration step below; never claim a visual milestone verified without pixels.

## Hard rules (do not relitigate)

- **This is a rewrite, not a patch series.** Fix by rebuilding the affected unit (a whole shader,
  a whole pass, a whole draw loop) and rechecking its call sites — never bolt a guard or a
  special case onto churned code. V1 died of patch-on-patch; the broken shader layer died of it
  a second time. When a defect is found in something you wrote, rewrite that unit too.
- **Build the new render module ALONGSIDE the old one** (mirror the track approach): create
  `opengl/src/render/` with its own files, keep `render_fx.cpp` compiling and in the call path
  until the new module passes its visual checkpoints, then switch the host and archive
  `render_fx.cpp` (and whatever else is replaced) to `opengl/legacy/` — **archive, never
  delete** (standing user decision).
- **One source of truth for shared shader constants.** The audit found ACES copy-pasted into 4
  shader strings, exposure into 3, sky constants hand-synced between `environment.cpp` and the
  shader. The new module must define tonemap/exposure/sky/fog constants once (a shared GLSL
  fragment or generated header) and everything — including any surviving pathtrace path —
  consumes it.
- **No half-wired features.** Either a feature is fully implemented and sampled, or its plumbing
  does not exist. (The gutted SSR — buffers maintained and bound every frame for a shader that
  never reads them — is the canonical violation.)
- **Materials by identity, not heuristics.** Tile identity (`metalUVRange`, atlas tiles) decides
  material response; delete brightness/saturation guesses (`pale`/`sheen`) that recolor snow and
  stone.
- **Honest gates.** Never loosen `v2track_tests`, `--v2audit`, or any check to make something
  pass. Strengthen, don't relax.
- **Ask before locking in look decisions.** Visual-taste choices only the user can make — the
  reflection approach (real SSR vs polished sky-fallback), day/night vs curated fixed sun, the
  pathtrace renderer's fate (demote to shot-only / unify / remove), any big palette shift —
  surface options (with screenshots once available) and ask. Same rule the track rewrite used
  for element sizes.
- **Delegation:** the user runs low on Fable-only usage. Fable (you) does the architecture,
  shader design, and anything sign-sensitive; delegate mechanical/self-contained work (dead-code
  sweeps, doc updates, well-specified refactors, research) to opus (judgment) or sonnet
  (mechanical) subagents. Workflows: ~7 agents is right, ≤10 unless truly necessary.
- **Commit at verified milestones** (message style: imperative summary + why-body, ending with
  the `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer). **Push to origin after
  each verified milestone.**

## Migration sequence (work through it; don't stop between steps except at human visual
checkpoints and ask-before-locking-in moments)

0. **Track loose ends first** (small, unblocks physics-visual consistency — details in
   `V2_NEXT_SESSION_PLAN.md` §3): calibrate the host physics loss term (`ride_constants.h`
   `DRAG/FRICTION`, integration in `main.cpp`) to the planner's researched two-term model
   (`track_planner.cpp` — μ=0.008 rolling + cAero=1e-4); reduce the ~42% unsupported spans by
   lowering `gradeTurnToTerrain`'s clearance toward small cuts until `--v2audit 8` is 8/8; the
   top-hat lift-assist cosmetic (`chain=true` on the powered face, or ask the user).
1. **Render module skeleton** — `opengl/src/render/` (own translation units like `track/`, not
   unity-included): shader library layout, ONE shared GLSL constants fragment
   (tonemap/exposure/sky/fog), a `RenderV2`-style interface the host will consume, compiled into
   both targets but out of the call path. Gate: clean build, harness untouched.
2. **Lighting + shadow core rewrite** — the user's headline complaint. Design the cascade scheme
   from first principles (how many cascades, principled log/uniform split, per-cascade texel-
   snapped projections, a real near cascade — the old one rendered cascade0 every frame and
   never sampled it), **configurable shadow distance** (no magic 256 m; distant shadows fade,
   not vanish), keep/re-derive the PCSS blocker-search+penumbra (the old math was sound). Gate:
   human screenshot checkpoint (`--shot` + play) reviewed by you reading the PNGs; frame-time
   sanity via `--bench`.
3. **Materials + water** — identity-based material response (metal/gold/rail via tile range,
   Ward anisotropic rails kept), water re-based on the shared constants, biome surfaces stop
   being recolored by heuristics. Gate: screenshot checkpoint.
4. **Reflections** — ask the user first (SSR vs polished analytic fallback), then implement the
   choice COMPLETELY: either a real screen-space trace using prev-frame color/depth (plumbing
   for it already exists host-side) with a sky fallback, or delete every trace of the SSR
   remnant (second HDR ping-pong buffer, binds, uniforms, comments). Gate: screenshot checkpoint.
5. **Sky/atmosphere + fog unification** — sky scattering re-based on shared constants; fog
   SAMPLED from the sky model (the current fog is a constant reverse-fudged for one fixed sun);
   if the user wants day/night (ask), make sun+fog a per-frame atomic snapshot (the terrain
   worker reads FOG concurrently — `game_state.cpp` names the hazard). Gate: screenshots at
   several sun angles if day/night, else one.
6. **Post stack + single tonemap path** — bloom/SSAO/CA/vignette/grain on the shared ACES;
   eliminate the `legacyTonemap` dual path. **Pathtrace decision** (ask the user): demote to
   shot-only, unify its look constants, or archive it — then do it fully.
7. **Host draw rewrite** (`main.cpp` render regions): fix the two real bugs (frozen tree wind —
   move sway to a GPU vertex animation or drop it; the `simTime` worker-thread race), batch or
   bake the immediate-mode track drawing (currently one cube at a time across 4 passes), then
   track/support material styling and biome art to the new module's standards. Gate: screenshot
   checkpoint + `--bench` frame times.
8. **Switch + archive** — host consumes only the new render module; move `render_fx.cpp` (and
   anything else fully replaced, e.g. the dead ~100 lines of `spline.cpp`, the `#if 0` block
   origin) to `opengl/legacy/` with its README updated. Final full verification: build, harness
   270/0, `--v2audit`, human plays the game, you review final screenshots. Push.
9. **Polish backlog** (only after 8, as capacity allows — see `V2_NEXT_SESSION_PLAN.md` Phases
   E/F): train/station art, audio depth (dead coin sound: wire it or remove it), menu/settings,
   CI (GitHub Actions: build + harness + `--v2audit` on push).

**Resuming mid-sequence:** check what exists under `opengl/src/render/` and what
`main.cpp` includes/calls — that tells you which step you are on. Read the git log for this
branch; every prior milestone is a documented commit. Do not assume step 0/1 just because this
prompt is being reused — verify against the actual repo state first.

**Cleanups safe to delegate immediately, any time** (all evidenced in the inventory doc): the
dead `#if 0` block `voxel_render.cpp:1-168`; the stale V1 `struct Track` forward-decl
`pathtrace.cpp:54`; the shipping-path debug `printf` `pathtrace.cpp:609`; dead `spline.cpp` math
(keep `orthoUp/pushFrame/popFrame` — three TUs use them); the never-played coin sound; stale
comments (`main.cpp` ~2088/2091, `presentation.cpp:100`); dead non-const `ride_constants.h`
knobs. Each removal is a unit rewrite of its file region, verified by a clean build.
