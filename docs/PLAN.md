# Vibe-Coaster rewrite — near-future seeded coaster generator

*(Approved plan, 2026-08-08. This is a guidance document capturing intent — not an execution
script, and NOTHING in it is fixed: every number and choice is provisional and expected to move
with better research. Implementation happens in a NEW session on a NEW PC, starting from a
clone of this repo — see Repo handoff, already performed.)*

## Intent

Delete and rewrite the current checkpoint. It is one hardcoded, vibe-authored route: emergent
wrong element shapes (asymmetric camelback, uncontrolled steepness), a hidden ±2.5 g trim solver,
~35% flat/straight track, banks forced to 0° at every seam, average speed bought with sustained
LSM boost, a hardcoded mesa with the track on stilts, no seed. **This is an engineering-sim
checkpoint: physics, generation, and validation are the product; visuals are a minimal,
deliberately generic inspection layer (placeholder train, simple pillars/track — real shapes
decided later, keep the base checkpoint unpolluted).**

What replaces it: a **seed-based one-shot generator** baking the user's vision of a
**near-future (~15 yr, ≈2041) hybrid of Falcon's Flight and Tormenta: Rampaging Run**, where
records and human limits are stretched per-domain by researched technology trajectories — not a
uniform multiplier, and not "slightly beyond record."

## Current direction (user Q&A, 2026-08-08 — all provisional, nothing fixed)

- **Keep only** the load-verification toolkit (100 Hz resample → 4-pole 5 Hz Butterworth →
  duration-dependent envelope usage/held-curve, seam + clearance checks). Everything else is
  rewritten. The old "never inverted" frame check dies — inversions are legal now.
- **Seed controls terrain, element dimensions, AND sequence** (shuffle/substitute where the
  story allows). Same seed → identical ride. Structure the code as generator-with-parameters
  (future: style, wanted elements, per-element targets, length/duration) but build no config
  surface now.
- **FVD for thrill elements, C4 seams**; authored geometry only for true infrastructure
  (launches, lifts, brakes, station). No hidden trims, no prescribed exit speeds. Checked
  against NoLimits 2 / Planet Coaster (researched): NL2's NURBS spline is an authoring/display
  layer with no curvature-continuity guarantee at nodes and separately-interpolated roll — its
  realism comes from pro workflows feeding it FVD-generated nodes, i.e. our approach without
  the middleman; Planet Coaster's piece system is the negative example. Verdict: keep
  FVD + C4, and adopt **clothoid (Stengel) shape priors** within elements (constant-g authoring
  yields them implicitly); sample ~1 m nodes if NL2 export is ever wanted.
- **Element families:** Falcon's Flight phases (primary guide) + Tormenta's **held
  beyond-vertical drop, giant Immelmann + vertical loop, cutback** (no mid-course
  near-stop/second-drop). Records chased: **speed / height / drop / length, launch
  acceleration, tallest inversion.** Not steepest drop; no duration records.
- **Numbers:** top speed **~340 km/h** (chosen via radius math: with the stretched envelope's
  brief ~6.5 g centripetal, a 340 km/h pullout needs R≈140 m vs today's ~123 m — no
  ballooning); structure **~250 m (provisional — re-sanity-check against terrain in Step 0)**;
  site class **Jebel Fihrayn ~300 m relief**; **total elevation change ~300 m** (Falcon's real
  proportion: structure = 163/195 = 84% of elevation change → 250 m structure + ~50 m
  cliff-assist matches it); length **6–7 km**; launch **~4 g, envelope-credited** (beats the
  defunct 3.3 g Do-Dodonpa record); trains **faired but open** (nose cones, faired chassis,
  per-row windscreens ⇒ ~20–30% drag cut vs today) — visually placeholder for now.
- **Pacing truth comes from real POV, not assumption.** The user rejected the "constant-speed
  powered climb" guess; the cliff-climb profile, slow-beat placement (all thrill coasters have
  slow beats — cf. Formula Rossa), and height-over-terrain behavior are read frame-by-frame off
  real onride POV in Step 0 (non-Fable agent). No sustained boost to game average speed; no
  numeric average-speed contract.
