//! Generates the preset ride and writes a viewer you can open in a browser.
//!
//! ```text
//! cargo run --release -p vc-ride --bin generate
//! ```
//!
//! Writes `out/ride.json` and `out/ride.html`. The HTML has the ride baked into
//! it, so it opens straight off the filesystem with nothing to serve.

use std::fs;

use vc_ride::analysis::{Analysis, analyse};
use vc_ride::eval::{Ride, evaluate};
use vc_ride::{RideModel, export, preset, solve};

fn main() -> std::io::Result<()> {
    let mut model = preset::falcon_class();

    println!("--- as specified ---");
    report(&model, &evaluate(&model, &model.spec.free_parameters()));

    let (outcome, ride) = solve::solve_two_rounds(&mut model, 60);
    println!("\n--- solve ---\n{}", outcome.summary());
    println!("\n--- as solved ---");
    report(&model, &ride);

    let analysis = analyse(&model, &ride);
    scorecard(&model, &ride, &analysis);

    let failures = analysis.failures();
    if failures.is_empty() {
        println!("\nevery comfort and clearance limit met");
    } else {
        println!("\nlimits broken:");
        for check in &failures {
            println!("  {:<48} over by {:.3}", check.name, check.over);
        }
    }
    for check in &analysis.advisories {
        let verdict = if check.over > 0.0 {
            "OVER by"
        } else {
            "within"
        };
        println!(
            "advisory: {:<38} {} {:.3}",
            check.name,
            verdict,
            check.over.abs()
        );
    }
    println!(
        "buildability: {:.0} m of track, {:.0} support metre-metres, \
         closest approach to the ground {:.1} m",
        analysis.track_length, analysis.support_metres, analysis.min_clearance
    );

    let note = if outcome.converged {
        "solved".to_string()
    } else {
        format!("UNCONVERGED - {}", outcome.worst[0].0)
    };
    let json = export::to_json(&model, &ride, &analysis, &note);

    fs::create_dir_all("out")?;
    fs::write("out/ride.json", &json)?;
    let page = include_str!("../../viewer.html").replace("\"__RIDE__\"", &json);
    fs::write("out/ride.html", page)?;
    println!("\nwrote out/ride.json and out/ride.html");
    Ok(())
}

/// Peak and trough of the felt vertical g across one element.
fn extremes(ride: &Ride<f64>, index: usize) -> (f64, f64) {
    ride.samples
        .iter()
        .filter(|s| s.element == index)
        .fold((f64::MIN, f64::MAX), |(u, d), s| {
            (u.max(s.normal_g), d.min(s.normal_g))
        })
}

fn report(model: &RideModel, ride: &Ride<f64>) {
    println!(
        "{:<16} {:>6} {:>6} {:>6} {:>7} {:>7} {:>7} {:>7} {:>6} {:>6}",
        "element", "len", "enter", "exit", "rise", "drop", "pitch", "turn", "+g", "-g"
    );
    for (i, result) in ride.elements.iter().enumerate() {
        let (up, down) = extremes(ride, i);
        println!(
            "{:<16} {:>6.0} {:>6.1} {:>6.1} {:>7.1} {:>7.1} {:>7.1} {:>7.1} {:>6.2} {:>6.2}",
            result.name,
            result.length,
            result.entry_speed,
            result.exit_speed,
            result.rise,
            result.drop,
            result.exit_pitch,
            result.heading_change,
            up,
            down
        );
    }
    let top = ride.samples.iter().fold(0.0_f64, |m, s| m.max(s.speed));
    let end = ride.end();
    println!(
        "total {:.0} m, {:.0} s, top {:.0} km/h, average {:.0} km/h",
        ride.length,
        ride.duration,
        top * 3.6,
        ride.length / ride.duration * 3.6
    );
    println!(
        "closure gap {:.1} m, heading error {:.1} deg",
        (end.position - model.spec.station.position).norm(),
        end.frame
            .tangent
            .dot(model.spec.station.heading / model.spec.station.heading.norm())
            .clamp(-1.0, 1.0)
            .acos()
            .to_degrees()
    );
}

/// The records this ride exists to beat, checked against what it produced.
///
/// Printed rather than left to the reader: a generator aimed at records that
/// does not say whether it hit them is asking to be believed.
fn scorecard(model: &RideModel, ride: &Ride<f64>, analysis: &Analysis<f64>) {
    let of = |name: &str, pick: fn(&vc_ride::eval::ElementResult<f64>) -> f64| {
        ride.elements
            .iter()
            .find(|e| e.name == name)
            .map_or(0.0, pick)
    };
    let (peak_up, peak_down) = (0..ride.elements.len())
        .map(|i| extremes(ride, i))
        .fold((f64::MIN, f64::MAX), |(u, d), (a, b)| (u.max(a), d.min(b)));

    println!("\n--- records ---");
    println!("{:<22} {:>10} {:>10}", "", "got", "target");
    for (label, got, target, unit) in [
        (
            "tallest hill (rise)",
            of("camelback", |e| e.rise),
            163.0 * 1.25,
            "m",
        ),
        (
            "tallest drop",
            of("cliff-dive", |e| e.drop),
            158.0 * 1.25,
            "m",
        ),
        ("top speed", analysis.top_speed * 3.6, 250.0 * 1.28, "km/h"),
        (
            "average speed",
            analysis.average_speed * 3.6,
            model.spec.target_average_speed * 3.6,
            "km/h",
        ),
        ("peak positive g", peak_up, 5.9, "g"),
        ("peak airtime g", -peak_down, 2.0, "g"),
    ] {
        let mark = if got >= target { "beaten" } else { "MISSED" };
        println!("{label:<22} {got:>10.1} {target:>10.1} {unit:<5} {mark}");
    }
}
