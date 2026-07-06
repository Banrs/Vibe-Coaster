#pragma once
// Scalar physics/sizing constants shared by BOTH hosts (OpenGL opengl/src/main.cpp +
// Vulkan vulkan/src/GameCompat.h) because they FEED the shared generator (coaster_track.cpp).
// A stale hand-kept mirror once built a genuinely DIFFERENT ride on Vulkan (BOOST_TRIG 48 vs 84
// -> different inversion/re-power windows), not just a differently-tuned one, so they now live in
// this one header included by both. NOTE: WATER_Y and WUP deliberately stay per-host -- WATER_Y is
// WORLD-DEPENDENT (opengl world sea=30, vulkan=64; see GameCompat.h Fix 1) and WUP needs each
// host's own Vector3 type. `static` linkage kept as-is: every consumer is a single-TU build.
static const float SEG_LEN   = 14.0f;
static const float BUILD_MAX  = 430.0f;
static const float GRAV      = 9.81f;

static float       DRAG      = 0.00028f;  // realistic aero drag: ~1.8 m/s^2 at 80 m/s (a ~10t train, ~5 m^2, Cd~0.7)
static const float FRICTION  = 0.015f;    // steel-on-steel rolling resistance: Crr~0.0015 * g ~= 0.015 m/s^2 constant decel; air DRAG dominates speed bleed at ride speed
static const float CHAIN_V   = 22.0f;
static const float MIN_V     = 42.0f;
static const float MAX_V     = 82.0f;
static const float LAUNCH_V  = 108.0f;  // asymptote ~389 km/h; drag-limited TOP speed ~350 km/h by physics (no cap).
static const float CLIMB_V   = 27.0f;   // crest speed off a lift/top-hat (~97 km/h): the drop supplies the speed, not the lift. Raised from 22 so the long rounded crowns never dip under the 26 m/s crawl threshold.
// Speed is fully physics-driven: no re-power floor and no top cap. Speed is whatever launch
// thrust + gravity + friction/drag produce; low points may occasionally dip into a real stall.
// Only V_GUARD remains, a pure numeric floor so du/dt stays finite.
static const float V_GUARD   =  6.0f;    // numeric-only floor (prevents v<=0 -> NaN du)
static float       BOOST_V   = 62.0f;
// Ambient re-power threshold: below this speed the ride considers itself "run down" and
// re-launches/re-boosts (uniformly, regardless of what element comes next -- this is pure
// pacing, not an inversion-reactive brake). Kept low enough that genV can coast down through
// an inversion's eligible speed window before the ride re-powers.
static float       BOOST_TRIG = 84.0f;   // re-power below ~302 km/h: holds the ride average near ~265-270 km/h now that the slow windows are shared with the entry-gated inversions (nextMode's wantBoost hook) and boosts wait for the ground-hug drop first.
