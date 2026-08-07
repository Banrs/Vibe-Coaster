//! One solve, over every free parameter, satisfying everything at once.
//!
//! Forward integration alone cannot close a circuit — it lands where it lands.
//! The usual fix is a chain of correction passes, and that is exactly what
//! turns a generator into a pile of modifiers. Everything adjustable is
//! therefore adjusted here, together: station closure, the height the human
//! pinned, the speeds the infrastructure was asked for, the force envelope, and
//! the ground.
//!
//! ## What it optimises
//!
//! Closure and the pinned outcomes are about a dozen equations; the preset has
//! twenty-five free parameters; the envelope and clearance are inequalities
//! that carve out a region rather than pinning a point. The feasible set is a
//! manifold, so something has to choose a point on it, and that choice is a
//! design decision rather than a mathematical one.
//!
//! The choice made here is **stay closest to the ride as described**: a small
//! residual pulls every parameter back towards the value the spec gave it,
//! scaled by how far it is allowed to roam. That keeps the spec a steering
//! wheel — nudge an element and the ride changes there, not everywhere. It is
//! a term in the same least-squares problem, not a pass afterwards, so
//! swapping it for "maximise pacing" or "minimise cost" later is a change of
//! one function, not of the architecture.
//!
//! ## Naming the failure
//!
//! A global solve fails by not converging, and an unconverged solve that only
//! says "failed" is nearly useless. Every residual carries a name, and the
//! report ends with the worst offenders in order, so the answer to "why didn't
//! it close" is a sentence rather than an investigation.

use vc_math::{Dual, Scalar};

use crate::analysis::analyse;
use crate::eval::{ElementResult, Ride, evaluate};
use crate::model::{Pin, RideModel};

/// Weights putting every residual on a comparable footing, so that no
/// constraint dominates the solve for a reason as arbitrary as its units.
///
/// Each is roughly "one unit of residual per amount of error we would just
/// about accept".
mod weight {
    /// Per metre of station closure error.
    pub const POSITION: f64 = 2.0;
    /// Per unit of unit-tangent mismatch — about one per degree.
    pub const HEADING: f64 = 60.0;
    /// Per unit of frame roll at the station.
    pub const BANK: f64 = 60.0;
    /// Per metre a pinned rise or drop is missed by.
    pub const PIN: f64 = 1.0;
    /// Per m/s the infrastructure fails to deliver.
    pub const SPEED: f64 = 3.0;
    /// Per m/s the ride's average speed falls short of the pacing target.
    /// One-sided — running faster than asked costs nothing.
    pub const PACE: f64 = 2.0;
    /// Per degree a structural demand — exit pitch, net turn — is missed by.
    ///
    /// Comparable to the closure weights, deliberately. Set light, the solve
    /// simply spends the layout: at 0.5 it span a brake run through 1,760
    /// degrees and left a hill climbing at 47 to buy closure it never got.
    pub const STRUCTURE: f64 = 3.0;
    /// Per unit over a comfort or clearance limit. Heavy: these are the
    /// constraints that must not be traded away.
    pub const PENALTY: f64 = 50.0;
    /// Per unit of a parameter's range that it has drifted from the spec.
    /// Light: this only picks between rides that already satisfy everything.
    pub const REGULARISATION: f64 = 0.10;
}

/// How the solve went.
#[derive(Clone, Debug)]
pub struct Report {
    /// Whether every hard residual came in under tolerance.
    pub converged: bool,
    /// Iterations used.
    pub iterations: usize,
    /// Final half-sum-of-squares.
    pub cost: f64,
    /// Solved free parameters.
    pub parameters: Vec<f64>,
    /// The residuals that are still largest, worst first.
    pub worst: Vec<(String, f64)>,
}

