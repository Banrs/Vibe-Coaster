// Sky gradient constants mirrored from render_fx.cpp's SKY_FS shader (its
// ZENITH/MIDSKY/HORIZON/HAZE/GROUND consts) -- kept in sync by hand since fog
// is computed CPU-side here, not via a shared header. Used only by
// computeFogColor() below to derive FOG from the sky's own atmosphere model
// instead of a hand-picked constant that silently drifts out of sync if the
// sky is ever re-tuned.
static const Vector3 SKY_ZENITH_C  = { 0.045f, 0.26f, 0.74f };
static const Vector3 SKY_MIDSKY_C  = { 0.16f,  0.50f, 0.95f };
static const Vector3 SKY_HORIZON_C = { 0.52f,  0.74f, 1.00f };
static const Vector3 SKY_HAZE_C    = { 1.00f,  0.78f, 0.50f };
static const Vector3 SKY_GROUND_C  = { 0.64f,  0.72f, 0.80f };

static float smoothstepf(float e0, float e1, float x) {
    float t = Clamp((x - e0) / (e1 - e0), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}
// Same ACES curve as PostFX's composite-pass tonemap (see render_fx.cpp) --
// mirrored here (not called into) so this file doesn't reach into the PostFX
// pipeline for a one-line curve.
static Vector3 acesTonemapC(Vector3 c) {
    auto ch = [](float x) {
        float v = (x * (2.51f * x + 0.03f)) / (x * (2.43f * x + 0.59f) + 0.14f);
        return Clamp(v, 0.0f, 1.0f);
    };
    return { ch(c.x), ch(c.y), ch(c.z) };
}

// Derives the fog color from SKY_FS's own horizon-band gradient math,
// evaluated at a fixed representative direction (looking exactly at the
// horizon, side-on to the sun) rather than the full per-pixel/per-view
// formula -- fog is a single non-directional color uploaded once a frame, so
// what's wanted is a representative "ambient horizon tone", not one specific
// on-screen pixel. The sun-elevation-driven term (sunLift's haze warmth)
// still varies the result with sun position; the tail end runs it through
// the same ACES+gamma tonemap the sky itself is composited with, so it lands
// in the same post-tonemap space as what's actually on screen.
//
// CAL is a single fixed per-channel calibration scale applied on top -- the
// same kind of empirical grading step that originally produced the
// hand-picked {198,204,209} constant this replaces (it was "sampled directly
// from SKY_FS's actual rendered horizon pixel colour"), just now applied to a
// formula that responds to sun position instead of to a frozen RGB triple.
// It's solved so the CURRENT default g_sunDir reproduces {198,204,209}
// exactly; other sun elevations shift warmer/darker or cooler/brighter from
// there, tracking the sky instead of sitting fixed.
// Pre-tonemap linear sky-derived fog color (everything computeFogColor() below does,
// minus the exposure/ACES/gamma/calibration tail) -- exposed separately because the
// PostFX-era SHADOW_FS mixes fog into scene color in TWO different spaces depending on
// legacyTonemap: the legacy overlay paths mix into already-tonemapped/gamma-encoded
// color (display space, matches computeFogColor()'s FOG), but the main HDR path mixes
// BEFORE the composite pass's tonemap, i.e. into still-linear color -- mixing linear
// scene color against a display-space FOG there double-processes fog through ACES+gamma
// a second time when the composite pass runs, measurably shifting it brighter/flatter
// than intended (checked: {198,204,209} would land around {221,222,223} on screen,
// reintroducing a mild version of the "flat wall at the render-distance frontier" bug
// this whole feature exists to prevent). FOG_LINEAR is this function's un-tonemapped
// output, uploaded as a second uniform (fogColLinear) and used for the main path's mix
// instead, so it only goes through ACES+gamma once, in the composite pass, same as
// everything else in that path.
static Vector3 computeFogColorLinear(Vector3 sunDir) {
    float sunLift = smoothstepf(-0.12f, 0.55f, sunDir.y);

    const float dirY    = 0.0f; // representative "looking at the horizon" elevation
    const float mu      = 0.0f; // representative "side-on to the sun" view azimuth
    const float hazeMix = 0.6f; // matches SKY_FS's own lowHaze mix constant

    float h = Clamp(dirY * 0.5f + 0.5f, 0.0f, 1.0f);
    float skyT = smoothstepf(0.03f, 0.92f, h);
    Vector3 col = Vector3Lerp(SKY_HORIZON_C, SKY_MIDSKY_C, smoothstepf(0.0f, 0.55f, skyT));
    col = Vector3Lerp(col, SKY_ZENITH_C, smoothstepf(0.34f, 1.0f, skyT));

    float airMass = expf(-fmaxf(dirY, 0.0f) * 2.6f);
    col = Vector3Lerp(col, SKY_HORIZON_C, airMass * 0.22f);
    float horizonGlow = expf(-fabsf(dirY) * 4.2f);
    col = Vector3Add(col, Vector3Scale(SKY_HORIZON_C, horizonGlow * 0.22f));
    col = Vector3Add(col, Vector3Scale(SKY_HAZE_C, horizonGlow * (0.10f + 0.20f * (1.0f - sunLift))));

    const float sunAz = 1.0f / PI; // azimuth-averaged sunAz term (fog has no view direction of its own)
    Vector3 groundWarm = { SKY_GROUND_C.x * 1.05f, SKY_GROUND_C.y * 1.0f, SKY_GROUND_C.z * 0.93f };
    Vector3 lowHaze = Vector3Lerp(SKY_GROUND_C, groundWarm, sunAz * hazeMix);
    float wt = smoothstepf(-0.16f, 0.06f, dirY);
    col = Vector3Lerp(lowHaze, col, wt);

    float rayleigh = 0.55f + 0.45f * mu * mu;
    col = Vector3Scale(col, rayleigh);
    return col;
}

static Color computeFogColor(Vector3 sunDir) {
    Vector3 col = Vector3Scale(computeFogColorLinear(sunDir), 0.94f); // same pre-tonemap exposure as PostFX's composite pass
    col = acesTonemapC(col);
    col = { powf(col.x, 1.0f / 2.2f), powf(col.y, 1.0f / 2.2f), powf(col.z, 1.0f / 2.2f) };

    static const Vector3 CAL = { 1.226045f, 1.069453f, 0.988171f };
    col.x = Clamp(col.x * CAL.x, 0.0f, 1.0f);
    col.y = Clamp(col.y * CAL.y, 0.0f, 1.0f);
    col.z = Clamp(col.z * CAL.z, 0.0f, 1.0f);

    return Color{ (unsigned char)roundf(col.x * 255.0f), (unsigned char)roundf(col.y * 255.0f),
                  (unsigned char)roundf(col.z * 255.0f), 255 };
}
// The terrain heightfield (hashf/vnoise/fbm/ridgef/terrainH/groundTopAt)
// moved verbatim to terrain_field.h (included via game_state.cpp) so the V2
// track module and its acceptance harness query the same field the world
// meshes from. Nothing about the terrain changed.

struct TerrainCache {
    int W = 0;
    std::vector<int> h, tx, tz;
    // Biome noise (bio/humid/temp) is a pure function of (cx,cz) that never changes, yet the mesh
    // loop used to recompute it (3 fbm/vnoise = ~24 hashf) for every one of ~322k cells EVERY
    // rebuild. Cache it alongside height so it costs only the ~leading-band columns per re-center
    // (filled in prefillTerrain's parallel pass), not the whole disc on the single mesh worker.
    std::vector<float> bio, humid, temp;
    void resize(int w) { W = w; int n = W * W; h.assign(n, 0); tx.assign(n, INT_MIN); tz.assign(n, INT_MIN);
                         bio.assign(n, 0); humid.assign(n, 0); temp.assign(n, 0); }
    inline int slot(int cx, int cz) const {
        int ix = cx % W; if (ix < 0) ix += W;
        int iz = cz % W; if (iz < 0) iz += W;
        return iz * W + ix;
    }
    inline void fill(int i, int cx, int cz) {
        float wx = cx * CELL + CELL * 0.5f, wz = cz * CELL + CELL * 0.5f;
        h[i]     = terrainH(wx, wz);
        bio[i]   = vnoise(wx * 0.0045f + 91.3f, wz * 0.0045f + 23.1f);
        humid[i] = fbm(wx * 0.0028f + 44.0f, wz * 0.0028f + 108.0f, 2);
        temp[i]  = fbm(wx * 0.0019f + 12.0f, wz * 0.0019f + 204.0f, 2);
        tx[i] = cx; tz[i] = cz;
    }
    inline int get(int cx, int cz) {
        int i = slot(cx, cz);
        if (tx[i] != cx || tz[i] != cz) fill(i, cx, cz);
        return h[i];
    }
    // Returns the (fresh) slot index so callers can read h/bio/humid/temp without recomputing.
    inline int getSlot(int cx, int cz) {
        int i = slot(cx, cz);
        if (tx[i] != cx || tz[i] != cz) fill(i, cx, cz);
        return i;
    }
};
static TerrainCache gHCache;

static void prefillTerrain(int ccx, int ccz, int R) {
    if (gHCache.W < 2 * R + 1) gHCache.resize(2 * R + 1);
    unsigned hw = std::thread::hardware_concurrency();
    int nT = (int)(hw ? (hw < 8u ? hw : 8u) : 4u);
    int rows = 2 * R + 1, band = (rows + nT - 1) / nT;
    auto work = [&](int dz0, int dz1) {
        for (int dz = dz0; dz < dz1; dz++)
            for (int dx = -R; dx <= R; dx++)
                gHCache.get(ccx + dx, ccz + dz);
    };
    std::vector<std::thread> pool;
    for (int t = 0; t < nT; t++) {
        int dz0 = -R + t * band, dz1 = -R + (t + 1) * band;
        if (dz1 > R + 1) dz1 = R + 1;
        if (dz0 >= dz1) break;
        pool.emplace_back(work, dz0, dz1);
    }
    for (auto &th : pool) th.join();
}

