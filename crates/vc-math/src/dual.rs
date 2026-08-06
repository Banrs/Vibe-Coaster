//! Forward-mode automatic differentiation.
//!
//! A [`Dual`] carries a value and one directional derivative. Evaluating any
//! [`Scalar`]-generic function with `Dual` in place of `f64` produces the
//! function's value and the derivative of that value along the seeded
//! direction, exactly — no step size, no truncation error, no cancellation.
//!
//! This exists for two reasons. The first is step 6: a gradient-based solve
//! over the free ride parameters needs a Jacobian, and finite differences over
//! a long forward integration are both expensive and noisy. The second is
//! immediate: `Dual` is the second implementor of [`Scalar`], and without a
//! second implementor it is very easy to write code that is generic in its
//! signature and `f64`-only in its body. The math layer's tests exercise both.
//!
//! `Dual` is generic in its own scalar, so second derivatives come from
//! `Dual<Dual<f64>>` without further machinery.
//!
//! ```
//! use vc_math::{Dual, Scalar};
//!
//! // d/dx (x^3) at x = 2 is 12.
//! let x = Dual::variable(2.0);
//! let y = x.powi(3);
//! assert!((y.du - 12.0).abs() < 1e-12);
//! ```

use core::cmp::Ordering;
use core::ops::{Add, AddAssign, Div, DivAssign, Mul, MulAssign, Neg, Sub, SubAssign};

use crate::scalar::Scalar;

/// A value paired with its derivative along one seeded direction.
#[derive(Clone, Copy, Debug)]
pub struct Dual<T: Scalar = f64> {
    /// The value.
    pub re: T,
    /// The derivative of the value with respect to the seeded direction.
    pub du: T,
}

impl<T: Scalar> Dual<T> {
    /// A number with a known value and a known derivative.
    #[inline]
    pub const fn new(re: T, du: T) -> Self {
        Self { re, du }
    }

    /// A number that does not vary with the seeded direction.
    #[inline]
    pub const fn constant(re: T) -> Self {
        Self { re, du: T::ZERO }
    }

    /// The number being differentiated with respect to. Seeds the derivative
    /// to one.
    #[inline]
    pub const fn variable(re: T) -> Self {
        Self { re, du: T::ONE }
    }
}

// Comparison is on the value only. See the note on `Scalar`: this is what lets
// branching code take the same branch whether or not it is being
// differentiated.
impl<T: Scalar> PartialEq for Dual<T> {
    #[inline]
    fn eq(&self, other: &Self) -> bool {
        self.re == other.re
    }
}

impl<T: Scalar> PartialOrd for Dual<T> {
    #[inline]
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        self.re.partial_cmp(&other.re)
    }
}

impl<T: Scalar> Add for Dual<T> {
    type Output = Self;
    #[inline]
    fn add(self, rhs: Self) -> Self {
        Self::new(self.re + rhs.re, self.du + rhs.du)
    }
}

impl<T: Scalar> Sub for Dual<T> {
    type Output = Self;
    #[inline]
    fn sub(self, rhs: Self) -> Self {
        Self::new(self.re - rhs.re, self.du - rhs.du)
    }
}

impl<T: Scalar> Mul for Dual<T> {
    type Output = Self;
    #[inline]
    fn mul(self, rhs: Self) -> Self {
        Self::new(self.re * rhs.re, self.re * rhs.du + self.du * rhs.re)
    }
}

impl<T: Scalar> Div for Dual<T> {
    type Output = Self;
    #[inline]
    fn div(self, rhs: Self) -> Self {
        Self::new(
            self.re / rhs.re,
            (self.du * rhs.re - self.re * rhs.du) / rhs.re.squared(),
        )
    }
}

impl<T: Scalar> Neg for Dual<T> {
    type Output = Self;
    #[inline]
    fn neg(self) -> Self {
        Self::new(-self.re, -self.du)
    }
}

impl<T: Scalar> AddAssign for Dual<T> {
    #[inline]
    fn add_assign(&mut self, rhs: Self) {
        *self = *self + rhs;
    }
}

impl<T: Scalar> SubAssign for Dual<T> {
    #[inline]
    fn sub_assign(&mut self, rhs: Self) {
        *self = *self - rhs;
    }
}

impl<T: Scalar> MulAssign for Dual<T> {
    #[inline]
    fn mul_assign(&mut self, rhs: Self) {
        *self = *self * rhs;
    }
}

impl<T: Scalar> DivAssign for Dual<T> {
    #[inline]
    fn div_assign(&mut self, rhs: Self) {
        *self = *self / rhs;
    }
}

impl<T: Scalar> Scalar for Dual<T> {
    const ZERO: Self = Self {
        re: T::ZERO,
        du: T::ZERO,
    };
    const ONE: Self = Self {
        re: T::ONE,
        du: T::ZERO,
    };

    #[inline]
    fn from_f64(x: f64) -> Self {
        Self::constant(T::from_f64(x))
    }

    #[inline]
    fn to_f64(self) -> f64 {
        self.re.to_f64()
    }

    #[inline]
    fn abs(self) -> Self {
        if self.re < T::ZERO { -self } else { self }
    }

    #[inline]
    fn sqrt(self) -> Self {
        let root = self.re.sqrt();
        Self::new(root, self.du / (root + root))
    }

