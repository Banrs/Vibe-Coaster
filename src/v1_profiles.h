#pragma once

// Analytic longitudinal profiles for the V1 coaster generator.
//
// The independent variable is plan-view distance along the route (the same
// distance advanced by SEG_LEN in coaster_track.cpp), not three-dimensional
// rail arc length.  Every authored join carries height, grade and vertical
// curvature.  The convenience profiles below are C2 at their internal joins
// (the top-hat feet additionally have zero jerk), so they are sampled directly
// into finalized control points; a second smoothing pass would only distort
// their boundary conditions.

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstddef>

namespace v1profile {

constexpr double kPi = 3.14159265358979323846264338327950288;
constexpr double kDegreesToRadians = kPi / 180.0;
constexpr double kRadiansToDegrees = 180.0 / kPi;
constexpr double kTopHatMinFaceDegrees = 60.0;
constexpr double kTopHatMaxFaceDegrees = 65.0;
constexpr double kTopHatReferenceRise = 165.0;
constexpr double kTopHatReferenceFaceDegrees = 64.25;
constexpr double kTopHatMaximumUnitSlope = 5.210821945572;
constexpr double kTopHatMaximumSlopeU = 0.2893314096;
// Canonical 165 m / 64.25 degree dimensions. Every generated hat is a scaled
// instance of this law, so footprint, rail length and radius share one scale
// contract instead of depending on separately rounded copies.
constexpr double kTopHatReferencePlanLength = 414.71135295802475;
constexpr double kTopHatReferenceRailLength = 569.2931108803162;
constexpr double kTopHatReferenceCrownRadius = 72.03308270020875;
constexpr double kTopHatReferenceTightCrestRadius = 71.396248485;
constexpr double kTopHatReferencePullupRadius = 96.721269472;
constexpr std::size_t kMaxSegments = 8;
constexpr std::size_t kMaxChainHills = 4;
constexpr double kCamelbackValleyCurvatureRatio = 0.45;

// Height on either half of the top hat is one degree-20 Bernstein polynomial
// in s=(2u-1)^2.  The non-increasing coefficients make the profile monotone
// from either foot to the crown, while the five trailing zeroes give each
// foot zero grade, curvature and jerk.  Unlike face/crown/face construction,
// this law has no internal seam or constant-pitch interval.
constexpr std::array<double, 21> kTopHatHeightBernstein{{
    1.0,
    0.909560964683043,
    0.787706264466512,
    0.787706264466512,
    0.244138729186889,
    0.244138729186889,
    0.169398193085941,
    0.169398193085941,
    0.169398193085941,
    0.0492794743522736,
    0.0492794743522736,
    0.0492794743522736,
    0.0492794743522736,
    0.00746658702307168,
    0.00746658702307168,
    0.00746658702307168,
    0.0, 0.0, 0.0, 0.0, 0.0
}};

inline double clamp01(double value) {
    return std::max(0.0, std::min(1.0, value));
}

inline bool finite(double value) {
    return std::isfinite(value);
}

// Evaluate a finite difference of a Bernstein polynomial in O(degree).  The
// basis is walked from the better-conditioned endpoint, avoiding both the
// large alternating power-basis coefficients and an O(n^2) de Casteljau pass.
inline double bernsteinDifference(int differenceOrder, double x) {
    assert(differenceOrder >= 0 && differenceOrder <= 3);
    x = clamp01(x);
    const int degree = 20 - differenceOrder;
    auto coefficient = [differenceOrder](int i) {
        const auto &d = kTopHatHeightBernstein;
        if (differenceOrder == 0) return d[static_cast<std::size_t>(i)];
        if (differenceOrder == 1)
            return d[static_cast<std::size_t>(i + 1)] -
                   d[static_cast<std::size_t>(i)];
        if (differenceOrder == 2)
            return d[static_cast<std::size_t>(i + 2)] -
                   2.0*d[static_cast<std::size_t>(i + 1)] +
                   d[static_cast<std::size_t>(i)];
        return d[static_cast<std::size_t>(i + 3)] -
               3.0*d[static_cast<std::size_t>(i + 2)] +
               3.0*d[static_cast<std::size_t>(i + 1)] -
               d[static_cast<std::size_t>(i)];
    };

    if (x <= 0.0) return coefficient(0);
    if (x >= 1.0) return coefficient(degree);

    const double oneMinusX = 1.0 - x;
    double sum = 0.0;
    if (x <= 0.5) {
        double basis = std::pow(oneMinusX, degree);
        for (int i = 0; i <= degree; ++i) {
            sum += coefficient(i) * basis;
            if (i < degree)
                basis *= (static_cast<double>(degree - i) / (i + 1)) *
                         (x / oneMinusX);
        }
    } else {
        double basis = std::pow(x, degree);
        for (int i = degree; i >= 0; --i) {
            sum += coefficient(i) * basis;
            if (i > 0)
                basis *= (static_cast<double>(i) / (degree - i + 1)) *
                         (oneMinusX / x);
        }
    }
    return sum;
}

struct Boundary {
    double height = 0.0;       // y
    double grade = 0.0;        // dy / ds
    double curvature = 0.0;    // d2y / ds2
};

struct Sample : Boundary {
    double jerk = 0.0;         // d3y / ds3

