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

use crate::model::{Element, Params, RideModel};

/// Integration steps per element.
///
/// Fixed, not derived from element length: a count that changed with the
/// parameters would make the ride a discontinuous function of them, and the
/// solve differentiates through this.
pub const STEPS_PER_ELEMENT: usize = 1600;

/// Speed floor, m/s.
///
/// Curvature divides by speed squared, so a train that stops does not merely
/// stop — the geometry blows up, and the solve, differentiating through it,
/// finds a landscape full of spirals it can wander into. Set below any real
/// dispatch or brake-run speed so it never binds on a healthy ride, but high
/// enough that an unhealthy one degrades instead of exploding.
const MIN_SPEED: f64 = 2.0;

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
    /// Metres climbed from the low point before this element's high point.
    pub rise: T,
    /// Metres descended from this element's high point to the low point after.
    pub drop: T,
    /// Speed at the high point, m/s. The condition the rise was delivered
    /// under: the same shape at a different speed is a different size, so a
    /// height figure quoted without it does not transfer.
    pub crest_speed: T,
    /// Pitch of the track leaving the element, degrees, positive climbing.
    pub exit_pitch: T,
    /// Net change in the direction of travel across the element, degrees,
    /// positive turning left. Accumulated rather than taken end to end, so a
    /// turnaround that goes past half a circle is not reported as a small one
    /// the other way.
    pub heading_change: T,
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

/// The state a segment of the ride starts from.
///
/// The station is one of these; in a multiple-shooting solve every seam is
/// another, carried as unknowns. Bank is zero at every element seam by
/// authorship — channels meet their neighbours at one g and level — so the
/// carrier here is also the rider's frame.
#[derive(Clone, Copy, Debug)]
pub struct Start<T: Scalar> {
    /// Heartline position.
    pub position: Vec3<T>,
    /// Rotation-minimising frame, before bank.
    pub carrier: Frame<T>,
    /// Speed, m/s.
    pub speed: T,
    /// Seconds since dispatch.
    pub time: T,
    /// Arclength already travelled, metres.
    pub s: T,
}

/// Runs the ride described by `model` with the free parameters `x`.
///
/// `x` is the flat vector from [`crate::model::Spec::free_parameters`]; pinned
/// parameters come from the model.
pub fn evaluate<T: Scalar>(model: &RideModel, x: &[T]) -> Ride<T> {
    evaluate_split(model, x, &[]).0
}

/// Runs the ride in segments, each after the first starting from a given seam
/// state rather than from wherever the previous segment ended.
///
/// This is the evaluator half of multiple shooting: `seams` gives, for each
/// cut, the element index the next segment begins at and the state it begins
/// from. What each segment *actually* ended at comes back alongside the ride,
/// so the solve can demand end and seam agree — the defect constraints. With
/// no seams this is exactly the single forward pass.
///
/// Within a train length after a seam, the rows behind the front read the
/// seam's own tangent — the same straight-continuation assumption the station
/// makes for rows behind the dispatch point.
pub fn evaluate_split<T: Scalar>(
    model: &RideModel,
    x: &[T],
    seams: &[(usize, Start<T>)],
) -> (Ride<T>, Vec<Start<T>>) {
    let params = model.spec.unpack(x);
    let station = &model.spec.station;
    let capacity = model.spec.elements.len() * STEPS_PER_ELEMENT + 1;
    let mut samples = Vec::with_capacity(capacity);
    let mut results = Vec::with_capacity(model.spec.elements.len());
    // Tangent at every step so far, so the rows behind the front can be asked
    // what slope they are on.
    let mut history: Vec<(T, Vec3<T>)> = Vec::with_capacity(capacity);

    let mut start = Start {
        position: Vec3::new(
            T::from_f64(station.position.x),
            T::from_f64(station.position.y),
            T::from_f64(station.position.z),
        ),
        carrier: Frame::level(Vec3::new(
            T::from_f64(station.heading.x),
            T::from_f64(station.heading.y),
            T::from_f64(station.heading.z),
        )),
        speed: T::from_f64(station.dispatch_speed),
        time: T::ZERO,
        s: T::ZERO,
    };
    let mut begin = 0;
    let mut ends = Vec::with_capacity(seams.len());
    for &(element, seam) in seams {
        ends.push(integrate(
            model,
            &params,
            begin..element,
            start,
            &mut samples,
            &mut results,
            &mut history,
        ));
        // Cleared so a segment cannot see through its seam: reading the
        // previous segment's tangents would couple the two, which is the
        // conditioning problem shooting exists to remove.
        history.clear();
        begin = element;
        start = seam;
    }
    let end = integrate(
        model,
        &params,
        begin..model.spec.elements.len(),
        start,
        &mut samples,
        &mut results,
        &mut history,
    );

    close_and_measure(model, &params, &end, &mut samples, &mut results, &history);
    append_closer(model, &end, &mut samples, &mut results);
    let last = samples.len() - 1;
    let ride = Ride {
        length: samples[last].s,
        duration: samples[last].time,
        samples,
        elements: results,
    };
    (ride, ends)
}

