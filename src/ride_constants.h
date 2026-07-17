#pragma once
// Shared scalar constants for the current V1 host adapters. V2 should centralize its own
// configuration rather than extending this header. Water level and up-vector are host-specific.
static const float SEG_LEN   = 14.0f;
static const float BUILD_MAX  = 430.0f;
static const float GRAV      = 9.81f;

// Calibrated against the 64-seed live integrator: powered peaks remain
// 360 km/h while the full-layout mean settles near the requested 240 km/h.
static float       DRAG      = 0.00040f;
static const float FRICTION  = 0.015f;
static const float CHAIN_V   = 22.0f;
static const float MIN_V     = 42.0f;
static const float MAX_V     = 82.0f;
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

static constexpr float FASTEST_ACCEL_REF_V    = 180.0f / 3.6f;
static constexpr float FASTEST_ACCEL_REF_TIME = 1.56f;
static constexpr float FASTEST_ACCEL_REF      = FASTEST_ACCEL_REF_V / FASTEST_ACCEL_REF_TIME;
static constexpr PropulsionSpec V1_PROPULSION{
    360.0f/3.6f, FASTEST_ACCEL_REF, 1.50f, FASTEST_ACCEL_REF*1.50f,
    70.0f, 2000.0f, 42.0f
};
// The normal in-course propulsion cadence is 2 km.  This reserve is only a
// genuine anti-stall backstop: at the current drag law a flat 360 km/h arc
// reaches roughly 42 m/s at 2.1 km, so a higher trigger would always pre-empt
// the physical cadence and turn every booster into an "emergency" section.
static float BOOST_TRIG = V1_PROPULSION.operatingReserve;
