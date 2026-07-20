#pragma once
// Centralised design constants for the V1 streaming generator.
//
// Phase 1 of the refactor moves Track's static constexpr design constants (and
// the scattered scheduler/terrain/entry constants) here VERBATIM, as constexpr
// globals in namespace `genc`.  Track keeps thin `static constexpr` aliases that
// reference these, so ZERO call sites change and the sizing spec stays at its
// Phase-1 parity values (RECORD_SCALE floor/ceiling unchanged; value changes are
// Phase 4).  These are consumed both by Track and by the terrain-probe service.
#include "../src/v1_profiles.h"

namespace genc {

// Reserve successor lookahead beyond the final sampling stencil.
inline constexpr int ADAPTIVE_LAG = 23;

// Every physical axis owns the same record-scale contract.  Phase 4 lowered
// the floor from 1.0x to 0.75x (approved sizing spec): a smaller element
// admits a LOWER entry speed (its viability window widens at the bottom),
// which helps mix breadth without ever conceding the 1.5x hard cap.
// Centreline length alone gets a small allowance for C3 shoulders and 14 m
// publication quantisation.  A height cap can therefore never conceal an
// oversized radius or kilometre-long path again.
inline constexpr float RECORD_SCALE_MIN       = 0.75f;
inline constexpr float RECORD_SCALE_CAP       = 1.50f;
inline constexpr float TOP_HAT_RECORD_RISE =
    (float)v1profile::kTopHatReferenceRise; // Intamin Falcon's Flight camelback
inline constexpr float TOP_HAT_FACE_DEGREES =
    (float)v1profile::kTopHatReferenceFaceDegrees;
inline constexpr float TOP_HAT_VERTICAL_CAP =
    TOP_HAT_RECORD_RISE * RECORD_SCALE_CAP; // 247.5 m: rise, drop and terrain clearance
inline constexpr float LOOP_RECORD_HEIGHT     = 54.5592f;  // Tormenta, official 179 ft loop
inline constexpr float IMMEL_RECORD_HEIGHT    = 66.4464f;  // Tormenta, official 218 ft Immelmann
inline constexpr float LOOP_REFERENCE_CROWN_RADIUS =
    LOOP_RECORD_HEIGHT * (19.6f / 48.8f); // canonical clothoid crown, not half-height
inline constexpr float IMMEL_REFERENCE_RADIUS = IMMEL_RECORD_HEIGHT * 0.5f;
inline constexpr float DIVELOOP_RECORD_DROP   = 60.0f;
inline constexpr float AIRTIME_RECORD_HEIGHT  = 60.0f;
inline constexpr float BANKAIR_RECORD_HEIGHT  = 35.0f;
inline constexpr float CORKSCREW_REFERENCE_RADIUS = 6.6f;
inline constexpr float CORKSCREW_REFERENCE_EXCURSION =
    2.0f * CORKSCREW_REFERENCE_RADIUS;
inline constexpr float CORKSCREW_REFERENCE_RAIL = 94.30664f;
inline constexpr float HELIX_RECORD_REVS      = 1.625f;

// No formal helix-radius world record is published.  Six Flags America's
// engineering workbook does publish 30.5 m for Ride of Steel's first
// horizontal loop/helix, so this is deliberately named as a real-ride
// reference rather than a fictitious WR.  Its 1.5x cap is 45.75 m radius
// (91.5 m diameter).
inline constexpr float HELIX_REFERENCE_RADIUS = 30.5f;
inline constexpr float HELIX_REFERENCE_DROP   = 30.0f;
inline constexpr float HELIX_TARGET_G         = 11.75f;
inline constexpr float HELIX_SPIRAL_SWEEP     = 6.0f;
inline constexpr float HELIX_MAX_REVS         = 1.725f;
inline constexpr float BANKAIR_REFERENCE_RADIUS = 132.0f;
inline constexpr float WAVE_REFERENCE_RADIUS    = 100.0f;
inline constexpr float HILL_REFERENCE_LOBE_PLAN = 190.44893f;
inline constexpr float HILL_REFERENCE_LOBE_RAIL = 233.50868f;
inline constexpr float HILL_REFERENCE_CROWN_RADIUS = 30.625f;
inline constexpr float HARD_TURN_REFERENCE_RADIUS = 45.0f;
inline constexpr float SPEED_TURN_REFERENCE_RADIUS = 68.0f;
inline constexpr float HARD_TURN_REFERENCE_LENGTH = 210.0f;
inline constexpr float SPEED_TURN_REFERENCE_LENGTH = 154.0f;
inline constexpr float SCURVE_REFERENCE_RADIUS = SPEED_TURN_REFERENCE_RADIUS;
inline constexpr float SCURVE_REFERENCE_PLAN = 140.0f;
inline constexpr float SCURVE_REFERENCE_RISE = 10.0f;

// Boundary scheduler bounds.
inline constexpr int SCHEDULER_ATTEMPT_BUDGET = 3;
// Hard bound on terminal forward escapes taken from one anchor before the
// scheduler forces a powered launch/boost.
inline constexpr int ESCAPE_LIMIT = 6;
inline constexpr int ESCAPES_PER_LAP = 20;
inline constexpr int INVERSION_BUDGET = 4;

// Minimum length of a complete connective transition.
inline constexpr int MIN_CONN = 4;   // 4 cps ~= 56 m; longer only when the actual incoming curvature requires it

// Terrain is a whole-corridor constraint; ordinary routes target a shallow cutting.
inline constexpr float TERRAIN_CUT_TOLERANCE = 18.0f;
inline constexpr float TERRAIN_DECK_CLEARANCE = 2.0f;

// Energy solve for a -5 g crest: v_entry^2 = g*scale*
// (2*60 m + 6*30.625 m). Scaling height and radius together gives the
// exact 1.0--1.5x geometry window rather than an unrelated speed clamp.
inline constexpr float HILL_ENTRY_MIN = 48.0f; // 172.8 km/h; entering slower than the exact -5g energy solve (54.59f/196.5 km/h at 1.0x) just yields a gentler (floater) crest -- the 1.0-1.5x dimension clamp still applies -- so widen the window here so the airtime family isn't starved by near-misses.
inline constexpr float HILL_ENTRY_MAX = 66.85f; // 240.7 km/h at 1.5x

// Macro-profile sampling step (plan-view metres between authored knots).
inline constexpr float MACRO_SAMPLE_STEP = 7.0f;

// U1 occupancy (Phase 2).  A persistent 16 m hash grid of committed track
// spans is consulted by every commit qualification path so an element can
// never be authored through already-built geometry.  The rider envelope is
// the project 6 m centreline clearance (docs/REFACTOR_PLAN.md U1); escape
// arcs/connectors relax to 4 m, and a completion-safety fallback relaxes the
// ordinary envelope to 4.5 m in the boundary escape stage.  A candidate span
// only tests against committed spans whose arc-length differs by more than
// OCCUPANCY_ARC_EXCLUDE (the same 120 m self-exclusion the --overlap probe
// uses), so the track a new element legitimately joins onto is never a clip.
inline constexpr float OCCUPANCY_CELL            = 16.0f;
inline constexpr float OCCUPANCY_ENVELOPE        = 6.0f;
inline constexpr float OCCUPANCY_ENVELOPE_ESCAPE = 4.0f;
inline constexpr float OCCUPANCY_ENVELOPE_RELAXED = 4.5f;
// Absolute last-resort clearance for a genuinely boxed-in anchor (occupancy
// rerouting can steer a lap into a corner baseline never visited).  Kept above
// the 2 m hard-clip threshold so completion is guaranteed WITHOUT ever
// producing a <2 m geometry intersection -- the overlap gate's zero-tolerance
// invariant.  Only the escape/launch fallbacks ever drop this low.
inline constexpr float OCCUPANCY_ENVELOPE_LASTRESORT = 2.5f;
inline constexpr float OCCUPANCY_ARC_EXCLUDE     = 120.0f;

// --- PHASE 4 COMPOSITION DIRECTOR ---------------------------------------
// Share controller (U3/U4).  Replaces the count-based per-lap caps with a
// windowed share controller: SHARE_TARGET[m] is the target percent of
// COUNTED features (the same denominator the census "observed mix" uses).
// Bands are [SHARE_BAND_LO, SHARE_BAND_HI] x target.  Set-piece / count
// rules (top hat, splashdown, corkscrew pairing, inversion adjacency and
// budget) are kept separately in the generator; a 0 target here means the
// element is governed by a count rule, not the share controller.
inline constexpr float SHARE_BAND_LO = 0.75f;
inline constexpr float SHARE_BAND_HI = 1.75f;
// Sliding window (most-recent counted features) the live shares are measured
// over -- adaptive, so an early-ride deficit does not become permanent debt.
inline constexpr int   SHARE_WINDOW  = 48;
// Banked-turn family (elemFamily(3) = TURN/SCURVE/DIVE/WAVE) aggregate target.
// The family hi-gate is the binding one for that family (the per-subtype
// bands sum a little above it by design).
inline constexpr float FAMILY_BANKED_TARGET = 26.0f;

// Target percent of counted features, indexed by SegMode (positional, enum
// order).  0 == count-ruled / not a counted feature.
inline constexpr float SHARE_TARGET[M_COUNT] = {
    /*M_FLAT*/     0.0f,
    /*M_CLIMB*/    0.0f,   // top hat: exactly-1/lap count rule
    /*M_DROP*/    13.0f,
    /*M_HILLS*/   15.0f,
    /*M_TURN*/    14.0f,
    /*M_LOOP*/     4.0f,
    /*M_ROLL*/     2.5f,
    /*M_STATION*/  0.0f,
    /*M_DIP*/      3.0f,
    /*M_LAUNCH*/   0.0f,
    /*M_HELIX*/    4.0f,
    /*M_BOOST*/    0.0f,
    /*M_IMMEL*/   12.0f,
    /*M_SCURVE*/   8.0f,
    /*M_DIVE*/     4.0f,
    /*M_BANKAIR*/  6.0f,
    /*M_WAVE*/     4.0f,
    /*M_STALL*/    3.0f,
    /*M_DIVELOOP*/ 3.0f,
};

// Lap pacing by TIME (~130 s/lap): the lap closes at its ride-second budget
// rather than a feature count.  Backstops keep a pathological corridor from
// running an unbounded lap (hard elems cap; +45 s launch-postpone window).
// A full lap closes AT this budget, but hostile-terrain laps that spend their
// escape budget force-launch early (30-85 s); centring the normal lap a little
// above the 120 s midpoint keeps the census mean inside the [105,135] band
// once those unavoidable short laps are averaged in.
inline constexpr float TARGET_LAP_SECONDS       = 120.0f;
inline constexpr int   LAP_HARD_ELEM_CAP        = 44;
inline constexpr float LAP_POSTPONE_SECONDS     = 45.0f;

// Duration realism (approved 0.9-1.0x spec): clean-room estimate of each
// element's real ride duration in seconds (per lobe for HILLS, per rev for
// ROLL/corkscrew).  0 == truly unknown -> skip the duration bias for it.
// Consumed as a SOFT size/lambda preference in the builders, never a hard
// reject (which could strand completion).
inline constexpr float REAL_ELEMENT_SECONDS[M_COUNT] = {
    /*M_FLAT*/     0.0f,
    /*M_CLIMB*/    9.0f,   // top hat profile
    /*M_DROP*/     6.0f,
    /*M_HILLS*/    5.0f,   // per lobe
    /*M_TURN*/     5.5f,
    /*M_LOOP*/     4.5f,
    /*M_ROLL*/     2.8f,   // per revolution
    /*M_STATION*/  0.0f,
    /*M_DIP*/      4.0f,
    /*M_LAUNCH*/   0.0f,
    /*M_HELIX*/    8.0f,
    /*M_BOOST*/    0.0f,
    /*M_IMMEL*/    5.0f,
    /*M_SCURVE*/   5.0f,
    /*M_DIVE*/     0.0f,   // unknown -> skip
    /*M_BANKAIR*/  4.0f,
    /*M_WAVE*/     5.0f,
    /*M_STALL*/    3.5f,
    /*M_DIVELOOP*/ 5.0f,
};
inline constexpr float REAL_DURATION_BIAS_LO = 0.9f;
inline constexpr float REAL_DURATION_BIAS_HI = 1.0f;

// Act themes: each lap is one composed act with a rotating theme that biases
// shares INSIDE their bands (weights, never gates).  Multipliers are bounded
// [0.7,1.4] so a theme can never push a share out of band.
enum class ActTheme : unsigned char { MOUNTAIN, CANYON, WATER, CLASSIC };
inline constexpr int   ACT_THEME_COUNT = 4;
inline constexpr float ACT_THEME_MULT_LO = 0.7f;
inline constexpr float ACT_THEME_MULT_HI = 1.4f;
// Distance (m) ahead a lap probes for water before choosing the WATER theme.
inline constexpr float ACT_WATER_PROBE_DIST = 600.0f;

} // namespace genc
