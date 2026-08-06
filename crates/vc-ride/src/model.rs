//! The ride model: everything a ride *is*, as data.
//!
//! Three inputs — spec, site, vehicle — plus the rulebook that says what a
//! rider may be put through. Nothing here decides anything or computes a ride;
//! it is the argument the evaluator takes.
//!
//! The load-bearing idea is that **every element is the same kind of thing**. A
//! top hat and an airtime hill are not two shapes with two pieces of maths
//! behind them; they are two sets of numbers in the same three curves. Force
//! Vector Design says a ride is specified by, at each point along the track,
//! the vertical g the rider feels, the lateral g they feel, and how far the
//! track is banked. That is exactly three quantities, which is exactly the
//! three components of the frame's rotation rate — no more, or the roll is
//! undetermined; no fewer, or the system is over-specified. Geometry is then
//! solved from those three, never drawn.
//!
//! So an element is three curves plus a handful of scalars the solve is allowed
//! to move. Adding an element type means adding data. There is no place in this
//! crate where an element's name is branched on.

use vc_math::Scalar;
use vc_math::vec3::Vec3;

/// A number the solve may vary, and the bounds engineering puts on it.
///
/// A pinned value is one whose bounds have collapsed, not a separate case.
#[derive(Clone, Copy, Debug)]
pub struct Free {
    /// Starting value, and the value used when this parameter is not free.
    pub value: f64,
    /// Lower bound.
    pub lo: f64,
    /// Upper bound.
    pub hi: f64,
}

impl Free {
    /// A parameter the solve may move within bounds.
    pub const fn new(value: f64, lo: f64, hi: f64) -> Self {
        Self { value, lo, hi }
    }

    /// A parameter the solve may not move.
    pub const fn fixed(value: f64) -> Self {
        Self {
            value,
            lo: value,
            hi: value,
        }
    }

    /// Whether the solve has any room here.
    pub fn is_free(self) -> bool {
        self.hi > self.lo
    }
}

/// One curve across an element, keyed in normalised progress from 0 to 1.
///
/// Between keys the value follows a quintic smoothstep, whose slope *and*
/// curvature are zero at both ends. That choice is the whole jerk story: a
/// linear ramp would make jerk jump at every key, a cubic would make it
/// continuous but non-zero, and the quintic makes the force curve join its
/// neighbours smoothly enough that no separate smoothing pass is ever needed.
/// Bounded jerk falls out of the representation rather than being imposed on
/// top of it.
#[derive(Clone, Debug)]
pub struct Channel {
    keys: Vec<(f64, f64)>,
}

impl Channel {
    /// A curve through the given `(progress, value)` keys.
    ///
    /// Panics if empty, or if the keys are not in increasing order of
    /// progress — both are authoring mistakes with no sensible interpretation.
    pub fn new(keys: &[(f64, f64)]) -> Self {
        assert!(!keys.is_empty(), "a channel needs at least one key");
        assert!(
            keys.windows(2).all(|w| w[1].0 > w[0].0),
            "channel keys must increase in progress"
        );
        Self {
            keys: keys.to_vec(),
        }
    }

    /// A curve holding one value throughout.
    pub fn flat(value: f64) -> Self {
        Self::new(&[(0.0, value)])
    }

    /// The value at progress `u`, clamped outside `[0, 1]`.
    pub fn sample<T: Scalar>(&self, u: T) -> T {
        self.evaluate(u).0
    }

    /// The value and its derivative with respect to progress at `u`.
    pub fn evaluate<T: Scalar>(&self, u: T) -> (T, T) {
        let i = self.segment(u.to_f64());
        let (a, va) = self.keys[i];
        let Some(&(b, vb)) = self.keys.get(i + 1) else {
            return (T::from_f64(va), T::ZERO);
        };
        let width = b - a;
        let x = ((u - T::from_f64(a)) / T::from_f64(width)).clamp(T::ZERO, T::ONE);
        let span = T::from_f64(vb - va);
        // Quintic smoothstep and its derivative.
        let smooth = x.powi(3)
            * (T::from_f64(10.0) - T::from_f64(15.0) * x + T::from_f64(6.0) * x.squared());
        let slope = T::from_f64(30.0) * x.squared() * (T::ONE - x).squared();
        (
            T::from_f64(va) + span * smooth,
            span * slope / T::from_f64(width),
        )
    }

