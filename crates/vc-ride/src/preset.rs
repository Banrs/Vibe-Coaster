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
    Channel, Element, Envelope, Free, Limits, Pin, RideModel, Site, Spec, Station, Terrain, Vehicle,
};

/// The standing records this ride is built to beat, and the margin it beats
/// them by.
///
/// **A record figure alone is not a target.** Each was set at its own speed with
/// its own felt g, and those three quantities are not independent: for a
/// force-specified element every length scales as `v²/g₀` times a dimensionless
/// shape factor, so size, speed and intensity determine one another. Pick any
/// two and the third follows. The trap this table exists to avoid is scaling an
/// element up at a fixed speed — that grows every radius with it and leaves the
/// element *weaker* than the record it beats.
///
/// So only the **geometric** figures are scaled here. Intensity is authored into
/// the force channels and floored so the solve cannot trade it away, and speed
/// is an outcome of the drops and the boosters. Three quantities, three
/// mechanisms, none of them over-specified.
mod record {
    /// Falcon's Flight's camelback, its high point: 163 m of structure. Note
    /// this is *not* its headline 195 m, which is elevation change across the
    /// whole layout, nor its 158 m first drop.
    pub const TALLEST_HILL_M: f64 = 163.0;
    /// Falcon's Flight's cliff dive, the tallest drop built.
    pub const TALLEST_DROP_M: f64 = 158.0;
    /// Falcon's Flight, the fastest built, m/s (250 km/h).
    pub const FASTEST_MS: f64 = 69.4;
    /// Geometric margin over the record. Applied to lengths only.
    pub const MARGIN: f64 = 1.25;
}

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
        // No standard states a general jerk limit. Rohde, p.40: fifteen g/s is
        // "the max. allowable value when proving the design", and designers
        // work to "5 g/s or max. 10 g/s in the design phase". Ten here.
        // Corroborated by ISO/TS 17929:2014; a real dive coaster's valley was
        // measured at about seven.
        jerk: 10.0,
        // Not codified anywhere either — Rohde, §7.6.2: "rotational
        // accelerations are not mentioned and not measured". Eighty is the
        // red threshold in openFVD's own colour bands, which is the closest
        // thing to a practitioner consensus that exists.
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
        // Whinnery & Forster and the Naval Flight Surgeon's Manual (via Rohde
        // §7.2.7) support 3-5 Gy sustained beyond a minute; four briefly is
        // comfortably inside that. Ratified by Daniel 2026-08-07.
        lateral: Envelope {
            points: vec![(0.2, 4.0), (1.0, 4.0), (2.0, 3.0), (4.0, 2.5)],
        },
        longitudinal: Envelope {
            points: vec![(0.2, 7.0), (1.0, 7.0), (2.0, 5.0), (5.0, 4.0)],
        },
        // A contoured seat and a supported head take onset far better than a
        // lap bar does. Fifteen is not an invention: it is the figure Rohde
        // gives as the maximum allowable when proving a design on the rig,
        // adopted here as the design value rather than the verification one.
        jerk: 15.0,
        // Above openFVD's red band at eighty, and deliberately. No standard
        // states a roll-rate limit at all, so this is a position, not a
        // reading — active restraint is the argument for it.
        roll_rate: 110.0,
    }
}

/// Height of the escarpment, metres.
///
/// Sized against the 320 m elevation budget rather than maximised: the ride
/// now lives at the cliff base and climbs the face once, the way the
/// reference ride does, so the cliff only needs to be tall enough that a
/// 198 m rider-felt dive plus its pull-out fits down the far side.
pub const CLIFF_M: f64 = 290.0;

/// The escarpment: a plateau that falls away to the east.
///
/// Real heightmaps come later; this is generated, but it is generated *into
/// the same grid* a survey would fill, and it is read through the same bicubic
/// sampler. There is no flat-ground shortcut for the solver to take.
///
/// A circuit has to climb back whatever it descends, so a cliff this size is
/// only rideable because the layout spends propulsion on the way home; that is
/// a design choice the vehicle pays for, not a limit on the site.
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
            let cliff = CLIFF_M / (1.0 + ((x - 520.0) / 110.0).exp());
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
/// How far either side of level a pitch trim may range, g.
///
/// Wide, because the trim is now the only thing aiming an element. It has to be
/// able to swing a kilometre-long hill by tens of degrees of exit pitch.
const TRIM_SPAN: f64 = 0.7;

