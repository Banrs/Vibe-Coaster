# MINECOASTER

A voxel roller-coaster simulator. An endless, procedurally generated coaster threads
through a streaming Minecraft-style world — launches, drops, loops, cobras, helices and
inversions, all sized by a physics-driven generator that holds the felt-g inside a
realistic-but-arcadey envelope. Cross-platform, built on [raylib](https://www.raylib.com).

## Features

- **Procedural endless track** — a rolling-deque generator builds the circuit ahead of
  the train and drops it behind, so the ride never ends and never repeats.
- **Physics-driven sizing** — elements are sized from the entry speed so felt-g stays in
  a +10 / −6 g envelope (Earth-real gravity); speed dictates size, not brakes.
- **Streaming voxel terrain** — biome-varied landscape (plains, forest, savanna, desert,
  taiga, tundra) with trees, water and a day-lit sky, meshed in a ring around the train.
- **Real ride physics** — gravity, drag, friction, LSM/hydraulic launches and boosters,
  with a live HUD (speed, altitude, element, g-meter).

## Build

Requires CMake and a C++17 compiler. raylib is fetched and built automatically.

```sh
cmake -B build
cmake --build build -j
```

This produces `./minecoaster`. On macOS you can also just run `./build.sh`, or
double-click `MINECOASTER.command`.

## Windows RTX renderer (DXR + DLSS 4.5)

An alternative **hardware ray-tracing** renderer for Windows + NVIDIA RTX lives in
[`win-rtx/`](win-rtx/). It bakes the same voxel world, builds a DXR acceleration
structure from the 8³ macro-bricks, path-traces it on RT cores, and denoises +
upscales with **DLSS 4.5** (Super Resolution + Ray Reconstruction) via NVIDIA
Streamline — mirroring the look of the software tracer in `src/pathtrace.cpp`.
See [`win-rtx/README.md`](win-rtx/README.md) and
[`win-rtx/ARCHITECTURE.md`](win-rtx/ARCHITECTURE.md). (Windows + RTX only; the
cross-platform build above is unchanged.)

## Run

```sh
./minecoaster
```

| Key       | Action                          |
|-----------|---------------------------------|
| SPACE     | launch / boost on powered track |
| S         | trim brake                      |
| C         | cycle camera (1st / chase / side)|
| F         | free-look                       |
| E         | exit (at station)               |
| P         | pause                           |
| WASD Q E  | free-fly the camera             |

## Headless tools

```sh
./minecoaster --simtest     # ride 8 seeds, report avg speed / inversions / stalls
./minecoaster --gaudit      # audit per-element felt-g against the envelope
```
