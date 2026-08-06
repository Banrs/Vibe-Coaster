//! The ride: the model, the evaluator that runs it, and the solve that
//! determines it.
//!
//! - [`model`] — what a ride is, as data
//! - [`preset`] — the one ride, and the rulebook it is judged against
//! - [`eval`] — force profile in, ride out. A pure function
//! - [`analysis`] — judging a ride against the envelope, the ground and the
//!   pacing it was asked for
//! - [`solve`] — one constrained solve over every free parameter at once
//! - [`export`] — the solved ride as JSON, for the viewer

pub mod analysis;
pub mod eval;
pub mod export;
pub mod model;
pub mod preset;
pub mod solve;

pub use eval::{Ride, Sample, evaluate};
pub use model::RideModel;
