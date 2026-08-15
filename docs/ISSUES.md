# Open issues — user review, 2026-08-09

Daniel's ride-through/review findings after the fidelity campaign. This is the starting
point for the next round of work, not a spec: investigate openly, measure, and expect to
discover problems beyond what is listed. `docs/TELEMETRY.md` holds measured ground truth;
root `CLAUDE.md` holds the contract.

## Next session — start here (2026-08-15)

The `codex/material-generator` slice is merged. Verified on Godot 4.7.1 at merge time: the
import gate, the nine focused suites in `.github/focused-tests.txt`, and `smoke.gd` (2m00s)
are all green, and all fifteen seeds build and place clean. Two measured gaps found while
reviewing that branch are the recommended entry points, ahead of the sixteen items below.

**A. The seed does not vary the ride.** Measured across seeds 11, 42, 20260809, 1 and 99:
`8132.1–8132.4 m`, `158.8 s`, `328.3 km/h` top — identical to within 0.3 m and 0.1 km/h, and
the sweep reports `lengths 8.1-8.1 km` for all twelve. Determinism holds and is not the
problem; diversity is absent by construction. `_material_roles()` in `godot/generator.gd` is a
hardcoded twenty-entry list that takes no RNG, so every role's `length_m` band, `targets` and
`recipe_id` are seed-invariant. `_plan()` spends the seeded RNG on exactly three values —
`side`, `along_m`, `placement_u` — all of which move where the ride sits on the terrain, none
of which change what the ride *is*. `role_allocations_m` is byte-identical across seeds.
Decide deliberately whether that is the intended contract: `CLAUDE.md` promises "seeded
terrain-relative placement", which this satisfies literally, while `README.md`'s framing
invites the reading that seeds differ as rides. Either narrow the prose or give the plan real
seeded variation (role ordering, band sampling within the story, per-seed target draws) — and
if it is variation, `smoke.gd`'s cross-seed determinism check will need a companion check that
seeds actually *differ*, which nothing currently asserts.

**B. The record launch is ~12 km/h short of its declared number.** `CLAUDE.md` and `README.md`
both declare the tunnel LSM boost as "~340 km/h (the record launch)"; the built ride tops out
at 328.3 km/h on every seed. Nothing gates top speed, so this is undetected by CI. Resolve it
in one direction — author the tunnel booster up to the declared figure, or correct both
documents to the honest built value. Do not leave the contract and the ride disagreeing.

Since then Daniel's second ride-through added issues 20–26, and issue 24 — *FVD++ gets the g's
but not the geometry* — is the strongest candidate for the single root cause behind several of
them. If one thing is picked up next, pick that.

Carry-over from the same review: role `targets`, `phases` and `recipe_id` are published in the
accepted route but still unenforced (see *Known limitations of the baseline itself* below).
Only `length_m` and the three terrain intents are proven against the built ride, by
`_validate_role_lengths` in `godot/route_contract.gd` — that function is the working model for
enforcing the rest. None of the sixteen ride-quality issues below is closed.

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

### Second review pass — 2026-08-15

Daniel's findings after riding the merged material-generator build. Numbered from 20 to keep
1–16 stable, because those IDs are wired into the catalog and the audit (see the coverage note
below); these seven are **not** covered by the audit's traceability record.

20. Roll sections cheat the g and jerk budget. The roll is delivered as abrupt
    roll → flat → roll → flat steps rather than a coherent continuous roll, which keeps the
    filtered channels inside the envelope while the actual motion is incoherent. Closely
    related to 15 and 10, but the specific mechanism is the stepping, and it is a way of
    passing `validate_loads` without earning it — treat any fix that keeps the stepping and
    only reshapes the filtered trace as a cheat.
21. Height above terrain is not watched and drifts upward. There is a terrain-clearance floor
    but no ceiling and no control of slow upward drift, so the track wanders away from the
    ground over long stretches. Sharpens 6 with a concrete mechanism: the drift is unwatched,
    not merely mis-tuned.
