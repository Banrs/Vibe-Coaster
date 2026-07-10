# Render/host rewrite inventory — what is still V1, what is broken, what to rewrite

Produced 2026-07-10 from a 6-subsystem static audit (git provenance + deep code read; output
could not be viewed — no GL context in the dev environment, so "broken" claims below are ones a
static reader can PROVE from the code, quoted with file:line). This supersedes the optimistic
"renderer is already advanced" framing in `V2_NEXT_SESSION_PLAN.md` §2: the machinery is
present, but key parts were **gutted or left half-wired by a prior agent** — matching the user's
report that cascades, reflections, and shadow distance are broken.

**Ground truth: everything outside `opengl/src/track/` is V1 or V1-era.** The V2 rewrite so far
covered only the track generator. Git provenance per file:

| File | Lines | Commits | Lineage |
|---|---|---|---|
| `render_fx.cpp` | 1262 | 20 | V1-era, heavily churned by prior agents ("Flow round" 07-09) — the broken-shader zone |
| `pathtrace.cpp` | 1130 | 3 | V1-era second renderer, mechanically rewired for V2 only |
| `main.cpp` render regions | ~1500 of 2600 | — | terrain mesh V2-churned; track styling/camera/HUD V1-original |
| `voxel_render.cpp` | 593 | 1 | pure untouched V1 (only the mechanical split) |
| `spline.cpp` | 129 | 1 | pure untouched V1 — **~100 of 129 lines now dead** |
| `environment.cpp` / `game_state.cpp` | 163/113 | 2/3 | V1 + tiny V2 rehoming edits |
| `coaster_car.cpp` / `presentation.cpp` | 134/137 | 2/2 | V1 + V2 color/rehoming edits |

---

## 1. `render_fx.cpp` — the shader engine (REWRITE PRIORITY: CRITICAL, effort L)

User-reported breakage **confirmed with mechanisms**:

- **Reflections are gutted.** The shader declares `uniform sampler2D prevSceneColor; prevSceneDepth; mat4 prevVP` (:59) and **never samples them** — comments (:257-260) and `main.cpp:1799` reference an `ssrTrace()` **that does not exist anywhere**. Yet the host still computes `ssrThisFrameVP`, binds prev color/depth on texture units 20/21 **every frame** (`main.cpp:1542-1573`), and maintains a second full-res R16G16B16A16+depth ping-pong buffer (:1030-1031) purely to feed the nothing. All actual "reflections" (metal Fresnel + water) sample `skyReflect()` — a flat analytic sky gradient (:247-254). *A prior agent removed the SSR feature body and left all its plumbing and lying comments.*
- **Cascade0 is rendered but never used.** The depth loop renders all three cascades every frame (`main.cpp:1496`, cascade0 = 2048² + a full `drawWorld()`), and `cascadeSplit0` is bound (:1524) — but the shader's `shadow()` (:224-235) only calls `shadowCascade1/2`; **there is no `shadowCascade0`**. A whole shadow pass per frame is pure waste; the code's own comment (:173-182) admits it.
- **Shadow distance hardcoded ~256 m**: beyond `SHADOW_CASCADE_R[2]=256` from the shadow focus, fragments fall outside cascade2's ortho box and return unshadowed (:201, :447); `SHADOW_FADE_NEAR/FAR` (120/400 m) additionally fades tall casters to fully lit. Any elevated/wide shot loses distant shadows with no falloff cue.
- **Tonemap divergence trap**: the ACES curve is copy-pasted into 4 shader strings (:237, :760, :921, :311), exposure `*0.94` into 3, saturation into 2; the `legacyTonemap` dual path means the pathtrace-overlay and main HDR paths silently drift on any change.
- **`pale`/`sheen` heuristics** (:331-333, :386): fire on any bright low-saturation surface — snow/sand/pale stone get blue-shifted/desaturated 42% and a satin sky-sheen. The correct tile-identity mechanism (`metalUVRange`, tiles T_GOLD..T_RAIL) already exists and works; the heuristics should die.
- Sound parts (keep/reuse): the PCSS blocker-search + Poisson PCF math is correct and world-space-consistent; cascades 1-2 split logic is sound; sky Rayleigh/Mie is hand-tuned but fine; the HDR→ACES composite (bloom/SSAO/CA/vignette/grain) is coherent.

**Rewrite scope**: (1) reflections — either implement a real SSR march against the
already-maintained prev-frame buffers, or delete the entire remnant (buffers, binds, uniforms,
comments); do not leave it half-wired. (2) Make cascade0 real (near-field density) or delete its
render pass. (3) Rework the cascade ranges/fades for honest long-distance shadows (config, not
magic). (4) Single shared ACES/exposure/saturation; kill the inline `legacyTonemap` duplicates.
(5) Replace pale/sheen with tile-identity material response. Risk: HIGH — visual output,
verifiable only by a human launch; shared with the pathtrace overlay paths.

