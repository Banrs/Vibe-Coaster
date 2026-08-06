//! Ordinary differential equation integration.
//!
//! **Fixed step, deliberately.** Adaptive step-size control is the usual
//! default and it is the wrong default here, for two reasons that both matter
//! more than the efficiency it buys.
//!
//! The first is differentiability. An adaptive integrator decides where to put
//! its steps by comparing an error estimate against a threshold, and those
//! decisions are discontinuous functions of the parameters being solved for.
//! Nudge a launch speed by a millimetre per second and the integrator may take
//! one more step somewhere, moving the answer by a hair for reasons unrelated
//! to the physics. Differentiate through that and the gradient carries the
//! noise; the global solve then sees a jagged objective and stalls.
//!
//! The second is reproducibility. The same ride model must produce the same
//! ride every time and on every machine. A fixed step count makes the sequence
//! of arithmetic operations a function of the model alone.
//!
//! Choosing the step count is therefore an offline decision, made once per kind
//! of problem with [`richardson_error`] and then written down — not a decision
//! the integrator makes while the solver is watching.

use crate::scalar::Scalar;

/// A state vector that can be advanced by an integrator.
///
/// Deliberately minimal: the only things a Runge–Kutta step needs are the
/// ability to accumulate a scaled derivative, and — for error estimation — a
/// way to compare two states.
pub trait State<T: Scalar>: Copy {
    /// `self + k * d`.
    fn add_scaled(self, k: T, d: Self) -> Self;

    /// The largest absolute difference between corresponding components.
    fn max_abs_diff(self, other: Self) -> T;
}

impl<T: Scalar, const N: usize> State<T> for [T; N] {
    #[inline]
    fn add_scaled(self, k: T, d: Self) -> Self {
        let mut out = self;
        for (o, &di) in out.iter_mut().zip(d.iter()) {
            *o += k * di;
        }
        out
    }

    #[inline]
    fn max_abs_diff(self, other: Self) -> T {
        self.iter()
            .zip(other.iter())
            .fold(T::ZERO, |worst, (&a, &b)| worst.max((a - b).abs()))
    }
}

/// One classical fourth-order Runge–Kutta step of size `h`, from `(x, y)`.
///
/// `f` is the derivative `dy/dx` as a function of the independent variable and
/// the state. For this project `x` is arclength along the track, not time.
#[inline]
pub fn rk4_step<T, S, F>(f: &F, x: T, y: S, h: T) -> S
where
    T: Scalar,
    S: State<T>,
    F: Fn(T, S) -> S,
{
    let half = T::from_f64(0.5);
    let sixth = T::from_f64(1.0 / 6.0);
    let third = T::from_f64(1.0 / 3.0);

    let k1 = f(x, y);
    let k2 = f(x + h * half, y.add_scaled(h * half, k1));
    let k3 = f(x + h * half, y.add_scaled(h * half, k2));
    let k4 = f(x + h, y.add_scaled(h, k3));

    y.add_scaled(h * sixth, k1)
        .add_scaled(h * third, k2)
        .add_scaled(h * third, k3)
        .add_scaled(h * sixth, k4)
}

/// Integrates from `x0` to `x1` in exactly `steps` equal steps, returning the
/// final state.
///
/// `steps` of zero returns `y0` unchanged.
#[inline]
pub fn rk4<T, S, F>(f: &F, x0: T, y0: S, x1: T, steps: usize) -> S
where
    T: Scalar,
    S: State<T>,
    F: Fn(T, S) -> S,
{
    rk4_sampled(f, x0, y0, x1, steps, |_, _| {})
}

/// As [`rk4`], but calls `sample` with every state along the way, starting with
/// the initial one and ending with the final one.
///
/// This is how the evaluator records a ride: forces and clearances are wanted
/// at every station along the track, not only at the brake run.
pub fn rk4_sampled<T, S, F, G>(f: &F, x0: T, y0: S, x1: T, steps: usize, mut sample: G) -> S
where
    T: Scalar,
    S: State<T>,
    F: Fn(T, S) -> S,
    G: FnMut(T, S),
{
    sample(x0, y0);
    if steps == 0 {
        return y0;
    }
    let h = (x1 - x0) / T::from_f64(steps as f64);
    let mut y = y0;
    for i in 0..steps {
        // Recomputed from `x0` rather than accumulated, so rounding does not
        // drift over the tens of thousands of steps in a long ride.
        let x = x0 + h * T::from_f64(i as f64);
        y = rk4_step(f, x, y, h);
        sample(x + h, y);
    }
    y
}

/// How much the answer moves when the step count is doubled.
///
/// A diagnostic for choosing a step count offline. For a fourth-order method
/// the true error is about one fifteenth of this figure, so a run whose
/// doubling changes the answer by a millimetre is resolved to well under that.
/// Never call this from inside the evaluator: using it to decide anything at
/// solve time reintroduces exactly the parameter-dependent branching that fixed
/// steps exist to avoid.
pub fn richardson_error<T, S, F>(f: &F, x0: T, y0: S, x1: T, steps: usize) -> T
where
    T: Scalar,
    S: State<T>,
    F: Fn(T, S) -> S,
{
    let coarse = rk4(f, x0, y0, x1, steps);
    let fine = rk4(f, x0, y0, x1, steps * 2);
    coarse.max_abs_diff(fine)
}