fn levelled(mut element: Element, span: f64) -> Element {
    /// Largest pitch trim a seed may ask for, g.
    ///
    /// The trim is a nudge, not a redefinition of the element. A force profile
    /// that cannot be levelled inside this is one that is *meant* to change
    /// height — a pull-out, a dive — and flattening it cancels the very forces
    /// it exists to deliver. Uncapped, the seed for a 6.8 g valley came out at
    /// −2.3 g and quietly turned it into a 4.2 g one.
    const MAX_TRIM: f64 = 0.6;

    let seed = element.level_trim().clamp(-MAX_TRIM, MAX_TRIM);
    element.trim = Free::new(seed, seed - span, seed + span);
    element
}

/// A geometric section at a constant grade: station, launch, lift, brake run.
///
/// Pitch is authored — level in, up to `grade_deg`, level out — and the felt
/// force is measured, because a force profile cannot hold a straight grade:
/// `n = cos θ` is a knife-edge, and an earlier climb authored as force looped
/// through 791 degrees trying to sit on it. This is the FVD boundary, drawn
/// where practitioners draw it.
fn grade(
    name: &'static str,
    grade_deg: f64,
    length: Free,
    speed: Option<Free>,
    pin: Option<Pin>,
) -> Element {
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
        pitch_deg: Some(if grade_deg == 0.0 {
            Channel::flat(0.0)
        } else {
            spread(&[0.0, grade_deg, grade_deg, 0.0], 0.45)
        }),
        pin,
        exit_pitch_deg: 0.0,
    }
}

/// A dead-level geometric stretch: station, flat launch, brake run.
fn straight(name: &'static str, length: Free, speed: Option<Free>) -> Element {
    grade(name, 0.0, length, speed, None)
}

/// Channel keys with each swing's width in proportion to the g it crosses —
/// the minimax split. A big swing gets a long ramp and a small correction a
/// short one, so peak jerk is even across the element instead of spiking
/// wherever a fixed grid squeezed a large Δg into a narrow slot. It also
/// removes the micro-flats: no ramp is wider than its swing deserves, so the
/// track stops dwelling at one g between moves.
///
/// Equal neighbours are holds; they share whatever `ramp_budget` leaves.
fn spread_keys(values: &[f64], ramp_budget: f64) -> Vec<(f64, f64)> {
    let weights: Vec<f64> = values.windows(2).map(|w| (w[1] - w[0]).abs()).collect();
    let swing: f64 = weights.iter().sum();
    let holds = weights.iter().filter(|w| **w == 0.0).count();
    let hold_width = if holds > 0 {
        (1.0 - ramp_budget) / holds as f64
    } else {
        0.0
    };
    let budget = if holds > 0 { ramp_budget } else { 1.0 };
    let mut at = 0.0;
    let mut keys = vec![(0.0, values[0])];
    for (w, &v) in weights.iter().zip(&values[1..]) {
        at += if *w == 0.0 {
            hold_width
        } else {
            budget * w / swing
        };
        keys.push((at.min(1.0), v));
    }
    keys.last_mut().expect("non-empty").0 = 1.0;
    keys
}

fn spread(values: &[f64], ramp_budget: f64) -> Channel {
    Channel::new(&spread_keys(values, ramp_budget))
}

/// An arc in the vertical plane: ease into `middle_g`, hold it, ease out
/// through `ends_g`.
///
/// One builder covers hills and valleys, which is the architecture's claim made
/// concrete. `middle_g` below one is a crest — below zero is ejector airtime —
/// and `middle_g` above one is a pull-out. Nothing distinguishes them but the
/// number, and the geometry that comes back is a crest or a valley accordingly.
///
/// The middle is held over a tenth of the element rather than a third. Peak g
/// is limited by *duration*, not by magnitude: the envelope allows seven g for
/// a moment and six for two seconds, so a brief spike buys intensity that a
/// plateau of the same height would spend on a violation.
fn arc(
    name: &'static str,
    middle_g: f64,
    ends_g: f64,
    length: Free,
    speed: Option<Free>,
    pin: Option<Pin>,
) -> Element {
    levelled(
        Element {
            name,
            normal_g: spread(&[1.0, ends_g, middle_g, middle_g, ends_g, 1.0], 0.90),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::flat(0.0),
            length,
            // Floored at one: the solve may firm an element up but never soften
            // it. Softening is the cheapest way to buy closure, and it is how
            // an earlier version of this ride ended up at 3.3 g inside a 7 g
            // envelope — big because it was weak.
            g_scale: Free::new(1.0, 1.0, 1.45),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: speed,
            pitch_deg: None,
            pin,
            // An arc is symmetric, so level in and level out is what it is for.
            exit_pitch_deg: 0.0,
        },
        TRIM_SPAN,
    )
}

