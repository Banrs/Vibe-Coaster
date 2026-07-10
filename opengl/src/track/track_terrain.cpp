// Track V2 — immutable terrain queries and escarpment scan
// (docs/TERRAIN_CONTRACT.md). Terrain belongs to the world generator; this
// module only READS it. Cut/tunnel spans are recorded by validation for the
// host to carve at meshing time — the heightfield datum is never mutated.
//
// The host binds TerrainQuery.height to groundTopAt (terrain_field.h) at
// adapter-switch time; the harness binds the same function directly.
#include <algorithm>
#include <map>

#include "track_math.h"

namespace v2 {

// ---------------------------------------------------------------------------
// Escarpment scan (migration step 4). Finds natural cliff-dive sites: cells
// whose ground drops sharply toward one side, clustered into ridge lines.
// Contract guards (TERRAIN_CONTRACT.md "World terrain"):
//  - a qualifying site belongs to a LONG ridge cluster (>= kMinRidgeLen of
//    connected edge cells), which rejects isolated spikes and small mesas;
//  - the adjacent valley must offer a usably flat pull-out zone;
//  - the scan never writes terrain; a ride with no qualifying site simply
//    has no cliff dive (no fallback tower, SHAPES.md).
// ---------------------------------------------------------------------------
namespace {
constexpr float kGrid = 8.0f;        // scan cell size
constexpr float kProbe = 36.0f;      // drop-test look-ahead
constexpr float kMinDrop = 55.0f;    // qualifying edge drop at the probe
constexpr float kMinRidgeLen = 80.0f; // cluster extent guard (spike/mesa filter)
constexpr float kValleyWalk = 170.0f; // how far past the edge to hunt the floor
constexpr float kPulloutSpan = 60.0f; // flat-zone length required past the floor
constexpr float kPulloutRough = 18.0f; // max floor variation over that span
} // namespace

std::vector<EscarpmentSite> scanEscarpments(const TerrainQuery& t, Vector3 center,
                                            float radiusM) {
    const int n = (int)(radiusM / kGrid);
    struct Edge { float x, z, h, drop, dirX, dirZ; };
    std::map<std::pair<int, int>, Edge> edges;

    for (int gz = -n; gz <= n; gz++) {
        for (int gx = -n; gx <= n; gx++) {
            if ((float)(gx * gx + gz * gz) * kGrid * kGrid > radiusM * radiusM) continue;
            float x = center.x + gx * kGrid, z = center.z + gz * kGrid;
            float h = t.height(x, z);
            float bestDrop = 0.0f, bx = 0.0f, bz = 0.0f;
            for (int d = 0; d < 16; d++) {
                float a = (float)d * (2.0f * kPi / 16.0f);
                float dx = sinf(a), dz = cosf(a);
                float drop = h - t.height(x + dx * kProbe, z + dz * kProbe);
                if (drop > bestDrop) { bestDrop = drop; bx = dx; bz = dz; }
            }
            if (bestDrop >= kMinDrop)
                edges[{gx, gz}] = Edge{x, z, h, bestDrop, bx, bz};
        }
    }

    // Flood-fill clusters over 8-neighbour adjacency.
    std::vector<EscarpmentSite> sites;
    std::map<std::pair<int, int>, bool> seen;
    for (auto& kv : edges) {
        if (seen[kv.first]) continue;
        std::vector<const Edge*> cluster;
        std::vector<std::pair<int, int>> stack{kv.first};
        seen[kv.first] = true;
        while (!stack.empty()) {
            auto c = stack.back();
            stack.pop_back();
            cluster.push_back(&edges[c]);
            for (int dz = -1; dz <= 1; dz++)
                for (int dx = -1; dx <= 1; dx++) {
                    std::pair<int, int> nb{c.first + dx, c.second + dz};
                    auto it = edges.find(nb);
                    if (it != edges.end() && !seen[nb]) {
                        seen[nb] = true;
                        stack.push_back(nb);
                    }
                }
        }

        // Ridge length: cluster extent along the direction perpendicular to
        // the mean drop direction (i.e. along the crest line).
        float mdx = 0, mdz = 0;
        for (const Edge* e : cluster) { mdx += e->dirX; mdz += e->dirZ; }
        float ml = sqrtf(mdx * mdx + mdz * mdz);
        if (ml < 1e-3f) continue; // incoherent drop directions: not a ridge line
        mdx /= ml; mdz /= ml;
        float rx = mdz, rz = -mdx; // along-crest axis
        float lo = 1e9f, hi = -1e9f, crestLo = 1e9f, crestHi = -1e9f;
        const Edge* best = cluster[0];
        for (const Edge* e : cluster) {
            float along = (e->x - center.x) * rx + (e->z - center.z) * rz;
            lo = fminf(lo, along); hi = fmaxf(hi, along);
            crestLo = fminf(crestLo, e->h); crestHi = fmaxf(crestHi, e->h);
            if (e->drop > best->drop) best = e;
        }
        if (hi - lo < kMinRidgeLen) continue; // spike / small mesa: rejected

        // Valley floor + pull-out flatness along the best cell's dive line.
        float floorY = 1e9f, floorAt = 0.0f;
        for (float w = kProbe; w <= kValleyWalk; w += 6.0f) {
            float g = t.height(best->x + best->dirX * w, best->z + best->dirZ * w);
            if (g < floorY) { floorY = g; floorAt = w; }
        }
        float rough = 0.0f;
        for (float w = 0.0f; w <= kPulloutSpan; w += 6.0f) {
            float g = t.height(best->x + best->dirX * (floorAt + w),
                               best->z + best->dirZ * (floorAt + w));
            rough = fmaxf(rough, fabsf(g - floorY));
        }
        if (rough > kPulloutRough) continue; // no usable pull-out zone

        EscarpmentSite site;
        site.crest = Vector3{best->x, best->h, best->z};
        site.heading = atan2f(best->dirX, best->dirZ); // dive direction
        site.crestY = best->h;
        site.valleyY = floorY;
        site.dropHeight = best->h - floorY;
        sites.push_back(site);
    }

    std::sort(sites.begin(), sites.end(),
              [](const EscarpmentSite& a, const EscarpmentSite& b) {
                  return a.dropHeight > b.dropHeight;
              });
    return sites;
}

// ---------------------------------------------------------------------------
// Clearance policy (TERRAIN_CONTRACT.md route-interaction rule 3): a shallow
// cut/tunnel is the DEFAULT, preferred response to encroachment; reject and
// replan only when a cut can't plausibly resolve it. The limits keep cuts
// bounded and safe — they exist to size cuts, not to justify avoiding them.
// Limits are PROVISIONAL design values (no real-world source prescribes
// them; TERRAIN_CONTRACT.md only requires that they exist and are reported).
// ---------------------------------------------------------------------------
ClearanceDecision clearanceDecision(const ValidationReport& rep,
                                    const ClearanceLimits& lim) {
    bool anyCut = false;
    for (const ClearanceSpan& c : rep.clearance) {
        if (c.kind == ClearanceSpan::Kind::LowClearance ||
            c.kind == ClearanceSpan::Kind::UnsupportedSpan)
            continue;
        anyCut = true;
        if (c.s1 - c.s0 > lim.maxCutLen) return ClearanceDecision::Reject;
        if (c.maxDepth > lim.maxTunnelDepth) return ClearanceDecision::Reject;
    }
    return anyCut ? ClearanceDecision::AcceptWithCuts : ClearanceDecision::Accept;
}

} // namespace v2
