//! GDExtension binding: the generator, callable from Godot.
//!
//! One class, one method. The binding hands Godot value types only — packed
//! arrays and a dictionary — so the core never sees the renderer and every
//! scene decision stays in GDScript. The ride is produced by the same
//! [`solve::solve_two_rounds`] the CLI uses, so what Godot renders is
//! bit-identical to what `out/ride.html` plays.

use std::thread::JoinHandle;

use godot::builtin::VarDictionary;
use godot::prelude::*;
use vc_math::Vec3;
use vc_ride::eval::Ride;
use vc_ride::solve::Report;
use vc_ride::{RideModel, preset, solve};

/// Roughly how many heartline samples to hand over. The integration runs far
/// finer than a camera path needs.
const TARGET_SAMPLES: usize = 2000;

/// Terrain vertices per side, sampled through the model's own bicubic
/// interpolation so the mesh matches what the clearance constraint saw.
const TERRAIN_GRID: usize = 96;

struct VcGodotExtension;

/// The `unsafe impl` gdext requires as its entry point — the only unsafe in
/// the crate, scoped here because the workspace otherwise denies it.
mod entry {
    #![allow(unsafe_code)]

    use godot::prelude::*;

    #[gdextension]
    unsafe impl ExtensionLibrary for super::VcGodotExtension {}
}

/// Project space is Z-up right-handed; Godot is Y-up right-handed. This map
/// has determinant +1, so cross products survive it and GDScript may rebuild
/// `right = tangent.cross(up)`.
fn to_godot(v: Vec3<f64>) -> Vector3 {
    Vector3::new(v.x as f32, v.z as f32, -(v.y as f32))
}

/// Generates the preset ride, in-engine.
#[derive(GodotClass)]
#[class(init, base = RefCounted)]
struct RideGenerator {
    /// The solve in flight, if [`Self::start`] has been called. Pure Rust on a
    /// plain thread — it must never touch the engine, which only the main
    /// thread may do.
    worker: Option<JoinHandle<(RideModel, Report, Ride<f64>)>>,
}

#[godot_api]
impl RideGenerator {
    /// Starts the solve on a background thread; the window stays honest while
    /// it runs. Fetch the result with [`Self::poll`].
    #[func]
    fn start(&mut self) {
        self.worker = Some(std::thread::spawn(|| {
            let mut model = preset::falcon_class();
            let (outcome, ride) = solve::solve_two_rounds(&mut model, 60);
            (model, outcome, ride)
        }));
    }

    /// Empty until the started solve finishes; then the ride, once.
    #[func]
    fn poll(&mut self) -> VarDictionary {
        if self.worker.as_ref().is_none_or(|w| !w.is_finished()) {
            return VarDictionary::new();
        }
        let worker = self.worker.take().expect("checked above");
        let (model, outcome, ride) = worker.join().expect("the solve does not panic");
        pack(&model, &outcome, &ride)
    }

    /// Runs the full pipeline synchronously — preset, seed, solve, re-seed,
    /// solve — and returns the ride. The headless smoke test's entry point;
    /// interactive callers use [`Self::start`] and [`Self::poll`].
    #[func]
    fn generate(&self) -> VarDictionary {
        let mut model = preset::falcon_class();
        let (outcome, ride) = solve::solve_two_rounds(&mut model, 60);
        pack(&model, &outcome, &ride)
    }
}

