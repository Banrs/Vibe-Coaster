//! Parametric space curves.
//!
//! A note on where these sit. In an editor-driven coaster tool the spline *is*
//! the ride: you drag control points and the geometry follows. Here the ride's
//! geometry comes out of forward integration of a force profile, so curves are
//! not the primary representation. They are the supporting cast — seeding the
//! solve with a nominal centreline, resampling a solved heartline for the
//! renderer, describing lift and brake geometry that is specified as shape
//! rather than as force.
//!
//! Cubic Hermite is the form used because it is the one that takes tangents as
//! input. Track sections meet with a known direction, and a representation that
//! makes matching directions at a seam trivial is worth more here than one with
//! prettier interpolation properties.

use crate::scalar::Scalar;
use crate::vec3::Vec3;

/// A curve in space, parameterised by some `u` that is *not* arclength.
///
/// Recovering arclength is [`mod@crate::arclength`]'s job. The distinction matters:
/// equal steps in `u` are not equal steps in metres, and a force profile
/// integrated against the wrong one is silently wrong.
pub trait Curve<T: Scalar> {
    /// The valid range of the parameter, inclusive.
    fn domain(&self) -> (T, T);

    /// The point at parameter `u`.
    fn position(&self, u: T) -> Vec3<T>;

    /// The first derivative with respect to the parameter, `dp/du`. Its
    /// direction is the tangent; its magnitude is not generally one.
    fn derivative(&self, u: T) -> Vec3<T>;

    /// `|dp/du|` — how much arclength a unit of parameter buys at `u`.
    #[inline]
    fn parametric_speed(&self, u: T) -> T {
        self.derivative(u).norm()
    }

    /// The unit tangent at `u`. Undefined where the derivative vanishes.
    #[inline]
    fn unit_tangent(&self, u: T) -> Vec3<T> {
        self.derivative(u).normalized()
    }
}

/// One cubic Hermite segment: two endpoints and the tangents at them, over a
/// local parameter in `[0, 1]`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct HermiteSegment<T: Scalar> {
    /// Position at `u = 0`.
    pub p0: Vec3<T>,
    /// `dp/du` at `u = 0`.
    pub m0: Vec3<T>,
    /// Position at `u = 1`.
    pub p1: Vec3<T>,
    /// `dp/du` at `u = 1`.
    pub m1: Vec3<T>,
}

impl<T: Scalar> HermiteSegment<T> {
    /// A segment from its endpoints and their tangents.
    #[inline]
    pub const fn new(p0: Vec3<T>, m0: Vec3<T>, p1: Vec3<T>, m1: Vec3<T>) -> Self {
        Self { p0, m0, p1, m1 }
    }

    /// The point at local parameter `u` in `[0, 1]`.
    #[inline]
    pub fn position(&self, u: T) -> Vec3<T> {
        let uu = u * u;
        let uuu = uu * u;
        let two = T::from_f64(2.0);
        let three = T::from_f64(3.0);
        self.p0 * (two * uuu - three * uu + T::ONE)
            + self.m0 * (uuu - two * uu + u)
            + self.p1 * (-two * uuu + three * uu)
            + self.m1 * (uuu - uu)
    }

    /// `dp/du` at local parameter `u`.
    #[inline]
    pub fn derivative(&self, u: T) -> Vec3<T> {
        let uu = u * u;
        let two = T::from_f64(2.0);
        let three = T::from_f64(3.0);
        let four = T::from_f64(4.0);
        let six = T::from_f64(6.0);
        self.p0 * (six * uu - six * u)
            + self.m0 * (three * uu - four * u + T::ONE)
            + self.p1 * (-six * uu + six * u)
            + self.m1 * (three * uu - two * u)
    }

    /// `d²p/du²` at local parameter `u`.
    #[inline]
    pub fn second_derivative(&self, u: T) -> Vec3<T> {
        let two = T::from_f64(2.0);
        let four = T::from_f64(4.0);
        let six = T::from_f64(6.0);
        let twelve = T::from_f64(12.0);
        self.p0 * (twelve * u - six)
            + self.m0 * (six * u - four)
            + self.p1 * (-twelve * u + six)
            + self.m1 * (six * u - two)
    }
}

