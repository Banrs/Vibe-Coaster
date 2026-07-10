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
            // Legit bound: an S5 roll ramp of dRoll over L has
            // |d2roll/ds2| <= 5.78*dRoll/L^2 — under 0.0025 for every ramp
            // this game uses (60 deg over 50 m). 0.01 gives 4x margin while
            // still catching a ~0.6 deg bank kink at one sample.
            if (jump > 0.01f * ds && !isDeliberateJoint(A.tag, B.tag))
                rep.discontinuities.push_back(Discontinuity{B.s, "rollRate", jump, B.tag});
        }
        prevRollRate = rollRate;
        havePrevRollRate = true;

        // Frame sweep (after buildFrames): unit up, orthogonal to the
        // tangent, and no frame flips — the twist between adjacent samples
        // stays far below legitimate roll-rate + transport turning budgets.
        float upLen = Vector3Length(B.up);
        if (fabsf(upLen - 1.0f) > 1e-2f)
            rep.discontinuities.push_back(Discontinuity{B.s, "frameUnit", upLen - 1.0f, B.tag});
        float upDotTan = fabsf(Vector3DotProduct(B.up, B.tan));
        if (upDotTan > 3e-2f)
            rep.discontinuities.push_back(Discontinuity{B.s, "frameOrtho", upDotTan, B.tag});
        float upTwistCos = Vector3DotProduct(A.up, B.up);
        if (upTwistCos < cosf(0.15f))
            rep.discontinuities.push_back(
                Discontinuity{B.s, "frameTwist", acosf(fmaxf(-1.0f, fminf(1.0f, upTwistCos))), B.tag});
    }
}

static void sweepClearance(const Route& r, const TerrainQuery& t, ValidationReport& rep) {
    // Measure-and-report only: the accept/cut/replan POLICY lives in
    // clearanceDecision (TERRAIN_CONTRACT.md rule 3). Near-zero cut/tunnel
    // usage across seeds is a red flag the caller must surface.
    //
    // Classification looks at the train envelope, not just the rail line:
    // a below-ground sample whose LATERAL neighbours (+-3 m) are also buried
    // is enclosed — a tunnel — even when shallow; an open trench is a cut.
    const float kTunnelDepth = 6.0f;   // depth beyond which any bore is a tunnel
    const float kEnvelope = 3.0f;      // lateral half-width + headroom probe
    const float kUnsupported = 45.0f;  // tallest plausible support (PROVISIONAL)

    ClearanceSpan cur;
    bool open = false;
    int enclosedCount = 0, spanCount = 0;
    auto closeSpan = [&]() {
        bool enclosed = enclosedCount * 2 > spanCount;
        cur.kind = (cur.maxDepth > kTunnelDepth || enclosed) ? ClearanceSpan::Kind::Tunnel
                                                             : ClearanceSpan::Kind::Cut;
        float len = cur.s1 - cur.s0;
        (cur.kind == ClearanceSpan::Kind::Tunnel ? rep.tunnelLength : rep.cutLength) += len;
        rep.clearance.push_back(cur);
        open = false;
    };
    ClearanceSpan sky;
    bool skyOpen = false;
    for (const Sample& smp : r.samples) {
        float ground = t.height(smp.pos.x, smp.pos.z);
        float depth = ground - smp.pos.y; // >0: rail below ground
        if (depth > 0.0f) {
            if (!open) {
                cur = ClearanceSpan{};
                cur.s0 = smp.s;
                enclosedCount = spanCount = 0;
                open = true;
            }
            cur.maxDepth = fmaxf(cur.maxDepth, depth);
            cur.s1 = smp.s;
            spanCount++;
            // Lateral envelope probe (horizontal normal of the tangent).
            float hx = smp.tan.z, hz = -smp.tan.x;
            float hl = sqrtf(hx * hx + hz * hz);
            if (hl > 1e-4f) {
                hx /= hl; hz /= hl;
                float gL = t.height(smp.pos.x + hx * kEnvelope, smp.pos.z + hz * kEnvelope);
                float gR = t.height(smp.pos.x - hx * kEnvelope, smp.pos.z - hz * kEnvelope);
                if (fminf(gL, gR) > smp.pos.y + kEnvelope) enclosedCount++;
            }
        } else if (open) {
            closeSpan();
        }
        // Unsupported spans: rail farther above ground than supports reach.
        if (-depth > kUnsupported) {
            if (!skyOpen) {
                sky = ClearanceSpan{};
                sky.s0 = smp.s;
                sky.kind = ClearanceSpan::Kind::UnsupportedSpan;
                skyOpen = true;
            }
            sky.s1 = smp.s;
            sky.maxDepth = fmaxf(sky.maxDepth, -depth);
        } else if (skyOpen) {
            rep.unsupportedLength += sky.s1 - sky.s0;
            rep.clearance.push_back(sky);
            skyOpen = false;
        }
    }
    if (open) closeSpan();
    if (skyOpen) {
        rep.unsupportedLength += sky.s1 - sky.s0;
        rep.clearance.push_back(sky);
    }
}

