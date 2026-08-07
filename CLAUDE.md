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

Its cost is peak jerk. Force sits two derivatives below position (`p'' = κ ∝ n`), so force continuity
maps directly onto position continuity. Peak slope for the smoothstep family is `((2n+1)!/(n!)²)/4ⁿ`:

| | force | position | peak / average jerk |
|---|---|---|---|
| linear — the clothoid | C⁰ | **C²** | 1.00 |
| cubic | C¹ | C³ | 1.50 |
| **quintic, what we use** | **C²** | **C⁴** | **1.875** |
| septic | C³ | C⁵ | 2.1875 |

Read the position column as the derivative it makes continuous: **C² is continuous acceleration, C³
continuous jerk, C⁴ continuous snap.** So C⁴ is not merely "smoother than needed" — it is the order
at which snap stops stepping, and Daniel's read is that this is what makes a transition feel organic
rather than caught. No standard limits snap, but Rohde *measures* it (+22 / −32 g/s² on Valkyria),
which suggests practitioners track it even unlegislated. Whether it is independently perceptible from
jerk is not something this project has a source for.

Do not conflate it with vibration or shimmy. A snap discontinuity is a single event at one join;
shimmy is oscillatory and comes from running gear and track joints at a few Hz upwards. This model
has no structural dynamics and cannot produce the latter at all.

A clothoid gives up both: curvature is continuous but its derivative steps, so position is C² and
jerk steps at the join. That step is the price real designers pay for minimum peak jerk.

**Three options, not two.** The trade is real in both directions and unchosen:

- **Keep C⁴, lengthen the transitions.** Peak jerk scales inversely with transition length, so about
  1.31× longer clears 19.7 → 15 with snap continuity intact. Costs track length and crispness. Most
  consistent with a ride whose premise is active suspension.
- **Move to clothoid-with-easement** — a linear force ramp with short high-order fillets. Analytic
  expectation 19.7 → ~10.5 g/s. Matches built practice, gives up continuous snap.
- **Keep as is**, accept 19.7 g/s, and say so in the analysis rather than pretending otherwise.

**Isolate the cause before choosing.** Two candidates were flagged and never separated: the smoothing
law, and the brake run reaching the speed floor. If it is the stall, none of the above touches it.
Whatever is chosen moves every radius, and this solve jumps basins when provoked — verify closure has
not regressed from 18.7 m before keeping anything.

## Keep researching — use agents

Daniel wants this grounded in real sources, not reasoned from first principles alone, and expects
subagents to be used for it. Run retrieval *before* building on any thin section. Last session's
search budget hit 200/200, so a fresh session has a fresh one.

Worth re-attempting, highest value first:

1. **ASTM F2291 per-axis acceleration/duration tables.** The single biggest gap. `PACING.md` §1 gates
   on a lone secondary-source "6 G / <0.8 s" figure; the real per-axis envelope was never obtained.
   `preset.rs` uses Rohde's reproduction of F2291-23b instead, which is better sourced but still not
   the standard. EN 13814's numeric tables likewise. Both paywalled — try library access, the ISO/TS
   17929 route, or Rohde's later editions.
2. **Coaster design principles** — clothoid and easement practice, heartlining, transition lengths.
   Stengel's own g-vs-time diagrams were never found. This bears directly on the smoothing question
   above, which is currently decided by analysis rather than by evidence.
3. **Specific coasters, per-element.** No manufacturer publishes radii and no per-element g
   breakdowns were located for Magnum, Steel Vengeance, Voyage, Maverick, Iron Gwazi, Fury 325,
   Tormenta or Falcon's Flight. Falcon's Flight conditions in `preset.rs` are *derived* with the
   simulator from published geometry, not sourced — worth trying to verify against anything real.

`PACING.md` §11 is the full gap list with the retrieval blockers hit (403s from coasterforce,
coasterpedia, researchgate, reddit). Use Haiku for plain fetch work; reserve stronger models for
synthesis. Ask for figures *with the conditions they were set under* — a record height means nothing
without the speed and g it was set at, which is the mistake that shaped this whole model.

## Questions to put to Daniel, before writing code

1. Where should FVD stop and geometry-first begin? See the steer above; turns are the live case.
2. Smoothing — isolate the jerk cause first, then pick from the three options above. Daniel's steer
   so far is that continuous snap (C⁴) is worth keeping for the organic feel, which points at
   lengthening transitions rather than dropping to the clothoid. Confirm before acting.
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
