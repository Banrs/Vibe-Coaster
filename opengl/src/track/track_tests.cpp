// Track V2 — acceptance/test harness entry point (standalone executable,
// no window). Exit code 0 == all checks pass; the build plus this binary is
// the verification gate for every migration step (COASTER_REWRITE.md
// "Acceptance harness").
#include <cmath>
#include <cstdio>

#include "track_math.h"

using namespace v2;

static int g_checks = 0, g_fails = 0;

#define CHECK(cond, ...)                                    \
    do {                                                    \
        g_checks++;                                         \
        if (!(cond)) {                                      \
            g_fails++;                                      \
            printf("FAIL %s:%d  ", __FILE__, __LINE__);     \
            printf(__VA_ARGS__);                            \
            printf("\n");                                   \
        }                                                   \
    } while (0)

static float len3(Vector3 v) { return sqrtf(v.x * v.x + v.y * v.y + v.z * v.z); }
static Vector3 sub3(Vector3 a, Vector3 b) { return Vector3{a.x - b.x, a.y - b.y, a.z - b.z}; }

// ---------------------------------------------------------------------------
static void testS5() {
    CHECK(fabsf(s5(0.0f)) < 1e-7f, "S5(0)=%g", s5(0.0f));
    CHECK(fabsf(s5(1.0f) - 1.0f) < 1e-6f, "S5(1)=%g", s5(1.0f));
    CHECK(fabsf(s5d(0.0f)) < 1e-6f && fabsf(s5d(1.0f)) < 1e-5f, "S5' endpoints");
    CHECK(fabsf(s5dd(0.0f)) < 1e-5f && fabsf(s5dd(1.0f)) < 1e-4f, "S5'' endpoints");
    // Derivatives against central differences. h is deliberately coarse:
    // second differences in float cancel catastrophically below h~1e-2.
    for (float u = 0.1f; u < 0.95f; u += 0.2f) {
        float h = 0.02f;
        float d1 = (s5(u + h) - s5(u - h)) / (2.0f * h);
        float d2 = (s5(u + h) - 2.0f * s5(u) + s5(u - h)) / (h * h);
        CHECK(fabsf(d1 - s5d(u)) < 5e-3f, "S5' at %g: %g vs %g", u, d1, s5d(u));
        CHECK(fabsf(d2 - s5dd(u)) < 5e-2f, "S5'' at %g: %g vs %g", u, d2, s5dd(u));
    }
}

// ---------------------------------------------------------------------------
static void testHermiteBasis() {
    // Endpoint conditions with distinct, non-axis-aligned vectors.
    QuinticHermite q;
    q.p0 = Vector3{1, 2, 3};
    q.v0 = Vector3{4, -1, 2};
    q.a0 = Vector3{0.5f, 0.25f, -0.75f};
    q.a1 = Vector3{-0.25f, 0.5f, 0.125f};
    q.v1 = Vector3{-2, 3, 1};
    q.p1 = Vector3{10, -4, 7};

    CHECK(len3(sub3(q.pos(0.0f), q.p0)) < 1e-5f, "H pos(0)");
    CHECK(len3(sub3(q.pos(1.0f), q.p1)) < 1e-5f, "H pos(1)");
    CHECK(len3(sub3(q.vel(0.0f), q.v0)) < 1e-4f, "H vel(0)");
    CHECK(len3(sub3(q.vel(1.0f), q.v1)) < 1e-4f, "H vel(1)");
    CHECK(len3(sub3(q.acc(0.0f), q.a0)) < 1e-3f, "H acc(0)");
    CHECK(len3(sub3(q.acc(1.0f), q.a1)) < 1e-3f, "H acc(1)");

    // vel/acc consistent with finite differences of pos mid-curve (coarse h:
    // float second differences cancel catastrophically below h~1e-2).
    for (float t = 0.2f; t < 0.9f; t += 0.3f) {
        float h = 0.02f;
        Vector3 fd = Vector3Scale(sub3(q.pos(t + h), q.pos(t - h)), 1.0f / (2.0f * h));
        CHECK(len3(sub3(fd, q.vel(t))) < 5e-2f, "H vel fd at %g", t);
        Vector3 fa = Vector3Scale(
            Vector3Add(sub3(q.pos(t + h), Vector3Scale(q.pos(t), 2.0f)), q.pos(t - h)),
            1.0f / (h * h));
        CHECK(len3(sub3(fa, q.acc(t))) < 0.5f, "H acc fd at %g", t);
    }
}

