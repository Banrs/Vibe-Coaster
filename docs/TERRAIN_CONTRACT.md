# Terrain contract for Track V2

Terrain belongs to the world generator; track geometry belongs to the route builder. Neither may
silently edit the other after its own generation stage.

## World terrain

- Use a dry, low-relief plains baseline with local hills, valleys, forests, and rarer mountain
  regions. Water occupies low basins rather than setting the effective height of the whole world.
- A natural escarpment is a long, warped ridge with varying crest height, broken erosion and a
  broad foot. It is not a radial mesa, cylinder, isolated spike, or track-aligned wall.
- Terrain is seeded from world coordinates and generated before route planning. It is never
  mutated when a ride beat is selected.

## Route interaction

1. The planner queries terrain to choose a broad route and candidate escarpments.
2. A primitive is authored from its planned entry and exit pose, independent of individual terrain
   samples.
3. Clearance validation may accept the primitive as designed. **If it would intersect terrain, a
   shallow cut/tunnel is the default, preferred response — not a last resort.** Only reject and
   replan (choose a different beat/primitive/route) when a cut/tunnel genuinely can't resolve the
   conflict (the encroachment is too large, or the terrain there is structurally implausible to
   tunnel through). **It may never flatten, lift, shorten, re-tag, or introduce a compensating
   kink into individual samples to dodge terrain** — the primitive's designed smooth shape is
   never sacrificed for clearance; cut through the ground instead of bending the track around it.
4. A cliff dive is omitted if the selected natural ridge and adjacent valley cannot support the
   designed approach, drop, and pull-out. There is no artificial fallback cliff.

**Historical note, read before implementing clearance validation**: an earlier version of this
generator had a severe bug where track could dive to -100 m or worse — a real clearance failure.
The fix for that must not be a generator that's *afraid* of ever carving into terrain, because
that produces the opposite failure: track that abandons its intended shape (small vertical kinks,
overly conservative routing that always goes around/over rather than through) purely to avoid any
ground contact. Cutting a tunnel is a normal, correct, expected outcome — not something to avoid.
Use the cut/tunnel-length and unsupported-span limits in the Validation section below to keep cuts
*bounded and safe*, not to justify avoiding them. If validation reports near-zero cut/tunnel length
across many seeds, that's as much a red flag as excessive unsupported spans — it likely means the
system is kinking or over-rejecting instead of cutting.

## Validation

Report these separately for every fixed seed:

- terrain height distribution and dry-land / water coverage;
- escarpment extent, crest variation, and adjacent valley depth;
- route clearance, cut/tunnel length, and unsupported spans;
- **cut/tunnel usage rate across seeds** — report it explicitly, don't just fold it into a pass/
  fail gate. Near-zero usage across many seeds is a signal the generator is over-rejecting or
  kinking instead of cutting (see the historical note above), just as excessive unsupported-span
  length signals unsafe cuts;
- terrain mutations (must be zero).