/// A chain of Hermite segments, parameterised by `u` in `[0, n]` for `n`
/// segments: the integer part selects the segment, the fraction is the local
/// parameter.
///
/// Positions and tangents match at every seam by construction, so the curve is
/// C¹. It is not generally C², which for a coaster centreline means curvature
/// can jump at a seam — that is precisely the discontinuity the solver's
/// continuity constraints exist to remove, so it is left visible here rather
/// than smoothed away by a higher-order representation.
#[derive(Clone, Debug, PartialEq)]
pub struct HermiteCurve<T: Scalar> {
    segments: Vec<HermiteSegment<T>>,
}

impl<T: Scalar> HermiteCurve<T> {
    /// A curve from its segments. Returns `None` if there are none.
    pub fn new(segments: Vec<HermiteSegment<T>>) -> Option<Self> {
        if segments.is_empty() {
            None
        } else {
            Some(Self { segments })
        }
    }

    /// A curve passing through `points`, with Catmull–Rom tangents.
    ///
    /// Each interior tangent is half the vector between a point's neighbours;
    /// the ends use the one-sided difference. Fewer than two points gives
    /// `None`.
    pub fn catmull_rom(points: &[Vec3<T>]) -> Option<Self> {
        if points.len() < 2 {
            return None;
        }
        let half = T::from_f64(0.5);
        let tangent = |i: usize| -> Vec3<T> {
            let lo = points[i.saturating_sub(1)];
            let hi = points[(i + 1).min(points.len() - 1)];
            let span = if i == 0 || i + 1 == points.len() {
                T::ONE
            } else {
                half
            };
            (hi - lo) * span
        };
        let segments = (0..points.len() - 1)
            .map(|i| HermiteSegment::new(points[i], tangent(i), points[i + 1], tangent(i + 1)))
            .collect();
        Self::new(segments)
    }

    /// The segments making up the curve.
    #[inline]
    pub fn segments(&self) -> &[HermiteSegment<T>] {
        &self.segments
    }

    /// How many segments the curve has.
    #[inline]
    pub fn len(&self) -> usize {
        self.segments.len()
    }

    /// Always false — a curve cannot be built with no segments.
    #[inline]
    pub fn is_empty(&self) -> bool {
        false
    }

    /// Splits a global parameter into a segment index and a local parameter,
    /// clamping to the domain.
    ///
    /// The segment is chosen by the *value* of `u`. Under differentiation that
    /// makes the choice a constant, which is what we want everywhere except
    /// exactly at a seam, where the derivative is one-sided anyway.
    #[inline]
    fn locate(&self, u: T) -> (usize, T) {
        let last = self.segments.len() - 1;
        let (lo, hi) = self.domain();
        // Clamp before splitting, not after: clamping only the index would
        // leave the local parameter outside [0, 1] and evaluate the cubic as
        // an extrapolation, which for a Hermite segment diverges fast.
        let u = u.clamp(lo, hi);
        // A negative or NaN parameter cannot survive the clamp, and `as`
        // saturates in any case.
        let index = (u.to_f64().floor() as usize).min(last);
        (index, u - T::from_f64(index as f64))
    }
}

impl<T: Scalar> Curve<T> for HermiteCurve<T> {
    #[inline]
    fn domain(&self) -> (T, T) {
        (T::ZERO, T::from_f64(self.segments.len() as f64))
    }

    #[inline]
    fn position(&self, u: T) -> Vec3<T> {
        let (i, local) = self.locate(u);
        self.segments[i].position(local)
    }