// ---------------------------------------------------------------------------
static void testSmokeRoute() {
    Route r = buildSmokeRoute(1);
    CHECK(r.samples.size() > 300, "smoke route has %zu samples", r.samples.size());
    CHECK(r.segs.size() == 5, "smoke route has %zu segs", r.segs.size());

    // Grid uniformity.
    for (size_t i = 1; i < r.samples.size(); i++) {
        float step = r.samples[i].s - r.samples[i - 1].s;
        if (fabsf(step - r.ds) > 1e-4f) {
            CHECK(false, "sample %zu arc step %g", i, step);
            break;
        }
    }

    // Continuity sweep + exact join checks must be clean.
    ValidationReport rep = validateRoute(r, nullptr);
    for (const Discontinuity& d : rep.discontinuities)
        printf("  discontinuity: s=%.1f %s jump=%g tag=%s\n", d.s, d.quantity, d.jump,
               tagName(d.tag));
    CHECK(rep.pass(), "smoke route validation: %zu discontinuities, %zu failures",
          rep.discontinuities.size(), rep.elementFailures.size());

    // Straight-line beats stay straight and level.
    const Sample& s10 = r.samples[10];
    CHECK(fabsf(s10.pitch) < 1e-6f && fabsf(s10.kPitch) < 1e-7f, "station is level");

    // Frames: unit up, orthogonal to tangent, upright where roll==0.
    for (size_t i = 0; i < r.samples.size(); i += 7) {
        const Sample& s = r.samples[i];
        CHECK(fabsf(len3(s.up) - 1.0f) < 1e-3f, "up length at %zu", i);
        CHECK(fabsf(Vector3DotProduct(s.up, s.tan)) < 2e-2f, "up.tan at %zu = %g", i,
              Vector3DotProduct(s.up, s.tan));
        if (i >= r.samples.size()) break;
    }
    CHECK(r.samples[10].up.y > 0.999f, "station frame upright");

    // Connector reached its planned target pose (planner-side sanity).
    const SegmentRec& conn = r.segs[3];
    CHECK(conn.tag == Tag::Connector, "seg 3 is the connector");
    CHECK(fabsf(conn.exit.pitch) < 1e-3f, "connector exits level, pitch=%g", conn.exit.pitch);
    CHECK(fabsf(conn.exit.kPitch) < 1e-3f && fabsf(conn.exit.kYaw) < 1e-3f,
          "connector exits straight");
}

// ---------------------------------------------------------------------------
static void testAdapter() {
    TrackV2 trk;
    trk.build(1);
    size_t n = trk.route.samples.size();
    CHECK(n > 0, "adapter built");
    CHECK(trk.cp.size() == n && trk.up.size() == n && trk.kind.size() == n &&
              trk.chainf.size() == n && trk.arc.size() == n,
          "mirror sizes");

    // Integer u hits samples exactly.
    for (size_t i = 0; i < n; i += 50) {
        Vector3 p = trk.pos((float)i);
        CHECK(len3(sub3(p, trk.route.samples[i].pos)) < 1e-4f, "pos(%zu) matches sample", i);
    }
    // Fractional u interpolates between neighbours.
    Vector3 mid = trk.pos(10.5f);
    Vector3 expect = Vector3Lerp(trk.route.samples[10].pos, trk.route.samples[11].pos, 0.5f);
    CHECK(len3(sub3(mid, expect)) < 1e-4f, "pos(10.5) interpolates");

    CHECK(fabsf(trk.speedScale(3.0f) - trk.route.ds) < 1e-6f, "speedScale == ds");
    CHECK(trk.tagAt(5.0f) == (unsigned char)Tag::Station, "tag at station");
    CHECK(trk.chainAt(40.0f), "launch beat is powered (chain flag)");
    CHECK(!trk.chainAt(5.0f), "station is not powered");
    CHECK(fabsf(trk.maxU() - (float)(n - 1)) < 1e-3f, "maxU on open route");

    // Out-of-range u clamps instead of crashing (V1 accessors clamp too).
    (void)trk.pos(-5.0f);
    (void)trk.pos((float)n + 25.0f);
    (void)trk.tangent(-1.0f);
    CHECK(true, "out-of-range access safe");
}

// ---------------------------------------------------------------------------
int main() {
    testS5();
    testHermiteBasis();
    testSmokeRoute();
    testAdapter();
    printf("%s: %d checks, %d failures\n", g_fails == 0 ? "PASS" : "FAIL", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