impl Report {
    /// A short human-readable account, including which constraint is unhappy.
    pub fn summary(&self) -> String {
        let mut out = if self.converged {
            format!(
                "converged in {} iterations, cost {:.3e}",
                self.iterations, self.cost
            )
        } else {
            format!(
                "DID NOT CONVERGE after {} iterations, cost {:.3e}",
                self.iterations, self.cost
            )
        };
        for (name, value) in self.worst.iter().take(6) {
            out.push_str(&format!("\n    {name}: {value:+.4}"));
        }
        out
    }
}

/// Every residual, with the name it will be blamed by.
fn residuals<T: Scalar>(model: &RideModel, x: &[T], seed: &[f64]) -> (Vec<T>, Vec<String>) {
    let ride = evaluate(model, x);
    let end = ride.end();
    let station = &model.spec.station;
    let mut r = Vec::new();
    let mut names = Vec::new();
    let mut push = |value: T, name: String| {
        r.push(value);
        names.push(name);
    };

    // Station closure: back to the same place, pointing the same way, level.
    let w = T::from_f64(weight::POSITION);
    push(
        (end.position.x - T::from_f64(station.position.x)) * w,
        "closure x (m)".into(),
    );
    push(
        (end.position.y - T::from_f64(station.position.y)) * w,
        "closure y (m)".into(),
    );
    push(
        (end.position.z - T::from_f64(station.position.z)) * w,
        "closure z (m)".into(),
    );

    let heading = station.heading;
    let unit = heading / heading.norm();
    let wh = T::from_f64(weight::HEADING);
    push(
        (end.frame.tangent.x - T::from_f64(unit.x)) * wh,
        "closure heading x".into(),
    );
    push(
        (end.frame.tangent.y - T::from_f64(unit.y)) * wh,
        "closure heading y".into(),
    );
    push(
        (end.frame.tangent.z - T::from_f64(unit.z)) * wh,
        "closure heading z".into(),
    );
    // The rider's right must be horizontal, or the train arrives banked.
    push(
        end.frame.right.z * T::from_f64(weight::BANK),
        "closure bank".into(),
    );

    // What the human pinned, and what the infrastructure was asked for.
    for (element, result) in model.spec.elements.iter().zip(&ride.elements) {
        match element.pin {
            Some(Pin::Rise(m)) => push(
                (result.rise - T::from_f64(m)) * T::from_f64(weight::PIN),
                format!("{} rise (m, pinned {m:.0})", element.name),
            ),
            Some(Pin::Drop(m)) => push(
                (result.drop - T::from_f64(m)) * T::from_f64(weight::PIN),
                format!("{} drop (m, pinned {m:.0})", element.name),
            ),
            // Held lightly. Seeding a turnaround is not enough on its own:
            // nothing else in the residual set knows it is meant to be a half
            // circle, and the solve will happily spin one through 595 degrees
            // to buy a few metres of closure.
            Some(Pin::Turn(deg)) => push(
                (result.heading_change - T::from_f64(deg)) * T::from_f64(weight::STRUCTURE),
                format!("{} turn (deg)", element.name),
            ),
            None => {}
        }
        // Where the element points when it hands over. Every element has one,
        // and between them they are what keeps the layout from running away.
        push(
            (result.exit_pitch - T::from_f64(element.exit_pitch_deg))
                * T::from_f64(weight::STRUCTURE),
            format!("{} exit pitch (deg)", element.name),
        );
        if let Some(requested) = result.requested_speed {
            push(
                (result.exit_speed - requested) * T::from_f64(weight::SPEED),
                format!("{} exit speed (m/s)", element.name),
            );
        }
    }

    // Pacing. A ride that reaches its top speed once and crawls everywhere else
    // is not fast, and the average is the only number that notices.
    push(
        (T::from_f64(model.spec.target_average_speed) - ride.length / ride.duration).max(T::ZERO)
            * T::from_f64(weight::PACE),
        "average speed shortfall (m/s)".into(),
    );

    // Comfort, clearance and running gear. Zero unless broken.
    let analysis = analyse(model, &ride);
    for (check, penalty) in analysis.checks.iter().zip(analysis.penalties()) {
        push(
            penalty * T::from_f64(weight::PENALTY),
            format!("over {}", check.name),
        );
    }

    // Stay near the ride as described. This is what picks one point out of the
    // feasible manifold; see the module note.
    let bounds = model.spec.bounds();
    for (i, (&value, (lo, hi))) in x.iter().zip(bounds).enumerate() {
        let range = (hi - lo).max(1e-9);
        push(
            (value - T::from_f64(seed[i])) / T::from_f64(range)
                * T::from_f64(weight::REGULARISATION),
            format!("drift in parameter {i}"),
        );
    }

    (r, names)
}

