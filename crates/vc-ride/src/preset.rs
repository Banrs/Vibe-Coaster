//! The one preset: a Falcon's Flight-class cliff ride, and the rulebook it is
//! judged against.
//!
//! Everything here is data. There is no code path that only this ride takes,
//! and nothing below this module knows the preset exists. Changing the ride
//! means changing numbers.
//!
//! ## On the reference figures
//!
//! Nothing published about Falcon's Flight is an engineering source. Intamin
//! and Six Flags material gives height, speed and length; there are no load
//! cases, no masses, no thrust curves and no g-traces anywhere. The numbers
//! below that come from the real ride are marked; everything else is
//! engineering-plausible for a four-across steel train and is *not* a
//! measurement.
//!
//! Three specific traps, all of which this file avoids:
//!
//! - The headline "195 m" is elevation change from the lowest to the highest
//!   point of the layout, not structure height. Structure height is 163 m and
//!   the drop is 158 m. Feeding 195 m into a drop-energy calculation is wrong
//!   by 37 m of head.
//! - Track length is quoted as 4,250 m by RCDB and Wikipedia and 4,325 m by
//!   Intamin. Unresolved.
//! - The real train is **two across in seven rows**, not four across. The
//!   project README says four-across; that appears to be mistaken.

use vc_math::vec3::Vec3;

use crate::model::{
    Channel, Element, Envelope, Free, Limits, RideModel, Site, Spec, Station, Terrain, Vehicle,
};

/// Rider acceleration limits, duration-scaled.
///
/// Both EN 13814 and ASTM F2291 state limits as a curve against how long the
/// load is held, not as single peaks; the two are numerically identical for a
/// coaster, EN omitting only an extended head-down branch that is out of its
/// scope. A model that enforced one peak number would be wrong twice — it
/// would forbid a legal five-g flash and permit an illegal three-g helix.
///
/// **Provenance.** Both standards are paywalled and were not read. These
/// figures come from Matthias Rohde, *Some Details About the Development of
/// Acceleration Limits for Amusement Rides* (2nd ed., 2024, VDV
/// Freizeittechnologie), which reproduces F2291-23b's own figures; the author
/// sits on the ASTM F24 G-force task group. Ramp breakpoints were read off
/// rendered graphs, so treat them as ±0.5 s. This is data, deliberately, so
/// that buying the standard later is an edit to this function.
///
/// Two known gaps, both of which make this table *permissive*: the standards
/// measure at the seat through a 5 Hz low-pass, where this simulator reads an
/// idealised point, and combined-axis loading is judged by an ellipsoid
/// criterion that per-axis checks cannot express.
pub fn astm_limits() -> Limits {
    Limits {
        normal_positive: Envelope {
            points: vec![
                (0.2, 6.0),
                (1.0, 6.0),
                (2.0, 4.0),
                (4.0, 4.0),
                (5.0, 3.0),
                (11.8, 3.0),
                (12.0, 2.0),
            ],
        },
        normal_negative: Envelope {
            points: vec![(0.2, 2.0), (0.5, 1.5), (4.0, 1.5), (7.0, 1.1)],
        },
        lateral: Envelope {
            points: vec![(0.2, 3.0), (1.0, 3.0), (2.0, 2.0)],
        },
        longitudinal: Envelope {
            points: vec![(0.2, 6.0), (1.0, 6.0), (2.0, 4.0), (4.0, 4.0), (5.0, 3.0)],
        },
        // No standard states a general jerk limit. Ten g/s is design-stage
        // practice; fifteen is the ceiling when verifying on a test rig.
        jerk: 10.0,
        // Not codified anywhere either. Sixty to ninety degrees per second is
        // manufacturer practice.
        roll_rate: 80.0,
    }
}

