# Honest Drag — Engineering Re-Derivation

**Status:** **built and refused by measurement (2026-08-16); nothing landed, `AERO_PER_M` stays 0.000075.** The re-baseline was
executed end to end against issue 24's landed prefix closure solve. Six of its seven beats close at honest drag — §7 records the
exact constants that produced a 340.2–340.4 km/h record, an in-band camelback and a 310 km/h launch — and the seventh, the
seven-control return, does not close from **any** control vector, including deliberately over-wide diagnostic bounds and an
opened route band. §§3.1–3.5 below are corrected in place where the built measurement contradicted the analytic propagation; the
uncorrected prose is the derivation as first written and §7 is what the code did. **Authority:** user decisions → physical
derivation → vision docs → code; where this disagrees with issue 2's recorded band, the disagreement is derived and the loser
corrected.

## 1. The constants

`a_res(v) = rolling + aero·v²` (`godot/motion.gd:155`), today `0.08 + 0.000075·v²` (`godot/ride_program.gd:9-10`), where
`aero ≡ ½ρ·Cd·A/m` [1/m] and `rolling ≡ c_rr·g`.

**AERO_PER_M := 0.00021, tolerance 0.00015–0.00025.** `m = 12,000 kg` (the train mass the record derivation uses, §2).
**ρ = 1.04 kg/m³ (0.99–1.09):** issue 2 records 1.1–1.225 "desert air", which is a sea-level figure and the site is not at sea
level — `docs/PLAN.md` fixes the site class as Jebel Fihrayn, the Tuwaiq escarpment top, ~950 m. `p = 101325·(1 −
2.25577e-5·z)^5.2559` → 90.4 kPa, and `ρ = p/(287.05·T)` gives 1.093 at 288 K, 1.040 at 303 K, 0.991 at 318 K: operating air is
thin and hot, so honest ρ is ~15% *below* the recorded band. **Cd·A = 4.8 m² (3.6–5.6):** today's open ~12 t train has frontal
area ≈ 3.0–3.6 m² (car width ~2 m × seated-rider height ~1.7 m) and Cd ≈ 1.3–1.6 for a bluff multi-row body with exposed riders
and row-to-row interference → 4.5–7.0 m², the band issue 2 records; point 6.0. The **fairing credit is −20%, the conservative
end of `docs/PLAN.md`'s 20–30%** (nose cones, faired chassis, per-row windscreens): claimable on the chassis/bogie/interference
share (≈35–45% of Cd·A), *not* on the exposed-rider share, because the trains stay open by design — 30% would need the
windscreens to erase most of the rider term, and that is the fiction line. So `½·1.04·4.8/12000 = 2.08e-4` → **0.00021**, with
corners `½·0.99·3.6/12000 = 1.49e-4` and `½·1.09·5.6/12000 = 2.54e-4`. That is **2.8× today**, not issue 2's 3–5×, and every
reason it lands at the floor of the recorded band is derived above; terminal speed `√(g/aero) = 216 m/s` stays far above any
ride speed, so gravity still dominates the dive.

**ROLLING_MPS2 := 0.08, unchanged.** `c_rr = 0.08/9.81 = 0.0082`; steel-on-steel rail is 0.001–0.002, polyurethane
road/upstop/side wheels on steel rail ~0.005–0.015 (hysteresis plus preload on three wheel sets rail does not carry). 0.0082 is
mid-band and already carries bogie credit, so issue 2's "defensible" verdict stands. One omission is *named, not fixed*: real
rolling loss scales with normal load, so a 4 g valley costs ~4× and the model is load-independent — `Δh = 0.08·(n̄−1)·s/g` ≈
26 m of head for 1600 m at n̄ = 3. Adopting it would couple `resistance()` to `normal_g`: measured non-goal (§6.5).

**Evidence check.** `docs/TELEMETRY.md` has no usable drag evidence: its one near-level unpowered row, the clifftop crest crawl
at t 78.0–90.3 (`TELEMETRY.md:123`), reads Gx −0.28…−0.43 sustained at crawl speed — orders above any drag term there, so trim
braking, not decay — and the 6.0–13.5 s "coast/climb" row is on the LSM lift hill RCDB lists. Recorded as an evidence gap.

