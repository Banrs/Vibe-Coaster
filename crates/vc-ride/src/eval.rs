//! The evaluator: force profile in, ride out.
//!
//! A pure function. Given a fully determined parameter set it forward-
//! integrates the ride and reports what that parameter set produces. It makes
//! no decisions, adjusts nothing, and never fails a design — deciding is the
//! solve's job, and judging is the analysis's.
//!
//! ## The inversion
//!
//! Conventional track design draws a curve and measures the forces. This does
//! the opposite. At each point the rider's felt acceleration is known, because
//! the spec says what it is; what is unknown is where the track has to go to
//! produce it.
//!
//! The felt acceleration `f` is what an accelerometer in the seat reads, so the
//! track's actual acceleration is `a = f + g`, with `g` pointing down. The
//! component of `a` along the direction of travel changes speed; the component
//! across it bends the track, and bending is curvature:
//!
//! ```text
//! kappa = (n * g0 * up + l * g0 * right + g - (g . t) t) / v^2
//! ```
//!
//! for felt vertical g `n`, felt lateral g `l`, and the rider's own axes `up`
//! and `right`. Everything else follows: `dp/ds = t`, `dt/ds = kappa`, and the
//! frame rides along with it.
//!
//! Two consequences worth stating plainly. Speed appears squared in the
//! denominator, so the same force costs less curvature the faster you go — and
//! a ride specified purely by force is *singular at a standstill*, which is why
//! the station has a dispatch speed rather than starting at zero. And gravity
//! must be subtracted in the instantaneous frame, not the world frame:
//! treating force and curvature as a pointwise algebraic map gets the bank
//! silently wrong everywhere.
//!
//! ## Why the train, not a point
//!
//! Longitudinal acceleration is not taken at the front of the train. It is the
//! mass-weighted mean of the gravity component along every row's own piece of
//! track. That single change is where back-row snap comes from: as the leading
//! cars tip over a crest they are already being pulled forward while the back
//! is still climbing, so the back row crests faster than a point mass would and
//! gets thrown harder. Row choice mattering is not an effect added later; it is
//! this line.

use vc_math::units::G0;
use vc_math::vec3::Vec3;
use vc_math::{Frame, Scalar};

use crate::model::{Params, RideModel};

/// Integration steps per element.
///
/// Fixed, not derived from element length: a count that changed with the
/// parameters would make the ride a discontinuous function of them, and the
/// solve differentiates through this.
pub const STEPS_PER_ELEMENT: usize = 1600;

/// Speed floor, m/s. Curvature divides by speed squared; this keeps a station
/// crawl finite. Set well below any real dispatch speed so it never binds.
const MIN_SPEED: f64 = 0.25;

/// One point along the ride.
#[derive(Clone, Copy, Debug)]
pub struct Sample<T: Scalar> {
    /// Distance travelled from the station, metres.
    pub s: T,
    /// Time since dispatch, seconds.
    pub time: T,
    /// Heartline position.
    pub position: Vec3<T>,
    /// The rider's axes, bank included.
    pub frame: Frame<T>,
    /// Speed, m/s.
    pub speed: T,
    /// Felt vertical g, positive into the seat.
    pub normal_g: T,
    /// Felt lateral g, positive to the rider's right.
    pub lateral_g: T,
    /// Felt longitudinal g, positive pressing the rider back.
    pub longitudinal_g: T,
    /// Bank rate, degrees per second.
    pub roll_rate: T,
    /// Height of the heartline above the ground, metres.
    pub clearance: T,
    /// Which element this belongs to.
    pub element: usize,
}

/// What one element turned out to do.
#[derive(Clone, Copy, Debug)]
pub struct ElementResult<T: Scalar> {
    /// Its name, for reports.
    pub name: &'static str,
    /// Solved arclength, metres.
    pub length: T,
    /// Speed entering, m/s.
    pub entry_speed: T,
    /// Speed leaving, m/s.
    pub exit_speed: T,
    /// Speed the infrastructure was asked for, where it was asked.
    pub requested_speed: Option<T>,
    /// Highest point reached, metres above the station.
    pub apex: T,
}

/// A ride, as measured.
#[derive(Clone, Debug)]
pub struct Ride<T: Scalar> {
    /// Every integration step.
    pub samples: Vec<Sample<T>>,
    /// Per-element outcomes.
    pub elements: Vec<ElementResult<T>>,
    /// Total track length, metres.
    pub length: T,
    /// Total ride time, seconds.
    pub duration: T,
}