    /// The average value across the element.
    ///
    /// Used to seed the pitch trim: over a stretch where speed does not change
    /// much, an element climbs or descends according to whether its mean
    /// vertical force is above or below the one g that holds it level.
    pub fn mean(&self) -> f64 {
        const SAMPLES: usize = 64;
        (0..SAMPLES)
            .map(|i| self.sample((i as f64 + 0.5) / SAMPLES as f64))
            .sum::<f64>()
            / SAMPLES as f64
    }

    /// Index of the last key at or below `u`, by value.
    fn segment(&self, u: f64) -> usize {
        let last = self.keys.len() - 1;
        self.keys
            .iter()
            .rposition(|&(at, _)| at <= u)
            .unwrap_or(0)
            .min(last)
    }
}

/// One stretch of track, described by what the rider feels across it.
#[derive(Clone, Debug)]
pub struct Element {
    /// What to call it in a report. Never branched on.
    pub name: &'static str,
    /// Rider-frame vertical g across the element. 1.0 is level track.
    pub normal_g: Channel,
    /// Rider-frame lateral g. Zero is a coordinated, properly-banked turn.
    pub lateral_g: Channel,
    /// Bank angle in degrees, right-handed about the direction of travel, so
    /// positive banks a left turn.
    pub bank_deg: Channel,
    /// Arclength of the element, metres.
    pub length: Free,
    /// Multiplies the *departure from level* of the force channels, so scaling
    /// an element makes it stronger without bending straight track.
    pub g_scale: Free,
    /// A constant added to the vertical force across the whole element.
    ///
    /// This is the parameter that decides whether an element climbs, holds its
    /// height or descends, and without it the solve is helpless about
    /// altitude: scaling a hill scales its crest and its pull-out together,
    /// which changes how it feels but not where it ends up. A constant offset
    /// moves the balance directly.
    pub trim: Free,
    /// Multiplies the bank channel. Fixed for elements with no bank, since a
    /// parameter nothing responds to is a rank-deficient column in the solve's
    /// Jacobian, not a harmless extra degree of freedom.
    pub roll_scale: Free,
    /// Speed the infrastructure brings the train to by the end of this element.
    /// `Some` for launches, lifts and brakes; `None` wherever it coasts.
    ///
    /// One field covers all of them deliberately: whether that speed change is
    /// achievable, and how, is a property of the vehicle's propulsion, not of
    /// the track.
    pub speed_control: Option<Free>,
    /// Height above the station the element's high point must reach, if the
    /// human pinned one. An outcome the solve must hit, not an input.
    pub pin_apex_m: Option<f64>,
}

/// Fraction of an element over which the pitch trim eases in and out.
///
/// The trim must vanish at both ends. Every channel is authored to sit at one
/// g where elements meet, so a constant offset would step the felt force at
/// each seam — and a step in force is unbounded jerk, which the analysis then
/// reports as a comfort failure the solver cannot fix because it is an
/// artefact of the parameterisation rather than of the ride.
const TRIM_RAMP: f64 = 0.12;

impl Element {
    /// What the rider feels at progress `u`, given this element's solved
    /// parameters: `(normal g, lateral g, bank in radians)`.
    pub fn felt<T: Scalar>(&self, u: T, p: &Params<T>) -> (T, T, T) {
        let ramp = T::from_f64(TRIM_RAMP);
        let ease = |x: T| {
            let x = x.clamp(T::ZERO, T::ONE);
            x.powi(3) * (T::from_f64(10.0) - T::from_f64(15.0) * x + T::from_f64(6.0) * x.squared())
        };
        let window = ease(u / ramp) * ease((T::ONE - u) / ramp);
        let normal = T::ONE + (self.normal_g.sample(u) - T::ONE) * p.g_scale + p.trim * window;
        let lateral = self.lateral_g.sample(u) * p.g_scale;
        let bank = vc_math::units::from_degrees(self.bank_deg.sample(u)) * p.roll_scale;
        (normal, lateral, bank)
    }

