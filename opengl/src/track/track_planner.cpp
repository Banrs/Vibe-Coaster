// Track V2 — whole-ride layout planner (COASTER_REWRITE.md §1). Plans a
// finite list of beats — each with entry/exit pose, speed intent, clearance
// band and minimum length — BEFORE any geometry is generated, then emits the
// primitives beat by beat. buildRide is the real generator; the buildStepN
// routes are the per-step acceptance-harness fixtures.
#include <cassert>

#include "track_math.h"

namespace v2 {

// ---------------------------------------------------------------------------
// Planner RNG — deterministic, local (never the host's global RNG).
// ---------------------------------------------------------------------------
namespace {

struct Rng {
    uint32_t s;
    explicit Rng(uint32_t seed) : s(seed * 2654435761u | 1u) {}
    uint32_t next() {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return s;
    }
    float uni() { return (float)(next() & 0xffffff) / 16777216.0f; }
    float range(float a, float b) { return a + (b - a) * uni(); }
    int pick(int n) { return (int)(next() % (uint32_t)n); }
};

constexpr float kG = 9.81f;

// Energy bookkeeping: v^2 after a height change plus an aggregate loss model
// for an EXTREMELY EFFICIENT modern steel coaster (Intamin-giga class), per
// REALISM_SCALE.md "Speed-loss model" (researched 2026-07-10):
//   a_loss(v) = kRollG*g + cAero*v^2   ->
//   v^2(s) = (v0^2 + kRollG*g/cAero) * exp(-2*cAero*s) - kRollG*g/cAero
// Two terms matter: rolling resistance dominates below ~28 m/s, aero above.
// Cross-checked against Millennium Force retaining ~96.5% of ideal kinetic
// energy over its first drop. Calibrate the HOST physics to match at the
// step-6 switch.
constexpr float kRollG = 0.008f;  // rolling decel in g (efficient polyurethane)
constexpr float cAero = 1.0e-4f;  // 0.5*rho*Cd*A/m per meter (heavy giga train)

float v2After(float v2, float dy) { return v2 - 2.0f * kG * dy; }
float v2Drag(float v2, float meters) {
    float ug = kRollG * kG;
    float u = (v2 + ug / cAero) * expf(-2.0f * cAero * meters) - ug / cAero;
    return fmaxf(u, 0.0f);
}

// Level the route out (elements and lines need a level, straight entry).
// Safe to call anywhere; a no-op when already level.
void levelOut(Route& r) {
    if (fabsf(r.endPose.pitch) > 0.012f)
        emitGradeChange(r, 0.0f, fmaxf(18.0f, fabsf(r.endPose.pitch) * 70.0f), Tag::Line);
}

// Planner-side drop with ramps PROPORTIONAL to the height, so any terrain- or
// speed-derived dy keeps a real sustained face (fixed ramps eat small heights
// whole and trip the primitive's solvability assert). LEVELS the entry first:
// emitDrop starts its push-over from the current pitch, so a positive (still
// climbing) entry would make the drop RISE at its mouth — exactly the
// "height rises inside drop" element failure. A drop is a pure vertical
// element; the terrain-following grade lives in emitGroundLeg, not here.
void plannerDrop(Route& r, float dy) {
    levelOut(r);
    DropSpec d;
    d.height = dy;
    d.thetaDrop = 0.35f + fminf(0.87f, dy / 90.0f);
    // Ramps scale with the face angle as well as the height: a steep
    // push-over over a short ramp is a ~3 m radius (validator-visible kink
    // territory), not a coaster transition.
    d.rampIn = fminf(42.0f, fmaxf(fmaxf(10.0f, dy * 0.35f), d.thetaDrop * 24.0f));
    d.rampOut = d.rampIn + 6.0f;
    // Very small drops can't afford the full angle; shrink it.
    while (d.thetaDrop > 0.3f) {
        Profile1D in = rampProfile(0.0f, -d.thetaDrop, d.rampIn);
        Profile1D out = rampProfile(-d.thetaDrop, 0.0f, d.rampOut);
        float need = -profileRise(in, 0.0f, d.rampIn) - profileRise(out, 0.0f, d.rampOut);
        if (dy - need > 4.5f * sinf(d.thetaDrop)) break;
        d.thetaDrop *= 0.8f;
        d.rampIn = fminf(42.0f, fmaxf(fmaxf(10.0f, dy * 0.35f), d.thetaDrop * 24.0f));
        d.rampOut = d.rampIn + 6.0f;
    }
    emitDrop(r, d);
}

// Planner-side climb (drop mirrored). Levels the entry for the same reason:
// emitClimb's pull-up starts from the current pitch.
void plannerClimb(Route& r, float dy, Tag tag, bool chain) {
    levelOut(r);
    float theta = dy > 60.0f ? 0.61f : 0.42f; // 35 or 24 deg
    float ramp = fminf(40.0f, fmaxf(10.0f, dy * 0.5f));
    emitClimb(r, dy, theta, ramp, ramp, tag, chain);
}

// Continuous ground-hugging leg (COASTER_REWRITE.md "low terrain-hugging
// turns/hills"; TERRAIN_CONTRACT.md: bounded cuts are the norm, km-scale
// bores the failure). Walks the straight in short steps, grading the pitch
// toward (ground ahead + clearance) each step with a capped slope, so the
// rail tracks the relief the WHOLE way — the cut/unsupported excursion is
// bounded per step, never a kilometre-deep bore. Grade ramps are S5 (C2);
// levels out at the end so the next element gets a level, straight entry.
// Errs slightly ABOVE ground (clearance): an unsupported span never trips the
// clearance gate, a tunnel does. Returns v^2 after the net rise.
float emitGroundLeg(Route& r, float v2, const TerrainQuery& terrain, float length,
                    float clearance) {
    const float step = 40.0f;
    const float startY = r.endPose.pos.y;
    float done = 0.0f;
    while (length - done > 1.0f) {
        float seg = fminf(step, length - done);
        float dx = sinf(r.endPose.yaw), dz = cosf(r.endPose.yaw);
        float gAhead = terrain.height(r.endPose.pos.x + dx * seg, r.endPose.pos.z + dz * seg);
        float dy = (gAhead + clearance) - r.endPose.pos.y;
        // Climb steeper than descend: keeping up with a rising flank avoids a
        // tunnel; a fast descent just floats (unsupported, harmless).
        float pitch = fmaxf(-0.42f, fminf(0.52f, atanf(dy / seg)));
        float rampLen = fminf(seg, fmaxf(10.0f, fabsf(pitch - r.endPose.pitch) * 60.0f));
        emitGradeChange(r, pitch, rampLen, Tag::Line);
        if (seg - rampLen > 1.0f) emitLine(r, seg - rampLen, Tag::Line, false);
        done += seg;
    }
    levelOut(r);
    return fmaxf(v2After(v2, r.endPose.pos.y - startY), 100.0f);
}

// Geometric speed conditioning: climb (or descend) toward the height that
// brings v^2 to the target band. Climbs are capped (a conditioning tower
// taller than ~150 m stops being ride texture); when capped, the element
// simply takes the residual higher entry speed — sizes sit at the band top
// and the user accepts the higher g (REALISM_SCALE, 2026-07-10 note).
// Returns the ACHIEVED v^2.
float conditionSpeed(Route& r, float v2, float v2Target) {
    float dy = (v2 - v2Target) / (2.0f * kG);
    if (fabsf(dy) < 6.0f) return v2; // close enough — soft tolerances
    if (dy > 0.0f) {
        float climb = fminf(dy, 150.0f);
        plannerClimb(r, climb, Tag::Line, false);
        return v2After(v2, climb);
    }
    plannerDrop(r, -dy);
    return v2Target;
}

// Grade the upcoming turn so its (constant-pitch) arc CLEARS every bit of
// ground it sweeps over. A turn is a single-grade ramp — it cannot follow a
// mid-arc hump — so instead of grading toward the exit alone, sample the whole
// sweep and take the pitch that clears the HIGHEST point (+clearance). Ground
// lower than that line passes beneath the arc as an unsupported span (harmless
// to the clearance gate); only a hump steeper than the pitch cap leaves a
// bounded cut, never a long bore from a level arc sitting under a rising flank.
void gradeTurnToTerrain(Route& r, const TerrainQuery& terrain, const TurnSpec& t) {
    float s1 = t.totalAngle >= 0.0f ? 1.0f : -1.0f;
    float yaw = r.endPose.yaw;
    float R = t.radius;
    float cx = r.endPose.pos.x + s1 * R * cosf(yaw);
    float cz = r.endPose.pos.z - s1 * R * sinf(yaw);
    float y0 = r.endPose.pos.y;
    float need = -1e9f;
    const int N = 6;
    for (int i = 1; i <= N; i++) {
        float frac = (float)i / (float)N;
        float ang = yaw + t.totalAngle * frac;
        float px = cx - s1 * R * cosf(ang), pz = cz + s1 * R * sinf(ang);
        float arcLen = R * fabsf(t.totalAngle) * frac;
        float req = atanf((terrain.height(px, pz) + 12.0f - y0) / fmaxf(arcLen, 30.0f));
        need = fmaxf(need, req);
    }
    float pitch = fminf(0.30f, fmaxf(-0.30f, need));
    if (fabsf(pitch - r.endPose.pitch) > 0.02f)
        emitGradeChange(r, pitch, fmaxf(18.0f, fabsf(pitch - r.endPose.pitch) * 70.0f),
                        Tag::Line);
}

// Valley-following heading probe (COASTER_REWRITE.md's "choose another beat"
// applied to headings): sample candidate bearings around `base` and keep the
// one whose ground ahead climbs LEAST above the current rail altitude, so
// long legs and big hills sit over low, along-contour or descending ground
// instead of ramming a flank. Only above-rail ground is penalized — heading
// downhill is free (an unsupported span, not a tunnel). Returns absolute yaw.
float pickLowHeading(Route& r, const TerrainQuery& terrain, float base, float spread,
                     float reach, int n) {
    float bestH = base, bestDev = 1e18f;
    for (int c = 0; c < n; c++) {
        float hCand = base + (n <= 1 ? 0.0f
                                     : spread * (2.0f * (float)c / (float)(n - 1) - 1.0f));
        float dx = sinf(hCand), dz = cosf(hCand);
        float dev = 0.0f;
        for (float w = 60.0f; w <= reach; w += 60.0f)
            dev += fmaxf(0.0f, terrain.height(r.endPose.pos.x + dx * w,
                                              r.endPose.pos.z + dz * w) +
                                   12.0f - r.endPose.pos.y);
        if (dev < bestDev) { bestDev = dev; bestH = hCand; }
    }
    return bestH;
}

// Steer the heading toward a bearing with one banked turn (no-op when nearly
// aligned). Bank scales with the turn angle, the roll ramps are sized from a
// rider roll-rate bound (~1.5 rad/s) at the LIVE speed, and the arc runs at
// a terrain-following grade toward its exit. Returns the angle turned.
float steerToward(Route& r, Rng& rng, const TerrainQuery& terrain, float targetYaw,
                  float radius, float bank, float v2) {
    float d = targetYaw - r.endPose.yaw;
    while (d > kPi) d -= 2.0f * kPi;
    while (d < -kPi) d += 2.0f * kPi;
    if (fabsf(d) < 0.12f) return 0.0f;
    TurnSpec t;
    t.totalAngle = d;
    t.bank = fminf(bank * rng.range(0.9f, 1.1f), 0.30f + 0.85f * fabsf(d));
    float v = sqrtf(fmaxf(v2, 100.0f));
    float rampMin = 1.875f * t.bank * v / 1.5f; // S5 peak roll rate <= 1.5 rad/s
    t.rampLen = fmaxf(rampMin, fminf(60.0f, fabsf(d) * radius * 0.3f));
    t.radius = radius;
    // The ramps must leave a real constant-radius middle.
    if (fabsf(d) * t.radius < 2.4f * t.rampLen) t.radius = 2.6f * t.rampLen / fabsf(d);
    gradeTurnToTerrain(r, terrain, t);
    emitTurn(r, t);
    levelOut(r);
    return d;
}

// Re-anchor the route to the terrain: drop/climb toward ground + clearance
// whenever the gap has drifted. Keeps the plan carving THROUGH relief
// (bounded cuts) instead of flying kilometers of sky or boring endless
// tunnels. Returns the updated v^2.
float settleToGround(Route& r, float v2, const TerrainQuery& terrain, float clearance) {
    float ground = terrain.height(r.endPose.pos.x, r.endPose.pos.z);
    float dy = r.endPose.pos.y - (ground + clearance);
    if (dy > 25.0f) {
        plannerDrop(r, dy);
        return v2After(v2, -dy);
    }
    if (dy < -25.0f) {
        plannerClimb(r, -dy, Tag::Line, false);
        return v2After(v2, -dy);
    }
    return v2;
}

// Staged docking onto a target pose. A Dubins-style CSC path (turn -
// straight - turn, deterministic, always solvable) carries the route to an
// ENTRY GATE well out on the target's approach line; the vertical difference
// rides inside the straight leg as a climb/drop; the final, short connector
// then has a guaranteed in-front, aligned target (see emitConnector's cusp
// guard for why the planner must guarantee that). Used for the cliff-dive
// approach and the station return alike.
float dockTo(Route& r, Rng& rng, float v2, const TerrainQuery& terrain,
             const Pose& target, float standoffDist) {
    // Gate sits just behind the target on its approach line; the final
    // connector spans only this much (kept short so it stays near the
    // target's ground and can't bore a long tunnel). The long haul to the
    // gate is a ground-following leg between the two Dubins arcs.
    const float gateBack = standoffDist + 40.0f;
    Vector3 gate = Vector3Subtract(target.pos,
                                   Vector3Scale(dirFromAngles(0.0f, target.yaw), gateBack));
    // Tighter docking circles than the ride's cruising turns: a shorter arc
    // sweeps less terrain, so a big heading change docks without a long arc
    // humping over relief.
    const float R = 100.0f;
    float x0 = r.endPose.pos.x, z0 = r.endPose.pos.z, y0 = r.endPose.yaw;
    float gx = gate.x, gz = gate.z, gy = target.yaw;
    float dx0 = gx - x0, dz0 = gz - z0;

    if (dx0 * dx0 + dz0 * dz0 > 60.0f * 60.0f) {
        // Candidate CSC paths; s = +1 right-hand circle, -1 left.
        float bestLen = 1e18f, bestA1 = 0.0f, bestA2 = 0.0f, bestLine = 0.0f;
        for (int c = 0; c < 4; c++) {
            float s1 = (c & 1) ? -1.0f : 1.0f;
            float s2 = (c & 2) ? -1.0f : 1.0f;
            // Right normal of heading psi in (x,z) is (cos psi, -sin psi).
            float csx = x0 + s1 * R * cosf(y0), csz = z0 - s1 * R * sinf(y0);
            float ctx = gx + s2 * R * cosf(gy), ctz = gz - s2 * R * sinf(gy);
            float Dx = ctx - csx, Dz = ctz - csz;
            float d = sqrtf(Dx * Dx + Dz * Dz);
            float lineHeading, lineLen;
            if (s1 == s2) { // external tangent
                if (d < 1.0f) continue;
                lineHeading = atan2f(Dx, Dz);
                lineLen = d;
            } else { // internal tangent
                if (d < 2.0f * R + 1.0f) continue;
                lineHeading = atan2f(Dx, Dz) + s1 * asinf(2.0f * R / d);
                lineLen = sqrtf(d * d - 4.0f * R * R);
            }
            // Arc sweeps, taken in each circle's own rotation direction.
            float a1 = lineHeading - y0;
            while (a1 * s1 < 0.0f) a1 += s1 * 2.0f * kPi;
            while (a1 * s1 >= 2.0f * kPi) a1 -= s1 * 2.0f * kPi;
            float a2 = gy - lineHeading;
            while (a2 * s2 < 0.0f) a2 += s2 * 2.0f * kPi;
            while (a2 * s2 >= 2.0f * kPi) a2 -= s2 * 2.0f * kPi;
            float total = R * (fabsf(a1) + fabsf(a2)) + lineLen;
            if (total < bestLen) {
                bestLen = total;
                bestA1 = a1;
                bestA2 = a2;
                bestLine = lineLen;
            }
        }
        // Emit: arc, straight (with the height difference inside), arc.
        if (fabsf(bestA1) > 0.10f) {
            TurnSpec t;
            t.totalAngle = bestA1;
            t.radius = R;
            t.bank = fminf(0.9f, 0.30f + 0.85f * fabsf(bestA1));
            float v = sqrtf(fmaxf(v2, 100.0f));
            t.rampLen = fmaxf(1.875f * t.bank * v / 1.5f, 24.0f);
            if (fabsf(bestA1) * t.radius < 2.4f * t.rampLen)
                t.radius = 2.6f * t.rampLen / fabsf(bestA1);
            gradeTurnToTerrain(r, terrain, t);
            emitTurn(r, t);
            levelOut(r);
        }
        // The long haul between the arcs rides the relief (bounded cuts),
        // never a plain straight boring through it. The target's own
        // elevation is reached by the short final connector, not here.
        if (bestLine > 24.0f) v2 = emitGroundLeg(r, v2, terrain, bestLine, 11.0f);
        if (fabsf(bestA2) > 0.10f) {
            TurnSpec t;
            t.totalAngle = bestA2;
            t.radius = R;
            t.bank = fminf(0.9f, 0.30f + 0.85f * fabsf(bestA2));
            float v = sqrtf(fmaxf(v2, 100.0f));
            t.rampLen = fmaxf(1.875f * t.bank * v / 1.5f, 24.0f);
            if (fabsf(bestA2) * t.radius < 2.4f * t.rampLen)
                t.radius = 2.6f * t.rampLen / fabsf(bestA2);
            gradeTurnToTerrain(r, terrain, t);
            emitTurn(r, t);
            levelOut(r);
        }
        (void)rng;
    }
    // The Dubins ramps distort the ideal arcs slightly, so we're near — not
    // on — the gate, still ~gateBack short of the target, aligned within the
    // residual. Exactly the connector's kind of job.
    emitConnector(r, target, Tag::Connector, false);
    return v2;
}

} // namespace

// ---------------------------------------------------------------------------
// buildRide — one closed lap, Falcon-inspired beat order (COASTER_REWRITE.md):
// station -> main launch -> top hat -> long descending transition -> low
// terrain turns/hills -> uphill LSM -> scanned escarpment cliff dive (or
// valley run when no natural site exists — never a fake cliff) -> flagship
// camelback -> inversions (1-3, locked roster) -> high-speed return turns ->
// brake -> closure connector back onto the station.
// ---------------------------------------------------------------------------
static Route buildRideOnce(uint32_t seed, const TerrainQuery& terrain) {
    Rng rng(seed);
    Route r;

    // Station siting: try seed-varied candidates and pick the flattest, LOW
    // ground (plains) — the ride's first kilometer (launch + top hat run)
    // extends straight ahead, so score the terrain along that line too.
    Pose p0;
    float stYaw = rng.range(0.0f, 2.0f * kPi);
    {
        float bestScore = 1e18f, bx = 0.0f, bz = 0.0f, byaw = stYaw;
        for (int cand = 0; cand < 12; cand++) {
            float cx = rng.range(-900.0f, 900.0f), cz = rng.range(-900.0f, 900.0f);
            float cyaw = rng.range(0.0f, 2.0f * kPi);
            float dx = sinf(cyaw), dz = cosf(cyaw);
            float h0 = terrain.height(cx, cz);
            float rough = 0.0f, high = fmaxf(0.0f, h0 - 45.0f);
            for (float w = 60.0f; w <= 900.0f; w += 60.0f) {
                float g = terrain.height(cx + dx * w, cz + dz * w);
                rough += fabsf(g - h0);
            }
            // Score the RETURN approach too (behind the station along -yaw):
            // the closure connector + brake dock in from there, so both sides
            // must be low, flat plains or the closure bores a shallow tunnel.
            for (float w = 60.0f; w <= 360.0f; w += 60.0f) {
                float g = terrain.height(cx - dx * w, cz - dz * w);
                rough += fmaxf(0.0f, g - h0); // only a rise behind matters
            }
            float score = rough + 6.0f * high;
            if (score < bestScore) { bestScore = score; bx = cx; bz = cz; byaw = cyaw; }
        }
        stYaw = byaw;
        p0.pos = Vector3{bx, terrain.height(bx, bz) + 2.0f, bz};
        p0.yaw = stYaw;
    }
    startRoute(r, p0, 1.0f);

    emitLine(r, 40.0f, Tag::Station, false);

    // Drag bookkeeping: v2 decays with track length since the last speed-set
    // point (launches reset the marker because they SET speed at their end).
    float sMark = r.endS;
    auto drag = [&](float v2) {
        float out = v2Drag(v2, r.endS - sMark);
        sMark = r.endS;
        return out;
    };

    // Main launch: k_v ~ k_r (transit ~1x real) — Falcon-anchored entries
    // at the locked 1.4-1.5x sizes want ~100 m/s (360 km/h) here.
    emitLine(r, 150.0f, Tag::Launch, true);
    float v2 = 100.0f * 100.0f;
    sMark = r.endS;

    // Signature top hat (locked 230 m rise), exiting ~12 m above the entry.
    TopHatSpec hat;
    hat.riseH = 230.0f * rng.range(0.95f, 1.05f);
    hat.dropH = hat.riseH - 12.0f;
    emitTopHat(r, hat);
    v2 = drag(v2After(v2, 12.0f));

    // Long descending transition onto the terrain.
    v2 = settleToGround(r, v2, terrain, 10.0f);
    v2 = drag(v2);

    // Low terrain leg: turn onto a VALLEY-FOLLOWING heading (probe candidate
    // bearings, prefer the one whose ground ahead climbs least above the rail
    // — the doc's "choose another beat" applied to headings), then mid
    // camelback and s-curve (sizes speed-derived).
    steerToward(r, rng, terrain,
                pickLowHeading(r, terrain, stYaw, 1.6f, 640.0f, 11), 170.0f, 1.0f, v2);
    v2 = drag(v2);
    v2 = settleToGround(r, v2, terrain, 12.0f);
    {
        float hillH = fminf(150.0f, 0.5f * v2 / (2.0f * kG));
        float vc2 = fmaxf(v2After(v2, hillH), 150.0f);
        CamelbackSpec cb;
        cb.height = hillH;
        cb.c = 1.35f * kG / (2.0f * vc2); // floater: 1.35x free-fall parabola
        cb.blendLen = fmaxf(30.0f, hillH * 0.5f);
        emitCamelback(r, cb);
    }
    v2 = drag(v2);
    emitLine(r, rng.range(20.0f, 50.0f), Tag::Line, false);
    {
        // Beat rejection, doc-style: the s-curve is a fixed-shape level plan
        // element (it can't follow relief), so accept it only where the ground
        // stays within a shallow band of the rail across its WHOLE footprint;
        // otherwise ride a terrain-following leg instead of boring through.
        float dx = sinf(r.endPose.yaw), dz = cosf(r.endPose.yaw);
        float worst = 0.0f;
        for (float w = 40.0f; w <= 320.0f; w += 40.0f)
            worst = fmaxf(worst, terrain.height(r.endPose.pos.x + dx * w,
                                                r.endPose.pos.z + dz * w) +
                                     12.0f - r.endPose.pos.y);
        if (worst < 30.0f) {
            SCurveSpec sc;
            sc.radius = 140.0f;
            sc.angle = rng.range(0.5f, 0.8f);
            sc.rampLen = 45.0f;
            emitSCurve(r, sc);
        } else {
            v2 = emitGroundLeg(r, v2, terrain, 160.0f, 12.0f);
        }
    }
    v2 = drag(v2);
    v2 = settleToGround(r, v2, terrain, 12.0f);

    // Inversions live in the naturally slower mid-ride leg (1-3 per lap,
    // locked roster; reversers pair so the lap heading survives).
    int nInv = 1 + rng.pick(3);
    bool usedPair = false;
    for (int i = 0; i < nInv; i++) {
        emitLine(r, rng.range(25.0f, 60.0f), Tag::Line, false);
        v2 = drag(v2);
        int kind = rng.pick(usedPair || i + 1 >= nInv ? 3 : 4);
        switch (kind) {
            case 0: {
                LoopSpec lp;
                lp.height = 78.0f * rng.range(0.92f, 1.06f);
                lp.vEntry = sqrtf(2.0f * kG * lp.height + rng.range(180.0f, 420.0f));
                v2 = conditionSpeed(r, v2, lp.vEntry * lp.vEntry);
                emitLoop(r, lp);
                break;
            }
            case 1: {
                CorkscrewSpec cs;
                cs.vElement = sqrtf(fminf(v2, 38.0f * 38.0f));
                v2 = conditionSpeed(r, v2, cs.vElement * cs.vElement);
                emitCorkscrew(r, cs);
                break;
            }
            case 2: {
                // The stall nets ~90 m of descent; being high AND slow needs
                // ENERGY, so any altitude deficit is made up with a powered
                // (LSM) climb before speed conditioning — never by letting
                // the element bore out the valley floor.
                ZeroGStallSpec st;
                st.vApex = rng.range(23.0f, 28.0f);
                float climbToApex = fmaxf(0.0f, (v2 - st.vApex * st.vApex) / (2.0f * kG));
                float ground = terrain.height(r.endPose.pos.x, r.endPose.pos.z);
                float apexY = r.endPose.pos.y + climbToApex;
                float deficit = (ground - 15.0f + 95.0f) - apexY;
                if (deficit > 5.0f) {
                    plannerClimb(r, deficit, Tag::Launch, true);
                    sMark = r.endS; // powered: speed maintained through it
                }
                v2 = conditionSpeed(r, v2, st.vApex * st.vApex);
                float yApex = r.endPose.pos.y;
                emitZeroGStall(r, st);
                v2 = v2After(st.vApex * st.vApex, r.endPose.pos.y - yApex);
                break;
            }
            case 3: {
                ImmelmannSpec im;
                im.height = 95.0f * rng.range(0.92f, 1.05f);
                im.vEntry = sqrtf(2.0f * kG * im.height + rng.range(220.0f, 450.0f));
                v2 = conditionSpeed(r, v2, im.vEntry * im.vEntry);
                emitImmelmann(r, im);
                v2 = v2After(im.vEntry * im.vEntry, im.height);
                emitLine(r, rng.range(30.0f, 60.0f), Tag::Line, false);
                DiveLoopSpec dl;
                dl.height = im.height;
                dl.vTop = sqrtf(fmaxf(v2, 140.0f));
                emitDiveLoop(r, dl);
                v2 = v2After(dl.vTop * dl.vTop, -dl.height);
                usedPair = true;
                i++;
                break;
            }
        }
        v2 = drag(v2);
        v2 = settleToGround(r, v2, terrain, 12.0f);
    }

    // Uphill LSM, then hunt a natural escarpment for the signature dive.
    plannerClimb(r, 24.0f, Tag::Launch, true);
    v2 = fmaxf(v2, 55.0f * 55.0f);
    sMark = r.endS;
    std::vector<EscarpmentSite> sites =
        scanEscarpments(terrain, r.endPose.pos, 700.0f);
    if (!sites.empty()) {
        const EscarpmentSite& site = sites[0];
        CliffDiveSpec cd;
        cd.climbHeight = 70.0f;
        float dirX = sinf(site.heading), dirZ = cosf(site.heading);
        float lip = 8.0f;
        for (float w = 8.0f; w <= 60.0f; w += 4.0f) {
            lip = w;
            if (terrain.height(site.crest.x + dirX * w, site.crest.z + dirZ * w) <
                site.crestY - 25.0f)
                break;
        }
        float diveStartY = site.crestY + 2.0f + cd.climbHeight;
        cd.diveHeight = diveStartY - (site.valleyY + 3.0f);

        Route probe;
        Pose o;
        startRoute(probe, o, 1.0f);
        emitLine(probe, 40.0f, Tag::Line, false);
        emitCliffDive(probe, cd);
        const Pose dv = probe.segs[probe.segs.size() - 3].entry;
        float alpha = site.heading - dv.yaw;
        float ca = cosf(alpha), sa = sinf(alpha);
        Vector3 dRot{dv.pos.x * ca + dv.pos.z * sa, dv.pos.y,
                     dv.pos.z * ca - dv.pos.x * sa};
        Pose app;
        app.pos = Vector3{site.crest.x + dirX * lip - dRot.x, diveStartY - dRot.y,
                          site.crest.z + dirZ * lip - dRot.z};
        app.yaw = alpha;
        v2 = dockTo(r, rng, v2, terrain, app, 150.0f);
        emitLine(r, 40.0f, Tag::Line, false);
        emitCliffDive(r, cd);
        v2 = v2After(fmaxf(v2, 30.0f * 30.0f), -(cd.diveHeight - cd.climbHeight));
        v2 = drag(v2);
    } else {
        // No natural site: an honest valley run — LSM + big drop into the
        // lowest nearby ground. Never a fake cliff.
        emitLine(r, 90.0f, Tag::Launch, true);
        v2 = fmaxf(v2, 72.0f * 72.0f);
        sMark = r.endS;
        float ground = terrain.height(r.endPose.pos.x, r.endPose.pos.z);
        float dy = r.endPose.pos.y - (ground + 8.0f);
        if (dy > 20.0f) {
            plannerDrop(r, dy);
            v2 = v2After(v2, -dy);
        }
        v2 = drag(v2);
    }

    // Flagship camelback (locked ~240 m) off an LSM boost to its MATCHED
    // entry (~1.45x Falcon's ~250 km/h -> ~100 m/s), keeping transit ~1x.
    // Orient it along low/descending ground first: a 240 m symmetric hill's
    // far half must FLOAT over falling terrain (an unsupported span), not bury
    // itself in a rising flank (a tunnel). Its own crest naturally clears any
    // hump under the footprint.
    v2 = settleToGround(r, v2, terrain, 12.0f);
    steerToward(r, rng, terrain,
                pickLowHeading(r, terrain, r.endPose.yaw, 1.4f, 700.0f, 11), 200.0f, 0.8f, v2);
    v2 = settleToGround(r, v2, terrain, 12.0f);
    emitLine(r, 110.0f, Tag::Launch, true);
    v2 = fmaxf(v2, 100.0f * 100.0f);
    sMark = r.endS;
    {
        CamelbackSpec cb;
        cb.height = 240.0f * rng.range(0.96f, 1.04f);
        float vc2 = fmaxf(v2After(v2, cb.height), 180.0f);
        cb.c = 1.25f * kG / (2.0f * vc2);
        cb.blendLen = 120.0f;
        emitCamelback(r, cb);
    }
    v2 = drag(v2);
    v2 = settleToGround(r, v2, terrain, 12.0f);

    // Return docking: hop toward a point well BEFORE the station until we're
    // reasonably close and roughly aligned, then a controlled two-stage
    // closure — connector to an aligned pre-station pose, brake, and a short
    // straight-shot connector onto the station entry. A single wild closure
    // connector from an arbitrary pose can cusp (near-zero-speed quintic),
    // which corrupts the seam frame; staged docking keeps every piece tame.
    {
        Pose dock = p0;
        dock.pos = Vector3Subtract(p0.pos,
                                   Vector3Scale(dirFromAngles(0.0f, stYaw), 200.0f));
        dock.yaw = stYaw;
        v2 = dockTo(r, rng, v2, terrain, dock, 180.0f);
        v2 = drag(v2);
    }
    emitLine(r, 60.0f, Tag::Brake, false);
    Pose home = p0;
    emitConnector(r, home, Tag::Connector, false);
    if (!r.samples.empty() &&
        Vector3Distance(r.samples.back().pos, r.samples.front().pos) < 0.5f * r.ds)
        r.samples.pop_back();
    r.closed = true;

    buildFrames(r);
    return r;
}

Route buildRide(uint32_t seed, const TerrainQuery& terrain) {
    // Bounded layout retries: whether a given seed's post-inversion position
    // lands near a natural escarpment (rare by design) varies attempt to
    // attempt, so among the clean+bounded variations PREFER one that found a
    // real cliff-dive site — the signature element — falling back to the first
    // clean variation without one. Cut/tunnel is the preferred encroachment
    // response; rejection is only for genuinely unresolvable conflicts
    // (TERRAIN_CONTRACT.md rule 3).
    const ClearanceLimits lim;
    auto hasCliff = [](const Route& r) {
        for (const SegmentRec& s : r.segs)
            if (s.tag == Tag::CliffDive) return true;
        return false;
    };
    Route best, cleanNoCliff;
    bool haveClean = false;
    float bestScore = 1e30f;
    for (int attempt = 0; attempt < 8; attempt++) {
        Route r = buildRideOnce(seed + (uint32_t)attempt * 7919u, terrain);
        ValidationReport rep = validateRoute(r, &terrain);
        bool pass = rep.pass();
        if (pass && clearanceDecision(rep, lim) != ClearanceDecision::Reject) {
            if (hasCliff(r)) return r;        // clean, bounded AND a cliff dive
            if (!haveClean) { cleanNoCliff = r; haveClean = true; } // keep as fallback
            continue;
        }
        // Otherwise score by how far the worst cut/tunnel span overruns the
        // bounded-cut limits (depth weighted to meters-equivalent) plus a big
        // penalty for a failed continuity/element check, and keep the least
        // bad so a marginal seed still returns its most honest layout.
        float overage = 0.0f;
        for (const ClearanceSpan& c : rep.clearance) {
            if (c.kind == ClearanceSpan::Kind::LowClearance ||
                c.kind == ClearanceSpan::Kind::UnsupportedSpan)
                continue;
            overage = fmaxf(overage, (c.s1 - c.s0) - lim.maxCutLen);
            overage = fmaxf(overage, (c.maxDepth - lim.maxTunnelDepth) * 6.0f);
        }
        float score = (pass ? 0.0f : 1e6f) + overage;
        if (score < bestScore) { bestScore = score; best = r; }
    }
    if (haveClean) return cleanNoCliff; // a clean layout, just no natural cliff
    // No variation was clean AND bounded: return the least-bad — the caller's
    // validation surfaces exactly what's wrong (fail loudly, never bend
    // geometry to pass).
    return best;
}

Route buildSmokeRoute(uint32_t seed) {
    (void)seed; // deterministic: the smoke route exists to exercise emitters,
                // framing and the adapter, not to be a ride.
    Route r;
    Pose p0;
    p0.pos = Vector3{0.0f, 40.0f, 0.0f};
    startRoute(r, p0, 1.0f);

    emitLine(r, 30.0f, Tag::Station, false);
    emitLine(r, 80.0f, Tag::Launch, true);
    emitLine(r, 150.0f, Tag::Line, false);

    // A pose-to-pose connector: up 20 m, 60 m ahead, 40 m sideways, heading
    // yawed 35 degrees, straight (zero curvature) at both ends.
    Pose target = r.endPose;
    target.pos = Vector3Add(r.endPose.pos, Vector3{40.0f, 20.0f, 60.0f});
    target.yaw = r.endPose.yaw + degToRad(35.0f);
    target.pitch = 0.0f;
    target.roll = 0.0f;
    emitConnector(r, target, Tag::Connector, false);

    emitLine(r, 60.0f, Tag::Line, false);

    buildFrames(r);
    return r;
}

// Step-2 proof route: every vertical-profile primitive at realistic-ish scale
// on one straight heading. Sizes are PROVISIONAL harness values (see
// REALISM_SCALE.md "ask before locking in" — final planner targets are a user
// decision); what this route proves is continuity and element acceptance,
// which are size-independent. `ds` is a parameter so the harness can also
// validate at the acceptance sweep's finer 0.25-0.5 m resolution.
Route buildStep2Route(uint32_t seed) { return buildStep2RouteDs(seed, 1.0f); }
Route buildStep2RouteDs(uint32_t seed, float ds) {
    (void)seed;
    Route r;
    Pose p0;
    p0.pos = Vector3{0.0f, 80.0f, 0.0f};
    startRoute(r, p0, ds);

    emitLine(r, 30.0f, Tag::Station, false);
    emitLine(r, 120.0f, Tag::Launch, true);

    TopHatSpec hat; // locked defaults: 230 up / 225 down, 65 deg faces
    emitTopHat(r, hat);

    emitLine(r, 40.0f, Tag::Line, false);

    CamelbackSpec cbBig;
    cbBig.height = 50.0f;
    cbBig.c = 0.012f;
    cbBig.blendLen = 40.0f;
    emitCamelback(r, cbBig);

    emitLine(r, 30.0f, Tag::Line, false);

    CamelbackSpec cbSmall;
    cbSmall.height = 32.0f;
    cbSmall.c = 0.02f;
    cbSmall.blendLen = 30.0f;
    emitCamelback(r, cbSmall);

    emitLine(r, 40.0f, Tag::Line, false);

    DropSpec drop; // defaults: 60 m descent @ 70 deg
    emitDrop(r, drop);

    emitLine(r, 60.0f, Tag::Line, false);

    buildFrames(r);
    return r;
}

// Step-3 proof route: plan-view primitives (turn, s-curve, helix) between
// straights. Same provisional-size caveat as buildStep2Route.
Route buildStep3Route(uint32_t seed) { return buildStep3RouteDs(seed, 1.0f); }
Route buildStep3RouteDs(uint32_t seed, float ds) {
    (void)seed;
    Route r;
    Pose p0;
    p0.pos = Vector3{0.0f, 80.0f, 0.0f};
    startRoute(r, p0, ds);

    emitLine(r, 40.0f, Tag::Line, false);

    TurnSpec turn; // defaults: 90 deg right, R=110, 60 deg bank
    emitTurn(r, turn);

    emitLine(r, 30.0f, Tag::Line, false);

    SCurveSpec sc; // defaults: 40 deg lobes, R=120
    emitSCurve(r, sc);

    emitLine(r, 30.0f, Tag::Line, false);

    HelixSpec hx; // defaults: R=70, 1.5 revs, 12 m/rev
    emitHelix(r, hx);

    emitLine(r, 50.0f, Tag::Line, false);

    buildFrames(r);
    return r;
}

// Step-5 proof route: the first two inversions — vertical loop and
// Immelmann, at the LOCKED grand sizes (78 m / 95 m = 1.43x their Tormenta
// anchors; REALISM_SCALE.md "Locked element targets", user 2026-07-10).
Route buildStep5Route(uint32_t seed) { return buildStep5RouteDs(seed, 1.0f); }
Route buildStep5RouteDs(uint32_t seed, float ds) {
    (void)seed;
    Route r;
    Pose p0;
    p0.pos = Vector3{0.0f, 50.0f, 0.0f};
    startRoute(r, p0, ds);

    emitLine(r, 50.0f, Tag::Line, false);

    LoopSpec loop; // locked: 78 m teardrop @ 44 m/s entry
    emitLoop(r, loop);

    emitLine(r, 50.0f, Tag::Line, false);

    ImmelmannSpec imm; // locked: 95 m half-loop + half-roll @ 47 m/s
    emitImmelmann(r, imm);

    // Exits reversed, 95 m above the entry line — run back over the route.
    emitLine(r, 40.0f, Tag::Line, false);

    DiveLoopSpec dl; // the Immelmann's mirror: dives the 95 m back down
    emitDiveLoop(r, dl);

    // Reversed again: original heading, back near the entry altitude.
    emitLine(r, 40.0f, Tag::Line, false);

    ZeroGStallSpec st; // locked: 2.25 s weightless inverted hold
    emitZeroGStall(r, st);

    emitLine(r, 30.0f, Tag::Line, false);

    CorkscrewSpec cs; // locked band: 95 deg/s full rotation
    emitCorkscrew(r, cs);

    emitLine(r, 60.0f, Tag::Line, false);

    buildFrames(r);
    return r;
}

} // namespace v2