/// A dive: crest over the top and stay there.
///
/// One-sided, unlike [`arc`], and that is the whole point. A symmetric profile
/// pitches down and then back up by the same amount, so it cannot dive at all —
/// an earlier version of this preset built its cliff dive out of an arc and got
/// an element that finished pointing 82 degrees *up*. The pull-out is the next
/// element's job, which is also how a real layout is drawn.
///
/// Not levelled either: an element whose purpose is to lose two hundred metres
/// is exactly the element a levelling trim must not touch.
fn dive(
    name: &'static str,
    hold_g: f64,
    twist_deg: f64,
    exit_pitch_deg: f64,
    length: Free,
    speed: Option<Free>,
    pin: Pin,
) -> Element {
    Element {
        name,
        // Returns to one g at the very end. Every channel in this file meets
        // its neighbours at one g, and a dive that simply stopped at 0.15 would
        // put a step in the felt force at the seam — unbounded jerk, which cost
        // 177 g/s before this last key was added. Closing it back costs almost
        // no descent: at one g on a 40-degree slope the track curves up by
        // under two degrees over a hundred metres.
        //
        // A hold above one g makes this a *climb* — the same shape pitching the
        // other way, which is what an LSM lift or a launch up a cliff face is.
        // Nothing branches on which it is.
        normal_g: spread(&[1.0, hold_g, hold_g, 1.0], 0.40),
        lateral_g: Channel::flat(0.0),
        // The reference ride's first drop is twisted: a roll on the way down,
        // handed back level before the pull-out.
        bank_deg: if twist_deg == 0.0 {
            Channel::flat(0.0)
        } else {
            Channel::new(&[(0.0, 0.0), (0.35, twist_deg), (0.80, 0.0)])
        },
        length,
        g_scale: Free::new(1.0, 1.0, 1.45),
        trim: Free::new(0.0, -TRIM_SPAN, TRIM_SPAN),
        roll_scale: Free::fixed(1.0),
        speed_control: speed,
        pitch_deg: None,
        pin: Some(pin),
        exit_pitch_deg,
    }
}

/// A zero-g roll: a full heartline rotation taken at almost no felt g.
///
/// The bank sweeps a whole turn while the vertical channel floats near zero,
/// so the rider corkscrews weightless. The bank ends at 360 — the same
/// orientation it started, so the seam is clean — and both scales are fixed:
/// scaling a full roll to 0.9 of a roll would hand the next element a
/// thirty-degree bank it never asked for.
fn zero_g_roll(name: &'static str, length: Free) -> Element {
    levelled(
        Element {
            name,
            normal_g: Channel::new(&[
                (0.0, 1.0),
                (0.22, 0.35),
                (0.50, 0.10),
                (0.78, 0.35),
                (1.0, 1.0),
            ]),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::new(&[(0.0, 0.0), (0.22, 0.0), (0.78, 360.0), (1.0, 360.0)]),
            length,
            g_scale: Free::fixed(1.0),
            trim: Free::fixed(0.0),
            roll_scale: Free::fixed(1.0),
            speed_control: None,
            pitch_deg: None,
            pin: None,
            exit_pitch_deg: 0.0,
        },
        TRIM_SPAN,
    )
}

