// Infinite streaming track + terrain for the hardware ray-traced renderer.
// Wraps the software game's rolling-deque generator (src/coaster_track.cpp) via
// raylib_shim.h, walks it ahead of the train, drops control points behind, and
// re-tessellates rails / spine / ties / supports / train + a terrain ring around
// the train into the shared MeshVertex triangle list the AS is built from.
#pragma once
#include "raylib_shim.h"
#include "terrain.h"                  // MeshVertex, pushQuad, pushTree, pushVoxBox
#include "coaster.h"                  // pushBox, orthoUp, catmull(float3,...) for the generator
#include <deque>
#include <vector>
#include <cstdio>
#include "../src/coaster_track.cpp"   // struct Track (uses the shim + coaster.h, NOT raylib)

// --- terrain ring extent (file scope so both StreamTrack + TrackSnapshot use it) ---
// The terrain ring must reach the track far-edge; the track build is clipped to
// this same radius so no track ever floats beyond the terrain edge. 1m blocks
// (CELL=1) keep true Minecraft scale on all sides.
static constexpr float TG_CELL = 1.0f;     // 1m voxel blocks (true MC scale)
static constexpr float TG_RING = 380.0f;   // half-extent meshed around the train (750->500->380: closer horizon recovers fps for FULL-RES no-upscale rendering + fewer/faster chunk rebuilds).
                                           // Lowered 1200->750: a smaller ring means
                                           // far fewer terrain tris and much cheaper
                                           // incremental edge-strip rebuilds, so the
                                           // moving ride holds a smooth 120fps (the
                                           // re-centre AS builds no longer spike).

// raylib_shim Color (0-255) -> float3 albedo (0-1), for porting themed liveries.
static inline float3 col2f3(Color c) { return vec3(c.r/255.f, c.g/255.f, c.b/255.f); }

// ---------------------------------------------------------------------------
// A self-contained, copyable snapshot of the spline window the meshing reads:
// flat copies of the control-point arrays + the window params. It exposes the
// SAME sampling interface (pos/tangent/upAt/tagAt/chainAt/cp[]/up[]/npts/mpu) as
// StreamTrack so the meshing code (templated below) runs against either. The
// snapshot is taken cheaply on the main thread, then meshed on a BACKGROUND
// thread so the ~100ms terrain build never stalls the frame loop.
struct TrackSnapshot {
    std::vector<Vector3>       cpv;     // control points
    std::vector<Vector3>       upv;     // rider-up per cp
    std::vector<unsigned char> kindv;   // SegMode tag per cp
    std::vector<unsigned char> chainv;  // chain-lift flag per cp
    std::vector<float>         arcv;    // cumulative world arc length per cp (popFront-stable support keying)
    float trainU = 6.0f;
    int   winLo = 4, buildAhead = 130;
    int   nptsv = 0;
    long  base  = 0;                    // absolute index of cp[0] (popFront-stable keying)
    // themed livery (1:1 with the SW game) + launch-station anchor, copied from the
    // generator so the meshing colours/builds match src/main.cpp exactly.
    float3 trainBody{}, trainAccent{}, spineCol{}, railColT{};
    float3 startPos{}; float startYaw = 0.0f;

    int npts() const { return nptsv; }
    // cp/up indexers (named to match StreamTrack's gen.cp[i]/gen.up[i] usage). They
    // reference THIS object's vectors via a member pointer, so they stay valid
    // through copies/moves (a cached raw pointer would dangle when the snapshot is
    // copied into the worker block).
    struct Idx {
        const std::vector<Vector3> TrackSnapshot::*m;
        const TrackSnapshot* owner;
        Vector3 operator[](int i) const { return (owner->*m)[i]; }
    };
    Idx cp{&TrackSnapshot::cpv, this};
    Idx up{&TrackSnapshot::upv, this};

    // copies/moves must re-point the indexers at the NEW object.
    TrackSnapshot() = default;
    TrackSnapshot(const TrackSnapshot& o) { *this = o; }
    TrackSnapshot& operator=(const TrackSnapshot& o) {
        cpv=o.cpv; upv=o.upv; kindv=o.kindv; chainv=o.chainv; arcv=o.arcv;
        trainU=o.trainU; winLo=o.winLo; buildAhead=o.buildAhead; nptsv=o.nptsv;
        base=o.base;
        trainBody=o.trainBody; trainAccent=o.trainAccent; spineCol=o.spineCol; railColT=o.railColT;
        startPos=o.startPos; startYaw=o.startYaw;
        cp = {&TrackSnapshot::cpv, this}; up = {&TrackSnapshot::upv, this};
        return *this;
    }