    /// The constant trim that would, to first order, leave this element at the
    /// height it started.
    ///
    /// The part of the felt force that fights gravity is the vertical one, and
    /// on banked track that is `n * cos(bank)`. Averaging that across the
    /// element and asking for one gives the offset directly. It is only a
    /// seed — speed varies along an element and this assumes it does not — but
    /// a seed that holds its altitude is the difference between a solve that
    /// converges and one that starts a kilometre underground.
    pub fn level_trim(&self) -> f64 {
        const SAMPLES: usize = 64;
        let at = |i: usize| (i as f64 + 0.5) / SAMPLES as f64;
        let cosines: f64 = (0..SAMPLES)
            .map(|i| vc_math::units::from_degrees(self.bank_deg.sample(at(i))).cos())
            .sum::<f64>()
            / SAMPLES as f64;
        let vertical: f64 = (0..SAMPLES)
            .map(|i| {
                let u = at(i);
                self.normal_g.sample(u)
                    * vc_math::units::from_degrees(self.bank_deg.sample(u)).cos()
            })
            .sum::<f64>()
            / SAMPLES as f64;
        // A frame spending as much time inverted as upright cannot be trimmed
        // level at all; leave it alone rather than dividing by nothing.
        // The trim is windowed to zero at the seams, so it delivers only its
        // mean share; ask for correspondingly more.
        let window_mean = 1.0 - TRIM_RAMP;
        if cosines.abs() < 0.15 {
            0.0
        } else {
            (1.0 - vertical) / (cosines * window_mean)
        }
    }

    /// The rate of change of bank with progress, radians per unit progress.
    /// Roll rate per second is this divided by the time to cross the element.
    pub fn bank_slope<T: Scalar>(&self, u: T, p: &Params<T>) -> T {
        vc_math::units::from_degrees(self.bank_deg.evaluate(u).1) * p.roll_scale
    }
}

/// One element's free parameters, as the solve currently has them.
#[derive(Clone, Copy, Debug)]
pub struct Params<T: Scalar> {
    /// Arclength, metres.
    pub length: T,
    /// Force multiplier.
    pub g_scale: T,
    /// Constant added to the vertical force.
    pub trim: T,
    /// Bank multiplier.
    pub roll_scale: T,
    /// Target exit speed where the infrastructure sets one.
    pub exit_speed: Option<T>,
}

/// Where the ride starts and must return to.
#[derive(Clone, Copy, Debug)]
pub struct Station {
    /// Heartline position at the start of the first element.
    pub position: Vec3<f64>,
    /// Direction of travel leaving the station. Need not be normalised.
    pub heading: Vec3<f64>,
    /// Speed the train leaves the station at, metres per second.
    ///
    /// Not decoration. Curvature is felt force divided by speed squared, so a
    /// ride specified by forces is singular at a standstill; the train is
    /// always moving, as a real one on a powered station advance is.
    pub dispatch_speed: f64,
}

/// The element sequence, and the station it closes back to.
#[derive(Clone, Debug)]
pub struct Spec {
    /// Where the ride begins and ends.
    pub station: Station,
    /// The elements, in order.
    pub elements: Vec<Element>,
}

impl Spec {
    /// The free parameters, flattened in a fixed order: for each element,
    /// length, force scale, bank scale and exit speed, skipping any that are
    /// pinned.
    ///
    /// Pinned parameters are left out rather than carried and clamped: a
    /// column of the Jacobian that cannot move is a rank deficiency the solver
    /// has to work around.
    pub fn free_parameters(&self) -> Vec<f64> {
        self.each_free().map(|(_, f)| f.value).collect()
    }

    /// Bounds matching [`Self::free_parameters`].
    pub fn bounds(&self) -> Vec<(f64, f64)> {
        self.each_free().map(|(_, f)| (f.lo, f.hi)).collect()
    }

    /// Human-readable names matching [`Self::free_parameters`], for diagnostics.
    pub fn parameter_names(&self) -> Vec<String> {
        self.each_free().map(|(name, _)| name).collect()
    }