    double pitchRadians() const { return std::atan(grade); }
    double pitchDegrees() const { return pitchRadians() * kRadiansToDegrees; }
};

inline bool near(double a, double b, double tolerance) {
    return std::abs(a - b) <= tolerance * (1.0 + std::max(std::abs(a), std::abs(b)));
}

inline bool nearBoundary(const Boundary& a, const Boundary& b,
                         double tolerance = 1.0e-9) {
    return near(a.height, b.height, tolerance) &&
           near(a.grade, b.grade, tolerance) &&
           near(a.curvature, b.curvature, tolerance);
}

inline bool finiteBoundary(const Boundary& boundary) {
    return finite(boundary.height) && finite(boundary.grade) &&
           finite(boundary.curvature);
}

// A segment is either a polynomial boundary solve or the single analytic
// top-hat law. Coefficients are in height units; physical derivatives apply
// powers of 1/length.
struct Segment {
    static constexpr int kDegree = 15;
    enum class Kind : unsigned char { Quintic, TopHat };

    Kind kind = Kind::Quintic;
    double length = 0.0;
    std::array<double, kDegree + 1> coefficient{};
    double topHatStartHeight = 0.0;
    double topHatRise = 0.0;          // ascent rise = crest - startHeight
    // Phase 5X (asymmetric top hat): the exit foot may descend past the entry
    // foot to a terrain-following hand-off.  The ascent half and the descent
    // half each remain one mirror-symmetric Bernstein leg; only the descent
    // face is steepened so the *crest curvature* (crown radius) is unchanged --
    // "the same g-law run longer, not tighter".  topHatEndHeight == startHeight
    // and topHatCrestFraction == 0.5 recover the symmetric law byte-for-byte.
    double topHatEndHeight = 0.0;     // exit foot height (== startHeight if symmetric)
    double topHatDescentRise = 0.0;   // descent rise = crest - endHeight
    double topHatCrestFraction = 0.5; // lenUp / (lenUp + lenDown)

    static Segment topHat(double startHeight, double crestHeight,
                          double maximumPitch) {
        return topHatAsymmetric(startHeight, crestHeight, startHeight,
                                maximumPitch);
    }

    // Ascent leg reaches maximumPitch; the descent leg reaches
    // atan(tan(maximumPitch) * sqrt(riseDown/riseUp)) so that the physical
    // crest curvature matches on both sides, giving an internally C2/C3 crown.
    static Segment topHatAsymmetric(double startHeight, double crestHeight,
                                    double endHeight, double maximumPitch) {
        Segment result;
        result.kind = Kind::TopHat;
        result.topHatStartHeight = startHeight;
        result.topHatEndHeight = endHeight;
        const double riseUp = crestHeight - startHeight;
        const double riseDown = crestHeight - endHeight;
        result.topHatRise = riseUp;
        result.topHatDescentRise = riseDown;
        const double tanUp = std::tan(maximumPitch);
        // lenUp: half the symmetric plan length for riseUp.  lenDown: derived
        // from the curvature-matching face so lenDown = 0.5*sqrt(riseUp*riseDown)
        // * kUnitSlope / tanUp (= 0.5*riseDown*kUnitSlope/tan(pitchDown)).
        const double lenUp = 0.5 * riseUp * kTopHatMaximumUnitSlope / tanUp;
        const double lenDown = 0.5 * std::sqrt(riseUp * riseDown) *
                               kTopHatMaximumUnitSlope / tanUp;
        result.length = lenUp + lenDown;
        result.topHatCrestFraction = (result.length > 0.0)
            ? lenUp / result.length : 0.5;
        return result;
    }