#[cfg(test)]
mod tests {
    // Integrating zero steps must return the state untouched, bit for bit —
    // exact comparison is the point of that assertion.
    #![allow(clippy::float_cmp)]

    use super::*;
    use crate::dual::Dual;

    /// dy/dx = y, y(0) = 1. The answer is e^x.
    fn exponential<T: Scalar>(_x: T, y: [T; 1]) -> [T; 1] {
        y
    }

    /// A unit harmonic oscillator as a first-order system: y'' = -y.
    fn oscillator<T: Scalar>(_x: T, y: [T; 2]) -> [T; 2] {
        [y[1], -y[0]]
    }

    #[test]
    fn exponential_growth_is_integrated_correctly() {
        // A thousand steps over unit distance puts the fourth-order truncation
        // error near the floor of what f64 can hold onto.
        let got = rk4(&exponential, 0.0, [1.0], 1.0, 1000)[0];
        assert!((got - core::f64::consts::E).abs() < 1e-12, "{got}");
    }

    #[test]
    fn the_method_is_fourth_order() {
        // Halving the step should cut the error by about sixteen. Measured
        // over a range where rounding has not yet taken over.
        let exact = core::f64::consts::E;
        let error = |n| (rk4(&exponential, 0.0, [1.0], 1.0, n)[0] - exact).abs();
        for &n in &[4_usize, 8, 16] {
            let ratio = error(n) / error(n * 2);
            assert!((12.0..20.0).contains(&ratio), "n = {n}: ratio {ratio}");
        }
    }

    #[test]
    fn the_oscillator_keeps_its_energy_over_many_cycles() {
        // Twenty cycles at 200 steps each. Energy drift is the honest measure
        // of whether an integrator is fit for a long ride.
        let cycles = 20.0;
        let end = cycles * core::f64::consts::TAU;
        let y = rk4(&oscillator, 0.0, [1.0, 0.0], end, 200 * 20);
        let energy = y[0] * y[0] + y[1] * y[1];
        // Under a part in ten million of amplitude lost over twenty cycles,
        // and the phase still lands on the crest.
        assert!((energy - 1.0).abs() < 1e-7, "energy {energy}");
        assert!((y[0] - 1.0).abs() < 1e-4, "phase drifted: {}", y[0]);
    }

    #[test]
    fn zero_steps_changes_nothing() {
        assert_eq!(rk4(&exponential, 0.0, [3.0], 1.0, 0)[0], 3.0);
    }

    #[test]
    fn sampling_visits_every_step_including_both_ends() {
        let mut xs = Vec::new();
        let mut ys = Vec::new();
        rk4_sampled(&exponential, 0.0, [1.0], 1.0, 4, |x, y| {
            xs.push(x);
            ys.push(y[0]);
        });
        assert_eq!(xs.len(), 5);
        assert!((xs[0] - 0.0).abs() < 1e-15);
        assert!((xs[4] - 1.0).abs() < 1e-15);
        assert!((ys[0] - 1.0).abs() < 1e-15);
        // Each sample matches the exact solution at its own x — loosely, since
        // four steps across the whole interval is a coarse integration; the
        // point of the test is that the samples are the states, not endpoints
        // of some other calculation.
        for (&x, &y) in xs.iter().zip(ys.iter()) {
            assert!((y - x.exp()).abs() < 1e-4, "at {x}: {y}");
        }
    }

    #[test]
    fn richardson_error_falls_as_the_step_count_rises() {
        let coarse = richardson_error(&exponential, 0.0, [1.0], 1.0, 8);
        let fine = richardson_error(&exponential, 0.0, [1.0], 1.0, 32);
        assert!(coarse > fine * 100.0, "coarse {coarse}, fine {fine}");
    }

    #[test]
    fn integration_is_bit_for_bit_repeatable() {
        let a = rk4(&oscillator, 0.0, [1.0, 0.0], 13.7, 5000);
        let b = rk4(&oscillator, 0.0, [1.0, 0.0], 13.7, 5000);
        assert_eq!(a[0].to_bits(), b[0].to_bits());
        assert_eq!(a[1].to_bits(), b[1].to_bits());
    }

    #[test]
    fn integration_carries_derivatives() {
        // y' = a*y, y(0) = 1 gives y(1) = e^a, so dy/da at a = 1 is e.
        let a = Dual::variable(1.0);
        let f = move |_x: Dual, y: [Dual; 1]| [y[0] * a];
        let y = rk4(
            &f,
            Dual::constant(0.0),
            [Dual::constant(1.0)],
            Dual::constant(1.0),
            200,
        );
        assert!((y[0].re - core::f64::consts::E).abs() < 1e-9);
        assert!((y[0].du - core::f64::consts::E).abs() < 1e-8, "{}", y[0].du);
    }
}