/// Steps sampled along the closer.
const CLOSER_STEPS: usize = 400;

/// Longest gap the closer will bridge, metres. While the solve is still
/// kilometres from home a bridge would be a monster whose measured forces
/// reshape every residual; under this length at creep speed its forces are
/// negligible, so the solve's landscape is untouched by its appearance.
const CLOSER_REACH: f64 = 80.0;

/// Appends the closer: a septic Hermite bridge from wherever the ride ended
/// to the station. Position, velocity, acceleration and jerk all match at
/// both ends — C³, so nothing steps or kinks at the joins — and the circuit
/// closes exactly by construction.
///
/// This is the one stretch where geometry is dictated and the felt force is
/// an *outcome*, measured and judged against the envelope like everything
/// else. That is honest for what it models: a train creeping home under tyre
/// control, where the infrastructure owns the kinematics.
fn append_closer<T: Scalar>(
    model: &RideModel,
    end: &Start<T>,
    samples: &mut Vec<Sample<T>>,
    results: &mut Vec<ElementResult<T>>,
) {
    let g0 = T::from_f64(G0);
    let gravity = Vec3::new(T::ZERO, T::ZERO, -g0);
    let station = &model.spec.station;
    let target = Vec3::new(
        T::from_f64(station.position.x),
        T::from_f64(station.position.y),
        T::from_f64(station.position.z),
    );
    let gap = (target - end.position).norm();
    if !(0.5..CLOSER_REACH).contains(&gap.to_f64()) {
        return;
    }

    // Acceleration and jerk at entry, read off the last two samples: the felt
    // force is the proper acceleration, so a = f·g₀ + g.
    let accel = |s: &Sample<T>| {
        (s.frame.up * s.normal_g + s.frame.right * s.lateral_g + s.frame.tangent * s.longitudinal_g)
            * g0
            + gravity
    };
    let (last, prev) = (&samples[samples.len() - 1], &samples[samples.len() - 2]);
    let a0 = accel(last);
    let dt = last.time - prev.time;
    let j0 = if dt.to_f64() > 0.0 {
        (a0 - accel(prev)) / dt
    } else {
        Vec3::new(T::ZERO, T::ZERO, T::ZERO)
    };

    // The bridge in time: u ∈ [0, 1] over `span` seconds, endpoint derivatives
    // scaled accordingly. The station end is level, straight and settled.
    let dispatch = T::from_f64(station.dispatch_speed);
    let span = gap / ((end.speed + dispatch) * T::from_f64(0.5)) * T::from_f64(1.1);
    let heading = Vec3::new(
        T::from_f64(station.heading.x),
        T::from_f64(station.heading.y),
        T::from_f64(station.heading.z),
    );
    let c0 = end.position;
    let c1 = end.carrier.tangent * (end.speed * span);
    let c2 = a0 * span.squared() * T::from_f64(0.5);
    let c3 = j0 * span.squared() * span / T::from_f64(6.0);
    let r0 = target - (c0 + c1 + c2 + c3);
    let r1 = heading * (dispatch * span) - (c1 + c2 * T::from_f64(2.0) + c3 * T::from_f64(3.0));
    let r2 = -(c2 * T::from_f64(2.0) + c3 * T::from_f64(6.0));
    let r3 = -c3 * T::from_f64(6.0);
    // Right-end conditions solved once, exactly: the inverse of the u⁴..u⁷
    // constraint matrix at u = 1.
    let mix = |a: f64, b: f64, c: f64, d: f64| {
        r0 * T::from_f64(a) + r1 * T::from_f64(b) + r2 * T::from_f64(c) + r3 * T::from_f64(d)
    };
    let c4 = mix(35.0, -15.0, 2.5, -1.0 / 6.0);
    let c5 = mix(-84.0, 39.0, -7.0, 0.5);
    let c6 = mix(70.0, -34.0, 6.5, -0.5);
    let c7 = mix(-20.0, 10.0, -2.0, 1.0 / 6.0);

    let element = results.len();
    let mut s = end.s;
    let mut position = end.position;
    let mut turned = T::ZERO;
    let mut previous = end.carrier.tangent;
    let mut zmax = (end.position.z, end.speed);
    let min_speed = T::from_f64(MIN_SPEED);
    for step in 1..=CLOSER_STEPS {
        let u = T::from_f64(step as f64 / CLOSER_STEPS as f64);
        let at = |k: usize| -> T {
            [
                T::ONE,
                u,
                u.squared(),
                u.powi(3),
                u.powi(4),
                u.powi(5),
                u.powi(6),
                u.powi(7),
            ][k]
        };
        let horner = |f: &dyn Fn(usize) -> T| {
            c0 * f(0)
                + c1 * f(1)
                + c2 * f(2)
                + c3 * f(3)
                + c4 * f(4)
                + c5 * f(5)
                + c6 * f(6)
                + c7 * f(7)
        };
        let p = horner(&|k| at(k));
        let dp = horner(&|k| {
            if k == 0 {
                T::ZERO
            } else {
                at(k - 1) * T::from_f64(k as f64)
            }
        }) / span;
        let ddp = horner(&|k| {
            if k < 2 {
                T::ZERO
            } else {
                at(k - 2) * T::from_f64((k * (k - 1)) as f64)
            }
        }) / span.squared();

        let speed = dp.norm().max(min_speed);
        let tangent = dp / speed;
        let frame = Frame::level(tangent);
        let felt = (ddp - gravity) / g0;
        s += (p - position).norm();
        position = p;
        turned += (previous.x * tangent.y - previous.y * tangent.x)
            .atan2(previous.x * tangent.x + previous.y * tangent.y);
        previous = tangent;
        if position.z.to_f64() > zmax.0.to_f64() {
            zmax = (position.z, speed);
        }
        samples.push(Sample {
            s,
            time: end.time + u * span,
            position,
            frame,
            speed,
            normal_g: felt.dot(frame.up),
            lateral_g: felt.dot(frame.right),
            longitudinal_g: felt.dot(frame.tangent),
            roll_rate: T::ZERO,
            clearance: position.z - model.site.terrain.height(position.x, position.y),
            element,
        });
    }
    let station_z = T::from_f64(station.position.z);
    results.push(ElementResult {
        name: "closer",
        length: s - end.s,
        entry_speed: end.speed,
        exit_speed: dispatch,
        requested_speed: Some(dispatch),
        apex: zmax.0 - station_z,
        rise: T::ZERO,
        drop: T::ZERO,
        crest_speed: zmax.1,
        exit_pitch: T::ZERO,
        heading_change: vc_math::units::to_degrees(turned),
    });
}