    /// Rebuilds per-element parameters from a flat vector, filling pinned
    /// values from the model.
    pub fn unpack<T: Scalar>(&self, x: &[T]) -> Vec<Params<T>> {
        let mut next = x.iter().copied();
        let mut take = |f: &Free| -> T {
            if f.is_free() {
                next.next().unwrap_or(T::from_f64(f.value))
            } else {
                T::from_f64(f.value)
            }
        };
        self.elements
            .iter()
            .map(|e| Params {
                length: take(&e.length),
                g_scale: take(&e.g_scale),
                trim: take(&e.trim),
                roll_scale: take(&e.roll_scale),
                exit_speed: e.speed_control.as_ref().map(&mut take),
            })
            .collect()
    }

    fn each_free(&self) -> impl Iterator<Item = (String, Free)> + '_ {
        self.elements.iter().flat_map(|e| {
            [
                ("length", Some(e.length)),
                ("g_scale", Some(e.g_scale)),
                ("trim", Some(e.trim)),
                ("roll_scale", Some(e.roll_scale)),
                ("exit_speed", e.speed_control),
            ]
            .into_iter()
            .filter_map(move |(what, f)| {
                f.filter(|f| f.is_free())
                    .map(|f| (format!("{}.{what}", e.name), f))
            })
        })
    }
}

/// The ground. A first-class input, never a flat default.
#[derive(Clone, Debug)]
pub struct Terrain {
    /// World position of sample `(0, 0)`.
    pub origin: (f64, f64),
    /// Metres between samples, both axes.
    pub spacing: f64,
    /// Samples per row (the x direction).
    pub nx: usize,
    /// Ground heights, row-major, metres.
    pub heights: Vec<f64>,
}

impl Terrain {
    /// Ground height under a world position.
    ///
    /// Bicubic, not bilinear. Bilinear interpolation has a slope that jumps at
    /// every cell edge, and the solve reads terrain through a clearance
    /// constraint whose gradient it differentiates: a discontinuous slope makes
    /// that gradient lie, and the solver walks into the hill.
    pub fn height<T: Scalar>(&self, x: T, y: T) -> T {
        let ny = self.heights.len() / self.nx;
        let gx = (x - T::from_f64(self.origin.0)) / T::from_f64(self.spacing);
        let gy = (y - T::from_f64(self.origin.1)) / T::from_f64(self.spacing);
        let ix = gx.to_f64().floor();
        let iy = gy.to_f64().floor();
        let fx = gx - T::from_f64(ix);
        let fy = gy - T::from_f64(iy);

        let mut rows = [T::ZERO; 4];
        for (j, row) in rows.iter_mut().enumerate() {
            let mut cols = [T::ZERO; 4];
            for (i, col) in cols.iter_mut().enumerate() {
                let sx = clamp_index(ix as i64 + i as i64 - 1, self.nx);
                let sy = clamp_index(iy as i64 + j as i64 - 1, ny);
                *col = T::from_f64(self.heights[sy * self.nx + sx]);
            }
            *row = catmull_rom(cols, fx);
        }
        catmull_rom(rows, fy)
    }
}

fn clamp_index(i: i64, len: usize) -> usize {
    i.clamp(0, len as i64 - 1) as usize
}

/// Catmull–Rom through the middle two of four samples.
fn catmull_rom<T: Scalar>(v: [T; 4], t: T) -> T {
    let half = T::from_f64(0.5);
    let a = v[1];
    let b = (v[2] - v[0]) * half;
    let c = v[0] - v[1] * T::from_f64(2.5) + v[2] * T::from_f64(2.0) - v[3] * half;
    let d = (v[3] - v[0]) * half + (v[1] - v[2]) * T::from_f64(1.5);
    a + b * t + c * t.squared() + d * t.powi(3)
}

/// Where the ride is built.
#[derive(Clone, Debug)]
pub struct Site {
    /// The ground.
    pub terrain: Terrain,
    /// Metres the heartline must stay above the ground.
    pub min_clearance: f64,
    /// Air density, kg/m³. A site property, not a constant: the reference ride
    /// sits about 900 m up in desert heat, where the air is some 15% thinner
    /// than sea level and the top speed is several km/h higher for it.
    pub air_density: f64,
}