## 2. Analytic propagation

Extra head per metre: `Δh′ = (aero_new − aero_old)·v²/g = 1.376e-5·v²`. Applied over the nominal role lengths
(`ride_program.gd:105-113`, Σ = 7870 m) with anchors: launch exit 71.9 m/s (the authored pulse,
`9.81·3.9·(0.5·0.3903354 + 0.8038 + 0.5·1.762572)`, `:531-539`), act one 42–50, LSM3 entry 69.95, record 94.73 (measured,
seed 42), arrival 79.7 (record derivation §2).

| beat | L (m) | v̄² | extra head | absorbed by | territory |
|---|---|---|---|---|---|
| station-launch | 180 | 2586 | 6 m | launch plateau duration | prefix |
| opener (3 roles) | 1600 | 4553 | 100 m | launch Δv (§3.1) | prefix |
| act one (5 roles) | 1600 | 2200 | 48 m | launch Δv + role targets | prefix |
| climb-lsm2 | 600 | 1220 | 10 m | `climb_core_s` (solve control) | prefix |
| clifftop (2 roles) | 140 | 324 | 1 m | `crest_hold_s` (solve control) | prefix |
| outward-dive | 420 | 2609 | 15 m | residual 4 / `dive_approach_s` | prefix |
| tunnel-lsm3 | 180 | 6934 | 17 m | LSM3 length or drive (§3.3) | constant |
| camelback | 1000 | 6000 | 83 m | `fall_s` / `crest_s` / `unload_s` | constant |
| return (4 roles) | 1920 | 5191 | 137 m | seven-control solve | return |
| capture + brakes | 230 | 2116 | 7 m | brake solve | return |

**Σ ≈ 424 m of extra head per circuit.** The loop is closed, so gravity nets zero and propulsion pays resistance plus the
terminal brakes. Today's propulsive head ≈ 257 m (launch) + 152 m (LSM2, `9.81·0.293679·10.756 = 31.0 m/s`) + 239 m (LSM3,
`9.81·1.33·1.9333 = 25.2 m/s`) ≈ 648 m, so honest drag adds ~65% to the loss side: not absorbable by drive constants alone.

## 3. Beat-by-beat verdicts

- **3.1 Entry launch: Δv +≈13 m/s, peak g unchanged.** To hold the Immelmann entry inside 42–50 m/s the launch must pay the
  opener's extra head; iterating (a faster opener sheds more) exit 71.4 → **≈ 84 m/s (302 km/h)**, head 259.8 → 360 m. At the
  gated 3.9 g peak that is `+12.6/(9.81·3.9) = +0.33 s` of plateau (+17%), so **the 3.7–4.1 g band is untouched** — it gates peak
  drive, not Δv. Consequence, not a wish: this substantially closes **issue 9** (302 vs 341 km/h), which the record derivation
  had to refuse as a free choice. Caution: at 84 m/s the opener's g-profiles sweep larger radii (`R = v²/(n·g)`), so it inflates
  and sheds more again — the coupling converges only inside the closure solve.
  **Corrected by measurement (2026-08-16).** Two things here are wrong. (a) 71.9 m/s is the authored *drive Δv*, not the exit:
  the launch already exits at **77.004 m/s (277.2 km/h)** from the 6 m/s station. (b) The launch does **not** pay the opener's
  extra head. A 0.95–1.45 s sweep of the plateau at the gated 3.9 g peak (85 points, coarse step) measures act-one-exit head
  running −51.9 → +159.4 m against the old-drag baseline's **186.7 m**, non-monotonically, and never reaching it: the faster
  opener sheds what the launch adds, exactly as the caution predicted, and it saturates. Inside the 300–320 km/h exit band
  (plateau 1.02–1.17 s) the best head is 124.4 m at 1.17 s, where act one's minimum speed has fallen to 21.4 m/s and the
  inversions are no longer honest. The landing point §7 uses is **plateau 1.094 s, exit 86.184 m/s (310.3 km/h)**, chosen because
  it is the only value in the band where the act-one exit **bank crosses zero** (7.4° of residual bank at 1.08 s is amplified by
  the climb to 53° at the crest, which tips the whole clifftop into a dive) — and it arrives **102.5 m of head short**, which
  §3.2's "negligible" LSM2 then has to find.
