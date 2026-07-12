#pragma once
// Shared scalar constants for the current V1 host adapters. V2 should centralize its own
// configuration rather than extending this header. Water level and up-vector are host-specific.
static const float SEG_LEN   = 14.0f;
static const float BUILD_MAX  = 430.0f;
static const float GRAV      = 9.81f;

static float       DRAG      = 0.00028f;
static const float FRICTION  = 0.015f;
static const float CHAIN_V   = 22.0f;
static const float MIN_V     = 42.0f;
static const float MAX_V     = 82.0f;
static const float CLIMB_V   = 27.0f;
static const float V_GUARD   =  6.0f;

// Launch pacing is scaled from measured real launch-coaster profiles. Formula
// Rossa's hydraulic launch reaches 240 km/h in 4.9 s; Red Force's LSM reaches
// 180 km/h in 5.0 s. Applying the same 1.5x multiplier to speed and net
// acceleration preserves their real transit times while raising the game's
// energy scale. Falcon's Flight's 150 km/h cliff LSM uses the same speed scale.
static constexpr float LAUNCH_SPEED_MUL = 1.50f;
static constexpr float LAUNCH_ACCEL_MUL = 1.50f;

static constexpr float HYDRAULIC_REF_V     = 240.0f / 3.6f;
static constexpr float HYDRAULIC_REF_TIME  = 4.90f;
static constexpr float HYDRAULIC_REF_ACCEL = HYDRAULIC_REF_V / HYDRAULIC_REF_TIME;
static constexpr float LAUNCH_V             = HYDRAULIC_REF_V * LAUNCH_SPEED_MUL;
static constexpr float LAUNCH_ACCEL         = HYDRAULIC_REF_ACCEL * LAUNCH_ACCEL_MUL;

static constexpr float LSM_REF_V       = 180.0f / 3.6f;
static constexpr float LSM_REF_TIME    = 5.00f;
static constexpr float LSM_REF_ACCEL   = LSM_REF_V / LSM_REF_TIME;
static constexpr float BOOST_V         = LSM_REF_V * LAUNCH_SPEED_MUL;
static constexpr float BOOST_ACCEL     = LSM_REF_ACCEL * LAUNCH_ACCEL_MUL;
static constexpr float CLIFF_LSM_V     = (150.0f / 3.6f) * LAUNCH_SPEED_MUL;
static float           BOOST_TRIG      = 58.0f;