impl<T: Scalar> Ride<T> {
    /// The last sample. There is always at least one.
    pub fn end(&self) -> &Sample<T> {
        &self.samples[self.samples.len() - 1]
    }
}

/// Derivatives with respect to arclength at one point.
struct Derivative<T: Scalar> {
    tangent: Vec3<T>,
    curvature: Vec3<T>,
    /// d(v²/2)/ds, which is just the longitudinal acceleration.
    energy: T,
    /// dt/ds, the reciprocal of speed.
    time: T,
}

/// State carried along the integration.
#[derive(Clone, Copy)]
struct State<T: Scalar> {
    position: Vec3<T>,
    /// Rotation-minimising frame, before bank is applied.
    carrier: Frame<T>,
    /// v²/2. Integrating energy rather than speed avoids dividing by a speed
    /// that may be near zero in the station.
    energy: T,
    time: T,
}

/// Runs the ride described by `model` with the free parameters `x`.
///
/// `x` is the flat vector from [`crate::model::Spec::free_parameters`]; pinned
/// parameters come from the model.
pub fn evaluate<T: Scalar>(model: &RideModel, x: &[T]) -> Ride<T> {
    let params = model.spec.unpack(x);
    let vehicle = &model.vehicle;
    let offsets = vehicle.row_offsets();
    let mass = T::from_f64(vehicle.mass());
    let drag_factor = T::from_f64(0.5 * model.site.air_density * vehicle.cda()) / mass;
    let thrust_cap = T::from_f64(vehicle.thrust_max) / mass;
    let brake_cap = T::from_f64(vehicle.brake_max_decel);
    let g0 = T::from_f64(G0);
    let gravity = Vec3::new(T::ZERO, T::ZERO, -g0);
    let min_energy = T::from_f64(0.5 * MIN_SPEED * MIN_SPEED);
    let station_z = T::from_f64(model.spec.station.position.z);

    let mut state = State {
        position: Vec3::new(
            T::from_f64(model.spec.station.position.x),
            T::from_f64(model.spec.station.position.y),
            station_z,
        ),
        carrier: Frame::level(Vec3::new(
            T::from_f64(model.spec.station.heading.x),
            T::from_f64(model.spec.station.heading.y),
            T::from_f64(model.spec.station.heading.z),
        )),
        energy: T::from_f64(0.5 * model.spec.station.dispatch_speed.powi(2)),
        time: T::ZERO,
    };

    let capacity = model.spec.elements.len() * STEPS_PER_ELEMENT + 1;
    let mut samples = Vec::with_capacity(capacity);
    let mut results = Vec::with_capacity(model.spec.elements.len());
    // Tangent at every step so far, so the rows behind the front can be asked
    // what slope they are on.
    let mut history: Vec<(T, Vec3<T>)> = Vec::with_capacity(capacity);
    let mut s = T::ZERO;

    for (index, element) in model.spec.elements.iter().enumerate() {
        let p = params[index];
        let steps = T::from_f64(STEPS_PER_ELEMENT as f64);
        let h = p.length / steps;
        let entry_speed = (state.energy.max(min_energy) * T::from_f64(2.0)).sqrt();
        let mut apex = state.position.z - station_z;

        // Constant specific force across the element, sized to reach the
        // requested speed. What actually comes out is whatever physics gives
        // once gravity and drag have had their say; the difference is a
        // residual the solve can see, not something corrected here.
        let demand = p.exit_speed.map(|target| {
            (target.squared() - entry_speed.squared()) / (T::from_f64(2.0) * p.length)
        });

        for step in 0..STEPS_PER_ELEMENT {
            let u0 = T::from_f64(step as f64) / steps;
            let u1 = T::from_f64(step as f64 + 0.5) / steps;

            let (d0, mut measured) = derivative(
                &state,
                element,
                &p,
                u0,
                s,
                &history,
                &offsets,
                model,
                demand,
                g0,
                gravity,
                drag_factor,
                thrust_cap,
                brake_cap,
                min_energy,
            );
            measured.element = index;
            samples.push(measured);
            history.push((s, d0.tangent));

            // Midpoint: advance a half step, re-evaluate, apply the result
            // across the whole step. Second order for the cost of one extra
            // evaluation, and no adaptive decisions anywhere.
            let half = h * T::from_f64(0.5);
            let mid = State {
                position: state.position + d0.tangent * half,
                carrier: state.carrier.transport_to(d0.tangent + d0.curvature * half),
                energy: state.energy + d0.energy * half,
                time: state.time + d0.time * half,
            };
            let (d1, _) = derivative(
                &mid,
                element,
                &p,
                u1,
                s + half,
                &history,
                &offsets,
                model,
                demand,
                g0,
                gravity,
                drag_factor,
                thrust_cap,
                brake_cap,
                min_energy,
            );

            state = State {
                position: state.position + d1.tangent * h,
                carrier: state.carrier.transport_to(d1.tangent + d1.curvature * h),
                energy: state.energy + d1.energy * h,
                time: state.time + d1.time * h,
            };
            s += h;
            apex = apex.max(state.position.z - station_z);
        }

        results.push(ElementResult {
            name: element.name,
            length: p.length,
            entry_speed,
            exit_speed: (state.energy.max(min_energy) * T::from_f64(2.0)).sqrt(),
            requested_speed: p.exit_speed,
            apex,
        });
    }

    // Close the sample list on the final state, so the last sample is the end
    // of the ride rather than one step short of it.
    let last = model.spec.elements.len() - 1;
    let (_, mut final_sample) = derivative(
        &state,
        &model.spec.elements[last],
        &params[last],
        T::ONE,
        s,
        &history,
        &offsets,
        model,
        None,
        g0,
        gravity,
        drag_factor,
        thrust_cap,
        brake_cap,
        min_energy,
    );
    final_sample.element = last;
    samples.push(final_sample);

    Ride {
        samples,
        elements: results,
        length: s,
        duration: state.time,
    }
}

