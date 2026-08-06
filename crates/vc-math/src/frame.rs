//! Orientation along the track: rotation-minimising frames.
//!
//! A ride needs an orientation at every point of the heartline — the axis the
//! train rolls about, and where "up" and "the rider's right" point. The
//! textbook answer is the Frenet frame, built from the curve's own derivatives,
//! and it is the wrong answer here for two reasons.
//!
//! First, the Frenet normal is undefined wherever curvature is zero, and a
//! coaster is full of straight track: launches, brake runs, the top of a
//! perfectly-shaped hill. Second, at an inflection — the transition from a
//! left turn to a right turn, which happens several times a ride — the Frenet
//! normal flips through 180° instantaneously. Neither is a numerical
//! inconvenience to be smoothed over; they are places where the frame simply
//! does not exist.
//!
//! The frame used instead is *rotation-minimising*: it is carried along the
//! curve by rotating only as much as the tangent itself rotates, and never
//! about the tangent. It is defined everywhere, including on straight track,
//! and it changes continuously through inflections. Bank is then applied on
//! top of it as an explicit roll — which is what a track designer means by
//! bank anyway, and what makes roll rate something the solver can constrain
//! directly rather than infer.
//!
//! [`Frame`] is carried as state through the evaluator's integration rather
//! than recomputed per point, so it costs a rotation per step and nothing else.

use crate::scalar::Scalar;
use crate::vec3::Vec3;

/// An orthonormal orientation: where the track is heading, and which way is up
/// for the rider.
///
/// The invariant is `right = tangent × up`, with all three of unit length and
/// mutually perpendicular. Note that the *right-handed* ordering of the basis
/// is `(right, tangent, up)`, which is what to feed a rotation matrix.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Frame<T: Scalar> {
    /// Direction of travel.
    pub tangent: Vec3<T>,
    /// The rider's right.
    pub right: Vec3<T>,
    /// The rider's up — the track normal, not world up.
    pub up: Vec3<T>,
}

impl<T: Scalar> Frame<T> {
    /// Below this sine of the turn angle, a transport step is treated as
    /// leaving the tangent unchanged. At 1e-9 the discarded rotation is far
    /// under the orthonormalisation error it would introduce.
    const PARALLEL_EPS: f64 = 1e-9;

    /// A frame from three vectors already known to satisfy the invariant.
    #[inline]
    pub const fn new_unchecked(tangent: Vec3<T>, right: Vec3<T>, up: Vec3<T>) -> Self {
        Self { tangent, right, up }
    }

    /// The frame heading along `tangent` whose up is as close to `up_hint` as
    /// perpendicularity allows.
    ///
    /// This is for *starting* a frame — at the station, or at a segment
    /// boundary in a multiple-shooting solve. It fails where the track is
    /// parallel to the hint, which for a world-up hint means vertical track:
    /// a launch into a top hat has exactly that. Along a ride the frame should
    /// be carried with [`Self::transport_to`] instead, which has no such
    /// degeneracy.
    #[inline]
    pub fn from_tangent_and_up_hint(tangent: Vec3<T>, up_hint: Vec3<T>) -> Self {
        let tangent = tangent.normalized();
        let up = (up_hint - tangent * tangent.dot(up_hint)).normalized();
        Self {
            tangent,
            right: tangent.cross(up),
            up,
        }
    }

    /// The frame with world up as its hint. Convenient for level track.
    #[inline]
    pub fn level(tangent: Vec3<T>) -> Self {
        Self::from_tangent_and_up_hint(tangent, Vec3::Z)
    }

