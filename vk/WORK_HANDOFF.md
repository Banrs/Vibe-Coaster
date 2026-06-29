# MINECOASTER Vulkan port — work handoff

Continuation brief for a new agent. The goal of this branch
(`claude/windows-rtx-ray-tracing-pkif4h`) is a **Vulkan renderer in `vk/` that has
feature parity with the raylib base game in `src/`** (terrain, biomes, trees,
coaster, HUD, physics) plus a modern PBR effect stack — and that the base-game
logic is **ported, not reinvented**.

## Build & verify (READ THIS FIRST — avoid the mistakes I made)
```
cd /home/user/Claude-Coaster/vk
cmake --build build -j                                # builds; EXIT 0 = ok
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json ./build/minecoaster_vk \
    --shot -o /tmp/x.ppm                              # headless render (lavapipe)
# optional flags: --ride <sec> (ride camera/telemetry), --cam x,y,z,yaw,pitch (frame a shot)
```
- The output is a **1280x720 PPM (~2.7 MB)**. **DO NOT** convert it to a full-size
  PNG and Read it — the image is too large and the Read gets **rejected by the API**
  ("media removed / request too large"), which wasted many turns. ALWAYS downscale
  hard first, e.g.:
  ```
  python3 -c "from PIL import Image; im=Image.open('/tmp/x.ppm'); im.thumbnail((360,360)); im.save('/tmp/x.png')"
  ```
  Keep thumbnails ≤ ~360 px. Even then some get rejected — prefer relying on the
  **headless stdout** (`[track] … [ride] … [vk] wrote …`) and small crops.
- `cd` does NOT persist between Bash calls here — put `cd vk && …` in every command.
- lavapipe is a software rasterizer: a `--shot` takes a few seconds; that's normal.

## Git
- Commit author must be `Claude <noreply@anthropic.com>` (a stop-hook checks this).
  `git config user.email noreply@anthropic.com && git config user.name Claude` is set.
- End commit messages with the Co-Authored-By + Claude-Session trailers (see history).
- Develop ONLY on `claude/windows-rtx-ray-tracing-pkif4h`. `git push -u origin <branch>`.
- Do NOT put the model id in commits/PRs.

## Architecture (vk/)
Deferred renderer in `src/main.cpp` (one big file). Per-frame passes in `Renderer::record`:
1. **shadow** (sun depth, PCF) → 2. **G-buffer** MRT (albedo+metal / world-normal+rough /
world-pos+flag, +depth); the **animated train** is CPU-transformed to the RideSim frame
and drawn here → 3. **SSAO** → 4. **deferred lighting** → HDR (PBR Cook-Torrance, sky+
volumetric clouds for background, contact shadows, foliage SSS, sky-probe IBL, god-ray
in-scatter, fog) → 5. **water** (forward, alpha-blended, depth-tested) → 6. **SSR**
(hdr→hdr2 ping-pong) → 7. **bloom** → 8. **post** (radial god-rays, auto-exposure, ACES,
gamma) → 9. **HUD** overlay → blit/copy.
- Shaders in `vk/shaders/` (compiled by CMake via glslangValidator; list is in
  `CMakeLists.txt` — add new shaders there).
- `Terrain.h`: ported `terrainH`/noise + `biomeAt` (base-game biome classification:
  bio/humid/temp+height → cap/side colours + treeType/treeDen) + `addTree`
  (oak/birch/spruce/acacia) + `buildTerrain`/`buildTrees`. Trees match biomes.
- `CoasterTrack.h`: drives the REAL `../../src/coaster_track.cpp` via `GameCompat.h`.
  `genLongTrack`, `buildTrackMesh`, `buildTrainMesh`, and the endless-coaster helpers
  `trackMaxU` / `extendTrack` / `trimBehind` (rolling window under the 512-cp cap).
- `Hud.h`: font atlas + `addText`/`addRect` + **`buildGameHud(GameHud)`** = exact
  base-game HUD layout (SCORE, speed card, element panel, boost meter).
- `Physics.h`: `world::RideSim` (ported train kinematics: `advance`, `frame`, `feltG`).
- `Water.h`: `buildWaterMesh` (grid at WATER_Y-0.28 to avoid shoreline z-fight).
- `Math.h`, `Props.h` (station/coins), `Track.h` (mesh helpers/addBox).

