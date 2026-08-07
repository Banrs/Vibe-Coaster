# Vibe-Coaster — start here

Read `docs/ROADMAP.md` first, then `docs/MODEL.md`. Daniel directs vision and architecture; pitch at
that level, explain the engineering reasoning, and ask before deciding anything design-shaped.

```
cargo run --release -p vc-ride --bin generate && open out/ride.html
cargo test --workspace --release          # 92 tests
cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings
```

## Where it stands

Rideable. The generator solves a closed circuit and writes a POV viewer. Roadmap steps 1–4 and 8 are
done, 5 and 6 partial, 7 stands in as HTML rather than Godot.

Latest run: 6,861 m, 386 km/h top, 205 km/h average, 247 m airtime hill, 206 m cliff dive, 7.3 g
pull-out. Every record target beaten. Station closure 18.7 m with 11.4° of heading error.

## The two ideas everything rests on

**Force first.** An element is three curves — felt vertical g, felt lateral g, bank — and geometry is
solved from them, never drawn. Nothing in the crate branches on an element's name. Adding an element
type means adding data.

**Sizes cannot be authored by eye, because of `v²`.** The pitch an element sweeps is roughly
`(n̄−1)·g₀·L/v²`, so a thousand metres at one g of departure turns 69° at 90 m/s and 351° at 40 m/s —
the same element is a hill where the train is fast and a spiral where it is slow. So each element
carries two demands, matched to the two free parameters that move them independently: **trim sets the
pitch it hands on, length sets its size.** A seeder solves both by damped Newton on exact dual-number
derivatives, then solve → re-seed → solve.

The same relation is why size, speed and intensity are not independent. Pick any two, the third
follows. Scaling an element up at fixed speed grows every radius and leaves it *weaker* than the
record it beats — so record margins apply to geometry only; intensity is authored and floored, speed
is an outcome.

## Known problems, worst first

1. **The solve is basin-sensitive.** A brake-run tweak took closure from 18.7 m to 439 m and was
   reverted rather than tuned around. Residual weights behave like hyperparameters. Multiple shooting
   is the recommended structural fix. Table of attempts in `MODEL.md`.
2. **Three limits still slightly over:** jerk 19.7 vs 15 g/s, peak +g 7.29 vs 7.0 over 0.2 s,
   clearance 3.91 vs 4.0 m. Two candidate causes for the jerk, not yet isolated: the brake run
   reaching the speed floor, and the point below.
3. **Quintic is used for every transition, and it costs peak jerk.** `f'(x) = 30x²(1−x)²` peaks at
   **1.875×** its own average, where a clothoid — curvature linear in arc length, which is what real
   practice uses — has constant jerk and so peaks at 1.0×. Same transition, ~87% more peak jerk.
   Quintic earns its place at element *seams*, where a linear ramp would step the jerk; inside long
   transitions it does not. Expected gain from switching: 19.7 → ~10.5 g/s, inside the limit.
4. **Doc comments are heavier than Daniel wants.** He has asked for lean, minimal code three times
   and a trimming pass on the prose is still outstanding.

## Next session, in order

1. Clothoid ramps inside long transitions, quintic kept at the seams (problem 3). Re-solve and
   expect a basin jump — check closure did not regress from 18.7 m before keeping it.
2. Multiple shooting for the solve (problem 1). The structural fix, recommended since the first
   checkpoint and still not attempted.
3. Ask Daniel the rulings in `MODEL.md` and `PACING.md` §12 before building the pacing score.

Not modelled, and an engineer would ask: structural load cases (none), elastic couplers and snatch
loads, and the rail-offset cusp check `1 + h·κ ≤ 0` — that last one measures 0.006 at the pull-out's
162 m radius, so its absence is currently hiding nothing. Peak propulsion power is ~44 MW at the
thrust knee, burst-only, implying stored energy rather than grid draw; and 520 kN on a 6,200 kg train
is 8.5 g, *above* the 7 g longitudinal envelope. The envelope binds first, which is the right way
round, but by accident rather than by a check.

## Awaiting Daniel's ruling

- `MODEL.md` — four decisions, including the +7/−2.5 g envelope and what the solve should optimise.
- `PACING.md` §12 — six open questions for roadmap step 9. The sharp one: step 9 says "analysis
  surfaced", but a pacing score the *solver optimises against* is a step 6 concern, and that fork is
  unchosen. `PACING.md` is research input; one confidently-worded claim in it was already withdrawn
  on review, so check its derivations rather than coding them.

## House rules that bit

Every force channel must meet its neighbours at 1 g — a step in force is unbounded jerk. No
adaptivity anywhere; the solve differentiates through the evaluator. Positive bank turns **right**
(this was documented backwards once and cost a 2,819° spiral). Curvature is force over speed squared,
so a stalled train explodes the geometry.
