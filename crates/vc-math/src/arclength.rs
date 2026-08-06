//! Arclength: measuring a curve in metres, and finding the point a given
//! number of metres along it.
//!
//! Force is specified against distance travelled, not against a curve's
//! parameter, so every force profile in the project is a function of arclength.
//! Cubic curves have no closed-form arclength, and the map from parameter to
//! distance is not linear — stepping `u` uniformly along a Hermite chain can
//! easily vary the step in metres by a factor of several between segments. The
//! two operations here close that gap: integrate `|dp/du|` to get distance, and
//! invert it to get back a parameter.

use crate::curve::Curve;
use crate::quadrature::composite_gauss_legendre;
use crate::scalar::Scalar;

/// Quadrature panels used across one knot span of an [`ArcTable`]. Four
/// seven-point panels resolve a cubic's speed variation to well under a
/// millimetre over a span tens of metres long.
pub const PANELS_PER_KNOT_SPAN: usize = 4;

/// The arclength of `curve` between two parameter values, in metres.
///
/// `panels` controls the quadrature; more panels cost linearly and buy
/// accuracy. Reversing the endpoints negates the result.
pub fn arclength<T: Scalar, C: Curve<T> + ?Sized>(curve: &C, u0: T, u1: T, panels: usize) -> T {
    composite_gauss_legendre(|u| curve.parametric_speed(u), u0, u1, panels)
}

/// A precomputed map between a curve's parameter and distance along it.
///
/// Built once per curve. Without it, finding the parameter at a given distance
/// means re-integrating from the start of the curve on every query, which turns
/// a resampling pass into quadratic work.
#[derive(Clone, Debug)]
pub struct ArcTable<T: Scalar> {
    knots: Vec<T>,
    cumulative: Vec<T>,
    panels: usize,
}

impl<T: Scalar> ArcTable<T> {
    /// Iterations allowed to the inverse solve. Newton on a monotone function
    /// converges in a handful; this bound exists so a pathological curve fails
    /// predictably rather than hanging.
    const MAX_ITERATIONS: usize = 60;

    /// Builds a table over the whole domain of `curve`, using `knots_per_unit`
    /// sample points per unit of parameter.
    ///
    /// Panics if `knots_per_unit` is zero.
    pub fn build<C: Curve<T> + ?Sized>(curve: &C, knots_per_unit: usize) -> Self {
        assert!(
            knots_per_unit > 0,
            "a table needs at least one knot per unit"
        );
        let (lo, hi) = curve.domain();
        let span = hi - lo;
        let count = (span.to_f64().abs().ceil() as usize * knots_per_unit).max(1);

        let mut knots = Vec::with_capacity(count + 1);
        let mut cumulative = Vec::with_capacity(count + 1);
        knots.push(lo);
        cumulative.push(T::ZERO);

        let step = span / T::from_f64(count as f64);
        let panels = PANELS_PER_KNOT_SPAN;
        let mut total = T::ZERO;
        for i in 1..=count {
            let u = lo + step * T::from_f64(i as f64);
            total += arclength(curve, knots[i - 1], u, panels);
            knots.push(u);
            cumulative.push(total);
        }

        Self {
            knots,
            cumulative,
            panels,
        }
    }

    /// The total length of the curve, in metres.
    #[inline]
    pub fn total_length(&self) -> T {
        self.cumulative[self.cumulative.len() - 1]
    }

    /// Distance along the curve at parameter `u`, clamped to the domain.
    pub fn length_at<C: Curve<T> + ?Sized>(&self, curve: &C, u: T) -> T {
        let lo = self.knots[0];
        let hi = self.knots[self.knots.len() - 1];
        let u = u.clamp(lo, hi);
        let i = self.knot_below(u);
        self.cumulative[i] + arclength(curve, self.knots[i], u, self.panels)
    }