- **Envelope (~2041, derived from researched tech credits, duration-structured like ASTM
  F2291):** ≈ **+8.0/−3.0 Gz · ±4.7 Gy · +8.0/−6.0 Gx · ~25 g/s onset · ~120°/s roll** (user
  judgment caps −Gz at −3.0; deeper negative isn't credible for unscreened riders. Gx is
  asymmetric — eyes-back tolerance far exceeds eyes-front even well-restrained (Step-0
  research; F2291 itself is +6.0 vs −1.5/−2.0/−3.5 by restraint class).
  **Step-0 note: +8.0 Gz is credited to riders wearing anti-G suits (user decision 2026-08-09;
  aviation suits add ~1.0–1.5 g of relaxed tolerance) on top of recline/vests/MR seats — valid
  as a brief peak; sustained +Gz still follows the duration curve. See docs/RESEARCH.md §5 for
  the actual F2291 curves and per-axis credibility caveats**).
  Derivation per axis: ASTM brief baseline (≈+6/−2 Gz) + seat recline (+Gz), load-distributing
  vest restraints (−Gz, ±Gy, ±Gx), semi-active MR seats (onset/jerk — the axis that stretches
  most), interpolated between the researched mid-2030s and ~2050 syntheses. Lateral and roll
  are the least-grounded axes — refine in Step 0 against the actual F2291 duration tables.
- **Proportional envelope usage (validation principle):** element g-targets scale from their
  real-world counterpart's profile by the per-axis stretch ratio — whichever element is
  *genuinely* highest-g must reach the envelope, but which one that is gets determined, not
  assumed (a big dive pullout may be slower/more smoothed than expected; real rides often have
  several thrill elements with similar peaks). Ejector hills land proportionally strong
  (approaching −3 Gz class), floater crowns stay gentle, suspense elements stay light. Not
  everything designed to the max; not merely "within limits to pass."
- **Working rule for the implementation session: do not take this plan's reference numbers
  verbatim.** When unsure, research and confirm with the user via a question — skippable only
  when the answer is obvious.

## Research digest (all researched this session; sources in agent reports)

> **STEP 0 COMPLETE (2026-08-08): this digest has been re-verified and partially corrected —
> `docs/RESEARCH.md` supersedes it wherever they disagree.** Key overrides: the 158 m drop is
> the **camelback's** (structurally 165 m), not the cliff dive's — the 90° cliff drop is a
> separate ~160 m element;
> LSM1 is a constant-speed lift, not a launch; the cliff climb is a launch at the base then
> **gradual deceleration up** (~19 s); the hold (~3 s) comes **before** the cliff-edge
> traverse and there is **no pause at the dive lip**; there is **no late boost** on the return
> run; Tormenta's cutback wraps its own first drop (not the drop tower) and Tormenta **does**
> have a mid-course brake + second drop (our exclusion is a deliberate deviation, reaffirmed);
> "tallest inversion" claim for Tormenta is Immelmann-class only — Spitfire's 73 m still
> stands; canonical numbers = RCDB/Wikipedia set. Suspense/clifftop elements scale from
> reference geometry only, never toward records (user rule).