/// An overbanked turn: banked past ninety, the rider hung over the inside.
///
/// Light in the seat by design — the felt vertical share goes *negative* past
/// ninety degrees, so this cannot hold altitude and is not asked to; the trim
/// aims it. The reference ride's summit moment is one of these.
fn overbank(name: &'static str, bank: f64, hold_g: f64, length: Free, pin: Pin) -> Element {
    levelled(
        Element {
            name,
            normal_g: spread(&[1.0, hold_g, hold_g, 1.0], 0.50),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::new(&[(0.0, 0.0), (0.30, bank), (0.70, bank), (1.0, 0.0)]),
            length,
            g_scale: Free::new(1.0, 1.0, 1.30),
            trim: Free::fixed(0.0),
            roll_scale: Free::new(1.0, 0.85, 1.15),
            speed_control: None,
            pitch_deg: None,
            pin: Some(pin),
            exit_pitch_deg: 0.0,
        },
        TRIM_SPAN,
    )
}

/// A banked turn. Positive bank turns left.
///
/// The bank eases in over a third of the element rather than a fifth: bank
/// rate is what actually sets how long a turn has to be, and rushing it breaks
/// the roll-rate limit long before anything else complains.
fn turn(name: &'static str, bank: f64, hold_g: f64, length: Free, roll: Free, pin: Pin) -> Element {
    // A turn holds its altitude only when the vertical share of the felt force
    // is one g, so `hold_g * cos(bank)` must be about one. At 78 degrees that
    // needs 4.8 g; anything less is a descending turn wearing a level turn's
    // name, and an earlier version of this preset paired 78 degrees with 3.2 g
    // and wondered why the layout sank.
    debug_assert!(
        (hold_g * vc_math::units::from_degrees(bank).cos() - 1.0).abs() < 0.25,
        "{name}: {hold_g} g at {bank} deg does not hold altitude"
    );
    levelled(
        Element {
            name,
            normal_g: Channel::new(&[(0.0, 1.0), (0.30, hold_g), (0.70, hold_g), (1.0, 1.0)]),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::new(&[(0.0, 0.0), (0.30, bank), (0.70, bank), (1.0, 0.0)]),
            length,
            g_scale: Free::new(1.0, 0.9, 1.35),
            trim: Free::fixed(0.0),
            roll_scale: roll,
            speed_control: None,
            pitch_deg: None,
            pin: Some(pin),
            exit_pitch_deg: 0.0,
        },
        TRIM_SPAN,
    )
}

