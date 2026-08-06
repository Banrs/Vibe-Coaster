//! Math foundations for Vibe-Coaster.
//!
//! Everything here is below the ride model: no element knows about a coaster,
//! and nothing in this crate makes a design decision. It exists so that the
//! layers above it — the evaluator, and then the solve — can be written in
//! terms of the right primitives rather than reinventing them mid-derivation.
//!
//! Two choices run through the whole crate and are worth knowing before reading
//! any of it.
//!
//! **Generic over the scalar.** No function takes `f64`. They take
//! [`Scalar`], which `f64` implements and so does [`Dual`], the forward-mode
//! automatic-differentiation number. The global solve wants exact derivatives
//! of the evaluator; substituting the scalar is how it gets them, and doing so
//! only works if the genericity goes all the way down.
//!
//! **Deterministic by construction.** Fixed quadrature order, fixed panel
//! counts, fixed integration steps, no adaptivity anywhere. Same inputs, same
//! arithmetic, same answer — which is what makes regression tests against real
//! ride data meaningful, and what keeps the solver from chasing noise that is
//! an artefact of the numerics rather than the physics.
//!
//! ## Layout
//!
//! - [`scalar`] — the numeric trait everything is written against
//! - [`dual`] — forward-mode automatic differentiation
//! - [`units`] — the SI convention, and conversions for the boundaries
//! - [`vec3`] — vectors, and the coordinate convention
//! - [`frame`] — rotation-minimising orientation along the track
//! - [`curve`] — parametric space curves
//! - [`quadrature`] — Gauss–Legendre integration of a scalar function
//! - [`mod@arclength`] — measuring a curve in metres, and inverting that
//! - [`integrate`] — fixed-step Runge–Kutta

pub mod arclength;
pub mod curve;
pub mod dual;
pub mod frame;
pub mod integrate;
pub mod quadrature;
pub mod scalar;
pub mod units;
pub mod vec3;

pub use arclength::{ArcTable, arclength};
pub use curve::{Curve, HermiteCurve, HermiteSegment};
pub use dual::Dual;
pub use frame::Frame;
pub use integrate::{State, rk4, rk4_sampled, rk4_step};
pub use quadrature::{composite_gauss_legendre, gauss_legendre};
pub use scalar::Scalar;
pub use vec3::Vec3;
