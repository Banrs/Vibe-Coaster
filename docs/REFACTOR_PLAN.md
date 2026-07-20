# Vibe-Coaster Full Refactor Plan (approved 2026-07-20)

User-approved plan for the full re-architecture. Source-of-truth requirements remain
`docs/AGENT_BRIEF.md`; this file records the approved architecture, targets, and phase gates.
Hard rule unchanged: **`--census 8` must end `complete=yes` after every change** — completion is
never traded for cosmetics. Push target: branch `claude/vibe-coaster-refactor-plan-jkxn0h`.

## User decisions (interview 2026-07-20)

- **Identity**: realistic, grounded set-piece showcase; high stimulation without over-densing;
  element/distance grounded in real-world values adjusted by the scaling spec below.
- **Sizing spec (AMENDED)**: element dimensions **0.75–1.5× the real record** (floor lowered from
  1.0×); one uniform λ per element. **Per-element time duration 0.9–1.0× the real element's
  duration** — sizing/entry-speed gating must respect duration, not just geometry bands.
- **Overlap (U1)**: zero geometry intersection ever; near-miss flybys allowed/encouraged as a
  feature (structure just outside the envelope). Envelope: 6 m centerline clearance (4 m escapes),
  relax to 4.5 m only if a seed fails completion. ASTM F2291 basis: patron reach + 76 mm; no public
  fixed number exists, so the 6 m radius is the project constant.
- **Water (U2)**: measured 10–15% water fraction (15% max on extreme seeds); terrain stays dramatic
  (cliffs ~195 m+ preserved).
- **Mix (U3/U4)**: balanced to real record coasters (Falcon's Flight + Tormenta average), no
  user-preferred weighting. Percentage shares, not counts.
- **Speed**: realistic base (360 km/h launch peak, natural decay) tuned upward toward the 240 km/h
  average after the mix is fixed; element speed windows must not starve.
- **Pacing**: ~120 s per lap; each lap is one composed act (launch statement → rush → airtime block
  → inversion block → breather → finale); acts rotate themes (mountain / canyon / water-skim) that
  bias shares within bands. Lap length derived from target duration × avg speed.
- **Visuals**: full shadow rework + broader visual pass; user does final GPU sign-off.
- **Refactor scope**: full re-architecture, census-gated at every step.

## Root-cause diagnosis (verified by full code read, 2026-07-20)

1. **No occupancy** — all commit qualification tests terrain only; streaming window pops old cps so
   built track can't be tested against (U1).
2. **Monolithic `Track`** — trial transactions deep-copy the whole object (all deques): 13 s/lap
   observed; occupancy impossible to bolt on.
3. **Count-based composition** — per-lap caps and `elemLimit=irnd(13,17)` instead of shares (U3/U4).
4. **Three frame systems** (Authored/Radial/FeltBank) + ~15 duplicated corridor scans + fallback
   ladder (escapes/relaxedPicks) covering placement root causes.
5. **Shadows**: direct term floored at 0.18 in full shadow AND ambient shadow-modulated (0.52–0.74)
   → "uniform slight dimming"; no cull-face control anywhere (no back-face depth pass possible);
   drifted duplicate shadow sampler in pathtrace; three drifted lighting-constant sets (U5).
6. **Renderer perf**: water + supports immediate-mode every frame; one draw call per 4 m rail span
   (uniform-tangent constraint); wheels never rotate.
7. **Audits** reconstruct roll via parallel transport (against the generator's own contract);
   thresholds duplicated and drifted (0.18 vs 0.15 curvature-jerk).

## Architecture

**Generator split** (keystone): `Track` becomes
- `CommittedTrack` — immutable append-only store: cps, spatial/analytic runs, evaluator
  (pos/upAt/tagAt), **occupancy hash grid** (16 m cells, shared_ptr archive surviving popFront).
- `GenCursor` — small mutable generation state (rng, speed, counters, pending, beat/act);
  transactions copy the cursor, not the world.
- One **corridor/occupancy probe service** (replaces all hand-rolled scans).
- One **frame authority** (felt-bank law over an RMF base; radial/authored frames become inputs).
- One **constants module** (Track statics + ride_constants.h merged; sizing spec 0.75–1.5×,
  duration 0.9–1.0×).
- Element builders behind a single interface; `v1_profiles.h` math kept as-is.
- **Composition director**: ride-cumulative share controller + act/beat script.

**Share targets** (bands 0.75–1.75× unless noted; sources: docs/CONTINUE.md researched table +
2026-07-20 research pass): banked-turn family ~26%, airtime hills ~15%, drops ~13%, inversions
~18% total (Immelmann ~12%, loop ~4%, corkscrew 2–3% always paired), S-curve ~8%, helix ~4%.
Count rules only for set pieces: opening top hat 1/lap, splashdown ≤1/lap finale-only-near-water
(real splashdowns are once-per-ride finale elements — SheiKra/Griffon), cliff dive 1/act.

**Rendering rework**: back-face shadow depth pass (add cull-face control), 3×3–5×5 PCF, bias
~0.5–1.5 texels, texel snapping kept; shadow multiplies DIRECT sun only; hemispheric ambient never
shadow-modulated; one lighting-constant source; one raster sky source. Then perf: static water
mesh, cached support meshes, rail tangent as vertex attribute (merge draw calls), spinning wheels.
Headless verify loop: `xvfb-run --orbitshot` → read PNG → iterate.

**Audits**: authored-frame sampling everywhere (Track::upAt, no parallel transport); centralized
thresholds; shared drive-loop helper; new probes `--overlap`, `--waterfrac`; census share report.

## Phases (each gates on census-8 complete=yes, then logical commit + push)

| # | Phase | Extra gate |
|---|---|---|
| 0 | Baseline snapshot + probes (--overlap, --waterfrac, census shares) | probes reproduce known state |
| 1 | Generator split + probe service + constants merge (behavior-preserving) | --exporttrack same-seed parity |
| 2 | U1 occupancy grid, enforced everywhere | --overlap = 0 violations |
| 3 | U2 water retune | waterfrac 10–15% across seeds |
| 4 | U3/U4 composition director + act pacing (~120 s laps) | all shares in band over 8 seeds |
| 5 | Fallbacks → ≤~1/10 seeds; joint anomalies; authored-frame audits | jointaudit clean, fallback target |
| 6 | U5 shadows + lighting unification + perf + wheels | orbitshot shows crisp shadows |
| 7 | Cliff-dive set piece + speed toward 240 avg + final gates | full suite + GPU gallery for user |

Delegation: architecture/review by the lead session; execution fanned out to parallel agents per
phase. Audits are hints — verify by geometry probes and screenshots.