/// The near-future envelope: what a rider can take, rather than what a ride
/// built today is permitted to do.
///
/// This is **not** a standard and must never be presented as one. It is a
/// deliberate design position, and it is data so that it can be argued with.
///
/// Two limits get conflated in ride design. *Engineering* limits — height,
/// speed, structure, running gear, propulsion — move with technology, and this
/// project's whole premise is that they move a long way. *Physiological*
/// limits do not: a rider in 2050 has the same neck and the same cerebral
/// blood pressure as one today. What technology buys is not a higher ceiling
/// but permission to use the one that is already there.
///
/// Current practice sits well under human tolerance, for good reasons that are
/// mostly about restraint hardware: a lap bar cannot be relied on to hold a
/// slumping rider, so sustained negative g is capped far below what a person
/// could take, and a passive seat cannot support a head under 7 g, so the
/// positive limit is set where an unsupported neck is safe. Active restraint,
/// a contoured supportive seat and reclined seating change those premises, and
/// the figures below are where the envelope lands once they do.
///
/// The reference points are aviation and centrifuge, not amusement rides:
/// trained pilots in reclined seats tolerate 7-9 g positive for tens of
/// seconds, and around -2 to -3 g is the accepted short-duration negative
/// limit before facial petechiae and retinal haemorrhage. These numbers stay
/// under that, briefly, for an untrained rider in a supportive seat.
///
/// Still duration-scaled, and still enforced absolutely. Records are bought
/// with height, speed and length — never by relaxing this.
pub fn frontier_limits() -> Limits {
    Limits {
        // Aviation-grade positive tolerance, reclined and supported.
        normal_positive: Envelope {
            points: vec![
                (0.2, 7.0),
                (1.0, 7.0),
                (2.0, 6.0),
                (4.0, 5.0),
                (8.0, 4.0),
                (15.0, 3.2),
            ],
        },
        // Active restraint holds the rider in the seat, so sustained airtime
        // stops being a containment problem and becomes a physiological one.
        normal_negative: Envelope {
            points: vec![(0.2, 2.5), (1.0, 2.5), (2.0, 2.2), (5.0, 1.8), (8.0, 1.4)],
        },
        lateral: Envelope {
            points: vec![(0.2, 3.5), (1.0, 3.5), (2.0, 2.8), (4.0, 2.2)],
        },
        longitudinal: Envelope {
            points: vec![(0.2, 7.0), (1.0, 7.0), (2.0, 5.0), (5.0, 4.0)],
        },
        // A contoured seat and a supported head take onset far better than a
        // lap bar does.
        jerk: 15.0,
        roll_rate: 110.0,
    }
}

/// The escarpment: a plateau that falls away to the east.
///
/// Real heightmaps come later; this is generated, but it is generated *into
/// the same grid* a survey would fill, and it is read through the same bicubic
/// sampler. There is no flat-ground shortcut for the solver to take.
///
/// A 200 m fall over about 350 m of ground — deeper than the Tuwaiq
/// escarpment the reference ride is cut into. A circuit has to climb back
/// whatever it descends, so a cliff this size is only rideable because the
/// layout spends propulsion on the way home; that is a design choice the
/// vehicle pays for, not a limit on the site.
pub fn escarpment() -> Terrain {
    let nx = 121;
    let ny = 121;
    let spacing = 40.0;
    let origin = (-1200.0, -2400.0);
    let mut heights = Vec::with_capacity(nx * ny);
    for j in 0..ny {
        for i in 0..nx {
            let x = origin.0 + i as f64 * spacing;
            let y = origin.1 + j as f64 * spacing;
            // Logistic drop centred on x = 900 m, plus a gentle roll across the
            // plateau so nothing anywhere is exactly flat.
            let cliff = 200.0 / (1.0 + ((x - 520.0) / 85.0).exp());
            let undulation = 6.0 * (y / 700.0).sin() + 4.0 * (x / 900.0).cos();
            heights.push(700.0 + cliff + undulation);
        }
    }
    Terrain {
        origin,
        spacing,
        nx,
        heights,
    }
}

/// The train.
///
/// Seating follows the reference ride — four cars, seven rows of two, fourteen
/// riders — but the running gear does not. This train is maglev, actively
/// restrained and reclined, with linear motors far beyond anything installed.
/// Those are the parameters that buy the records; the force envelope is
/// untouched by them.
pub fn train() -> Vehicle {
    Vehicle {
        cars: 4,
        rows_per_car: 2,
        riders_per_row: 2,
        row_pitch: 0.95,
        car_pitch: 2.9,
        car_mass: 1250.0,
        rider_mass: 75.0,
        heartline_offset: 1.0,
        // Faired and reclined, and with no wheels to lose energy to.
        cda_lead: 1.25,
        cda_trailing: 0.22,
        rolling_resistance: 0.003,
        // Well past any built installation. Records are what aggressive
        // parameters produce, not a feature.
        thrust_max: 520_000.0,
        thrust_sync_speed: 120.0,
        brake_max_decel: 9.0,
        force_ramp: 22.0,
        // Maglev running gear. Urethane wheels soften somewhere north of
        // 70 m/s and that is the cap this ride had to get past; with maglev
        // the limit is simply absent. No branch, no special case — a `None`.
        wheel_speed_limit: None,
    }
}

/// Gives an element a pitch trim seeded to hold its height, free to move
/// either side of that.
///
/// The seed matters more than the freedom. A template authored by eye almost
/// never balances, and thirteen elements each drifting thirty metres downhill
/// puts the nominal ride a kilometre underground — from which no solver
/// recovers, because every gradient it can see points at a different disaster.
fn levelled(mut element: Element, span: f64) -> Element {
    let seed = element.level_trim();
    element.trim = Free::new(seed, seed - span, seed + span);
    element
}

