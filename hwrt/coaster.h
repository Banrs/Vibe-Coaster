// Loads the exported coaster spline (track.txt) and builds ray-traceable box
// geometry: two running rails, cross ties, a colored box-beam spine, support
// posts to the terrain, and a few train cars. All as triangles appended into
// the same vertex buffer the terrain uses.
#pragma once
#include "math.h"
#include "terrain.h"  // MeshVertex, pushQuad, groundTopAt
#include <vector>
#include <cstdio>

struct CP {
    float3 p;    // control point
    float3 up;   // rider-up
    int    kind; // SegMode tag
};

// Catmull-Rom (centripetal), ported VERBATIM from main.cpp catmull().
static inline float3 c_vlerp(float3 a, float3 b, float s) {
    return a + (b - a) * s;
}
static float3 catmull(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    const float A = 0.5f;
    float t0 = 0.0f;
    float t1 = t0 + powf(fmaxf(length(p1 - p0), 1e-3f), A);
    float t2 = t1 + powf(fmaxf(length(p2 - p1), 1e-3f), A);
    float t3 = t2 + powf(fmaxf(length(p3 - p2), 1e-3f), A);
    float tt = t1 + (t2 - t1) * t;
    float3 A1 = c_vlerp(p0, p1, (tt - t0) / (t1 - t0));
    float3 A2 = c_vlerp(p1, p2, (tt - t1) / (t2 - t1));
    float3 A3 = c_vlerp(p2, p3, (tt - t2) / (t3 - t2));
    float3 B1 = c_vlerp(A1, A2, (tt - t0) / (t2 - t0));
    float3 B2 = c_vlerp(A2, A3, (tt - t1) / (t3 - t1));
    return c_vlerp(B1, B2, (tt - t1) / (t2 - t1));
}

struct Coaster {
    std::vector<CP> cps;
    int   nFull;       // total points loaded
    int   nRender;     // how many points to actually build geometry for

    bool load(const char* path) {
        FILE* fp = fopen(path, "r");
        if (!fp) return false;
        CP c;
        while (fscanf(fp, "%f %f %f %f %f %f %d",
                      &c.p.x, &c.p.y, &c.p.z, &c.up.x, &c.up.y, &c.up.z, &c.kind) == 7)
            cps.push_back(c);
        fclose(fp);
        nFull = (int)cps.size();
        return nFull >= 8;
    }

    float3 pos(float u) const {
        int k = (int)u;
        if (k > (int)cps.size() - 4) k = (int)cps.size() - 4;
        if (k < 0) k = 0;
        return catmull(cps[k].p, cps[k+1].p, cps[k+2].p, cps[k+3].p, u - k);
    }
    float3 upAt(float u) const {
        int k = (int)u;
        if (k > (int)cps.size() - 4) k = (int)cps.size() - 4;
        if (k < 0) k = 0;
        float3 a = catmull(cps[k].up, cps[k+1].up, cps[k+2].up, cps[k+3].up, u - k);
        if (length(a) < 1e-4f) return vec3(0,1,0);
        return normalize(a);
    }
    float3 tangent(float u) const {
        float3 d = pos(u + 0.05f) - pos(u - 0.05f);
        float L = length(d);
        if (L < 1e-5f) return vec3(0,0,1);
        return d * (1.0f / L);
    }
};

// Orthonormal up from a forward + up-hint (ported from main.cpp orthoUp).
static float3 orthoUp(float3 fwd, float3 hint) {
    float3 up = hint - fwd * dot(hint, fwd);
    if (length(up) < 1e-3f) {
        float3 ref = (fabsf(fwd.y) < 0.9f) ? vec3(0,1,0) : vec3(1,0,0);
        up = ref - fwd * dot(ref, fwd);
    }
    return normalize(up);
}

// Append an oriented box: centered at `c`, half-extents (hr along right,
// hu along up, hf along fwd). The three axes must be orthonormal.
static void pushBox(std::vector<MeshVertex>& out, float3 c,
                    float3 right, float3 up, float3 fwd,
                    float hr, float hu, float hf, float3 albedo) {
    float3 R = right * hr, U = up * hu, F = fwd * hf;
    // 8 corners
    float3 p[8] = {
        c - R - U - F, c + R - U - F, c + R + U - F, c - R + U - F, // back face (-F)
        c - R - U + F, c + R - U + F, c + R + U + F, c - R + U + F, // front face (+F)
    };
    auto quad = [&](int a, int b, int d, int e, float3 n) {
        pushQuad(out, p[a], p[b], p[d], p[e], n, albedo);
    };
    quad(0,3,2,1, normalize(fwd * -1.0f)); // -F
    quad(4,5,6,7, normalize(fwd));         // +F
    quad(0,1,5,4, normalize(up * -1.0f));  // -U (bottom)
    quad(3,7,6,2, normalize(up));          // +U (top)
    quad(0,4,7,3, normalize(right * -1.0f));// -R
    quad(1,2,6,5, normalize(right));       // +R
}