- **3.2 Act one held; LSM2 negligible.** With §3.1 the Immelmann entry stays at today's ~46 m/s, and the 48 m lost *inside* act
  one bleeds the later inversions ~3–4 m/s, absorbed by the role targets once issue 24 unblocks them (issue 3). LSM2's +10 m of
  head over ~520 m of drive is +0.16 m/s² = **+0.017 g** (0.294 → 0.311), or no constant change with `climb_core_s` +~0.3 s.
  **Corrected by measurement (2026-08-16): LSM2 is the largest re-derivation in the chain, not the smallest.** Act one *is* held
  — at plateau 1.094 s its minimum speed measures 37.30 m/s against the baseline's 36.08, so the inversions run honest — but the
  handoff it delivers is 102.5 m of head down (§3.1), and the only propulsion downstream of it is the cliff-base assist. The
  drive has to **roughly double, 0.29368 → 0.59711 g**, and the assist's shape has to be re-authored with it (pull-up peak
  3.37797 → 3.22746 g, core normal 0.87362 → 0.82272, pull-over normal 0.72153 → 0.58484, seed `climb_core_s` 8.78839 → 7.7012 s
  and `climb_pull_over_s` 3.20659 → 3.8044 s) because the climb is *unstable* in its entry speed: below ~40 m/s the pull-up over-
  rotates, the core steepens as it slows, and the ride crests early and falls off the far side before the clifftop begins. The
  re-derived assist reproduces the old-drag crest to **v 19.435 (was 19.462), y 285.86 (286.20), pitch −0.51° (−0.52°), bank
  0.38°, role length 636.6 m (636.0 m, band 520–680)** — found by multi-start coordinate search over the six knobs, not by hand.
- **3.3 Dive exit → LSM3, and the record.** The dive sheds 15 m more, so LSM3 entry falls **69.95 → ≈ 67.8 m/s**; inside the
  180 m tunnel the extra decel `1.35e-4·6934 = 0.94 m/s²` over ~2.2 s costs 2.1 m/s, so required drive Δv rises 25.2 →
  **29.4 m/s**. Two legal ways to pay it: **length at unchanged 1.33 g** — plateau 1.933 → 2.256 s, the booster grows ~180 →
  **≈ 207 m**, inside its 150–220 m role band, so **the record survives at 1.33 g** (preferred); or **drive at unchanged
  length** — `29.44/(9.81·1.9333) = 1.55 g`, peak power `12000·1.55·9.81·94.73 = 17.3 MW` against the record derivation's
  15 MW-class figure at 1.33 g (14.7 MW by the same arithmetic), whose cited ~19.6 MW TGV-record ceiling allows
  `19.6e6/(12000·94.73) = 17.24 m/s² = 1.76 g`. **~13% of power headroom remains either way.**
