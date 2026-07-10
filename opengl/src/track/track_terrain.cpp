// Track V2 — immutable terrain queries and escarpment scan
// (docs/TERRAIN_CONTRACT.md). Terrain belongs to the world generator; this
// module only READS it. Cut/tunnel spans are recorded by validation for the
// host to carve at meshing time — the heightfield datum is never mutated.
//
// The host binds TerrainQuery.height to its groundTopAt(x,z) (environment.cpp)
// at adapter-switch time; the test harness binds synthetic heightfields.
#include "track_math.h"

namespace v2 {

// Migration step 4: scan the seeded terrain for natural escarpments — long,
// warped ridges with varying crest height and a broad foot (never radial
// mesas, cylinders or track-aligned spikes) — and return candidate cliff-dive
// sites with their raw drop heights. A cliff dive is OMITTED when no
// qualifying site exists; there is no fallback tower (SHAPES.md, hard rule).
std::vector<EscarpmentSite> scanEscarpments(const TerrainQuery& terrain,
                                            Vector3 center, float radiusM) {
    (void)terrain;
    (void)center;
    (void)radiusM;
    return {}; // not implemented until step 4 — callers must treat "no sites"
               // as "no cliff dive this ride", which is the correct fallback.
}

} // namespace v2