/// Integrates one contiguous run of elements from a given start, appending to
/// the shared sample, result and history lists, and returns where it ended.
fn integrate<T: Scalar>(
    model: &RideModel,
    params: &[Params<T>],
    range: std::ops::Range<usize>,
    start: Start<T>,
    samples: &mut Vec<Sample<T>>,
    results: &mut Vec<ElementResult<T>>,
    history: &mut Vec<(T, Vec3<T>)>,
) -> Start<T> {
    let vehicle = &model.vehicle;
    let offsets = vehicle.row_offsets();
    let mass = T::from_f64(vehicle.mass());
    let drag_factor = T::from_f64(0.5 * model.site.air_density * vehicle.cda()) / mass;
    let thrust_cap = T::from_f64(vehicle.thrust_max) / mass;
    let brake_cap = T::from_f64(vehicle.brake_max_decel);
    let ramp = T::from_f64(vehicle.force_ramp);
    let g0 = T::from_f64(G0);
    let gravity = Vec3::new(T::ZERO, T::ZERO, -g0);
    let min_energy = T::from_f64(0.5 * MIN_SPEED * MIN_SPEED);
    let station_z = T::from_f64(model.spec.station.position.z);

    let mut state = State {
        position: start.position,
        carrier: start.carrier,
        energy: start.speed.squared() * T::from_f64(0.5),
        time: start.time,
    };
    let mut s = start.s;

    for index in range {
        let element = &model.spec.elements[index];
        let p = params[index];
        let steps = T::from_f64(STEPS_PER_ELEMENT as f64);
        let h = p.length / steps;
        let entry_speed = (state.energy.max(min_energy) * T::from_f64(2.0)).sqrt();
        let mut apex = state.position.z - station_z;

        let demand = speed_demand(element, &p, entry_speed, g0, ramp);

        for step in 0..STEPS_PER_ELEMENT {
            let u0 = T::from_f64(step as f64) / steps;
            let u1 = T::from_f64(step as f64 + 0.5) / steps;

            let (d0, mut measured) = derivative(
                &state,
                element,
                &p,
                u0,
                s,
                history,
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
                history,
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
                // Midpoint update: rotate the tangent the step STARTED with by
                // the midpoint curvature. d1.tangent is already half a step
                // rotated, so adding a full step to it over-rotates every
                // element by exactly 1.5x — an error independent of step size,
                // which is how it survived: a 23-degree lift rode at 34.5.
                carrier: state.carrier.transport_to(d0.tangent + d1.curvature * h),
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
            // Filled once the whole ride exists; a crest's valley is usually in
            // the next element.
            rise: T::ZERO,
            drop: T::ZERO,
            crest_speed: T::ZERO,
            exit_pitch: T::ZERO,
            heading_change: T::ZERO,
        });
    }

    Start {
        position: state.position,
        carrier: state.carrier,
        speed: (state.energy.max(min_energy) * T::from_f64(2.0)).sqrt(),
        time: state.time,
        s,
    }
}