// Build all coaster geometry into `out`. Renders points [4, nRender] of the
// spline (skip the first few so catmull has neighbors).
// clipC / clipR (optional): if clipR > 0, only emit track within a square of
// half-extent clipR centred at clipC.xz (so track never floats past the terrain
// edge in the benchmark's camera-following 1m terrain ring).
static void buildCoaster(const Coaster& co, std::vector<MeshVertex>& out, int nRender,
                         float3 clipC = vec3(0,0,0), float clipR = 0.0f,
                         float trainU = 6.0f) {
    auto inClip = [&](float3 p) {
        return clipR <= 0.0f ||
               (fabsf(p.x - clipC.x) <= clipR && fabsf(p.z - clipC.z) <= clipR);
    };
    int last = nRender;
    if (last > co.nFull - 3) last = co.nFull - 3;

    const float RAIL_GAUGE = 1.3f;   // lateral half-spacing of running rails
    const float RAIL_R     = 0.18f;  // rail beam half-thickness
    const float SPINE_DROP = 1.0f;   // spine sits this far below the rail plane
    const float SPINE_HALF = 0.55f;  // spine box half-size

    float3 railCol   = vec3(0.82f, 0.83f, 0.86f);  // light steel rails
    float3 spineSteel= vec3(0.46f, 0.48f, 0.52f);  // iron box-beam spine (un-powered)
    float3 spineHot  = vec3(1.00f, 0.45f, 0.10f);  // orange boost cue (LAUNCH/BOOST only)
    float3 tieCol    = vec3(0.30f, 0.31f, 0.34f);  // dark cross ties
    float3 supCol    = vec3(0.46f, 0.48f, 0.52f);  // steel support bents

    // Fine stepping along u for smooth rails/spine.
    const float STEP = 0.20f;          // u increment between rail box segments
    int tieEvery = 3;                  // place a tie every Nth rail segment
    int segCount = 0;

    float uMax = (float)last;
    float3 prevL{}, prevR{}; bool havePrev = false;

    for (float u = 4.0f; u <= uMax; u += STEP, segCount++) {
        float3 c   = co.pos(u);
        if (!inClip(c)) { havePrev = false; continue; }   // clip track to terrain ring
        float3 fwd = co.tangent(u);
        float3 up  = orthoUp(fwd, co.upAt(u));
        float3 lat = normalize(cross(up, fwd)); // lateral (right of travel)

        float3 railL = c + lat * RAIL_GAUGE;
        float3 railR = c - lat * RAIL_GAUGE;

        // Rail box segments connecting prev->cur (a short box per step).
        if (havePrev) {
            auto railSeg = [&](float3 a, float3 b) {
                float3 d = b - a; float L = length(d);
                if (L < 1e-4f) return;
                float3 f = d * (1.0f / L);
                float3 u2 = orthoUp(f, up);
                float3 r2 = normalize(cross(u2, f));
                float3 mid = (a + b) * 0.5f;
                pushBox(out, mid, r2, u2, f, RAIL_R, RAIL_R, L * 0.5f, railCol);
            };
            railSeg(prevL, railL);
            railSeg(prevR, railR);
        }
        prevL = railL; prevR = railR; havePrev = true;

        // Box-beam spine under the rail plane, following the spline. Iron grey,
        // turning orange ONLY on powered sections (LAUNCH/BOOST) as a boost cue.
        // Half-length along fwd covers the gap to the next step (rails are ~14m
        // apart per segment, STEP=0.2 -> ~2.8m between spine boxes).
        int   ki   = (int)(u + 0.5f);
        if (ki < 0) ki = 0; if (ki >= co.nFull) ki = co.nFull - 1;
        int   kind = co.cps[ki].kind;
        bool  powered = (kind == 9 || kind == 11);   // M_LAUNCH, M_BOOST
        float3 spineCol = powered ? spineHot : spineSteel;
        float3 spineC = c - up * SPINE_DROP;
        float spineHalfF = length(co.pos(u + STEP) - c) * 0.6f;
        pushBox(out, spineC, lat, up, fwd, SPINE_HALF, SPINE_HALF, spineHalfF, spineCol);

        // Cross ties spanning the two rails every few steps.
        if (segCount % tieEvery == 0) {
            float3 tieC = c - up * (SPINE_DROP * 0.4f);
            pushBox(out, tieC, lat, up, fwd, RAIL_GAUGE + 0.25f, 0.15f, 0.30f, tieCol);
        }
    }

    // Support bents (A-frame V), ported from the sim's drawVBent: two raked legs
    // splay from a node tucked under the spine out to feet on the terrain. Tops
    // and feet share one lateral sense (rRight) so the legs never cross into an X;
    // the node sits just inside the spine underside. Skip inverted spans.
    const float NODE_DROP = 1.5f;     // node centre below the rail plane (under the spine box)
    for (int i = 5; i < last; i += 2) {
        const CP& cp = co.cps[i];
        float3 fwd = co.tangent((float)i);
        float3 up  = orthoUp(fwd, cp.up);
        if (up.y < 0.30f) continue;                          // inverted span -> no ground support
        float3 p  = cp.p;
        if (!inClip(p)) continue;                            // clip supports to terrain ring
        float3 node = p - up * NODE_DROP;
        float gC = groundTopAt(p.x, p.z);
        float hgt = node.y - gC;
        if (hgt < 3.0f) continue;                            // already near ground
        float3 rRight = normalize(cross(up, fwd));           // rail lateral (banks with the track)
        float3 latH   = normalize(vec3(rRight.x, 0.0f, rRight.z));  // ground projection: feet splay here
        float baseHalf = t_Clamp(hgt * 0.20f, 1.8f, 5.5f);   // ground splay grows with height
        float topHalf  = 0.34f;                              // leg tops just inside the node
        for (float s = -1.0f; s <= 1.0f; s += 2.0f) {
            float3 top  = node + rRight * (s * topHalf);
            float3 foot = vec3(p.x + latH.x * s * baseHalf, 0.0f, p.z + latH.z * s * baseHalf);
            foot.y = groundTopAt(foot.x, foot.z);
            float3 d = foot - top; float L = length(d);
            if (L < 0.5f) continue;
            float3 f  = d * (1.0f / L);
            float3 u2 = orthoUp(f, vec3(0,1,0));
            float3 r2 = normalize(cross(u2, f));
            pushBox(out, (top + foot) * 0.5f, r2, u2, f, 0.40f, 0.40f, L * 0.5f, supCol);
        }
        // square node block where the legs converge, oriented to the rail frame.
        pushBox(out, node, rRight, up, fwd, 0.55f, 0.55f, 0.55f, supCol);
    }

    // Train: a coupled consist of cars near the start of the circuit. Cars are
    // spaced by real arc length (~CAR_PITCH metres) so they sit nose-to-tail
    // instead of being scattered along the spline.
    float3 bodyCol   = vec3(0.10f, 0.45f, 0.85f);
    float3 accentCol = vec3(0.95f, 0.85f, 0.20f);
    const float CAR_HALF_LEN = 2.0f;        // half length of a car body (m)
    const float CAR_PITCH    = 4.6f;        // centre-to-centre spacing (m)
    float u = trainU;                       // train rides at the camera parameter
    for (int car = 0; car < 5; car++) {
        if (u >= uMax - 1.0f || u < 4.0f) break;
        float3 c   = co.pos(u);
        float3 fwd = co.tangent(u);
        float3 up  = orthoUp(fwd, co.upAt(u));
        float3 lat = normalize(cross(up, fwd));
        float3 carC = c + up * 0.7f;        // sit on top of the rails
        pushBox(out, carC, lat, up, fwd, 1.1f, 0.7f, CAR_HALF_LEN, car == 0 ? accentCol : bodyCol);
        // a small accent stripe / roof block
        pushBox(out, carC + up * 0.8f, lat, up, fwd, 0.8f, 0.25f, CAR_HALF_LEN * 0.82f, accentCol);
        // advance u by ~CAR_PITCH metres of arc length; cars trail BEHIND the lead.
        float mpu = length(co.pos(u + 0.1f) - co.pos(u - 0.1f)) / 0.2f;
        u -= CAR_PITCH / fmaxf(mpu, 1e-3f);
    }
}