## 2. `main.cpp` render regions (REWRITE PRIORITY: HIGH, effort L)

- **BROKEN — tree wind is frozen**: sway is evaluated once on the worker thread and **baked into
  the static terrain mesh** (:1084-1092); it only "moves" when a chunk rebuilds. Fix: per-vertex
  sway weight animated in the vertex shader, or drop sway.
- **Data race**: the mesh worker reads `simTime` (and other `[&]`-captured floats) while the main
  loop mutates them (:874, :1084).
- **Perf**: the entire V2 dense-sample track (supports/ties/rails/spine/grate) is drawn
  **immediate-mode one cube at a time**, across 3 cascade depth passes + main (:1290-1453). Batch
  or bake it like terrain.
- **V1 art everywhere**: flat single-color untextured track structure (:1330, :1402, :1419), rails
  as two plain boxes, V1 biome coloring with hardcoded height thresholds (:944-963), V1 flat-2D
  HUD (:2059-2209 — lateral g not labeled), V1 camera modes with big dormant shot-harness blocks
  in the hot path (:672-759).

## 3. `pathtrace.cpp` — the second renderer (decision needed; effort S once decided)

GPU voxel DDA tracer (live KEY_T + `--shot`/`--rttest`), internally coherent but: stale V1
`struct Track` forward-decl (:54, dead), debug `printf` in shipping init (:609), copy-paste-drifted
sky/cloud/tonemap constants vs both its own two variants and `render_fx` (captures don't match
play), double-representation composite (raster world redrawn over the traced frame), hard 176×176×168
view window. **Recommendation: demote to shot-only or delete the live half; if kept, unify look
constants with `render_fx` in one shared GLSL string.** Not the product renderer.

## 4. `voxel_render.cpp` — pure V1, works (priority LOW, optional M)

Not broken, not the shader problem. Optional modernization: delete the dead 168-line `#if 0`
block (old single-cascade shadow/sky), greedy meshing (currently one quad per cell), texture
array + mipmaps (currently point-filtered strip that shimmers at distance), `unsigned int`
indices (latent 16-bit overflow on steep buckets), real neighbor-AO instead of top/bottom
darkening.

## 5. `environment.cpp` + `game_state.cpp` — V1, fine today (priority LOW, S)

The elaborate fog-from-sky derivation collapses to a constant (sun is fixed; a reverse-solved
`CAL` vector reproduces the old hand-picked fog exactly) — all the atmosphere math is effectively
dead until a day/night cycle exists, and the `CAL` fudge becomes wrong the instant the sun moves.
SKY_* constants are hand-synced with the shader (no shared header). FOG globals are non-atomic
and read by the mesh worker — safe only while the sun never moves. Rewrite only when adding
day/night: sample fog from the sky model across elevations, atomically publish sun+fog, share
constants with the shader.

## 6. `spline.cpp`, `coaster_car.cpp`, `presentation.cpp` (cleanup S + polish M)

- **`spline.cpp` is ~78% dead**: `trackSpline/catmull/quinticC2/monotoneHermiteY/easeUpVec/vlerp`
  have **zero live callers** now that V1 is archived — only `orthoUp/pushFrame/popFrame` (:1-27)
  are used. Delete the dead math; rename to a frame-helper file.
- **Dead coin sound**: `makeCoinSound` is created and unloaded but `PlaySound(sndCoin)` appears
  nowhere; there is no coin pickup system despite the HUD coin score.
- Car/station are coherent V1 magic-number voxel art (static passengers, no wheel animation);
  audio is shallow V1 (wind/rumble/clack/whoosh only — no brake hiss, station ambience, or
  per-element cues). Polish targets, gated on the shader rewrite landing first.

---

## Suggested execution order (next session)

1. **`render_fx.cpp` rewrite** (the user's ask): SSR decision + cascade0 + shadow distance +
   tonemap unification + material identity. Fable-led design; verify by human launch checkpoints.
2. **main.cpp render fixes**: frozen wind (real bug), the data race, track-draw batching — then
   track material styling.
3. **Cleanups** (delegable): spline.cpp dead math, voxel `#if 0`, pathtrace stale decl/printf,
   dead coin sound, stale comments.
4. **pathtrace decision** (demote/unify), then voxel modernization / biome art / HUD / audio as
   polish phases per `V2_NEXT_SESSION_PLAN.md`.

Human visual checkpoints remain mandatory between shader milestones — this environment cannot
render; every shader change is otherwise verified only by reading.
