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

## Recommended approach

Compare the ride element by element against real high-thrill coasters — not just the two
named references. Use RideForcesDB (raw per-recording traces are decodable; multiple
recordings of one ride can be cross-checked) and similar sources, plus POV video extraction
and analysis, to ground every element class in measured reality and in how the real thing
*feels*. Discovery is the point: ride it, trace it, and chase whatever looks or feels wrong,
whether or not it is on this list.