/// The ride as packed arrays in Godot's coordinate space.
///
/// Keys: `positions`, `tangents`, `ups` (PackedVector3Array), `times`,
/// `speeds` (PackedFloat32Array), `duration` (float, s), `note` and `stats`
/// (String), `terrain_vertices` (PackedVector3Array, row-major) with
/// `terrain_nx`, `terrain_ny` (int).
fn pack(model: &RideModel, outcome: &Report, ride: &Ride<f64>) -> VarDictionary {
    let stride = (ride.samples.len() / TARGET_SAMPLES).max(1);
    let mut picked: Vec<usize> = (0..ride.samples.len()).step_by(stride).collect();
    if picked.last() != Some(&(ride.samples.len() - 1)) {
        picked.push(ride.samples.len() - 1);
    }

    let positions: PackedVector3Array = picked
        .iter()
        .map(|&i| to_godot(ride.samples[i].position))
        .collect();
    let tangents: PackedVector3Array = picked
        .iter()
        .map(|&i| to_godot(ride.samples[i].frame.tangent))
        .collect();
    let ups: PackedVector3Array = picked
        .iter()
        .map(|&i| to_godot(ride.samples[i].frame.up))
        .collect();
    let times: PackedFloat32Array = picked
        .iter()
        .map(|&i| ride.samples[i].time as f32)
        .collect();
    let speeds: PackedFloat32Array = picked
        .iter()
        .map(|&i| ride.samples[i].speed as f32)
        .collect();

    let terrain = &model.site.terrain;
    let rows = terrain.heights.len() / terrain.nx;
    let width = (terrain.nx - 1) as f64 * terrain.spacing;
    let depth = (rows - 1) as f64 * terrain.spacing;
    let mut terrain_vertices = PackedVector3Array::new();
    for j in 0..TERRAIN_GRID {
        for i in 0..TERRAIN_GRID {
            let x = terrain.origin.0 + width * i as f64 / (TERRAIN_GRID - 1) as f64;
            let y = terrain.origin.1 + depth * j as f64 / (TERRAIN_GRID - 1) as f64;
            let z = terrain.height(x, y);
            terrain_vertices.push(to_godot(Vec3::new(x, y, z)));
        }
    }

    let dists: PackedFloat32Array = picked.iter().map(|&i| ride.samples[i].s as f32).collect();
    let gn: PackedFloat32Array = picked
        .iter()
        .map(|&i| ride.samples[i].normal_g as f32)
        .collect();
    let gl: PackedFloat32Array = picked
        .iter()
        .map(|&i| ride.samples[i].lateral_g as f32)
        .collect();
    let gx: PackedFloat32Array = picked
        .iter()
        .map(|&i| ride.samples[i].longitudinal_g as f32)
        .collect();
    let element_index: PackedInt32Array = picked
        .iter()
        .map(|&i| ride.samples[i].element as i32)
        .collect();
    let element_names: PackedStringArray = ride
        .elements
        .iter()
        .map(|e| GString::from(e.name))
        .collect();
    // Per-element vertical extent, already in Godot's y.
    let mut element_top = vec![f32::MIN; ride.elements.len()];
    let mut element_bottom = vec![f32::MAX; ride.elements.len()];
    for s in &ride.samples {
        let z = s.position.z as f32;
        element_top[s.element] = element_top[s.element].max(z);
        element_bottom[s.element] = element_bottom[s.element].min(z);
    }

    let top = ride.samples.iter().fold(0.0_f64, |m, s| m.max(s.speed));
    let gap = (ride.end().position - model.spec.station.position).norm();
    let note = if outcome.converged {
        "solved".to_string()
    } else {
        format!("UNCONVERGED - {}", outcome.worst[0].0)
    };
    let stats = format!(
        "{:.0} m, {:.0} s, top {:.0} km/h, closure {:.1} m",
        ride.length,
        ride.duration,
        top * 3.6,
        gap
    );

    let mut out = VarDictionary::new();
    out.set("positions", &positions);
    out.set("tangents", &tangents);
    out.set("ups", &ups);
    out.set("times", &times);
    out.set("speeds", &speeds);
    out.set("duration", ride.duration);
    out.set("note", note);
    out.set("stats", stats);
    out.set("dists", &dists);
    out.set("length", ride.length);
    out.set("gn", &gn);
    out.set("gl", &gl);
    out.set("gx", &gx);
    out.set("element_index", &element_index);
    out.set("element_names", &element_names);
    out.set(
        "element_top",
        &PackedFloat32Array::from(element_top.as_slice()),
    );
    out.set(
        "element_bottom",
        &PackedFloat32Array::from(element_bottom.as_slice()),
    );
    out.set("terrain_vertices", &terrain_vertices);
    out.set("terrain_nx", TERRAIN_GRID as i64);
    out.set("terrain_ny", TERRAIN_GRID as i64);
    out
}
