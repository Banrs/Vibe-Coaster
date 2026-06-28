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

    // SCALE matched 1:1 to the software renderer (src/main.cpp ~2578-2601): true 1m-block scale.
    const float RAIL_GAUGE = 0.55f;  // lateral half-spacing of running rails (~1.1m gauge)
    const float RAIL_R     = 0.09f;  // rail beam half-thickness (0.18 full)
    const float SPINE_DROP = 0.30f;  // spine centre below the rail plane

    float3 railCol   = vec3(0.82f, 0.83f, 0.86f);  // light steel rails
    float3 spineSteel= vec3(0.17f, 0.18f, 0.22f);  // dark structural box-beam tube (un-powered)
    float3 spineHot  = vec3(1.00f, 0.45f, 0.10f);  // orange boost cue (LAUNCH/BOOST only)
    float3 tieCol    = vec3(0.38f, 0.39f, 0.42f);  // steel cross ties
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

        // Box-beam spine under the rail plane, following the spline. Dark structural
        // tube, turning orange ONLY on powered sections (LAUNCH/BOOST) as a boost cue.
        int   ki   = (int)(u + 0.5f);
        if (ki < 0) ki = 0; if (ki >= co.nFull) ki = co.nFull - 1;
        int   kind = co.cps[ki].kind;
        bool  powered = (kind == 9 || kind == 11);   // M_LAUNCH, M_BOOST
        float3 spineCol = powered ? spineHot : spineSteel;
        float spW = powered ? 0.19f : 0.15f;   // half-width  (0.38 / 0.30 full)
        float spH = powered ? 0.27f : 0.23f;   // half-height (0.54 / 0.46 full)
        float3 spineC = c - up * SPINE_DROP;
        float spineHalfF = length(co.pos(u + STEP) - c) * 0.6f;
        pushBox(out, spineC, lat, up, fwd, spW, spH, spineHalfF, spineCol);

        // Cross ties spanning the two rails every few steps.
        if (segCount % tieEvery == 0) {
            float3 tieC = c - up * 0.17f;
            pushBox(out, tieC, lat, up, fwd, 0.675f, 0.07f, 0.225f, tieCol);
        }
    }

    // --- HELIX central tower (port of src/main.cpp): one open 4-post lattice tower per
    // contiguous helix run, coils tie in via radial struts so legs never punch down
    // through the stacked coils. axis = centroid of the whole run.
    float3 hxAxis = vec3(0,0,0); int hxN = 0; float hxTopY = -1e9f; int hxSeed = -1;
    for (int i = 4; i < last; i++)
        if (co.cps[i].kind == 10) { hxSeed = i; break; }     // M_HELIX
    if (hxSeed >= 0) {
        int a = hxSeed, b = hxSeed;
        while (a > 1 && co.cps[a - 1].kind == 10) a--;
        while (b + 2 < co.nFull && co.cps[b + 1].kind == 10) b++;
        for (int i = a; i <= b; i++) {
            hxAxis.x += co.cps[i].p.x; hxAxis.z += co.cps[i].p.z; hxN++;
            if (co.cps[i].p.y > hxTopY) hxTopY = co.cps[i].p.y;
        }
    }
    bool haveHx = hxN >= 4;
    if (haveHx) {
        hxAxis.x /= hxN; hxAxis.z /= hxN;
        float gAxis = groundTopAt(hxAxis.x, hxAxis.z), th = hxTopY - gAxis;
        if (th > 3.0f && inClip(hxAxis)) {
            const float tw = 1.4f;
            for (float sx = -1.0f; sx <= 1.0f; sx += 2.0f)
                for (float sz = -1.0f; sz <= 1.0f; sz += 2.0f)
                    pushBox(out, vec3(hxAxis.x + sx*tw, gAxis + th*0.5f, hxAxis.z + sz*tw),
                            vec3(1,0,0), vec3(0,1,0), vec3(0,0,1), 0.17f, th*0.5f, 0.17f, supCol);
            for (float ry = gAxis + 8.0f; ry < hxTopY - 2.0f; ry += 9.0f)
                pushBox(out, vec3(hxAxis.x, ry, hxAxis.z), vec3(1,0,0), vec3(0,1,0), vec3(0,0,1),
                        tw + 0.2f, 0.16f, tw + 0.2f, supCol);
        }
    }

    // --- Support bents (track-aligned A-frame V), ported 1:1 from src/main.cpp drawVBent.
    // Spaced by WORLD ARC LENGTH (SUP_SP metres) so bents land evenly and never overlap
    // regardless of control-point density. Each leg is one solid beam raking from a node
    // under the spine out to a foot on the terrain; tall bents get trussed.
    const float SUP_SP = 9.0f;
    float arcPrev = 0.0f, arcCur = 0.0f;
    float3 lastP = co.cps[4].p;
    for (int i = 4; i < last; i++) {
        const CP& cp = co.cps[i];
        float3 p  = cp.p;
        arcPrev = arcCur;
        arcCur += length(p - lastP);
        lastP = p;
        int kn = cp.kind;
        float3 fwd = co.tangent((float)i);
        float3 up  = orthoUp(fwd, cp.up);
        // skip the inverted half of loops/rolls/etc (overhead spans get no ground leg)
        bool inversionElem = (kn == 5 || kn == 6 || kn == 12 || kn == 17 || kn == 18 ||
                              kn == 19 || kn == 21 || kn == 20 || kn == 22 || kn == 24);
        if (inversionElem && cp.up.y < 0.35f) continue;
        if (!inClip(p)) continue;                            // clip supports to terrain ring
        float gC = groundTopAt(p.x, p.z);
        if (p.y - gC < 1.5f) continue;

        // HELIX coils tie radially into the central tower (no individual legs).
        if (kn == 10 && haveHx) {
            pushBox(out, vec3((p.x + hxAxis.x)*0.5f, p.y - 0.6f, (p.z + hxAxis.z)*0.5f),
                    vec3(1,0,0), vec3(0,1,0), vec3(0,0,1),
                    (fabsf(hxAxis.x - p.x) + 0.4f)*0.5f, 0.15f,
                    (fabsf(hxAxis.z - p.z) + 0.4f)*0.5f, supCol);
            continue;
        }

        // arc-length spacing: a bent only where this cp crosses a SUP_SP boundary
        if (floorf(arcCur / SUP_SP) == floorf(arcPrev / SUP_SP)) continue;

        float topY = p.y - 0.5f;                             // apex flush to the spine underside
        float hgt  = topY - gC;
        if (hgt < 1.0f) continue;

        float vary = hashf((int)floorf(p.x * 0.5f), (int)floorf(p.z * 0.5f));
        float baseHalf = t_Clamp(hgt * (0.17f + vary * 0.07f), 1.5f, 5.5f);
        float legR     = t_Clamp(0.30f + hgt * 0.0045f, 0.30f, 0.55f);
        float topHalf  = 0.22f;
        float3 rRight = normalize(cross(up, fwd));
        float3 latH   = normalize(vec3(rRight.x, 0.0f, rRight.z));
        float3 node = vec3(p.x, topY, p.z) - up * 0.58f;
        float3 tops[2], feet[2]; int si = 0;
        for (float sgn = -1.0f; sgn <= 1.0f; sgn += 2.0f) {
            float3 top  = node + rRight * (sgn * topHalf);
            float bx = p.x + latH.x * sgn * baseHalf, bz = p.z + latH.z * sgn * baseHalf;
            float3 foot = vec3(bx, groundTopAt(bx, bz), bz);
            tops[si] = top; feet[si] = foot; si++;
            float3 d = foot - top; float L = length(d);
            if (L < 0.3f) continue;
            float3 f  = d * (1.0f / L);
            float3 u2 = orthoUp(f, vec3(0,1,0));
            float3 r2 = normalize(cross(u2, f));
            pushBox(out, (top + foot) * 0.5f, r2, u2, f, legR, legR, L * 0.5f, supCol);
        }
        auto strut = [&](float3 a, float3 b, float r) {
            float3 d = b - a; float L = length(d);
            if (L < 0.3f) return;
            float3 f = d * (1.0f / L);
            float3 u2 = orthoUp(f, vec3(0,1,0));
            float3 r2 = normalize(cross(u2, f));
            pushBox(out, (a + b) * 0.5f, r2, u2, f, r, r, L * 0.5f, supCol);
        };
        if (hgt > 14.0f) {
            int levels = (int)t_Clamp(hgt / 16.0f, 1.0f, 4.0f);
            float3 prevL{}, prevR{}; bool have = false;
            for (int k = 1; k <= levels; k++) {
                float fr = (float)k / (float)(levels + 1);
                float3 L = tops[0] + (feet[0] - tops[0]) * fr;
                float3 R = tops[1] + (feet[1] - tops[1]) * fr;
                strut(L, R, legR * 0.7f);
                if (have && hgt > 22.0f) { strut(prevL, R, legR * 0.5f); strut(prevR, L, legR * 0.5f); }
                prevL = L; prevR = R; have = true;
            }
        }
        pushBox(out, node, rRight, up, fwd, 0.28f, 0.28f, 0.50f, supCol);
    }

    // Train: a coupled consist of cars near the start of the circuit. Cars are
    // spaced by real arc length (~CAR_PITCH metres) so they sit nose-to-tail
    // instead of being scattered along the spline.
    float3 bodyCol   = vec3(0.10f, 0.45f, 0.85f);
    float3 accentCol = vec3(0.95f, 0.85f, 0.20f);
    const float CAR_HALF_LEN = 1.55f;       // half length of a car body (m)
    const float CAR_PITCH    = 4.2f;        // centre-to-centre spacing (m)
    float u = trainU;                       // train rides at the camera parameter
    for (int car = 0; car < 5; car++) {
        if (u >= uMax - 1.0f || u < 4.0f) break;
        float3 c   = co.pos(u);
        float3 fwd = co.tangent(u);
        float3 up  = orthoUp(fwd, co.upAt(u));
        float3 lat = normalize(cross(up, fwd));
        float3 carC = c + up * 0.46f;       // sit just above the rail plane
        pushBox(out, carC, lat, up, fwd, 0.70f, 0.40f, CAR_HALF_LEN, car == 0 ? accentCol : bodyCol);
        // a small accent stripe / roof block
        pushBox(out, carC + up * 0.40f, lat, up, fwd, 0.52f, 0.16f, CAR_HALF_LEN * 0.82f, accentCol);
        // advance u by ~CAR_PITCH metres of arc length; cars trail BEHIND the lead.
        float mpu = length(co.pos(u + 0.1f) - co.pos(u - 0.1f)) / 0.2f;
        u -= CAR_PITCH / fmaxf(mpu, 1e-3f);
    }
}