    #[inline]
    fn derivative(&self, u: T) -> Vec3<T> {
        let (i, local) = self.locate(u);
        self.segments[i].derivative(local)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dual::Dual;

    type V = Vec3<f64>;

    fn close(a: V, b: V) {
        assert!((a - b).norm() < 1e-12, "{a:?} vs {b:?}");
    }

    fn sample_segment() -> HermiteSegment<f64> {
        HermiteSegment::new(
            V::new(0.0, 0.0, 0.0),
            V::new(1.0, 2.0, 0.5),
            V::new(3.0, 1.0, 2.0),
            V::new(0.0, -1.0, 1.5),
        )
    }

    #[test]
    fn a_segment_interpolates_its_endpoints_and_tangents() {
        let s = sample_segment();
        close(s.position(0.0), s.p0);
        close(s.position(1.0), s.p1);
        close(s.derivative(0.0), s.m0);
        close(s.derivative(1.0), s.m1);
    }

    #[test]
    fn segment_derivatives_agree_with_finite_differences() {
        let s = sample_segment();
        let h = 1e-6;
        for &u in &[0.0_f64, 0.25, 0.5, 0.9, 1.0] {
            let numeric = (s.position(u + h) - s.position(u - h)) / (2.0 * h);
            assert!((s.derivative(u) - numeric).norm() < 1e-7, "d at {u}");
            let numeric2 = (s.derivative(u + h) - s.derivative(u - h)) / (2.0 * h);
            assert!(
                (s.second_derivative(u) - numeric2).norm() < 1e-7,
                "dd at {u}"
            );
        }
    }

    #[test]
    fn a_straight_segment_stays_straight() {
        // Endpoints and tangents all colinear: the cubic must collapse to a
        // line, which is the case a coaster launch track actually is.
        let d = V::new(2.0, 0.0, 0.0);
        let s = HermiteSegment::new(V::ZERO, d, d, d);
        for i in 0..=10 {
            let u = f64::from(i) / 10.0;
            close(s.position(u), d * u);
        }
    }

    #[test]
    fn a_chain_is_continuous_in_position_and_tangent_across_seams() {
        let points = [
            V::new(0.0, 0.0, 0.0),
            V::new(10.0, 2.0, 1.0),
            V::new(18.0, -3.0, 6.0),
            V::new(25.0, 0.0, 4.0),
        ];
        let curve = HermiteCurve::catmull_rom(&points).unwrap();
        assert_eq!(curve.len(), 3);
        for &p in &points {
            // Every input point is on the curve.
            let hit = (0..=300).any(|i| {
                let u = f64::from(i) / 100.0;
                (curve.position(u) - p).norm() < 1e-9
            });
            assert!(hit, "{p:?} not interpolated");
        }
        // Continuity checked exactly, at the seam rather than either side of
        // it: the end of one segment must be the start of the next, in both
        // position and tangent.
        for seam in 1..curve.len() {
            let before = curve.segments()[seam - 1];
            let after = curve.segments()[seam];
            close(before.position(1.0), after.position(0.0));
            close(before.derivative(1.0), after.derivative(0.0));
        }
    }

    #[test]
    fn the_parameter_is_clamped_to_the_domain() {
        let curve = HermiteCurve::catmull_rom(&[V::ZERO, V::X, V::new(2.0, 1.0, 0.0)]).unwrap();
        let (lo, hi) = curve.domain();
        close(curve.position(lo - 5.0), curve.position(lo));
        close(curve.position(hi + 5.0), curve.position(hi));
    }

    #[test]
    fn too_few_points_is_not_a_curve() {
        assert!(HermiteCurve::<f64>::catmull_rom(&[]).is_none());
        assert!(HermiteCurve::catmull_rom(&[V::ZERO]).is_none());
        assert!(HermiteCurve::<f64>::new(vec![]).is_none());
    }

    #[test]
    fn curves_carry_derivatives() {
        let s = HermiteSegment::new(
            Vec3::from_f64(0.0, 0.0, 0.0),
            Vec3::from_f64(1.0, 0.0, 0.0),
            Vec3::from_f64(1.0, 1.0, 0.0),
            Vec3::from_f64(1.0, 0.0, 0.0),
        );
        // Differentiating the position with respect to the parameter must
        // reproduce the analytic derivative.
        let u = 0.4;
        let p = s.position(Dual::variable(u));
        let d = s.derivative(Dual::constant(u));
        assert!((p.x.du - d.x.re).abs() < 1e-12);
        assert!((p.y.du - d.y.re).abs() < 1e-12);
    }
}
