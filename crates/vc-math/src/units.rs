//! Units.
//!
//! **The convention: every number inside the core is SI.** Metres, seconds,
//! kilograms, radians, and the units derived from them. There are no
//! kilometres per hour, no feet and no degrees below the interface layer, and
//! no quantity is ever stored in "g".
//!
//! This is enforced by discipline and naming rather than by the type system.
//! Wrapping every quantity in a dimensioned newtype is possible in Rust, but
//! combined with the [`Scalar`] genericity it produces a large, noisy surface
//! — every operator overload doubled, every generic bound doubled — for a
//! guarantee that a single consistent convention already buys. If unit
//! confusion turns out to cause real bugs later, this is the module that
//! becomes the newtypes.
//!
//! The conversions here exist for the boundaries: reading a spec written in
//! human units, and reporting results in them. They are generic so that
//! converted quantities keep their derivatives.

use crate::scalar::Scalar;

/// Standard gravity, m/s². The value fixed by BIPM, not a local measurement.
pub const G0: f64 = 9.806_65;

/// One international foot, in metres. Exact by definition.
pub const FOOT: f64 = 0.3048;

/// One statute mile, in metres. Exact by definition.
pub const MILE: f64 = 1609.344;

/// Standard gravity as a scalar.
#[inline]
pub fn g0<T: Scalar>() -> T {
    T::from_f64(G0)
}

/// Kilometres per hour to metres per second.
#[inline]
pub fn from_km_h<T: Scalar>(v: T) -> T {
    v / T::from_f64(3.6)
}

/// Metres per second to kilometres per hour.
#[inline]
pub fn to_km_h<T: Scalar>(v: T) -> T {
    v * T::from_f64(3.6)
}

/// Miles per hour to metres per second.
#[inline]
pub fn from_mph<T: Scalar>(v: T) -> T {
    v * T::from_f64(MILE / 3600.0)
}

/// Metres per second to miles per hour.
#[inline]
pub fn to_mph<T: Scalar>(v: T) -> T {
    v / T::from_f64(MILE / 3600.0)
}

/// Feet to metres.
#[inline]
pub fn from_feet<T: Scalar>(x: T) -> T {
    x * T::from_f64(FOOT)
}

/// Metres to feet.
#[inline]
pub fn to_feet<T: Scalar>(x: T) -> T {
    x / T::from_f64(FOOT)
}

/// Multiples of standard gravity to metres per second squared.
#[inline]
pub fn from_g<T: Scalar>(a: T) -> T {
    a * T::from_f64(G0)
}

/// Metres per second squared to multiples of standard gravity.
#[inline]
pub fn to_g<T: Scalar>(a: T) -> T {
    a / T::from_f64(G0)
}

/// Degrees to radians.
#[inline]
pub fn from_degrees<T: Scalar>(a: T) -> T {
    a * T::from_f64(core::f64::consts::PI / 180.0)
}

/// Radians to degrees.
#[inline]
pub fn to_degrees<T: Scalar>(a: T) -> T {
    a * T::from_f64(180.0 / core::f64::consts::PI)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn close(a: f64, b: f64) {
        assert!((a - b).abs() < 1e-12, "{a} vs {b}");
    }

    #[test]
    fn conversions_round_trip() {
        for &x in &[0.0_f64, 1.0, 42.5, -7.25] {
            close(to_km_h(from_km_h(x)), x);
            close(to_mph(from_mph(x)), x);
            close(to_feet(from_feet(x)), x);
            close(to_g(from_g(x)), x);
            close(to_degrees(from_degrees(x)), x);
        }
    }

    #[test]
    fn known_values() {
        // 100 km/h is 27.7... m/s.
        close(from_km_h(100.0), 100.0 / 3.6);
        // Falcon's Flight is quoted at 250 km/h; that is a shade under 156 mph.
        let v = from_km_h(250.0);
        assert!((to_mph(v) - 155.34).abs() < 0.01, "{}", to_mph(v));
        // 640 ft is a bit over 195 m.
        assert!((from_feet(640.0) - 195.07).abs() < 0.01);
        close(from_degrees(180.0), core::f64::consts::PI);
    }
}