    /// This frame carried onto a new tangent direction, rotating as little as
    /// possible.
    ///
    /// The rotation applied is the minimal one taking the old tangent to the
    /// new: about their common perpendicular, by the angle between them. No
    /// rotation about the tangent is introduced, which is what "rotation
    /// minimising" means and why accumulated bank stays under the caller's
    /// control.
    ///
    /// `new_tangent` need not be normalised. Consecutive tangents must not be
    /// antiparallel — a step that reverses direction of travel is a bug in the
    /// caller, and is caught by a debug assertion.
    #[inline]
    pub fn transport_to(self, new_tangent: Vec3<T>) -> Self {
        let t1 = new_tangent.normalized();
        let cross = self.tangent.cross(t1);
        let sin = cross.norm();
        let cos = self.tangent.dot(t1);

        if sin <= T::from_f64(Self::PARALLEL_EPS) {
            debug_assert!(
                cos > T::ZERO,
                "direction of travel reversed within one transport step"
            );
            return Self {
                tangent: t1,
                ..self
            };
        }

        let axis = cross / sin;
        let angle = sin.atan2(cos);
        Self {
            tangent: t1,
            right: self.right.rotate_about(axis, angle),
            up: self.up.rotate_about(axis, angle),
        }
        .orthonormalized()
    }

    /// This frame rolled about its own tangent by `angle` radians,
    /// right-handed about the direction of travel.
    ///
    /// Right-handed about `+tangent` tilts the rider's up towards the rider's
    /// *right*, which is the bank of a **left**-hand turn.
    #[inline]
    pub fn rolled(self, angle: T) -> Self {
        Self {
            tangent: self.tangent,
            right: self.right.rotate_about(self.tangent, angle),
            up: self.up.rotate_about(self.tangent, angle),
        }
    }

    /// This frame with rounding drift removed.
    ///
    /// Applied after every transport step. Over the tens of thousands of steps
    /// in a 4 km ride, an un-corrected frame loses orthogonality steadily, and
    /// a frame that is not orthonormal reports forces in a basis that is not
    /// the rider's.
    #[inline]
    pub fn orthonormalized(self) -> Self {
        let tangent = self.tangent.normalized();
        let up = (self.up - tangent * tangent.dot(self.up)).normalized();
        Self {
            tangent,
            right: tangent.cross(up),
            up,
        }
    }

