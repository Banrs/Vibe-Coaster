// Track V2 — primitive library: line, connector, top hat, camelback, drop,
// turn, helix (built out over migration steps 2–5; see COASTER_REWRITE.md's
// primitive table and docs/SHAPES.md for each shape's contract).
#include <cassert>

#include "track_math.h"

namespace v2 {

const char* tagName(Tag t) {
    switch (t) {
        case Tag::Station:    return "STATION";
        case Tag::Brake:      return "BRAKE";
        case Tag::Launch:     return "LAUNCH";
        case Tag::Line:       return "LINE";
        case Tag::Connector:  return "CONNECTOR";
        case Tag::TopHat:     return "TOPHAT";
        case Tag::Camelback:  return "CAMELBACK";
        case Tag::Drop:       return "DROP";
        case Tag::Turn:       return "TURN";
        case Tag::SCurve:     return "SCURVE";
        case Tag::Helix:      return "HELIX";
        case Tag::CliffDive:  return "CLIFFDIVE";
        case Tag::Loop:       return "LOOP";
        case Tag::Immelmann:  return "IMMELMANN";
        case Tag::DiveLoop:   return "DIVELOOP";
        case Tag::Corkscrew:  return "CORKSCREW";
        case Tag::ZeroGStall: return "ZEROGSTALL";
        default:              return "?";
    }
}

Pose emitLine(Route& r, float lengthM, Tag tag, bool chain) {
    // A line cannot absorb curvature; the upstream primitive must hand over
    // with a straight pose (its own exit ramp ends at zero curvature).
    assert(fabsf(r.endPose.kPitch) < 1e-4f && fabsf(r.endPose.kYaw) < 1e-4f);
    return emitSchedule(r, lengthM,
                        constantProfile(r.endPose.pitch),
                        constantProfile(r.endPose.yaw),
                        constantProfile(r.endPose.roll), tag, chain);
}

Pose emitConnector(Route& r, const Pose& target, Tag tag, bool chain) {
    // Tangent-length heuristic: proportional to the chord keeps the interior
    // curvature bounded; join continuity at the ends is exact for any lt > 0
    // (the Hermite matches pos/tangent/curvature there by construction).
    float chord = Vector3Distance(r.endPose.pos, target.pos);
    assert(chord > 1e-3f && "connector endpoints coincide");
    float lt = 1.2f * chord;
    QuinticHermite h = hermiteFromPoses(r.endPose, target, lt);
    return emitHermite(r, h, target.roll, tag, chain);
}

} // namespace v2
