// Track V2 — continuity, clearance and element acceptance checks
// (COASTER_REWRITE.md "Acceptance harness", TERRAIN_CONTRACT.md "Validation").
//
// Two independent layers:
//  1. EXACT join checks — emitters record entry/exit poses per primitive
//     (Route::segs); consecutive segments must agree in position, angles,
//     roll and curvature. This is where a V1-style "stitched at a control
//     point" bug would show, so tolerances are tight, not statistical.
//  2. Sample sweep — geometric self-consistency of the dense samples
//     (uniform arc spacing, tangent vs chord, position-derived curvature vs
//     the stored analytic schedule, roll-rate steps). This layer catches
//     integrator bugs even when the analytic bookkeeping looks clean.
// Deliberate joints (station/brake) keep a continuous rider tangent but may
// step curvature/roll-rate (SHAPES.md "Shared rules"); only those tags are
// exempt from the C2 criteria.
#include <cmath>
#include <cstdio>

#include "track_math.h"

namespace v2 {

static bool isDeliberateJoint(Tag a, Tag b) {
    auto j = [](Tag t) { return t == Tag::Station || t == Tag::Brake; };
    return j(a) || j(b);
}

static void checkJoin(const SegmentRec& a, const SegmentRec& b, float seamGap,
                      ValidationReport& rep) {
    // seamGap: expected position gap (0 for ordinary joins; closed-route seam
    // passes the station straight, also 0). Kept explicit for clarity.
    (void)seamGap;
    auto flag = [&](const char* q, float jump) {
        rep.discontinuities.push_back(Discontinuity{a.s1, q, jump, b.tag});
    };
    float dPos = Vector3Distance(a.exit.pos, b.entry.pos);
    if (dPos > 1e-2f) flag("position", dPos);
    float dPitch = fabsf(a.exit.pitch - b.entry.pitch);
    if (dPitch > 1e-3f) flag("pitch", dPitch);
    float dYaw = fabsf(a.exit.yaw - b.entry.yaw);
    // Yaw is stored unwrapped; joins may legitimately differ by 2*pi*k.
    dYaw = fmodf(dYaw, 2.0f * kPi);
    if (dYaw > kPi) dYaw = 2.0f * kPi - dYaw;
    if (dYaw > 1e-3f) flag("yaw", dYaw);
    float dRoll = fabsf(a.exit.roll - b.entry.roll);
    if (dRoll > 1e-3f) flag("roll", dRoll);
    if (!isDeliberateJoint(a.tag, b.tag)) {
        float dkP = fabsf(a.exit.kPitch - b.entry.kPitch);
        float dkY = fabsf(a.exit.kYaw - b.entry.kYaw);
        if (dkP > 1e-3f) flag("curvature", dkP);
        if (dkY > 1e-3f) flag("curvature", dkY);
    }
}

static void sweepSamples(const Route& r, ValidationReport& rep) {
    const float ds = r.ds;
    size_t n = r.samples.size();
    float prevRollRate = 0.0f;
    bool havePrevRollRate = false;

    for (size_t i = 1; i < n; i++) {
        const Sample& A = r.samples[i - 1];
        const Sample& B = r.samples[i];

        // Chord vs arc: a 1 m arc step at curvature k has chord ~ ds*(1-k^2*ds^2/24);
        // anything past 2% is a teleport/kink, not curvature.
        float chord = Vector3Distance(A.pos, B.pos);
        if (fabsf(chord - ds) > 0.02f * ds)
            rep.discontinuities.push_back(Discontinuity{B.s, "position", chord - ds, B.tag});

        // Stored analytic angles must integrate consistently with themselves:
        // the angle step should equal the trapezoidal integral of the stored
        // curvature over the step.
        float pitchResid = fabsf((B.pitch - A.pitch) - 0.5f * (A.kPitch + B.kPitch) * ds);
        if (pitchResid > 4e-3f)
            rep.discontinuities.push_back(Discontinuity{B.s, "pitch", pitchResid, B.tag});
        float yawResid = fabsf((B.yaw - A.yaw) - 0.5f * (A.kYaw + B.kYaw) * ds);
        if (yawResid > 4e-3f)
            rep.discontinuities.push_back(Discontinuity{B.s, "yaw", yawResid, B.tag});

        // Tangent must match the chord direction to within the turning budget.
        float cosT = Vector3DotProduct(B.tan, Vector3Scale(Vector3Subtract(B.pos, A.pos),
                                                           1.0f / fmaxf(chord, 1e-6f)));
        float kMag = sqrtf(B.kPitch * B.kPitch + B.kYaw * B.kYaw);
        float allow = 0.75f * kMag * ds + 0.01f;
        if (cosT < cosf(allow) - 1e-4f)
            rep.discontinuities.push_back(
                Discontinuity{B.s, "tangent", acosf(fminf(fmaxf(cosT, -1.0f), 1.0f)), B.tag});

        // Roll rate must be continuous everywhere outside deliberate joints
        // (the railway-transition constraint: no step in droll/ds).
        float rollRate = (B.roll - A.roll) / ds;
        if (havePrevRollRate) {
            float jump = fabsf(rollRate - prevRollRate);
            // S5 roll ramps bound |d2roll/ds2| well under 0.05 for any ramp
            // this game uses; a genuine step lands far above this.
            if (jump > 0.05f * ds && !isDeliberateJoint(A.tag, B.tag))
                rep.discontinuities.push_back(Discontinuity{B.s, "rollRate", jump, B.tag});
        }
        prevRollRate = rollRate;
        havePrevRollRate = true;
    }
}

static void sweepClearance(const Route& r, const TerrainQuery& t, ValidationReport& rep) {
    // Measure-and-report only: the accept/cut/replan POLICY lives in the
    // planner (TERRAIN_CONTRACT.md route-interaction rule 3). Near-zero
    // cut/tunnel usage across seeds is a red flag the caller must surface.
    const float kTunnelDepth = 6.0f; // deeper than this: tunnel, else open cut
    ClearanceSpan cur;
    bool open = false;
    for (const Sample& smp : r.samples) {
        float ground = t.height(smp.pos.x, smp.pos.z);
        float depth = ground - smp.pos.y; // >0: rail below ground
        bool below = depth > 0.0f;
        if (below && !open) {
            cur = ClearanceSpan{};
            cur.s0 = smp.s;
            open = true;
        }
        if (open) {
            cur.maxDepth = fmaxf(cur.maxDepth, depth);
            cur.s1 = smp.s;
        }
        if (!below && open) {
            cur.kind = cur.maxDepth > kTunnelDepth ? ClearanceSpan::Kind::Tunnel
                                                   : ClearanceSpan::Kind::Cut;
            float len = cur.s1 - cur.s0;
            (cur.kind == ClearanceSpan::Kind::Tunnel ? rep.tunnelLength : rep.cutLength) += len;
            rep.clearance.push_back(cur);
            open = false;
        }
    }
    if (open) {
        cur.kind = cur.maxDepth > kTunnelDepth ? ClearanceSpan::Kind::Tunnel
                                               : ClearanceSpan::Kind::Cut;
        float len = cur.s1 - cur.s0;
        (cur.kind == ClearanceSpan::Kind::Tunnel ? rep.tunnelLength : rep.cutLength) += len;
        rep.clearance.push_back(cur);
    }
}

ValidationReport validateRoute(const Route& r, const TerrainQuery* terrain) {
    ValidationReport rep;
    if (r.samples.size() < 2) {
        rep.elementFailures.push_back("route has fewer than 2 samples");
        return rep;
    }
    for (size_t i = 1; i < r.segs.size(); i++)
        checkJoin(r.segs[i - 1], r.segs[i], 0.0f, rep);
    if (r.closed && r.segs.size() > 1)
        checkJoin(r.segs.back(), r.segs.front(), 0.0f, rep);

    sweepSamples(r, rep);
    if (terrain && terrain->height) sweepClearance(r, *terrain, rep);

    // Per-element acceptance checks (top-hat apex/faces, camelback symmetry,
    // drop pull-out) land with their primitives in migration step 2.
    return rep;
}

} // namespace v2