    // General quintic Hermite segment.  The supplied states are in physical
    // distance units, so position, grade and curvature are explicit at both
    // boundaries.  Adjacent segments sharing a Boundary are exactly C2.
    static Segment quintic(const Boundary& begin, const Boundary& end,
                           double segmentLength) {
        assert(segmentLength > 0.0);
        Segment result;
        result.length = segmentLength;

        const double l2 = segmentLength * segmentLength;
        const double v0 = begin.grade * segmentLength;
        const double v1 = end.grade * segmentLength;
        const double a0 = begin.curvature * l2;
        const double a1 = end.curvature * l2;

        result.coefficient[0] = begin.height;
        result.coefficient[1] = v0;
        result.coefficient[2] = 0.5 * a0;

        const double positionRemainder =
            end.height - result.coefficient[0] - result.coefficient[1] -
            result.coefficient[2];
        const double gradeRemainder =
            v1 - result.coefficient[1] - 2.0 * result.coefficient[2];
        const double curvatureRemainder = a1 - 2.0 * result.coefficient[2];

        result.coefficient[3] = 10.0 * positionRemainder -
                                4.0 * gradeRemainder +
                                0.5 * curvatureRemainder;
        result.coefficient[4] = -15.0 * positionRemainder +
                                7.0 * gradeRemainder -
                                curvatureRemainder;
        result.coefficient[5] = 6.0 * positionRemainder -
                                3.0 * gradeRemainder +
                                0.5 * curvatureRemainder;
        return result;
    }

    // Integrate a bounded Bernstein curvature law from trough to crown, or its
    // exact mirror. Two equal controls at the trough and four -1 controls at
    // the crown make jerk zero at both extrema and keep the negative-G crown
    // broad enough to be sustained rather than a single sampled peak. The
    // eight intervening controls share exactly the positive curvature needed
    // for zero total curvature. Bernstein's convex-hull property guarantees
    // no positive or negative curvature overshoot.
    static Segment camelbackHalf(const Boundary& begin, const Boundary& end,
                                 double segmentLength, bool crownAtEnd) {
        const Boundary& crown = crownAtEnd ? end : begin;
        const Boundary& trough = crownAtEnd ? begin : end;
        const double crownCurvature = -crown.curvature;
        const double ratio = trough.curvature / crownCurvature;
        assert(crownCurvature > 0.0 && ratio >= 0.0 && ratio < 1.0);
        assert(near(begin.grade, 0.0, 1.0e-10) &&
               near(end.grade, 0.0, 1.0e-10));

        Segment result;
        result.length = segmentLength;
        result.coefficient[0] = begin.height;
        const double scale = crownCurvature * segmentLength * segmentLength;
        constexpr int curvatureDegree = 13;
        std::array<double, curvatureDegree + 1> ascentControl{};
        ascentControl[0] = ascentControl[1] = ratio;
        const double compensation = (4.0 - 2.0 * ratio) / 8.0;
        for (int i = 2; i <= 9; ++i) ascentControl[i] = compensation;
        for (int i = 10; i <= curvatureDegree; ++i) ascentControl[i] = -1.0;

        auto choose = [](int n, int k) {
            int value = 1;
            for (int i = 1; i <= k; ++i) value = value * (n - i + 1) / i;
            return value;
        };
        for (int power = 0; power <= curvatureDegree; ++power) {
            double difference = 0.0;
            for (int i = 0; i <= power; ++i) {
                const int controlIndex = crownAtEnd ? i : curvatureDegree - i;
                const double sign = ((power - i) & 1) ? -1.0 : 1.0;
                difference += sign * choose(power, i) * ascentControl[controlIndex];
            }
            const double curvaturePower =
                choose(curvatureDegree, power) * difference;
            result.coefficient[power + 2] = scale * curvaturePower /
                static_cast<double>((power + 1) * (power + 2));
        }
        return result;
    }

