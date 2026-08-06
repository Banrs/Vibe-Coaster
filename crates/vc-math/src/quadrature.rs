//! Numerical integration of a scalar function over an interval.
//!
//! Gauss–Legendre, at fixed order, over a fixed number of equal panels. Fixed
//! everything is the point: the result must depend on the inputs alone, so that
//! the same ride model always produces the same numbers, and so that
//! differentiating through the quadrature gives the derivative of a smooth
//! function rather than the derivative of an adaptive algorithm's decisions.
//!
//! Seven-point Gauss–Legendre integrates polynomials up to degree 13 exactly,
//! which covers the cubic-segment integrands this crate uses with room to
//! spare; the residual error on a curve's arclength comes from the square root
//! in the integrand, not from the polynomial order.

use crate::scalar::Scalar;

/// Seven-point Gauss–Legendre abscissae on `[-1, 1]`.
pub const GL7_NODES: [f64; 7] = [
    -0.949_107_912_342_758_5,
    -0.741_531_185_599_394_4,
    -0.405_845_151_377_397_2,
    0.0,
    0.405_845_151_377_397_2,
    0.741_531_185_599_394_4,
    0.949_107_912_342_758_5,
];

/// Weights matching [`GL7_NODES`]. They sum to two.
pub const GL7_WEIGHTS: [f64; 7] = [
    0.129_484_966_168_869_7,
    0.279_705_391_489_276_7,
    0.381_830_050_505_118_9,
    0.417_959_183_673_469_4,
    0.381_830_050_505_118_9,
    0.279_705_391_489_276_7,
    0.129_484_966_168_869_7,
];

/// The integral of `f` over `[a, b]`, by seven-point Gauss–Legendre.
#[inline]
pub fn gauss_legendre<T: Scalar>(f: impl Fn(T) -> T, a: T, b: T) -> T {
    let half = (b - a) / T::from_f64(2.0);
    let mid = (a + b) / T::from_f64(2.0);
    let mut sum = T::ZERO;
    for (&node, &weight) in GL7_NODES.iter().zip(GL7_WEIGHTS.iter()) {
        sum += T::from_f64(weight) * f(mid + half * T::from_f64(node));
    }
    sum * half
}

/// The integral of `f` over `[a, b]`, splitting the interval into `panels`
/// equal pieces and applying [`gauss_legendre`] to each.
///
/// `panels` of zero integrates nothing and returns zero.
#[inline]
pub fn composite_gauss_legendre<T: Scalar>(f: impl Fn(T) -> T, a: T, b: T, panels: usize) -> T {
    if panels == 0 {
        return T::ZERO;
    }
    let width = (b - a) / T::from_f64(panels as f64);
    let mut sum = T::ZERO;
    for i in 0..panels {
        let lo = a + width * T::from_f64(i as f64);
        sum += gauss_legendre(&f, lo, lo + width);
    }
    sum
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dual::Dual;
    use core::f64::consts::PI;

    #[test]
    fn weights_sum_to_the_interval() {
        let total: f64 = GL7_WEIGHTS.iter().sum();
        assert!((total - 2.0).abs() < 1e-15);
        assert!((gauss_legendre(|_: f64| 1.0, 3.0, 7.0) - 4.0).abs() < 1e-14);
    }

    #[test]
    fn polynomials_up_to_degree_thirteen_are_exact() {
        for n in 0..=13_i32 {
            let exact = (2.0_f64.powi(n + 1) - 1.0_f64.powi(n + 1)) / f64::from(n + 1);
            let got = gauss_legendre(|x: f64| x.powi(n), 1.0, 2.0);
            assert!((got - exact).abs() < 1e-12 * exact.abs(), "degree {n}");
        }
    }

    #[test]
    fn transcendental_integrands_converge() {
        // The integral of sin over [0, pi] is exactly 2.
        let got = gauss_legendre(|x: f64| x.sin(), 0.0, PI);
        assert!((got - 2.0).abs() < 1e-11, "{got}");
    }

    #[test]
    fn panels_reduce_the_error() {
        // A deliberately hard integrand: 1/(1 + 25 x^2) over [-1, 1].
        let f = |x: f64| 1.0 / (1.0 + 25.0 * x * x);
        let exact = 2.0 * (5.0_f64).atan() / 5.0;
        let one = (gauss_legendre(f, -1.0, 1.0) - exact).abs();
        let many = (composite_gauss_legendre(f, -1.0, 1.0, 32) - exact).abs();
        assert!(many < one * 1e-6, "one panel {one}, 32 panels {many}");
    }

    #[test]
    fn empty_panel_count_integrates_nothing() {
        assert!((composite_gauss_legendre(|x: f64| x, 0.0, 1.0, 0)).abs() < 1e-15);
    }

    #[test]
    fn quadrature_carries_derivatives() {
        // d/db of the integral of x^2 from 0 to b is b^2.
        let b = Dual::variable(1.3);
        let integral = gauss_legendre(|x: Dual| x.squared(), Dual::constant(0.0), b);
        assert!((integral.du - 1.3 * 1.3).abs() < 1e-12, "{}", integral.du);
    }
}