// ---------------------------------------------------------------------------
// Per-element acceptance checks (COASTER_REWRITE.md acceptance harness 2–4).
// An "element run" is a maximal group of consecutive segments with the same
// element tag; checks operate on the dense samples inside the run.
// ---------------------------------------------------------------------------
namespace {

struct ElemRun {
    Tag tag;
    int i0, i1;      // inclusive sample index range
    int firstSeg, lastSeg;
};

std::vector<ElemRun> elementRuns(const Route& r) {
    std::vector<ElemRun> runs;
    for (size_t k = 0; k < r.segs.size(); k++) {
        Tag t = r.segs[k].tag;
        if (!runs.empty() && runs.back().tag == t && runs.back().lastSeg == (int)k - 1) {
            runs.back().lastSeg = (int)k;
            runs.back().i1 = (int)floorf(r.segs[k].s1 / r.ds + 1e-4f);
        } else {
            ElemRun run;
            run.tag = t;
            run.firstSeg = run.lastSeg = (int)k;
            run.i0 = (int)ceilf(r.segs[k].s0 / r.ds - 1e-4f);
            run.i1 = (int)floorf(r.segs[k].s1 / r.ds + 1e-4f);
            runs.push_back(run);
        }
    }
    for (ElemRun& run : runs) {
        if (run.i1 >= (int)r.samples.size()) run.i1 = (int)r.samples.size() - 1;
        if (run.i0 < 0) run.i0 = 0;
    }
    return runs;
}

int countHeightApexes(const Route& r, const ElemRun& run) {
    int apexes = 0;
    for (int i = run.i0 + 1; i < run.i1; i++) {
        float y0 = r.samples[i - 1].pos.y, y1 = r.samples[i].pos.y, y2 = r.samples[i + 1].pos.y;
        if (y1 > y0 && y1 >= y2 && r.samples[i + 1].pos.y < y1) apexes++;
    }
    return apexes;
}

// "Zero consecutive flat samples at the crest": inside the near-level region
// containing the apex, pitch must fall STRICTLY monotonically — a shelf sits
// at constant ~0 pitch, while any honest crest (even a gentle floater) keeps
// moving through zero. Element bases legitimately dwell near zero pitch, so
// this deliberately checks only the apex neighbourhood.
bool crestHasShelf(const Route& r, const ElemRun& run) {
    int apex = run.i0;
    for (int i = run.i0; i <= run.i1; i++)
        if (r.samples[i].pos.y > r.samples[apex].pos.y) apex = i;
    const float flat = degToRad(0.75f);
    int lo = apex, hi = apex;
    while (lo > run.i0 && fabsf(r.samples[lo - 1].pitch) < flat) lo--;
    while (hi < run.i1 && fabsf(r.samples[hi + 1].pitch) < flat) hi++;
    const float minStep = degToRad(0.02f);
    for (int i = lo + 1; i <= hi; i++)
        if (r.samples[i].pitch > r.samples[i - 1].pitch - minStep) return true;
    return false;
}

int longestPitchBand(const Route& r, const ElemRun& run, float lo, float hi) {
    int best = 0, cur = 0;
    for (int i = run.i0; i <= run.i1; i++) {
        float p = r.samples[i].pitch;
        cur = (p >= lo && p <= hi) ? cur + 1 : 0;
        if (cur > best) best = cur;
    }
    return best;
}

void fail(ValidationReport& rep, const ElemRun& run, const Route& r, const char* msg) {
    char buf[160];
    snprintf(buf, sizeof buf, "%s@s=%.0f..%.0f: %s", tagName(run.tag),
             r.segs[run.firstSeg].s0, r.segs[run.lastSeg].s1, msg);
    rep.elementFailures.push_back(buf);
}

void checkTopHat(const Route& r, const ElemRun& run, ValidationReport& rep) {
    if (countHeightApexes(r, run) != 1) fail(rep, run, r, "crest apex count != 1");
    if (crestHasShelf(r, run)) fail(rep, run, r, "flat shelf at crest");
    float peakUp = -10.0f, peakDown = 10.0f;
    for (int i = run.i0; i <= run.i1; i++) {
        peakUp = fmaxf(peakUp, r.samples[i].pitch);
        peakDown = fminf(peakDown, r.samples[i].pitch);
    }
    // Sustained faces in the 60–70 deg band, both signs (acceptance test 2).
    if (longestPitchBand(r, run, degToRad(60.0f), degToRad(70.0f)) < 5)
        fail(rep, run, r, "ascent face not sustained in 60..70 deg");
    if (longestPitchBand(r, run, degToRad(-70.0f), degToRad(-60.0f)) < 5)
        fail(rep, run, r, "descent face not sustained in -60..-70 deg");
    if (fabsf(peakUp + peakDown) > degToRad(5.0f))
        fail(rep, run, r, "ascent/descent peak grades differ by > 5 deg");
}

void checkCamelback(const Route& r, const ElemRun& run, ValidationReport& rep) {
    if (countHeightApexes(r, run) != 1) fail(rep, run, r, "crest count != 1");
    if (crestHasShelf(r, run)) fail(rep, run, r, "plateau at crest");
    // No mid-hill flattening: between the steepest-up and steepest-down
    // points, pitch must fall monotonically (the parabola+blend construction
    // guarantees it; terrain feedback or a bad blend would break it).
    int iMax = run.i0, iMin = run.i0;
    for (int i = run.i0; i <= run.i1; i++) {
        if (r.samples[i].pitch > r.samples[iMax].pitch) iMax = i;
        if (r.samples[i].pitch < r.samples[iMin].pitch) iMin = i;
    }
    if (iMax >= iMin) {
        fail(rep, run, r, "pitch extremes out of order");
        return;
    }
    for (int i = iMax + 1; i <= iMin; i++)
        if (r.samples[i].pitch > r.samples[i - 1].pitch + 1e-4f) {
            fail(rep, run, r, "mid-hill flattening (pitch not monotone over the hill)");
            break;
        }
    // Mirror-image halves (SHAPES.md): pitch antisymmetric about the crest.
    // The crest generally falls BETWEEN samples, so locate it as the
    // interpolated pitch zero-crossing and compare interpolated pitch at
    // +-d around it (a sample-anchored comparison would carry up to ~1.4 deg
    // of legitimate sub-sample offset bias).
    float sCrest = -1.0f;
    for (int i = iMax; i < iMin; i++)
        if (r.samples[i].pitch > 0.0f && r.samples[i + 1].pitch <= 0.0f) {
            float p0 = r.samples[i].pitch, p1 = r.samples[i + 1].pitch;
            sCrest = r.samples[i].s + r.ds * p0 / (p0 - p1);
            break;
        }
    if (sCrest < 0.0f) {
        fail(rep, run, r, "no pitch zero-crossing at crest");
        return;
    }
    auto pitchAt = [&](float s) {
        float fi = s / r.ds;
        int i = (int)fi;
        float f = fi - (float)i;
        return r.samples[i].pitch * (1.0f - f) + r.samples[i + 1].pitch * f;
    };
    float reach = fminf(sCrest - r.samples[run.i0].s, r.samples[run.i1].s - sCrest) - r.ds;
    for (float d = 2.0f; d < reach; d += 3.0f)
        if (fabsf(pitchAt(sCrest + d) + pitchAt(sCrest - d)) > degToRad(1.0f)) {
            fail(rep, run, r, "halves are not mirror images (pitch asymmetry > 1 deg)");
            break;
        }
}

void checkCliffDive(const Route& r, const ElemRun& run, ValidationReport& rep) {
    // Signature element: powered climb present, ONE apex, outward bank at the
    // summit turn, near-vertical sustained face, completed pull-out.
    float peakUp = -10.0f, minPitch = 10.0f;
    bool anyChain = false;
    for (int i = run.i0; i <= run.i1; i++) {
        peakUp = fmaxf(peakUp, r.samples[i].pitch);
        minPitch = fminf(minPitch, r.samples[i].pitch);
        anyChain |= r.samples[i].chain;
    }
    if (!anyChain) fail(rep, run, r, "no powered climb");
    if (peakUp < degToRad(12.0f)) fail(rep, run, r, "climb face missing");
    if (minPitch > degToRad(-80.0f)) fail(rep, run, r, "dive face not near-vertical");
    if (longestPitchBand(r, run, minPitch - degToRad(1.0f), minPitch + degToRad(1.0f)) < 3)
        fail(rep, run, r, "dive face not sustained");
    // Height structure is rise -> flat summit turn -> fall (no strict apex),
    // so instead require: once the dive has begun (5 m below the peak), the
    // track never climbs again inside this element.
    {
        int iPeak = run.i0;
        for (int i = run.i0; i <= run.i1; i++)
            if (r.samples[i].pos.y > r.samples[iPeak].pos.y) iPeak = i;
        bool fell = false;
        float minSince = r.samples[iPeak].pos.y;
        for (int i = iPeak; i <= run.i1; i++) {
            float y = r.samples[i].pos.y;
            minSince = fminf(minSince, y);
            if (!fell && y < r.samples[iPeak].pos.y - 5.0f) fell = true;
            if (fell && y > minSince + 0.5f) {
                fail(rep, run, r, "track rises again inside the dive");
                break;
            }
        }
    }
    // Outward bank: wherever the summit turn is banked, roll and kYaw agree
    // in sign (inward banking would make them oppose; see the roll-sign note
    // in track_primitives.cpp).
    for (int i = run.i0; i <= run.i1; i++) {
        const Sample& s = r.samples[i];
        if (fabsf(s.roll) > degToRad(5.0f) && fabsf(s.kYaw) > 1e-4f && s.roll * s.kYaw < 0.0f) {
            fail(rep, run, r, "summit turn banked inward, not outward");
            break;
        }
    }
    const Pose& planned = r.segs[run.lastSeg].exit;
    if (fabsf(r.samples[run.i1].pitch - planned.pitch) > degToRad(1.5f))
        fail(rep, run, r, "pull-out did not complete");
}

void checkDrop(const Route& r, const ElemRun& run, ValidationReport& rep) {
    // The drop must hold a sustained face and finish its planned pull-out
    // (exit pitch equals the segment record's plan — no early hand-off).
    float minPitch = 10.0f;
    for (int i = run.i0; i <= run.i1; i++) minPitch = fminf(minPitch, r.samples[i].pitch);
    if (minPitch > degToRad(-30.0f)) fail(rep, run, r, "no real descent face");
    if (longestPitchBand(r, run, minPitch - degToRad(1.0f), minPitch + degToRad(1.0f)) < 3)
        fail(rep, run, r, "descent face not sustained");
    const Pose& planned = r.segs[run.lastSeg].exit;
    const Sample& last = r.samples[run.i1];
    if (fabsf(last.pitch - planned.pitch) > degToRad(1.5f))
        fail(rep, run, r, "pull-out did not complete to planned exit pitch");
    for (int i = run.i0 + 1; i <= run.i1; i++)
        if (r.samples[i].pos.y > r.samples[i - 1].pos.y + 1e-3f) {
            fail(rep, run, r, "height rises inside drop");
            break;
        }
}

} // namespace

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

    for (const ElemRun& run : elementRuns(r)) {
        switch (run.tag) {
            case Tag::TopHat:    checkTopHat(r, run, rep); break;
            case Tag::Camelback: checkCamelback(r, run, rep); break;
            case Tag::Drop:      checkDrop(r, run, rep); break;
            case Tag::CliffDive: checkCliffDive(r, run, rep); break;
            default: break;
        }
    }
    return rep;
}

} // namespace v2
