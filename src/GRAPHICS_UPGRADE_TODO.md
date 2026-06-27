# Graphics Upgrade — Feasibility & TODO

Goal: richer, "lush" Minecraft-style textures and a more modern look, without
breaking the dual renderer (raster voxel batch + live voxel path tracer) or the
licensing posture (this is a fan project — **no Mojang/Minecraft assets**).

## Where textures live today
- `makeAtlas()` (main.cpp): a procedural **16×16 greyscale** atlas of 8 tiles
  (`T_WHITE, T_GRAIN, T_GRASS, T_PLANK, T_LOG, T_LEAF, T_GOLD, T_IRON`). Each tile
  is a luminance pattern; the *colour* comes from the per-cube `rlColor4ub` tint.
  Point-filtered, so it reads crisp/pixel-art.
- The **raster** path (terrain, trees, station, coaster) samples this atlas.
- The **path tracer** (pathtrace.cpp) does **NOT** texture: each baked voxel stores
  one flat linear albedo (`putMat`). So texture detail only appears in the raster
  composite, never in the path-traced terrain. This is the single biggest
  constraint on any texture upgrade.

## Options (cheapest → richest)

### 1. Richer procedural atlas  ·  ~½ day  ·  low risk  ·  RECOMMENDED FIRST
Keep the greyscale-tile + vertex-tint model, but make the tiles lusher:
- Bump tile resolution 16→32 px for finer grain (atlas stays tiny).
- Bake subtle *hue* variation into a few tiles (grass blade flecks, mossy stone,
  plank knots) instead of pure luminance, and lean less on the flat per-cube tint.
- Add 2–3 grass/leaf variants chosen by hash so foliage doesn't tile visibly.
- No external assets, no licensing exposure, works in raster immediately.

### 2. Real CC0 "faithful/lush" texture pack  ·  ~1–2 days  ·  licensing care
Load a PNG atlas at startup instead of the procedural one. **Must be CC0 / public
domain** (e.g. a permissively-licensed pack) and remixed enough to be clearly not
Mojang art. Steps:
- Add `LoadTexture` of a packed atlas; map our 8 tile slots to its tiles.
- Drop the per-cube greyscale assumption where the pack already has colour
  (tint → white) so we don't double-darken.
- Risk: per-face UVs assume one tile per material; packs with top/side/bottom
  variants (grass) need a small per-face tile index (see option 4).

### 3. Per-face tile selection (grass top vs dirt side)  ·  ~1 day
`emitCubeTex` currently uses one tile for all 6 faces. Give it `topTile`,
`sideTile`, `botTile` so grass blocks get a green top + dirt sides like real MC.
Cheap, big readability win, pairs well with options 1–2.

### 4. Textured path-traced terrain  ·  ~3–5 days  ·  medium/high risk
Make the voxel trace sample the atlas so the *ray-traced* world is textured too.
- Store a tile id (+ face) per voxel, or procedurally derive UVs from the hit
  voxel + normal in `shadeHit`/the trace, then sample the atlas.
- Heaviest change; touches the hot trace loop (perf) and the bake format.
- Only worth it after 1–3 land, since most of the frame is path-traced terrain.

### 5. Normal/spec maps, PBR-ish surfaces  ·  ~1 week  ·  high risk
Per-tile normal + roughness for the raster shadow shader and the tracer. Biggest
visual jump (depth, wet rails, glinting gold) but the largest surface area and
the easiest to destabilise. Defer.

## Recommended path
1. **Option 1** (richer procedural atlas) — immediate lushness, zero risk.
2. **Option 3** (per-face tiles) — proper grass/dirt/log blocks.
3. Evaluate **Option 2** only if a clean CC0 pack is sourced + remixed.
4. **Option 4** later, gated on a perf budget review of the trace loop.

## Open questions for the user
- Target art direction: "vanilla MC", "faithful 32×/64×", or a softer stylised
  look (closer to the current vibrant palette)?
- Is a small bundled external texture file acceptable, or keep everything
  procedural (no asset files, simplest licensing)?
- How much of the budget should go to making the *path-traced* terrain textured
  (option 4) vs. just the raster look?