## Done (committed)
Deferred G-buffer · SSAO · contact shadows · per-material PBR (metallic steel rails
only) · analytic sky + volumetric clouds · god rays (radial + volumetric) · sky-probe
IBL · SSR · foliage SSS · HDR fp16 · bloom · ACES · auto-exposure (eye adaptation) ·
PCF shadows · **ported biomes + biome-matched trees** · **Minecraft-style sea level +
ocean** · **depth-based transparent water** (G-buffer bed depth) · ride camera +
telemetry · **animated train** · **endless terrain + coaster streaming** · **exact HUD**.

## Current state / what may be "broken"
- Build is **clean** and headless run does **not crash** (verified: `--ride 30` and
  `--ride 240` both render; coaster generates past the old 122 s wall, ~6 km out).
- The user said **"you broke it"** right after the water-depth change
  (`water.frag` now samples `gPosition` for true depth + alpha blending). I could NOT
  visually verify it because image previews kept being rejected. **First task: render a
  small thumbnail of a shoreline (`--cam -300,140,500,-1.6,-0.8`) and a normal view, and
  check for: water-depth gradient looking right, no new artifacts, water not too
  dark/odd.** If the water regressed, the suspect edits are in `vk/shaders/water.frag`
  (the `wdepth`/`dN`/`alpha` block) and the water descriptor wiring in `main.cpp`
  (`waterDSL`/`waterSet` now = UBO+shadow+gPosition).

## Outstanding user feedback (chronological, newest last)
1. Sky/clouds tuning — addressed (deeper blue, sparser clouds).
2. Water should use Minecraft sea-level logic — addressed (sea level 64 + ocean).
3. "No actual god rays" / "missing SSR" — addressed (radial shafts + SSR).
4. "Do what can be done" on the full PBR/GI list — most feasible items done; see below.
5. HUD must match the base game's OpenGL HUD — addressed (`buildGameHud`).
6. "Infinitely generating terrain and coaster" — addressed (rolling-window streaming).
7. Trees must match biome like Minecraft + **port over everything, don't remake** —
   addressed for terrain/biomes/trees/HUD/coaster (all now ported from `src/`).
8. Keep a subtle MC-style biome blend (less than the old over-blend) — addressed
   (light 5-tap cap-colour blend in `buildTerrain`).
9. "Water doesn't have a realistic depth feel — flat texture with fresnel" — the
   depth-based water change targets this; **needs visual confirmation** (see above).

## Suggested next steps (priority order)
1. **Verify the water-depth change visually** (small thumbnail). Fix if regressed.
2. **Anti-aliasing**: voxel edges shimmer/jag badly — this is probably the biggest
   remaining "realism" gap the user feels. TAA (task #6) or even a cheap FXAA in the
   post pass would help a lot. (No TAA yet.)
3. Remaining requested effects not yet done: **CSM** (#3, crisper shadows), full
   split-sum IBL (#8: prefiltered env + BRDF LUT; currently analytic sky probe),
   anisotropic, clearcoat, SSGI, refraction/caustics. Out of scope for flat voxels:
   normal mapping/POM (no UVs), VCT/SDF-GI/DDGI/probes.
4. **Async streaming**: the patch re-bake is synchronous (~visible hitch). Base game
   uses a tighter cell-budget trigger; consider threading the rebuild.
5. HUD `score`/`boost` are passed as 0 (RideSim doesn't model them) — wire real values
   if desired (e.g. coins for score).

## Task tracker
TaskList has #1-16. Done: 1,2,4,5,7,9,10,11,13. In-progress/partial: 8 (IBL).
Pending: 3 (CSM), 6 (TAA), 12 (on-foot/cam modes), 14 (render_fx port), 15 (pathtrace
→ Vulkan path tracer), 16 (IRenderer seam for the win-rtx DXR/DLSS backend).

## Verification camera presets (framing for thumbnails)
- Island/ocean overview: `--cam -380,200,470,-2.4,-0.7`
- Shoreline (water depth): `--cam -300,140,500,-1.6,-0.8`
- Ride POV + HUD: `--ride 12` (no --cam) ; external train: `--ride 0 --cam -8.5,115,-14.6,-2.356,-0.42`
- God rays toward sun: `--cam -431,135,360,-0.6,0.05`
(Focus prints at startup as `[vk] focus: …`; train pos as `[train] pos …`.)