    /// How far this frame departs from orthonormality — zero for an exact
    /// frame. A diagnostic, not used in the hot path.
    #[inline]
    pub fn orthonormality_error(self) -> T {
        let mut worst = T::ZERO;
        for e in [
            self.tangent.norm_squared() - T::ONE,
            self.right.norm_squared() - T::ONE,
            self.up.norm_squared() - T::ONE,
            self.tangent.dot(self.right),
            self.tangent.dot(self.up),
            self.right.dot(self.up),
            (self.tangent.cross(self.up) - self.right).norm(),
        ] {
            worst = worst.max(e.abs());
        }
        worst
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dual::Dual;
    use core::f64::consts::{FRAC_PI_2, PI, TAU};

    type V = Vec3<f64>;
    type F = Frame<f64>;

    #[test]
    fn level_frame_faces_the_right_way() {
        let f = F::level(V::X);
        assert!((f.up - V::Z).norm() < 1e-15);
        // Facing east with up as up, the rider's right is south.
        assert!((f.right - -V::Y).norm() < 1e-15);
        assert!(f.orthonormality_error() < 1e-15);
    }

    #[test]
    fn transport_around_a_planar_circle_keeps_up_fixed() {
        // A flat circular turn in the xy-plane. A rotation-minimising frame
        // introduces no bank, so up must stay exactly world up all the way
        // round: any drift is spurious roll the solver would have to chase.
        let steps = 2000;
        let mut frame = F::level(V::X);
        for i in 1..=steps {
            let a = TAU * f64::from(i) / f64::from(steps);
            frame = frame.transport_to(V::new(a.cos(), a.sin(), 0.0));
        }
        assert!(
            (frame.up - V::Z).norm() < 1e-12,
            "up drifted: {:?}",
            frame.up
        );
        // A closed planar curve returns the frame exactly to where it started.
        assert!((frame.tangent - V::X).norm() < 1e-12);
        assert!((frame.right - -V::Y).norm() < 1e-12);
    }

    #[test]
    fn transport_stays_orthonormal_along_a_helix() {
        // Radius 20 m, 8 m of climb per turn — a helix steep enough that the
        // tangent sweeps well out of the horizontal plane.
        let steps = 20_000;
        let turns = 6.0;
        let tangent_at = |a: f64| V::new(-20.0 * a.sin(), 20.0 * a.cos(), 8.0 / TAU).normalized();
        let mut frame = F::level(tangent_at(0.0));
        let mut worst = 0.0_f64;
        for i in 1..=steps {
            let a = turns * TAU * f64::from(i) / f64::from(steps);
            frame = frame.transport_to(tangent_at(a));
            worst = worst.max(frame.orthonormality_error());
            assert!(frame.tangent.dot(frame.up).abs() < 1e-12);
        }
        assert!(worst < 1e-12, "orthonormality error {worst}");
    }

    #[test]
    fn transport_through_an_inflection_is_continuous() {
        // A non-planar wiggle whose curvature passes through zero: the case
        // where the Frenet normal is undefined and then flips through 180°.
        // The rotation-minimising frame must cross it without noticing.
        let tangent_at = |s: f64| V::new(1.0, 0.5 * s.sin(), 0.3 * (2.0 * s).sin()).normalized();
        let mut frame = F::level(tangent_at(-0.5));
        let mut previous = frame;
        let steps = 1000;
        for i in 1..=steps {
            let s = -0.5 + f64::from(i) / f64::from(steps);
            frame = frame.transport_to(tangent_at(s));
            // No step may swing the frame more than a small fraction of a turn.
            assert!(
                frame.up.dot(previous.up) > 0.999,
                "frame jumped at s = {s}: {:?} -> {:?}",
                previous.up,
                frame.up
            );
            previous = frame;
        }
    }

    #[test]
    fn transport_is_a_no_op_when_the_tangent_does_not_change() {
        let f = F::level(V::new(1.0, 2.0, 3.0)).rolled(0.7);
        let g = f.transport_to(f.tangent);
        assert!(f.orthonormality_error() < 1e-15);
        assert!((f.up - g.up).norm() < 1e-15);
        assert!((f.right - g.right).norm() < 1e-15);
    }

    #[test]
    fn roll_is_right_handed_about_the_direction_of_travel() {
        let f = F::level(V::X).rolled(FRAC_PI_2);
        // A quarter turn right-handed about east takes up onto the rider's
        // original right, which was south.
        assert!((f.up - -V::Y).norm() < 1e-12, "{:?}", f.up);
        assert!(f.orthonormality_error() < 1e-14);
    }

    #[test]
    fn roll_composes_and_a_full_turn_is_identity() {
        let f = F::level(V::new(0.3, 1.0, 0.2));
        let a = f.rolled(0.6).rolled(0.9);
        let b = f.rolled(1.5);
        assert!((a.up - b.up).norm() < 1e-12);
        assert!((f.rolled(TAU).up - f.up).norm() < 1e-12);
        assert!((f.rolled(PI).up + f.up).norm() < 1e-12);
    }

    #[test]
    fn orthonormalize_repairs_a_perturbed_frame() {
        let bad = Frame::new_unchecked(
            V::new(1.0, 0.01, 0.0),
            V::new(0.02, -1.0, 0.0),
            V::new(0.0, 0.03, 1.0),
        );
        assert!(bad.orthonormality_error() > 1e-3);
        assert!(bad.orthonormalized().orthonormality_error() < 1e-15);
    }

    #[test]
    fn frames_carry_derivatives() {
        // Roll by angle a: d(up)/da at a = 0 is the rider's right, since a
        // right-handed roll tips up towards right.
        let f = Frame::<Dual>::level(Vec3::from_f64(1.0, 0.0, 0.0));
        let rolled = f.rolled(Dual::variable(0.0));
        assert!((rolled.up.y.du - f.right.y.re).abs() < 1e-12);
        assert!(rolled.up.z.du.abs() < 1e-12);
    }
}