    #[inline]
    fn recip(self) -> Self {
        Self::new(self.re.recip(), -self.du / self.re.squared())
    }

    #[inline]
    fn powi(self, n: i32) -> Self {
        if n == 0 {
            return Self::ONE;
        }
        Self::new(
            self.re.powi(n),
            T::from_f64(f64::from(n)) * self.re.powi(n - 1) * self.du,
        )
    }

    #[inline]
    fn sin(self) -> Self {
        let (s, c) = self.re.sin_cos();
        Self::new(s, c * self.du)
    }

    #[inline]
    fn cos(self) -> Self {
        let (s, c) = self.re.sin_cos();
        Self::new(c, -s * self.du)
    }

    #[inline]
    fn tan(self) -> Self {
        let t = self.re.tan();
        Self::new(t, (T::ONE + t.squared()) * self.du)
    }

    #[inline]
    fn asin(self) -> Self {
        Self::new(
            self.re.asin(),
            self.du / (T::ONE - self.re.squared()).sqrt(),
        )
    }

    #[inline]
    fn acos(self) -> Self {
        Self::new(
            self.re.acos(),
            -self.du / (T::ONE - self.re.squared()).sqrt(),
        )
    }

    #[inline]
    fn atan2(self, x: Self) -> Self {
        // d atan2(y, x) = (x dy - y dx) / (x^2 + y^2)
        let denom = x.re.squared() + self.re.squared();
        Self::new(
            self.re.atan2(x.re),
            (x.re * self.du - self.re * x.du) / denom,
        )
    }

    #[inline]
    fn exp(self) -> Self {
        let e = self.re.exp();
        Self::new(e, e * self.du)
    }

    #[inline]
    fn ln(self) -> Self {
        Self::new(self.re.ln(), self.du / self.re)
    }

    #[inline]
    fn is_finite(self) -> bool {
        self.re.is_finite()
    }
}

#[cfg(test)]
mod tests {
    // Several assertions below are about exactness rather than closeness — a
    // constant's derivative is precisely zero, not nearly zero — so exact
    // comparison is the claim being made.
    #![allow(clippy::float_cmp)]

    use super::*;

    /// Central differences, as an independent check on the analytic
    /// derivatives. Deliberately not used anywhere but in tests.
    fn central_difference(f: impl Fn(f64) -> f64, x: f64) -> f64 {
        let h = 1e-6;
        (f(x + h) - f(x - h)) / (2.0 * h)
    }

    fn check(name: &str, f: impl Fn(Dual) -> Dual + Copy, x: f64) {
        let analytic = f(Dual::variable(x)).du;
        let numeric = central_difference(|v| f(Dual::constant(v)).re, x);
        assert!(
            (analytic - numeric).abs() < 1e-6 * (1.0 + numeric.abs()),
            "{name}: analytic {analytic} vs numeric {numeric} at x = {x}"
        );
    }

    #[test]
    fn elementary_derivatives_match_finite_differences() {
        for &x in &[0.3_f64, 0.7, 1.4, 2.6] {
            check("sqrt", Scalar::sqrt, x);
            check("recip", Scalar::recip, x);
            check("sin", Scalar::sin, x);
            check("cos", Scalar::cos, x);
            check("tan", Scalar::tan, x);
            check("exp", Scalar::exp, x);
            check("ln", Scalar::ln, x);
            check("powi3", |v: Dual| v.powi(3), x);
            check("powi-neg2", |v: Dual| v.powi(-2), x);
        }
        for &x in &[-0.8_f64, -0.2, 0.2, 0.8] {
            check("asin", Scalar::asin, x);
            check("acos", Scalar::acos, x);
        }
    }

    #[test]
    fn arithmetic_derivatives_match_finite_differences() {
        let x = 1.7;
        check("product", |v: Dual| v * v.sin(), x);
        check("quotient", |v: Dual| v.exp() / (v + Dual::constant(2.0)), x);
        check(
            "composition",
            |v: Dual| (v.squared() + Dual::constant(1.0)).sqrt().ln(),
            x,
        );
        check(
            "atan2",
            |v: Dual| v.sin().atan2(v.cos() + Dual::constant(2.0)),
            x,
        );
    }

    #[test]
    fn constants_have_zero_derivative() {
        let c: Dual = Scalar::from_f64(3.5);
        assert_eq!(c.du, 0.0);
        assert_eq!(Dual::<f64>::ONE.du, 0.0);
        assert_eq!(Dual::<f64>::ZERO.re, 0.0);
    }

    #[test]
    fn nesting_gives_second_derivatives() {
        // d²/dx² (sin x) = -sin x.
        let x = 0.9_f64;
        let inner = Dual::variable(x);
        let outer: Dual<Dual> = Dual::new(inner, Dual::constant(1.0));
        let second = outer.sin().du.du;
        assert!((second + x.sin()).abs() < 1e-12, "got {second}");
    }

    #[test]
    fn comparison_ignores_the_derivative() {
        assert_eq!(Dual::variable(1.0), Dual::constant(1.0));
        assert!(Dual::constant(1.0) < Dual::variable(2.0));
        assert_eq!(Dual::variable(1.0).max(Dual::constant(2.0)).re, 2.0);
    }
}