    double derivativeNormalized(double u, int order) const {
        assert(order >= 0 && order <= 3);
        u = clamp01(u);
        if (kind == Kind::TopHat) {
            // Map the whole-segment parameter u onto one mirror-symmetric leg.
            // Ascent (u<=f): the [0,0.5] half of a symmetric top hat of rise
            // riseUp; descent (u>f): the [0.5,1] half of one of rise riseDown.
            // The chain-rule factor `scale = duSym/du` converts leg-local
            // derivatives back to whole-segment ones; physical derivatives then
            // divide by the total length in sampleNormalized as usual.
            const double f = topHatCrestFraction;
            double uSym, baseHeight, rise, scale;
            if (u <= f) {
                uSym  = (f > 0.0) ? 0.5 * (u / f) : 0.0;
                baseHeight = topHatStartHeight;
                rise  = topHatRise;
                scale = (f > 0.0) ? 0.5 / f : 1.0;
            } else {
                uSym  = 0.5 + 0.5 * ((u - f) / (1.0 - f));
                baseHeight = topHatEndHeight;
                rise  = topHatDescentRise;
                scale = 0.5 / (1.0 - f);
            }
            const double t = 2.0*uSym - 1.0;
            const double s = t*t;
            if (order == 0)
                return baseHeight + rise*bernsteinDifference(0, s);
            const double first = 20.0*bernsteinDifference(1, s);
            if (order == 1) return rise*4.0*t*first * scale;
            const double second = 20.0*19.0*bernsteinDifference(2, s);
            if (order == 2)
                return rise*(8.0*first + 16.0*s*second) * (scale*scale);
            const double third = 20.0*19.0*18.0*bernsteinDifference(3, s);
            return rise*32.0*t*(3.0*second + 2.0*s*third) * (scale*scale*scale);
        }
        double result = 0.0;
        for (int index = kDegree; index >= order; --index) {
            double factor = 1.0;
            for (int derivative = 0; derivative < order; ++derivative)
                factor *= static_cast<double>(index - derivative);
            result = result * u + coefficient[static_cast<std::size_t>(index)] * factor;
        }
        return result;
    }

    Sample sampleNormalized(double u) const {
        assert(length > 0.0);
        const double inverseLength = 1.0 / length;
        const double inverseLength2 = inverseLength * inverseLength;
        return {{derivativeNormalized(u, 0),
                 derivativeNormalized(u, 1) * inverseLength,
                 derivativeNormalized(u, 2) * inverseLength2},
                derivativeNormalized(u, 3) * inverseLength2 * inverseLength};
    }

    Sample sampleDistance(double localDistance) const {
        return sampleNormalized(localDistance / length);
    }

    Boundary begin() const {
        const Sample sample = sampleNormalized(0.0);
        return {sample.height, sample.grade, sample.curvature};
    }

    Boundary end() const {
        const Sample sample = sampleNormalized(1.0);
        return {sample.height, sample.grade, sample.curvature};
    }
};

// Fixed-capacity storage keeps construction allocation-free and sampling
// predictable. The largest built-in shape (four hills) uses eight segments.
class Profile {
public:
    bool append(const Segment& segment) {
        if (segmentCount_ >= segment_.size() || !(segment.length > 0.0) ||
            !finite(segment.length))
            return false;
        if (segment.kind == Segment::Kind::TopHat &&
            (!finite(segment.topHatStartHeight) ||
             !finite(segment.topHatRise) || !(segment.topHatRise > 0.0) ||
             !finite(segment.topHatEndHeight) ||
             !finite(segment.topHatDescentRise) ||
             !(segment.topHatDescentRise > 0.0) ||
             !(segment.topHatCrestFraction > 0.0) ||
             !(segment.topHatCrestFraction < 1.0)))
            return false;
        for (double coefficient : segment.coefficient)
            if (!finite(coefficient)) return false;
        segment_[segmentCount_++] = segment;
        totalLength_ += segment.length;
        return true;
    }

    bool empty() const { return segmentCount_ == 0; }
    std::size_t segmentCount() const { return segmentCount_; }
    double length() const { return totalLength_; }

    const Segment& segment(std::size_t index) const {
        assert(index < segmentCount_);
        return segment_[index];
    }

