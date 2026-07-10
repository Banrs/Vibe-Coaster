# MINECOASTER

Voxel roller-coaster game: a raylib/OpenGL host, mid-rewrite. Style target: "arcadey but grounded
in real coaster engineering," Minecraft-style voxel world with a modern shader-quality look.

## Current direction

The **V2 route builder is live** (2026-07-10): the OpenGL host generates every ride from the
`opengl/src/track/` module — continuous primitives first, dense arc-length samples second, terrain
validation last. The old V1 generator has been retired to `opengl/legacy/` (kept for reference,
unbuilt). The **rendering/shader layer is the next rewrite target** — a separate, partial-to-full
pass to hit the "shader Minecraft" look; see `docs/REALISM_SCALE.md`'s "Core philosophy" section
and `opengl/COASTER_REWRITE.md` for status.

Read these before touching track geometry, sizing, or pacing:

1. [`docs/SHAPES.md`](docs/SHAPES.md) — cited geometry contract for track primitives.
2. [`docs/REALISM_SCALE.md`](docs/REALISM_SCALE.md) — how big/fast/long each element is, and the
   real-world research (with sourcing and confidence flags) behind every number.
3. [`opengl/COASTER_REWRITE.md`](opengl/COASTER_REWRITE.md) — V2 architecture, file boundaries,
   migration order, and acceptance checks.

Historical generator tuning notes and stale audit targets were deliberately removed. Git history
preserves them if needed; they are not valid requirements for V2.

## Repository layout

| Folder | Purpose |
|---|---|
| [`opengl/`](opengl/) | The playable raylib/OpenGL host. `opengl/src/track/` is the live V2 generator; `opengl/src/` is the host (game loop, rendering, world). |
| [`opengl/legacy/`](opengl/legacy/) | Retired V1 generator (`coaster_track.cpp`, `coaster_elements_ext.cpp`, `audit_diagnostics.cpp`), unbuilt, kept for reference — do not modify or re-include. |
| [`docs/`](docs/) | Design docs (`SHAPES.md`, `TERRAIN_CONTRACT.md`, `REALISM_SCALE.md`). |

The experimental Vulkan and Windows DXR renderer forks (each hard-depending on the V1
generator internals) were moved out of this repo to `../mythostest-forks/` on 2026-07-09
and quarantined there — do not resume either until the V2 rewrite lands and they're
ported to the new `Track` adapter. See `../mythostest-forks/README.md`.

## Build the OpenGL host

```sh
cmake -B opengl/build -S opengl
cmake --build opengl/build -j
```

The executable is `opengl/minecoaster`. On macOS, `opengl/build.sh` is also available.

## Rewrite boundary

Do not add another smoothing pass or a terrain-driven correction to V1. Build V2 beside it, keep
the renderer-facing track interface stable, and switch hosts only after the V2 continuity and
fixed-seed visual checks pass. The required split is specified in
[`opengl/COASTER_REWRITE.md`](opengl/COASTER_REWRITE.md).