/// The train.
#[derive(Clone, Copy, Debug)]
pub struct Vehicle {
    /// Cars in the train.
    pub cars: usize,
    /// Seating rows per car.
    pub rows_per_car: usize,
    /// Riders abreast in a row.
    pub riders_per_row: usize,
    /// Metres between row centres within a car.
    pub row_pitch: f64,
    /// Metres between car centres, body plus coupler.
    pub car_pitch: f64,
    /// Empty mass of one car, kg.
    pub car_mass: f64,
    /// Design rider mass, kg.
    pub rider_mass: f64,
    /// Height of the roll axis above the rail plane, metres.
    pub heartline_offset: f64,
    /// Drag area of the leading car, m².
    pub cda_lead: f64,
    /// Drag area of each shielded car behind it, m².
    pub cda_trailing: f64,
    /// Rolling resistance as a fraction of normal load.
    pub rolling_resistance: f64,
    /// Peak linear-motor thrust on the whole train, newtons.
    pub thrust_max: f64,
    /// Speed past which linear-motor thrust falls away, metres per second.
    pub thrust_sync_speed: f64,
    /// Strongest braking the infrastructure can apply, m/s².
    pub brake_max_decel: f64,
    /// Distance over which infrastructure force builds up and releases, metres.
    ///
    /// Real linear motors and brakes engage over their entry, not instantly.
    /// Modelling the switch as instantaneous puts a step in the longitudinal
    /// force at every element seam, and a step in force is unbounded jerk —
    /// which the analysis then correctly reports as a comfort failure that the
    /// solver can never fix, because it is an artefact of the model rather
    /// than of the ride.
    pub force_ramp: f64,
    /// Speed above which running gear overheats. `None` is maglev, which is
    /// what "records via parameters" means: no branch, just a missing limit.
    pub wheel_speed_limit: Option<f64>,
}

impl Vehicle {
    /// Total mass of the loaded train, kg.
    pub fn mass(&self) -> f64 {
        let riders = (self.cars * self.rows_per_car * self.riders_per_row) as f64;
        self.cars as f64 * self.car_mass + riders * self.rider_mass
    }

    /// Total drag area, m².
    pub fn cda(&self) -> f64 {
        self.cda_lead + (self.cars.saturating_sub(1)) as f64 * self.cda_trailing
    }

    /// How far behind the leading row each row sits, metres.
    pub fn row_offsets(&self) -> Vec<f64> {
        (0..self.cars)
            .flat_map(|c| {
                (0..self.rows_per_car)
                    .map(move |r| c as f64 * self.car_pitch + r as f64 * self.row_pitch)
            })
            .collect()
    }
}

/// A duration-scaled acceleration limit: how much g a rider may take, as a
/// function of how long it is held.
///
/// Both EN 13814 and ASTM F2291 work this way. A model enforcing one peak
/// number is wrong twice over — it forbids a legal 5 g flash and permits an
/// illegal 3 g helix.
#[derive(Clone, Debug)]
pub struct Envelope {
    /// `(duration in seconds, limit in g)`, increasing in duration,
    /// interpolated linearly between and held flat outside.
    pub points: Vec<(f64, f64)>,
}

impl Envelope {
    /// The limit that applies to a load held for `duration` seconds.
    pub fn at(&self, duration: f64) -> f64 {
        let p = &self.points;
        if duration <= p[0].0 {
            return p[0].1;
        }
        for w in p.windows(2) {
            if duration <= w[1].0 {
                let t = (duration - w[0].0) / (w[1].0 - w[0].0);
                return w[0].1 + t * (w[1].1 - w[0].1);
            }
        }
        p[p.len() - 1].1
    }

    /// The durations this envelope is checked at.
    pub fn durations(&self) -> impl Iterator<Item = f64> + '_ {
        self.points.iter().map(|&(d, _)| d)
    }
}

/// What a rider may be put through. The rulebook, not a design lever.
///
/// Near-future technology buys height and speed; it never buys permission to
/// exceed this. The only thing the vehicle may do is fail to use all of it.
#[derive(Clone, Debug)]
pub struct Limits {
    /// Vertical g into the seat.
    pub normal_positive: Envelope,
    /// Vertical g out of the seat — airtime.
    pub normal_negative: Envelope,
    /// Lateral g, either direction.
    pub lateral: Envelope,
    /// Longitudinal g, either direction.
    pub longitudinal: Envelope,
    /// Rate of change of acceleration, g per second.
    pub jerk: f64,
    /// Bank rate, degrees per second.
    pub roll_rate: f64,
}

