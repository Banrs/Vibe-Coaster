# Record Launch Numbers — Engineering Derivation

**Status:** approved direction (2026-08-15 review session): resolve gap B toward the
contract, but derive the numbers from real engineering before touching code. This note is
the derivation of record; the numbers below become both the prose and the gated code.

## Authority

User decision → reproducible physical derivation → vision docs → code. The ~2041 premise
grants plausible near-future credit on real, measured technology — never a physics handwave.

## 1. Entry launch (Do-Dodonpa-class air/hydraulic)

Real reference: Do-Dodonpa (2001/2017, compressed air) — 0–180 km/h (50 m/s) in 1.56 s,
mean acceleration ≈ 32.05 m/s² ≈ **3.27 g**. The landed code authors a 3.2 g plateau —
i.e. the built ride matches the *2001* reference, and CLAUDE.md's "~4 g" was the
unsupported side of the disagreement (recorded in `docs/ISSUES.md`).

2041 credit: higher-pressure storage, faster valves, and the anti-G-suit rider envelope
(+8.0 Gx, 25 g/s onset — `godot/verify.gd`) support a **peak authored drive of 3.9 g**
(mean over the pulse ≈ 3.5 g, ≈ +8% over the real mean; peak well inside +8.0 Gx and the
onset limit). That keeps CLAUDE.md's "~4 g" honest as a peak figure.

Constraint that caps it: act one runs at honest giant-inversion speed (42–50 m/s entries —
measured physics limit). The launch's **exit speed must therefore stay where the story
needs it**; raising peak g means shortening the pulse to conserve Δv, making the launch
punchier without breaking the opener/act-one speed bands. Issue 9's ask ("launch speed in
the tunnel-booster class") cannot be satisfied literally without destroying act one — the
punch rises, the record speed sensation stays with LSM3. Recorded as the honest reading.

## 2. Tunnel LSM3 (the record launch, ~340 km/h)

Real references: fastest current LSM coaster launches ≈ 180 km/h (Red Force, Top Thrill 2);
hydraulic Formula Rossa 240 km/h; Falcon's Flight (Intamin) ~250 km/h class on a downhill
LSM run. Rail-guided speed itself is proven far beyond 340 km/h (TGV 574.8 km/h wheeled,
~19.6 MW; L0 maglev 603 km/h), so the binding constraints are launch power electronics and
wheel/bogie rating — engineering, not physics.

The ride's LSM3 does not start from rest: it boosts from cliff-dive exit speed
(≈ 85–88 m/s after a ~245 m drop) to the record. Required: exit **93.9–95.6 m/s
(338–344 km/h)**, Δv ≈ +4–9 m/s beyond today's built 91.2 m/s. At ~1.3–1.4 g drive and
~94 m/s, per-train power peaks ≈ 13–16 MW (m ≈ 12 t) — a record-scale but credible 2041
installation (TGV-record-class power, flywheel/supercap buffered like existing launch
systems), run over a 150–220 m tunnel booster consistent with the role band. Verdict:
**340 km/h holds up**; the built 328.3 km/h was a tuning shortfall, not a physical limit.

Downstream consistency: camelback entry at ~94.5 m/s crests the ~250 m structure at
≈ 63 m/s (√(94.5² − 2·9.81·250)) — sustained-airtime crest speed, consistent with the
marquee intent; the unpowered return then bleeds to the 70–77 m/s passive entry band via
the seven-control solve.

## 3. Gated outcomes

- Tunnel exit / ride top speed: **93.9–95.6 m/s (338–344 km/h)**, asserted in `smoke.gd`
  on the deep seeds and in `generator_material_tests.gd` (tightened from the old 90–98
  acceptance).
- Entry launch peak authored drive: **3.9 g, band 3.7–4.1**, replacing the 3.0–3.8 test
  band; Δv conserved so opener/act-one entry speeds stay within their proven bands.
- LSM2 cliff-base climb assist is untouched by this derivation: its ~0.29 g drive follows
  from its speed/length targets, and no record claim attaches to it.
