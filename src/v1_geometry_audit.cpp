// Finalized V1 geometry audit.
//
// This is intentionally smaller and more geometric than audit_diagnostics.cpp.  It samples only
// Track::maxFinalU(), after the adaptive tail has settled, and looks for the macro-shape failures
// visible in the V1 issue photographs.  Tags are used only to exclude operational alignments,
// identify scheduler stubs and measure launched top hats as complete profiles.

#include <cstring>

namespace v1_geometry_audit {

namespace {

// Twelve samples per control span expose short shelves, roll discontinuities, and macro seams.
// Pitch and curvature retain overlapping ~14 m chords, deliberately ignoring mesh-scale noise.
constexpr float SAMPLE_DU       = 1.0f / 12.0f;
constexpr int   DERIV_HALF      = 6;
constexpr float EXTREMUM_DEG    = 1.25f;

// A shelf is not merely level: it is a near-extremum interval whose vertical radius exceeds
// about 700 m.  The inclined-trough variant permits a 20 degree grade but still requires that
// the straight interval touch the valley transition.  The 22/28 m lengths are shorter than the
// photographed 30-60 m defects, while remaining longer than an ordinary spline apex.
constexpr float SHELF_K_MAX     = 0.00145f;
constexpr float SHELF_PITCH_DEG = 7.0f;
constexpr float INCLINE_DEG     = 20.0f;
// A two-control-point near-level easing is a normal real transition, not a slab. Keep the
// photographed multi-block defects hard while the separate elevated-flat gate catches >220 m runs.
constexpr float SHELF_MIN_M     = 45.0f;
constexpr float INCLINE_MIN_M   = 55.0f;
constexpr float EXT_NEAR_M      = 18.0f;

// Three meaningful curvature sign changes inside 100 m is an alternating four-lobe bump, not
// one coherent crest/valley or turn transition.  The 1/450 m threshold rejects spline chatter.
constexpr float REV_K_MIN       = 0.00220f;
constexpr float REV_WINDOW_M    = 100.0f;
constexpr int   REV_LIMIT       = 4;
constexpr float SHAPE_EDGE_M    = 14.0f;

constexpr float STUB_MAX_M      = 46.0f;  // catches <=3 nominal V1 cps, not MIN_CONN's 4 cps
constexpr float BANK_FLAT_DEG   = 3.0f;
constexpr float BANKED_DEG      = 20.0f;
constexpr float BANK_GAP_MIN_M  = 10.0f;
constexpr float BANK_GAP_MAX_M  = 72.0f;
constexpr float BANK_SEARCH_M   = 58.0f;

// Continuity is measured independently from the broad macro-shape stencil above.  At the
// nominal V1 spacing these short stencils cover roughly 2-5 m, so a one-frame stitch cannot be
// averaged into an apparently smooth 14 m pitch/heading chord.  The vector-jerk threshold grows
// with k^2: a tight but coherent curve naturally rotates its curvature vector at that rate.
constexpr int   JOINT_DERIV_HALF       = 1;
constexpr int   CURVATURE_DERIV_HALF   = 1;
constexpr float TANGENT_STEP_HARD_DEG  = 9.0f;
// Calibrated against the new single-owner C3 interpolation. Smooth high-g
// hills legitimately reach about 0.11 1/m^2 while the former stitched
// dive-loop/teleport defects measured 0.9-2.8 1/m^2. Keep ample separation:
// this is a hard seam detector, not a ban on intentional force onset.
constexpr float CURVATURE_MAG_JERK_HARD = 0.1500f; // 1/m^2
constexpr float CURVATURE_VEC_JERK_BASE = 0.1500f; // 1/m^2
constexpr float CURVATURE_VEC_K2_SCALE  = 1.8f;
constexpr float CURVATURE_ONE_SIDED_JERK_HARD = 0.1800f; // 1/m^2
constexpr float ROLL_STEP_HARD_DEG      = 24.0f;
constexpr float ROLL_RATE_HARD          = 24.0f;   // degrees/m
constexpr float ROLL_ACCEL_HARD         = 5.5f;    // degrees/m^2
constexpr float ROLL_JERK_HARD          = 5.0f;    // degrees/m^3
constexpr float JOINT_EVENT_MERGE_M     = 8.0f;
constexpr float TERRAIN_PENETRATION_M   = 18.0f;

// Named elements hand a neutral frame to the next owner.  Measure the actual
// production frame evaluator inside the first/last half metre: a sampled bank
// curve followed by linear angle interpolation retains a finite terminal rate,
// even when its control-point values came from a nominally eased formula.
constexpr float ENDPOINT_ROLL_SAMPLE_M   = 0.50f;
constexpr float ENDPOINT_ROLL_RATE_MAX   = 0.12f;  // degrees/m
constexpr float ENDPOINT_ROLL_ACCEL_MAX  = 0.03f;  // degrees/m^2

// A vertical loop is planar.  These reference dimensions are the record-height
// instance of V1's intended planar curvature law (before the removed lateral
// offset patch); every larger instance must use one common 1.0..1.5 scale.
constexpr float LOOP_PLANAR_TOLERANCE_M  = 0.75f;
constexpr float LOOP_REFERENCE_PLAN_M    = 124.02636f;
constexpr float LOOP_REFERENCE_RAIL_M    = 185.38566f;
constexpr float LOOP_SCALE_MATCH_MAX     = 0.03f;

// drawVBent's first helix outrigger reaches 6 m radially and protects a 1.85 m
// swept train envelope.  Keeping the next coil outside that complete corridor
// makes at least one support path geometrically possible before terrain tests.
constexpr float HELIX_SUPPORT_REACH_M    = 6.0f;
constexpr float HELIX_TRAIN_CLEARANCE_M  = 1.85f;
constexpr float HELIX_SUPPORT_ENVELOPE_M =
    HELIX_SUPPORT_REACH_M + HELIX_TRAIN_CLEARANCE_M;

// A powered launch is a physical block, not a percentage of an arbitrarily expanded
// "flat section".  These limits describe the block directly: its rail is level and
// straight, its full kinematic length is driven, and at most one 14 m publication
// quantum of unpowered FLAT may touch either end.
constexpr float POWER_LEVEL_PITCH_DEG   = 0.50f;
constexpr float POWER_HEADING_CHANGE_DEG = 0.50f;
constexpr float POWER_CURVATURE_MAX     = 0.00050f; // radius >= 2 km: effectively straight
constexpr float POWER_LENGTH_TOLERANCE_M = 2.0f;   // 12 Hz sampling boundary tolerance
constexpr float POWER_FLAT_TOLERANCE_M  = 1.5f;
const float CADENCE_EARLY_TOLERANCE_M = SEG_LEN;
constexpr float CADENCE_LATE_TOLERANCE_M  = 500.0f; // one large element may finish after 2 km
constexpr float BACKSTOP_SPEED_TOLERANCE  = 1.0f;   // m/s around the 42 m/s reserve trigger

struct Sample {
    Vector3 p{};
    Vector3 up{};
    float u = 0.0f;
    float s = 0.0f;
    float pitch = 0.0f;       // radians
    float heading = 0.0f;     // radians
    float kVert = 0.0f;       // signed 1/m
    float kPlan = 0.0f;       // signed 1/m
    float bank = 0.0f;        // degrees
    float materialRoll = 0.0f; // continuous twist, parallel-transported through vertical track
    Vector3 tangent{};         // short-window unit tangent
    Vector3 curvature{};       // full xyz dT/ds, 1/m
    float curvatureMag = 0.0f;
    float rollRate = 0.0f;     // degrees/m
    float rollAccel = 0.0f;    // degrees/m^2
    float rollJerk = 0.0f;     // degrees/m^3
    unsigned char tag = M_FLAT;
    unsigned char drive = 0;
    unsigned char declaredDrive = 0;
    float plannedSpeed = 0.0f;
    uint32_t runId = 0;
    unsigned char macroKind = Track::MACRO_NONE;
    bool alignment = false;
    bool planValid = false;
    bool rollValid = false;
};

struct Extremum { int i = 0; bool crest = false; };

struct HatMetric {
    float apex = 0.0f, rise = 0.0f, drop = 0.0f;
    float planLength = 0.0f, railLength = 0.0f, crownRadius = 0.0f;
    float maxTerrainClearance = 0.0f;
    float climbFace = 0.0f, dropFace = 0.0f;
    float wrongWay = 0.0f;
    float straightFace = 0.0f;
    int reversals = 0;
};

enum DimensionMetric {
    LOOP_PLAN, LOOP_RAIL, LOOP_CROWN_RADIUS,
    HILL_RISE, HILL_PLAN, HILL_RAIL, HILL_CROWN_RADIUS,
    HELIX_DROP, HELIX_REVS, HELIX_RADIUS, HELIX_PLAN, HELIX_RAIL, HELIX_COIL,
    WAVE_RISE, WAVE_RADIUS, WAVE_PLAN, WAVE_RAIL,
    BANKAIR_RISE, BANKAIR_RADIUS, BANKAIR_PLAN, BANKAIR_RAIL,
    DIMENSION_METRIC_COUNT
};

struct MetricRange {
    float minimum = 0.0f, maximum = 0.0f;

