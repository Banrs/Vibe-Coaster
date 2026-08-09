# Ride Fidelity Audit Design

## Purpose

Build a reproducible, diagnostic-only audit before changing ride behavior. The audit compares the established fifteen-seed fleet with the measured references already recorded in `docs/TELEMETRY.md`, `docs/TELEMETRY-I305.md`, and `docs/RESEARCH.md`. It keeps loads, geometry, pacing, terrain, and transition evidence separate, generates a standard human-review pack, and recommends one bounded follow-up only when the evidence is systemic and credible.

The audit does not alter the generator, element templates, verification envelope, viewer, or CI gate. A fidelity miss is evidence, not a failure. Only malformed reference data, generation failure, or artifact-write failure makes the audit command fail.

## Architecture

- `godot/fidelity.gd` is a stateless measurement and comparison module. It owns composite-element grouping, row-aware windows, held-value calculations, route measurements, catalog validation, fleet aggregation, and deterministic recommendation ranking.
- `godot/fidelity_references.gd` is the reviewed executable subset of the existing telemetry prose. Every target carries provenance, confidence and caveats, an element selector, a metric, the raw measured band, any near-future scaling rule, the retained hold duration, the final target band, and the related issue numbers.
- `godot/_inspect.gd` remains the on-demand non-gating entry point. It builds each seed once, writes deterministic JSON and Markdown under `/out/fidelity/`, and creates the standard review images.
- `godot/smoke.gd` delegates only element segmentation and held-value math to the shared module. Its target constants, error messages, seed fleet, CI role, and pass/fail semantics stay unchanged.

## Measurement Model

Each route is split into stable beats using shared element-dictionary identity, with grade and closure sections as boundaries. Beat IDs use phase, ordinal, and kind. Seven row windows are measured; a rear-row window begins and ends when that row, rather than the train nose, crosses the beat boundaries.

The five scorecard dimensions are:

1. loads: filtered peaks, held values at reference durations, onset, roll rate, and time in force bands;
2. geometry and scale: length, height or drop, width, pitch, bank, radius, and entry/exit speed;
3. pacing and energy: duration, cadence, speed shares, dead-zone time, and unpowered speed loss;
4. terrain: AGL minimum, median, maximum, and time in terrain-hugging bands;
5. flow and transitions: adjacent beat types, flat dwell, force swing and duration, and bank/roll handoff.

Catalog-backed measurements are classified as `within`, `under`, or `over`. Other measurements are `observed_only`; selectors with no matching generated beat are `evidence_gap`. No overall fidelity score is emitted.

An eligible recommendation must use medium- or high-confidence evidence and affect at least eight of fifteen seeds. Eligible findings sort by normalized median miss, prevalence, confidence, then stable target ID. Normalized miss is the distance outside the target band divided by the greatest of the two target magnitudes, the target span, or `0.1`.

## Outputs

The canonical `audit.json` contains schema and catalog versions, the fixed seed fleet, source and issue mappings, per-seed/per-beat/per-row measurements, dimension aggregates, findings, evidence gaps, human-review prompts, and either one eligible recommendation or an explicit no-eligible-finding result. `audit.md` is a deterministic summary generated from the same model. Neither file contains timestamps or absolute paths.

The review pack contains channel, top, and elevation views for seeds 11, 42, and 20260809; seed-42 element side views; and an unscored checklist for feel, speed perception, shaping, and support overlap.

## Verification

Synthetic tests cover catalog validation, composite grouping, row-shifted windows, held-value parity, target classification, evidence gaps, aggregation, and deterministic ranking. The full fifteen-seed audit runs twice with byte-identical JSON and Markdown. The required Godot import and smoke commands pass before and after implementation, and generated ride behavior remains untouched.