22. The cliff dive starts too far out from the cliff edge. The dive should commit at the rim;
    it currently begins well back from it, which also costs the vertigo the beat exists for.
    Interacts with 12's "hold extending too far from the cliff edge" and with the placement
    bands in `generator.gd` (`DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M`, `DIVE_EXIT_APRON_BAND`).
23. Too many elements are geometrically distorted — e.g. the camelback carries a sideways tilt
    it should not have. The elements hit their force targets while their shapes are visibly
    wrong. Extends 7 beyond inversions and supports to the marquee elements.
24. The FVD++ implementation gets the g's but not the geometry, especially in the connecting
    transitions. This is the root cause behind 20, 23 and much of 15: authoring in the rider's
    frame is reproducing the force trace without producing a coherent swept shape, and the
    transitions between elements are where the discrepancy shows most. The deepest of the seven
    — 20, 23 and 25 are plausibly symptoms of it.
25. Still no sense of speed, possibly because of the height off the ground (see 21). Restates 8
    with a candidate cause worth testing directly: measure whether AGL, not velocity, is what
    is missing.
26. The clifftop section is just a slow bank, not the twisty, windy suspense the real coaster
    has there. The declared roles `clifftop-slow-crest` (35–70 m) and `clifftop-outward-rim`
    (65–120 m) may simply be too short to contain that character at all — check whether this is
    a shaping bug or an under-declared story beat before treating it as either.

## App

17. Loading time.
18. Camera/HUD issues.
19. Generation/CI speed — the time-domain return, capture, and brake solves have bounded
    coarse/fine/production evaluations, but the full fleet gate can still be slow. Measure current
    GitHub Actions timings before changing evaluation caps, caching imports, or splitting jobs.

## Code health — 2026-08-15 hygiene review

Production is 8,959 SLOC across 17 files; tests are 7,252 across 9. By subsystem: fidelity
4,080 · generator 3,544 · viewer 483 · verify 448 · harness 404. The read-only diagnostic layer
is the largest thing in the repository — larger than the generator it measures — which is worth
knowing before anyone reads `CLAUDE.md`'s "physics, generation, and validation are the product"
as a description of where the code is.

A **full** generator refactor is not recommended: it is green, deterministic, freshly landed,
and none of issues 20–26 is caused by its file layout. The return solve is also basin-sensitive
(act-one force changes perturb it), so gratuitous motion risks a hand-calibrated result for no
functional gain. Two bounded targets are worth doing, ideally as part of the issue 24 work
rather than before it:

- **Duplicated numerics.** `ride_program.gd` preloads `BoundedSolver` and uses it once, at the
  return solve, while carrying its own private `_linear_solve`, `_finite_difference_jacobian`
  and `_matrix_conditioning` for the capture and brake solves. Two Gauss-elimination paths that
  should be one. `godot/bounded_solver.gd` already exists and is tested.
- **`ride_program.gd` holds five concerns** in 1,746 lines / 55 functions: story-recipe assembly,
  the return solve, the capture solve, the brake solve, and the numerics above. The solve
  triple is the natural seam. Decomposition remains a standing user deferral — do it when
  issue 24 forces changes there, not speculatively.

Not adjusted, deliberately: the flat `godot/` layout (17 production files, prefix-grouped by
name — a directory move would rewrite ~40 preload paths, the `.uid` files, `main.tscn`, the CI
manifest and every doc reference for modest gain), and the name `_inspect.gd`, whose leading
underscore reads as private though it is a documented user-facing command (54 references, most
in historical plans).

## Audit coverage for issues 1–16