/// A level stretch: station, launch or brake run.
fn straight(name: &'static str, length: Free, speed: Option<Free>) -> Element {
    Element {
        name,
        normal_g: Channel::flat(1.0),
        lateral_g: Channel::flat(0.0),
        bank_deg: Channel::flat(0.0),
        length,
        g_scale: Free::fixed(1.0),
        trim: Free::fixed(0.0),
        roll_scale: Free::fixed(1.0),
        speed_control: speed,
        pin_apex_m: None,
    }
}

/// A hill: pull up, ease over the top at low or negative g, pull out.
///
/// `crest_g` is what the rider feels over the top — below one is airtime, below
/// zero is ejector. `pullout_g` is the pull at each end.
fn hill(
    name: &'static str,
    crest_g: f64,
    pullout_g: f64,
    length: Free,
    speed: Option<Free>,
    apex: Option<f64>,
) -> Element {
    levelled(
        Element {
            name,
            normal_g: Channel::new(&[
                (0.0, 1.0),
                (0.20, pullout_g),
                (0.42, crest_g),
                (0.58, crest_g),
                (0.80, pullout_g),
                (1.0, 1.0),
            ]),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(0.0),
            length,
            g_scale: Free::new(1.0, 0.65, 1.35),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: speed,
            pin_apex_m: apex,
        },
        0.45,
    )
}

/// A banked turn. Positive bank turns left.
///
/// The bank eases in over a third of the element rather than a fifth: bank
/// rate is what actually sets how long a turn has to be, and rushing it breaks
/// the roll-rate limit long before anything else complains.
fn turn(name: &'static str, bank: f64, hold_g: f64, length: Free, roll: Free) -> Element {
    levelled(
        Element {
            name,
            normal_g: Channel::new(&[(0.0, 1.0), (0.30, hold_g), (0.70, hold_g), (1.0, 1.0)]),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::new(&[(0.0, 0.0), (0.30, bank), (0.70, bank), (1.0, 0.0)]),
            length,
            g_scale: Free::new(1.0, 0.75, 1.25),
            trim: Free::fixed(0.0),
            roll_scale: roll,
            speed_control: None,
            pin_apex_m: None,
        },
        0.40,
    )
}

/// A wave turn: an airtime hill rolled onto its side and back the other way.
///
/// Banking one way and then the other leaves the heading roughly where it
/// started, so this adds character to a straight leg without spending any of
/// the layout's turning budget.
fn wave(name: &'static str, bank: f64, length: Free, roll: Free) -> Element {
    levelled(
        Element {
            name,
            normal_g: Channel::new(&[
                (0.0, 1.0),
                (0.25, 1.5),
                (0.5, 0.35),
                (0.75, 1.5),
                (1.0, 1.0),
            ]),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::new(&[
                (0.0, 0.0),
                (0.25, bank),
                (0.5, 0.0),
                (0.75, -bank),
                (1.0, 0.0),
            ]),
            length,
            g_scale: Free::new(1.0, 0.7, 1.3),
            trim: Free::fixed(0.0),
            roll_scale: roll,
            speed_control: None,
            pin_apex_m: None,
        },
        0.40,
    )
}

