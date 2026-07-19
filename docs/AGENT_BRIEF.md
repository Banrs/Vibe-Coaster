# Vibe-Coaster — Agent Brief

You are taking over a voxel roller-coaster game (raylib/OpenGL, C++). Your job is to make it
**correct, realistic, cohesive, thrilling, and well-rendered**. This brief tells you WHAT is wrong
and WHAT the game should be. It deliberately does **not** tell you how to fix anything or where the
bugs are — **read the entire codebase yourself, form your own diagnoses, and fix root causes.** The
previous assistant's guesses were often wrong; trust the code and the running build, not prior
conclusions.

Start by reading the whole thing: `v1/coaster_track.cpp` (the streaming generator), `src/*.cpp`
(host, rendering, physics, car, terrain), `src/v1_profiles.h`, and the docs. Then decide what the
real architecture problems are. Prefer refactoring root causes over stacking patches.

---

## What this ride is (the identity to hit)

A **record-breaking** coaster that reads like a real, modern, world-record steel coaster — the
airtime + terrain drama of Intamin's Falcon's Flight crossed with a Tormenta-class dive coaster's
inversions. Every decision should be the one a real engineer building the world's most intense
coaster would make.

Design constants (these are firm; source them from one place, not scattered literals):
- **Speed:** average/cruise **~240 km/h**, peak **~360 km/h**. 200 km/h is a *slow* moment, not a
  fast one.
- **Size:** each element **1.0–1.5× the real-world record** for its type (one uniform linear scale
  per element).
- **G-force:** felt g **~2× the real per-element value**, inside a hard **+12 g / −6 g** envelope.
- **Clearance:** per **ASTM F2291** (envelope-based; no fixed floor). The track may run *close* to
  terrain — a metre or two of margin, not tens of metres.

Real-world anchors and the geometry philosophy are in `docs/GEOMETRY_REFERENCES.md`. Element
**frequencies** should match the **average of Falcon's Flight and Tormenta Rampaging Run** (not the
max of either), each type within **0.5×–2×** of that average.

---

## What's wrong right now (observed symptoms — diagnose the causes yourself)

**Ride composition / realism**
- Far too many banked turns, and they frequently chain back-to-back.
- Airtime hills are far too rare.
- Corkscrews are too frequent; they should be ~2–3% of features, occasionally doubled. Keep a few,
  plus a few signature elements seen on other modern record-breakers.
- Overall element frequencies don't match real life (see the average-of-two basis above).
- Elements are tuned to stay inside a g limit but aren't *geometrically* correct. The elements
  **and the joints between them** must be right and realistic — not merely force-capped.
- Corkscrews have a yaw problem: the heading behaves wrongly / snaps at the joints.
- Roll recovery is too fast and too short — a ~90° twist happens in under ~0.2 s. It doesn't even
  register as sustained force on the g-meter, but it spikes. Real roll transitions are drawn out.
- Entry-angle g spikes appear at some element joints.

**Terrain relationship**
- The track rides weirdly high — it floats far above flat ground instead of hugging it.
- Top hats crest and return to ~20 m every time. (The element being symmetric is *correct*; the
  problem is that its entry / launch platform sits too high above the ground.)
- There are random terrain digs on flat-ish sections where nothing should be cutting into the
  ground.
- The coaster should work WITH the terrain: launch up from near the surface, dive back down toward
  it — converting height into speed like a real terrain coaster.
- The terrain itself should stay **dramatic** (Falcon's-Flight-style cliff at the start, variation
  up to ~195 m and beyond given the size multipliers). Tunnels are fine but should be shallow and
  occasional, not deep or frequent.

**Robustness**
- The generator leans on artificial fallbacks (e.g. single-hill fallback, forced escape connectors)
  to guarantee the ride finishes. These should almost never fire — target **≤ ~1 fallback per 10
  seeds across all of seed space, of any kind** — achieved by the normal path being robust, not by
  canned rescues. It must still always produce a complete ride.

**Rendering**
- Shadows are broken: the whole scene sits under a uniform slight dimming instead of showing crisp
  cast shadows. (A candidate fix was attempted in `render_fx.cpp` — verify it yourself, and own the
  whole shadow pipeline; don't assume it's right or wrong.)
- The car's wheels look missing/broken.
- The renderer needs a real optimization pass (culling, LOD, static-mesh caching) to hold a high
  frame rate at record speed with long sightlines.

---

## Reference facts you can rely on (not solutions — just true things)

- Top-hat face pitch is currently capped at ~65° (reference 64.25°, the Falcon's Flight camelback);
  the general grade cap is 65°; the recovery drop reaches 67°. For comparison, a real dive-coaster
  drop is ~95° (beyond vertical) — relevant only if a true dive element is wanted; a top hat at 65°
  is realistic.
- Corkscrew reference geometry: one 360° revolution, ~60° helix pitch, ~6.6 m reference radius
  (details and citations in `docs/GEOMETRY_REFERENCES.md`).

---

## How to verify (do NOT trust the audits as truth)

The headless audits are buggy and have mis-reported repeatedly — treat any pass/fail as a hint, then
confirm for yourself. Verify by, in order of trust:
1. **Reading the geometry and the code.**
2. Deterministic geometry probes: `--census N` (element mix / family share / completion),
   `--clearance N` (deck height vs terrain, buried samples), `--jointaudit N` (joint continuity,
   roll/curvature rates), `--forceaudit N` (live g/speed envelope). These reflect real geometry
   faithfully.
3. **Running the build and looking.** github is blocked here; raylib 5.5 is vendored, so build with:
   ```sh
   g++ -std=c++17 -O2 -DNDEBUG -I/root/raylib55/src src/main.cpp /root/raylib55/libraylib.a \
       -lGL -lm -lpthread -ldl -lrt -lX11 -o minecoaster
   ```
   Headless rendering runs on software Mesa (`xvfb-run … ./minecoaster --orbitshot`) — it's slow and
   its HDR/sky exposure is unfaithful (blows out to white), so use it for **geometry**, and use A/B
   comparisons or a faithful-exposure path for lighting. It faithfully shows shape, layout, shadows-
   as-relative-contrast, and the car.
4. The human running it on a real GPU is the final word on lighting.

**Hard rule:** never introduce a generation stall or raise the fallback rate to fix a cosmetic
issue. After any generator change, confirm a full multi-seed run still completes every ride.

Use online references as clean-room *concepts* only (openFVD/FVD++ for force-vector design, clothoid
math for transitions, ASTM F2291 for clearance, manufacturer specs for dimensions), honoring the
licenses noted in `docs/GEOMETRY_REFERENCES.md`. No GPL code copied.

---

## Definition of done

A complete ride on every seed, with: element frequencies within 0.5–2× of the real-life average
(banked turns down, airtime hills common, corkscrew ~2–3%); geometrically correct elements and
continuous, realistic joints (no yaw snaps, no entry g-spikes, drawn-out roll transitions); a track
that hugs and uses dramatic terrain (launches from near grade, dives toward it, no random flat-ground
digs, no floating); record-level speed/size/g inside the +12/−6 envelope; fallbacks essentially gone;
and a renderer with working crisp shadows, visible wheels, and a solid frame rate.
