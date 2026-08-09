# Intimidator 305 — measured vertical-g character reference

## Source & method

- **Video:** "Intimidator 305 Pov With G force readings" — YouTube `wX7uHKj-Ujc`
  (channel *Intamindator 305*, 63k views). 1920×1080, 49.56 s.
  Uploader's own note: *"The Pov is not mine, it is east coasters. The app I used is called
  'Ride Forces'."*
- **Overlay:** a live scrolling accelerometer plot (top-right), y-axis labelled −2 g … +5 g,
  a "now" cursor with the recording clock under it, and `@50 fps` in the corner. Numbers
  change continuously — this is real recorded telemetry, not a static graphic.
- **Channel:** one signed trace. It reads a flat **1.00 g at rest** at the end of the
  recording and goes **negative** in airtime, so it is signed rider-frame **normal (vertical)
  g**, not a magnitude. There is no lateral or longitudinal trace in this overlay.
- **Time base:** overlay clock = video time + 0.21 s (verified at 9 points, 1:1, no speed-up).
  All times below are **overlay/ride seconds**.
- **Plot calibration:** window ≈ 6.6 s wide, ≈ 214 px/s, cursor ≈ 3.5 s of past / 3.1 s of
  future. Derived by matching identical features across frames 4 s apart (two independent
  feature matches agreed to within 1%). Nine overlapping windows (cursor at t = 4.2, 7.2,
  11.2, 15.2, 19.5, 24.5, 29.5, 34.5, 39.5, 44.5, 48.2) tile the whole recording.
- **Precision:** values read off the plot to roughly **±0.15 g**, times to **±0.15 s**. The
  trace carries visible accelerometer noise of ±0.2 g in the high-g sections (real chassis
  vibration plus phone noise); quoted peaks are the local mean of the noise band, not the
  spikes.

**Caveats to carry forward:** (1) the g data and the imagery come from different sources, so
element↔time attribution is the uploader's sync, not mine — the *g numbers and their
durations are solid*, the *element labels are good-confidence but not certified*.
(2) A phone accelerometer includes seat/chassis vibration; treat the sustained plateau values
as trustworthy and the ±0.2 g fuzz as noise.
(3) Element names below are descriptive of what the POV shows; I did not use any published
layout spec.

---

## 1. Element-by-element timeline

Read: **span** = ride-clock seconds, **peak** = peak vertical g, **≥3.5 g** = how long the
trace stays at or above 3.5 g in that element, **neg** = the negative-g excursion.

