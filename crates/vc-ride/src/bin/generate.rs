//! Generates the preset ride and writes a viewer you can open in a browser.
//!
//! ```text
//! cargo run --release -p vc-ride --bin generate
//! ```
//!
//! Writes `out/ride.json` and `out/ride.html`. The HTML has the ride baked into
//! it, so it opens straight off the filesystem with nothing to serve.

use std::fs;

use vc_ride::analysis::analyse;
use vc_ride::eval::evaluate;
use vc_ride::{export, preset, solve};

fn main() -> std::io::Result<()> {
    let model = preset::falcon_class();
    let seed = model.spec.free_parameters();

    println!("{} free parameters", seed.len());
    println!("\n--- as specified ---");
    report(&model, &evaluate(&model, &seed));

    let (report_out, ride) = solve::solve(&model, 90);
    println!("\n--- solve ---\n{}", report_out.summary());
    println!("\n--- as solved ---");
    report(&model, &ride);

    let analysis = analyse(&model, &ride);
    let failures = analysis.failures();
    if failures.is_empty() {
        println!("\nevery comfort and clearance limit met");
    } else {
        println!("\nlimits broken:");
        for check in &failures {
            println!("  {:<48} over by {:.3}", check.name, check.over);
        }
    }
    println!(
        "\nbuildability: {:.0} m of track, {:.0} support metre-metres, \
         closest approach to the ground {:.1} m",
        analysis.track_length, analysis.support_metres, analysis.min_clearance
    );

    let note = if report_out.converged {
        "solved".to_string()
    } else {
        format!("UNCONVERGED - {}", report_out.worst[0].0)
    };
    let json = export::to_json(&model, &ride, &analysis, &note);

    fs::create_dir_all("out")?;
    fs::write("out/ride.json", &json)?;
    let page = include_str!("../../viewer.html").replace("\"__RIDE__\"", &json);
    fs::write("out/ride.html", page)?;
    println!("\nwrote out/ride.json and out/ride.html");
    Ok(())
}

fn report(model: &vc_ride::RideModel, ride: &vc_ride::Ride<f64>) {
    println!(
        "{:<14} {:>7} {:>7} {:>7} {:>7} {:>8} {:>8}",
        "element", "len", "enter", "exit", "apex", "min z", "max z"
    );
    let mut at = 0usize;
    for (i, result) in ride.elements.iter().enumerate() {
        let end = (at + vc_ride::eval::STEPS_PER_ELEMENT).min(ride.samples.len() - 1);
        let span = &ride.samples[at..=end];
        let lo = span.iter().fold(f64::MAX, |m, s| m.min(s.position.z));
        let hi = span.iter().fold(f64::MIN, |m, s| m.max(s.position.z));
        println!(
            "{:<14} {:>7.0} {:>7.1} {:>7.1} {:>7.1} {:>8.1} {:>8.1}",
            result.name, result.length, result.entry_speed, result.exit_speed, result.apex, lo, hi
        );
        at = end;
        let _ = i;
    }
    let top = ride.samples.iter().fold(0.0_f64, |m, s| m.max(s.speed));
    let station = model.spec.station.position;
    let end = ride.end();
    println!(
        "total {:.0} m, {:.0} s, top speed {:.1} m/s ({:.0} km/h)",
        ride.length,
        ride.duration,
        top,
        top * 3.6
    );
    println!(
        "closure gap {:.1} m, heading error {:.1} deg",
        (end.position - station).norm(),
        end.frame
            .tangent
            .dot(model.spec.station.heading / model.spec.station.heading.norm())
            .clamp(-1.0, 1.0)
            .acos()
            .to_degrees()
    );
}