/// Everything the evaluator needs.
#[derive(Clone, Debug)]
pub struct RideModel {
    /// The element sequence.
    pub spec: Spec,
    /// The ground it is built on.
    pub site: Site,
    /// The train.
    pub vehicle: Vehicle,
    /// What the riders may take.
    pub limits: Limits,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_flat_channel_holds_its_value_and_has_no_slope() {
        let c = Channel::flat(1.0);
        for u in [0.0_f64, 0.5, 1.0, -2.0, 3.0] {
            let (v, slope) = c.evaluate(u);
            assert!((v - 1.0).abs() < 1e-15);
            assert!(slope.abs() < 1e-15);
        }
    }

    #[test]
    fn a_channel_hits_its_keys_with_zero_slope() {
        // Zero slope at the keys is the jerk guarantee; if this stops holding,
        // force traces get corners.
        let c = Channel::new(&[(0.0, 1.0), (0.3, -0.4), (1.0, 1.6)]);
        for &(at, value) in &[(0.0, 1.0), (0.3, -0.4), (1.0, 1.6)] {
            let (v, slope) = c.evaluate(at);
            assert!((v - value).abs() < 1e-12, "value at {at}");
            assert!(slope.abs() < 1e-9, "slope at {at} was {slope}");
        }
    }

    #[test]
    fn channel_slope_matches_finite_differences() {
        let c = Channel::new(&[(0.0, 1.0), (0.4, -0.3), (1.0, 2.0)]);
        let h = 1e-6;
        for u in [0.1_f64, 0.25, 0.5, 0.75, 0.9] {
            let numeric = (c.sample(u + h) - c.sample(u - h)) / (2.0 * h);
            assert!((c.evaluate(u).1 - numeric).abs() < 1e-5, "at {u}");
        }
    }

    #[test]
    fn channels_are_monotone_between_keys() {
        // Smoothstep must not overshoot: an airtime channel that dips below
        // its own key would report g the design never asked for.
        let c = Channel::new(&[(0.0, 1.0), (1.0, -0.5)]);
        let mut previous = 2.0;
        for i in 0..=100 {
            let v = c.sample(f64::from(i) / 100.0);
            assert!(
                v <= previous + 1e-12 && (-0.5..=1.0).contains(&v),
                "at {i}: {v}"
            );
            previous = v;
        }
    }

    #[test]
    fn scaling_an_element_leaves_level_track_level() {
        // g_scale multiplies the departure from 1 g, so a station stays
        // straight no matter what the solver does to it.
        let e = Element {
            name: "station",
            normal_g: Channel::flat(1.0),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(0.0),
            length: Free::fixed(40.0),
            g_scale: Free::new(1.0, 0.5, 2.0),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: None,
            pin_apex_m: None,
        };
        let p = Params {
            length: 40.0,
            g_scale: 1.9,
            trim: 0.0,
            roll_scale: 1.0,
            exit_speed: None,
        };
        let (n, l, b) = e.felt(0.5, &p);
        assert!((n - 1.0).abs() < 1e-15 && l.abs() < 1e-15 && b.abs() < 1e-15);
    }

    #[test]
    fn envelopes_are_duration_scaled() {
        let e = Envelope {
            points: vec![(0.2, 6.0), (1.0, 6.0), (2.0, 4.0), (5.0, 3.0)],
        };
        assert!((e.at(0.1) - 6.0).abs() < 1e-12, "held flat below the table");
        assert!((e.at(0.5) - 6.0).abs() < 1e-12);
        assert!((e.at(1.5) - 5.0).abs() < 1e-12, "interpolates the ramp");
        assert!(
            (e.at(50.0) - 3.0).abs() < 1e-12,
            "held flat above the table"
        );
    }

    #[test]
    fn flat_terrain_is_flat_everywhere_including_between_samples() {
        // Rule 2: flat ground is terrain at constant height running the real
        // terrain code, so this must be exact, not nearly exact.
        let t = Terrain {
            origin: (0.0, 0.0),
            spacing: 10.0,
            nx: 8,
            heights: vec![42.0; 64],
        };
        for &(x, y) in &[(0.0, 0.0), (13.7, 22.1), (-5.0, 3.0), (500.0, 500.0)] {
            assert!((t.height(x, y) - 42.0).abs() < 1e-12, "at {x}, {y}");
        }
    }

