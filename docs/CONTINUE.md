# Continue here — Vibe-Coaster generator repair

Self-contained brief for continuing this work (incl. in a fresh / online session). Read this, then
`README.md`, `docs/GEOMETRY_REFERENCES.md`, and `docs/V1_HANDOFF.md`. The diagnosis below was
verified with `lldb` against the live binary (not just static reading) — trust it over the raw
audit output, which misreports (see "audit caveat").

## Ride spec — authoritative multipliers (do not re-derive)

Arcade feel on a **real-world record-breaking** grounding. Every element is sized/paced from a real
reference, then scaled by these multipliers, and the *relative* relations (radii, element durations,
entry/exit speeds, spacing) should still roughly follow real-life proportions per element:

- **Speed:** ~**240 km/h average**, **360 km/h peak** (~2× Falcon's Flight). So ~200 km/h is *below
  average* cruising speed — NOT "very high speed". Elements must run cleanly across this whole band;
  a stall at 190–230 km/h is a geometry/terrain bug, never a "too fast" symptom.
- **Size:** **1.0–1.5× world-record** dimensions (`RECORD_SCALE_CAP = 1.50`).
- **G-forces:** ~**2× the real element's** peak, per element (overall envelope ≈ **+12 / −6 g**).
- **Proportions:** radius, duration, and repetition per element follow the real reference (e.g. a
  corkscrew's real revolution count), then scale uniformly by the one 1.0–1.5× λ.

## Mission

Make the procedural generator produce a **complete, intense, record-breaking** ride every time.
The tree already *targets* the right spec and already builds a correct opening — it just **stalls a
few elements in** and never finishes the ride.

## Current state (2026-07-18)

- **One branch: `main`.** Builds to `./minecoaster` (`cmake -B build -S . && cmake --build build -j`).
  Generator: `v1/coaster_track.cpp` (one `struct Track`, a streaming generator). Host: `src/main.cpp`.
  Analytic profiles: `src/v1_profiles.h`. Audits: `src/v1_geometry_audit.cpp`, `v1/audit_diagnostics.cpp`.
- **The spec is already correct:** g envelope enforced at `+12 / −6.5 g` (`src/main.cpp:770`), launches
  to **360 km/h** at 1.5× Do-Dodonpa accel (`src/ride_constants.h:22-38`, `--launchaudit` PASSes),
  record dimensions capped at 1.0–1.5× (`RECORD_SCALE_CAP=1.50`, `v1/coaster_track.cpp:18`).

## THE ROOT BUG (fix this first — everything else cascades from it)

Generation **exhausts the scheduler 2–4 elements after the opening top hat**. Path: `reset()`
(`v1/coaster_track.cpp:700-827`) opens with `M_LAUNCH` → top hat → and within a few more elements,
right at an `M_DIP` → `M_HELIX`/`M_WAVE`/`M_IMMEL`/`M_ROLL` hand-off, the successor element gets
built and runs, then **can find no valid next connector/element from its own exit anchor**. All 3
scheduler attempts fail (`SCHEDULER_ATTEMPT_BUDGET=3`, `:155`), `schedulerExhaustions++` (`:4348`),
`genPoint()` returns false (`:4352-4458`) = "GENERATION FAIL". Because no lap ever closes, this one
stall causes **all** the scary symptoms downstream.

Next debug step (lldb, as done for this map): instrument the exit-frame / boundary state of
`initHelix()` (`:2666`), `initWave()` (`:3126`), `initImmel()` (`:1862`), `initRoll()` (`:1869`)
**immediately after an `M_DIP` predecessor**, and check `routeConnectorAround()`'s final fallback.
This is the still-open "helix … C3 neutral exit" item in `docs/V1_HANDOFF.md:13`. Fix the **root
cause** in that hand-off, not a patch. Fixing it alone should flip `--census`, `--audit` (A/I),
`--forceaudit`, and `--jointaudit` from FAIL to measurable.

## What is NOT broken (verified — don't waste time here)

- **The opening top hat is fine.** `beginTopHat(major)` succeeds on the *first* attempt in all 8
  seeds (lldb-confirmed). The geometry has it (`M_LAUNCH`→`M_CLIMB`→`M_DROP`, one `MACRO_TOP_HAT`
  analytic run). `--audit` Gate B/C/G independently confirm it's present and correctly sized
  (drop 165–238 m). The **`hat=0` report is a MEASUREMENT ARTIFACT**: the census top-hat counter
  only updates in `closeLapAtLaunch()` (`:2218-2246`), which never runs because no lap closes; and
  `--v1issues` early-returns at `src/v1_geometry_audit.cpp:1726` (`if finalPoints<450 ||
  generationExhaustions!=0 return`) *before* it inspects top hats. So "top hat lost" is a symptom of
  the stall, not a top-hat bug. (If it still looks absent in-game *after* the stall is fixed, chase
  it then — but expect it to reappear on its own.)
- **Airtime is already ejector, not "leisure."** Measured top-hat crest g (`--forceaudit 4`):
  **−2.79 / −5.61 / −4.72 / −6.52 g** — at/over the −6 g floor. If play feels tame, it's because
  generation dies after ~3–4 elements, so a sustained intense sequence is never reached.
- **Braking is already minimal.** No auto in-course brake/trim/MCBR anywhere in the generator or
  physics — grep confirms the only brake is the station-arrival velocity clamp (`src/main.cpp:1725-1729`)
  and a manual debug key. Coasts between launches use natural `DRAG`/`FRICTION` (`src/ride_constants.h:10-11`).
  Nothing to remove; this already matches "station + one holding-pause only."
- **Streaming + new-platform already exist.** `popFront()`/`ensureAhead()` stream infinitely
  (`:367-376`, `:4460-4473`); a "lap" = the launch-to-launch interval (`elemLimit=irnd(13,17)`,
  reset in `closeLapAtLaunch`); a physical **station** is a separate ~205 s-cadence event
  (`src/main.cpp:1709-1716` → `startStation()` `:3258-3283` → always re-launches). Infinite terrain
  (`src/environment.cpp:200-270`). It already "arrives at a new platform then continues" — it just
  needs to survive long enough to reach one.

## Real g problems that DO need fixing (after the stall)

- **`M_TURN` entry spikes to +12 g** (seed 2 already exceeds the +12 cap) — an entry-angle g spike,
  not a conservative cap. (`docs/V1_HANDOFF.md:13` "no stitched entry-angle g spike".)
- **`M_ROLL` rings 15.4 g LATERAL** (seed 2) — the continuity blowup. Same entry-angle-spike class.
- **`M_HILLS` (main airtime family) has no explicit crest-g target** — `beginHillChain()`
  (`:469-572`) sizes from an energy ratio only. `M_BANKAIR`/`M_WAVE` do set one (`gCrest=-3.2f` at
  `:3108/:3147/:3491/:3510`). If you want deliberate ejector control on the main hills, add an
  explicit crest-g target there, sized *within* the existing 1.0–1.5× band (via radius/height),
  NOT by moving the record anchors.

## VERIFY THE ELEMENT COUNT FROM FIRST PRINCIPLES (do not trust the audit's number)

`elemLimit = irnd(13,17)` elements per launch-to-launch lap (`v1/coaster_track.cpp`, reset in
`closeLapAtLaunch`). **Confirm this is actually realistic — do not accept 13–17, or any audit
count, on faith** (the audit is buggy; a "300 elements" figure seen earlier was a misreport of
control-points/samples, not elements — a real 5 km coaster has ~20–40 elements). Derive the
expected count from real data:

1. Compute **real-world element density** (elements per km of track) from the reference coasters
   (Falcon's Flight, Millennium Force, Steel Vengeance — count named elements ÷ length).
2. **Adjust for our sizing/speed multipliers**: our elements are ~1.0–1.5× larger and run at ~2×
   speed, so each eats *more* track length ⇒ *fewer* elements per km. (At ~2× speed with real
   element *durations*, element track-length roughly doubles.)
3. Multiply the adjusted density by the **actual generated track length** (measure it — arc length
   between two stations / per lap), and check the generated element count matches that expectation.
4. Also confirm the audit's "element" *unit* itself isn't conflating control-points/samples with
   elements. Fix the reporting if it is.

The question to answer explicitly: **is 13–17 the same elements-per-unit-track as real life once
the size multiplier is applied — or is the count (or the unit) wrong?**

## Goals, in order

1. **Fix the post-top-hat scheduler exhaustion** (the `M_DIP`→inversion hand-off) so rides COMPLETE.
2. **Confirm inversions then actually generate** (they're currently dead only because of the stall).
3. **Kill the entry-angle g spikes** (`M_TURN` +12 g, `M_ROLL` 15.4 g lateral).
4. **Verify + right-size the element count** per the section above.
5. **Tune deliberate intensity** where it's emergent (main `M_HILLS` crest-g), staying in-band.
6. **Visuals** — voxel / modern / futuristic look for track / coaster / platform + shader fixes.
   Real geometry drives shape/structure only; art stays voxel-futuristic.

## Working rules

- **The audit is NOT ground truth** — it's buggy and over/mis-reports (`hat=0`, "300 elements",
  early-returns). Use it as a hint, then verify by reading geometry, by lldb on the live binary,
  and decisively by the human running `./minecoaster`.
- **No GL in the dev sandbox** — `InitWindow` segfaults headless; visual changes are human-verified.
- **Refactor root causes; don't stack patches.**
- The deleted "V2" rewrite is **not** a reference (over-smoothed, broken pitch/roll). Reusable
  *ideas* only: pull-through airtime valleys (no flat bottoms), heartline banking with lead/lag +
  fast roll unwind, curvature sized from speed for controlled g.

## Build / verify (gate status at this HEAD)

```sh
cmake -B build -S . && cmake --build build -j    # -> ./minecoaster
```
| Flag | Measures | Status |
|---|---|---|
| `--launchaudit` | launch/booster hit 360 km/h @4.90 g | **PASS** |
| `--terrainaudit` | terrain cache/mesh reuse | **PASS** |
| `--audit N` | Gate table; **B/C/G (top hat) PASS**, A/I FAIL | FAIL via the stall only |
| `--census N` | 3 laps/seed, element mix | FAIL — stall before lap 1 closes |
| `--forceaudit N` | live g/speed envelope | FAIL (stall) — also surfaces the +12 g / 15.4 g spikes |
| `--v1issues N` | static structural audit | FAIL — early-returns on `generationExhaustions!=0` |
| `--jointaudit N` | rail joint continuity | FAIL (stall) |

Every "does a full ride generate?" gate fails for the **same** reason (the stall); every "is the
top hat correct?" gate already passes. So: fix the stall first, then re-read everything.