    void include(float value, int previousCount) {
        if (!previousCount) minimum = maximum = value;
        else {
            minimum = fminf(minimum, value);
            maximum = fmaxf(maximum, value);
        }
    }
    void include(float low, float high, int previousCount) {
        if (!previousCount) { minimum = low; maximum = high; }
        else { minimum = fminf(minimum, low); maximum = fmaxf(maximum, high); }
    }
};

struct SeedMetric {
    int finalPoints = 0;
    unsigned generationExhaustions = 0;
    float length = 0.0f;
    bool immutable = true;
    int crestShelves = 0, valleyShelves = 0, inclinedTroughs = 0;
    int verticalBursts = 0, planBursts = 0, maxVerticalFlips = 0, maxPlanFlips = 0;
    int shortFlats = 0, shortDrops = 0, bankGaps = 0;
    int subterranean = 0;
    float maxPenetration = 0.0f;
    int directionSnaps = 0, elevatedFlats = 0, gaps = 0;
    int continuityBreaks = 0;
    int continuityByTag[M_COUNT]{};
    int tangentBreakSamples = 0, curvatureBreakSamples = 0, rollBreakSamples = 0;
    float maxTangentStep = 0.0f, maxCurvatureJump = 0.0f;
    float maxCurvatureVecJerk = 0.0f, maxCurvatureMagJerk = 0.0f;
    float maxCurvatureOneSidedJerk = 0.0f;
    float maxRollStep = 0.0f, maxRollRate = 0.0f;
    float maxRollAccel = 0.0f, maxRollJerk = 0.0f;
    float maxMacroStraight = 0.0f;
    int poweredBlocks = 0, boostBlocks = 0, launchBlocks = 0;
    int badPoweredBlocks = 0, orphanPoweredTags = 0;
    float minPoweredLength = 0.0f, maxPoweredLength = 0.0f;
    float maxPoweredLengthError = 0.0f;
    float maxPoweredPitch = 0.0f, maxPoweredCurvature = 0.0f;
    float maxPoweredHeadingChange = 0.0f;
    float maxUnpoweredLead = 0.0f, maxUnpoweredTail = 0.0f;
    int cadenceScheduled = 0, cadenceBackstop = 0;
    int cadenceEarly = 0, cadenceLate = 0, cadenceIntervals = 0;
    float minPowerSpacing = 0.0f, maxPowerSpacing = 0.0f;
    float finalPowerAge = 0.0f;
    int loopRuns = 0, badLoops = 0;
    int immelRuns = 0, badImmels = 0;
    int rollRuns = 0, badRolls = 0;
    int hillRuns = 0, badHills = 0, hillLobes = 0, badHillLobes = 0;
    int helixRuns = 0, badHelixes = 0;
    int waveRuns = 0, badWaves = 0;
    int bankAirRuns = 0, badBankAirs = 0;
    float minLoopClearance = 0.0f, maxLoopAspect = 0.0f, minLoopCrown = 0.0f;
    float minLoopCurvatureRamp = 0.0f;
    float maxLoopCrownRadiusRatio = 0.0f;
    float maxLoopLateral = 0.0f, maxLoopScaleError = 0.0f;
    float maxLoopApexTangentError = 0.0f;
    float maxImmelSeam = 0.0f, minImmelOverlap = 0.0f;
    float minImmelRise = 0.0f, minImmelTurn = 0.0f, minImmelTwist = 0.0f;
    float maxImmelEndpointRate = 0.0f, maxImmelEndpointAccel = 0.0f;
    float minRollExcursion = 0.0f, minRollTwist = 0.0f;
    float minRollInwardAlignment = 0.0f;
    unsigned rollHandMask = 0;
    MetricRange dimension[DIMENSION_METRIC_COUNT]{};
    float maxHelixEndpointRate = 0.0f, maxHelixEndpointAccel = 0.0f;
    float minBankAirOverlap = 0.0f;
    float minBankAirHeading = 0.0f, minBankAirBank = 0.0f;
    float maxBankAirDead = 0.0f, maxBankAirSeam = 0.0f;
    float maxBankAirEndpointRate = 0.0f, maxBankAirEndpointAccel = 0.0f;
    float firstNamedDefect = -1.0f;
    unsigned char firstNamedTag = M_FLAT;
    int hats = 0, badHats = 0;
    HatMetric primaryHat{};
    float firstCrest = -1.0f, firstValley = -1.0f, firstIncline = -1.0f;
    float firstCrestU = -1.0f, firstValleyU = -1.0f, firstInclineU = -1.0f;
    float firstVRev = -1.0f, firstPRev = -1.0f, firstStub = -1.0f, firstBankGap = -1.0f;
    float firstUnder = -1.0f;
    float firstUnderU = -1.0f;
    float firstSnap = -1.0f;
    float firstSnapU = -1.0f;
    float firstContinuity = -1.0f;
    float firstContinuityU = -1.0f;
    unsigned char firstContinuityBefore = M_FLAT, firstContinuityAfter = M_FLAT;
    unsigned char firstCrestTag = M_FLAT, firstValleyTag = M_FLAT;
    unsigned char firstVRevTag = M_FLAT, firstUnderTag = M_FLAT;
    int hard = 0;
};

struct ElementRange { int a = 0, b = 0; unsigned char tag = M_FLAT; };

static bool operational(unsigned char tag) {
    return tag == M_LAUNCH || tag == M_STATION || tag == M_BOOST;
}

static bool authoredInversion(unsigned char tag) {
    return tag == M_LOOP || tag == M_ROLL || tag == M_IMMEL || tag == M_STALL ||
           tag == M_DIVELOOP;
}

static bool shapeExcluded(unsigned char tag) {
    // The photographed macro defects are upright route-shape failures. Closed
    // inversions deliberately reverse vertical/plan curvature as part of their
    // topology and have their own force/continuity gates in --audit.
    return operational(tag) || authoredInversion(tag);
}

static bool shapeExcluded(const Sample &sample) {
    bool splashAlignment = sample.tag == M_DIP &&
        sample.p.y - WATER_Y < 3.0f &&
        submergedGround(groundTopAt(sample.p.x, sample.p.z));
    return shapeExcluded(sample.tag) || sample.alignment || splashAlignment ||
           sample.macroKind == Track::MACRO_DROP ||
           sample.macroKind == Track::MACRO_TOP_HAT;
}

static float wrapPi(float a) {
    while (a > PI) a -= 2.0f * PI;
    while (a < -PI) a += 2.0f * PI;
    return a;
}

static float vectorAngleDegrees(Vector3 a, Vector3 b) {
    float la = Vector3Length(a), lb = Vector3Length(b);
    if (la < 1e-6f || lb < 1e-6f) return 0.0f;
    float cosine = Clamp(Vector3DotProduct(a, b) / (la * lb), -1.0f, 1.0f);
    return acosf(cosine) * 180.0f / PI;
}

static float intervalDistance(float x, float a, float b) {
    return x < a ? a - x : (x > b ? x - b : 0.0f);
}

static void hashBytes(uint64_t &h, const void *data, size_t n) {
    const unsigned char *p = static_cast<const unsigned char *>(data);
    for (size_t i = 0; i < n; ++i) { h ^= p[i]; h *= UINT64_C(1099511628211); }
}

// Hash every field a finalized consumer can observe.  Exact float bits are intentional: once a
// prefix is published, even a tiny later adaptive write is a streaming/render race regression.
static uint64_t prefixHash(const Track &t, int count) {
    uint64_t h = UINT64_C(1469598103934665603);
    for (int i = 0; i < count; ++i) {
        hashBytes(h, &t.cp[i], sizeof(t.cp[i]));
        hashBytes(h, &t.up[i], sizeof(t.up[i]));
        hashBytes(h, &t.kind[i], sizeof(t.kind[i]));
        hashBytes(h, &t.chainf[i], sizeof(t.chainf[i]));
        hashBytes(h, &t.alignmentf[i], sizeof(t.alignmentf[i]));
        hashBytes(h, &t.spanRun[i], sizeof(t.spanRun[i]));
        hashBytes(h, &t.spanStart[i], sizeof(t.spanStart[i]));
        hashBytes(h, &t.spanEnd[i], sizeof(t.spanEnd[i]));
        hashBytes(h, &t.arc[i], sizeof(t.arc[i]));
        if (i < (int)t.gvlog.size()) hashBytes(h, &t.gvlog[i], sizeof(t.gvlog[i]));
    }
    return h;
}

static float bankDegrees(Vector3 tangent, Vector3 upHint) {
    Vector3 level = Vector3Subtract(WUP, Vector3Scale(tangent, tangent.y));
    float levelLen = Vector3Length(level);
    if (levelLen < 1e-4f) return 0.0f;
    level = Vector3Scale(level, 1.0f / levelLen);
    Vector3 up = orthoUp(tangent, upHint);
    Vector3 side = Vector3CrossProduct(tangent, level);
    float sideLen = Vector3Length(side);
    if (sideLen < 1e-4f) return 0.0f;
    side = Vector3Scale(side, 1.0f / sideLen);
    return atan2f(Vector3DotProduct(up, side), Vector3DotProduct(up, level)) * 180.0f / PI;
}

static Vector3 transportFrame(Vector3 up, Vector3 fromTangent, Vector3 toTangent) {
    Vector3 axis = Vector3CrossProduct(fromTangent, toTangent);
    float sine = Vector3Length(axis);
    float cosine = Clamp(Vector3DotProduct(fromTangent, toTangent), -1.0f, 1.0f);
    Vector3 transported = up;
    if (sine > 1e-6f) {
        axis = Vector3Scale(axis, 1.0f / sine);
        transported = Vector3Add(
            Vector3Add(Vector3Scale(up, cosine),
                       Vector3Scale(Vector3CrossProduct(axis, up), sine)),
            Vector3Scale(axis, Vector3DotProduct(axis, up) * (1.0f - cosine)));
    }
    return orthoUp(toTangent, transported);
}

static std::vector<Sample> sampleFinal(const Track &t) {
    std::vector<Sample> out;
    const float maxU = t.maxFinalU();
    if (maxU <= 0.0f) return out;
    out.reserve((size_t)(maxU / SAMPLE_DU) + 2);
    for (float u = Track::rideStartU; u <= maxU; u += SAMPLE_DU) {
        Sample q;
        q.u = u; q.p = t.pos(u); q.up = t.upAt(u);
        q.tag = t.tagAt(u); q.drive = t.driveAt(u);
        q.plannedSpeed = t.plannedSpeedAt(u);
        int k = (int)t.clampFinalU(u), incoming = k + 2;
        if (incoming >= 0 && incoming < (int)t.spanRun.size()) {
            q.declaredDrive = t.chainf[incoming];
            q.runId = t.spanRun[incoming];
            q.alignment = t.alignmentf[incoming] != 0;
            if (const Track::AnalyticRun *run = t.analyticRun(q.runId))
                q.macroKind = (unsigned char)run->kind;
        }
        if (!out.empty()) q.s = out.back().s + Vector3Distance(q.p, out.back().p);
        out.push_back(q);
    }
    // A deliberate level alignment includes its entry taper. levelHold is
    // armed only after a connective FLAT may already have begun, so propagate
    // the alignment marker across that one contiguous flat run instead of
    // diagnosing its first few metres as a valley shelf.
    for (int a = 0; a < (int)out.size();) {
        int b = a + 1;
        while (b < (int)out.size() && out[b].tag == out[a].tag) ++b;
        if (out[a].tag == M_FLAT) {
            bool alignment = false;
            for (int i = a; i < b; ++i) alignment = alignment || out[i].alignment;
            if (alignment) for (int i = a; i < b; ++i) out[i].alignment = true;
        }
        a = b;
    }
    const int n = (int)out.size();
    // Use a local xyz chord for continuity and roll.  The broader pitch/heading chord below is
    // intentionally retained for macro-shape classification, but is too wide to expose a seam.
    for (int i = 0; i < n; ++i) {
        int a = std::max(0, i - JOINT_DERIV_HALF);
        int b = std::min(n - 1, i + JOINT_DERIV_HALF);
        Vector3 d = Vector3Subtract(out[b].p, out[a].p);
        float length = Vector3Length(d);
        out[i].tangent = length > 1e-5f ? Vector3Scale(d, 1.0f / length)
                                        : Vector3{0.0f, 0.0f, 1.0f};
        // World-referenced bank remains useful for detecting a level gap between
        // ordinary turns, but it is intentionally not used for roll continuity
        // near vertical track.
        out[i].rollValid = length > 1e-5f && fabsf(out[i].tangent.y) < 0.965f;
        out[i].bank = bankDegrees(out[i].tangent, out[i].up);
    }
    bool havePriorRoll = false;
    float priorRoll = 0.0f;
    for (int i = 0; i < n; ++i) {
        if (!out[i].rollValid) { havePriorRoll = false; continue; }
        if (havePriorRoll) {
            float delta = out[i].bank - priorRoll;
            while (delta > 180.0f) delta -= 360.0f;
            while (delta < -180.0f) delta += 360.0f;
            out[i].bank = priorRoll + delta;
        }
        priorRoll = out[i].bank;
        havePriorRoll = true;
    }
    // Material roll is the signed twist of the actual rider frame relative to
    // the preceding frame after parallel transport onto the new tangent. It is
    // defined through vertical loop/Immelmann sides, where world-up bank is
    // singular, and therefore exposes an orientation teleport hidden by the
    // old rollValid reset.
    if (n > 0) {
        Vector3 previousUp = orthoUp(out[0].tangent, out[0].up);
        out[0].materialRoll = out[0].rollValid ? out[0].bank : 0.0f;
        for (int i = 1; i < n; ++i) {
            Vector3 transported = transportFrame(previousUp, out[i - 1].tangent,
                                                  out[i].tangent);
            Vector3 actual = orthoUp(out[i].tangent, out[i].up);
            float sine = Vector3DotProduct(Vector3CrossProduct(transported, actual),
                                           out[i].tangent);
            float cosine = Clamp(Vector3DotProduct(transported, actual), -1.0f, 1.0f);
            out[i].materialRoll = out[i - 1].materialRoll +
                                  atan2f(sine, cosine) * 180.0f / PI;
            previousUp = actual;
        }
    }
    for (int i = CURVATURE_DERIV_HALF; i + CURVATURE_DERIV_HALF < n; ++i) {
        int a = i - CURVATURE_DERIV_HALF, b = i + CURVATURE_DERIV_HALF;
        float ds = fmaxf(out[b].s - out[a].s, 1e-4f);
        out[i].curvature = Vector3Scale(Vector3Subtract(out[b].tangent, out[a].tangent),
                                        1.0f / ds);
        out[i].curvatureMag = Vector3Length(out[i].curvature);
    }
    constexpr int ROLL_HALF = 2;
    for (int i = ROLL_HALF; i + ROLL_HALF < n; ++i) {
        int a = i - ROLL_HALF, b = i + ROLL_HALF;
        float ds = fmaxf(out[b].s - out[a].s, 1e-4f);
        out[i].rollRate = (out[b].materialRoll - out[a].materialRoll) / ds;
    }
    for (int i = ROLL_HALF * 2; i + ROLL_HALF * 2 < n; ++i) {
        int a = i - ROLL_HALF, b = i + ROLL_HALF;
        float ds = fmaxf(out[b].s - out[a].s, 1e-4f);
        out[i].rollAccel = (out[b].rollRate - out[a].rollRate) / ds;
    }
    for (int i = ROLL_HALF * 3; i + ROLL_HALF * 3 < n; ++i) {
        int a = i - ROLL_HALF, b = i + ROLL_HALF;
        float ds = fmaxf(out[b].s - out[a].s, 1e-4f);
        out[i].rollJerk = (out[b].rollAccel - out[a].rollAccel) / ds;
    }
    for (int i = 0; i < n; ++i) {
        int a = std::max(0, i - DERIV_HALF), b = std::min(n - 1, i + DERIV_HALF);
        Vector3 d = Vector3Subtract(out[b].p, out[a].p);
        float horizontal = sqrtf(d.x*d.x + d.z*d.z), chord = Vector3Length(d);
        out[i].pitch = atan2f(d.y, fmaxf(horizontal, 1e-5f));
        out[i].heading = atan2f(d.x, d.z);
        out[i].planValid = chord > 1e-4f && horizontal / chord > 0.34f;
    }
    for (int i = DERIV_HALF; i + DERIV_HALF < n; ++i) {
        int a = i - DERIV_HALF, b = i + DERIV_HALF;
        float ds = fmaxf(out[b].s - out[a].s, 1e-4f);
        out[i].kVert = (out[b].pitch - out[a].pitch) / ds;
        if (out[a].planValid && out[b].planValid)
            out[i].kPlan = wrapPi(out[b].heading - out[a].heading) / ds;
    }
    return out;
}

static std::vector<Extremum> findExtrema(const std::vector<Sample> &v) {
    std::vector<Extremum> out;
    const float threshold = EXTREMUM_DEG * PI / 180.0f;
    int priorSign = 0, priorStrong = -1;
    for (int i = DERIV_HALF; i + DERIV_HALF < (int)v.size(); ++i) {
        int sign = v[i].pitch > threshold ? 1 : (v[i].pitch < -threshold ? -1 : 0);
        if (!sign) continue;
        if (priorSign && sign != priorSign) {
            int e = priorStrong;
            for (int q = priorStrong; q <= i; ++q) {
                if ((priorSign > 0 && v[q].p.y > v[e].p.y) ||
                    (priorSign < 0 && v[q].p.y < v[e].p.y)) e = q;
            }
            out.push_back({e, priorSign > 0});
        }
        priorSign = sign; priorStrong = i;
    }
    return out;
}

struct StraightRun { float length = 0.0f, meanAbsPitch = 0.0f; int a = -1, b = -1; };

static StraightRun lowCurvatureNear(const std::vector<Sample> &v, int e, float pitchLimit) {
    StraightRun best;
    // Helixes and dive turns are lateral elements with an intentionally
    // sustained vertical grade. Their exits can be vertical extrema without
    // being the shelf-like valley defect this gate is designed to catch.
    auto excluded = [](const Sample &sample) {
        return shapeExcluded(sample) || sample.tag == M_HELIX || sample.tag == M_DIVE;
    };
    int lo = e, hi = e;
    while (lo > 0 && v[e].s - v[lo-1].s <= 62.0f) --lo;
    while (hi + 1 < (int)v.size() && v[hi+1].s - v[e].s <= 62.0f) ++hi;
    int i = lo;
    while (i <= hi) {
        bool ok = !excluded(v[i]) && fabsf(v[i].kVert) <= SHELF_K_MAX &&
                  fabsf(v[i].pitch) <= pitchLimit;
        if (!ok) { ++i; continue; }
        int a = i; float pitchSum = 0.0f; int count = 0;
        while (i <= hi && !excluded(v[i]) && fabsf(v[i].kVert) <= SHELF_K_MAX &&
               fabsf(v[i].pitch) <= pitchLimit) {
            pitchSum += fabsf(v[i].pitch); ++count; ++i;
        }
        int b = i - 1;
        float length = v[b].s - v[a].s;
        if (intervalDistance(v[e].s, v[a].s, v[b].s) <= EXT_NEAR_M && length > best.length) {
            best = {length, count ? pitchSum / count : 0.0f, a, b};
        }
    }
    return best;
}

struct BurstMetric {
    int count = 0, maxFlips = 0;
    float first = -1.0f;
    unsigned char firstTag = M_FLAT;
};

static BurstMetric reversalBursts(const std::vector<Sample> &v, bool plan) {
    struct Reversal { float s; int run; unsigned char tag; };
    std::vector<Reversal> reversals;
    std::vector<float> interior(v.size(), 0.0f);
    // Derivative stencils necessarily straddle an element boundary. Keep one
    // nominal control-point spacing at each edge for the seam gates, and use
    // this gate for unintended reversals in the authored element body.
    for (int a = 0; a < (int)v.size();) {
        bool valid = !shapeExcluded(v[a]) && v[a].tag != M_HILLS &&
                     (!plan || v[a].planValid);
        int b = a + 1;
        while (b < (int)v.size()) {
            bool nextValid = !shapeExcluded(v[b]) && v[b].tag != M_HILLS &&
                             (!plan || v[b].planValid);
            if (!valid || !nextValid || v[b].tag != v[a].tag) break;
            ++b;
        }
        if (valid) {
            const float first = v[a].s, last = v[b - 1].s;
            for (int i = a; i < b; ++i)
                interior[i] = fminf(v[i].s - first, last - v[i].s);
        }
        a = valid ? b : a + 1;
    }
    int previous = 0, run = 0;
    unsigned char previousTag = M_COUNT;
    for (int i = DERIV_HALF*2; i + DERIV_HALF*2 < (int)v.size(); ++i) {
        bool valid = !shapeExcluded(v[i]) && v[i].tag != M_HILLS &&
                     (!plan || v[i].planValid) && interior[i] >= SHAPE_EDGE_M;
        float k = plan ? v[i].kPlan : v[i].kVert;
        if (!valid || v[i].tag != previousTag) {
            previous = 0; ++run; previousTag = valid ? v[i].tag : M_COUNT;
        }
        if (!valid) continue;
        int sign = k > REV_K_MIN ? 1 : (k < -REV_K_MIN ? -1 : 0);
        if (!sign) continue;
        if (previous && sign != previous) reversals.push_back({v[i].s, run, v[i].tag});
        previous = sign;
    }
    BurstMetric result;
    size_t i = 0;
    while (i < reversals.size()) {
        size_t j = i;
        while (j + 1 < reversals.size() && reversals[j+1].run == reversals[i].run &&
               reversals[j+1].s - reversals[i].s <= REV_WINDOW_M) ++j;
        int flips = (int)(j - i + 1);
        result.maxFlips = std::max(result.maxFlips, flips);
        if (flips >= REV_LIMIT) {
            if (result.first < 0.0f) {
                result.first = reversals[i].s;
                result.firstTag = reversals[i].tag;
            }
            ++result.count;
            while (i + 1 < reversals.size() && reversals[i+1].run == reversals[j].run &&
                   reversals[i+1].s <= reversals[j].s) ++i;
        }
        ++i;
    }
    return result;
}

static int reversalCount(const std::vector<Sample> &v, int a, int b) {
    int previous = 0, count = 0;
    for (int i = a; i <= b; ++i) {
        int sign = v[i].kVert > REV_K_MIN ? 1 : (v[i].kVert < -REV_K_MIN ? -1 : 0);
        if (!sign) continue;
        if (previous && sign != previous) ++count;
        previous = sign;
    }
    return count;
}

static float strongFace(const std::vector<Sample> &v, int a, int b, int sign) {
    std::vector<float> values;
    for (int i = a; i <= b; ++i) {
        float degrees = v[i].pitch * 180.0f / PI * sign;
        if (degrees > 5.0f) values.push_back(degrees);
    }
    if (values.empty()) return 0.0f;
    std::sort(values.begin(), values.end(), std::greater<float>());
    int take = std::max(1, (int)values.size() / 5); // strongest sustained 20%, not one spike
    float sum = 0.0f;
    for (int i = 0; i < take; ++i) sum += values[i];
    return sum / take;
}

static bool strictRecordBand(double value, double reference) {
    return std::isfinite(value) && value >= reference &&
           value <= reference * (double)Track::RECORD_SCALE_CAP;
}

static void inspectTopHats(const Track &t, const std::vector<Sample> &v,
                           SeedMetric &m) {
    for (int left = 0; left < (int)v.size();) {
        if (v[left].macroKind != Track::MACRO_TOP_HAT || v[left].runId == 0) {
            ++left;
            continue;
        }
        const uint32_t runId = v[left].runId;
        int right = left;
        while (right + 1 < (int)v.size() && v[right + 1].runId == runId) ++right;
        const int landing = right + 1;
        // The fixed audit window may end inside a hat.  Validate only complete
        // finalized runs, but never hide a complete undersized macro profile.
        if (landing >= (int)v.size()) {
            left = landing;
            continue;
        }
        const Track::AnalyticRun *run = t.analyticRun(runId);
        if (!run || run->kind != Track::MACRO_TOP_HAT || run->profile.empty()) {
            ++m.hats;
            ++m.badHats;
            left = landing;
            continue;
        }
        const double planLength = run->profile.length();
        const v1profile::Sample begin = run->profile.sampleDistance(0.0);
        const v1profile::Sample apex = run->profile.sampleDistance(0.5 * planLength);
        const v1profile::Sample end = run->profile.sampleDistance(planLength);
        // 128 Simpson intervals keeps the quadrature error below a micrometre
        // at 1.5x, so the hard cap needs no outward comparison epsilon.
        const double railLength = v1profile::railArcLength(run->profile, 128);
        const double crownRadius = fabs(apex.curvature) > 1.0e-12
            ? 1.0 / fabs(apex.curvature) : INFINITY;
        int e = left;
        for (int i = left + 1; i <= right; ++i)
            if (v[i].p.y > v[e].p.y) e = i;
        bool poweredHat = false;
        for (int i = left; i <= e; ++i)
            if (v[i].tag == M_CLIMB) { poweredHat = true; break; }

        HatMetric h;
        h.apex = (float)apex.height;
        h.rise = (float)(apex.height - begin.height);
        h.drop = (float)(apex.height - end.height);
        h.planLength = (float)planLength;
        h.railLength = (float)railLength;
        h.crownRadius = (float)crownRadius;
        for (int i = left; i <= landing; ++i)
            h.maxTerrainClearance = fmaxf(h.maxTerrainClearance,
                v[i].p.y - groundTopAt(v[i].p.x, v[i].p.z));
        h.climbFace = strongFace(v, left, e, 1);
        h.dropFace = -strongFace(v, e, landing, -1);
        h.reversals = reversalCount(v, left, landing);
        float straight = 0.0f;
        for (int i = left + 1; i <= landing; ++i) {
            bool tiltedLine = fabsf(v[i].pitch) > 10.0f * PI / 180.0f &&
                               fabsf(v[i].kVert) < 0.00005f;
            straight = tiltedLine ? straight + (v[i].s - v[i - 1].s) : 0.0f;
            h.straightFace = fmaxf(h.straightFace, straight);
        }
        for (int i = left + 1; i <= e; ++i) if (v[i].pitch < -2.0f*PI/180.0f)
            h.wrongWay += v[i].s - v[i-1].s;
        for (int i = e + 1; i <= landing; ++i) if (v[i].pitch > 2.0f*PI/180.0f)
            h.wrongWay += v[i].s - v[i-1].s;

        ++m.hats;
        if (m.primaryHat.drop < h.drop) m.primaryHat = h;
        // These are V1's explicit top-hat invariants: every hat, not merely
        // the largest one in a seed, stays inside the 1.0-1.5x record
        // envelope.  It must also have real steep faces, one monotone
        // rise/drop, and the expected pull-up/crown/pull-out sign sequence.
        const double hatFloor = Track::TOP_HAT_RECORD_RISE;
        const double hatCap = hatFloor * Track::RECORD_SCALE_CAP;
        // Terrain-relative clearance has its separate 250 m safety ceiling;
        // it includes the entry track's existing ground clearance and is not
        // itself the element's record-scaled rise.
        if (!poweredHat || h.maxTerrainClearance > 250.01f ||
            h.rise < hatFloor || h.rise > hatCap ||
            h.drop < hatFloor || h.drop > hatCap ||
            !strictRecordBand(planLength, v1profile::kTopHatReferencePlanLength) ||
            !strictRecordBand(railLength, v1profile::kTopHatReferenceRailLength) ||
            !strictRecordBand(crownRadius, v1profile::kTopHatReferenceCrownRadius) ||
            h.climbFace < 50.0f || h.dropFace > -50.0f ||
            h.wrongWay > 12.0f || h.reversals > 4 || h.straightFace > 32.0f)
            ++m.badHats;
        left = landing;
    }
}

static void inspectStubs(const Track &t, SeedMetric &m) {
    int n = t.finalizedPointCount(), i = 0;
    while (i < n) {
        int a = i; unsigned char tag = t.kind[i];
        while (i < n && t.kind[i] == tag) ++i;
        int b = i - 1;
        if (a == 0 || b == n - 1 || (tag != M_FLAT && tag != M_DROP)) continue;
        float length = 0.0f;
        for (int q = a; q <= b; ++q) length += Vector3Distance(t.cp[q], t.cp[q-1]);
        if (length < STUB_MAX_M) {
            if (tag == M_FLAT) ++m.shortFlats; else ++m.shortDrops;
            if (m.firstStub < 0.0f) m.firstStub = t.arc[a];
        }
    }
}

static void inspectBankGaps(const std::vector<Sample> &v, SeedMetric &m) {
    int i = 0, n = (int)v.size();
    while (i < n) {
        if (shapeExcluded(v[i]) || v[i].tag == M_DIP || fabsf(v[i].bank) >= BANK_FLAT_DEG) { ++i; continue; }
        int a = i;
        while (i < n && !shapeExcluded(v[i]) && v[i].tag != M_DIP && fabsf(v[i].bank) < BANK_FLAT_DEG) ++i;
        int b = i - 1;
        float gap = v[b].s - v[a].s;
        if (gap < BANK_GAP_MIN_M || gap > BANK_GAP_MAX_M) continue;
        int before = -1, after = -1;
        for (int q = a - 1; q >= 0 && v[a].s - v[q].s <= BANK_SEARCH_M; --q)
            if (!shapeExcluded(v[q]) && v[q].tag != M_DIP && v[q].planValid &&
                fabsf(v[q].bank) >= BANKED_DEG) { before = q; break; }
        for (int q = b + 1; q < n && v[q].s - v[b].s <= BANK_SEARCH_M; ++q)
            if (!shapeExcluded(v[q]) && v[q].tag != M_DIP && v[q].planValid &&
                fabsf(v[q].bank) >= BANKED_DEG) { after = q; break; }
        // Opposite signs are a deliberate S-curve transfer through level; same-sign banks with a
        // held zero interval are the photographed/ride-felt dead-gap family.
        if (before >= 0 && after >= 0 && v[before].bank * v[after].bank > 0.0f) {
            ++m.bankGaps;
            if (m.firstBankGap < 0.0f) m.firstBankGap = v[a].s;
        }
    }
}

static void inspectContinuity3D(const std::vector<Sample> &v, SeedMetric &m) {
    float lastSevere = -1.0e9f;
    bool eventOpen = false;
    // Curvature itself uses a short central stencil. Comparing the two neighboring curvature
    // vectors captures magnitude and direction changes in xyz, including horizontal/vertical
    // compound seams that separate pitch and heading tests can miss.
    for (int i = 3; i + 3 < (int)v.size(); ++i) {
        float tangentStep = vectorAngleDegrees(v[i - 1].tangent, v[i].tangent);
        float curvatureJump = Vector3Length(Vector3Subtract(v[i].curvature,
                                                            v[i - 1].curvature));
        float oneSidedDs = fmaxf(v[i].s - v[i - 1].s, 1e-4f);
        float oneSidedCurvatureJerk = curvatureJump / oneSidedDs;
        float ds = fmaxf(v[i + 1].s - v[i - 1].s, 1e-4f);
        float vectorJerk = Vector3Length(Vector3Subtract(v[i + 1].curvature,
                                                         v[i - 1].curvature)) / ds;
        float magnitudeJerk = fabsf(v[i + 1].curvatureMag - v[i - 1].curvatureMag) / ds;
        float referenceK = fmaxf(v[i - 1].curvatureMag, v[i + 1].curvatureMag);
        float vectorJerkLimit = CURVATURE_VEC_JERK_BASE +
                                CURVATURE_VEC_K2_SCALE * referenceK * referenceK;

        float rollStep = fabsf(v[i].materialRoll - v[i - 1].materialRoll);
        float rollRate = fabsf(v[i].rollRate);
        float rollAccel = fabsf(v[i].rollAccel);
        float rollJerk = fabsf(v[i].rollJerk);

        m.maxTangentStep = fmaxf(m.maxTangentStep, tangentStep);
        m.maxCurvatureJump = fmaxf(m.maxCurvatureJump, curvatureJump);
        m.maxCurvatureOneSidedJerk = fmaxf(m.maxCurvatureOneSidedJerk,
                                           oneSidedCurvatureJerk);
        m.maxCurvatureVecJerk = fmaxf(m.maxCurvatureVecJerk, vectorJerk);
        m.maxCurvatureMagJerk = fmaxf(m.maxCurvatureMagJerk, magnitudeJerk);
        m.maxRollStep = fmaxf(m.maxRollStep, rollStep);
        m.maxRollRate = fmaxf(m.maxRollRate, rollRate);
        m.maxRollAccel = fmaxf(m.maxRollAccel, rollAccel);
        m.maxRollJerk = fmaxf(m.maxRollJerk, rollJerk);

        bool tangentBreak = tangentStep > TANGENT_STEP_HARD_DEG;
        bool curvatureBreak = oneSidedCurvatureJerk > CURVATURE_ONE_SIDED_JERK_HARD ||
                              magnitudeJerk > CURVATURE_MAG_JERK_HARD ||
                              vectorJerk > vectorJerkLimit;
        bool rollBreak = rollStep > ROLL_STEP_HARD_DEG || rollRate > ROLL_RATE_HARD ||
                         rollAccel > ROLL_ACCEL_HARD || rollJerk > ROLL_JERK_HARD;
        if (tangentBreak) ++m.tangentBreakSamples;
        if (curvatureBreak) ++m.curvatureBreakSamples;
        if (rollBreak) ++m.rollBreakSamples;
        if (!(tangentBreak || curvatureBreak || rollBreak)) {
            if (eventOpen && v[i].s - lastSevere > JOINT_EVENT_MERGE_M) eventOpen = false;
            continue;
        }

        // One physical stitch often lights several overlapping derivative samples. It is one
        // hard defect, not four. A continuously bad short region remains one event; only a clean
        // interval of JOINT_EVENT_MERGE_M arms the detector for another seam.
        if (!eventOpen) {
            ++m.continuityBreaks;
            if (v[i].tag < M_COUNT) ++m.continuityByTag[v[i].tag];
            eventOpen = true;
            if (m.firstContinuity < 0.0f) {
                m.firstContinuity = v[i].s;
                m.firstContinuityU = v[i].u;
                m.firstContinuityBefore = v[i - 1].tag;
                m.firstContinuityAfter = v[i].tag;
            }
        }
        lastSevere = v[i].s;
    }
}

// Distance between two finite centreline chords.  The finalized spline is sampled at roughly
// one metre here, so segment distance (rather than point distance) makes the overlap gate
// independent of where a control-span sample happens to land.
static float segmentDistance(Vector3 p1, Vector3 q1, Vector3 p2, Vector3 q2) {
    constexpr float EPS = 1.0e-7f;
    Vector3 d1 = Vector3Subtract(q1, p1), d2 = Vector3Subtract(q2, p2);
    Vector3 r = Vector3Subtract(p1, p2);
    float a = Vector3DotProduct(d1, d1), e = Vector3DotProduct(d2, d2);
    float f = Vector3DotProduct(d2, r), s = 0.0f, t = 0.0f;
    if (a <= EPS && e <= EPS) return Vector3Distance(p1, p2);
    if (a <= EPS) t = Clamp(f / e, 0.0f, 1.0f);
    else {
        float c = Vector3DotProduct(d1, r);
        if (e <= EPS) s = Clamp(-c / a, 0.0f, 1.0f);
        else {
            float b = Vector3DotProduct(d1, d2);
            float denom = a * e - b * b;
            if (fabsf(denom) > EPS) s = Clamp((b * f - c * e) / denom, 0.0f, 1.0f);
            t = (b * s + f) / e;
            if (t < 0.0f) { t = 0.0f; s = Clamp(-c / a, 0.0f, 1.0f); }
            else if (t > 1.0f) { t = 1.0f; s = Clamp((b - c) / a, 0.0f, 1.0f); }
        }
    }
    Vector3 c1 = Vector3Add(p1, Vector3Scale(d1, s));
    Vector3 c2 = Vector3Add(p2, Vector3Scale(d2, t));
    return Vector3Distance(c1, c2);
}

static std::vector<ElementRange> namedRanges(const std::vector<Sample> &v) {
    std::vector<ElementRange> out;
    for (int a = 0; a < (int)v.size();) {
        unsigned char tag = v[a].tag;
        int b = a + 1;
        while (b < (int)v.size() && v[b].tag == tag) ++b;
        // The fixed audit window can finish inside the next element.  A partial tail is neither
        // absent nor defective, so only complete interior instances are eligible.
        if (a > 0 && b < (int)v.size() &&
            (tag == M_LOOP || tag == M_IMMEL || tag == M_ROLL ||
             tag == M_HILLS || tag == M_HELIX || tag == M_BANKAIR ||
             tag == M_WAVE) && b - a >= 8)
            out.push_back({a, b - 1, tag});
        a = b;
    }
    return out;
}

struct CurveDimensions {
    bool valid = false;
    float planLength = 0.0f, railLength = 0.0f;
    float headingSweep = 0.0f;
    float meanRadius = 0.0f;
    float minimumRadius = 0.0f, maximumRadius = 0.0f;
    float minimumY = 0.0f, maximumY = 0.0f;
    float coilSeparation = 0.0f;
};

static const Track::SpatialRun *elementSpatialRun(const Track &t,
                                                   const std::vector<Sample> &v,
                                                   int a, int b) {
    const Track::SpatialRun *result = nullptr;
    for (int i = a; i <= b; ++i) if (const Track::SpatialRun *run = t.spatialRun(v[i].runId)) {
        if (result && result != run) return nullptr;
        result = run;
    }
    return result;
}

// Integrate the complete immutable SpatialRun, not its tag-trimmed sample
// window. Plan and rail arc are separate, while local plan curvature exposes
// both radii of a spiral helix. Equal-tangent points one turn apart provide a
// direct XZ coil-clearance measurement: a vertically separated but perfectly
// overlapping helix therefore still fails.
static CurveDimensions spatialDimensions(const Track &t,
                                          const Track::SpatialRun *run) {
    CurveDimensions result;
    if (!run || run->points.size() < 3) return result;
    constexpr int SUBDIVISIONS = 16;
    const int spans = (int)run->points.size() - 1;
    const int count = spans * SUBDIVISIONS;
    std::vector<Vector3> point((size_t)count + 1);
    std::vector<float> heading((size_t)count), planStep((size_t)count);
    std::vector<float> sweep((size_t)count + 1, 0.0f);
    result.minimumY = result.maximumY = run->points.front().y;
    for (int i = 0; i <= count; ++i) {
        point[i] = t.spatialRunPos(*run, (float)spans * i / count);
        result.minimumY = fminf(result.minimumY, point[i].y);
        result.maximumY = fmaxf(result.maximumY, point[i].y);
        if (!i) continue;
        Vector3 d = Vector3Subtract(point[i], point[i - 1]);
        planStep[i - 1] = sqrtf(d.x*d.x + d.z*d.z);
        heading[i - 1] = atan2f(d.x, d.z);
        result.planLength += planStep[i - 1];
        result.railLength += Vector3Length(d);
    }
    float minimumRadius = INFINITY, maximumRadius = 0.0f;
    for (int i = 1; i < count; ++i) {
        float turn = fabsf(wrapPi(heading[i] - heading[i - 1]));
        sweep[i] = sweep[i - 1] + turn;
        result.headingSweep += turn;
        float tRun = (float)i / count;
        float ds = 0.5f * (planStep[i - 1] + planStep[i]);
        // The helix shoulder is fully active through this interval. Radius
        // here is the physical coil radius, uncontaminated by entry/runout.
        if (tRun >= 0.105f && tRun <= 0.895f && turn > 1.0e-5f) {
            float radius = ds / turn;
            minimumRadius = fminf(minimumRadius, radius);
            maximumRadius = fmaxf(maximumRadius, radius);
        }
    }
    sweep[count] = sweep[count - 1];
    result.meanRadius = result.headingSweep > 1.0e-5f
        ? result.planLength / result.headingSweep : 0.0f;
    if (std::isfinite(minimumRadius)) {
        result.minimumRadius = minimumRadius;
        result.maximumRadius = maximumRadius;
    }
    float coil = INFINITY;
    for (int i = 1; i <= count; ++i) {
        float target = sweep[i] - 2.0f * PI;
        if (target < 0.0f) continue;
        auto end = sweep.begin() + i;
        auto upper = std::lower_bound(sweep.begin(), end, target);
        int hi = (int)(upper - sweep.begin()), lo = std::max(0, hi - 1);
        float f = hi == lo ? 0.0f :
            (target - sweep[lo]) / fmaxf(sweep[hi] - sweep[lo], 1.0e-6f);
        Vector3 prior = Vector3Lerp(point[lo], point[hi], Clamp(f, 0.0f, 1.0f));
        float dx = point[i].x - prior.x, dz = point[i].z - prior.z;
        coil = fminf(coil, sqrtf(dx*dx + dz*dz));
    }
    result.coilSeparation = std::isfinite(coil) ? coil : 0.0f;
    result.valid = true;
    return result;
}

struct EndpointFrameMetric {
    bool valid = false;
    float maximumRate = 0.0f;
    float maximumAcceleration = 0.0f;
};

static Vector3 spatialTangent(const Track &t, const Track::SpatialRun &run,
                              float d) {
    const float end = (float)run.points.size() - 1.0f;
    constexpr float PARAMETER_EPSILON = 0.0025f;
    const float a = fmaxf(0.0f, d - PARAMETER_EPSILON);
    const float b = fminf(end, d + PARAMETER_EPSILON);
    Vector3 tangent = Vector3Subtract(t.spatialRunPos(run, b),
                                      t.spatialRunPos(run, a));
    if (Vector3Length(tangent) < 1.0e-6f) return {};
    return Vector3Normalize(tangent);
}

static float transportedFrameChange(const Track &t,
                                    const Track::SpatialRun &run,
                                    float a, float b) {
    const Vector3 tangentA = spatialTangent(t, run, a);
    const Vector3 tangentB = spatialTangent(t, run, b);
    if (Vector3Length(tangentA) < 0.5f || Vector3Length(tangentB) < 0.5f)
        return NAN;
    const Vector3 upA = orthoUp(tangentA, t.spatialRunUp(run, a));
    const Vector3 upB = orthoUp(tangentB, t.spatialRunUp(run, b));
    const Vector3 transported = transportFrame(upA, tangentA, tangentB);
    return atan2f(Vector3DotProduct(Vector3CrossProduct(transported, upB),
                                    tangentB),
                  Clamp(Vector3DotProduct(transported, upB), -1.0f, 1.0f)) /
           DEG2RAD;
}

// Evaluate the actual final frame law, rather than differentiating its authored
// control values.  Four samples remain inside one endpoint span; this exposes a
// finite linear-interpolation rate at the publication boundary while giving a
// true C2/C3 bank law room to approach zero naturally.
static EndpointFrameMetric endpointFrameMetric(const Track &t,
                                                const Track::SpatialRun *run) {
    EndpointFrameMetric result;
    if (!run || run->points.size() < 3) return result;
    const float end = (float)run->points.size() - 1.0f;
    auto inspect = [&](bool start) {
        const float edgeA = start ? 0.0f : end - 1.0f;
        const float edgeB = start ? 1.0f : end;
        const float spanLength = Vector3Distance(t.spatialRunPos(*run, edgeA),
                                                 t.spatialRunPos(*run, edgeB));
        if (spanLength < 1.0e-4f) return false;
        const float step = Clamp(ENDPOINT_ROLL_SAMPLE_M / spanLength,
                                 0.001f, 0.20f);
        float d[4];
        for (int i = 0; i < 4; ++i)
            d[i] = start ? step * i : end - step * (3 - i);
        float length[3], rate[3];
        for (int i = 0; i < 3; ++i) {
            length[i] = Vector3Distance(t.spatialRunPos(*run, d[i]),
                                        t.spatialRunPos(*run, d[i + 1]));
            const float change = transportedFrameChange(t, *run, d[i], d[i + 1]);
            if (length[i] < 1.0e-4f || !std::isfinite(change)) return false;
            rate[i] = change / length[i];
        }
        const int endpointInterval = start ? 0 : 2;
        const int endpointAcceleration = start ? 0 : 1;
        const float acceleration =
            (rate[endpointAcceleration + 1] - rate[endpointAcceleration]) /
            fmaxf(0.5f * (length[endpointAcceleration] +
                          length[endpointAcceleration + 1]), 1.0e-4f);
        result.maximumRate = fmaxf(result.maximumRate,
                                   fabsf(rate[endpointInterval]));
        result.maximumAcceleration = fmaxf(result.maximumAcceleration,
                                           fabsf(acceleration));
        return true;
    };
    result.valid = inspect(true) && inspect(false);
    return result;
}

static float spatialCurvatureRadius(const Track &t,
                                    const Track::SpatialRun &run, float d) {
    constexpr float PARAMETER_STEP = 0.02f;
    const float end = (float)run.points.size() - 1.0f;
    const float a = fmaxf(0.0f, d - PARAMETER_STEP);
    const float b = Clamp(d, 0.0f, end);
    const float c = fminf(end, d + PARAMETER_STEP);
    const Vector3 pa = t.spatialRunPos(run, a);
    const Vector3 pb = t.spatialRunPos(run, b);
    const Vector3 pc = t.spatialRunPos(run, c);
    const float leftLength = Vector3Distance(pa, pb);
    const float rightLength = Vector3Distance(pb, pc);
    if (leftLength < 1.0e-5f || rightLength < 1.0e-5f) return INFINITY;
    const Vector3 left = Vector3Scale(Vector3Subtract(pb, pa), 1.0f / leftLength);
    const Vector3 right = Vector3Scale(Vector3Subtract(pc, pb), 1.0f / rightLength);
    const float curvature = Vector3Length(Vector3Subtract(right, left)) /
        fmaxf(0.5f * (leftLength + rightLength), 1.0e-5f);
    return curvature > 1.0e-7f ? 1.0f / curvature : INFINITY;
}

static float loopLateralExcursion(const Track &t,
                                  const Track::SpatialRun *run) {
    if (!run || run->points.size() < 3) return INFINITY;
    Vector3 forward = spatialTangent(t, *run, 0.0f);
    forward.y = 0.0f;
    if (Vector3Length(forward) < 1.0e-5f) return INFINITY;
    forward = Vector3Normalize(forward);
    const Vector3 side = Vector3Normalize(Vector3CrossProduct(WUP, forward));
    const Vector3 origin = t.spatialRunPos(*run, 0.0f);
    constexpr int SUBDIVISIONS = 16;
    const int samples = ((int)run->points.size() - 1) * SUBDIVISIONS;
    float result = 0.0f;
    for (int i = 0; i <= samples; ++i) {
        const float d = ((float)run->points.size() - 1.0f) * i / samples;
        result = fmaxf(result, fabsf(Vector3DotProduct(
            Vector3Subtract(t.spatialRunPos(*run, d), origin), side)));
    }
    return result;
}

static float bankedCamelbackRailLength(float height, float planLength) {
    constexpr int INTERVALS = 512;
    double sum = 0.0;
    for (int i = 0; i <= INTERVALS; ++i) {
        double t = (double)i / INTERVALS, a = t*(1.0 - t), q = t - 0.5;
        double derivative = 256.0 * (4.0*a*a*a*(1.0 - 2.0*t)*(1.0 + 8.0*q*q) +
                                     16.0*a*a*a*a*q);
        double speed = sqrt((double)planLength*planLength +
                            (double)height*height*derivative*derivative);
        sum += (i == 0 || i == INTERVALS) ? speed : (i & 1 ? 4.0 : 2.0)*speed;
    }
    return (float)(sum / (3.0 * INTERVALS));
}

static bool dimensionBand(float value, float reference, float tolerance,
                          float upperAllowance = 1.0f) {
    return value >= reference - tolerance &&
           value <= reference * Track::RECORD_SCALE_CAP * upperAllowance + tolerance;
}

static bool badDimension(MetricRange &range, int previousCount, float value,
                         float reference, float tolerance,
                         float upperAllowance = 1.0f) {
    range.include(value, previousCount);
    return !dimensionBand(value, reference, tolerance, upperAllowance);
}

static float rangeMinClearance(const std::vector<Sample> &v, int a, int b,
                               float separatedFraction) {
    float runLength = v[b].s - v[a].s;
    float separation = separatedFraction * runLength;
    float result = 1.0e9f;
    for (int i = a; i < b; ++i) {
        float si = 0.5f * (v[i].s + v[i + 1].s);
        for (int j = i + 2; j < b; ++j) {
            float sj = 0.5f * (v[j].s + v[j + 1].s);
            if (sj - si < separation) continue;
            result = fminf(result, segmentDistance(v[i].p, v[i + 1].p,
                                                   v[j].p, v[j + 1].p));
        }
    }
    return result == 1.0e9f ? 0.0f : result;
}

static float lineExcursion(Vector3 p, Vector3 origin, Vector3 axis) {
    Vector3 d = Vector3Subtract(p, origin);
    return Vector3Length(Vector3Subtract(d, Vector3Scale(axis, Vector3DotProduct(d, axis))));
}

static int internalSeamEvents(const std::vector<Sample> &v, int a, int b,
                              float &worstNormalized) {
    int margin = std::max(3, (b - a) / 20);
    int events = 0;
    bool open = false;
    worstNormalized = 0.0f;
    for (int i = a + margin; i <= b - margin; ++i) {
        float ds = fmaxf(v[i].s - v[i - 1].s, 1.0e-4f);
        float tangent = vectorAngleDegrees(v[i - 1].tangent, v[i].tangent) /
                        TANGENT_STEP_HARD_DEG;
        float oneSided = Vector3Length(Vector3Subtract(v[i].curvature,
                                                       v[i - 1].curvature)) /
                         ds / CURVATURE_ONE_SIDED_JERK_HARD;
        float roll = fmaxf(fabsf(v[i].materialRoll - v[i - 1].materialRoll) /
                           ROLL_STEP_HARD_DEG,
                           fmaxf(fabsf(v[i].rollAccel) / ROLL_ACCEL_HARD,
                                 fabsf(v[i].rollJerk) / ROLL_JERK_HARD));
        float severity = fmaxf(tangent, fmaxf(oneSided, roll));
        worstNormalized = fmaxf(worstNormalized, severity);
        if (severity > 1.0f) {
            if (!open) ++events;
            open = true;
        } else if (severity < 0.65f) open = false;
    }
    return events;
}

// Contiguous finalized named elements must pass both topology and generic C3 gates.
static void inspectNamedElements(const Track &t, const std::vector<Sample> &v,
                                 SeedMetric &m) {
    for (const ElementRange &r : namedRanges(v)) {
        const int a = r.a, b = r.b;
        const float length = fmaxf(v[b].s - v[a].s, 1.0f);
        float minY = v[a].p.y, maxY = v[a].p.y;
        for (int i = a + 1; i <= b; ++i) {
            minY = fminf(minY, v[i].p.y);
            maxY = fmaxf(maxY, v[i].p.y);
        }
        const float rise = maxY - minY;
        bool bad = false;

        if (r.tag == M_LOOP) {
            const int previousRuns = m.loopRuns++;
            const Track::SpatialRun *spatial = elementSpatialRun(t, v, a, b);
            const CurveDimensions dimensions = spatialDimensions(t, spatial);
            const float runRise = dimensions.maximumY - dimensions.minimumY;
            const float crownRadius = spatial
                ? spatialCurvatureRadius(t, *spatial,
                    0.5f * ((float)spatial->points.size() - 1.0f))
                : INFINITY;
            const float lateralExcursion = loopLateralExcursion(t, spatial);
            const float riseScale = runRise / Track::LOOP_RECORD_HEIGHT;
            const float planScale = dimensions.planLength / LOOP_REFERENCE_PLAN_M;
            const float railScale = dimensions.railLength / LOOP_REFERENCE_RAIL_M;
            const float crownScale = crownRadius / Track::LOOP_REFERENCE_CROWN_RADIUS;
            const float scaleError = fmaxf(fabsf(planScale - riseScale),
                fmaxf(fabsf(railScale - riseScale),
                      fabsf(crownScale - riseScale)));
            float apexTangentError = INFINITY;
            if (spatial) {
                Vector3 entry = spatialTangent(t, *spatial, 0.0f);
                const Vector3 apex = spatialTangent(t, *spatial,
                    0.5f * ((float)spatial->points.size() - 1.0f));
                apexTangentError = vectorAngleDegrees(Vector3Scale(entry, -1.0f), apex);
            }
            m.dimension[LOOP_PLAN].include(dimensions.planLength, previousRuns);
            m.dimension[LOOP_RAIL].include(dimensions.railLength, previousRuns);
            m.dimension[LOOP_CROWN_RADIUS].include(crownRadius, previousRuns);
            m.maxLoopLateral = fmaxf(m.maxLoopLateral, lateralExcursion);
            m.maxLoopScaleError = fmaxf(m.maxLoopScaleError, scaleError);
            m.maxLoopApexTangentError = fmaxf(m.maxLoopApexTangentError,
                                               apexTangentError);
            Vector3 forward = v[a].tangent;
            forward.y = 0.0f;
            forward = Vector3Length(forward) > 1.0e-4f ? Vector3Normalize(forward)
                                                       : Vector3{0.0f, 0.0f, 1.0f};
            float minAlong = 0.0f, maxAlong = 0.0f;
            for (int i = a; i <= b; ++i) {
                float along = Vector3DotProduct(Vector3Subtract(v[i].p, v[a].p), forward);
                minAlong = fminf(minAlong, along); maxAlong = fmaxf(maxAlong, along);
            }
            float horizontalSpan = maxAlong - minAlong;
            float aspect = rise / fmaxf(horizontalSpan, 1.0f);
            float clearance = rangeMinClearance(v, a, b, 0.15f);
            float crownLength = 0.0f, baseFlat = 0.0f, baseFlatMax = 0.0f;
            for (int i = a + 1; i <= b; ++i) {
                float ds = v[i].s - v[i - 1].s;
                if (v[i].p.y >= minY + 0.90f * rise) crownLength += ds;
                bool flatBottom = v[i].p.y <= minY + 0.12f * rise &&
                                  fabsf(v[i].pitch) < 4.0f * DEG2RAD;
                baseFlat = flatBottom ? baseFlat + ds : 0.0f;
                baseFlatMax = fmaxf(baseFlatMax, baseFlat);
            }
            float endTangent = vectorAngleDegrees(v[a].tangent, v[b].tangent);
            float seamSeverity = 0.0f;
            int seams = internalSeamEvents(v, a, b, seamSeverity);
            float edgeK = 0.0f, crownK = 0.0f, leftK = 0.0f, rightK = 0.0f;
            int edgeN = 0, crownN = 0, leftN = 0, rightN = 0;
            for (int i = a; i <= b; ++i) {
                float f = (v[i].s - v[a].s) / length;
                if (f <= 0.10f || f >= 0.90f) { edgeK += v[i].curvatureMag; ++edgeN; }
                if (f >= 0.44f && f <= 0.56f) { crownK += v[i].curvatureMag; ++crownN; }
                if (f >= 0.20f && f <= 0.35f) { leftK += v[i].curvatureMag; ++leftN; }
                if (f >= 0.65f && f <= 0.80f) { rightK += v[i].curvatureMag; ++rightN; }
            }
            edgeK /= fmaxf((float)edgeN, 1.0f); crownK /= fmaxf((float)crownN, 1.0f);
            leftK /= fmaxf((float)leftN, 1.0f); rightK /= fmaxf((float)rightN, 1.0f);
            float curvatureRamp = crownK / fmaxf(edgeK, 1.0e-5f);
            float crownSpike = crownK / fmaxf(0.5f * (leftK + rightK), 1.0e-5f);
            float curvatureAsymmetry = fabsf(leftK - rightK) /
                                       fmaxf(0.5f * (leftK + rightK), 1.0e-5f);
            float crownRadiusRatio = 1.0f / fmaxf(crownK * rise, 1.0e-5f);
            if (!previousRuns) {
                m.minLoopClearance = clearance; m.maxLoopAspect = aspect;
                m.minLoopCrown = crownLength;
                m.minLoopCurvatureRamp = curvatureRamp;
                m.maxLoopCrownRadiusRatio = crownRadiusRatio;
            } else {
                m.minLoopClearance = fminf(m.minLoopClearance, clearance);
                m.maxLoopAspect = fmaxf(m.maxLoopAspect, aspect);
                m.minLoopCrown = fminf(m.minLoopCrown, crownLength);
                m.minLoopCurvatureRamp = fminf(m.minLoopCurvatureRamp, curvatureRamp);
                m.maxLoopCrownRadiusRatio = fmaxf(m.maxLoopCrownRadiusRatio,
                                                  crownRadiusRatio);
            }
            // Enforce one planar, uniformly record-scaled loop. A fixed lateral
            // displacement can otherwise satisfy the vertical silhouette while
            // silently changing plan length, apex heading and rider-frame normal.
            bad = !dimensions.valid || clearance < 10.0f ||
                  !dimensionBand(runRise, Track::LOOP_RECORD_HEIGHT, 0.20f) ||
                  !dimensionBand(dimensions.planLength, LOOP_REFERENCE_PLAN_M, 0.30f) ||
                  !dimensionBand(dimensions.railLength, LOOP_REFERENCE_RAIL_M, 0.30f) ||
                  !dimensionBand(crownRadius, Track::LOOP_REFERENCE_CROWN_RADIUS, 0.20f) ||
                  lateralExcursion > LOOP_PLANAR_TOLERANCE_M ||
                  scaleError > LOOP_SCALE_MATCH_MAX || apexTangentError > 2.0f ||
                  aspect < 1.10f || aspect > 3.20f || crownLength < 7.0f ||
                  crownLength > 45.0f || baseFlatMax > 22.0f ||
                  endTangent > 24.0f || curvatureRamp < 1.25f ||
                  crownSpike > 2.20f || crownRadiusRatio < 0.35f ||
                  crownRadiusRatio > 0.46f || curvatureAsymmetry > 0.35f || seams > 0;
            if (bad) ++m.badLoops;
        } else if (r.tag == M_IMMEL) {
            const int previousRuns = m.immelRuns++;
            const Track::SpatialRun *spatial = elementSpatialRun(t, v, a, b);
            const EndpointFrameMetric endpoint = endpointFrameMetric(t, spatial);
            m.maxImmelEndpointRate = fmaxf(m.maxImmelEndpointRate,
                                            endpoint.maximumRate);
            m.maxImmelEndpointAccel = fmaxf(m.maxImmelEndpointAccel,
                                             endpoint.maximumAcceleration);
            float tangentTurn = vectorAngleDegrees(v[a].tangent, v[b].tangent);
            // Twist travel is invariant to the half-loop's equivalent exit frame.
            float totalRoll = 0.0f;
            for (int i = a + 1; i <= b; ++i)
                totalRoll += fabsf(v[i].materialRoll - v[i - 1].materialRoll);
            float overlap = 0.0f, seamSeverity = 0.0f;
            for (int i = a + 1; i <= b; ++i) {
                bool curvedAndRolling = v[i].curvatureMag > 0.0025f &&
                                        fabsf(v[i].rollRate) > 0.45f;
                if (curvedAndRolling) overlap += v[i].s - v[i - 1].s;
            }
            int seams = internalSeamEvents(v, a, b, seamSeverity);
            m.maxImmelSeam = fmaxf(m.maxImmelSeam, seamSeverity);
            if (!previousRuns) {
                m.minImmelOverlap = overlap; m.minImmelRise = rise;
                m.minImmelTurn = tangentTurn; m.minImmelTwist = totalRoll;
            } else {
                m.minImmelOverlap = fminf(m.minImmelOverlap, overlap);
                m.minImmelRise = fminf(m.minImmelRise, rise);
                m.minImmelTurn = fminf(m.minImmelTurn, tangentTurn);
                m.minImmelTwist = fminf(m.minImmelTwist, totalRoll);
            }
            // Curvature and twist must overlap, excluding half-loop + straight-roll stitching.
            bad = !spatial || !endpoint.valid ||
                  endpoint.maximumRate > ENDPOINT_ROLL_RATE_MAX ||
                  endpoint.maximumAcceleration > ENDPOINT_ROLL_ACCEL_MAX ||
                  rise < 65.5f || rise > 100.5f ||
                  tangentTurn < 135.0f || totalRoll < 125.0f ||
                  overlap < 10.0f || seams > 0;
            if (bad) ++m.badImmels;
        } else if (r.tag == M_ROLL) {
            const int previousRuns = m.rollRuns++;
            const Track::SpatialRun *spatial = elementSpatialRun(t, v, a, b);
            const CurveDimensions dimensions = spatialDimensions(t, spatial);
            Vector3 axis = spatial
                ? Vector3Subtract(spatial->points.back(), spatial->points.front())
                : Vector3Subtract(v[b].p, v[a].p);
            axis = Vector3Length(axis) > 1.0e-4f
                ? Vector3Normalize(axis) : v[a].tangent;
            const Vector3 axisOrigin = spatial ? spatial->points.front() : v[a].p;
            float excursion = 0.0f, seamSeverity = 0.0f;
            if (spatial) {
                constexpr int SUBDIVISIONS = 16;
                const int samples = ((int)spatial->points.size() - 1) * SUBDIVISIONS;
                for (int i = 0; i <= samples; ++i)
                    excursion = fmaxf(excursion, lineExcursion(
                        t.spatialRunPos(*spatial,
                            (float)(spatial->points.size() - 1) * i / samples),
                        axisOrigin, axis));
            } else {
                for (int i = a; i <= b; ++i)
                    excursion = fmaxf(excursion,
                        lineExcursion(v[i].p, axisOrigin, axis));
            }
            float twist = 0.0f;
            for (int i = a + 1; i <= b; ++i)
                twist += fabsf(v[i].materialRoll - v[i - 1].materialRoll);
            float inwardAlignment = -1.0f;
            bool sawPositiveRadialSide = false, sawNegativeRadialSide = false;
            unsigned handMask = 0;
            if (spatial && spatial->radialFrame.valid) {
                inwardAlignment = 1.0f;
                constexpr int SUBDIVISIONS = 16;
                const int spans = (int)spatial->points.size() - 1;
                const int samples = spans * SUBDIVISIONS;
                const Track::RadialFrameSpec &frame = spatial->radialFrame;
                const Vector3 radialSide = Vector3Normalize(
                    Vector3CrossProduct(frame.up, frame.forward));
                for (int i = 0; i <= samples; ++i) {
                    const float d = (float)spans * i / samples;
                    const Vector3 p = t.spatialRunPos(*spatial, d);
                    const Vector3 tangent = spatialTangent(t, *spatial, d);
                    const float along = Vector3DotProduct(
                        Vector3Subtract(p, frame.origin), frame.forward);
                    const Vector3 axisPoint = Vector3Add(
                        Vector3Add(frame.origin, Vector3Scale(frame.forward, along)),
                        Vector3Scale(frame.up, frame.radius));
                    const Vector3 outward = Vector3Subtract(p, axisPoint);
                    const float signedSide = Vector3DotProduct(outward, radialSide);
                    sawPositiveRadialSide = sawPositiveRadialSide ||
                        signedSide > 0.20f * frame.radius;
                    sawNegativeRadialSide = sawNegativeRadialSide ||
                        signedSide < -0.20f * frame.radius;
                    Vector3 radialTangent = Vector3Subtract(tangent,
                        Vector3Scale(frame.forward,
                                     Vector3DotProduct(tangent, frame.forward)));
                    const float orientation = Vector3DotProduct(frame.forward,
                        Vector3CrossProduct(outward, radialTangent));
                    if (fabsf(orientation) > 1.0e-4f)
                        handMask |= orientation > 0.0f ? 1u : 2u;
                    const Vector3 inward = orthoUp(
                        tangent, Vector3Subtract(axisPoint, p));
                    const Vector3 actual = t.spatialRunUp(*spatial, d);
                    inwardAlignment = fminf(inwardAlignment,
                        Vector3DotProduct(inward, actual));
                }
            }
            m.rollHandMask |= handMask;
            int seams = internalSeamEvents(v, a, b, seamSeverity);
            if (!previousRuns) {
                m.minRollExcursion = excursion;
                m.minRollTwist = twist;
                m.minRollInwardAlignment = inwardAlignment;
            }
            else {
                m.minRollExcursion = fminf(m.minRollExcursion, excursion);
                m.minRollTwist = fminf(m.minRollTwist, twist);
                m.minRollInwardAlignment = fminf(m.minRollInwardAlignment,
                                                 inwardAlignment);
            }
            // The complete cylindrical corkscrew scales every physical axis
            // uniformly: 94.30664 m rail and 13.2 m axis-line excursion at
            // 1.0x, with the shared 1.5x cap.
            const float radius = spatial && spatial->radialFrame.valid
                ? spatial->radialFrame.radius : 0.0f;
            const float radiusScale = radius / Track::CORKSCREW_REFERENCE_RADIUS;
            const float excursionScale = excursion /
                                         Track::CORKSCREW_REFERENCE_EXCURSION;
            const float railScale = dimensions.railLength /
                                    Track::CORKSCREW_REFERENCE_RAIL;
            const float uniformError = fmaxf(fabsf(radiusScale - excursionScale),
                                              fabsf(radiusScale - railScale));
            bad = !dimensions.valid ||
                  !spatial || !spatial->radialFrame.valid ||
                  !dimensionBand(radius, Track::CORKSCREW_REFERENCE_RADIUS, 0.05f) ||
                  !dimensionBand(dimensions.railLength,
                                 Track::CORKSCREW_REFERENCE_RAIL, 0.20f) ||
                  !dimensionBand(excursion,
                                 Track::CORKSCREW_REFERENCE_EXCURSION, 0.10f) ||
                  uniformError > LOOP_SCALE_MATCH_MAX ||
                  !sawPositiveRadialSide || !sawNegativeRadialSide ||
                  (handMask != 1u && handMask != 2u) || twist < 260.0f ||
                  inwardAlignment < 0.995f || seams > 0;
            if (bad) ++m.badRolls;
        } else if (r.tag == M_HILLS) {
            ++m.hillRuns;
            uint32_t runId = 0;
            for (int i = a; i <= b && !runId; ++i)
                if (v[i].macroKind == Track::MACRO_HILLS) runId = v[i].runId;
            const Track::AnalyticRun *run = t.analyticRun(runId);
            const bool exactProfile = run && run->kind == Track::MACRO_HILLS &&
                                      run->profile.segmentCount() == 4;
            bool runBad = !exactProfile;
            double lobeStart = 0.0;
            for (size_t lobeIndex = 0; exactProfile && lobeIndex < 2; ++lobeIndex) {
                const v1profile::Segment &climb = run->profile.segment(2*lobeIndex);
                const v1profile::Segment &fall = run->profile.segment(2*lobeIndex + 1);
                const float lobeRise = (float)(climb.end().height - climb.begin().height);
                const float lobePlan = (float)(climb.length + fall.length);
                const float lobeRail = (float)v1profile::railArcLength(
                    run->profile, lobeStart, lobeStart + lobePlan);
                const double curvature = fabs(climb.end().curvature);
                const float crownRadius = curvature > 1.0e-12
                    ? (float)(1.0 / curvature) : INFINITY;
                int previousLobes = m.hillLobes++;
                bool lobeBad =
                    badDimension(m.dimension[HILL_RISE], previousLobes, lobeRise,
                                 Track::AIRTIME_RECORD_HEIGHT, 1.0f) |
                    badDimension(m.dimension[HILL_PLAN], previousLobes, lobePlan,
                                 Track::HILL_REFERENCE_LOBE_PLAN, 0.1f) |
                    badDimension(m.dimension[HILL_RAIL], previousLobes, lobeRail,
                                 Track::HILL_REFERENCE_LOBE_RAIL, 0.2f) |
                    badDimension(m.dimension[HILL_CROWN_RADIUS], previousLobes,
                                 crownRadius, Track::HILL_REFERENCE_CROWN_RADIUS, 0.05f);
                if (lobeBad) {
                    ++m.badHillLobes;
                    runBad = true;
                }
                lobeStart += lobePlan;
            }
            if (!exactProfile) m.badHillLobes += 2;
            bad = runBad;
            if (bad) ++m.badHills;
        } else if (r.tag == M_HELIX) {
            int previousRuns = m.helixRuns++;
            const Track::SpatialRun *spatial = elementSpatialRun(t, v, a, b);
            const CurveDimensions dimensions = spatialDimensions(t, spatial);
            const EndpointFrameMetric endpoint = endpointFrameMetric(t, spatial);
            m.maxHelixEndpointRate = fmaxf(m.maxHelixEndpointRate,
                                            endpoint.maximumRate);
            m.maxHelixEndpointAccel = fmaxf(m.maxHelixEndpointAccel,
                                             endpoint.maximumAcceleration);
            const float totalDrop = spatial
                ? spatial->points.front().y - spatial->points.back().y : 0.0f;
            const float revolutions = dimensions.headingSweep / (2.0f * PI);
            m.dimension[HELIX_RADIUS].include(dimensions.minimumRadius,
                                              dimensions.maximumRadius, previousRuns);
            m.dimension[HELIX_COIL].include(dimensions.coilSeparation, previousRuns);
            const bool radiusBad =
                !dimensionBand(dimensions.minimumRadius, Track::HELIX_REFERENCE_RADIUS, 1.0f) ||
                !dimensionBand(dimensions.maximumRadius, Track::HELIX_REFERENCE_RADIUS, 1.0f);
            bad = !dimensions.valid |
                  badDimension(m.dimension[HELIX_DROP], previousRuns, totalDrop,
                               Track::HELIX_REFERENCE_DROP, 1.0f) |
                  badDimension(m.dimension[HELIX_REVS], previousRuns, revolutions,
                               Track::HELIX_RECORD_REVS, 0.02f) |
                  radiusBad |
                  badDimension(m.dimension[HELIX_PLAN], previousRuns,
                               dimensions.planLength, Track::helixReferencePlanLength(), 1.0f) |
                  badDimension(m.dimension[HELIX_RAIL], previousRuns,
                               dimensions.railLength, Track::helixReferenceRailLength(), 1.0f) |
                  (dimensions.coilSeparation < HELIX_SUPPORT_ENVELOPE_M) |
                  (!endpoint.valid ||
                   endpoint.maximumRate > ENDPOINT_ROLL_RATE_MAX ||
                   endpoint.maximumAcceleration > ENDPOINT_ROLL_ACCEL_MAX);
            if (bad) ++m.badHelixes;
        } else if (r.tag == M_WAVE) {
            int previousRuns = m.waveRuns++;
            const CurveDimensions dimensions = spatialDimensions(
                t, elementSpatialRun(t, v, a, b));
            const float rise = dimensions.maximumY - dimensions.minimumY;
            const float referencePlan = Track::WAVE_REFERENCE_RADIUS *
                                        dimensions.headingSweep;
            const float referenceRail = bankedCamelbackRailLength(
                Track::BANKAIR_RECORD_HEIGHT, referencePlan);
            bool dimensionsBad =
                badDimension(m.dimension[WAVE_RISE], previousRuns, rise,
                             Track::BANKAIR_RECORD_HEIGHT, 1.0f) |
                badDimension(m.dimension[WAVE_RADIUS], previousRuns,
                             dimensions.meanRadius, Track::WAVE_REFERENCE_RADIUS, 2.0f) |
                badDimension(m.dimension[WAVE_PLAN], previousRuns,
                             dimensions.planLength, referencePlan, 1.0f) |
                badDimension(m.dimension[WAVE_RAIL], previousRuns,
                             dimensions.railLength, referenceRail, 1.0f);
            bad = !dimensions.valid || dimensionsBad ||
                  dimensions.headingSweep < 143.0f * DEG2RAD ||
                  dimensions.headingSweep > 167.0f * DEG2RAD;
            if (bad) ++m.badWaves;
        } else if (r.tag == M_BANKAIR) {
            int previousRuns = m.bankAirRuns++;
            const Track::SpatialRun *spatial = elementSpatialRun(t, v, a, b);
            const CurveDimensions dimensions = spatialDimensions(t, spatial);
            const EndpointFrameMetric endpoint = endpointFrameMetric(t, spatial);
            m.maxBankAirEndpointRate = fmaxf(m.maxBankAirEndpointRate,
                                              endpoint.maximumRate);
            m.maxBankAirEndpointAccel = fmaxf(m.maxBankAirEndpointAccel,
                                               endpoint.maximumAcceleration);
            const float rise = dimensions.maximumY - dimensions.minimumY;
            float maxBank = 0.0f, overlap = 0.0f, dead = 0.0f, maxDead = 0.0f;
            for (int i = a + 1; i <= b; ++i) {
                float ds = v[i].s - v[i - 1].s;
                // bank is unwrapped across the whole ride so a preceding roll
                // may leave an ordinary 55-degree hill reported as 415deg.
                // Element shape uses the equivalent world-frame angle.
                float bank = fabsf(remainderf(v[i].bank, 360.0f));
                maxBank = fmaxf(maxBank, bank);
                bool elevation = v[i].p.y > minY + 0.20f * rise ||
                                 fabsf(v[i].pitch) > 5.0f * DEG2RAD;
                bool yawing = fabsf(v[i].kPlan) > 0.0008f;
                bool banked = bank > 14.0f;
                if (elevation && yawing && banked) overlap += ds;
                bool deadPiece = fabsf(v[i].pitch) < 2.0f * DEG2RAD &&
                                 fabsf(v[i].kPlan) < 0.0005f &&
                                 bank < 5.0f;
                dead = deadPiece ? dead + ds : 0.0f;
                maxDead = fmaxf(maxDead, dead);
            }
            const float headingSweep = dimensions.headingSweep;
            float overlapFraction = overlap / length;
            float seamSeverity = 0.0f;
            int seams = internalSeamEvents(v, a, b, seamSeverity);
            constexpr float referencePlan = 196.0f;
            const float referenceRail = bankedCamelbackRailLength(
                Track::BANKAIR_RECORD_HEIGHT, referencePlan);
            bool dimensionsBad =
                badDimension(m.dimension[BANKAIR_RISE], previousRuns, rise,
                             Track::BANKAIR_RECORD_HEIGHT, 1.0f) |
                badDimension(m.dimension[BANKAIR_RADIUS], previousRuns,
                             dimensions.meanRadius, Track::BANKAIR_REFERENCE_RADIUS, 2.0f) |
                badDimension(m.dimension[BANKAIR_PLAN], previousRuns,
                             dimensions.planLength, referencePlan, 1.0f) |
                badDimension(m.dimension[BANKAIR_RAIL], previousRuns,
                             dimensions.railLength, referenceRail, 1.0f);
            if (m.bankAirRuns == 1) {
                m.minBankAirOverlap = overlapFraction;
                m.minBankAirHeading = headingSweep; m.minBankAirBank = maxBank;
            } else {
                m.minBankAirOverlap = fminf(m.minBankAirOverlap, overlapFraction);
                m.minBankAirHeading = fminf(m.minBankAirHeading, headingSweep);
                m.minBankAirBank = fminf(m.minBankAirBank, maxBank);
            }
            m.maxBankAirDead = fmaxf(m.maxBankAirDead, maxDead);
            m.maxBankAirSeam = fmaxf(m.maxBankAirSeam, seamSeverity);
            // Elevation, yaw and bank must overlap; a >28 m zero piece is a stitched flat.
            bad = !dimensions.valid || !endpoint.valid || dimensionsBad ||
                  endpoint.maximumRate > ENDPOINT_ROLL_RATE_MAX ||
                  endpoint.maximumAcceleration > ENDPOINT_ROLL_ACCEL_MAX ||
                  headingSweep < 35.0f * DEG2RAD || maxBank < 25.0f ||
                  overlapFraction < 0.22f || maxDead > 28.0f || seams > 0;
            if (bad) ++m.badBankAirs;
        }

        if (bad && m.firstNamedDefect < 0.0f) {
            m.firstNamedDefect = v[a].s;
            m.firstNamedTag = r.tag;
        }
    }
}

static bool poweredRole(unsigned char tag) {
    return tag == M_BOOST || tag == M_LAUNCH;
}

static float poweredBlockLength(float entrySpeed) {
    const float accelerationDistance = fmaxf(
        (V1_PROPULSION.targetSpeed * V1_PROPULSION.targetSpeed -
         entrySpeed * entrySpeed) /
        (2.0f * V1_PROPULSION.netAcceleration), 0.0f);
    const float physicalLength = fmaxf(accelerationDistance,
                                       V1_PROPULSION.minimumSectionLength);
    return ceilf(physicalLength / SEG_LEN - 1.0e-4f) * SEG_LEN;
}

static float tangentPitchDegrees(const Sample &sample) {
    const float horizontal = sqrtf(sample.tangent.x * sample.tangent.x +
                                   sample.tangent.z * sample.tangent.z);
    return fabsf(atan2f(sample.tangent.y, fmaxf(horizontal, 1.0e-5f))) /
           DEG2RAD;
}

static float headingChangeDegrees(const Sample &sample, float referenceHeading) {
    const float horizontal = sqrtf(sample.tangent.x * sample.tangent.x +
                                   sample.tangent.z * sample.tangent.z);
    if (horizontal < 1.0e-5f) return 180.0f;
    const float heading = atan2f(sample.tangent.x, sample.tangent.z);
    return fabsf(wrapPi(heading - referenceHeading)) / DEG2RAD;
}

static bool adjacentLevelFlat(const Sample &sample, float referenceHeading) {
    return sample.tag == M_FLAT && sample.declaredDrive != 2 &&
           tangentPitchDegrees(sample) <= POWER_LEVEL_PITCH_DEG &&
           sample.curvatureMag <= POWER_CURVATURE_MAX &&
           headingChangeDegrees(sample, referenceHeading) <= POWER_HEADING_CHANGE_DEG;
}

static void inspectPropulsion(const std::vector<Sample> &v, SeedMetric &m) {
    float previousPowerStart = -1.0f;

    // A BOOST/LAUNCH label without its drive channel is an orphaned visual deck,
    // counted once per contiguous occurrence rather than once per 12 Hz sample.
    for (int i = 0; i < (int)v.size();) {
        const bool orphan = poweredRole(v[i].tag) && v[i].declaredDrive != 2;
        if (!orphan) { ++i; continue; }
        ++m.orphanPoweredTags;
        const unsigned char role = v[i].tag;
        while (++i < (int)v.size() && v[i].tag == role &&
               v[i].declaredDrive != 2) {}
    }

    for (int i = 0; i + 1 < (int)v.size();) {
        if (v[i].declaredDrive != 2) { ++i; continue; }
        const int first = i;
        while (i + 1 < (int)v.size() && v[i + 1].declaredDrive == 2) ++i;
        const int last = i;
        const unsigned char role = v[first].tag;
        const float start = v[first].s;
        if (last + 1 >= (int)v.size()) {
            if (poweredRole(role)) previousPowerStart = start;
            break; // finalized window ended inside the block
        }
        const float length = v[last + 1].s - start;
        const float entrySpeed = role == M_LAUNCH ? 0.0f : v[first].plannedSpeed;
        const bool validEntrySpeed = std::isfinite(entrySpeed) && entrySpeed >= 0.0f;
        const float expectedLength = validEntrySpeed ? poweredBlockLength(entrySpeed) : 0.0f;
        const float lengthError = validEntrySpeed ? fabsf(length - expectedLength) : INFINITY;
        const float referenceHeading = atan2f(v[first].tangent.x, v[first].tangent.z);
        const uint32_t runId = v[first].runId;
        float blockPitch = 0.0f, blockCurvature = 0.0f, blockHeading = 0.0f;
        bool wrongOwner = !poweredRole(role) || runId == 0 || !validEntrySpeed;
        bool suppressedDrive = false;
        for (int q = first; q <= last; ++q) {
            wrongOwner = wrongOwner || v[q].tag != role || v[q].runId != runId;
            suppressedDrive = suppressedDrive || v[q].drive != 2;
            blockPitch = fmaxf(blockPitch, tangentPitchDegrees(v[q]));
            blockCurvature = fmaxf(blockCurvature, v[q].curvatureMag);
            blockHeading = fmaxf(blockHeading,
                                  headingChangeDegrees(v[q], referenceHeading));
        }

        float lead = 0.0f;
        for (int q = first - 1; q >= 0 && adjacentLevelFlat(v[q], referenceHeading); --q)
            lead += v[q + 1].s - v[q].s;
        float tail = 0.0f;
        for (int q = last + 1; q + 1 < (int)v.size() &&
             adjacentLevelFlat(v[q], referenceHeading); ++q)
            tail += v[q + 1].s - v[q].s;

        const int previousBlocks = m.poweredBlocks++;
        if (!previousBlocks) m.minPoweredLength = m.maxPoweredLength = length;
        else {
            m.minPoweredLength = fminf(m.minPoweredLength, length);
            m.maxPoweredLength = fmaxf(m.maxPoweredLength, length);
        }
        if (role == M_BOOST) ++m.boostBlocks;
        if (role == M_LAUNCH) ++m.launchBlocks;
        m.maxPoweredLengthError = fmaxf(m.maxPoweredLengthError, lengthError);
        m.maxPoweredPitch = fmaxf(m.maxPoweredPitch, blockPitch);
        m.maxPoweredCurvature = fmaxf(m.maxPoweredCurvature, blockCurvature);
        m.maxPoweredHeadingChange = fmaxf(m.maxPoweredHeadingChange, blockHeading);
        m.maxUnpoweredLead = fmaxf(m.maxUnpoweredLead, lead);
        m.maxUnpoweredTail = fmaxf(m.maxUnpoweredTail, tail);

        if (wrongOwner || suppressedDrive ||
            lengthError > POWER_LENGTH_TOLERANCE_M ||
            blockPitch > POWER_LEVEL_PITCH_DEG ||
            blockCurvature > POWER_CURVATURE_MAX ||
            blockHeading > POWER_HEADING_CHANGE_DEG ||
            lead > SEG_LEN + POWER_FLAT_TOLERANCE_M ||
            tail > SEG_LEN + POWER_FLAT_TOLERANCE_M)
            ++m.badPoweredBlocks;

        // Cadence is measured start-to-start, matching the scheduler's physical
        // odometer. An early section is legitimate only when the predicted entry
        // speed has reached the explicit anti-stall reserve.
        if (role == M_BOOST && previousPowerStart >= 0.0f) {
            const float spacing = start - previousPowerStart;
            const int previousIntervals = m.cadenceIntervals++;
            if (!previousIntervals) m.minPowerSpacing = m.maxPowerSpacing = spacing;
            else {
                m.minPowerSpacing = fminf(m.minPowerSpacing, spacing);
                m.maxPowerSpacing = fmaxf(m.maxPowerSpacing, spacing);
            }
            if (spacing < V1_PROPULSION.nominalCadence - CADENCE_EARLY_TOLERANCE_M) {
                if (entrySpeed <= V1_PROPULSION.operatingReserve + BACKSTOP_SPEED_TOLERANCE)
                    ++m.cadenceBackstop;
                else
                    ++m.cadenceEarly;
            } else if (spacing <= V1_PROPULSION.nominalCadence +
                                  CADENCE_LATE_TOLERANCE_M) {
                ++m.cadenceScheduled;
            } else {
                ++m.cadenceLate;
            }
        }
        if (poweredRole(role)) previousPowerStart = start;
        ++i;
    }
    if (!m.launchBlocks) ++m.badPoweredBlocks;
    if (previousPowerStart >= 0.0f && !v.empty()) {
        m.finalPowerAge = v.back().s - previousPowerStart;
        if (m.finalPowerAge > V1_PROPULSION.nominalCadence +
                              CADENCE_LATE_TOLERANCE_M)
            ++m.cadenceLate;
    }
}

static SeedMetric inspectSeed(int seed) {
    SeedMetric m;
    g_rng = (uint32_t)seed * UINT32_C(2654435761) | UINT32_C(1);
    Track t; t.reset();

    const int frozen = t.finalizedPointCount();
    const uint64_t before = frozen > 0 ? prefixHash(t, frozen) : 0;
    t.ensureFinalizedAhead(470.0f);
    m.finalPoints = t.finalizedPointCount();
    m.generationExhaustions = t.schedulerExhaustions;
    m.immutable = frozen > 0 && m.finalPoints > frozen && before == prefixHash(t, frozen);
    if (!m.immutable || m.finalPoints < 450 || m.generationExhaustions != 0) {
        ++m.hard;
        // A shortened finalized window is a generation failure in its own
        // right. Do not sample the terminal clamp and manufacture shape,
        // terrain, or propulsion measurements from a route that does not
        // exist beyond that boundary.
        if (m.finalPoints < 450 || m.generationExhaustions != 0) return m;
    }

    std::vector<Sample> v = sampleFinal(t);
    if (v.size() < 64) { ++m.hard; return m; }
    m.length = v.back().s;
    std::vector<Extremum> ext = findExtrema(v);

    for (const Extremum &x : ext) {
        if (shapeExcluded(v[x.i])) continue;
        StraightRun shelf = lowCurvatureNear(v, x.i, SHELF_PITCH_DEG * PI / 180.0f);
        StraightRun broad = lowCurvatureNear(v, x.i, INCLINE_DEG * PI / 180.0f);
        if (shelf.length >= SHELF_MIN_M) {
            if (x.crest) {
                ++m.crestShelves;
                if (m.firstCrest < 0.0f) { m.firstCrest = v[x.i].s; m.firstCrestU = v[x.i].u; m.firstCrestTag = v[x.i].tag; }
            } else {
                ++m.valleyShelves;
                if (m.firstValley < 0.0f) { m.firstValley = v[x.i].s; m.firstValleyU = v[x.i].u; m.firstValleyTag = v[x.i].tag; }
            }
        } else if (!x.crest && broad.length >= INCLINE_MIN_M &&
                   broad.meanAbsPitch >= 2.0f * PI / 180.0f) {
            ++m.inclinedTroughs;
            if (m.firstIncline < 0.0f) { m.firstIncline = v[x.i].s; m.firstInclineU = v[x.i].u; }
        }
    }

    BurstMetric vr = reversalBursts(v, false), pr = reversalBursts(v, true);
    m.verticalBursts = vr.count; m.maxVerticalFlips = vr.maxFlips;
    m.firstVRev = vr.first; m.firstVRevTag = vr.firstTag;
    m.planBursts = pr.count; m.maxPlanFlips = pr.maxFlips; m.firstPRev = pr.first;
    inspectStubs(t, m);
    inspectBankGaps(v, m);
    inspectContinuity3D(v, m);
    inspectNamedElements(t, v, m);
    inspectTopHats(t, v, m);
    for (int i = 1; i < t.finalizedPointCount(); ++i)
        if (Vector3Distance(t.cp[i - 1], t.cp[i]) > 40.0f) ++m.gaps;
    float elevatedRun = 0.0f;
    float macroStraight = 0.0f;
    for (int i = 1; i < (int)v.size(); ++i) {
        float pitchStep = fabsf(v[i].pitch - v[i - 1].pitch);
        float headingStep = fabsf(wrapPi(v[i].heading - v[i - 1].heading));
        if (pitchStep > 30.0f * PI / 180.0f ||
            (v[i].planValid && v[i - 1].planValid && headingStep > 30.0f * PI / 180.0f)) {
            if (m.firstSnap < 0.0f) { m.firstSnap = v[i].s; m.firstSnapU = v[i].u; }
            ++m.directionSnaps;
        }

        bool flatHigh = fabsf(v[i].pitch) < 2.0f * PI / 180.0f &&
            v[i].p.y - groundTopAt(v[i].p.x, v[i].p.z) > 50.0f &&
            (v[i].tag == M_FLAT || v[i].tag == M_BOOST || v[i].tag == M_LAUNCH);
        elevatedRun = flatHigh ? elevatedRun + (v[i].s - v[i - 1].s) : 0.0f;
        if (elevatedRun > 220.0f) { ++m.elevatedFlats; elevatedRun = -1.0e9f; }

        bool macroShape = v[i].macroKind == Track::MACRO_TOP_HAT ||
                          v[i].macroKind == Track::MACRO_DROP ||
                          v[i].macroKind == Track::MACRO_HILLS;
        bool constantGrade = macroShape && fabsf(v[i].pitch) > 5.0f * PI / 180.0f &&
                             fabsf(v[i].kVert) < 0.00005f;
        macroStraight = constantGrade ? macroStraight + (v[i].s - v[i - 1].s) : 0.0f;
        m.maxMacroStraight = fmaxf(m.maxMacroStraight, macroStraight);
    }
    for (const Sample &sample : v) {
        const float ground = groundTopAt(sample.p.x, sample.p.z);
        const bool overWater = submergedGround(ground);
        const bool explicitWaterDip = sample.tag == M_DIP && overWater;
        const float requiredFloor = explicitWaterDip
            ? WATER_Y + 0.5f
            : (overWater ? Track::ordinaryCorridorFloor(ground)
                         : ground - TERRAIN_PENETRATION_M);
        if (sample.p.y < requiredFloor) {
            if (m.firstUnder < 0.0f) {
                m.firstUnder = sample.s;
                m.firstUnderU = sample.u;
                m.firstUnderTag = sample.tag;
            }
            ++m.subterranean;
            m.maxPenetration = fmaxf(m.maxPenetration,
                requiredFloor - sample.p.y);
        }
    }
    inspectPropulsion(v, m);

    // Shelf/reversal counters remain visible shape diagnostics. They are not structural failures:
    // normal terrain-transition easings can meet their local-curvature heuristic. The hard set is
    // reserved for actual broken track, unsafe terrain interaction, truncated runs and bad hats.
    m.hard += m.shortFlats + m.shortDrops;
    m.hard += m.planBursts;
    m.hard += m.bankGaps + m.badHats + m.subterranean + m.continuityBreaks +
              m.directionSnaps + m.elevatedFlats + m.gaps;
    m.hard += m.badLoops + m.badImmels + m.badRolls + m.badHills +
              m.badHelixes + m.badWaves + m.badBankAirs;
    m.hard += m.badPoweredBlocks + m.orphanPoweredTags +
              m.cadenceEarly + m.cadenceLate;
    // A fixed 474-point window can end before the lap's launch hat; the rolling census owns its
    // per-lap occurrence requirement. Any hat that is present is still fully shape/cap validated.
    return m;
}

static const char *tagName(unsigned char tag) {
    static const char *names[M_COUNT] = {"FLAT","CLIMB","DROP","HILLS","TURN","LOOP","ROLL","STN","DIP","LAUNCH","HELIX","BOOST","IMMEL","SCURVE","DIVE","BANKAIR","WAVE","STALL","DIVELOOP"};
    return tag < M_COUNT ? names[tag] : "?";
}

static void printLoci(const SeedMetric &m) {
    if (m.firstCrest >= 0)  printf(" crest@%.0f/u%.2f:%s", m.firstCrest, m.firstCrestU, tagName(m.firstCrestTag));
    if (m.firstValley >= 0) printf(" valley@%.0f/u%.2f:%s", m.firstValley, m.firstValleyU, tagName(m.firstValleyTag));
    if (m.firstIncline >= 0)printf(" incline@%.0f/u%.2f", m.firstIncline, m.firstInclineU);
    if (m.firstVRev >= 0)   printf(" vrev@%.0f:%s", m.firstVRev, tagName(m.firstVRevTag));
    if (m.firstPRev >= 0)   printf(" prev@%.0f", m.firstPRev);
    if (m.firstStub >= 0)   printf(" stub@%.0f", m.firstStub);
    if (m.firstBankGap >= 0)printf(" bankgap@%.0f", m.firstBankGap);
    if (m.firstUnder >= 0)  printf(" under@%.0f/u%.2f:%s", m.firstUnder,
                                   m.firstUnderU, tagName(m.firstUnderTag));
    if (m.firstSnap >= 0)   printf(" snap@%.0f/u%.2f", m.firstSnap, m.firstSnapU);
    if (m.firstContinuity >= 0)
        printf(" c3@%.0f/u%.2f:%s>%s", m.firstContinuity, m.firstContinuityU,
               tagName(m.firstContinuityBefore), tagName(m.firstContinuityAfter));
    if (m.continuityBreaks) {
        printf(" c3tags=");
        bool first = true;
        for (int tag = 0; tag < M_COUNT; ++tag) if (m.continuityByTag[tag]) {
            printf("%s%s:%d", first ? "" : ",", tagName((unsigned char)tag),
                   m.continuityByTag[tag]);
            first = false;
        }
    }
    if (m.firstNamedDefect >= 0.0f)
        printf(" named@%.0f:%s", m.firstNamedDefect, tagName(m.firstNamedTag));
}

} // namespace

int run(int seeds) {
    seeds = Clamp(seeds, 1, 64);
    const uint32_t savedRng = g_rng;
    int failedSeeds = 0, defects = 0;
    int namedRuns[7]{}, namedBad[7]{};
    unsigned rollHandMask = 0;
    printf("=== V1 finalized geometry audit (%d seed%s) ===\n", seeds, seeds == 1 ? "" : "s");
    printf("[power-contract] 360km/h at 1.5x Do-Dodonpa; driven rail pitch<=%.2fdeg "
           "bend<=%.2fdeg curvature<=%.5f/m; length=ceil(max(kinematic,%.0fm)/%.0fm); "
           "unpowered FLAT<=%.0fm/end; cadence %.0fm (scheduled %.0f..%.0fm, "
           "earlier only at <=%.0fkm/h backstop)\n",
           POWER_LEVEL_PITCH_DEG, POWER_HEADING_CHANGE_DEG, POWER_CURVATURE_MAX,
           V1_PROPULSION.minimumSectionLength, SEG_LEN, SEG_LEN,
           V1_PROPULSION.nominalCadence,
           V1_PROPULSION.nominalCadence - CADENCE_EARLY_TOLERANCE_M,
           V1_PROPULSION.nominalCadence + CADENCE_LATE_TOLERANCE_M,
           (V1_PROPULSION.operatingReserve + BACKSTOP_SPEED_TOLERANCE) * 3.6f);
    printf("[named-contract] loop lateral<=%.2fm, common scale error<=%.3f; "
           "endpoint roll<=%.2fdeg/m and %.2fdeg/m2; helix coil>=%.2fm\n",
           LOOP_PLANAR_TOLERANCE_M, LOOP_SCALE_MATCH_MAX,
           ENDPOINT_ROLL_RATE_MAX, ENDPOINT_ROLL_ACCEL_MAX,
           HELIX_SUPPORT_ENVELOPE_M);
    for (int seed = 1; seed <= seeds; ++seed) {
        SeedMetric m = inspectSeed(seed);
        const HatMetric &h = m.primaryHat;
        const MetricRange *d = m.dimension;
        printf("[v1-geo] seed%d final=%d len=%.0fm immutable=%s "
               "shelf=%d/%d incline=%d rev=%d/%d(%d/%d) stub=%d/%d bankgap=%d "
               "hat=%d bad=%d drop=%.0fm plan=%.1fm rail=%.1fm crownR=%.2fm clr=%.0fm face=%.0f/%+.0f line=%.0fm macroline=%.0fm "
               "power=B%d/L%d bad=%d orphan=%d len=%.1f..%.1fm err=%.1fm pitch=%.2fdeg bend=%.2fdeg k=%.3f/km lead/tail=%.1f/%.1fm "
               "cadence=scheduled:%d backstop:%d early:%d late:%d spacing=%.0f..%.0fm open=%.0fm wrong=%.0fm hrev=%d under=%d/%.1fm "
               "c3=%d(%d/%d/%d) t=%.1fdeg kj=%.4f/%.4f/%.4f kr=%.4f roll=%.1f/%.1f/%.1f/%.1f "
               "named=L%d/%d(near=%.1fm asp=%.2f crown=%.1fm R/H=%.2f kramp=%.2f lat=%.1fm scale=%.3f apex=%.1fdeg) "
               "I%d/%d(rise=%.0fm turn=%.0fdeg twist=%.0fdeg seam=%.2f ov=%.1fm end=%.2f/%.3f) "
               "R%d/%d(exc=%.1fm twist=%.0fdeg inward=%.3f hand=%u) "
               "H%d/%d(lobes=%d/%d rise=%.0f..%.0fm plan=%.0f..%.0fm rail=%.0f..%.0fm crownR=%.1f..%.1fm) "
               "X%d/%d(drop=%.0f..%.0fm rev=%.2f..%.2f R=%.0f..%.0fm plan=%.0f..%.0fm rail=%.0f..%.0fm coil=%.1f..%.1fm end=%.2f/%.3f) "
               "W%d/%d(rise=%.0f..%.0fm R=%.0f..%.0fm plan=%.0f..%.0fm rail=%.0f..%.0fm) "
               "B%d/%d(rise=%.0f..%.0fm R=%.0f..%.0fm plan=%.0f..%.0fm rail=%.0f..%.0fm yaw=%.0fdeg bank=%.0fdeg ov=%.0f%% dead=%.1fm seam=%.2f end=%.2f/%.3f) "
               "snap=%d gap=%d highflat=%d hard=%d",
               seed, m.finalPoints, m.length, m.immutable ? "yes" : "NO",
               m.crestShelves, m.valleyShelves, m.inclinedTroughs,
               m.verticalBursts, m.planBursts, m.maxVerticalFlips, m.maxPlanFlips,
               m.shortFlats, m.shortDrops, m.bankGaps, m.hats, m.badHats,
               h.drop, h.planLength, h.railLength, h.crownRadius,
               h.maxTerrainClearance, h.climbFace, h.dropFace, h.straightFace,
               m.maxMacroStraight, m.boostBlocks, m.launchBlocks,
               m.badPoweredBlocks, m.orphanPoweredTags,
               m.minPoweredLength, m.maxPoweredLength, m.maxPoweredLengthError,
               m.maxPoweredPitch, m.maxPoweredHeadingChange,
               1000.0f * m.maxPoweredCurvature,
               m.maxUnpoweredLead, m.maxUnpoweredTail,
               m.cadenceScheduled, m.cadenceBackstop,
               m.cadenceEarly, m.cadenceLate,
               m.minPowerSpacing, m.maxPowerSpacing,
               m.finalPowerAge,
               h.wrongWay, h.reversals, m.subterranean, m.maxPenetration,
               m.continuityBreaks, m.tangentBreakSamples, m.curvatureBreakSamples,
               m.rollBreakSamples, m.maxTangentStep, m.maxCurvatureJump,
               m.maxCurvatureOneSidedJerk, m.maxCurvatureVecJerk,
               m.maxCurvatureMagJerk, m.maxRollStep,
               m.maxRollRate, m.maxRollAccel, m.maxRollJerk,
               m.loopRuns, m.badLoops, m.minLoopClearance, m.maxLoopAspect,
               m.minLoopCrown, m.maxLoopCrownRadiusRatio, m.minLoopCurvatureRamp,
               m.maxLoopLateral, m.maxLoopScaleError,
               m.maxLoopApexTangentError,
               m.immelRuns, m.badImmels, m.minImmelRise,
               m.minImmelTurn, m.minImmelTwist, m.maxImmelSeam,
               m.minImmelOverlap, m.maxImmelEndpointRate,
               m.maxImmelEndpointAccel,
               m.rollRuns, m.badRolls, m.minRollExcursion,
               m.minRollTwist, m.minRollInwardAlignment, m.rollHandMask,
               m.hillRuns, m.badHills, m.hillLobes, m.badHillLobes,
               d[HILL_RISE].minimum, d[HILL_RISE].maximum,
               d[HILL_PLAN].minimum, d[HILL_PLAN].maximum,
               d[HILL_RAIL].minimum, d[HILL_RAIL].maximum,
               d[HILL_CROWN_RADIUS].minimum, d[HILL_CROWN_RADIUS].maximum,
               m.helixRuns, m.badHelixes,
               d[HELIX_DROP].minimum, d[HELIX_DROP].maximum,
               d[HELIX_REVS].minimum, d[HELIX_REVS].maximum,
               d[HELIX_RADIUS].minimum, d[HELIX_RADIUS].maximum,
               d[HELIX_PLAN].minimum, d[HELIX_PLAN].maximum,
               d[HELIX_RAIL].minimum, d[HELIX_RAIL].maximum,
               d[HELIX_COIL].minimum, d[HELIX_COIL].maximum,
               m.maxHelixEndpointRate, m.maxHelixEndpointAccel,
               m.waveRuns, m.badWaves,
               d[WAVE_RISE].minimum, d[WAVE_RISE].maximum,
               d[WAVE_RADIUS].minimum, d[WAVE_RADIUS].maximum,
               d[WAVE_PLAN].minimum, d[WAVE_PLAN].maximum,
               d[WAVE_RAIL].minimum, d[WAVE_RAIL].maximum,
               m.bankAirRuns, m.badBankAirs,
               d[BANKAIR_RISE].minimum, d[BANKAIR_RISE].maximum,
               d[BANKAIR_RADIUS].minimum, d[BANKAIR_RADIUS].maximum,
               d[BANKAIR_PLAN].minimum, d[BANKAIR_PLAN].maximum,
               d[BANKAIR_RAIL].minimum, d[BANKAIR_RAIL].maximum,
               m.minBankAirHeading / DEG2RAD, m.minBankAirBank,
               100.0f * m.minBankAirOverlap, m.maxBankAirDead, m.maxBankAirSeam,
               m.maxBankAirEndpointRate, m.maxBankAirEndpointAccel,
               m.directionSnaps, m.gaps, m.elevatedFlats, m.hard);
        printLoci(m);
        if (m.generationExhaustions)
            printf(" genfail=%u", m.generationExhaustions);
        printf("\n");
        namedRuns[0] += m.loopRuns; namedBad[0] += m.badLoops;
        namedRuns[1] += m.immelRuns; namedBad[1] += m.badImmels;
        namedRuns[2] += m.rollRuns; namedBad[2] += m.badRolls;
        namedRuns[3] += m.hillRuns; namedBad[3] += m.badHills;
        namedRuns[4] += m.helixRuns; namedBad[4] += m.badHelixes;
        namedRuns[5] += m.waveRuns; namedBad[5] += m.badWaves;
        namedRuns[6] += m.bankAirRuns; namedBad[6] += m.badBankAirs;
        rollHandMask |= m.rollHandMask;
        if (m.hard) { ++failedSeeds; defects += m.hard; }
    }
    g_rng = savedRng;
    printf("V1 NAMED SHAPES LOOP=%d/%d IMMEL=%d/%d ROLL=%d/%d HILLS=%d/%d "
           "HELIX=%d/%d WAVE=%d/%d BANKAIR=%d/%d hands=%u (bad/runs)\n",
           namedBad[0], namedRuns[0], namedBad[1], namedRuns[1],
           namedBad[2], namedRuns[2], namedBad[3], namedRuns[3],
           namedBad[4], namedRuns[4], namedBad[5], namedRuns[5],
           namedBad[6], namedRuns[6], rollHandMask);
    printf("V1 GEOMETRY %s (%d failed seed%s, %d hard defect%s)\n",
           failedSeeds ? "FAIL" : "PASS", failedSeeds, failedSeeds == 1 ? "" : "s",
           defects, defects == 1 ? "" : "s");
    return failedSeeds ? 1 : 0;
}

} // namespace v1_geometry_audit
