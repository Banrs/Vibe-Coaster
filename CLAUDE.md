# Vibe-Coaster — start here

**Read before you build, and ask before you decide.** Daniel directs vision and architecture; Everything in this file and in `docs/` is a *guide*, not a constraint — including the
parts that sound confident. Nothing here has been ratified by him.

The first thing a new session should do is read, form a view, and **come back with questions**. Do
not open with an implementation.

```
cargo run --release -p vc-ride --bin generate && open out/ride.html
cargo build -p vc-godot --release && godot --path godot   # the rideable Godot client
cargo test --workspace --release          # 100 tests
cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings
```

# Please check the global claude.md from .claude

## Where it stands

Godot client works (steps 7 basic): `vc-godot` (GDExtension, godot-rust) runs the generator
in-engine, `godot/` rides it — POV/chase/fly cameras, train box, terrain, ground, crossties,
speed-FOV, and a live debug overlay (g, speed, pitch, distance, heights, element). Same
`solve_two_rounds` as the CLI; CI cross-builds the extension on Linux and Windows.

**The layout is mid-rebuild and the solve is NOT currently converged.** 2026-08-07 late session
landed, per Daniel's rulings: minimax transition split (micro-flats gone, design jerk passes on the
old layout), a C³ septic closer bridging end→station exactly (engages under an 80 m gap), geometric
grade sections (pitch authored, force measured — a force profile cannot hold a grade; one looped
791° trying), gravity-aware speed demands on grades, a 320 m elevation-span check, and a new
19-element FF-shaped roster (lift, twisted 55 m drop, airtime cluster, zero-g roll, inclined cliff
launch+climb, rim overbank, holding brake, 197.5 m dive, 6.9 g pullout, 225 m camelback, helix,
finale). The old 14-element layout closed at 18.7 m.

The 2026-08-08 session did the seeder work: geometric elements measure rise inside their own
endpoints (consecutive grades no longer share a pin's measurement), cliff-launch is pinned
Rise(60), and a pinless roll's length is seeded from the roll-rate limit. The roster now stands
at **1,085.7 m and 22.3° heading error, cost 4.6e6** — from ~1.3 km and 149° — with the
roll-rate violation cleared and jerk/clearance violations collapsed (379→16, 258→2.6). The
solve buys part of this by near-stalling the train through the zero-g-roll (8→2 m/s, 607° of
heading); that stall is the ugliest thing in the current answer. Dual-side anchoring was built
and measured (`DUAL_ANCHOR` in `solve.rs`, `eval::integrate_reverse`): the joint stayed 434 m
open and the forward ride lost the basin, so it is wired, test-exercised and off — same status
as multiple shooting. Two smaller findings: wave-turn's Turn(0.0) pin cannot size its length
but is load-bearing as a residual (dropping it cost 974→2,890 m), and the seeder's derivative
guard never trips on the roll/overbank trims — their stalls are step-budget and bounds.

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

1. **The solve is basin-sensitive, now measured thoroughly.** Residual weights behave like
   hyperparameters; even adding a residual that is *zero at the answer* reshapes the path enough to
   lose the 18.7 m basin. Multiple shooting was attempted 2026-08-07: it is wired end to end
   (`eval::evaluate_split`, seam seeding, defect residuals, all test-exercised) but **disabled in
   `solve()`** because defects never close from current seeds. Attempts table and next hypotheses
   in `MODEL.md`.
2. **Two limits slightly over, one guidance figure exceeded:** peak +g 7.29 vs 7.0 over 0.2 s,
   clearance 3.91 vs 4.0 m, and the authored profile's instantaneous jerk 19.7 g/s against Rohde's
   15 g/s design guidance — while the standard's own proving measurement passes at 10.5 (below).
3. **Doc comments and Markdown are heavier than Daniel wants.** He has asked for lean prose four
   times. The code is lean; the commentary is not.

## The smoothing question, resolved 2026-08-07

Quintic smoothstep interpolates every force channel: C² in force, C⁴ in position — continuous
snap — and it steps nothing at seams. Daniel's steer that this is the organic feel stands, and it
stays. Two findings closed the question:

- **The cause was isolated, and it was not the brake run.** The 19.7 g/s peak sits on the
  ejector-hop (second: pullout): transitions are authored as fractions of element length, so jerk
  ≈ 1.875·Δg·v/(fraction·length), and the solve shortened the element to buy closure. MODEL.md
  has the measurement.
- **The 15 g/s limit was being applied to the wrong quantity.** F2291 measures onset rate as an
  event-to-event mean slope on a 5 Hz-filtered signal, never a pointwise derivative — a clothoid's
  infinite instantaneous jerk *passes* (Rohde's own worked example). Analysis now carries both: the
  instantaneous **design** check the solve enforces (Rohde: 5–10 g/s design, this ride 19.7), and
  the standard's **proving** measurement as an advisory (this ride 10.5, passes 15). The advisory
  is provably dominated by the design check, and must never become a solver penalty — that alone
  cost the basin once.

The transition-shape improvement that *would* cut the authored peak to ~14 g/s at fixed length —
allocate each arc swing's key width in proportion to the g it crosses, the minimax split — is
verified but shelved: it moves every seeded trim and the solve loses the basin. See `MODEL.md`.
Open ruling for Daniel: accept 19.7 authored against design guidance (current state, honestly
reported), or raise the frontier design-jerk figure with the active-suspension rationale.

## Research status, after the 2026-08-07 retrieval pass

Daniel wants this grounded in real sources. Search **by record with its conditions, not by
coaster**, and use few agents — he corrected both mid-session.

Obtained (see `PACING.md` §1 and §13): the full F2291-23b per-axis envelope, twice-corroborated;
the standard's measurement conventions (event-slope onset, 5 Hz filter, slice durations, push-pull
rule, combination ellipses); sourced frontier headroom; a by-record table whose main finding is
that records carry no conditions; Intamin's own Falcon's Flight figures (camelback 165 m vs the
163 m in `preset.rs`, flagged not changed); and openFVD source evidence that practitioner tooling
mixes force-driven and radius-driven sections per element, with per-transition shape choice.

Still missing: Stengel's own diagrams (Rohde Fig. 9.3 substitutes), EN 13814 read directly
(closed by harmonisation), any per-element g or radius for real coasters (confirmed unpublished,
several routes), and any operating coaster's measured jerk.

## Questions to put to Daniel, before writing code

1. **FVD boundary.** The evidence now points at per-element choice: openFVD models turns as
   radius + angle with easements alongside force-driven sections (`PACING.md` §13). The smallest
   honest step here is an optional radius pin on turns. Awaiting his ruling.
2. **The design-jerk figure — ruled 2026-08-07: "aim for 15+".** The 15 g/s design constraint
   stays enforced and the authored figure should be brought down toward it; the shelved minimax
   transition split is the path once the solve can follow geometry changes. The 19.7 stays a
   reported exceedance until then.
3. **The frontier envelope — lateral raised to 4.0 g short-duration, ruled 2026-08-07.** A
   remaining sub-question: whether to split longitudinal asymmetrically (F2291's −Gx is far below
   its +Gx and restraint-dependent), which needs a model change to express.
4. `MODEL.md` — solve objective still provisional; `PACING.md` §12 — six open questions for
   step 9, unchanged.

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