/// A wave turn: an airtime hill rolled onto its side and back the other way.
///
/// Banking one way and then the other leaves the heading roughly where it
/// started, so this adds character to a straight leg without spending any of
/// the layout's turning budget.
fn wave(name: &'static str, bank: f64, length: Free, roll: Free, pin: Pin) -> Element {
    levelled(
        Element {
            name,
            normal_g: spread(&[1.0, 1.5, 0.35, 1.5, 1.0], 1.0),
            lateral_g: Channel::flat(0.0),
            bank_deg: Channel::new(&[
                (0.0, 0.0),
                (0.25, bank),
                (0.5, 0.0),
                (0.75, -bank),
                (1.0, 0.0),
            ]),
            length,
            g_scale: Free::new(1.0, 1.0, 1.35),
            trim: Free::fixed(0.0),
            roll_scale: roll,
            speed_control: None,
            pitch_deg: None,
            pin: Some(pin),
            exit_pitch_deg: 0.0,
        },
        TRIM_SPAN,
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
/// because length buys height and heading. **Force scales** are free upward
/// only, so an element may firm up but never soften. **Pitch trims** are free
/// because altitude has to come from somewhere. **Bank scales** are free only
/// on turns, since a bank multiplier on a hill is a Jacobian column that does
/// nothing.
///
/// ## Where the records are, and why they are where they are
///
/// Size and intensity cannot share an element. Radius is `v²/((n−1)g₀)`, so at
/// the same speed a bigger element is a gentler one — which is why the records
/// are placed rather than piled up:
///
/// - **Size** goes on the camelback, straight off the dive while the speed to
///   pay for it is still there. A 204 m rise crested at ~60 m/s.
/// - **Intensity** goes in the valley beneath it. The fastest point of the
///   circuit is the *only* place a near-seven-g pull has a radius large enough
///   to build; the same g at half the speed would want a quarter of the radius.
/// - **Speed** is the dive plus a booster, and it lands where the pull-out and
///   the camelback both need it.
///
/// Between them sit turns and hops that spend no records, because a ride whose
/// every element is maximal has no shape. Propulsion is one launch and three
/// boosters, roughly one every two kilometres.
pub fn falcon_class() -> RideModel {
    // Flagships sit in a band ~1.25–1.5× the records they beat, ruled
    // 2026-08-07; everything else stays at civilian scale.
    // Camelback elevation as ruled; the flagship band tops out near 1.4x the
    // record it beats, and the assert keeps a future edit inside it.
    let rise = 225.0;
    debug_assert!(rise <= record::TALLEST_HILL_M * 1.4);
    let drop_m = record::TALLEST_DROP_M * record::MARGIN; // 197.5, inside the ruled 175-200 band
    let fastest = record::FASTEST_MS * 1.28;

    // The reference ride's shape, kept: station at the cliff base, a modest
    // lift-and-twisted-drop opener, an airtime cluster of ordinary size, one
    // launch up the cliff face, a light-in-the-seat moment at the summit, a
    // held breath — and then everything at once: the dive, the fastest track,
    // the record camelback. Three headline moments; the rest is connective
    // tissue at civilian scale, because a layout whose every element is
    // maximal has no shape.
    let elements = vec![
        straight("station", Free::fixed(40.0), Some(Free::fixed(5.0))),
        // The opener: an LSM lift — a climb is a dive held above one g — into
        // the reference ride's signature twisted first drop. Deliberately not
        // a record: a third of the tall hill, like the original's 55 m.
        // Grades are ESTIMATES: no gradient is published for any FF section.
        grade(
            "lsm-lift",
            20.0,
            Free::new(230.0, 140.0, 400.0),
            Some(Free::new(11.0, 10.0, 14.0)),
            Some(Pin::Rise(68.0)),
        ),
        dive(
            "twisted-drop",
            0.35,
            48.0,
            -28.0,
            Free::new(130.0, 80.0, 260.0),
            None,
            Pin::Drop(55.0),
        ),
        arc(
            "first-valley",
            3.0,
            1.6,
            Free::new(110.0, 70.0, 220.0),
            None,
            None,
        ),
        // The airtime cluster: a floater, an ejector pop and a wave turn, each
        // at the scale the norms give them, none chasing a record.
        arc(
            "floater-hill",
            -0.25,
            1.7,
            Free::new(180.0, 110.0, 320.0),
            None,
            None,
        ),
        arc(
            "ejector-pop",
            -1.4,
            2.6,
            Free::new(100.0, 60.0, 200.0),
            None,
            None,
        ),
        wave(
            "wave-turn",
            55.0,
            Free::new(220.0, 140.0, 400.0),
            Free::new(1.0, 0.6, 1.3),
            Pin::Turn(0.0),
        ),
        zero_g_roll("zero-g-roll", Free::new(250.0, 190.0, 400.0)),
        // Up the face in one sustained LSM push, the way the original takes
        // its 150 km/h cliff launch.
        grade(
            "cliff-launch",
            12.0,
            Free::new(240.0, 160.0, 380.0),
            Some(Free::new(41.7, 34.0, 46.0)),
            None,
        ),
        grade(
            "cliff-climb",
            24.0,
            Free::new(620.0, 380.0, 1100.0),
            Some(Free::new(30.0, 24.0, 38.0)),
            Some(Pin::Rise(215.0)),
        ),
        // The summit: hung over the edge, then held still before the plunge —
        // the reference ride's one transferable pacing device.
        overbank(
            "rim-overbank",
            104.0,
            0.55,
            Free::new(240.0, 150.0, 440.0),
            Pin::Turn(-90.0),
        ),
        straight(
            "holding-brake",
            Free::new(60.0, 40.0, 110.0),
            Some(Free::new(9.0, 7.0, 12.0)),
        ),
        // Everything at once. The dive is near-vertical like the original's,
        // boosted past the speed record on the way down; the valley under it
        // is the intensity record, and the hill off it is the size record.
        dive(
            "cliff-dive",
            0.12,
            0.0,
            -78.0,
            Free::new(340.0, 240.0, 700.0),
            Some(Free::new(fastest, 76.0, 92.0)),
            Pin::Drop(drop_m),
        ),
        // 6.9 held briefly: the envelope allows 7.0 over 0.2 s, and a flagship
        // that leaves half a g on the table is not using the seat it argued
        // for. The other elements sit at real-coaster proportions below it.
        arc(
            "pullout",
            6.9,
            1.8,
            Free::new(260.0, 160.0, 480.0),
            None,
            None,
        ),
        arc(
            "camelback",
            -0.35,
            2.6,
            Free::new(1100.0, 500.0, 2400.0),
            None,
            Some(Pin::Rise(rise)),
        ),
        // The way home: a sustained helix, one more paid-for hill, a short
        // finale turn, and hard brakes. Fast but shaped, not maximal.
        turn(
            "helix",
            68.0,
            2.75,
            Free::new(540.0, 320.0, 1000.0),
            Free::new(1.0, 0.7, 1.3),
            Pin::Turn(-180.0),
        ),
        arc(
            "speed-hill",
            -0.6,
            2.4,
            Free::new(380.0, 220.0, 700.0),
            Some(Free::new(52.0, 44.0, 62.0)),
            Some(Pin::Rise(90.0)),
        ),
        turn(
            "finale-turn",
            62.0,
            2.15,
            Free::new(300.0, 180.0, 520.0),
            Free::new(1.0, 0.7, 1.3),
            Pin::Turn(-90.0),
        ),
        straight(
            "brake-run",
            Free::new(200.0, 140.0, 300.0),
            Some(Free::fixed(6.0)),
        ),
    ];

    RideModel {
        spec: Spec {
            station: Station {
                // At the cliff base on the low eastern ground, heading at the
                // face — the circuit runs up the cliff and dives back off it.
                position: Vec3::new(1300.0, 0.0, 712.0),
                heading: Vec3::new(-1.0, 0.0, 0.0),
                dispatch_speed: 5.0,
            },
            elements,
            // 151 km/h. Falcon's Flight averages about 71 km/h over its 4,250 m
            // in ~215 s; this asks for more than twice that, which is a demand
            // on the whole layout rather than on any one element.
            target_average_speed: 33.3,
        },
        site: Site {
            terrain: escarpment(),
            min_clearance: 4.0,
            max_elevation_span: 320.0,
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
    fn the_preset_reaches_a_record_top_speed() {
        let model = falcon_class();
        let ride = evaluate(&model, &model.spec.free_parameters());
        let top = ride.samples.iter().fold(0.0_f64, |m, s| m.max(s.speed));
        // The record is 69.4 m/s and this ride exists to beat it. The upper
        // bound is not a target, just a guard: past about 130 m/s the ride has
        // stopped being a coaster and the model has gone wrong somewhere.
        assert!(
            (record::FASTEST_MS..130.0).contains(&top),
            "top speed {top} m/s"
        );
    }

    #[test]
    fn a_positive_bank_turns_right() {
        // The convention, verified rather than asserted in a doc comment. It
        // was documented backwards, and the seeder spent a turnaround through
        // 2,819 degrees chasing the wrong sign before this was pinned down.
        let element = turn(
            "probe",
            72.0,
            3.25,
            Free::fixed(600.0),
            Free::fixed(1.0),
            Pin::Turn(-180.0),
        );
        let mut model = falcon_class();
        model.spec.elements = vec![element];
        model.spec.station.dispatch_speed = 60.0;
        let ride = evaluate(&model, &model.spec.free_parameters());
        assert!(
            ride.elements[0].heading_change < -10.0,
            "positive bank turned {} degrees",
            ride.elements[0].heading_change
        );
    }

    #[test]
    fn seeding_makes_a_geometric_pin_bind() {
        // The whole point of the seeder. As authored, the camelback's length is
        // a guess; after seeding it must actually deliver the demanded rise,
        // because no scale factor could have been written down instead.
        let mut model = falcon_class();
        let index = model
            .spec
            .elements
            .iter()
            .position(|e| e.name == "camelback")
            .expect("the preset has a camelback");
        let Some(Pin::Rise(demanded)) = model.spec.elements[index].pin else {
            panic!("the camelback is the pinned-rise element");
        };

        let before = evaluate(&model, &model.spec.free_parameters()).elements[index].rise;
        crate::solve::seed_geometry(&mut model, 3);
        let after = evaluate(&model, &model.spec.free_parameters()).elements[index].rise;

        assert!(
            (after - demanded).abs() < (before - demanded).abs(),
            "seeding did not help: {before} then {after}, wanted {demanded}"
        );
        assert!(
            (after - demanded).abs() < 15.0,
            "rise came out at {after} against a demanded {demanded}"
        );
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