- **3.4 Camelback crest.** Entry head `94.73²/19.62 = 457.4 m`; the ~500 m rise now costs 66 m (vs 28), so crest head =
  457.4 − 250 − 66 = 141 m → **crest ≈ 52.5 m/s**, down from ≈ 59 (the record derivation's drag-free 63). At the authored −1.55 g
  crest the radius `v²/(2.55g)` tightens 139 → **110 m**, so the ~250 m prominence claim moves; `fall_s` (3.40), `crest_s` and
  `unload_s` absorb it — that note already had `fall_s` re-tuning with the handoff.
  **Corrected by measurement (2026-08-16), and constrained by user ruling.** Right in sign, close in value: the built crest
  measures **49.67 m/s** against the predicted 52.5 (baseline 56.14). But **the prominence claim does not have to move**, and by
  Daniel's ruling of 2026-08-16 it may not: the camelback stays ~250 m above its valley and symmetric — a taller or reshaped hill
  is not an available absorber. Measured: `fall_s` **3.40 → 3.20 alone**, a same-height fall retune, holds prominence at
  **246.86–247.07 m** (band 245–255) with width/height **3.130–3.137** (band 3.1–3.9) on the three deep seeds, and the hill comes
  out *more* mirrored in height than the shipped one, not less — fall/rise height **1.012–1.014** against today's 0.966, arc
  0.793 against 0.824, time 0.883 against 0.878. `crest_s` and `unload_s` were **not** touched. Probing them (as a diagnostic
  only, before the ruling) confirmed the ruling independently: lengthening the rise drives prominence to 264–270 m, straight
  through the 255 ceiling, pushes the exit below station height, and made the §7 return wall *worse* (best residual cost 2060 with
  a −129.5 m height miss, against 413 at the pinned height). **The camelback is not where the energy went and not what blocks the
  chain.**
- **3.3 correction (2026-08-16).** The measured dive exit is **70.145 m/s**, not 67.8 — the re-derived climb (§3.2) hands the
  dive the same crest it always had, so the dive itself is unchanged to within 0.06 m/s. The tunnel therefore needs less than the
  table predicted: **core plateau 1.633337 → 1.933 s at unchanged 1.33 g**, growing the booster **184.6 → 211 m** (band 150–220),
  not 2.256 s. At that setting the prefix closure converges on seeds 11/42/20260809 in **16–28 of its 31 allowed evaluations**
  and the built ride tops out at **94.509–94.547 m/s (340.22–340.37 km/h)** — inside the 93.9–95.6 gate, with the certified
  0.4 m/s fleet margin intact. **The record survives honest drag at 1.33 g**, which was §3.3's preferred answer.
- **3.5 Return arrival: the largest shift, and it goes the helpful way.** The post-record beats shed ~227 m more head against a
  terminal brake budget of `79.7²/19.62 = 323.8 m`; iterating the return's own mean speed down, arrival converges to
  **≈ 45 m/s (162 km/h)**, not 70–80. Honest drag does not merely ease the record derivation's ~21.8 m surplus-head problem —
  **it deletes it**, and with it the reason the band was widened 70–77 → 70–80 on 2026-08-15. `CAPTURE_ENTRY_SPEED_MPS` (`:70`)
  is itself an artifact of understated drag and must be re-derived; it is a `CLAUDE.md` contract constant, so that needs its own
  note and a user decision, exactly as the widening did. The 7800–8200 m route band needs no change: honest drag asks for a
  slower arrival, not a longer circuit.
- **3.6 Brake solve, and the load gates.** At ~45 m/s over the 150 m reserve (`generator.gd:324`) mean decel is
  `2025/300 = 6.75 m/s² = 0.69 g`, solved peak ~1.0–1.2 g; the 3.6 g cap (`:84`) was raised only because the widened 80 m/s
  corridor needed ~3.0 g of it, so it reverts with the band and 4.286 g is never neared. Elements are force-authored, so lower
  speed changes *radii*, not `normal_g`/`lateral_g`; only `longitudinal_g = drive − a_res/g` (`motion.gd:461`) moves, gaining
  a sustained −0.20 g at 94.7 m/s (vs −0.075) — inside −6.0 Gx, but it shifts push-pull and reversal baselines.

## 4. Territory split

- **Prefix (blocked on 24):** §3.1–3.3. `climb_core_s`, `climb_pull_over_s`, `crest_hold_s` and `dive_approach_s` absorb
  §3.2–3.3, and residual 4 (`record_exit_speed_mps`) pins the record and freezes the camelback handoff. §3.1 has no control
  today — the design's open question ("whether a fifth control is needed", §9) is **answered here: a launch-duration control**,
  because Δv must move while peak g and the act-one entry band stay fixed.
- **Return (seven-control solve):** §3.5–3.6, via a re-derived `CAPTURE_ENTRY_SPEED_MPS` and `RETURN_SEED` against the existing
  route-length and entry-speed band residuals. **Pure constants:** `AERO_PER_M`; the LSM3 tunnel length (or `lsm3_drive_g`);
  camelback `fall_s`, `crest_s`, `unload_s`; `BRAKE_PARAMETER_BOUNDS[1]`. `ROLLING_MPS2` does not move.

## 5. Certification plan

**Must NOT move** (each needs its own derivation): record band 93.9–95.6 m/s; entry-launch peak band 3.7–4.1 g; route band
7800–8200 m; the 42–50 m/s inversion band; the ~2041 envelope; same-seed bit identity. **Moves, each with its own recorded
derivation and a user decision where `CLAUDE.md` names the number:** `CAPTURE_ENTRY_SPEED_MPS`; the 3.6 g brake cap; the
camelback prominence baseline; and every committed baseline (hashes, geometry metrics, quoted numbers) re-baselined in one
commit, the treatment the decision-streams change got. **Fleet diversity floors** are floors and honest drag makes the fleet
more speed-sensitive, so they should hold — re-measured, never assumed. **New assertion pinning the
constants** (`motion_tests.gd`): recompute `½ρ·Cd·A/m` from the derived ρ, Cd·A and m; assert `AERO_PER_M` equals that point
value and lies inside 0.00015–0.00025, and `ROLLING_MPS2/9.81` inside 0.005–0.015 — data ships once: the test recomputes the
identity, this note carries the justification. **Acceptance:** fifteen seeds green on structure, seams, terrain/self clearance; `validate_loads` green on the three deep seeds; record, launch and diversity gates green; both solves converge
inside their caps with coarse/fine agreement; **no gate band widened without its own derivation.**

## 6. Implementation sketch (TDD, after issue 24's stages land)

1. **Launch-duration control.** Failing test: the prefix solve converges on all fifteen seeds with a fifth control (launch
   plateau duration, bounds certified at both extremes) at **today's** drag — isolating the new DOF from the new physics.
2. **Capture-entry band re-derivation.** Its own note plus a user decision; land the new band and the brake cap with
   `RETURN_SEED` re-derived, still at today's drag, so the band change is proven alone.
3. **Flip the constants.** Failing test: §5's identity assertion at the honest values. Then re-derive the launch seed,
   `climb_core_s`, the LSM3 tunnel length (~207 m at 1.33 g), camelback `fall_s`/`crest_s`, and `RETURN_SEED`.
4. **Re-baseline and close.** Artifact hashes, geometry metrics, and the quoted numbers in `CLAUDE.md`, `docs/ISSUES.md`
   (issues 2 and 9) and the record derivation, in one commit.
5. **Measure the named non-goal.** Report `∫0.08·(n̄−1)·ds/g` on the deep seeds into `docs/ISSUES.md`; adopt or refuse
   load-dependent rolling resistance on evidence, not now.

## 7. Built and refused: the return will not close at honest drag (2026-08-16)

The whole re-baseline was implemented against the landed prefix closure solve and run, not argued about. **Six beats close; the
seventh does not, and nothing landed** — `AERO_PER_M` stays 0.000075 and the tree stays green, because a partial energy chain
builds zero of fifteen seeds.

### 7.1 The chain that closed (measured, seeds 11 / 42 / 20260809)

`AERO_PER_M := 0.00021` exactly as §1 derives, `ROLLING_MPS2` unchanged, and:

| constant | old | honest | why |
|---|---|---|---|
| launch plateau `launch_core_s` | 0.8038 s | **1.094 s** | exit 77.004 → **86.184 m/s (310.3 km/h)**, inside the 300–320 band; peak stays 3.9 g so the 3.7–4.1 gate never moves |
| climb `climb_drive_g` | 0.29368 | **0.59711** | §3.2 — the assist has to find the 102.5 m of head the handoff is short |
| climb pull-up peak | 3.37797 g | **3.22746 g** | re-shaped with the drive; the climb is unstable in entry speed |
| climb core normal | 0.87362 | **0.82272** | ” |
| climb pull-over normal | 0.72153 | **0.58484** | ” |
| `PREFIX_SEED[0..1]` | 8.78839, 3.20659 | **7.7012, 3.8044** | re-seeded so the preflight places an outward dive |
| tunnel `lsm3` core | 1.633337 s | **1.933 s** | §3.3 — booster 184.6 → 211 m at unchanged 1.33 g |
| camelback `fall_s` | 3.40 | **3.20** | §3.4 — same-height fall retune; prominence held, hill not raised |

Measured outcomes: top speed **94.509–94.547 m/s (340.22–340.37 km/h)**, inside the 93.9–95.6 record gate on every seed tried;
entry-launch peak unchanged at 3.9 g; act one's minimum speed **37.30 m/s** against the baseline's 36.08, so the giant inversions
run at honest speed; prefix closure **converged** in 16–28 of 31 allowed evaluations; camelback prominence **246.86–247.07 m**
with width/height 3.130–3.137; every prefix role length inside its declared band.

### 7.2 The wall: the camelback → return handoff moves 630 m, and the return has no height authority

Honest drag does not move the return's *arrival speed* (§3.5's expectation) — it moves the **handoff**, because the prefix's
ground track is chaotic in its own force constants. Measured against the old-drag build on seed 11, at the tunnel exit the
station sits **974 m** behind along its own forward axis instead of **343 m**, with ~20° more yaw; by the camelback exit the shift
is **426 m forward, 86 m cross, −22 m height and −7.05 m/s**. Issue 24's act-one swap — which already defeated three separate
attempts — moves that same handoff by 32–66 m and 3.5–5.1°. This is an order of magnitude more.

