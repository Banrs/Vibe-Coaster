#pragma once
// Shared scalar constants for the current V1 host adapters. V2 should centralize its own
// configuration rather than extending this header. Water level and up-vector are host-specific.
static const float SEG_LEN   = 14.0f;
static const float BUILD_MAX  = 430.0f;
static const float GRAV      = 9.81f;

// 0.9x-of-record law (user, 2026-07-21): specific drag = 0.9x the most-
// advanced real value.  Physical envelope 0.5*rho*Cd*A/m with rho 1.225,
// Cd 0.8 (streamlined open train, low end of the published 0.8-1.2 band),
// A 3 m^2 (low end of 3-5 m^2; matches our slim train), laden m 9500 kg
// (~750 kg/seat-equivalent x 14, heavy end) -> 0.000155 /m record-best;
// x0.9 = 0.00014 (docs/REAL_WORLD_REFERENCES.md drag row).
static float       DRAG      = 0.00014f;
// Realism calibration 2026-07-20 (docs/REAL_WORLD_REFERENCES.md 7): rolling
// resistance = C_rr * g with record-class polyurethane-on-steel C_rr ~ 0.010
// -> ~0.10 m/s^2. The old 0.015 was ~7x below physical rolling resistance
// (uncited). 0.9x-of-record law (user, 2026-07-21): 0.9 x (C_rr 0.010 x g)
// = 0.088 m/s^2 (docs/REAL_WORLD_REFERENCES.md 7).
static const float FRICTION  = 0.088f;
// Realism calibration 2026-07-20: real chain lifts run 1.8-4.5 m/s (fastest
// ~4 m/s); 1.5x record -> 6 m/s. The old 22 m/s was uncited fiction. ch=1 is
// not yet emitted by generation, so this only shapes the upcoming cliff-dive
// crest crawl (docs/REAL_WORLD_REFERENCES.md 8).
static const float CHAIN_V   = 6.0f;
static const float MIN_V     = 42.0f;
// Camera-FX / size-draw speed anchor only -- NOT a physics clamp (verified: the
// ride integrator never clamps to MAX_V; it feeds only camera FX scaling in
// src/main.cpp and mirrors the size-draw speed anchor genc::SIZE_SPEED_HI_MPS).
// 89 m/s is the upper ordinary authored-element entry band used by the
// camera/size calibration. The physical station launch can briefly reach
// 100 m/s; the normal in-course booster is 69.4 m/s.
static const float MAX_V     = 89.0f;
static const float V_GUARD   =  6.0f;

// Launch pacing uses the fastest recorded coaster acceleration as its baseline:
// Do-Dodonpa reached 180 km/h in 1.56 s. V1 uses 1.5x that average net
// acceleration and a 360 km/h target, producing 0-360 km/h in about 2.08 s.
// Every powered launch type converges on that common target; grade and rolling
// entry speed determine the time and distance each one needs.
struct PropulsionSpec {
    float targetSpeed;
    float referenceAcceleration;
    float accelerationMultiplier;
    float netAcceleration;
    float minimumSectionLength;
    float nominalCadence;
    float operatingReserve;
};

// Roll-speed ceiling for banking transitions, in felt degrees per second.
// No manufacturer publishes a number (verified 2026-07-19); FVD++/NL2
// practice treats roll speed as the primary hand-tuned curve. Smooth modern
// steel transitions land roughly 40-70 deg/s; this project runs ~2x real
// intensity, so 110 deg/s is the design ceiling. Tunable estimate, validated
// against the (2x-scaled) ASTM lateral envelope rather than a cited spec.
static constexpr float ROLL_RATE_DEG_PER_SEC = 110.0f;

static constexpr float FASTEST_ACCEL_REF_V    = 180.0f / 3.6f;
static constexpr float FASTEST_ACCEL_REF_TIME = 1.56f;
static constexpr float FASTEST_ACCEL_REF      = FASTEST_ACCEL_REF_V / FASTEST_ACCEL_REF_TIME;
static constexpr PropulsionSpec V1_PROPULSION{
    360.0f/3.6f, FASTEST_ACCEL_REF, 1.50f, FASTEST_ACCEL_REF*1.50f,
    70.0f, 1800.0f, 42.0f
};
// In-course boosters re-cruise, they do not re-launch: only the station launch
// reaches the project's 360 km/h record-scale peak.
// That real coaster uses its launches to enter long hills and drawn-out curves;
// 250 km/h lands directly in this generator's record-scale HILLS/LOOP windows,
// avoiding a synthetic 320 km/h eligibility desert and the resulting TURN
// monopoly. No trim brake is introduced: speed still decays only through
// gravity, drag and friction.
static constexpr float BOOST_CRUISE_TARGET = 250.0f / 3.6f;
// The normal in-course propulsion cadence is 2.1 km. At 250 km/h the booster
// restores Falcon-scale cruise without placing the track above the airtime and
// inversion entry windows. This reserve remains a genuine anti-stall backstop:
// a higher trigger would pre-empt the physical cadence and turn every booster
// into an emergency section.
// AVG-FLOOR calibration (2026-07-24, 7 configs measured): cadence 2100->1800
// is the one clean average gain (232->239 km/h); trigger raises (46/52) and
// plateau raises (255/260) either did nothing or tripped reshuffles onto
// chain-crawl/stall seeds.  The HILLS supply the shorter cadence trims is
// recovered by widening the hills window bottom (HILL_ENTRY_MIN 48->46,
// gen_constants.h) so the remaining slow-tail meters become floater-hill
// anchors instead of dead track.
static float BOOST_TRIG = V1_PROPULSION.operatingReserve;