/// Sizes and aims every element against its own demand, before the global
/// solve runs.
///
/// Two demands per element, and two parameters to meet them with. The **trim**
/// shifts the whole force profile up or down, so it controls the pitch the
/// element hands on; the **length** scales how long that profile acts for, so
/// it controls how big the element is. They move the two independently, which
/// makes the pair well posed.
///
/// Neither can be authored by eye. No scale factor turns "make this hill a
/// quarter taller" into a length: rise grows with the square of the pitch angle
/// swept while arclength grows with the angle itself, and the train slows as it
/// climbs, so the radius tightens on the way up and the top of a tall hill is a
/// different shape from its bottom. The reference ride shows it plainly — its
/// camelback runs a ~610 m radius at the valley and ~206 m at the crest.
///
/// The derivatives, however, are exact and free, so a few damped Newton steps
/// find both. This is what makes a pin bind. Asking the global solve to
/// discover two hundred metres of height *and* close a multi-kilometre circuit
/// from an arbitrary guess is what left an earlier apex pin at a third of its
/// target.
pub fn seed_geometry(model: &mut RideModel, sweeps: usize) {
    let slots = parameter_slots(&model.spec);
    // Sweeps, because elements are coupled through speed: lengthening a drop
    // feeds the hill after it, which then wants a different length itself.
    for _ in 0..sweeps {
        for (i, &(length, trim)) in slots.iter().enumerate() {
            // Pitch first. A size measured on an element that points the wrong
            // way is a measurement of the wrong thing.
            if let Some(slot) = trim {
                let target = model.spec.elements[i].exit_pitch_deg;
                converge(model, i, slot, Knob::Trim, target, |r| r.exit_pitch);
            }
            let (Some(slot), Some(pin)) = (length, model.spec.elements[i].pin) else {
                continue;
            };
            match pin {
                Pin::Rise(m) => converge(model, i, slot, Knob::Length, m, |r| r.rise),
                Pin::Drop(m) => converge(model, i, slot, Knob::Length, m, |r| r.drop),
                Pin::Turn(d) => converge(model, i, slot, Knob::Length, d, |r| r.heading_change),
            }
        }
    }
}

/// Which of an element's parameters a seeding pass may move.
enum Knob {
    Length,
    Trim,
}

/// Damped Newton on one parameter of one element against one measurement.
///
/// Damped because none of these maps is linear, and an undamped step on a
/// shallow gradient lands outside the bounds every time.
fn converge(
    model: &mut RideModel,
    element: usize,
    slot: usize,
    knob: Knob,
    target: f64,
    measure: fn(&ElementResult<Dual>) -> Dual,
) {
    const STEPS: usize = 8;
    /// Close enough, in metres or degrees as the demand requires.
    const TOLERANCE: f64 = 0.4;
    /// Largest fraction of its own value one step may move a parameter.
    const DAMPING: f64 = 0.3;
    /// Step floor, so a trim sitting at zero can still move.
    const FLOOR: f64 = 0.25;

    for _ in 0..STEPS {
        let x: Vec<Dual> = model
            .spec
            .free_parameters()
            .iter()
            .enumerate()
            .map(|(k, &v)| {
                if k == slot {
                    Dual::variable(v)
                } else {
                    Dual::constant(v)
                }
            })
            .collect();
        let got = measure(&evaluate(model, &x).elements[element]);
        let error = got.re - target;
        if error.abs() < TOLERANCE || got.du.abs() < 1e-9 {
            break;
        }
        let free = match knob {
            Knob::Length => &mut model.spec.elements[element].length,
            Knob::Trim => &mut model.spec.elements[element].trim,
        };
        let reach = DAMPING * free.value.abs().max(FLOOR);
        free.value = (free.value - (error / got.du).clamp(-reach, reach)).clamp(free.lo, free.hi);
    }
}

