// Track V2 — renderer/physics-facing adapter. Serves the host's existing
// Track method surface from a finished dense-sample Route. See the TrackV2
// declaration in track_types.h for the u-parameter and step-6 notes.
#include "track_math.h"

void TrackV2::build(uint32_t seed) {
    route = terrain.height ? v2::buildRide(seed, terrain)
                           : v2::buildSmokeRoute(seed); // harness fallback
    size_t n = route.samples.size();
    cp.resize(n);
    up.resize(n);
    kind.resize(n);
    chainf.resize(n);
    arc.resize(n);
    for (size_t i = 0; i < n; i++) {
        const v2::Sample& s = route.samples[i];
        cp[i] = s.pos;
        up[i] = s.up;
        kind[i] = (unsigned char)s.tag;
        chainf[i] = s.chain ? 1 : 0;
        arc[i] = s.s;
    }
    if (n > 0) {
        startPos = route.samples[0].pos;
        startYaw = route.samples[0].yaw;
    }
}

v2::Sample TrackV2::sampleAt(float u) const {
    size_t n = route.samples.size();
    if (n == 0) return v2::Sample{};
    if (n == 1) return route.samples[0];

    float maxIdx = (float)(n - 1);
    if (route.closed) {
        float span = (float)n; // seam interval [n-1 -> 0] counts as one step
        u = fmodf(u, span);
        if (u < 0.0f) u += span;
    } else {
        if (u < 0.0f) u = 0.0f;
        if (u > maxIdx) u = maxIdx;
    }
    size_t i = (size_t)u;
    float f = u - (float)i;
    const v2::Sample& a = route.samples[i];
    const v2::Sample& b = route.samples[(i + 1 < n) ? i + 1 : 0];

    // Dense 1 m samples: linear position + renormalized frame interpolation is
    // well inside rendering/physics tolerance (chord error < k*ds^2/8, ~3 mm
    // at the tightest curvature this game builds). Revisit at the step-6
    // visual regression if faceting ever shows.
    v2::Sample out = a;
    out.pos = Vector3Lerp(a.pos, b.pos, f);
    out.tan = Vector3Normalize(Vector3Lerp(a.tan, b.tan, f));
    Vector3 uv = Vector3Lerp(a.up, b.up, f);
    float ul = Vector3Length(uv);
    out.up = (ul > 1e-4f) ? Vector3Scale(uv, 1.0f / ul) : Vector3{0, 1, 0};
    out.s = a.s + f * route.ds;
    return out;
}

Vector3 TrackV2::pos(float u) const { return sampleAt(u).pos; }
Vector3 TrackV2::tangent(float u) const { return sampleAt(u).tan; }
Vector3 TrackV2::upAt(float u) const { return sampleAt(u).up; }

unsigned char TrackV2::tagAt(float u) const {
    size_t n = route.samples.size();
    if (n == 0) return 0;
    float span = route.closed ? (float)n : (float)(n - 1);
    if (route.closed) {
        u = fmodf(u, span);
        if (u < 0.0f) u += span;
    } else {
        if (u < 0.0f) u = 0.0f;
        if (u > span) u = span;
    }
    size_t i = (size_t)u;
    if (i >= n) i = n - 1;
    return (unsigned char)route.samples[i].tag;
}

bool TrackV2::chainAt(float u) const {
    size_t n = route.samples.size();
    if (n == 0) return false;
    float span = route.closed ? (float)n : (float)(n - 1);
    if (route.closed) {
        u = fmodf(u, span);
        if (u < 0.0f) u += span;
    } else {
        if (u < 0.0f) u = 0.0f;
        if (u > span) u = span;
    }
    size_t i = (size_t)u;
    if (i >= n) i = n - 1;
    return route.samples[i].chain;
}

float TrackV2::speedScale(float u) const {
    (void)u;
    return route.ds; // uniform by construction — the honest meters-per-u
}

float TrackV2::maxU() const {
    size_t n = route.samples.size();
    if (n < 2) return 0.0f;
    return route.closed ? (float)n : (float)(n - 1);
}