No control vector closes the seven return residuals. Each row is 900 random starts inside the stated bounds plus a bounded-Newton
refinement from each of the best 20, scored as the sum of squared scaled residuals:

| bounds | best cost | what remains |
|---|---|---|
| production | 2986 | cross-track 249 m, height −70 m, station-forward −215 m |
| turn-a bank floor 50°→35°, turn-b 60°→40°, duration ceilings raised | 1074 | height **−77.6 m** |
| deliberately over-wide diagnostic (banks 15–80°, durations to 30 s) | 413 | station-forward 36.9 m, cross 36.7 m, height **−78.6 m**, route +39.5 m past 8200 |
| the same, plus the route band opened to 7000–9500 m | 537 | station-forward −4.4 m, cross 31.2 m, height **−72.8 m** |

**The residual that never yields is the capture-gate height, −73 to −79 m in every configuration**, including one where the
horizontal placement is essentially solved and the route band has been removed as a constraint. The mechanism is structural, not
a basin: the return's height beats are authored at fixed peak g, so the rise of each scales with `v²`; honest drag runs the whole
return 8–10 m/s slower and each beat climbs ~20–25% less, while the handoff also starts 22 m lower. **All seven controls are
durations and bank angles. None of them is height authority.** Raising the camelback exit to hand the return more head was
measured and is worse, not better (§3.4), and the ruling of 2026-08-16 forecloses it regardless.