/// Derivatives and measurements at one point. The whole of the physics.
#[expect(
    clippy::too_many_arguments,
    reason = "the alternative is a context struct that exists only to be destructured here"
)]
fn derivative<T: Scalar>(
    state: &State<T>,
    element: &crate::model::Element,
    p: &Params<T>,
    u: T,
    s: T,
    history: &[(T, Vec3<T>)],
    offsets: &[f64],
    model: &RideModel,
    demand: Option<T>,
    g0: T,
    gravity: Vec3<T>,
    drag_factor: T,
    thrust_cap: T,
    brake_cap: T,
    min_energy: T,
) -> (Derivative<T>, Sample<T>) {
    let speed = (state.energy.max(min_energy) * T::from_f64(2.0)).sqrt();
    let (normal_g, lateral_g, bank) = element.felt(u, p);
    let frame = state.carrier.rolled(bank);
    let tangent = frame.tangent;

    // Curvature: the felt force, plus the part of gravity that acts across the
    // direction of travel, divided by speed squared.
    let felt = frame.up * (normal_g * g0) + frame.right * (lateral_g * g0);
    let gravity_across = gravity - tangent * gravity.dot(tangent);
    let curvature = (felt + gravity_across) / speed.squared();

    // Longitudinal acceleration. Gravity is averaged over the whole train, not
    // taken at the front — this is the multibody term.
    let slope = mean_gravity_along_train(history, s, offsets, tangent, gravity);
    let drag = drag_factor * speed.squared();
    let rolling = T::from_f64(model.vehicle.rolling_resistance) * normal_g.abs() * g0;
    // Infrastructure force eases in and out over the ends of the element, as
    // real motors and brakes do. Without this the force steps at every seam and
    // the jerk is unbounded.
    let window = engagement(u, p.length, T::from_f64(model.vehicle.force_ramp));
    let propulsion = match demand {
        // Saturation is real: linear motors fade towards synchronous speed and
        // brakes have a maximum. Inside those limits nothing here binds.
        Some(d) if d > T::ZERO => d.min(thrust_cap * thrust_fade(speed, &model.vehicle)) * window,
        Some(d) => d.max(-brake_cap) * window,
        None => T::ZERO,
    };
    let longitudinal = slope + propulsion - drag - rolling;

    let ground = model
        .site
        .terrain
        .height(state.position.x, state.position.y);

    let roll_rate = vc_math::units::to_degrees(element.bank_slope(u, p) / p.length * speed);

    let sample = Sample {
        s,
        time: state.time,
        position: state.position,
        frame,
        speed,
        normal_g,
        lateral_g,
        longitudinal_g: longitudinal / g0,
        roll_rate,
        clearance: state.position.z - ground,
        element: 0,
    };

    (
        Derivative {
            tangent,
            curvature,
            energy: longitudinal,
            time: speed.recip(),
        },
        sample,
    )
}