    Sample sampleDistance(double distance) const {
        if (empty()) return {};
        distance = std::max(0.0, std::min(totalLength_, distance));
        for (std::size_t i = 0; i < segmentCount_; ++i) {
            const bool last = i + 1 == segmentCount_;
            if (distance <= segment_[i].length || last)
                return segment_[i].sampleDistance(distance);
            distance -= segment_[i].length;
        }
        return segment_[segmentCount_ - 1].sampleNormalized(1.0);
    }

    double heightDistance(double distance) const {
        return sampleDistance(distance).height;
    }

    Boundary begin() const {
        if (empty()) return {};
        return segment_[0].begin();
    }

    Boundary end() const {
        if (empty()) return {};
        return segment_[segmentCount_ - 1].end();
    }

private:
    std::array<Segment, kMaxSegments> segment_{};
    std::size_t segmentCount_ = 0;
    double totalLength_ = 0.0;
};

// Convert the profile's plan-distance parameter into physical centreline
// length. A fixed Simpson rule is deterministic, allocation-free, and more
// than sufficient for the low-degree laws used by V1.
inline double railArcLength(const Profile& profile, double beginDistance,
                            double endDistance, int intervals = 128) {
    if (profile.empty()) return 0.0;
    beginDistance = std::max(0.0, std::min(profile.length(), beginDistance));
    endDistance = std::max(beginDistance, std::min(profile.length(), endDistance));
    if (!(endDistance > beginDistance)) return 0.0;
    intervals = std::max(2, intervals + (intervals & 1));
    const double step = (endDistance - beginDistance) / intervals;
    double sum = 0.0;
    for (int i = 0; i <= intervals; ++i) {
        const double grade = profile.sampleDistance(beginDistance + step*i).grade;
        const double weight = (i == 0 || i == intervals) ? 1.0 : (i & 1 ? 4.0 : 2.0);
        sum += weight * std::sqrt(1.0 + grade*grade);
    }
    return sum * step / 3.0;
}

inline double railArcLength(const Profile& profile, int intervals = 128) {
    return railArcLength(profile, 0.0, profile.length(), intervals);
}

// Small stateful composer for custom V1 profiles.  It refuses discontinuous
// appends rather than relying on a later spline pass to hide them.
class ProfileBuilder {
public:
    explicit ProfileBuilder(Boundary initial = {}) : cursor_(initial) {}

    bool good() const { return good_; }
    const Profile& profile() const { return profile_; }

    bool appendQuintic(const Boundary& end, double segmentLength) {
        if (!good_ || !(segmentLength > 0.0) || !finite(segmentLength) ||
            !finiteBoundary(cursor_) || !finiteBoundary(end))
            return fail();
        return appendChecked(Segment::quintic(cursor_, end, segmentLength));
    }

    bool appendCamelbackHalf(const Boundary& end, double segmentLength,
                             bool crownAtEnd) {
        if (!good_ || !(segmentLength > 0.0) || !finite(segmentLength) ||
            !finiteBoundary(cursor_) || !finiteBoundary(end))
            return fail();
        return appendChecked(Segment::camelbackHalf(
            cursor_, end, segmentLength, crownAtEnd));
    }

private:
    bool fail() {
        good_ = false;
        return false;
    }

    bool appendChecked(const Segment& segment) {
        if (!(segment.length > 0.0) || !finite(segment.length) ||
            !nearBoundary(cursor_, segment.begin(), 1.0e-8) ||
            !profile_.append(segment))
            return fail();
        cursor_ = segment.end();
        return true;
    }

    Profile profile_{};
    Boundary cursor_{};
    bool good_ = true;
};

struct ContinuityMetrics {
    double maximumHeightJump = 0.0;
    double maximumGradeJump = 0.0;
    double maximumCurvatureJump = 0.0;

