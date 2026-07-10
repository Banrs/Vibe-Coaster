// Track V2 — whole-ride layout planner (COASTER_REWRITE.md §1). Plans a
// finite list of beats — each with entry/exit pose, speed intent, clearance
// band and minimum length — BEFORE any geometry is generated, then emits the
// primitives beat by beat. Built out over migration steps 2+; step 1 provides
// only the deterministic smoke route the acceptance harness drives.
#include "track_math.h"

namespace v2 {

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

} // namespace v2
