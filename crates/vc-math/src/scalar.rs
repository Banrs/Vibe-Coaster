//! The numeric type the whole math layer is generic over.
//!
//! Every function below the evaluator is written against [`Scalar`] rather than
//! `f64`. The point is not abstraction for its own sake: the global solve in
//! step 6 wants exact derivatives of the evaluator with respect to the free
//! parameters, and forward-mode automatic differentiation gets them by
//! substituting a dual number for `f64` at the leaves. Retrofitting that later
//! would mean touching every line of the math and evaluator layers, so the
//! genericity is paid for up front.
//!
//! The trait deliberately carries only the operations this project actually
//! uses. It is not `num_traits::Float`: that trait demands bit-level operations
//! (`classify`, `integer_decode`) which dual numbers cannot meaningfully
//! provide.

use core::fmt::Debug;
use core::ops::{Add, AddAssign, Div, DivAssign, Mul, MulAssign, Neg, Sub, SubAssign};

/// A real-valued scalar supporting the arithmetic the math layer needs.
///
/// Implementors: [`f64`] for plain evaluation, and [`crate::dual::Dual`] for
/// evaluation that carries derivatives alongside values.
///
/// Comparison operators act on the *value* of the number. For a dual number
/// that means the derivative is ignored, so two duals with equal values and
/// different derivatives compare equal. This is the usual convention and is
/// what makes branch-heavy numeric code behave identically under
/// differentiation, but it does mean `PartialEq` is not structural equality.
pub trait Scalar:
    Copy
    + Debug
    + PartialEq
    + PartialOrd
    + Add<Output = Self>
    + Sub<Output = Self>
    + Mul<Output = Self>
    + Div<Output = Self>
    + Neg<Output = Self>
    + AddAssign
    + SubAssign
    + MulAssign
    + DivAssign
{
    /// The additive identity.
    const ZERO: Self;
    /// The multiplicative identity.
    const ONE: Self;

    /// Lifts a constant. The result has zero derivative.
    fn from_f64(x: f64) -> Self;

    /// The value of the number, discarding any derivative information.
    ///
    /// For reporting, comparison and interop only — using this inside a
    /// computation silently breaks the derivative chain.
    fn to_f64(self) -> f64;

    /// Absolute value. Not differentiable at zero; the derivative there is
    /// taken from the positive branch.
    fn abs(self) -> Self;
    /// Square root.
    fn sqrt(self) -> Self;
    /// Reciprocal.
    fn recip(self) -> Self;
    /// Raises to an integer power.
    fn powi(self, n: i32) -> Self;
    /// Sine, radians.
    fn sin(self) -> Self;
    /// Cosine, radians.
    fn cos(self) -> Self;
    /// Tangent, radians.
    fn tan(self) -> Self;
    /// Arcsine, radians.
    fn asin(self) -> Self;
    /// Arccosine, radians.
    fn acos(self) -> Self;
    /// Four-quadrant arctangent of `self / x`, radians.
    fn atan2(self, x: Self) -> Self;
    /// Natural exponential.
    fn exp(self) -> Self;
    /// Natural logarithm.
    fn ln(self) -> Self;
    /// Whether the value is finite. Derivative information is not considered.
    fn is_finite(self) -> bool;

    /// Sine and cosine together.
    #[inline]
    fn sin_cos(self) -> (Self, Self) {
        (self.sin(), self.cos())
    }

    /// The number squared.
    #[inline]
    fn squared(self) -> Self {
        self * self
    }

    /// The smaller of two numbers, compared by value.
    #[inline]
    fn min(self, other: Self) -> Self {
        if other < self { other } else { self }
    }

    /// The larger of two numbers, compared by value.
    #[inline]
    fn max(self, other: Self) -> Self {
        if other > self { other } else { self }
    }

    /// Clamps into `[lo, hi]`, compared by value.
    #[inline]
    fn clamp(self, lo: Self, hi: Self) -> Self {
        self.max(lo).min(hi)
    }
}

impl Scalar for f64 {
    const ZERO: Self = 0.0;
    const ONE: Self = 1.0;

    #[inline]
    fn from_f64(x: f64) -> Self {
        x
    }
    #[inline]
    fn to_f64(self) -> f64 {
        self
    }
    #[inline]
    fn abs(self) -> Self {
        f64::abs(self)
    }
    #[inline]
    fn sqrt(self) -> Self {
        f64::sqrt(self)
    }
    #[inline]
    fn recip(self) -> Self {
        f64::recip(self)
    }
    #[inline]
    fn powi(self, n: i32) -> Self {
        f64::powi(self, n)
    }
    #[inline]
    fn sin(self) -> Self {
        f64::sin(self)
    }
    #[inline]
    fn cos(self) -> Self {
        f64::cos(self)
    }
    #[inline]
    fn tan(self) -> Self {
        f64::tan(self)
    }
    #[inline]
    fn asin(self) -> Self {
        f64::asin(self)
    }
    #[inline]
    fn acos(self) -> Self {
        f64::acos(self)
    }
    #[inline]
    fn atan2(self, x: Self) -> Self {
        f64::atan2(self, x)
    }
    #[inline]
    fn exp(self) -> Self {
        f64::exp(self)
    }
    #[inline]
    fn ln(self) -> Self {
        f64::ln(self)
    }
    #[inline]
    fn is_finite(self) -> bool {
        f64::is_finite(self)
    }
}