    /// The parameter at which the curve has covered `s` metres, clamped to the
    /// domain.
    ///
    /// Newton's method, bracketed by the table's knots and backed by bisection.
    /// The bracket matters: `|dp/du|` can be small where a curve nearly stops,
    /// and unguarded Newton will happily step out of the segment there.
    pub fn param_at_length<C: Curve<T> + ?Sized>(&self, curve: &C, s: T) -> T {
        let s = s.clamp(T::ZERO, self.total_length());
        // The search always lands strictly inside a knot span, so `base` and
        // the knot above it are distinct and `i + 1` is in range.
        let i = self.knot_at_or_below_length(s);
        let base = self.knots[i];
        let above = self.knots[i + 1];

        // Distance still to cover past `base`. Measured from `base` and only
        // from `base`: the bracket below moves as the search narrows, but the
        // residual's reference point must not, or the two disagree about what
        // is being solved for.
        let remaining = s - self.cumulative[i];
        let span_length = self.cumulative[i + 1] - self.cumulative[i];

        let half = T::from_f64(0.5);
        let mut lo = base;
        let mut hi = above;
        // Speed varies little across one knot span, so linear interpolation is
        // already a good guess and Newton usually finishes in two steps.
        let mut u = if span_length > T::ZERO {
            base + (above - base) * (remaining / span_length)
        } else {
            base
        };

        let tolerance = T::from_f64(1e-12) * (T::ONE + self.total_length().abs());
        for _ in 0..Self::MAX_ITERATIONS {
            let residual = arclength(curve, base, u, self.panels) - remaining;
            if residual.abs() <= tolerance {
                return u;
            }
            if residual > T::ZERO {
                hi = u
            } else {
                lo = u
            }

            let speed = curve.parametric_speed(u);
            let stepped = u - residual / speed;
            // Bisect whenever Newton is undefined or leaves the bracket, which
            // is what happens where the curve nearly stops.
            u = if speed > T::ZERO && stepped > lo && stepped < hi {
                stepped
            } else {
                (lo + hi) * half
            };
        }
        u
    }

