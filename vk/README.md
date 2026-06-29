# MINECOASTER — Vulkan renderer

A from-scratch **Vulkan** rewrite of the MINECOASTER renderer, replacing the
raylib/OpenGL immediate-mode path. Cross-platform by design (Windows + Linux
natively, macOS via **MoltenVK**), and structured so the DXR/RTX path tracer from
the Windows RTX work (`../win-rtx`) can drop in as a second backend on Windows.

Two motivations:
1. **Correctness** — the world is uploaded as real GPU meshes, so the raylib
   immediate-mode batch-overflow that made terrain render half / striped / empty
   simply cannot happen here.
2. **Performance** — one indexed draw for the world instead of ~hundreds of
   thousands of per-cube `rlBegin/rlEnd` calls.

## Status

This is the **first increment** of a one-shot rewrite, and it already builds and
renders **headlessly** (verified on Mesa **lavapipe** software Vulkan in CI-less
sandboxes — no GPU required):

- ✅ Vulkan 1.1 core: instance / device / queue, offscreen color+depth targets,
  render pass, graphics pipeline, host-visible mesh upload, fenced submit,
  image→buffer readback to PPM.
- ✅ Renderer-agnostic world gen ported from the base game (`src/Terrain.h`:
  `terrainH`, biome palette, water) → a single indexed triangle mesh with
  per-vertex normals + colors.
- ✅ Sun + hemispherical ambient + distance fog + ACES in `shaders/mesh.frag`.
- ⏳ Next: SDL2 window + swapchain + fly camera/input; the coaster track + train
  meshes; physics (already renderer-agnostic in the base game); water shading and
  sky; then the path tracer (Vulkan compute / `VK_KHR_ray_tracing_pipeline`).
- ⏳ `IRenderer` seam so `../win-rtx` (D3D12/DXR + DLSS) is the Windows RTX backend.

## Build

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Requires the Vulkan SDK/loader and `glslangValidator` (Ubuntu: `libvulkan-dev`,
`glslang-tools`). Shaders are compiled to SPIR-V at build time into `build/shaders/`.

## Run (headless / offscreen)

The current core renders one frame to a PPM — no window needed:

```sh
# software Vulkan (no GPU): point the loader at lavapipe
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
  ./build/minecoaster_vk --shaders build/shaders -o frame.ppm
```

On a real GPU, drop `VK_ICD_FILENAMES`. A windowed SDL2 path is the next step.

## Layout

```
vk/
├─ CMakeLists.txt        Vulkan + glslang build
├─ src/
│  ├─ Math.h             minimal column-major vec/mat (Vulkan clip space)
│  ├─ Terrain.h          ported terrainH / biome / water -> Mesh
│  └─ main.cpp           offscreen Vulkan renderer
└─ shaders/
   ├─ mesh.vert          world mesh vertex stage
   └─ mesh.frag          sun + ambient + fog + ACES
```