| # | Element (from POV) | Span (s) | Peak +Gz | Sustain ≥3.5 g | Negative g | Transition into it |
|---|---|---|---|---|---|---|
| 0 | Lift, steep incline | 0.7 – 4.5 | 0.45 | — | — | (clip starts) |
| 1 | Crest / pre-drop float | 4.5 – 7.4 | 0.45 | — | **−0.55** min at 7.2; below 0 for **0.95 s** (6.4–7.35) | 0.45 → −0.55 over 2.7 s (slow, 0.4 g/s) |
| 2 | **First drop pullout** | 7.4 – 8.7 | (rising) | starts 8.55 | — | **−0.55 → +3.7 g in 1.5 s (≈2.8 g/s)**; 0→3 g in 0.93 s |
| 3 | **First banked turn (the big one)** | 8.7 – 12.7 | **4.80** (at 12.3); secondary 4.65 at 11.2 | **4.1 s continuous** (8.55 → 12.68), never dropping below 3.7 g inside it | — | see #2 |
| 4 | Turn exit / bleed-off | 12.7 – 15.4 | 4.8 → 1.55 | — | — | 4.8 → 2.0 in 1.8 s |
| 5 | **Ejector hill #1** | 15.4 – 18.2 | — | — | **−1.15** min at 16.3; below 0 for **2.4 s** (15.8–18.2); below −0.7 g for ~1.5 s | **+2.0 → −1.15 g in 0.8 s (3.9 g/s)** |
| 6 | Dive + banked turn | 18.2 – 20.7 | **4.30** (19.9) | **1.4 s** (19.35–20.75) | — | **0 → +4.0 g in 1.5 s (2.7 g/s)**; −1.15 → +4.3 in 3.6 s |
| 7 | **Ejector hill #2** | 20.7 – 22.4 | — | — | **−0.90** min at 21.5; below 0 for **1.33 s** (21.07–22.4) | **+3.8 → −0.9 g in 0.80 s (5.9 g/s)** — sharpest down-snap of the ride |
| 8 | **Sustained banked turn** | 22.4 – 25.9 | **4.30** (23.6 & 24.4) | **≈3.1 s** (22.75 → 25.95, with a 0.2 s notch to 3.45 g at 25.5) | — | **−0.75 → +3.5 g in 0.63 s (6.7 g/s)** — sharpest onset of the ride |
| 9 | Float notch (hill between turns) | 25.9 – 26.6 | — | — | **−0.05** min at 26.5; below 0.5 g for only **0.35 s** | +3.6 → −0.05 in 0.55 s (6.6 g/s) |
| 10 | Short turn / hill top | 26.6 – 28.7 | **3.75** (27.35) | **0.5 s** (27.15–27.65) | — | −0.05 → +3.7 g in 0.75 s |
| 11 | Low hump | 28.7 – 30.5 | 2.65 (29.46) | — | −0.15 min at 30.55 | 1.55 → 2.65 in 0.8 s |
| 12 | **Long banked turn** | 30.5 – 34.0 | **4.25** (31.7) | **≈2.4 s** (31.45 → 33.85) | — | **−0.15 → +4.2 g in 1.15 s (3.8 g/s)** |
| 13 | **Ejector hill #3 (longest float)** | 34.0 – 37.0 | — | — | **−0.75** min at 35.0; below 0 for **2.3 s** (34.65–36.95); below 0.5 g for **2.6 s** | +3.0 → −0.75 g in 1.0 s (3.8 g/s) |
| 14 | Dive + hill | 37.0 – 39.4 | **3.85** (38.6) | **0.43 s** (38.35–38.78) | — | 0 → +3.85 in 1.6 s |
| 15 | **Ejector hill #4** | 39.4 – 40.7 | — | — | **−0.50** min at 39.7; below 0 for **1.25 s** | +3.85 → −0.5 g in 1.1 s (4.0 g/s) |
| 16 | Turn / rise | 40.7 – 43.4 | 3.25 (42.55) | — (tops out 0.25 g short) | — | 0 → 3.25 in 1.9 s |
| 17 | **Ejector hill #5** | 43.4 – 44.3 | — | — | **−0.40** min at 44.0; below 0 for **0.38 s** | +3.25 → −0.4 g in 1.45 s (2.5 g/s) |
| 18 | **Final low twisted turn** | 44.3 – 47.9 | **3.50** (46.0) | **≈0.3 s** (grazes 3.5) — but **1.7 s above 3.2 g** | — | −0.4 → +3.0 g in 0.75 s (4.5 g/s) |
| 19 | Last airtime pop | 47.9 – 48.9 | — | — | **−0.45** min at 48.5; below 0 for **0.78 s** | +2.0 → −0.45 in 1.0 s |
| 20 | Brakes / station | 48.9 → end | flat **1.00** | — | — | −0.45 → 1.0 in 0.4 s, then dead flat |

### Peaks, ranked
1. **4.80 g** @ 12.3 s (first banked turn, late in it)
2. 4.65 g @ 11.2 s (same element, earlier)
3. 4.30 g @ 19.9 s and @ 23.6 / 24.4 s
4. 4.25 g @ 31.7 s
5. 3.85 g @ 38.6 s