/// Where each element's length and trim sit in the free-parameter vector.
///
/// Counted rather than looked up by name, because two elements may share a name
/// and a silent mismatch here would seed the wrong element.
fn parameter_slots(spec: &crate::model::Spec) -> Vec<(Option<usize>, Option<usize>)> {
    let mut next = 0;
    let mut take = |free: bool| {
        let slot = free.then_some(next);
        next += usize::from(free);
        slot
    };
    spec.elements
        .iter()
        .map(|e| {
            let length = take(e.length.is_free());
            take(e.g_scale.is_free());
            let trim = take(e.trim.is_free());
            take(e.roll_scale.is_free());
            take(e.speed_control.is_some_and(|f| f.is_free()));
            (length, trim)
        })
        .collect()
}

/// Solves the model, returning the report and the ride it settled on.
///
/// `max_iterations` bounds the work; the solve stops early once the step stops
/// buying anything.
pub fn solve(model: &RideModel, max_iterations: usize) -> (Report, Ride<f64>) {
    let seed = model.spec.free_parameters();
    let bounds = model.spec.bounds();
    let n = seed.len();
    let mut x = seed.clone();

    let (r0, names) = residuals(model, &x, &seed);
    let mut cost = half_sum_squares(&r0);
    let mut residual = r0;
    let mut lambda = 1e-3;
    let mut used = 0;

    for iteration in 0..max_iterations {
        used = iteration + 1;

        // Exact Jacobian: one forward pass per parameter, with that parameter
        // carrying a derivative. No step size, no cancellation, no noise for
        // the solver to chase.
        let m = residual.len();
        let mut jacobian = vec![vec![0.0; n]; m];
        #[expect(
            clippy::needless_range_loop,
            reason = "j is a column index into the Jacobian and a position in the seed vector at once"
        )]
        for j in 0..n {
            let dual: Vec<Dual> = x
                .iter()
                .enumerate()
                .map(|(i, &v)| {
                    if i == j {
                        Dual::variable(v)
                    } else {
                        Dual::constant(v)
                    }
                })
                .collect();
            let (column, _) = residuals(model, &dual, &seed);
            for (i, value) in column.iter().enumerate() {
                jacobian[i][j] = value.du;
            }
        }

        // Normal equations, damped.
        let mut jtj = vec![vec![0.0; n]; n];
        let mut jtr = vec![0.0; n];
        for i in 0..m {
            for a in 0..n {
                jtr[a] += jacobian[i][a] * residual[i];
                for b in 0..n {
                    jtj[a][b] += jacobian[i][a] * jacobian[i][b];
                }
            }
        }
        let gradient_norm = jtr.iter().fold(0.0_f64, |m, v| m.max(v.abs()));
        if gradient_norm < 1e-9 {
            break;
        }

        let mut improved = false;
        for _ in 0..12 {
            let mut damped = jtj.clone();
            for (a, row) in damped.iter_mut().enumerate() {
                // Scale the damping by each parameter's own curvature, so that
                // a length in metres and a dimensionless scale are damped
                // comparably.
                row[a] += lambda * jtj[a][a].max(1e-12);
            }
            let Some(step) = solve_linear(damped, jtr.iter().map(|v| -v).collect()) else {
                lambda *= 8.0;
                continue;
            };

            // Backtrack along the step before giving up on it. Clamping to
            // bounds bends the direction, and a bent full step often overshoots
            // where a short one would still have gone downhill; without this
            // the solve stalls the moment any parameter reaches a bound.
            let mut accepted = false;
            for scale in [1.0, 0.5, 0.2, 0.05] {
                let trial: Vec<f64> = x
                    .iter()
                    .zip(&step)
                    .zip(&bounds)
                    .map(|((&v, &d), &(lo, hi))| (v + d * scale).clamp(lo, hi))
                    .collect();
                let (trial_residual, _) = residuals(model, &trial, &seed);
                let trial_cost = half_sum_squares(&trial_residual);
                if trial_cost < cost {
                    x = trial;
                    residual = trial_residual;
                    cost = trial_cost;
                    lambda = (lambda / 3.0).max(1e-12);
                    accepted = true;
                    break;
                }
            }
            if accepted {
                improved = true;
                break;
            }
            lambda *= 8.0;
        }

        if !improved || lambda > 1e12 {
            break;
        }
    }

    let mut worst: Vec<(String, f64)> = names
        .iter()
        .cloned()
        .zip(residual.iter().copied())
        .filter(|(_, v)| v.abs() > 1e-6)
        .collect();
    worst.sort_by(|a, b| b.1.abs().total_cmp(&a.1.abs()));
    worst.truncate(10);

    // Converged means the hard constraints are met, not that the optimiser
    // stopped: drift residuals are meant to be non-zero.
    let converged = names
        .iter()
        .zip(&residual)
        .filter(|(name, _)| !name.starts_with("drift"))
        .all(|(_, v)| v.abs() < 1.0);

    let ride = evaluate(model, &x);
    (
        Report {
            converged,
            iterations: used,
            cost,
            parameters: x,
            worst,
        },
        ride,
    )
}