**Falcon's Flight** (Intamin, Qiddiya) — open Dec 31, 2025; real POV analyzed in Step 0 (CGI
allowed for 3rd-person geometry — essentially 1:1).
163 m record structure height / 195 m elevation change via the ~195 m Tuwaiq cliff ("200 m
step" was unverifiable); **camelback structurally 165 m carrying the recorded 158 m drop;
separate ~160 m 90° cliff drop**; 250 km/h via the last of 3 LSM sections (constant-speed
40 km/h lift + cliff launch + post-tunnel launch; >700 water-cooled modules), 4,250 m, 3:35,
0 inversions. Phases (POV-verified): station → LSM lift (constant ~40 km/h) → ~55 m twisted
drop → ~27 s terrain-hugging airtime hills + wave turn → cliff launch (launched at base then
decelerating up, ~19 s, 150–160 km/h) → crest crawl/hold ~3 s → clifftop turns + outward-banked
rim turn, accelerating monotonically (no pause at the lip) → 90° cliff drop into short tunnel →
LSM3 to 250 → camelback (trimmed in current operation) → ~36 s high-speed return (no late
boost) → brakes.

**Tormenta: Rampaging Run** (B&M Dive Coaster, "giga dive" is marketing; Six Flags Over
Texas) — open Jul 9, 2026. 94 m (309 ft), 87 m drop @ 95° with crest hold (official 3 s;
measured ~1.7 s dead stop after ~4 s pitch-over crawl), 140 km/h, inversions incl. 218 ft
Immelmann (tallest *Immelmann* only — Spitfire's 73 m inverted top hat remains the tallest
inversion) and 179 ft vertical loop (tallest loop), **cutback around its own first drop** (not
the park's drop tower). It DOES have a mid-course brake + second drop — our exclusion of both
is a deliberate deviation, reaffirmed in Step 0. "Rampaging Run" is the ride's name, not a
section; "hybrid" here means hybridizing the two rides.

**Records baseline** (2026-08): speed 250 / structure 163 m / drop 158 m (camelback; de facto,
not a formally tracked record) / length 4,250 m — all Falcon's Flight; launch-speed 240 km/h
in 4.9 s (Formula Rossa, Guinness "highest speed achieved by a rollercoaster launch");
launch-accel 3.3 g (Do-Dodonpa 0–180 in 1.56 s — ride closed,
record vacant in practice); tallest inversion 73 m (Spitfire, Qiddiya). Inversion-class
elements should scale proportionally past 66–73 m by the practical structure factor (~1.3–1.5)
rather than to a fixed number.

**Tech trajectories** (user-corrected framing): metrics run on different clocks. Speed/height
decelerated post-2005 — but both are **budget/uptime-gated, not physics-gated** (wind drives
tall-structure downtime; a far taller coaster is designable today — cf. the hypothetical 500 m
"euthanasia coaster" — nobody funds it). **Cliffs don't scale with time at all — they are a
siting choice**; real site classes: Tuwaiq/Qiddiya 200 m (built precedent) → **Jebel Fihrayn
"Edge of the World" ~300 m** (same limestone escarpment geology, managed tourist site;
Katoomba's 310 m Scenic World proves ride infrastructure at this height) → Cabo Girão 580 m /
Wadi Ghul ~1,000 m beyond. Propulsion has huge proven headroom (maglev LSMs 603 km/h, EMALS
energy ~5× a coaster launch): 340 km/h is economics, not physics. Launch *acceleration* is
gated by the human envelope, not motors — hence 4 g rides on the envelope credit. Drag: −20–30%
near-term via fairings (Formula Rossa's goggles show open-air is a choice, not a law).

**FVD shape recipe** (why elements look real this time): prescribe vertical/lateral g and
**roll-rate** (deg/s, never angle) over arc length; curvature = (proper accel + gravity across
track)/v². A symmetric g-profile does NOT give a symmetric hill (R = v²/((n−cosθ)g), speed
differs per side) — camelbacks need the g-profile symmetric in arc length about a pinned
pitch-0 apex with speed-compensated scaling. Drops get an explicit pitch-target/geometric core
(this replaces the old trim hack). Element closure = one 1D solve on exit pitch. Banks from
g-balance at local speed (outward rim turn = sign flip). Clothoid-look loops/Immelmanns emerge
from constant-g authoring at varying speed. Siblings scale R ∝ v². Per-element sanity: apex
pitch ≈ 0, seam pitch/roll handoff, envelope, onset, roll rate, C4.

## Shape of the rewrite (principles, not steps)

- Split godot/ride_model.gd into roughly: **verify** (kept toolkit, near-verbatim) ·
  **elements** (FVD templates with the shape recipe + infrastructure pieces) · **generator**
  (seed → terrain → story grammar → sequence → one-shot integration, cheap 1D solves only) ·
  **terrain** (seeded heightfield with a ~300 m Fihrayn-class escarpment; elements placed
  relative to terrain, POV-informed heights — no stilt cities).
- Flow rules replace the old contract: banks carry through seams (no forced 0° resets), no
  dead flats between elements, infrastructure share of track small, slow beats are deliberate
  POV-derived story moments (crest hold, cliff-lip crawl, etc.), everything C4 at seams.
- godot/main.gd minimal and generic: track ribbon/rails, terrain, placeholder train, the four
  cameras. No scenery props, no emissive fins. The engineering build keeps a debug/metrics HUD
  for the user (like the current one: section name/kind, speed, height AGL, selected row,
  bank/roll, per-axis g's, envelope usage, ride totals).
- **First-class, sustainable architecture:** the foundation (generator / elements / verify /
  terrain split and their interfaces) must be good enough to build on for **~3 years** — the
  eventual configurable generator (style, element picks, per-element targets) grows on it
  without rewrites. Nothing in the core gets corner-cut in a way that forces a redo for the
  final version. The sanctioned placeholder is visuals only (train/pillar/track *appearance*),
  never the math or the architecture.
- godot/smoke.gd: multi-seed headless — same seed twice identical; several seeds all valid.
- Validation is parametric per seed: continuity, stretched envelope with the proportional-usage
  principle, flow rules, terrain/self clearance, element-shape sanity (camelback symmetry,
  drop steepness, inversion geometry). Project CLAUDE.md gets rewritten to match all of this.

## Repo handoff (DONE 2025-08 on the old PC — historical)

The continuation runs on a different PC cloned from the `vibe-coaster` GitHub repo, so the repo
must carry everything needed and nothing else:

- **Copy this plan into the repo** (e.g. `docs/PLAN.md`) — it currently lives in
  `~/.claude/plans/` and would NOT transfer with a clone.
- **Commit the pending state**: the working tree already deletes the Rust crates, Cargo files,
  rust-toolchain, gdextension files, and old docs, and adds the GDScript checkpoint
  (godot/ride_model.gd, docs/REFERENCE.md, modified godot/* and CLAUDE.md/README). Commit and
  push so the clone starts clean.
- Nothing else to prune: `.gitignore` already excludes `target/`, `graphify-out/`, `.DS_Store`,
  and `godot/.godot/` (local-only junk that won't transfer), and CI is already Godot-only.
- What the clone should contain: `godot/` (project.godot, main.tscn, the four .gd files +
  .uid files), `docs/REFERENCE.md`, `docs/PLAN.md` (this plan), `CLAUDE.md` (to be rewritten
  per this plan), `README.md`, `.github/workflows/ci.yml`, `.gitignore`.
- Note: auto-memory (`~/.claude/projects/...`) also does not transfer; anything worth keeping
  must live in the repo docs.

## Step 0 of the implementation session (new PC, before any code)

> **STEP 0 COMPLETED 2026-08-08 — results in `docs/RESEARCH.md` (do not redo the video/fact
> research). One open item remains for the rewrite session's start: structure-vs-terrain
> sanity (~250 m provisional structure vs ~300 m Fihrayn relief) — see RESEARCH.md §6.**

**First: review this plan with the user and ask questions — do not start coding straight away.**
The new session reads docs/PLAN.md, surfaces anything stale or ambiguous, and confirms the open
items below before executing.

1. **POV frame-by-frame analysis — non-Fable agent** (user requirement). Real Falcon's Flight
   onride POV (post-opening) + Tormenta POV for dive elements. Video download needs user
   permission first. Deliverables: phase list with speed estimates (from known geometry spans +
   timestamps), true cliff-climb profile, slow-beat inventory with durations,
   height-over-terrain per phase, element shape notes, and per-element g-character of the real
   counterparts (for the proportional scaling rule).
2. Refinements flagged above: structure-vs-terrain sanity (~250 m provisional), envelope
   lateral/roll axes against actual F2291 duration tables, inversion-class sizing factor.

## Verification

- `godot --headless --path godot --editor --quit`
- `godot --headless --path godot --script res://smoke.gd` (multi-seed determinism + validation)
- **Performance testing runs in Claude's virtual environment, not the user's PC** — headless
  multi-seed generation timing there gives a conservative, repeatable baseline for generation
  speed/latency instead of numbers flattered by the user's hardware.
- Ride several seeds in-app: banks carry through, terrain hugging per POV evidence, ~300 m
  cliff used by the dive, slow beats present, no dead flats, elements visibly real-shaped
  (symmetric camelback, held beyond-vertical drop, giant Immelmann/loop, cutback), and the
  metrics HUD showing the highest-g element genuinely reaching the envelope.