/// Integrates the tail of the ride backward from the station's arrival side.
///
/// The arrival state is imposed rather than reached — station position, level
/// heading, bank zero — so that boundary holds by construction and the closure
/// error moves to a mid-ride joint the forward half can be asked to meet. It is
/// the same derivative field with a negated step, so drag hands energy back and
/// gravity flips with the slope without a special case anywhere. Records
/// nothing: it only carries state to the entry boundary of element `from`.
pub fn integrate_reverse<T: Scalar>(
    model: &RideModel,
    params: &[Params<T>],
    forward: &[ElementResult<T>],
    from: usize,
    arrival_speed: T,
) -> Start<T> {
    let vehicle = &model.vehicle;
    let offsets = vehicle.row_offsets();
    let mass = T::from_f64(vehicle.mass());
    let drag_factor = T::from_f64(0.5 * model.site.air_density * vehicle.cda()) / mass;
    let thrust_cap = T::from_f64(vehicle.thrust_max) / mass;
    let brake_cap = T::from_f64(vehicle.brake_max_decel);
    let ramp = T::from_f64(vehicle.force_ramp);
    let g0 = T::from_f64(G0);
    let gravity = Vec3::new(T::ZERO, T::ZERO, -g0);
    let min_energy = T::from_f64(0.5 * MIN_SPEED * MIN_SPEED);
    let station = &model.spec.station;

    let mut state = State {
        position: Vec3::new(
            T::from_f64(station.position.x),
            T::from_f64(station.position.y),
            T::from_f64(station.position.z),
        ),
        carrier: Frame::level(Vec3::new(
            T::from_f64(station.heading.x),
            T::from_f64(station.heading.y),
            T::from_f64(station.heading.z),
        )),
        energy: arrival_speed.squared() * T::from_f64(0.5),
        time: T::ZERO,
    };
    let mut s = params.iter().fold(T::ZERO, |a, p| a + p.length);

    for index in (from..model.spec.elements.len()).rev() {
        let element = &model.spec.elements[index];
        let p = params[index];
        let steps = T::from_f64(STEPS_PER_ELEMENT as f64);
        let step = -(p.length / steps);
        // The entry speed is what the backward pass is on its way to finding,
        // so it borrows the forward pass's — exact once the two halves agree,
        // which is the joint residual's whole job.
        let entry_speed = forward[index].entry_speed;

        let demand = speed_demand(element, &p, entry_speed, g0, ramp);

        for k in 0..STEPS_PER_ELEMENT {
            let left = T::from_f64((STEPS_PER_ELEMENT - k) as f64);
            let u0 = left / steps;
            let u1 = (left - T::from_f64(0.5)) / steps;

            let (d0, _) = derivative(
                &state,
                element,
                &p,
                u0,
                s,
                &[],
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

            let half = step * T::from_f64(0.5);
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
                &[],
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
                position: state.position + d1.tangent * step,
                // Same midpoint update as the forward pass: full-step rotation
                // is applied to the step's starting tangent, not the midpoint's.
                carrier: state.carrier.transport_to(d0.tangent + d1.curvature * step),
                energy: state.energy + d1.energy * step,
                time: state.time + d1.time * step,
            };
            s += step;
        }
    }

    Start {
        position: state.position,
        carrier: state.carrier,
        speed: (state.energy.max(min_energy) * T::from_f64(2.0)).sqrt(),
        time: state.time,
        s,
    }
}