fn half_sum_squares(r: &[f64]) -> f64 {
    0.5 * r.iter().map(|v| v * v).sum::<f64>()
}

/// Dense linear solve by Gaussian elimination with partial pivoting.
///
/// Written out rather than pulled in: the systems here are a couple of dozen
/// unknowns, and determinism matters more than speed.
fn solve_linear(mut a: Vec<Vec<f64>>, mut b: Vec<f64>) -> Option<Vec<f64>> {
    let n = b.len();
    for col in 0..n {
        let pivot = (col..n).max_by(|&i, &j| a[i][col].abs().total_cmp(&a[j][col].abs()))?;
        if a[pivot][col].abs() < 1e-14 {
            return None;
        }
        a.swap(col, pivot);
        b.swap(col, pivot);
        for row in col + 1..n {
            let factor = a[row][col] / a[col][col];
            if factor == 0.0 {
                continue;
            }
            let (upper, lower) = a.split_at_mut(row);
            for (target, source) in lower[0][col..n].iter_mut().zip(&upper[col][col..n]) {
                *target -= factor * source;
            }
            b[row] -= factor * b[col];
        }
    }
    let mut x = vec![0.0; n];
    for row in (0..n).rev() {
        let sum: f64 = (row + 1..n).map(|k| a[row][k] * x[k]).sum();
        x[row] = (b[row] - sum) / a[row][row];
    }
    x.iter().all(|v| v.is_finite()).then_some(x)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Channel, Element, Free, Site, Spec, Station, Terrain};
    use crate::preset;
    use vc_math::vec3::Vec3;

    #[test]
    fn the_linear_solver_solves() {
        let a = vec![
            vec![2.0, 1.0, -1.0],
            vec![-3.0, -1.0, 2.0],
            vec![-2.0, 1.0, 2.0],
        ];
        let b = vec![8.0, -11.0, -3.0];
        let x = solve_linear(a, b).unwrap();
        for (got, want) in x.iter().zip([2.0, 3.0, -1.0]) {
            assert!((got - want).abs() < 1e-10, "{x:?}");
        }
    }

    #[test]
    fn the_linear_solver_refuses_a_singular_system() {
        let a = vec![vec![1.0, 2.0], vec![2.0, 4.0]];
        assert!(solve_linear(a, vec![1.0, 2.0]).is_none());
    }

    /// A deliberately small problem: one straight element whose length is free,
    /// asked to end 250 m from the station. The answer is 250.
    fn trivial_model() -> RideModel {
        RideModel {
            spec: Spec {
                station: Station {
                    position: Vec3::new(250.0, 0.0, 100.0),
                    heading: Vec3::new(1.0, 0.0, 0.0),
                    dispatch_speed: 20.0,
                },
                target_average_speed: 0.0,
                elements: vec![Element {
                    name: "straight",
                    normal_g: Channel::flat(1.0),
                    lateral_g: Channel::flat(0.0),
                    bank_deg: Channel::flat(0.0),
                    length: Free::new(100.0, 20.0, 400.0),
                    g_scale: Free::fixed(1.0),
                    trim: Free::fixed(0.0),
                    roll_scale: Free::fixed(1.0),
                    speed_control: None,
                    pin: None,
                    exit_pitch_deg: 0.0,
                }],
            },
            site: Site {
                terrain: Terrain {
                    origin: (-1000.0, -1000.0),
                    spacing: 500.0,
                    nx: 8,
                    heights: vec![0.0; 64],
                },
                min_clearance: 3.0,
                air_density: 1.0,
            },
            vehicle: preset::train(),
            limits: preset::astm_limits(),
        }
    }

    #[test]
    fn the_solve_respects_bounds_and_names_what_it_could_not_do() {
        // A straight element asked to return to a station 900 m behind where
        // it ends. Impossible: the parameter must stop at its bound rather
        // than running past it, the report must not claim success, and it must
        // say which constraint it gave up on.
        let mut model = trivial_model();
        model.spec.station.position.x = 900.0;
        let (report, _) = solve(&model, 30);
        assert!(report.parameters[0] <= 400.0 + 1e-9, "ran past the bound");
        assert!(!report.converged);
        assert!(
            report.worst[0].0.contains("closure x"),
            "blamed the wrong thing: {:?}",
            report.worst
        );
    }

    #[test]
    fn the_solve_makes_real_progress_on_the_preset() {
        // The honest integration test. Closure on a real circuit is the hard
        // case and may not come in all the way, so what is asserted is that
        // the solve moves substantially towards it, keeps every parameter
        // legal, and can say what is left — not that it always wins.
        let model = preset::falcon_class();
        let seed = model.spec.free_parameters();
        let (before, _) = residuals(&model, &seed, &seed);
        let start_cost = half_sum_squares(&before);

        let (report, ride) = solve(&model, 25);
        assert!(
            report.cost < start_cost * 0.5,
            "cost barely moved: {start_cost:.3e} -> {:.3e}",
            report.cost
        );
        for (value, (lo, hi)) in report.parameters.iter().zip(model.spec.bounds()) {
            assert!((lo..=hi).contains(value), "{value} escaped {lo}..{hi}");
        }
        assert!(ride.samples.iter().all(|s| s.speed.is_finite()));
        assert!(!report.worst.is_empty(), "no diagnosis offered");
    }

    #[test]
    fn the_residual_vector_is_a_fixed_shape() {
        // The solve differentiates this; a residual that appears or vanishes
        // between evaluations would silently corrupt the Jacobian.
        let model = preset::falcon_class();
        let seed = model.spec.free_parameters();
        let (a, names) = residuals(&model, &seed, &seed);
        let nudged: Vec<f64> = seed.iter().map(|v| v * 1.15).collect();
        let (b, names_b) = residuals(&model, &nudged, &seed);
        assert_eq!(a.len(), b.len());
        assert_eq!(names, names_b);
        assert!(a.iter().all(|v| v.is_finite()) && b.iter().all(|v| v.is_finite()));
    }
}