    bool isC2(double tolerance = 1.0e-8) const {
        return maximumHeightJump <= tolerance &&
               maximumGradeJump <= tolerance &&
               maximumCurvatureJump <= tolerance;
    }
};

inline ContinuityMetrics continuityMetrics(const Profile& profile) {
    ContinuityMetrics result;
    for (std::size_t i = 1; i < profile.segmentCount(); ++i) {
        const Boundary left = profile.segment(i - 1).end();
        const Boundary right = profile.segment(i).begin();
        const double heightJump = std::abs(left.height - right.height);
        const double gradeJump = std::abs(left.grade - right.grade);
        const double curvatureJump = std::abs(left.curvature - right.curvature);
        result.maximumHeightJump = std::max(result.maximumHeightJump, heightJump);
        result.maximumGradeJump = std::max(result.maximumGradeJump, gradeJump);
        result.maximumCurvatureJump =
            std::max(result.maximumCurvatureJump, curvatureJump);
    }
    return result;
}

struct ShapeMetrics {
    double maximumAbsoluteGrade = 0.0;
    std::size_t localMaxima = 0;
    std::size_t localMinima = 0;

    double maximumPitchDegrees() const {
        return std::atan(maximumAbsoluteGrade) * kRadiansToDegrees;
    }
};

inline ShapeMetrics shapeMetrics(const Profile& profile,
                                 std::size_t samplesPerSegment = 32) {
    ShapeMetrics result;
    if (profile.empty()) return result;
    samplesPerSegment = std::max<std::size_t>(samplesPerSegment, 4);
    int previousGradeSign = 0;
    for (std::size_t segmentIndex = 0;
         segmentIndex < profile.segmentCount(); ++segmentIndex) {
        for (std::size_t sampleIndex = 0; sampleIndex <= samplesPerSegment;
             ++sampleIndex) {
            if (segmentIndex > 0 && sampleIndex == 0) continue;
            const Sample sample = profile.segment(segmentIndex).sampleNormalized(
                static_cast<double>(sampleIndex) /
                static_cast<double>(samplesPerSegment));
            result.maximumAbsoluteGrade =
                std::max(result.maximumAbsoluteGrade, std::abs(sample.grade));

            const int gradeSign = sample.grade > 1.0e-9 ? 1 :
                                  sample.grade < -1.0e-9 ? -1 : 0;
            if (gradeSign != 0) {
                if (previousGradeSign > 0 && gradeSign < 0) ++result.localMaxima;
                if (previousGradeSign < 0 && gradeSign > 0) ++result.localMinima;
                previousGradeSign = gradeSign;
            }
        }
    }
    return result;
}

inline void assertC2(const Profile& profile) {
#ifndef NDEBUG
    assert(!profile.empty());
    assert(continuityMetrics(profile).isC2());
#else
    (void)profile;
#endif
}

struct TopHatSpec {
    double startHeight = 0.0;
    double crestHeight = 250.0;
    double endHeight = 0.0;
    double faceDegrees = kTopHatReferenceFaceDegrees;
};

struct TopHatProfile {
    Profile profile{};
    TopHatSpec spec{};
    double apexDistance = 0.0;
    bool valid = false;