/// Closes the sample list on the final state and fills the whole-ride
/// measurements that need every sample to exist first.
fn close_and_measure<T: Scalar>(
    model: &RideModel,
    params: &[Params<T>],
    end: &Start<T>,
    samples: &mut Vec<Sample<T>>,
    results: &mut [ElementResult<T>],
    history: &[(T, Vec3<T>)],
) {
    let vehicle = &model.vehicle;
    let offsets = vehicle.row_offsets();
    let mass = T::from_f64(vehicle.mass());
    let drag_factor = T::from_f64(0.5 * model.site.air_density * vehicle.cda()) / mass;
    let thrust_cap = T::from_f64(vehicle.thrust_max) / mass;
    let brake_cap = T::from_f64(vehicle.brake_max_decel);
    let g0 = T::from_f64(G0);
    let gravity = Vec3::new(T::ZERO, T::ZERO, -g0);
    let min_energy = T::from_f64(0.5 * MIN_SPEED * MIN_SPEED);

    // Close the sample list on the final state, so the last sample is the end
    // of the ride rather than one step short of it.
    let state = State {
        position: end.position,
        carrier: end.carrier,
        energy: end.speed.squared() * T::from_f64(0.5),
        time: end.time,
    };
    let last = model.spec.elements.len() - 1;
    let (_, mut final_sample) = derivative(
        &state,
        &model.spec.elements[last],
        &params[last],
        T::ONE,
        end.s,
        history,
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

    // Rider-felt rise and drop: this element's high point to the valley either
    // side of it. The valley is found by walking out, not by taking a minimum
    // over a fixed window — a window reaching into the next element reports the
    // bottom of the *next* descent, which on a cliff ride is a hundred metres
    // of somebody else's geometry. A geometric element measures within its own
    // endpoints instead: its pitch is authored and monotone, and the walk out
    // of a grade continues through the equally monotone grade before it, so a
    // pin on one would bind the combined climb of both.
    for (i, result) in results.iter_mut().enumerate() {
        let first = i * STEPS_PER_ELEMENT;
        let last = (first + STEPS_PER_ELEMENT).min(samples.len() - 1);
        let height = |k: &usize| samples[*k].position.z.to_f64();
        let peak = (first..=last)
            .max_by(|a, b| height(a).total_cmp(&height(b)))
            .unwrap_or(first);
        if model.spec.elements[i].pitch_deg.is_some() {
            result.rise = samples[peak].position.z - samples[first].position.z;
            result.drop = samples[peak].position.z - samples[last].position.z;
        } else {
            result.rise = samples[peak].position.z - valley(samples, peak, -1);
            result.drop = samples[peak].position.z - valley(samples, peak, 1);
        }
        result.crest_speed = samples[peak].speed;
        result.exit_pitch = vc_math::units::to_degrees(samples[last].frame.tangent.z.asin());

        // Heading, accumulated in steps small enough that none can turn far
        // enough to wrap. Sampled coarsely: the sum is the same angle whether
        // it is taken in a hundred pieces or in sixteen hundred, and this runs
        // inside every Jacobian column.
        let mut turned = T::ZERO;
        let mut previous = samples[first].frame.tangent;
        for step in samples[first..=last].iter().step_by(HEADING_STRIDE).skip(1) {
            let next = step.frame.tangent;
            turned += (previous.x * next.y - previous.y * next.x)
                .atan2(previous.x * next.x + previous.y * next.y);
            previous = next;
        }
        result.heading_change = vc_math::units::to_degrees(turned);
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

    let gravity_across = gravity - tangent * gravity.dot(tangent);
    // Force-driven track bends to produce the authored force; a geometric
    // section follows its authored pitch and the force is measured off it.
    // Data decides which, never a name.
    let (curvature, normal_g, lateral_g) = if let Some(pitch) = &element.pitch_deg {
        let (_, slope) = pitch.evaluate(u);
        let rate = vc_math::units::from_degrees(slope) / p.length;
        let lift = {
            let up_world = Vec3::new(T::ZERO, T::ZERO, T::ONE);
            let perp = up_world - tangent * up_world.dot(tangent);
            perp / perp.norm().max(T::from_f64(1e-6))
        };
        let curvature = lift * rate;
        let felt = curvature * speed.squared() - gravity_across;
        (
            curvature,
            felt.dot(frame.up) / g0,
            felt.dot(frame.right) / g0,
        )
    } else {
        // Curvature: the felt force, plus the part of gravity that acts
        // across the direction of travel, divided by speed squared.
        let felt = frame.up * (normal_g * g0) + frame.right * (lateral_g * g0);
        (
            (felt + gravity_across) / speed.squared(),
            normal_g,
            lateral_g,
        )
    };

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

/// Metres the track must climb back out of a dip before it counts as a valley
/// rather than a wobble.
const VALLEY_REBOUND: f64 = 3.0;

/// Steps between samples when accumulating heading.
const HEADING_STRIDE: usize = 16;

/// The height of the valley reached by walking away from `peak` in `direction`.
///
/// Tracks the running minimum and stops once the track has climbed back out of
/// it, so what comes back is the bottom of *this* descent and not of the one
/// after it. Bounded to two elements' worth of travel so a monotonic run down a
/// cliff still terminates.
fn valley<T: Scalar>(samples: &[Sample<T>], peak: usize, direction: isize) -> T {
    let mut low = samples[peak].position.z;
    let mut at = peak;
    for _ in 0..2 * STEPS_PER_ELEMENT {
        let Ok(next) = usize::try_from(at as isize + direction) else {
            break;
        };
        let Some(sample) = samples.get(next) else {
            break;
        };
        at = next;
        if sample.position.z.to_f64() < low.to_f64() {
            low = sample.position.z;
        } else if sample.position.z.to_f64() > low.to_f64() + VALLEY_REBOUND {
            break;
        }
    }
    low
}

/// Specific force to ask of the infrastructure so the element exits at its
/// requested speed: the kinetic change, plus the climb a geometric grade
/// already knows about, divided through the engagement window's mean — the
/// window eases to zero at each end, so a demand sized as if it held
/// everywhere under-delivers by exactly the ramp fraction, which is what
/// stalled a lift asked for a feasible speed. Drag and rolling still have
/// their say; that difference is a residual the solve can see, not something
/// corrected here.
fn speed_demand<T: Scalar>(
    element: &Element,
    p: &Params<T>,
    entry_speed: T,
    g0: T,
    ramp: T,
) -> Option<T> {
    p.exit_speed.map(|target| {
        let climb = element.pitch_deg.as_ref().map_or(T::ZERO, |pitch| {
            const SAMPLES: usize = 32;
            let mean_sin = (0..SAMPLES)
                .map(|i| {
                    let u = T::from_f64((i as f64 + 0.5) / SAMPLES as f64);
                    vc_math::units::from_degrees(pitch.sample(u)).sin()
                })
                .fold(T::ZERO, |a, b| a + b)
                / T::from_f64(SAMPLES as f64);
            p.length * mean_sin
        });
        let delivered = T::ONE - (ramp / p.length).clamp(T::from_f64(1e-6), T::from_f64(0.45));
        (target.squared() - entry_speed.squared() + T::from_f64(2.0) * g0 * climb)
            / (T::from_f64(2.0) * p.length * delivered)
    })
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
            max_elevation_span: 10_000.0,
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
                target_average_speed: 0.0,
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
            pitch_deg: None,
            pin: None,
            exit_pitch_deg: 0.0,
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
            pitch_deg: None,
            pin: None,
            exit_pitch_deg: 0.0,
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
    fn a_geometric_grade_holds_its_authored_pitch() {
        // The regression that catches integrator over-rotation: the climb an
        // authored pitch profile implies is exactly the climb the track makes.
        // The 1.5x frame bug rode this 23-degree ramp at 34.5 degrees.
        let mut ramp = level("ramp", 230.0, None);
        ramp.pitch_deg = Some(Channel::new(&[
            (0.0, 0.0),
            (0.1, 23.0),
            (0.9, 23.0),
            (1.0, 0.0),
        ]));
        let expected = 230.0
            * (0..64)
                .map(|i| {
                    ramp.pitch_deg
                        .as_ref()
                        .unwrap()
                        .sample((i as f64 + 0.5) / 64.0)
                        .to_radians()
                        .sin()
                })
                .sum::<f64>()
            / 64.0;
        let model = model_of(vec![ramp], 60.0);
        let ride = run(&model);
        let rise = ride.end().position.z - 100.0;
        assert!((rise - expected).abs() < 0.5, "rise {rise} vs {expected}");
    }

    #[test]
    fn a_fast_turn_has_the_radius_theory_says_mid_element() {
        // Measured mid-element, where an over-rotating integrator has had
        // room to accumulate — the near-start radius check cannot see that.
        // At 200 m/s on a 90-degree bank the felt force is horizontal, so the
        // horizontal path radius is v^2/(n g0); gravity only adds a shallow
        // vertical drift that the horizontal projection ignores.
        let n = 2.5;
        let v = 200.0;
        let element = Element {
            name: "turn",
            normal_g: Channel::flat(n),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(90.0),
            length: Free::fixed(400.0),
            g_scale: Free::fixed(1.0),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: None,
            pitch_deg: None,
            pin: None,
            exit_pitch_deg: 0.0,
        };
        let model = model_of(vec![element], v);
        let ride = run(&model);
        let m = ride.samples.len() / 2;
        let (p0, p1, p2) = (
            ride.samples[m - 200].position,
            ride.samples[m].position,
            ride.samples[m + 200].position,
        );
        let (a, b, c) = ((p0.x, p0.y), (p1.x, p1.y), (p2.x, p2.y));
        let d2 = 2.0 * (a.0 * (b.1 - c.1) + b.0 * (c.1 - a.1) + c.0 * (a.1 - b.1));
        let sq = |p: (f64, f64)| p.0 * p.0 + p.1 * p.1;
        let ux = (sq(a) * (b.1 - c.1) + sq(b) * (c.1 - a.1) + sq(c) * (a.1 - b.1)) / d2;
        let uy = (sq(a) * (c.0 - b.0) + sq(b) * (a.0 - c.0) + sq(c) * (b.0 - a.0)) / d2;
        let radius = ((a.0 - ux).powi(2) + (a.1 - uy).powi(2)).sqrt();
        let expected = v * v / (n * G0);
        assert!(
            (radius - expected).abs() < expected * 0.03,
            "radius {radius} vs {expected}"
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
            pitch_deg: None,
            pin: None,
            exit_pitch_deg: 0.0,
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
    fn a_steep_lift_reaches_the_speed_it_was_asked_for() {
        // The demand must be sized through the engagement window's mean.
        // Without that a lift whose climb dominates its energy budget
        // under-delivers by the ramp fraction and sags to the speed floor
        // instead of reaching a plainly feasible target.
        let mut lift = level("lift", 230.0, Some(11.0));
        lift.pitch_deg = Some(Channel::new(&[
            (0.0, 0.0),
            (0.1, 23.0),
            (0.9, 23.0),
            (1.0, 0.0),
        ]));
        let mut model = model_of(vec![level("station", 40.0, None), lift], 5.0);
        model.vehicle.force_ramp = 22.0;
        let ride = run(&model);
        assert!(
            (ride.elements[1].exit_speed - 11.0).abs() < 0.5,
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
        assert!(
            (ride.elements[1].exit_speed - 5.0).abs() < 0.5,
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
            pitch_deg: None,
            pin: None,
            exit_pitch_deg: 0.0,
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
            pitch_deg: None,
            pin: None,
            exit_pitch_deg: 0.0,
        };
        let coarse = run(&model_of(vec![turn(400.0)], 45.0));
        let fine = run(&model_of(vec![turn(200.0), turn(200.0)], 45.0));

        // Compared at the end of the authored track, before any closer: the
        // closer lands every ride exactly on the station by construction,
        // which would make this comparison vacuous.
        let end_of = |r: &Ride<f64>, e: usize| {
            *r.samples
                .iter()
                .rfind(|s| s.element == e)
                .expect("element has samples")
        };
        let (ce, fe) = (end_of(&coarse, 0), end_of(&fine, 1));
        let gap = (ce.position - fe.position).norm();
        assert!(
            gap < 0.015,
            "endpoint moved {gap} m when the step was halved"
        );
        assert!((ce.speed - fe.speed).abs() < 1e-3);
        assert_eq!(
            coarse.samples.iter().filter(|s| s.element == 0).count(),
            STEPS_PER_ELEMENT + 1
        );
    }

    #[test]
    fn a_geometric_element_measures_its_own_rise_and_a_force_element_does_not() {
        // Two monotone grades back to back: the valley-walk from the second's
        // peak would descend through both, so a pin on the second would bind
        // the combined climb. Geometric elements measure inside their own
        // endpoints; force elements keep the walk.
        let graded = |name: &'static str, deg: f64, length: f64| Element {
            pitch_deg: Some(Channel::new(&[
                (0.0, 0.0),
                (0.25, deg),
                (0.75, deg),
                (1.0, 0.0),
            ])),
            ..level(name, length, None)
        };
        let dip = Element {
            normal_g: Channel::new(&[(0.0, 1.0), (0.3, 0.8), (0.7, 1.2), (1.0, 1.0)]),
            ..level("dip", 100.0, None)
        };
        let model = model_of(
            vec![
                graded("shallow", 6.0, 150.0),
                graded("steep", 12.0, 150.0),
                dip,
            ],
            30.0,
        );
        let ride = run(&model);
        let z_at = |e: usize| {
            let first = ride.samples.iter().position(|s| s.element == e).unwrap();
            let last = ride.samples.iter().rposition(|s| s.element == e).unwrap();
            (
                ride.samples[first].position.z,
                ride.samples[last].position.z,
            )
        };
        let (z0, z1) = z_at(0);
        let (_, z2) = z_at(1);
        let (climb_a, climb_b) = (z1 - z0, z2 - z1);
        assert!(climb_a > 5.0 && climb_b > 10.0, "{climb_a} {climb_b}");
        // The steep grade's rise is its own climb, not both climbs.
        assert!(
            (ride.elements[1].rise - climb_b).abs() < 0.1,
            "rise {} vs own climb {climb_b}",
            ride.elements[1].rise
        );
        // The force element behind them still walks out: its peak is where it
        // starts diving, and its valley is the bottom of the whole ascent, two
        // elements away.
        assert!(
            (ride.elements[2].rise - (climb_a + climb_b)).abs() < 1.0,
            "rise {} vs total climb {}",
            ride.elements[2].rise,
            climb_a + climb_b
        );
    }

    #[test]
    fn reverse_integration_of_level_track_retraces_the_forward_pass() {
        // An open straight cannot both leave and arrive at the station, so the
        // backward pass — which imposes the station as its arrival — lands one
        // whole track length behind it along the heading.
        let model = model_of(vec![level("a", 100.0, None), level("b", 100.0, None)], 30.0);
        let ride = run(&model);
        let params = model.spec.unpack(&model.spec.free_parameters());
        let back = integrate_reverse(&model, &params, &ride.elements, 0, ride.end().speed);
        assert!(
            (back.position - Vec3::new(-200.0, 0.0, 100.0)).norm() < 1e-3,
            "{:?}",
            back.position
        );
        assert!((back.carrier.tangent - Vec3::new(1.0, 0.0, 0.0)).norm() < 1e-6);
        assert!((back.speed - 30.0).abs() < 1e-6, "speed {}", back.speed);
        assert!(back.s.abs() < 1e-6, "s {}", back.s);
    }

    #[test]
    fn reverse_integration_gains_back_the_speed_a_climb_costs() {
        // Run backward down the same grade the forward pass climbed: the energy
        // the climb took must come back, and the track must descend by the
        // climb it undoes.
        let climb = Element {
            pitch_deg: Some(Channel::new(&[
                (0.0, 0.0),
                (0.25, 10.0),
                (0.75, 10.0),
                (1.0, 0.0),
            ])),
            ..level("climb", 150.0, None)
        };
        let model = model_of(vec![climb], 35.0);
        let ride = run(&model);
        let params = model.spec.unpack(&model.spec.free_parameters());
        let back = integrate_reverse(&model, &params, &ride.elements, 0, ride.end().speed);
        assert!((back.speed - 35.0).abs() < 0.1, "speed {}", back.speed);
        let rise = ride.elements[0].rise;
        assert!(rise > 15.0, "the grade barely climbed: {rise}");
        assert!(
            (back.position.z - (100.0 - rise)).abs() < 0.5,
            "z {} vs station minus a climb of {rise}",
            back.position.z
        );
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