/// How fully the infrastructure is engaged at progress `u`: zero at each end
/// of the element, one in the middle, easing quintically over `ramp` metres.
fn engagement<T: Scalar>(u: T, length: T, ramp: T) -> T {
    let fraction = (ramp / length).clamp(T::from_f64(1e-6), T::from_f64(0.45));
    let rise = (u / fraction).clamp(T::ZERO, T::ONE);
    let fall = ((T::ONE - u) / fraction).clamp(T::ZERO, T::ONE);
    smoothstep(rise) * smoothstep(fall)
}

/// Quintic smoothstep: zero slope and zero curvature at both ends.
fn smoothstep<T: Scalar>(x: T) -> T {
    x.powi(3) * (T::from_f64(10.0) - T::from_f64(15.0) * x + T::from_f64(6.0) * x.squared())
}

/// How much linear-motor thrust survives at this speed.
///
/// Flat until roughly seven tenths of synchronous speed, then falling to
/// nothing at synchronous. A constant-thrust model overshoots the top of a
/// launch badly.
fn thrust_fade<T: Scalar>(speed: T, vehicle: &crate::model::Vehicle) -> T {
    let sync = T::from_f64(vehicle.thrust_sync_speed);
    let knee = sync * T::from_f64(0.7);
    ((sync - speed) / (sync - knee)).clamp(T::ZERO, T::ONE)
}

/// Mass-weighted mean of the gravity component along the track, over every row
/// of the train.
///
/// Rows behind the front sit at earlier arclengths, where the tangent has
/// already been computed. Anything behind the station start is on the station's
/// straight level track, so it takes the tangent at zero — an exact
/// continuation, not an approximation.
fn mean_gravity_along_train<T: Scalar>(
    history: &[(T, Vec3<T>)],
    s: T,
    offsets: &[f64],
    front: Vec3<T>,
    gravity: Vec3<T>,
) -> T {
    let mut total = T::ZERO;
    for &offset in offsets {
        let target = s - T::from_f64(offset);
        let tangent = tangent_at(history, target).unwrap_or(front);
        total += gravity.dot(tangent);
    }
    total / T::from_f64(offsets.len() as f64)
}

