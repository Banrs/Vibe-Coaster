//! The solved ride as JSON, for a viewer to play back.
//!
//! Written by hand rather than with a serialisation crate: the shape is fixed,
//! it is written in one place and read in one place, and the core stays free of
//! dependencies.
//!
//! Only the heartline trace is exported, plus where each row sits along the
//! train. That is enough for the viewer to seat a rider anywhere: a row's
//! experience *is* the trace, sampled a fixed distance back. Exporting a
//! separate trace per row would be the same numbers fourteen times.

use std::fmt::Write as _;

use crate::analysis::Analysis;
use crate::eval::{Ride, Sample};
use crate::model::RideModel;

/// Roughly how many samples to export. The integration runs far finer than
/// anything needs to be drawn at.
const TARGET_SAMPLES: usize = 1400;

/// Terrain samples per side in the exported grid.
const TERRAIN_GRID: usize = 48;

/// Serialises a solved ride.
pub fn to_json(
    model: &RideModel,
    ride: &Ride<f64>,
    analysis: &Analysis<f64>,
    note: &str,
) -> String {
    let stride = (ride.samples.len() / TARGET_SAMPLES).max(1);
    let mut out = String::with_capacity(1 << 18);

    out.push_str("{\n\"meta\":{");
    let _ = write!(
        out,
        "\"length\":{:.1},\"duration\":{:.2},\"topSpeed\":{:.2},\"highest\":{:.1},\
         \"supportMetres\":{:.0},\"minClearance\":{:.2},\"note\":\"{}\"",
        ride.length,
        ride.duration,
        analysis.top_speed,
        analysis.highest,
        analysis.support_metres,
        analysis.min_clearance,
        escape(note)
    );
    out.push_str("},\n");

    out.push_str("\"rowOffsets\":[");
    join(&mut out, model.vehicle.row_offsets().iter(), |o, v| {
        let _ = write!(o, "{v:.2}");
    });
    out.push_str("],\n");

    out.push_str("\"elements\":[");
    let mut start = 0.0;
    join(
        &mut out,
        model.spec.elements.iter().zip(&ride.elements),
        |o, (element, result)| {
            let _ = write!(
                o,
                "{{\"name\":\"{}\",\"start\":{:.1},\"length\":{:.1},\"apex\":{:.1},\"exitSpeed\":{:.2}}}",
                escape(element.name),
                start,
                result.length,
                result.apex,
                result.exit_speed
            );
            start += result.length;
        },
    );
    out.push_str("],\n");

    out.push_str("\"checks\":[");
    join(&mut out, analysis.checks.iter(), |o, c| {
        let _ = write!(
            o,
            "{{\"name\":\"{}\",\"over\":{:.4}}}",
            escape(&c.name),
            c.over
        );
    });
    out.push_str("],\n");

    // Flat arrays rather than an array of objects: a third of the bytes, and
    // the viewer wants columns anyway.
    let taken: Vec<&Sample<f64>> = ride
        .samples
        .iter()
        .step_by(stride)
        .chain(std::iter::once(ride.end()))
        .collect();

    let column = |out: &mut String, name: &str, decimals: usize, f: fn(&Sample<f64>) -> f64| {
        let _ = write!(out, "\"{name}\":[");
        join(out, taken.iter().copied(), |o, s| {
            let _ = write!(o, "{:.*}", decimals, f(s));
        });
        out.push_str("],\n");
    };

    column(&mut out, "s", 2, |s| s.s);
    column(&mut out, "t", 3, |s| s.time);
    column(&mut out, "x", 2, |s| s.position.x);
    column(&mut out, "y", 2, |s| s.position.y);
    column(&mut out, "z", 2, |s| s.position.z);
    column(&mut out, "tx", 4, |s| s.frame.tangent.x);
    column(&mut out, "ty", 4, |s| s.frame.tangent.y);
    column(&mut out, "tz", 4, |s| s.frame.tangent.z);
    column(&mut out, "ux", 4, |s| s.frame.up.x);
    column(&mut out, "uy", 4, |s| s.frame.up.y);
    column(&mut out, "uz", 4, |s| s.frame.up.z);
    column(&mut out, "v", 2, |s| s.speed);
    column(&mut out, "gn", 3, |s| s.normal_g);
    column(&mut out, "gl", 3, |s| s.lateral_g);
    column(&mut out, "gx", 3, |s| s.longitudinal_g);
    column(&mut out, "el", 0, |s| s.element as f64);

    // A coarse ground mesh, so the cliff the ride is built into is visible.
    let terrain = &model.site.terrain;
    let ny = terrain.heights.len() / terrain.nx;
    let step_x = (terrain.nx / TERRAIN_GRID).max(1);
    let step_y = (ny / TERRAIN_GRID).max(1);
    let _ = write!(
        out,
        "\"terrain\":{{\"originX\":{:.1},\"originY\":{:.1},\"spacing\":{:.1},\"nx\":{},\"ny\":{},\"h\":[",
        terrain.origin.0,
        terrain.origin.1,
        terrain.spacing * step_x as f64,
        terrain.nx.div_ceil(step_x),
        ny.div_ceil(step_y)
    );
    join(
        &mut out,
        (0..ny)
            .step_by(step_y)
            .flat_map(|j| (0..terrain.nx).step_by(step_x).map(move |i| (i, j))),
        |o, (i, j)| {
            let _ = write!(o, "{:.1}", terrain.heights[j * terrain.nx + i]);
        },
    );
    out.push_str("]}\n}");
    out
}

/// Writes comma-separated items without a trailing comma.
fn join<T>(
    out: &mut String,
    items: impl Iterator<Item = T>,
    mut write: impl FnMut(&mut String, T),
) {
    for (i, item) in items.enumerate() {
        if i > 0 {
            out.push(',');
        }
        write(out, item);
    }
}

/// Escapes the handful of characters that can appear in a name here.
fn escape(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', " ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analysis::analyse;
    use crate::eval::evaluate;
    use crate::preset;

    #[test]
    fn the_export_is_plausible_json_and_has_matching_columns() {
        let model = preset::falcon_class();
        let ride = evaluate(&model, &model.spec.free_parameters());
        let analysis = analyse(&model, &ride);
        let json = to_json(&model, &ride, &analysis, "test");

        assert!(json.starts_with('{') && json.ends_with('}'));
        assert_eq!(
            json.matches('[').count(),
            json.matches(']').count(),
            "unbalanced brackets"
        );
        assert!(!json.contains(",]"), "trailing comma in an array");
        assert!(
            !json.contains("NaN") && !json.contains("inf"),
            "non-finite number exported"
        );

        // Every column must be the same length, or the viewer reads off the end.
        let count = |name: &str| {
            let start = json.find(&format!("\"{name}\":[")).unwrap() + name.len() + 4;
            let end = start + json[start..].find(']').unwrap();
            json[start..end].split(',').count()
        };
        let n = count("s");
        for name in ["t", "x", "y", "z", "tx", "uz", "v", "gn", "gl", "gx", "el"] {
            assert_eq!(count(name), n, "column {name} is a different length");
        }
        assert!(n > 100, "only {n} samples exported");
    }

    #[test]
    fn names_with_quotes_do_not_break_the_json() {
        assert_eq!(escape(r#"a "b" \c"#), r#"a \"b\" \\c"#);
    }
}