    /// Index of the last knot at or below `u`.
    fn knot_below(&self, u: T) -> usize {
        let target = u.to_f64();
        let mut lo = 0usize;
        let mut hi = self.knots.len() - 1;
        while hi - lo > 1 {
            let mid = usize::midpoint(lo, hi);
            if self.knots[mid].to_f64() <= target {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        lo
    }

    /// Index of the last knot whose cumulative length is at or below `s`.
    fn knot_at_or_below_length(&self, s: T) -> usize {
        let target = s.to_f64();
        let mut lo = 0usize;
        let mut hi = self.cumulative.len() - 1;
        while hi - lo > 1 {
            let mid = usize::midpoint(lo, hi);
            if self.cumulative[mid].to_f64() <= target {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        lo
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::curve::{HermiteCurve, HermiteSegment};
    use crate::dual::Dual;
    use crate::vec3::Vec3;
    use core::f64::consts::TAU;

    type V = Vec3<f64>;

    /// A circle of given radius in the xy-plane, parameterised by angle. Its
    /// arclength is known exactly, which is the point.
    struct Circle {
        radius: f64,
    }

    impl Curve<f64> for Circle {
        fn domain(&self) -> (f64, f64) {
            (0.0, TAU)
        }
        fn position(&self, u: f64) -> V {
            V::new(self.radius * u.cos(), self.radius * u.sin(), 0.0)
        }
        fn derivative(&self, u: f64) -> V {
            V::new(-self.radius * u.sin(), self.radius * u.cos(), 0.0)
        }
    }

    /// A helix: radius `r`, rising `pitch` per turn. Arclength per turn is
    /// `sqrt((2 pi r)^2 + pitch^2)`.
    struct Helix {
        radius: f64,
        pitch: f64,
    }

    impl Curve<f64> for Helix {
        fn domain(&self) -> (f64, f64) {
            (0.0, TAU)
        }
        fn position(&self, u: f64) -> V {
            V::new(
                self.radius * u.cos(),
                self.radius * u.sin(),
                self.pitch * u / TAU,
            )
        }
        fn derivative(&self, u: f64) -> V {
            V::new(
                -self.radius * u.sin(),
                self.radius * u.cos(),
                self.pitch / TAU,
            )
        }
    }

    #[test]
    fn circle_arclength_matches_the_closed_form() {
        let c = Circle { radius: 37.5 };
        let got = arclength(&c, 0.0, TAU, 16);
        let exact = TAU * 37.5;
        assert!((got - exact).abs() < 1e-9, "{got} vs {exact}");
    }

    #[test]
    fn helix_arclength_matches_the_closed_form() {
        let h = Helix {
            radius: 20.0,
            pitch: 8.0,
        };
        let got = arclength(&h, 0.0, TAU, 16);
        let exact = ((TAU * 20.0f64).powi(2) + 8.0f64.powi(2)).sqrt();
        assert!((got - exact).abs() < 1e-9, "{got} vs {exact}");
    }

    #[test]
    fn reversing_the_interval_negates_the_length() {
        let c = Circle { radius: 5.0 };
        let forward = arclength(&c, 0.5, 2.0, 8);
        let backward = arclength(&c, 2.0, 0.5, 8);
        assert!((forward + backward).abs() < 1e-12);
    }

    #[test]
    fn a_table_reports_the_total_length() {
        let c = Circle { radius: 12.0 };
        let table = ArcTable::build(&c, 8);
        assert!((table.total_length() - TAU * 12.0).abs() < 1e-9);
    }

    #[test]
    fn parameter_and_length_are_inverses_on_a_circle() {
        // On a circle of radius r, s = r * u exactly, so the inversion has a
        // known answer at every point rather than just round-tripping.
        let c = Circle { radius: 9.0 };
        let table = ArcTable::build(&c, 8);
        for i in 0..=40 {
            let s = table.total_length() * f64::from(i) / 40.0;
            let u = table.param_at_length(&c, s);
            assert!((u - s / 9.0).abs() < 1e-9, "s = {s}: got u = {u}");
            assert!((table.length_at(&c, u) - s).abs() < 1e-9);
        }
    }

    #[test]
    fn inversion_round_trips_on_a_curve_with_uneven_speed() {
        // Segments of very different length: the parameter-to-distance map is
        // strongly non-linear, which is the case that catches a naive
        // implementation.
        let curve = HermiteCurve::new(vec![
            HermiteSegment::new(V::ZERO, V::new(1.0, 0.0, 0.0), V::X, V::new(1.0, 0.0, 0.0)),
            HermiteSegment::new(
                V::X,
                V::new(200.0, 0.0, 0.0),
                V::new(120.0, 40.0, 15.0),
                V::new(100.0, 90.0, 0.0),
            ),
        ])
        .unwrap();
        let table = ArcTable::build(&curve, 16);
        assert!(table.total_length() > 100.0);
        for i in 0..=50 {
            let s = table.total_length() * f64::from(i) / 50.0;
            let u = table.param_at_length(&curve, s);
            let back = table.length_at(&curve, u);
            assert!((back - s).abs() < 1e-7, "s = {s}, back = {back}, u = {u}");
        }
    }

    #[test]
    fn queries_outside_the_curve_clamp() {
        let c = Circle { radius: 3.0 };
        let table = ArcTable::build(&c, 4);
        assert!(table.param_at_length(&c, -10.0).abs() < 1e-12);
        assert!((table.param_at_length(&c, 1e6) - TAU).abs() < 1e-9);
        assert!(table.length_at(&c, -1.0).abs() < 1e-12);
        assert!((table.length_at(&c, 100.0) - table.total_length()).abs() < 1e-9);
    }

    #[test]
    fn arclength_carries_derivatives() {
        // A straight segment from the origin to (L, 0, 0) has length L, so the
        // derivative of its length with respect to L is one.
        let make = |l: Dual| {
            let end = Vec3::new(l, Dual::constant(0.0), Dual::constant(0.0));
            HermiteCurve::new(vec![HermiteSegment::new(Vec3::ZERO, end, end, end)]).unwrap()
        };
        let curve = make(Dual::variable(17.0));
        let s = arclength(&curve, Dual::constant(0.0), Dual::constant(1.0), 4);
        assert!((s.re - 17.0).abs() < 1e-9, "{}", s.re);
        assert!((s.du - 1.0).abs() < 1e-9, "{}", s.du);
    }
}