    Vector3 pos(float u) const {
        if (u < 0) u = 0;
        int k = (int)u;
        if (k > (int)cpv.size() - 4) k = (int)cpv.size() - 4;
        if (k < 0) k = 0;
        return catmull(cpv[k], cpv[k+1], cpv[k+2], cpv[k+3], u - k);
    }
    Vector3 upAt(float u) const {
        if (u < 0) u = 0;
        int k = (int)u;
        if (k > (int)upv.size() - 4) k = (int)upv.size() - 4;
        if (k < 0) k = 0;
        Vector3 a = catmull(upv[k], upv[k+1], upv[k+2], upv[k+3], u - k);
        if (Vector3Length(a) < 1e-4f) return vec3(0,1,0);
        return Vector3Normalize(a);
    }
    Vector3 tangent(float u) const {
        Vector3 d = Vector3Subtract(pos(u + 0.05f), pos(u - 0.05f));
        float L = Vector3Length(d);
        if (L < 1e-5f) return Vector3{0,0,1};
        return Vector3Scale(d, 1.0f / L);
    }
    int  tagAt(float u) const {
        int k = (int)u; if (k < 0) k = 0; if (k >= (int)kindv.size()) k = (int)kindv.size()-1;
        return kindv.empty() ? 0 : kindv[k];
    }
    bool chainAt(float u) const {
        int k = (int)u; if (k < 0) k = 0; if (k >= (int)chainv.size()) k = (int)chainv.size()-1;
        return !chainv.empty() && chainv[k] != 0;
    }
    float mpu(float u) const {
        Vector3 a = pos(u), b = pos(u + 0.1f);
        float m = Vector3Length(Vector3Subtract(b, a)) / 0.1f;
        return m < 1e-3f ? 1e-3f : m;
    }
    // cumulative world arc length at control-point index i (for arc-spaced, popFront-
    // stable support placement, matching src/main.cpp's trk.arc[]).
    float arcAt(int i) const {
        if (i < 0) i = 0; if (i >= (int)arcv.size()) i = (int)arcv.size() - 1;
        return arcv.empty() ? 0.0f : arcv[i];
    }
};

// Full scene mesh for a snapshot (defined after the free meshing templates below).
static void meshSnapshot(const TrackSnapshot& s, std::vector<MeshVertex>& out);

// ---------------------------------------------------------------------------
// Streaming state: one Track, a train parameter in LOCAL u (relative to the
// current deque front), and a tessellation window that slides with the train.
// ---------------------------------------------------------------------------
struct StreamTrack {
    Track gen;
    float trainU   = 6.0f;     // local u of the train along the deque
    int   winLo    = 4;        // first local index to build geometry for
    int   buildAhead = 150;    // local indices of track to keep meshed ahead of the train
    int   buildBehind = 26;    // local indices kept meshed behind the train (so it doesn't pop into view)

    // physics (mirrors src/main.cpp ride loop)
    float speed = LAUNCH_V * 0.6f;
    int   kind  = M_LAUNCH;
    bool  chain = false;
    float alt   = 0.0f;
    float gLoad = 1.0f;        // total felt g
    float boost = 1.0f;        // 0..1 boost meter (recharges on powered sections)
    float vertG = 1.0f;
    float latG  = 0.0f;        // signed lateral felt g (HUD g-meter)
    bool  dispatched = false;  // station-boarding: the train SITS at the platform until SPACE launches it (parity w/ SW)

    void init(uint32_t seed) {
        g_rng = seed * 2654435761u | 1u;
        gen.reset();
        // make sure there are enough points to mesh the first window
        winLo = 1;             // mesh from cp[1] so the launch straight UNDER the station platform renders
        gen.ensureAhead((float)(winLo + buildAhead + 16));
        trainU = 1.0f;         // board AT the station (cp[0] anchor), not 84m down the launch straight
        speed = 0.0f;          // sit stationary at the launch platform until dispatched (SPACE)
        dispatched = false;
    }
    void dispatch() { dispatched = true; }   // SPACE at the station: release the hydraulic launch

    // --- spline sampling in LOCAL u (delegates to the deque generator) ---
    Vector3 pos(float u) const     { return gen.pos(u); }
    Vector3 tangent(float u) const { return gen.tangent(u); }
    Vector3 upAt(float u) const    { return gen.upAt(u); }
    int     tagAt(float u) const   { return (int)gen.tagAt(u); }
    bool    chainAt(float u) const { return gen.chainAt(u); }

    int npts() const { return (int)gen.cp.size(); }

    // metres per local-u unit at u (for converting speed -> du/dt)
    float mpu(float u) const {
        Vector3 a = gen.pos(u), b = gen.pos(u + 0.1f);
        float m = Vector3Length(Vector3Subtract(b, a)) / 0.1f;
        return m < 1e-3f ? 1e-3f : m;
    }

