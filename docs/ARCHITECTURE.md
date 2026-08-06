# Architecture

> **Directional, not a spec.** Shape and reasoning only.

## Stack

**Rust core (headless) → C ABI → Godot 4 client.**

The core is a pure library that cannot see the renderer: the solver and physics need to be fast,
deterministic, and testable against real ride data in CI. Godot handles rendering and the graph-heavy
tooling UI. The C ABI is insurance — it means the renderer is replaceable without touching the hard
parts.

Crates are added as there is something to put in them, not up front: `vc-math` exists, and
`vc-model`, `vc-eval`, `vc-solve`, `vc-ffi` follow their roadmap steps. An empty crate enforces no
dependency direction, it just makes the tree look finished.

RTX is a rendering concern only. NVIDIA's path-traced Godot fork
([`NVIDIA-RTX/godot`](https://github.com/NVIDIA-RTX/godot), MIT) is the likely path — currently
4.7-dev and experimental, may become an addon. If it stalls, the ABI lets us move to Unreal.

## The generator is one system

Not a pipeline of passes. Three inputs, one evaluator, one solve.

**Model** — everything a ride is, as data:

- **Spec** — the element sequence. The human pins some parameters; the rest are *free*.
- **Site** — terrain. A first-class input, always.
- **Vehicle** — running gear, restraint, propulsion, mass, drag, as a parameter set.

**Evaluator** — given fully determined parameters, forward-integrate: force profile → heartline →
track geometry → multibody train → measured forces, energy, clearance. A pure function. It makes no
decisions and adjusts nothing; it only reports what a parameter set produces.

**Solve** — one global constrained solve over the free parameters, satisfying all of these
*simultaneously*:

- station closure — position, direction, roll
- arrival energy at the brake run
- terrain clearance and ground-following
- force envelope (EN 13814 / ASTM F2291), jerk, roll rate
- curvature continuity at element seams

This is the crux of the design. Forward integration alone can't close a circuit — it lands where it
lands. The usual fix is a chain of correction passes, and that's exactly what turns a generator into
a pile of modifiers. Putting all the adjustment in *one* solve is what makes closure, terrain and
energy come out together rather than being chased one at a time.

## Four rules that keep it lean

1. **No modifiers.** If a behaviour would be a post-pass, it's a constraint instead.
2. **No stubs on their own code path.** Flat ground is terrain at constant height, running the real
   terrain code.
3. **No special-cased tech.** Chain lift, LSM and maglev are parameter sets over one propulsion and
   running-gear model — wheels carry a thermal limit, maglev doesn't. Records are what aggressive
   parameters produce, not a feature.
4. **No archetype branching.** Track profile, heartline offset and car geometry are data.

## Why records don't need special treatment

Two kinds of limit, usually conflated:

- **Soft — rider physiology.** G envelopes, jerk, roll rate. These don't scale with size; a 300 m
  coaster gets the same handful of G as a 100 m one. They stay enforced, always.
- **Hard — engineering.** Height, speed, length, bounded by structure, materials, running gear and
  propulsion. These move with technology, and they're what the vehicle parameters express: maglev
  removes the wheel-heat speed cap, active restraint uses the full comfort envelope instead of a
  margin under it, terrain lets you build *down* a cliff instead of up from a plain.

Near-future tech buys size and speed. It never buys permission to exceed the G envelope. So analysis
reports comfort as pass/fail but buildability as a *cost* — a record-breaker should come back
comfortable and expensive, not rejected.

## Known risk

A global constrained solve is harder than staged fixups, and it fails worse: instead of a slightly
wrong ride you get non-convergence that's awkward to diagnose. This is the price of the leanness, and
it's accepted knowingly. Mitigations: seed the solve from a forward pass with nominal parameters,
scale constraints so none dominates numerically, and always report *which* constraint failed rather
than just failing.

## Other things worth carrying between sessions

- **FVD inverts normal CAD**: specify the forces, solve the curve. Speed depends on height, height on
  geometry, geometry on speed — circular, which is why the evaluator is forward integration in small
  arclength steps rather than a closed-form solve.
- **Heartline**, roughly rider chest height, is the axis the train rolls about. Rails are an offset
  from it — which is why other archetypes are a change of offset, not of math.
- **Multibody, not a point mass.** Cars already over a crest pull the ones behind. That's where
  back-row snap and per-row feel come from.
- **Determinism is required.** Same model → same ride. That's what makes benchmark regression tests
  possible, and it constrains the solver choice.

## Numerics

Decided while building the math layer; each one is a constraint on everything above it.

- **Everything is generic over the scalar type.** No function in the core takes `f64`; they take a
  `Scalar` trait that `f64` and a forward-mode dual number both implement. Substituting the dual is
  how the solve gets exact derivatives of the evaluator. This only works if the genericity goes all
  the way down, which is why it was paid for before there was anything to differentiate.
- **No adaptivity, anywhere.** Fixed quadrature order, fixed panel counts, fixed integration steps.
  Adaptive step control makes the output a *discontinuous* function of the parameters — nudge a
  launch speed and the integrator may take one more step, moving the answer for reasons unrelated to
  the physics. Gradients then carry that noise and the solve stalls on it. Step counts are chosen
  offline by a Richardson study and written down.
- **Rotation-minimising frames, not Frenet.** The Frenet normal is undefined wherever curvature is
  zero — launches, brake runs, the crest of a well-shaped hill — and flips through 180° at every
  inflection. The frame is instead carried along the track rotating only as much as the tangent
  does, with bank applied on top as an explicit roll. That also makes roll rate something the solver
  constrains directly rather than infers.
- **SI everywhere, by convention rather than by newtype.** Metres, seconds, kilograms, radians below
  the interface layer; conversions only at the boundaries. Dimensioned newtypes over a generic
  scalar double every operator and every bound for a guarantee one convention already buys. If unit
  confusion causes real bugs, that is when it changes.
- **Z-up, right-handed** (`+x` east, `+y` north, `+z` against gravity) — the convention terrain and
  structural data arrive in. Godot is Y-up; the binding converts at the boundary, in one place.

## Settled

Ride-first · FVD-first · one-shot global solve · terrain first-class · full multibody · Rust + Godot
+ C ABI · one archetype (Falcon's Flight-style, profiles data-driven) · records via parameters ·
pacing as the north star · technical visuals first · scalar-generic and deterministic core.

## Open

- Which solver. The choice is constrained by determinism and by needing to name the failing constraint.
- **What the solve optimises.** Closure and arrival energy are about seven scalar equalities; a
  spec's free parameters number thirty-plus; envelope and clearance are inequalities that carve out
  a region rather than pinning a point. The feasible set is therefore a manifold and something must
  choose a point on it. Candidates: stay closest to the ride as described (regularise toward the
  seed), maximise pacing, minimise buildability cost. If it is pacing, the pacing score stops being
  a step-9 readout and becomes load-bearing at step 6.
- **Single vs multiple shooting.** Integrating the whole ride and asking the solver to hit the
  station makes the closure residual depend on the first element's parameters through the entire
  integration; the Jacobian ends up badly conditioned in its columns, which scaling the constraints
  does not fix. Multiple shooting — cut at the element seams that already exist, make each seam
  state an unknown, add defect constraints — is still one simultaneous solve, so it costs nothing
  against rule 1. It requires the evaluator to integrate a segment from an arbitrary given state
  rather than only from the station: free if designed in at step 4, invasive if retrofitted.
- Additional archetypes — B&M / Vekoma-style; what actually varies isn't settled.
- Head-lag and greyout — not chosen, but probably the biggest "feels real" lever. Revisit once rideable.
- Audio: real synthesis vs heavily-modulated samples.
- Goal-level generation — the spec must support being *emitted*; the search that does it is its own project.
- The pacing score definition — least-defined thing here, expect several passes.
