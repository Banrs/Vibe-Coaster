# Open issues — user review, 2026-08-09

Daniel's ride-through/review findings after the fidelity campaign. This is the starting
point for the next round of work, not a spec: investigate openly, measure, and expect to
discover problems beyond what is listed. `docs/TELEMETRY.md` holds measured ground truth;
root `CLAUDE.md` holds the contract.

## Ride quality

1. Missing micro elements — e.g. the slow-ish hilltop section Falcon's Flight has; small
   connective beats are absent.
2. Pacing cheated by near-zero-loss coasting — boring sections hold speed as if
   friction/drag-free, propping up the elapsed average.
3. G-force envelope still not reached in many parts.
4. Oversmoothing of elements.
5. Poor FVD implementation — the force-authoring quality itself, not just targets.
6. Poor terrain awareness — e.g. ~80 m above the terrain at the ride's highest point, never
   under 40 m; not actually terrain-hugging.
7. Overlapping supports and poor element shaping, especially inversions.
8. Poor sense of speed.
9. Entry launch should hit significantly higher speed — similar class to the camelback
   (tunnel) booster.
10. Poor element flow — jerky useless-bank → flat → useless-bank sequences.
11. Overly leisurely in many sections.
12. Too many flats — between the cliff-dive LSM and the camelback, on the return, and the
    hold extending too far from the cliff edge (so the clifftop is not terrain-hugging).
13. Airtime hills etc. too tame.
14. Elements miss the original near-future scaling requirements — scaling/geometry feels
    wrong when compared multi-dimensionally (height vs speed vs g vs duration together).
15. Jerky transitions.
16. Many more hard-to-describe "feel" gaps beyond the itemizable ones.

## App

17. Loading time.
18. Camera/HUD issues.
19. Generation/CI speed — a seed costs thousands of element integrations because every
    solver iteration re-integrates at full 1.5 m resolution; smoke is ~2 min local / ~4 min
    CI plus runner spin-up, too slow for a tight dev loop. Candidate levers: coarse-to-fine
    solving (search coarse, integrate the accepted geometry fine), caching Godot + imports
    on CI, splitting the gate into parallel jobs.

## Audit coverage for issues 1–16

The offline fidelity baseline (see README) emits a deterministic traceability record for every
issue in this list: `review/issue-coverage.json` and `review/issue-coverage.md` under
`INSPECT_OUT`, with `review/checklist.md` holding the review prompts and `audit.md` holding the
evidence snapshot, POV map, and gap list. Each record links the issue to the evidence IDs,
review prompts, and generated artifacts that bear on it.

**No issue here is closed by an audit result.** As of the 2026-08-11 baseline, every one of the
sixteen is in state `review-prompt` or `evidence-gap`: catalog
`2026-08-10.evidence-baseline.2` holds no `executable` source and empty `selectors`,
`observations` and `targets`, so the run legitimately produces zero findings and the
recommendation `no-eligible-finding`. That is the contracted output for an empty eligible set —
it records that nothing was eligible to compare against, not that the ride is right. A
diagnostic number, a green run, or an unlinked artifact is never sufficient to mark a
ride-quality issue solved; only measurement against reviewed evidence, or an explicit user
decision, closes one.

### Promoting a finding to a hard gate

A finding becomes an enforced gate only through a new Superpowers design cycle that establishes,
in writing and in code:

1. Reviewed **executable** evidence — a committed source artifact or content digest, retrieval
   date, exact window, axis mapping, row/seat, transform ID, confidence rationale, and the
   required corroborating links. Corroborative, observation-only, and review-pending sources
   cannot define a band.
2. An explicit **threshold and scope**: which metric, which axis and polarity, which selector
   and window role, which seeds, and what counts as a miss.
3. A **focused failing test** that fails before the change and passes after, plus a decision on
   whether the check joins the smoke gate or stays diagnostic.
4. Proof that the promoted gate **cannot be satisfied by cheating**: it must not reward geometry
   smoothing, a fitted or clamped radius, a viewer-only path, or hidden drive. Generated
   positions stay raw integrator output; any filtering must be the labelled human-tolerance
   filter or a catalogued evidence comparison.

## Known limitations of the baseline itself

- The radius strip in the channel sheets is degenerate. Near-straight track yields enormous
  finite radii, so the linear plot range runs to ~5.4e8 m (seed 42), ~7.7e8 m (seed 11) and
  ~8.0e8 m (seed 20260809), collapsing all small-radius detail onto the baseline. The sidecar
  legend declares the non-finite (`unbounded`) counts honestly, but the strip is not usefully
  readable as drawn. Lives in `godot/fidelity_artifacts.gd`.
- Issue coverage links only `review/seed-42/channels.png` as the generated artifact for every
  issue, and only issues 9, 12, 14 and 15 carry their real titles — the rest render as
  "Issue N". The top, elevation, and element side views are written and hashed but never linked
  from the coverage record, so the support-overlap and element-shaping prompts point at a
  channel sheet rather than the views they ask for.
- The POV map is entirely gaps: no source landmark has a committed alignment, so no POV frames
  are rendered. This is correct behavior (an unresolved alignment is an evidence gap, never a
  fallback), not a missing feature.

## Recommended approach

Compare the ride element by element against real high-thrill coasters — not just the two
named references. Use RideForcesDB (raw per-recording traces are decodable; multiple
recordings of one ride can be cross-checked) and similar sources, plus POV video extraction
and analysis, to ground every element class in measured reality and in how the real thing
*feels*. Discovery is the point: ride it, trace it, and chase whatever looks or feels wrong,
whether or not it is on this list.