    // Advance the train + slide the window; generate ahead, drop behind.
    // Returns true if the window shifted enough that geometry should rebuild.
    bool advance(float dt) {
        // station hold: before dispatch the train rests at the platform (0 g, 0 speed),
        // waiting for SPACE — the SW game's "PRESS SPACE TO LAUNCH" boarding state.
        if (!dispatched) {
            speed = 0.0f; kind = tagAt(trainU); chain = chainAt(trainU);
            gLoad = 1.0f; vertG = 1.0f; latG = 0.0f;
            alt = gen.pos(trainU).y - groundTopAt(gen.pos(trainU).x, gen.pos(trainU).z);
            return false;
        }
        // --- real ride physics (mirrors src/main.cpp + main.mm rideAdvance) ---
        Vector3 d3 = Vector3Subtract(gen.pos(trainU + 0.05f), gen.pos(trainU - 0.05f));
        float ds = Vector3Length(d3);
        float slope = (ds > 1e-4f) ? d3.y / ds : 0.0f;
        kind  = tagAt(trainU);
        chain = chainAt(trainU);

        float prevSpeed = speed;
        speed += (-GRAV * slope - DRAG * speed * speed - FRICTION) * dt;
        if      (kind == M_LAUNCH && speed < LAUNCH_V)            speed = fminf(speed + 85.0f * dt, LAUNCH_V);
        else if (kind == M_CLIMB  && !chain && speed < CLIMB_V)   speed = fminf(speed + 44.0f * dt, CLIMB_V);
        else if (kind == M_BOOST  && speed < BOOST_V )            speed = fminf(speed + 55.0f * dt, BOOST_V);
        else if (chain && slope > 0.05f && speed < CHAIN_V)       speed = fminf(speed + 20.0f * dt, CHAIN_V);

        // NO g-force trim brake. g is managed by TRACK GEOMETRY (elements are speed-sized
        // to ~1.30x world record so felt g stays in the +12/-9 envelope), NEVER by capping
        // speed — a speed cap is what made the car visibly throttle through inversions while
        // the readout/fps looked fine. If an inversion still spikes g, the fix is geometry,
        // not a brake (see the cobra/immel residual on the backlog).

        // CLIMB MOMENTUM ASSIST (parity w/ src/main.cpp): an unpowered climb never crawls to
        // the floor — a gentle assist holds a brisk speed ONLY while genuinely climbing (NOT a
        // global cruise pin; flats still coast down via drag). Kills the rises-stall-the-train bug.
        if (slope > 0.06f && kind != M_LAUNCH && kind != M_BOOST && kind != M_CLIMB && !chain && speed < 36.0f)
            speed = fminf(speed + 28.0f * dt, 36.0f);
        speed = fmaxf(speed, 20.0f); speed = fminf(speed, 135.0f);  // 20 = stall-only safety net (NOT a cruise floor); 135 = runaway guard

        // boost meter: recharges on powered sections, otherwise idle
        bool powered = (kind == M_LAUNCH || kind == M_BOOST);
        if (powered) boost = fminf(boost + dt * 0.6f, 1.0f);

        // felt-g estimate from the path: centripetal + gravity, projected onto rider up.
        {
            Vector3 fwd = tangent(trainU);
            Vector3 up  = orthoUp(fwd, upAt(trainU));
            Vector3 lat = Vector3Normalize(Vector3CrossProduct(up, fwd));
            // lateral accel ~ v^2 * curvature; approximate vertical felt g via slope change
            float dtu = 0.4f;
            Vector3 t0 = tangent(trainU - dtu), t1 = tangent(trainU + dtu);
            float segm = mpu(trainU) * (2.0f * dtu);
            Vector3 dT = Vector3Subtract(t1, t0);
            float curv = Vector3Length(dT) / fmaxf(segm, 1e-3f);
            Vector3 aCent = Vector3Scale(Vector3Normalize(dT), speed * speed * curv);
            Vector3 felt  = Vector3Add(aCent, vec3(0, GRAV, 0));
            vertG = Vector3DotProduct(felt, up) / GRAV;
            latG  = Vector3DotProduct(felt, lat) / GRAV;
            gLoad = Vector3Length(felt) / GRAV;
        }
        (void)prevSpeed;

        // advance the parameter
        trainU += (speed / mpu(trainU)) * dt;
        alt = gen.pos(trainU).y - groundTopAt(gen.pos(trainU).x, gen.pos(trainU).z);

        // slide the window: drop control points well behind the train, regenerate ahead
        bool shifted = false;
        int wantHead = (int)trainU + buildAhead + 16;
        if (wantHead > npts()) { gen.ensureAhead((float)wantHead); shifted = true; }

        int dropTo = (int)trainU - buildBehind;
        while (dropTo > 8 && (int)gen.cp.size() > buildAhead + buildBehind + 24) {
            gen.popFront();
            trainU -= 1.0f;
            dropTo  -= 1;
            shifted = true;
        }
        return shifted;
    }

    // Snapshot the spline window the meshing reads into a self-contained, copyable
    // TrackSnapshot (flat arrays). Cheap (a few hundred element copies) so it can run
    // on the main thread, then meshSnapshot() runs the heavy build on a worker thread.
    TrackSnapshot snapshot() const {
        TrackSnapshot s;
        s.trainU = trainU; s.winLo = winLo; s.buildAhead = buildAhead;
        s.nptsv = npts();
        s.base  = gen.base;          // absolute index of cp[0] (for popFront-stable support keying)
        // themed livery + launch-station anchor straight from the SW generator (1:1 colours).
        s.trainBody   = col2f3(gen.trainBody);
        s.trainAccent = col2f3(gen.trainAccent);
        s.spineCol    = col2f3(gen.spineC);
        s.railColT    = col2f3(gen.railC);
        s.startPos    = vec3(gen.startPos.x, gen.startPos.y, gen.startPos.z);
        s.startYaw    = gen.startYaw;
        int n = npts();
        s.cpv.resize(n); s.upv.resize(n); s.kindv.resize(n); s.chainv.resize(n); s.arcv.resize(n);
        for (int i = 0; i < n; i++) {
            s.cpv[i]    = gen.cp[i];
            s.upv[i]    = gen.up[i];
            s.kindv[i]  = (unsigned char)gen.kind[i];
            s.chainv[i] = (unsigned char)(gen.chainf[i] ? 1 : 0);
            s.arcv[i]   = gen.arc[i];
        }
        return s;
    }

