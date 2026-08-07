# Vibe-Coaster — start here

**Read before you build, and ask before you decide.** Daniel directs vision and architecture; he does
not read code. Everything in this file and in `docs/` is a *guide*, not a constraint — including the
parts that sound confident. Nothing here has been ratified by him.

The first thing a new session should do is read, form a view, and **come back with questions**. Do
not open with an implementation.

```
cargo run --release -p vc-ride --bin generate && open out/ride.html
cargo test --workspace --release          # 92 tests
cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings
```

## Where it stands

Rideable. Roadmap steps 1–4 and 8 done, 5 and 6 partial, 7 stands in as HTML rather than Godot.

Latest run: 6,861 m, 386 km/h top, 205 km/h average, 247 m airtime hill, 206 m cliff dive, 7.3 g
pull-out. Every record target beaten. Closure 18.7 m, 11.4° of heading error.

## The two ideas everything rests on

**Force first — as a method, not a religion.** An element is three curves (felt vertical g, felt
lateral g, bank) and geometry is integrated from `κ = (n·g₀·up + l·g₀·right + g − (g·t)t)/v²`. No
spline is fitted; nothing branches on an element's name.

Daniel's steer: this should follow how real coasters are actually dictated, not apply FVD to
everything on principle. Worth examining where geometry-first would be the honest description —
straights and brake runs are already effectively geometric (a flat 1 g channel *is* straight track),
and turns are the interesting case, since real practice specifies a radius and banks to coordinate
where we specify bank and g and let the radius fall out. Ours is better for comfort and worse for
"this turn must fit in this footprint". Not resolved. Ask.

**Sizes cannot be authored by eye, because of `v²`.** The pitch an element sweeps is roughly
`(n̄−1)·g₀·L/v²`, so a thousand metres at one g of departure turns 69° at 90 m/s and 351° at 40 m/s —
the same element is a hill where the train is fast and a spiral where it is slow. So each element
carries two demands matched to the two parameters that move them independently: **trim sets the pitch
it hands on, length sets its size.** A seeder solves both by damped Newton on exact dual-number
derivatives, then solve → re-seed → solve.

The same relation is why size, speed and intensity are not independent. Pick any two, the third
follows. Scaling an element up at fixed speed grows every radius and leaves it *weaker* than the
record it beats — so record margins apply to geometry only; intensity is authored and floored, speed
is an outcome.

## Known problems, worst first

1. **The solve is basin-sensitive.** A brake-run tweak took closure from 18.7 m to 439 m and was
   reverted rather than tuned around. Residual weights behave like hyperparameters. Multiple shooting
   is the standing recommendation, never attempted. Table of attempts in `MODEL.md`.
2. **Three limits still slightly over:** jerk 19.7 vs 15 g/s, peak +g 7.29 vs 7.0 over 0.2 s,
   clearance 3.91 vs 4.0 m. Two candidate causes for the jerk, not isolated: the brake run reaching
   the speed floor, and the smoothing law below.
3. **Doc comments and Markdown are heavier than Daniel wants.** He has asked for lean prose four
   times. The code is lean; the commentary is not.

## The smoothing question, unresolved

Quintic smoothstep interpolates every force channel. It is C² in force — hence C⁴ in position — and
it steps nothing at element seams, which is why it is there.

Its cost is peak jerk. For the smoothstep family, peak slope is `((2n+1)!/(n!)²)/4ⁿ`:

| | continuity in force | peak / average slope |
|---|---|---|
| linear — the clothoid case | C⁰ | 1.00 |
| cubic | C¹ | 1.50 |
| **quintic, what we use** | **C²** | **1.875** |
| septic | C³ | 2.1875 |

**Higher continuity is strictly worse for peak jerk** — smoother ends concentrate the derivative in
the middle. It buys lower *snap*, which no standard limits (Rohde reports snap as measured, never
capped). So the direction that helps is toward the clothoid, not away from it.

A clothoid is curvature linear in arc length, i.e. constant jerk, i.e. the minimum-peak easement for
a given length — and it is what real practice uses. In our terms that is a **linear** force ramp with
short high-order fillets at each end, which is exactly clothoid-with-easement.

Analytic expectation if switched: 19.7 → ~10.5 g/s, inside the limit. **Not measured, and not done.**
It moves every radius, and this solve jumps basins when provoked — verify closure has not regressed
from 18.7 m before keeping anything.

## Questions to put to Daniel, before writing code

1. Where should FVD stop and geometry-first begin? See the steer above; turns are the live case.
2. Clothoid-with-fillets in place of quintic inside long transitions — worth the basin risk to clear
   the jerk check, or leave the check failing and note it?
3. `MODEL.md` — four decisions, including the +7/−2.5 g envelope and what the solve should optimise.
4. `PACING.md` §12 — six open questions for step 9. The sharp one: step 9 says "analysis surfaced",
   but a score the *solver optimises against* is a step 6 concern, and that fork is unchosen.
   `PACING.md` is research input; one confident claim in it was already withdrawn on review.

## House rules that bit

Every force channel must meet its neighbours at 1 g — a step in force is unbounded jerk. No
adaptivity anywhere; the solve differentiates through the evaluator. Positive bank turns **right**
(documented backwards once, cost a 2,819° spiral). Curvature is force over speed squared, so a
stalled train explodes the geometry.

Not modelled, and an engineer would ask: structural load cases (none), elastic couplers and snatch
loads, and the rail-offset cusp check `1 + h·κ ≤ 0` — that measures 0.006 at the pull-out's 162 m
radius, so its absence hides nothing today. Peak propulsion is ~44 MW at the thrust knee, burst-only,
implying stored energy rather than grid draw; 520 kN on a 6,200 kg train is 8.5 g, *above* the 7 g
longitudinal envelope, so the envelope binds first — correct, but by accident rather than by a check.