    #[test]
    fn terrain_interpolates_a_slope_exactly() {
        // Catmull-Rom reproduces a linear ramp exactly, so a constant-gradient
        // hillside has no spurious ripple for the solver to catch on.
        let nx = 10;
        let heights: Vec<f64> = (0..nx * nx).map(|i| (i % nx) as f64 * 2.0).collect();
        let t = Terrain {
            origin: (0.0, 0.0),
            spacing: 5.0,
            nx,
            heights,
        };
        for i in 0..20 {
            let x = 10.0 + f64::from(i) * 1.0;
            let expected = x / 5.0 * 2.0;
            assert!((t.height(x, 20.0) - expected).abs() < 1e-10, "at x = {x}");
        }
    }

    #[test]
    fn terrain_gradients_survive_a_cell_boundary() {
        // The reason for bicubic. Sample the slope either side of a grid line;
        // bilinear would show a step here.
        let nx = 12;
        let heights: Vec<f64> = (0..nx * nx)
            .map(|i| {
                let x = (i % nx) as f64;
                20.0 / (1.0 + (-(x - 6.0)).exp())
            })
            .collect();
        let t = Terrain {
            origin: (0.0, 0.0),
            spacing: 10.0,
            nx,
            heights,
        };
        let slope = |x: f64| (t.height(x + 1e-4, 50.0) - t.height(x - 1e-4, 50.0)) / 2e-4;
        let before = slope(59.999);
        let after = slope(60.001);
        assert!(
            (before - after).abs() < 1e-3,
            "slope jumped at the cell edge: {before} vs {after}"
        );
    }

    #[test]
    fn only_free_parameters_are_exposed_to_the_solve() {
        let spec = Spec {
            station: Station {
                position: Vec3::new(0.0, 0.0, 0.0),
                heading: Vec3::new(1.0, 0.0, 0.0),
                dispatch_speed: 2.0,
            },
            elements: vec![Element {
                name: "hill",
                normal_g: Channel::flat(1.0),
                lateral_g: Channel::flat(0.0),
                bank_deg: Channel::flat(0.0),
                length: Free::new(100.0, 50.0, 200.0),
                g_scale: Free::fixed(1.0),
                trim: Free::fixed(0.0),
                roll_scale: Free::fixed(1.0),
                speed_control: Some(Free::new(30.0, 10.0, 40.0)),
                pin_apex_m: None,
            }],
        };
        assert_eq!(spec.free_parameters(), vec![100.0, 30.0]);
        assert_eq!(spec.bounds(), vec![(50.0, 200.0), (10.0, 40.0)]);

        // Unpacking must put them back where they came from and fill the rest.
        let p = spec.unpack(&[123.0, 33.0]);
        assert!((p[0].length - 123.0).abs() < 1e-15);
        assert!((p[0].g_scale - 1.0).abs() < 1e-15);
        assert!((p[0].exit_speed.unwrap() - 33.0).abs() < 1e-15);
    }

    #[test]
    fn a_train_knows_where_its_rows_are() {
        let v = Vehicle {
            cars: 2,
            rows_per_car: 2,
            riders_per_row: 2,
            row_pitch: 0.9,
            car_pitch: 3.0,
            car_mass: 1200.0,
            rider_mass: 75.0,
            heartline_offset: 1.0,
            cda_lead: 1.5,
            cda_trailing: 0.3,
            rolling_resistance: 0.01,
            thrust_max: 200_000.0,
            thrust_sync_speed: 70.0,
            brake_max_decel: 6.0,
            force_ramp: 15.0,
            wheel_speed_limit: Some(75.0),
        };
        assert_eq!(v.row_offsets(), vec![0.0, 0.9, 3.0, 3.9]);
        assert!((v.mass() - (2.0 * 1200.0 + 8.0 * 75.0)).abs() < 1e-12);
        assert!((v.cda() - 1.8).abs() < 1e-12);
    }
}
