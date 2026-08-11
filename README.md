# Vibe-Coaster

A seed-based, one-shot roller-coaster generator in pure GDScript (Godot 4.7). Every seed is a
complete, rideable, physically validated ride: a near-future (~2041) hybrid of Intamin's
Falcon's Flight and B&M's Tormenta: Rampaging Run, on a seeded desert escarpment of ~300 m
relief. Same seed, same ride — bit for bit.

This is an engineering-sim concept, not a survey reconstruction or a certified design.
Physics, generation, and validation are the product; the visuals are a deliberately generic
inspection layer (placeholder train, simple track and pillars).

## What a seed contains

- Records chased honestly: ~340 km/h via a downhill tunnel launch, a ~250 m camelback
  (structure above its valley), a ~90° cliff dive down ~0.8× the escarpment relief, a
  80–100 m Immelmann (tallest-inversion class), a helical-leg vertical loop, a cutback,
  9–10.5 km of track.
- Falcon's Flight's skeleton in five cohesive gestures — twisted side-drop into one flowing
  low act, a boosted-then-coasting decelerating cliff climb, one crest hold with an
  outward-banked rim turn, a monotonic 90° dive into the tunnel launch and camelback, and a
  single sweeping return arc home — with Tormenta's inversion act grafted where its physics
  belongs (act one, at 42–50 m/s). No lifts: a ~4 g air-powered entry launch plus two 
  ~2 g LSM boosters (one of them the record launch).
- Exactly three boost zones, no mid-course brake, one continuous energy arc after the tunnel
  launch, and one deliberate slow beat (the crest hold).
- A ~2041 human-load envelope: duration-stretched ASTM F2291 curves at +8.0/−3.0 Gz ·
  ±4.7 Gy · +8.0/−6.0 Gx · 25 g/s onset · 120°/s roll (anti-G-suit and restraint-tech
  credits — design fiction grounded in `docs/RESEARCH.md` §5).

Every seed passes: frame orthonormality and C4 seam continuity, terrain and self clearance,
push-pull, the 0.2 s reversal rule, pairwise combined-axis ellipses, onset and roll-rate
limits, element-shape expectations (camelback structure, inversion heights, dive steepness),
and determinism. Per-row (7 rows) filtered envelope usage on the duration curves is gated on
the three deep seeds (11, 42, 20260809); the twelve sweep seeds are gated on structure,
seams, and clearance only, to keep CI time down.

## Run

```sh
godot --path godot
```

- `N`: generate a new seed (the HUD shows the current one)
- `C`: POV → chase → overview → fly camera; `1`–`7`: choose a row
- `Space`: pause · `R`: restart · `[` / `]`: playback speed
- Fly camera: right mouse + mouse look, `WASD`, `Q/E`, Shift

## Verify

```sh
godot --headless --path godot --editor --quit
godot --headless --path godot --script res://smoke.gd
```

The smoke gate self-tests the verification toolkit against synthetic signals, probes every
element template against its closure contract, runs both focused fidelity suites, and builds
multiple seeds twice — identical output, all checks green, on CI's ubuntu baseline as the
performance floor.

## Offline fidelity baseline

`_inspect.gd` is the diagnostic runner and the offline fidelity-audit command. It is not a
gate on ride quality; it is a measurement pack you read.

```sh
INSPECT_OUT=out/fidelity-baseline-a godot --headless --path godot --script res://_inspect.gd
```

`INSPECT_OUT` chooses the output directory (default: `<user data>/inspect`). The run is fully
offline — no network client exists anywhere in `godot/`, and the only URLs in the tree are
inert provenance strings in `fidelity_references.gd` and the committed evidence records under
`docs/evidence/fidelity/`.

The fleet is fixed and its order is part of the contract, never sorted:

```
11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101
```

Each seed is generated exactly once per run (`manifest.json` → `generation_counts`, all `1`).
Seeds 11, 42 and 20260809 are the deep-review seeds whose routes are retained for rendering.

Output contract, all paths relative to `INSPECT_OUT`:

- `audit.json` / `audit.md` — the canonical report: identity and pinned legacy base commit,
  fleet, per-seed measurement summaries, findings, observed-only rows, evidence gaps,
  recommendation, evidence snapshot, POV map, checklist, issue coverage.
- `manifest.json` — `fidelity-artifact-manifest@1`: `generation_counts` plus one record per
  written file with byte size, SHA-256, kind, seed, beat, and PNG dimensions.
- `review/pov-map.{json,md}`, `review/checklist.md`, `review/issue-coverage.{json,md}` — the
  human review pack, keyed to the sixteen open issues in `docs/ISSUES.md`.
- `review/seed-<n>/channels.{json,md,png}` — eleven stacked raw-generated channels (speed,
  normal, lateral and longitudinal proper g, pitch, roll rate, AGL, reconstructed curvature,
  radius, roll acceleration, jerk). The PNG carries no text; the JSON/Markdown sidecar names
  every strip with unit, plot range, and non-finite counts, and the pair is the artifact.
- `review/seed-<n>/{top,elevation}.png` and `review/seed-42/elements/*.png` — the existing
  inspection views, now written through the same checked writer.
- `review/seed-<n>/pov/<beat>.png` — generated POV frames, written only for a source landmark
  with a committed alignment. No landmark has one today, so `pov-map.md` is all declared gaps
  and no frame is written. An unresolved alignment is an evidence gap, never a fallback.

Evidence authoring is a separate, manual workflow and is never part of this command. Sources
are researched, reviewed, and committed as metadata, timestamped landmarks, and hashes under
`docs/evidence/fidelity/`; no copyrighted video, frame, audio, cookie, or token is committed.
The audit, the focused suites, and CI only ever read those committed records.

Every text write is read back and byte-compared, every PNG is reopened and decoded, and every
manifest hash is computed from the file on disk. Two consecutive runs produce byte-identical
JSON, Markdown, and manifests.

Exit semantics are deliberately split. Operational failures exit 1: malformed catalog data, a
bad artifact root, generation failure, physical inconsistency, or a failed/unverifiable write.
Fidelity misses are diagnostic and exit 0 — an `under` or `over` finding is something to read,
never something that fails the command.

**Read the recommendation honestly.** The committed catalog currently holds no `executable`
source, and empty `selectors`, `observations` and `targets`, so the audit emits zero findings,
zero observed-only rows, zero evidence gaps in the comparison, and the
recommendation `no-eligible-finding`. That is the contracted output for an empty eligible set.
It means *no evidence was eligible to compare against*, not *the ride passed*. The gate is real
and deterministic; the evidence band is empty until a source is promoted to `executable`
through the review process in `docs/evidence/fidelity/catalog-review.md`.

Design history: `docs/PLAN.md` (the executed rewrite plan), `docs/RESEARCH.md` (fact-checks,
POV analysis, envelope grounding), `docs/REFERENCE.md` (retired checkpoint rationale).