    explicit operator bool() const { return valid; }
};

inline TopHatProfile makeTopHat(const TopHatSpec& spec) {
    TopHatProfile result;
    result.spec = spec;

    const bool finiteInput = finite(spec.startHeight) && finite(spec.crestHeight) &&
                             finite(spec.endHeight) && finite(spec.faceDegrees);
    if (!finiteInput ||
        spec.faceDegrees < kTopHatMinFaceDegrees ||
        spec.faceDegrees > kTopHatMaxFaceDegrees)
        return result;

    const double ascentRise = spec.crestHeight - spec.startHeight;
    const double descentDrop = spec.crestHeight - spec.endHeight;
    if (!(ascentRise > 0.0) || !(descentDrop > 0.0)) return result;

    // Phase 5X: the exit foot may sit below the entry foot (endHeight <
    // startHeight); a raised exit is not a top hat and is rejected.
    if (spec.endHeight > spec.startHeight + 1.0e-9) return result;
    const double actualPitch = spec.faceDegrees * kDegreesToRadians;
    const Segment shaped = Segment::topHatAsymmetric(
        spec.startHeight, spec.crestHeight, spec.endHeight, actualPitch);
    const double length = shaped.length;
    if (!(length > 0.0) || !finite(length)) return result;

    if (!result.profile.append(shaped))
        return result;
    result.apexDistance = length * shaped.topHatCrestFraction;
    const Sample foot = result.profile.sampleDistance(0.0);
    // The ascent face reaches faceDegrees at the symmetric max-slope point,
    // which within the [0,f] ascent leg lands at u = f * (kSlopeU / 0.5).
    const Sample face = result.profile.sampleDistance(
        length * shaped.topHatCrestFraction * (kTopHatMaximumSlopeU / 0.5));
    const Sample apex = result.profile.sampleDistance(result.apexDistance);
    const Sample exitFoot = result.profile.sampleDistance(length);
    result.valid = near(foot.height, spec.startHeight, 1.0e-9) &&
                   near(foot.grade, 0.0, 1.0e-9) &&
                   near(foot.curvature, 0.0, 1.0e-9) &&
                   near(foot.jerk, 0.0, 1.0e-9) &&
                   near(face.pitchDegrees(), spec.faceDegrees, 1.0e-9) &&
                   near(apex.height, spec.crestHeight, 1.0e-9) &&
                   near(apex.grade, 0.0, 1.0e-9) && apex.curvature < 0.0 &&
                   near(exitFoot.height, spec.endHeight, 1.0e-9) &&
                   near(exitFoot.grade, 0.0, 1.0e-9) &&
                   near(exitFoot.curvature, 0.0, 1.0e-9);
    if (result.valid) assertC2(result.profile);
    return result;
}

struct HillChainSpec {
    std::size_t hillCount = 2;             // compact V1 chain: two or three
    double startHeight = 0.0;
    double terrainRise = 0.0;              // smooth baseline lift across a rising corridor
    double firstCrestRise = 28.0;
    double crestHeightDecay = 0.82;        // absolute crests descend each hop
    double troughDropPerHill = 3.0;
    double crownRadius = 30.625;             // metres; fixed geometry, never entry-speed prediction
};

struct HillChainProfile {
    Profile profile{};
    HillChainSpec spec{};
    std::array<double, kMaxChainHills> crestDistance{};
    std::array<double, kMaxChainHills> crestHeight{};
    std::array<double, kMaxChainHills> troughDistance{};
    std::array<double, kMaxChainHills> troughHeight{};
    bool valid = false;