### Negatives, ranked
1. **−1.15 g** @ 16.3 s (ejector hill #1) — 2.4 s below zero
2. −0.90 g @ 21.5 s — 1.33 s below zero
3. −0.75 g @ 35.0 s — 2.3 s below zero (longest float)
4. −0.55 g @ 7.2 s (drop crest)
5. −0.50 / −0.45 / −0.40 g at 39.7 / 48.5 / 44.0 s

---

## 2. Ride-level statistics

Two denominators. **Course** = crest to brake bite, 6.0 → 49.0 s = **43.0 s**.
**Whole clip** = 0.7 → 49.0 s = 48.3 s (adds 5.3 s of lift at ≈0.45 g).

| Band | Course time | % of course | % of whole clip |
|---|---|---|---|
| ≥ 2.0 g | 24.8 s | **58 %** | 51 % |
| ≥ 3.5 g | 12.3 s | **29 %** | 25 % |
| ≥ 4.0 g | ≈ 5.0 s | 12 % | 10 % |
| ≤ 0.5 g | 12.0 s | **28 %** | 35 % |
| < 0.0 g (true negative) | 9.8 s | **23 %** | 20 % |
| 0.8 – 1.2 g ("dead zone") | ≈ 1.4 s | **3 %** | 3 % |

**The dead-zone number is the headline.** Over 43 s of course the ride spends about
**1.4 seconds** anywhere near 1 g, and every bit of that is transit through the band during a
transition — there is **no dwell at 1 g anywhere between the lift crest and the brakes**. The
ride is a two-state machine: pinned (≥2 g, 58 %) or floating (≤0.5 g, 28 %). The 0.5–2.0 g
band accounts for only ~14 % and is entirely made of transitions.

Other structural numbers:
- **9 distinct sub-zero events** in 43 s, i.e. one negative-g moment every ~4.8 s.
- **7 distinct excursions above 3.5 g**, totalling 12.3 s, of which one (4.1 s) is a third of
  the total.
- The trace crosses ±0 g nine times and crosses 3.5 g fourteen times.

---

## 3. Character notes per element family

**First-drop pullout (t 7.4–8.7, feeding element #3).**
The slowest-building onset on the ride: −0.55 g → +3.7 g in **1.5 s (≈2.8 g/s)**, and 0 → 3 g
takes 0.93 s. The crest before it is a *long lazy* negative — 2.7 s from +0.45 to −0.55, only
0.4 g/s — so the drop reads as a fall, not a snap. All of the pullout's violence is in
amplitude, not rate.

**Sustained banked turn (elements #3, #6, #8, #12).**
This is the ride's signature and it dominates the g budget: four turns hold **3.5–4.8 g** for
**4.1 s / 1.4 s / 3.1 s / 2.4 s** respectively — 11 of the 12.3 s the ride spends above 3.5 g.
The first one is the outlier: it enters at 3.7 g and *never dips below 3.7 g for 4.1 seconds*
while climbing to a 4.8 g peak at its end — the load is rising, not decaying, through the
whole hold. The later three are flat-topped 4.0–4.3 g plateaus with ±0.2 g of chassis noise.

**Ejector hill (elements #5, #7, #13, #15, #17, #19).**
Six of them, all genuine sub-zero. Amplitude and duration are inversely traded: the deepest
(−1.15 g) holds 2.4 s below zero; the longest below zero (2.3 s) only reaches −0.75 g; the
late ones are shallow-and-short (−0.4 to −0.5 g for 0.4–1.3 s). Sustained negative is the
norm here, not a spike — **four of the six hold below −0.35 g for over a second**, and the
first two hold below −0.7 g for ~1.5 s each.

**Transition snap (the boundaries between the two families above).**
The ride's real signature. Peak-to-trough swings and their times:
- **+3.8 → −0.9 g in 0.80 s (5.9 g/s)** @ 20.7–21.5 — sharpest unloading
- **−0.75 → +3.5 g in 0.63 s (6.7 g/s)** @ 22.1–22.7 — sharpest loading
- **+3.6 → −0.05 → +3.7 g in 1.3 s total** @ 25.9–27.2 — a full 3.7 g dump and reload back to
  back, with only a 0.35 s float between
- **+2.0 → −1.15 g in 0.8 s (3.9 g/s)** @ 15.5–16.3
- **+3.0 → −0.75 g in 1.0 s**, **+3.85 → −0.5 g in 1.1 s**, **−0.15 → +4.2 g in 1.15 s**
Typical full-scale transition is **3.5–4.7 g of swing in 0.6–1.2 s**, i.e. **3–7 g/s**. Nothing
in the recording exceeds ~7 g/s at this filtering level, and the median big transition is
about **4 g/s**.