    // Mesh the current generator window synchronously (used by the --shot path).
    void buildGeometry(std::vector<MeshVertex>& out) const { meshSnapshot(snapshot(), out); }
};

// ===========================================================================
// Free meshing functions. They take any source `s` exposing the StreamTrack /
// TrackSnapshot sampling interface (pos/tangent/upAt/tagAt/chainAt/cp/up/npts/mpu
// + trainU/winLo/buildAhead). Identical geometry to the old StreamTrack methods;
// just hoisted out so they can run on a background thread against a snapshot.
// ===========================================================================
template<class Src>
static void buildTerrainRingT(const Src& s, std::vector<MeshVertex>& out) {
    Vector3 tp = s.pos(s.trainU);
    int N = (int)(2.0f * TG_RING / TG_CELL);
    // Snap the ring centre to the voxel grid so the cell boundaries (and the
    // world-keyed trees) land on the SAME absolute grid every rebuild -> the
    // streamed terrain is rock-stable as the window slides (no wobble/flicker).
    tp.x = floorf(tp.x / TG_CELL) * TG_CELL;
    tp.z = floorf(tp.z / TG_CELL) * TG_CELL;
    std::vector<float3> trackPts;
    int lastU = (int)s.trainU + s.buildAhead;
    if (lastU > s.npts() - 1) lastU = s.npts() - 1;
    for (int i = s.winLo; i <= lastU; i++) {
        Vector3 p = s.cp[i];
        trackPts.push_back(vec3(p.x, p.y, p.z));
    }
    Terrain t = buildTerrain(tp.x, tp.z, N, TG_CELL, trackPts.data(), (int)trackPts.size());
    out.insert(out.end(), t.verts.begin(), t.verts.end());
}

template<class Src>
static void buildTrainT(const Src& s, std::vector<MeshVertex>& out) {
    // Full Formula-Rossa consist via the shared pushF1Car helper (chassis / tub / nose /
    // riders / wheels), ported 1:1 from src/main.cpp drawCoasterCar. Themed livery from
    // the generator (s.trainBody / s.trainAccent / s.railColT).
    const float CAR_PITCH = 4.2f;
    float u = s.trainU;
    for (int car = 0; car < 5; car++) {
        if (u >= (float)(s.npts() - 4)) break;
        float3 c   = s.pos(u);
        float3 fwd = s.tangent(u);
        float3 up  = orthoUp(fwd, s.upAt(u));
        float3 lat = normalize(cross(up, fwd));
        // c is the rail plane (software car origin y=0); pushF1Car offsets up from here.
        pushF1Car(out, c, lat, up, fwd, s.trainBody, s.trainAccent, s.railColT, car == 0, car);
        float m = s.mpu(u);
        u -= CAR_PITCH / fmaxf(m, 1e-3f);   // cars trail BEHIND the lead (camera) car
        if (u < (float)s.winLo) break;
    }
}

