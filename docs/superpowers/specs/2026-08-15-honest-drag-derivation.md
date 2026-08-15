# Honest Drag — Engineering Re-Derivation

**Status:** derivation only (2026-08-15); nothing implemented. Issue 2's mechanism is recorded — this is the engineering its fix
will execute **after issue 24's prefix closure solve lands** (`2026-08-15-prefix-closure-solve-design.md`). **Authority:** user
decisions → physical derivation → vision docs → code; where this disagrees with issue 2's recorded band, the disagreement is
derived and the loser corrected.

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
- **3.2 Act one held; LSM2 negligible.** With §3.1 the Immelmann entry stays at today's ~46 m/s, and the 48 m lost *inside* act
  one bleeds the later inversions ~3–4 m/s, absorbed by the role targets once issue 24 unblocks them (issue 3). LSM2's +10 m of
  head over ~520 m of drive is +0.16 m/s² = **+0.017 g** (0.294 → 0.311), or no constant change with `climb_core_s` +~0.3 s.
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