### 7.3 Both reverts are blocked behind this, and the block is measured

Neither the capture-band nor the brake revert is a free correction that can be taken while honest drag waits — under **today's**
understated drag both are still load-bearing, measured on all three deep seeds:

- **`CAPTURE_ENTRY_SPEED_MPS` 70–80 → 70–77:** every deep seed budget-exhausts the return at 79/80 with the entry speed
  **+1.04 … +1.39 m/s past the 77 ceiling**. The widening is doing exactly the job the record derivation says it is.
- **`BRAKE_PARAMETER_BOUNDS[1]` 3.6 → 3.0 g:** every deep seed refuses with `brake solve reached a parameter bound`; the solved
  peak on seed 11 is **3.0108 g**, over a 3.0 cap by 0.011 g.

So §3.6's "it reverts with the band" is right about the *reason* and wrong about the *order*: the reverts are downstream of
honest drag landing, and honest drag cannot land until the return closes. Neither number was touched.

### 7.4 What the next attempt needs

Not another seed and not another scalar — the last four attempts in this area all moved a scalar the solve was not short of.
The return needs **height authority**: a control that sets how much the return climbs rather than only how long it takes (the
natural candidate is `RETURN_HEIGHT_A_PEAK_G` / `RETURN_HEIGHT_B_PEAK_G` becoming solved controls, so the beats can hold their
rise as `v` falls), **or** the prefix needs a handoff-pose residual so the camelback → return seam lands where the return was
authored for. That is the same verdict issue 24 reached for the act-one swap at 32–66 m of handoff shift, restated at 630 m.
Until one of those exists, honest drag has nowhere to put the energy.