template<class Src>
static void buildTrackT(const Src& s, std::vector<MeshVertex>& out) {
    int last = (int)s.trainU + s.buildAhead;
    if (last > s.npts() - 4) last = s.npts() - 4;
    float uLo = (float)s.winLo;
    float uHi = (float)last;

    Vector3 tc = s.pos(s.trainU);
    float ringCx = floorf(tc.x / TG_CELL) * TG_CELL, ringCz = floorf(tc.z / TG_CELL) * TG_CELL;
    const float ringClip = TG_RING - 6.0f;
    auto inRing = [&](float3 p) {
        return fabsf(p.x - ringCx) <= ringClip && fabsf(p.z - ringCz) <= ringClip;
    };

    // --- SCALE: TRUE 1m-block steel. Modern-steel cross-section (B&M / Intamin read):
    // two running RAILS standing PROUD above a continuous box-beam SPINE, joined by a
    // ladder of cross-ties + a central web (so the spine reads as a separate element and
    // the whole track visibly ROLLS with the per-point up-vector through banks/inversions).
    //   rails  at ±0.55 lateral, lifted +RAIL_RISE so they float clear of the spine top
    //   spine  dropped SPINE_DROP below the rail plane (a clear gap, not flush)
    //   tie    a rung spanning the gauge at the rail underside + a web down to the spine
    const float RAIL_GAUGE = 0.55f;   // lateral half-spacing of running rails (~1.1m gauge)
    const float RAIL_R     = 0.085f;  // rail beam half-thickness (0.17 full) — slimmer tube
    const float RAIL_RISE  = 0.105f;  // rails lifted above the spline plane (bottom ≈ plane)
    const float SPINE_DROP = 0.44f;   // spine centre below the rail plane (top sits clear under rails)
    // Themed livery straight from the generator (1:1 with src/main.cpp: railC / spineC /
    // trainAccent). The colored spine + LSM fins read with the SAME palette as the game.
    float3 railCol   = s.railColT;                 // light steel rails (RAIL)
    float3 spineSteel= col2f3(Color{44, 47, 55, 255});  // dark structural box-beam tube (un-powered)
    float3 spineHot  = s.spineCol;                 // themed colored spine on powered sections
    float3 finCol    = s.trainAccent;              // themed LSM stator fins
    float3 chainCol  = col2f3(Color{108, 110, 118, 255});  // CHAINC: lift chain
    float3 tieCol    = col2f3(Color{96, 99, 108, 255});    // steel cross ties
    float3 supCol    = vec3(0.46f, 0.48f, 0.52f);  // steel support bents

    const float STEP = 0.20f;
    float3 prevL{}, prevR{}; bool havePrev = false;
    long lastTieBin = -1<<30;   // world-stable tie phase (keyed to absolute u, not local segCount)

    for (float u = uLo; u <= uHi; u += STEP) {
        float3 c   = s.pos(u);
        if (!inRing(c)) { havePrev = false; continue; }   // clip track to terrain ring
        float3 fwd = s.tangent(u);
        float3 up  = orthoUp(fwd, s.upAt(u));
        float3 lat = normalize(cross(up, fwd));
        // rails stand PROUD of the spline plane (lifted along the rolling up-vector) so
        // the spine reads as a separate beam below and the bank is visible on the rails.
        float3 railL = c + lat * RAIL_GAUGE + up * RAIL_RISE;
        float3 railR = c - lat * RAIL_GAUGE + up * RAIL_RISE;
        if (havePrev) {
            auto railSeg = [&](float3 a, float3 b) {
                float3 d = b - a; float L = length(d);
                if (L < 1e-4f) return;
                float3 f = d * (1.0f / L);
                float3 u2 = orthoUp(f, up);
                float3 r2 = normalize(cross(u2, f));
                pushBox(out, (a + b) * 0.5f, r2, u2, f, RAIL_R, RAIL_R, L * 0.5f, railCol);
            };
            railSeg(prevL, railL);
            railSeg(prevR, railR);
        }
        prevL = railL; prevR = railR; havePrev = true;

        int kn = s.tagAt(u);
        bool chain = s.chainAt(u);
        // powered = driven track: launch, mid-course booster, AND hydraulic (non-chain)
        // top-hat climb (src/main.cpp:2592-2593) -> themed colored spine + LSM fins.
        bool powered = (kn == M_LAUNCH || kn == M_BOOST || (kn == M_CLIMB && !chain));
        float spineHalfF = length(s.pos(u + STEP) - c) * 0.6f;
        // box-beam spine under the rail plane; themed colored ONLY on powered sections.
        float spW = powered ? 0.19f : 0.15f;   // half-width  (0.38 / 0.30 full)
        float spH = powered ? 0.27f : 0.23f;   // half-height (0.54 / 0.46 full)
        float3 spineC = c - up * SPINE_DROP;
        pushBox(out, spineC, lat, up, fwd, spW, spH, spineHalfF,
                powered ? spineHot : spineSteel);
        // every-other-step phase, popFront-stable (keyed to absolute u like the ties).
        bool finPhase = (((long)floorf((u + (float)s.base) / STEP)) & 1) == 0;
        // LSM stator fins flanking the powered spine top (themed accent) — sit on the
        // upper spine so they read as the launch motor, just below the running rails.
        if (powered && finPhase)
            pushBox(out, c - up * (SPINE_DROP - spH - 0.05f), lat, up, fwd,
                    spW + 0.10f, 0.09f, spineHalfF * 0.6f, finCol);
        // lift chain centred on the spine top on chain segments (where the lift dog rides).
        if (chain)
            pushBox(out, c - up * (SPINE_DROP - spH), lat, up, fwd, 0.07f, 0.07f, spineHalfF, chainCol);

        // cross-tie spanning the two rails ~every 0.6u. Keyed to the ABSOLUTE spline
        // parameter (u + base), NOT a local segment counter: the deque pops its front as
        // the train rides, which shifts every local index and used to flip the tie phase
        // each pop ("ties jittering"). (u+base) is invariant under popFront, so each tie
        // lands at the SAME world spot every rebuild.
        long tieBin = (long)floorf((u + (float)s.base) / 0.6f);
        if (tieBin != lastTieBin) {
            lastTieBin = tieBin;
            // rung: spans the gauge just under the rails (ties the two rails together).
            float3 rungC = c + up * (RAIL_RISE - 0.06f);
            pushBox(out, rungC, lat, up, fwd, RAIL_GAUGE + RAIL_R, 0.06f, 0.20f, tieCol);
            // web: a short vertical post from the rung down onto the spine top -> the
            // spine-rails-tie assembly reads as one I-beam that rolls with the bank.
            float webTopY = RAIL_RISE - 0.10f, webBotY = -(SPINE_DROP - spH);
            float3 webC = c + up * ((webTopY + webBotY) * 0.5f);
            pushBox(out, webC, lat, up, fwd, 0.10f, (webTopY - webBotY) * 0.5f, 0.18f, tieCol);
        }
    }

    // --- HELIX central tower (port of src/main.cpp's open 4-post lattice): a tight
    // coil drops ONE central tower with the coils tying in via radial struts, so legs
    // never punch down through the stacked coils. axis = centroid of the contiguous
    // helix run (stable: keyed to the whole run, not the sliding window).
    float3 hxAxis = vec3(0,0,0); int hxN = 0; float hxTopY = -1e9f; int hxSeed = -1;
    for (int i = s.winLo; i <= last; i++)
        if (s.tagAt((float)i) == M_HELIX) { hxSeed = i; break; }
    if (hxSeed >= 0) {
        int a = hxSeed, b = hxSeed;
        while (a > 1 && s.tagAt((float)(a - 1)) == M_HELIX) a--;
        while (b + 2 < s.npts() && s.tagAt((float)(b + 1)) == M_HELIX) b++;
        for (int i = a; i <= b; i++) {
            Vector3 cp = s.cp[i];
            hxAxis.x += cp.x; hxAxis.z += cp.z; hxN++;
            if (cp.y > hxTopY) hxTopY = cp.y;
        }
    }
    bool haveHx = hxN >= 4;
    if (haveHx) {
        hxAxis.x /= hxN; hxAxis.z /= hxN;
        float gAxis = groundTopAt(hxAxis.x, hxAxis.z), th = hxTopY - gAxis;
        if (th > 3.0f && inRing(hxAxis)) {
            const float tw = 1.4f;                       // tower half-width
            for (float sx = -1.0f; sx <= 1.0f; sx += 2.0f)
                for (float sz = -1.0f; sz <= 1.0f; sz += 2.0f)   // 4 full-height corner posts
                    pushBox(out, vec3(hxAxis.x + sx*tw, gAxis + th*0.5f, hxAxis.z + sz*tw),
                            vec3(1,0,0), vec3(0,1,0), vec3(0,0,1), 0.17f, th*0.5f, 0.17f, supCol);
            for (float ry = gAxis + 8.0f; ry < hxTopY - 2.0f; ry += 9.0f)   // ring braces
                pushBox(out, vec3(hxAxis.x, ry, hxAxis.z), vec3(1,0,0), vec3(0,1,0), vec3(0,0,1),
                        tw + 0.2f, 0.16f, tw + 0.2f, supCol);
        }
    }

    // --- Support bents (track-aligned A-frame V), ported 1:1 from src/main.cpp drawVBent.
    // Spaced by WORLD ARC LENGTH (SUP_SP metres), NOT control-point index: arc[] is
    // popFront-stable so each bent lands at a fixed world distance and never jumps or
    // overlaps as the deque slides. Each leg is one solid beam raking from a node tucked
    // under the spine out to a foot on the terrain; tall bents get trussed; helix coils
    // tie into the central tower instead of dropping their own legs.
    const float SUP_SP = 9.0f;                            // metres between A-frame bents
    auto isOverhead = [&](int kn, float upy) {
        // skip the inverted half of loops/rolls/etc (overhead spans get no ground leg)
        bool inversionElem = (kn == M_LOOP || kn == M_ROLL || kn == M_IMMEL ||
                              kn == M_STALL || kn == M_DIVELOOP || kn == M_COBRA ||
                              kn == M_HEARTLINE || kn == M_WINGOVER ||
                              kn == M_PRETZEL || kn == M_BANANA);
        return inversionElem && upy < 0.35f;
    };
    // --- ADAPTIVE SUPPORTS: a bent must never punch through (or block the train on) a
    // LOWER span of the same coaster that passes beneath it. lowerTrackUnder() returns the
    // highest other-span centreline that sits under (footX,footZ) within RIDE_CLR_H, but
    // ONLY spans at least V_GAP below `apexY` (so the bent's own track + its near neighbours
    // don't count). A foot is then floored to clear that span (CLR_V above it); if a span
    // runs right under the apex the whole bent is skipped (clipping there would gore the
    // train passing below). Uses the same control-point window the rails are built from.
    const float RIDE_CLR_H = 2.6f;     // horizontal half-width of the train+leg swept volume
    const float RIDE_CLR_H2 = RIDE_CLR_H * RIDE_CLR_H;
    const float CLR_V      = 3.0f;     // keep legs/feet this far above any track beneath them
    const float V_GAP      = 4.0f;     // a span must be this far below the apex to count as "lower"
    auto lowerTrackUnder = [&](float fx, float fz, float apexY, int self) -> float {
        float hi = -1e9f;
        for (int j = s.winLo; j <= last; j++) {
            if (j > self - 7 && j < self + 7) continue;       // skip the bent's OWN span (near indices)
            Vector3 q = s.cp[j];
            if (q.y > apexY - V_GAP) continue;               // not a genuinely lower span
            float dx = q.x - fx, dz = q.z - fz;
            if (dx*dx + dz*dz <= RIDE_CLR_H2 && q.y > hi) hi = q.y;
        }
        return hi;
    };
    for (int i = s.winLo + 1; i < last; i++) {
        Vector3 cpP = s.cp[i], cpU = s.up[i];
        int kn = s.tagAt((float)i);
        if (isOverhead(kn, cpU.y)) continue;             // overhead inversion span -> no leg
        float3 p = vec3(cpP.x, cpP.y, cpP.z);
        if (!inRing(p)) continue;                        // clip supports to terrain ring
        float gC = groundTopAt(p.x, p.z);
        if (p.y - gC < 1.5f) continue;                   // already near the ground

        float3 fwd = s.tangent((float)i);
        float3 up  = orthoUp(fwd, vec3(cpU.x, cpU.y, cpU.z));

        // Powered-section maintenance catwalk + handrails + access stair (src/main.cpp:
        // 2538-2557). Per control point on LAUNCH / BOOST sections, in a horizontal frame
        // (fwd flattened); pieces SEG_LEN(14m) long tile seamlessly along the straight.
        if (kn == M_LAUNCH || kn == M_BOOST) {
            float3 fwdH = normalize(vec3(fwd.x, 0.0f, fwd.z));
            float3 upH  = vec3(0, 1, 0);
            float3 latH = normalize(cross(upH, fwdH));
            float3 base = p;
            auto cbox = [&](float x, float y, float z, float w, float h, float l, float3 col) {
                pushBox(out, base + latH*x + upH*y + fwdH*z, latH, upH, fwdH, w*0.5f, h*0.5f, l*0.5f, col);
            };
            float3 grate = col2f3(Color{150, 154, 162, 255});  // steel grating
            float3 rail2 = col2f3(Color{236, 214,  96, 255});  // yellow safety handrail
            cbox(2.0f, -0.55f, 0, 1.5f, 0.12f, SEG_LEN, grate);          // walkway grating
            for (float ry : { 0.25f, 0.75f })                            // two handrail bars
                cbox(2.7f, ry, 0, 0.08f, 0.08f, SEG_LEN, rail2);
            for (float pz2 = -SEG_LEN*0.5f; pz2 < SEG_LEN*0.5f; pz2 += 3.5f)   // rail stanchions
                cbox(2.7f, 0.35f, pz2, 0.08f, 0.9f, 0.08f, rail2);
            if (p.y - gC > 2.0f && (i & 3) == 0) {                       // stepped access stair
                int steps = (int)fminf((p.y - gC) / 0.8f, 14.0f);
                for (int st = 0; st < steps; st++)
                    // 1:1 with src/main.cpp: local-y literally p.y-0.55-st*0.8 in the frame at p.
                    cbox(2.9f + st * 0.42f, p.y - 0.55f - st * 0.8f, 0, 0.5f, 0.16f, 1.1f, grate);
            }
        }

        // HELIX coils tie radially into the central tower (no individual legs).
        if (kn == M_HELIX && haveHx) {
            pushBox(out, vec3((p.x + hxAxis.x)*0.5f, p.y - 0.6f, (p.z + hxAxis.z)*0.5f),
                    vec3(1,0,0), vec3(0,1,0), vec3(0,0,1),
                    (fabsf(hxAxis.x - p.x) + 0.4f)*0.5f, 0.15f,
                    (fabsf(hxAxis.z - p.z) + 0.4f)*0.5f, supCol);
            continue;
        }

        // arc-length spacing: place a bent only when this cp crosses a SUP_SP boundary
        // (matches the SW game; keeps an even ~9m cadence regardless of point density).
        bool placeHere = floorf(s.arcAt(i) / SUP_SP) != floorf(s.arcAt(i - 1) / SUP_SP);
        if (!placeHere) continue;

        float topY = p.y - 0.5f;                          // apex flush to the spine underside
        float hgt  = topY - gC;
        if (hgt < 1.0f) continue;

        // adaptive: a lower span passing directly under the apex would be struck by this
        // bent (and the train on it would hit the node) -> skip the bent entirely here.
        if (lowerTrackUnder(p.x, p.z, topY, i) > -1e8f) continue;

        // deterministic per-location variation so the run of bents isn't uniform
        float vary = hashf((int)floorf(p.x * 0.5f), (int)floorf(p.z * 0.5f));
        float baseHalf = t_Clamp(hgt * (0.17f + vary * 0.07f), 1.5f, 5.5f);  // ground splay grows w/ height
        float legR     = t_Clamp(0.30f + hgt * 0.0045f, 0.30f, 0.55f);       // taller -> thicker legs
        float topHalf  = 0.22f;                            // leg tops attach just inside the node
        // tops + feet must splay along the SAME lateral sense (rRight) or the legs cross
        // into an X; node recessed UP into the spine underside along railUp.
        float3 rRight = normalize(cross(up, fwd));         // track lateral (tilts with bank)
        float3 latH   = normalize(vec3(rRight.x, 0.0f, rRight.z));  // ground projection
        float nodeDrop = 0.58f;
        float3 node = vec3(p.x, topY, p.z) - up * nodeDrop;
        // Tall supports use a 4-leg lattice TOWER (real coasters don't A-frame the big
        // lift/drop structures). Medium/short bents keep the A-frame below.
        if (hgt >= 20.0f) {
            buildSupportTower(out, node, rRight, fwd, baseHalf, legR, hgt, supCol,
                [&](float bx, float bz) -> float {
                    float fY = groundTopAt(bx, bz);
                    float under = lowerTrackUnder(bx, bz, topY, i);
                    if (under > -1e8f && under + CLR_V > fY) fY = under + CLR_V;
                    return fY;
                });
            continue;
        }
        float3 tops[2], feet[2]; bool legOK[2] = {false, false};
        int si = 0;
        for (float sgn = -1.0f; sgn <= 1.0f; sgn += 2.0f) {
            float3 top  = node + rRight * (sgn * topHalf);
            float bx = p.x + latH.x * sgn * baseHalf, bz = p.z + latH.z * sgn * baseHalf;
            // adaptive foot: stop the leg on the GROUND, or CLR_V above any lower track span
            // that runs under the leg's foot (so the leg never spears through it).
            float footY = groundTopAt(bx, bz);
            float under = lowerTrackUnder(bx, bz, topY, i);
            if (under > -1e8f && under + CLR_V > footY) footY = under + CLR_V;
            float3 foot = vec3(bx, footY, bz);
            tops[si] = top; feet[si] = foot;
            float3 d = foot - top; float L = length(d);
            si++;
            if (L < 1.2f) continue;                          // too stubby after clipping -> drop this leg
            legOK[si - 1] = true;
            float3 f  = d * (1.0f / L);
            float3 u2 = orthoUp(f, vec3(0,1,0));
            float3 r2 = normalize(cross(u2, f));
            pushBox(out, (top + foot) * 0.5f, r2, u2, f, legR, legR, L * 0.5f, supCol);
        }
        if (!legOK[0] && !legOK[1]) continue;                // both legs clipped away -> no bent
        // a steel strut between two world points (cross-ties / diagonal bracing)
        auto strut = [&](float3 a, float3 b, float r) {
            float3 d = b - a; float L = length(d);
            if (L < 0.3f) return;
            float3 f = d * (1.0f / L);
            float3 u2 = orthoUp(f, vec3(0,1,0));
            float3 r2 = normalize(cross(u2, f));
            pushBox(out, (a + b) * 0.5f, r2, u2, f, r, r, L * 0.5f, supCol);
        };
        // medium bents get a trussed A-frame: horizontal ties (tall ones are towers above)
        if (hgt > 14.0f && legOK[0] && legOK[1]) {
            int levels = (int)t_Clamp(hgt / 16.0f, 1.0f, 4.0f);
            for (int k = 1; k <= levels; k++) {
                float fr = (float)k / (float)(levels + 1);   // node(0) -> foot(1)
                float3 L = tops[0] + (feet[0] - tops[0]) * fr;
                float3 R = tops[1] + (feet[1] - tops[1]) * fr;
                strut(L, R, legR * 0.7f);                    // horizontal tie
            }
        }
        // node block where the legs converge, oriented to the rail frame
        pushBox(out, node, rRight, up, fwd, 0.28f, 0.28f, 0.50f, supCol);
    }

    // Launch / boarding hall at the generator's start anchor (themed). Only built while
    // the start anchor is still inside the streamed terrain ring (it pops from view once
    // the train rides far enough away — matching the SW game's distance fade-out).
    if (inRing(s.startPos))
        buildStation(out, s.startPos, s.startYaw, s.spineCol, s.trainAccent);

    buildTrainT(s, out);   // train consist near the head (rides with the camera)
}