**The range in this heading is a code contract, not prose.** `1..16` is hardcoded in
`godot/fidelity.gd` (`_validate_issues` rejects any issue id outside it), in
`godot/fidelity_artifacts.gd` (`range(1, 17)` builds the coverage records), and in two focused
suites. Issues 17–19 and 20–26 therefore have no coverage record and cannot be referenced from
a catalog target, review prompt, or evidence gap. Extending the audit to the 2026-08-15
findings is a code change in those four places plus `_ISSUE_TEXT`, not a documentation edit —
do it deliberately, or leave 20–26 tracked here only and say so.

The offline fidelity baseline (see README) emits a deterministic traceability record for every
issue in that range: `review/issue-coverage.json` and `review/issue-coverage.md` under
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

Optional local `RFDB_4804_CSV` / `RFDB_6383_CSV` overlays are diagnostic-only. They do not
modify the committed catalog, create catalog selectors, observations or targets, create
fleet-comparison findings, promote a source to `executable`, or satisfy the evidence requirement
above.

## Known limitations of the baseline itself

- Plan role `targets`, `phases`, and `recipe_id` (e.g. the Immelmann's declared
  `vertical_excursion_m`) are published in the accepted route's `terrain_story_plan` but no
  code measures or enforces them — only `length_m` and the three terrain intents are proven
  against the built ride. Confirmed by the 2026-08-15 pre-push review; enforcing them the way
  `_validate_role_lengths` enforces lengths is deliberate next-cycle scope (the planned
  Immelmann re-scale exercises exactly those fields).

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
- The POV map is entirely gaps because no source landmark has a committed alignment. Supplying
  either optional RFDB export still renders diagnostic seed-42 midpoint POVs for supported
  side-view beats;
  those frames neither resolve nor promote an alignment.

## Where the POV and force-diagram links already live

They are committed — nothing needs re-researching. All twelve catalogued sources are in
`docs/evidence/fidelity/source-manifest.json` (retrieved 2026-08-10), each with its URL,
`current_state`, permitted axes, promotion prerequisites, and the SHA-256 of its metadata
artifact. Per-source records sit alongside it in `docs/evidence/fidelity/rideforcesdb/` and
`docs/evidence/fidelity/youtube/`, and `godot/fidelity_references.gd` carries the same URLs as
inert provenance strings. There is no network client anywhere in `godot/` — these are records,
not fetches.

- **Force diagrams (RideForcesDB)** — Falcon's Flight `?id=4804`; Tormenta `?id=6369` and
  `?id=6383`. All three are `corroborative`; 4804 is flagged unreliable and cannot promote
  alone. `docs/evidence/fidelity/catalog-review.md` records that raw acquisition was blocked.
  Local CSV exports for the diagnostic overlay are hash-pinned in
  `rfdb-local-overlay-manifest.json` and supplied via `RFDB_4804_CSV` / `RFDB_6383_CSV`.
- **POV video (YouTube)** — nine sources: Falcon's Flight forward `cUURkqyn4Zs`, backward
  `J54WKu2nU6o`, `poco8rOnW18`, `sdXGD9kMR7s`, CGI `NFVNGgwZk3c`; Tormenta forward
  `AHjk2R4da_I`; CoasterTalk continuous `0UaOSBGSx20` and edited `seNRpi4wP-s`; I305 overlay
  `wX7uHKj-Ujc`. Four are `corroborative`, three `observation_only`, four `review_pending`.
  No frames, audio, or copyrighted content are committed — metadata and timestamps only.

**None is `executable`**, which is exactly why the audit emits `no-eligible-finding`. Grounding
any issue above in measurement means promoting a source through
`docs/evidence/fidelity/catalog-review.md` and the four-part bar in *Promoting a finding to a
hard gate* — the links being present is not the same as the evidence being usable.

## Recommended approach

Compare the ride element by element against real high-thrill coasters — not just the two
named references. Use RideForcesDB (raw per-recording traces are decodable; multiple
recordings of one ride can be cross-checked) and similar sources, plus POV video extraction
and analysis, to ground every element class in measured reality and in how the real thing
*feels*. Discovery is the point: ride it, trace it, and chase whatever looks or feels wrong,
whether or not it is on this list.