    explicit operator bool() const { return valid; }
};

inline bool validateHillChain(const HillChainProfile& chain,
                              double tolerance = 1.0e-6) {
    if (chain.spec.hillCount < 1 || chain.spec.hillCount > kMaxChainHills ||
        chain.profile.empty() ||
        !continuityMetrics(chain.profile).isC2(tolerance))
        return false;

    const Boundary begin = chain.profile.begin();
    const Boundary end = chain.profile.end();
    const Sample beginSample = chain.profile.sampleDistance(0.0);
    const Sample endSample = chain.profile.sampleDistance(chain.profile.length());
    const double expectedEnd = chain.spec.startHeight -
                               chain.spec.troughDropPerHill *
                               static_cast<double>(chain.spec.hillCount) +
                               chain.spec.terrainRise;
    if (!near(begin.height, chain.spec.startHeight, tolerance) ||
        !near(begin.grade, 0.0, tolerance) ||
        !near(begin.curvature, 0.0, tolerance) ||
        !near(end.height, expectedEnd, tolerance) ||
        !near(end.grade, 0.0, tolerance) ||
        !near(end.curvature, 0.0, tolerance) ||
        !near(beginSample.jerk, 0.0, tolerance) ||
        !near(endSample.jerk, 0.0, tolerance))
        return false;

    for (std::size_t i = 0; i < chain.spec.hillCount; ++i) {
        const Sample crest = chain.profile.sampleDistance(chain.crestDistance[i]);
        if (!near(crest.height, chain.crestHeight[i], tolerance) ||
            !near(crest.grade, 0.0, tolerance) ||
            !near(crest.curvature, -1.0 / chain.spec.crownRadius, tolerance) ||
            !near(crest.jerk, 0.0, tolerance))
            return false;

        const Sample trough = chain.profile.sampleDistance(chain.troughDistance[i]);
        if (!near(trough.height, chain.troughHeight[i], tolerance) ||
            !near(trough.grade, 0.0, tolerance))
            return false;
        if (i + 1 < chain.spec.hillCount &&
            (!near(trough.curvature,
                   kCamelbackValleyCurvatureRatio / chain.spec.crownRadius,
                   tolerance) || !near(trough.jerk, 0.0, tolerance)))
            return false;
    }

    const ShapeMetrics shape = shapeMetrics(chain.profile);
    return shape.localMaxima == chain.spec.hillCount &&
           shape.localMinima == chain.spec.hillCount - 1;
}

inline HillChainProfile makeDescendingHillChain(const HillChainSpec& spec) {
    HillChainProfile result;
    result.spec = spec;

    const bool finiteInput = finite(spec.startHeight) && finite(spec.terrainRise) &&
                             finite(spec.firstCrestRise) &&
                             finite(spec.crestHeightDecay) &&
                             finite(spec.troughDropPerHill) &&
                             finite(spec.crownRadius);
    if (!finiteInput || spec.hillCount < 1 || spec.hillCount > kMaxChainHills ||
        !(spec.terrainRise >= 0.0) ||
        !(spec.firstCrestRise > 0.0) ||
        !(spec.crestHeightDecay > 0.0 && spec.crestHeightDecay < 1.0) ||
        !(spec.troughDropPerHill >= 0.0) ||
        !(spec.crownRadius > 0.0))
        return result;

    const std::size_t extremaCount = 2 * spec.hillCount + 1;
    std::array<double, 2 * kMaxChainHills + 1> height{};
    std::array<double, 2 * kMaxChainHills> span{};
    std::array<double, 2 * kMaxChainHills + 1> curvature{};
    height[0] = spec.startHeight;
    for (std::size_t i = 0; i < spec.hillCount; ++i) {
        double crestU = static_cast<double>(2 * i + 1) /
                        static_cast<double>(extremaCount - 1);
        double troughU = static_cast<double>(2 * i + 2) /
                         static_cast<double>(extremaCount - 1);
        double crestBase = spec.terrainRise * crestU * crestU * (3.0 - 2.0 * crestU);
        double troughBase = spec.terrainRise * troughU * troughU * (3.0 - 2.0 * troughU);
        height[2 * i + 1] = spec.startHeight + crestBase + spec.firstCrestRise *
                            std::pow(spec.crestHeightDecay, static_cast<double>(i));
        height[2 * i + 2] = spec.startHeight + troughBase - spec.troughDropPerHill *
                            static_cast<double>(i + 1);
    }
    curvature[0] = curvature[extremaCount - 1] = 0.0;
    for (std::size_t i = 1; i + 1 < extremaCount; ++i) {
        curvature[i] = (i & 1u) ? -1.0 / spec.crownRadius
                                : kCamelbackValleyCurvatureRatio /
                                  spec.crownRadius;
    }
    // The integrated curvature law fixes half length exactly from height and
    // crown radius.  It has no face-angle or entry-speed sizing input.
    for (std::size_t i = 0; i + 1 < extremaCount; ++i) {
        const double delta = std::abs(height[i + 1] - height[i]);
        const double crownCurvature = (i & 1u) ? -curvature[i]
                                               : -curvature[i + 1];
        const double troughCurvature = (i & 1u) ? curvature[i + 1]
                                                : curvature[i];
        const double ratio = troughCurvature / crownCurvature;
        // For the degree-13 controls above, integral((1-u)*curvature) is
        // (12+5r)/105. This fixes height exactly while leaving crown radius as
        // an independent dimension.
        const double heightFactor = (12.0 + 5.0 * ratio) / 105.0;
        span[i] = std::sqrt(delta / (crownCurvature * heightFactor));
    }

    ProfileBuilder builder({height[0], 0.0, curvature[0]});
    for (std::size_t i = 0; i + 1 < extremaCount; ++i) {
        if (!builder.appendCamelbackHalf(
                {height[i + 1], 0.0, curvature[i + 1]}, span[i],
                (i & 1u) == 0u))
            return result;
        if ((i & 1u) == 0u) {
            std::size_t hill = i / 2;
            result.crestDistance[hill] = builder.profile().length();
            result.crestHeight[hill] = height[i + 1];
        } else {
            std::size_t hill = i / 2;
            result.troughDistance[hill] = builder.profile().length();
            result.troughHeight[hill] = height[i + 1];
        }
    }
    result.troughDistance[spec.hillCount - 1] = builder.profile().length();
    result.troughHeight[spec.hillCount - 1] = height[extremaCount - 1];

    result.profile = builder.profile();
    result.valid = builder.good() && validateHillChain(result);
    if (result.valid) assertC2(result.profile);
    return result;
}

}  // namespace v1profile