// Full scene mesh for a snapshot (terrain ring + clipped track + train). Kept for
// the --shot path's forceSyncRebuild; the live renderer meshes the two halves
// separately (different rebuild cadences) via meshTerrainOnly / meshTrackOnly.
static void meshSnapshot(const TrackSnapshot& s, std::vector<MeshVertex>& out) {
    out.clear();
    buildTerrainRingT(s, out);
    buildTrackT(s, out);
}

// Terrain ring only (instance 0 — big, rebuilt rarely on ring-centre moves).
static void meshTerrainOnly(const TrackSnapshot& s, std::vector<MeshVertex>& out) {
    out.clear();
    buildTerrainRingT(s, out);
}

// The track control points used to keep trees clear of the coaster + carve the
// terrain columns it threads, for the chunked terrain mesher (same window the ring
// mesher uses). If `kindsOut` is non-null it is filled with the matching per-point
// SegMode tag (so the carve can flatten helix coil interiors).
static std::vector<float3> snapshotTrackPts(const TrackSnapshot& s,
                                            std::vector<unsigned char>* kindsOut = nullptr) {
    std::vector<float3> pts;
    if (kindsOut) kindsOut->clear();
    int lastU = (int)s.trainU + s.buildAhead;
    if (lastU > s.npts() - 1) lastU = s.npts() - 1;
    for (int i = s.winLo; i <= lastU; i++) {
        Vector3 p = s.cp[i];
        pts.push_back(vec3(p.x, p.y, p.z));
        if (kindsOut) kindsOut->push_back(i < (int)s.kindv.size() ? s.kindv[i] : 0);
    }
    return pts;
}
// Track + supports + train only (instance 1 — tiny, rebuilt every few frames).
static void meshTrackOnly(const TrackSnapshot& s, std::vector<MeshVertex>& out) {
    out.clear();
    buildTrackT(s, out);
}