/// The tangent recorded at arclength `target`, linearly interpolated.
///
/// `None` past the end of what has been recorded, so the caller falls back to
/// the tangent it is holding. That case is the leading row, and it matters more
/// than it looks: the midpoint of a step is ahead of every recorded sample, so
/// reading a stale tangent there would make the energy the integrator adds
/// disagree with the height it climbs, and the ride would quietly gain or lose
/// energy on every slope.
fn tangent_at<T: Scalar>(history: &[(T, Vec3<T>)], target: T) -> Option<Vec3<T>> {
    if history.is_empty() {
        return None;
    }
    let key = target.to_f64();
    if key <= history[0].0.to_f64() {
        return Some(history[0].1);
    }
    let i = history.partition_point(|&(s, _)| s.to_f64() <= key);
    if i >= history.len() {
        return None;
    }
    let (s0, t0) = history[i - 1];
    let (s1, t1) = history[i];
    let span = s1 - s0;
    if span <= T::ZERO {
        return Some(t1);
    }
    Some(t0.lerp(t1, (target - s0) / span))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Channel, Element, Free, Limits, Site, Spec, Station, Terrain, Vehicle};
    use vc_math::Dual;

    fn flat_site() -> Site {
        Site {
            terrain: Terrain {
                origin: (-5000.0, -5000.0),
                spacing: 500.0,
                nx: 24,
                heights: vec![0.0; 24 * 24],
            },
            min_clearance: 3.0,
            air_density: 1.0,
        }
    }

    fn test_vehicle() -> Vehicle {
        Vehicle {
            cars: 1,
            rows_per_car: 1,
            riders_per_row: 2,
            row_pitch: 0.9,
            car_pitch: 3.0,
            car_mass: 1200.0,
            rider_mass: 75.0,
            heartline_offset: 1.0,
            cda_lead: 0.0,
            cda_trailing: 0.0,
            rolling_resistance: 0.0,
            thrust_max: 400_000.0,
            thrust_sync_speed: 100.0,
            brake_max_decel: 8.0,
            force_ramp: 1.0,
            wheel_speed_limit: None,
        }
    }

    fn limits() -> Limits {
        crate::preset::astm_limits()
    }

    fn model_of(elements: Vec<Element>, dispatch: f64) -> RideModel {
        RideModel {
            spec: Spec {
                station: Station {
                    position: Vec3::new(0.0, 0.0, 100.0),
                    heading: Vec3::new(1.0, 0.0, 0.0),
                    dispatch_speed: dispatch,
                },
                elements,
            },
            site: flat_site(),
            vehicle: test_vehicle(),
            limits: limits(),
        }
    }

    fn level(name: &'static str, length: f64, speed: Option<f64>) -> Element {
        Element {
            name,
            normal_g: Channel::flat(1.0),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(0.0),
            length: Free::fixed(length),
            g_scale: Free::fixed(1.0),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: speed.map(Free::fixed),
            pin_apex_m: None,
        }
    }

    /// Runs a model at its own nominal parameters, in plain f64.
    fn run(model: &RideModel) -> Ride<f64> {
        evaluate(model, &model.spec.free_parameters())
    }

    #[test]
    fn one_g_of_level_track_stays_level_and_straight() {
        // The base case the whole inversion rests on: asking for exactly the
        // force of standing still must produce no curvature at all.
        let model = model_of(vec![level("straight", 200.0, None)], 20.0);
        let ride = run(&model);
        let end = ride.end();
        assert!(
            (end.position.z - 100.0).abs() < 1e-9,
            "z {}",
            end.position.z
        );
        assert!(end.position.y.abs() < 1e-9);
        assert!((end.position.x - 200.0).abs() < 1e-6);
        assert!((end.frame.tangent - Vec3::new(1.0, 0.0, 0.0)).norm() < 1e-9);
        assert!((ride.length - 200.0).abs() < 1e-9);
    }

    #[test]
    fn a_constant_g_turn_has_the_radius_theory_says() {
        // Rolled fully onto its side, the whole of the felt force goes
        // sideways, so the track is a circle of radius v^2 / (n g).
        let bank = 90.0_f64;
        let n = 2.5;
        let v = 30.0;
        let element = Element {
            name: "turn",
            normal_g: Channel::flat(n),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(bank),
            length: Free::fixed(200.0),
            g_scale: Free::fixed(1.0),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: None,
            pin_apex_m: None,
        };
        let model = model_of(vec![element], v);
        let ride = run(&model);

        // At 90 degrees of bank the felt force is horizontal; gravity across
        // the track is unbalanced and pulls it down, so check the horizontal
        // curvature against the closed form.
        let expected_radius = v * v / (n * G0);
        let sample = &ride.samples[10];
        let horizontal = Vec3::new(sample.position.x, sample.position.y, 0.0);
        let centre_distance = (horizontal - Vec3::new(0.0, -expected_radius, 0.0)).norm();
        assert!(
            (centre_distance - expected_radius).abs() < 1.5,
            "radius {centre_distance} vs {expected_radius}"
        );
    }

    #[test]
    fn energy_is_conserved_when_nothing_takes_any() {
        // No drag, no rolling resistance, no propulsion: speed at the bottom
        // must match the drop exactly. This is the test that catches a sign
        // error in the gravity term.
        let hill = Element {
            name: "hill",
            normal_g: Channel::new(&[(0.0, 1.0), (0.5, 0.2), (1.0, 1.0)]),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(0.0),
            length: Free::fixed(300.0),
            g_scale: Free::fixed(1.0),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: None,
            pin_apex_m: None,
        };
        let model = model_of(vec![hill], 40.0);
        let ride = run(&model);
        let end = ride.end();
        let drop = 100.0 - end.position.z;
        let expected = (40.0_f64.powi(2) + 2.0 * G0 * drop).sqrt();
        assert!(
            (end.speed - expected).abs() < 1e-3,
            "speed {} vs {expected} over a drop of {drop}",
            end.speed
        );
    }

    #[test]
    fn a_launch_reaches_the_speed_it_was_asked_for() {
        let model = model_of(
            vec![
                level("station", 40.0, None),
                level("launch", 300.0, Some(60.0)),
            ],
            2.0,
        );
        let ride = run(&model);
        assert!(
            (ride.elements[1].exit_speed - 60.0).abs() < 0.2,
            "exit {}",
            ride.elements[1].exit_speed
        );
    }

    #[test]
    fn a_brake_run_sheds_the_speed_it_can() {
        // Asked for something the brakes can do in the distance available.
        let model = model_of(
            vec![level("run", 200.0, None), level("brakes", 200.0, Some(5.0))],
            50.0,
        );
        let ride = run(&model);
        // Not exact: the brakes ease in and out over the ends of the element,
        // so they deliver slightly less than a constant force would. That gap
        // is real and the solve sees it as a residual.
        assert!(
            (ride.elements[1].exit_speed - 5.0).abs() < 1.5,
            "exit {}",
            ride.elements[1].exit_speed
        );
    }

    #[test]
    fn an_impossible_stop_is_reported_not_faked() {
        // The same request in half the distance exceeds the brakes. The
        // evaluator must let the train run hot rather than quietly teleporting
        // it to the requested speed — the gap is what the solve needs to see.
        let model = model_of(
            vec![level("run", 200.0, None), level("brakes", 80.0, Some(5.0))],
            50.0,
        );
        let ride = run(&model);
        let exit = ride.elements[1].exit_speed;
        assert!(exit > 20.0, "brakes did the impossible: {exit}");
        let requested = ride.elements[1].requested_speed.unwrap();
        assert!(
            (requested - 5.0).abs() < 1e-12,
            "the request is still on record"
        );
    }

    #[test]
    fn the_back_of_the_train_crests_harder_than_the_front() {
        // The multibody claim, tested directly. A long train over a sharp crest
        // must be pulled over faster than a point mass would be.
        let crest = Element {
            name: "crest",
            normal_g: Channel::new(&[(0.0, 1.0), (0.5, -0.2), (1.0, 1.0)]),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(0.0),
            length: Free::fixed(120.0),
            g_scale: Free::fixed(1.0),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: None,
            pin_apex_m: None,
        };
        let mut long_train = model_of(vec![crest.clone()], 25.0);
        long_train.vehicle.cars = 6;
        long_train.vehicle.rows_per_car = 2;
        let point_mass = model_of(vec![crest], 25.0);

        let long = run(&long_train);
        let point = run(&point_mass);
        let difference = (long.end().speed - point.end().speed).abs();
        assert!(
            difference > 1e-4,
            "train length made no difference at all: {difference}"
        );
    }

    #[test]
    fn drag_costs_speed() {
        let mut with_drag = model_of(vec![level("run", 400.0, None)], 60.0);
        with_drag.vehicle.cda_lead = 2.0;
        let ride = run(&with_drag);
        assert!(ride.end().speed < 59.0, "{}", ride.end().speed);
    }

    #[test]
    fn the_integration_has_converged_at_the_step_count_we_use() {
        // Halving the step must not move the answer more than a few
        // centimetres over a few hundred metres, or the closure residuals the
        // solve chases are numerical noise.
        // Constant channels make one element of length L and two of L/2 the
        // *same physical curve* at half the step size. That is the only way to
        // vary step density without also varying the ride.
        let turn = |length: f64| Element {
            name: "turn",
            normal_g: Channel::flat(2.2),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(65.0),
            length: Free::fixed(length),
            g_scale: Free::fixed(1.0),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: None,
            pin_apex_m: None,
        };
        let coarse = run(&model_of(vec![turn(400.0)], 45.0));
        let fine = run(&model_of(vec![turn(200.0), turn(200.0)], 45.0));

        let gap = (coarse.end().position - fine.end().position).norm();
        assert!(
            gap < 0.015,
            "endpoint moved {gap} m when the step was halved"
        );
        assert!((coarse.end().speed - fine.end().speed).abs() < 1e-3);
        assert_eq!(coarse.samples.len(), STEPS_PER_ELEMENT + 1);
    }

    #[test]
    fn the_ride_carries_derivatives() {
        // The reason for the whole scalar-generic exercise: the solve needs
        // d(where it ends up) / d(element length), exactly.
        let model = model_of(
            vec![Element {
                name: "run",
                length: Free::new(200.0, 100.0, 300.0),
                ..level("run", 200.0, None)
            }],
            30.0,
        );
        let x = [Dual::variable(200.0)];
        let ride = evaluate(&model, &x);
        // Level straight track: a metre more length is a metre more x.
        assert!(
            (ride.end().position.x.du - 1.0).abs() < 1e-6,
            "{}",
            ride.end().position.x.du
        );
    }
}
