# Planner Decision Layer — Seeded Variety Design

**Status:** approved direction (2026-08-15 review session). Executes the user decision that
gap A (`docs/ISSUES.md`) is a bug: seeds must genuinely vary the ride — track, element
geometry, and element order — built as the FVD-first design's RidePlanner vision
(`2026-08-09-fvd-first-configurable-generator-design.md` §4), not a throwaway RNG sprinkle.
The version-1 config surface (`2026-08-12` material plan Task 4) builds directly on this
layer.

## Constraints carried over

- Randomness lives only in planning, in **named decision streams**; compilation and
  integration receive no RNG. Same seed → bit-identical ride.
- **No candidate loops**: draws come from conservatively certified capability ranges; a
  failed solve/validation is a structured error with stream/draw provenance, never a retry.
- Records are fixed identity: camelback ~250 m prominence, the derived record-launch band
  (`2026-08-15-record-launch-derivation.md`), Immelmann 100–110 m. Suspense elements never
  scale toward records. Non-record geometry draws within bands grounded in the FF/TRR
  counterpart table (`docs/evidence/fidelity/counterpart-bands.md`).
- Order variation only inside grammar cells; the spine
  (launch → opener → act1 → climb → clifftop → dive → tunnel → camelback → return → brakes)
  stays ordered; `sequence.order` stays reserved.
- The story stays twenty roles / ten beats under preset `material-v1`; role identity/count
  per beat may vary only where a grammar cell says so.

## Architecture

New file `godot/ride_planner.gd` (`class_name RidePlanner`), owning:

1. **Decision streams.** `streams(seed)` derives one `RandomNumberGenerator` per named
   decision from `hash(seed, stream_name)` — `terrain`, `placement`, `story.act1`,
   `story.return`, `targets.<role-id>`. Draw order inside a stream is fixed and documented;
   adding a stream never disturbs existing ones. `Terrain.generate` and `_plan` placement
   move onto their streams (visible behavior of terrain/placement per seed may change once —
   accepted, it is still seed-deterministic).
2. **Grammar.** The `material-v1` grammar as data: spine beats; act-one cell = Immelmann
   first (fixed physics anchor), then a pool {cutback, helical-loop, airtime-braid,
   wave-turn} permuted by `story.act1`, with one optional member (airtime-braid or
   wave-turn — never both dropped, never the inversions) droppable; return cell = the
   {turn, height, turn, height} sequence with `story.return` permuting which of the two
   authored turn/height variants comes first (composition count stays 2+2 this checkpoint —
   varying the count changes the seven-control solve topology and is deliberately deferred).
3. **Target draws.** Per-role resolved targets drawn on `targets.<role-id>` within declared
   conservative ranges, e.g.: airtime-hill negative-g and crest hold, wave-turn bank, teardrop
   overbank, loop positive-g, return-turn banks (inside the solve's existing bounds),
   role-length driving durations. Each range certified two ways before shipping: (a) inside
   the envelope and the counterpart band for that element class, (b) demonstrated feasible at
   both extremes on the full 15-seed fleet (test-enforced, not hoped).
4. **Plan provenance.** The plan records every selected sequence and resolved target with
   its stream name and draw index; `generation_stats` stays honest (`accepted_integrations: 1`,
   no retries).

`RideProgram` recipes become parameterized: `_add_story_act_one(...)` and friends take the
resolved targets/sequence instead of hardcoded literals; `terrain_story_capability` becomes
a function of (side, drawn story) — the prefix is still integrated exactly once per build.
Role-list validation (`ride_program.gd` `MATERIAL_ROLE_IDS`, prefix map,
`route_contract_tests.gd`, `generator_material_tests.gd`) validates against the plan's
declared sequence, generated from the grammar, instead of one static 20-list.

## Gates

- Same-seed double-build bit-identity stays (smoke).
- New smoke diversity assertions across the 15-seed fleet: route lengths not all within
  5 m, durations not all within 0.5 s, at least two distinct act-one sequences.
- All existing structure/seam/clearance/load gates unchanged; terrain proofs re-verified on
  all seeds; act-one identity tests generalize to grammar-legal sequences.
- Record bands (top speed, camelback prominence, Immelmann height) stay pinned per seed.

## Staging inside this checkpoint

1. Streams + parameterized targets (no order change yet) — fleet green, diversity gate on
   lengths/durations passes.
2. Act-one permutation + optional drop — diversity gate extends to sequences.
3. Return-pair permutation — only if the solve's basin tolerates it on all seeds without
   bound-widening; otherwise deferred with a recorded measurement.
