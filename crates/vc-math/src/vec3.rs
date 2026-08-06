//! Three-dimensional vectors.
//!
//! **Coordinate convention.** Right-handed, **Z up**: `+x` east, `+y` north,
//! `+z` against gravity. Lengths are metres. This is the convention terrain,
//! survey and structural data arrive in, and the core is the layer that has to
//! agree with them. Godot is Y-up with `-z` forward, so the renderer binding
//! converts at the boundary — one place, not scattered.

use core::ops::{Add, AddAssign, Div, Mul, Neg, Sub, SubAssign};

use crate::scalar::Scalar;

/// A vector in three dimensions.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Vec3<T: Scalar> {
    /// East.
    pub x: T,
    /// North.
    pub y: T,
    /// Up.
    pub z: T,
}

impl<T: Scalar> Vec3<T> {
    /// A vector from its components.
    #[inline]
    pub const fn new(x: T, y: T, z: T) -> Self {
        Self { x, y, z }
    }

    /// The zero vector.
    pub const ZERO: Self = Self::new(T::ZERO, T::ZERO, T::ZERO);
    /// The east-pointing unit vector.
    pub const X: Self = Self::new(T::ONE, T::ZERO, T::ZERO);
    /// The north-pointing unit vector.
    pub const Y: Self = Self::new(T::ZERO, T::ONE, T::ZERO);
    /// The upward unit vector.
    pub const Z: Self = Self::new(T::ZERO, T::ZERO, T::ONE);

    /// A vector from three `f64` components.
    #[inline]
    pub fn from_f64(x: f64, y: f64, z: f64) -> Self {
        Self::new(T::from_f64(x), T::from_f64(y), T::from_f64(z))
    }

    /// The dot product.
    #[inline]
    pub fn dot(self, rhs: Self) -> T {
        self.x * rhs.x + self.y * rhs.y + self.z * rhs.z
    }

    /// The cross product, right-handed.
    #[inline]
    pub fn cross(self, rhs: Self) -> Self {
        Self::new(
            self.y * rhs.z - self.z * rhs.y,
            self.z * rhs.x - self.x * rhs.z,
            self.x * rhs.y - self.y * rhs.x,
        )
    }

    /// The squared length. Cheaper than [`Self::norm`] and differentiable at
    /// the origin, so prefer it wherever the square root is not needed.
    #[inline]
    pub fn norm_squared(self) -> T {
        self.dot(self)
    }

    /// The length. Not differentiable at the origin.
    #[inline]
    pub fn norm(self) -> T {
        self.norm_squared().sqrt()
    }

    /// The vector scaled to unit length.
    ///
    /// The caller is responsible for the vector being non-zero; a zero vector
    /// yields NaN rather than an error, because this sits inside the
    /// integration loop where a branch per call is not worth paying for.
    #[inline]
    pub fn normalized(self) -> Self {
        self / self.norm()
    }

    /// Linear interpolation, `t = 0` giving `self`.
    #[inline]
    pub fn lerp(self, other: Self, t: T) -> Self {
        self + (other - self) * t
    }

    /// The vector rotated about a unit `axis` by `angle` radians, right-handed
    /// (Rodrigues' rotation formula).
    ///
    /// `axis` must already be normalised.
    #[inline]
    pub fn rotate_about(self, axis: Self, angle: T) -> Self {
        let (s, c) = angle.sin_cos();
        self * c + axis.cross(self) * s + axis * (axis.dot(self) * (T::ONE - c))
    }

    /// The vector with each component converted to `f64`, discarding
    /// derivatives. For reporting and interop.
    #[inline]
    pub fn to_f64(self) -> [f64; 3] {
        [self.x.to_f64(), self.y.to_f64(), self.z.to_f64()]
    }
}

impl<T: Scalar> Add for Vec3<T> {
    type Output = Self;
    #[inline]
    fn add(self, rhs: Self) -> Self {
        Self::new(self.x + rhs.x, self.y + rhs.y, self.z + rhs.z)
    }
}

impl<T: Scalar> Sub for Vec3<T> {
    type Output = Self;
    #[inline]
    fn sub(self, rhs: Self) -> Self {
        Self::new(self.x - rhs.x, self.y - rhs.y, self.z - rhs.z)
    }
}

impl<T: Scalar> Neg for Vec3<T> {
    type Output = Self;
    #[inline]
    fn neg(self) -> Self {
        Self::new(-self.x, -self.y, -self.z)
    }
}

impl<T: Scalar> Mul<T> for Vec3<T> {
    type Output = Self;
    #[inline]
    fn mul(self, k: T) -> Self {
        Self::new(self.x * k, self.y * k, self.z * k)
    }
}

impl<T: Scalar> Div<T> for Vec3<T> {
    type Output = Self;
    #[inline]
    fn div(self, k: T) -> Self {
        Self::new(self.x / k, self.y / k, self.z / k)
    }
}

impl<T: Scalar> AddAssign for Vec3<T> {
    #[inline]
    fn add_assign(&mut self, rhs: Self) {
        *self = *self + rhs;
    }
}

impl<T: Scalar> SubAssign for Vec3<T> {
    #[inline]
    fn sub_assign(&mut self, rhs: Self) {
        *self = *self - rhs;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dual::Dual;
    use core::f64::consts::FRAC_PI_2;

    type V = Vec3<f64>;

    fn close(a: V, b: V) {
        assert!((a - b).norm() < 1e-12, "{a:?} vs {b:?}");
    }

    #[test]
    fn axes_are_right_handed() {
        close(V::X.cross(V::Y), V::Z);
        close(V::Y.cross(V::Z), V::X);
        close(V::Z.cross(V::X), V::Y);
    }

    #[test]
    fn rotation_about_z_turns_east_to_north() {
        close(V::X.rotate_about(V::Z, FRAC_PI_2), V::Y);
    }

    #[test]
    fn rotation_preserves_length_and_the_axis() {
        let axis = V::new(1.0, -2.0, 0.5).normalized();
        let v = V::new(3.0, 1.0, -4.0);
        let r = v.rotate_about(axis, 0.9);
        assert!((r.norm() - v.norm()).abs() < 1e-12);
        // The component along the axis is unchanged by the rotation.
        assert!((r.dot(axis) - v.dot(axis)).abs() < 1e-12);
        close(axis.rotate_about(axis, 0.9), axis);
    }

    #[test]
    fn rotation_composes() {
        let axis = V::new(0.2, 0.3, 0.9).normalized();
        let v = V::new(1.0, 2.0, 3.0);
        close(
            v.rotate_about(axis, 0.4).rotate_about(axis, 0.7),
            v.rotate_about(axis, 1.1),
        );
    }

    #[test]
    fn norm_carries_derivatives() {
        // |(x, 3, 4)| at x = 0 has zero derivative; at x = 1 it is 1/sqrt(26).
        let at = |x: f64| Vec3::new(Dual::variable(x), Dual::constant(3.0), Dual::constant(4.0));
        assert!(at(0.0).norm().du.abs() < 1e-12);
        assert!((at(1.0).norm().du - 1.0 / 26.0_f64.sqrt()).abs() < 1e-12);
    }
}