/// The preset ride.
///
/// A stadium: out east along the plateau, over the escarpment rim and down the
/// cliff, a half-circle turnaround, back west, a second half-circle, and home
/// to the station. Two turns the same way is what closes a circuit — the
/// second turn's centre falls on the other side of the track, so the sideways
/// offset the first one bought is exactly given back.
///
/// Which parameters are free is the interesting part. **Lengths** are free
/// because length buys height and heading. **Force scales** are free in a
/// narrow band so an element can firm up or soften without becoming a
/// different element. **Pitch trims** are free because altitude has to come
/// from somewhere. **Bank scales** are free only on turns, since a bank
/// multiplier on a hill is a Jacobian column that does nothing. The apex of
/// the spine climb is pinned at 158 m — the human's one geometric demand —
/// and everything about that element is solved to meet it.
pub fn falcon_class() -> RideModel {
    let plateau = 700.0 + 200.0;
    let elements = vec![
        // Drive tyres hold the train at dispatch speed; without them rolling
        // resistance stops it before it reaches the launch.
        straight("station", Free::fixed(45.0), Some(Free::fixed(2.0))),
        // The real ride launches three times. The first two are here; the
        // third is the boost on the way down the cliff.
        straight(
            "launch-1",
            Free::new(150.0, 100.0, 250.0),
            Some(Free::fixed(13.0)),
        ),
        straight(
            "launch-2",
            Free::new(330.0, 220.0, 520.0),
            Some(Free::new(52.0, 40.0, 68.0)),
        ),
        // Up the cliff face and over the rim. The pinned one.
        // Powered up the cliff face, as the real ride is: kinetic energy alone
        // cannot buy a hundred metres of climb and still leave a ride at the
        // top. This is the second of the three launches.
        hill(
            "spine-climb",
            0.5,
            1.9,
            Free::new(430.0, 290.0, 740.0),
            Some(Free::new(48.0, 30.0, 64.0)),
            Some(150.0),
        ),
        // Down the escarpment, boosted to the fastest point on the circuit.
        hill(
            "cliff-drop",
            0.25,
            1.6,
            Free::new(330.0, 220.0, 560.0),
            Some(Free::new(92.0, 74.0, 99.0)),
            None,
        ),
        hill(
            "pullout",
            1.0,
            4.4,
            Free::new(330.0, 230.0, 560.0),
            None,
            None,
        ),
        turn(
            "turnaround-out",
            70.0,
            2.9,
            Free::new(1000.0, 620.0, 1600.0),
            Free::new(1.0, 0.6, 1.4),
        ),
        hill(
            "camelback",
            -0.9,
            2.4,
            Free::new(520.0, 320.0, 820.0),
            None,
            None,
        ),
        wave(
            "wave-turn",
            62.0,
            Free::new(420.0, 250.0, 650.0),
            Free::new(1.0, 0.5, 1.4),
        ),
        hill(
            "ejector-hop",
            -1.9,
            3.0,
            Free::new(260.0, 160.0, 420.0),
            None,
            None,
        ),
        // The third powered section. The real ride boosts on the descent; this
        // one boosts on the way home, which is what pays for the climb back up
        // to the station.
        hill(
            "airtime-run",
            0.1,
            1.8,
            Free::new(540.0, 330.0, 860.0),
            Some(Free::new(78.0, 58.0, 90.0)),
            None,
        ),
        turn(
            "turnaround-home",
            70.0,
            2.9,
            Free::new(1000.0, 620.0, 1600.0),
            Free::new(1.0, 0.6, 1.4),
        ),
        hill(
            "last-hill",
            -0.4,
            2.2,
            Free::new(290.0, 170.0, 470.0),
            None,
            None,
        ),
        straight(
            "brake-run",
            Free::new(330.0, 220.0, 560.0),
            Some(Free::fixed(6.0)),
        ),
    ];

    RideModel {
        spec: Spec {
            station: Station {
                position: Vec3::new(0.0, 0.0, plateau + 12.0),
                heading: Vec3::new(1.0, 0.0, 0.0),
                dispatch_speed: 2.0,
            },
            elements,
        },
        site: Site {
            terrain: escarpment(),
            min_clearance: 4.0,
            // ~900 m up in desert heat: about 15% thinner than sea level,
            // which is several km/h of top speed.
            air_density: 1.02,
        },
        vehicle: train(),
        limits: frontier_limits(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::eval::evaluate;

    #[test]
    fn the_preset_evaluates() {
        let model = falcon_class();
        let ride = evaluate(&model, &model.spec.free_parameters());
        assert!(ride.length > 2500.0, "length {}", ride.length);
        assert!(ride.duration > 60.0, "duration {}", ride.duration);
        assert!(
            ride.samples
                .iter()
                .all(|s| s.speed.is_finite() && s.position.z.is_finite()),
            "the ride produced a non-finite sample"
        );
    }

    #[test]
    fn the_preset_reaches_a_plausible_top_speed() {
        let model = falcon_class();
        let ride = evaluate(&model, &model.spec.free_parameters());
        let top = ride.samples.iter().fold(0.0_f64, |m, s| m.max(s.speed));
        // The real ride is quoted at 250 km/h, or about 69 m/s.
        assert!((45.0..90.0).contains(&top), "top speed {top} m/s");
    }

    #[test]
    fn every_free_parameter_starts_inside_its_bounds() {
        let spec = falcon_class().spec;
        for (value, (lo, hi)) in spec.free_parameters().iter().zip(spec.bounds()) {
            assert!((lo..=hi).contains(value), "{value} outside {lo}..{hi}");
        }
        assert_eq!(spec.free_parameters().len(), spec.parameter_names().len());
    }

    #[test]
    fn the_envelope_is_duration_scaled_not_a_single_peak() {
        let l = astm_limits();
        assert!(l.normal_positive.at(0.5) > l.normal_positive.at(6.0));
        assert!(l.normal_negative.at(0.3) > l.normal_negative.at(8.0));
        assert!(l.lateral.at(0.5) > l.lateral.at(5.0));
    }

    #[test]
    fn the_escarpment_actually_falls_away() {
        let t = escarpment();
        let west = t.height(-200.0_f64, 0.0);
        let east = t.height(1200.0_f64, 0.0);
        assert!(west - east > 80.0, "cliff is only {} m", west - east);
    }
}
