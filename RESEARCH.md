# RESEARCH.md — Real-world element data behind MINECOASTER's generator

Compiled 2026-07-04 from RCDB, Wikipedia, Guinness, Coasterpedia, park/manufacturer
fact sheets, and coaster press. Every number is tagged **[official]** (park/manufacturer
published), **[measured]** (period test data), or **[est]** (enthusiast/derived — radii for
turns/helices/crests are essentially never published; where missing, back-solve from
`r = v² / ((g_felt − 1) · 9.81)`).

How the game uses this: element sizes are capped at **1.0–1.75x the record** (small
elements up to 1.75x, the biggest at 1.25x — `recCapMul`), entry speeds run **~1.5–2.2x
that element's real entry** (`invVMax` windows), sustained felt g lands **~1.75–2x real**
and peaks **≤4x real** (curvature/jerk budgets). Knob locations are listed per element.

---

## Ride-level records (the headline anchors)

| Record | Holder | Numbers | Code anchor |
|---|---|---|---|
| Tallest coaster + tallest drop + fastest + longest | **Falcon's Flight**, Six Flags Qiddiya City, Saudi Arabia — Intamin "Exa Coaster", opened **Dec 31 2025** | Structure 163 m [official]; **drop element 158 m @ 90°** into a tunnel [official]; **~195 m elevation change / ~200 m cliff face** (the "200 m drop" people cite) [official/press]; 250 km/h [official]; 4,250 m track (longest, beats Steel Dragon 2000's 2,479 m) [official]; 3 LSM launches, 700+ LSM modules [official]; ride ~3:25–3:35 [est, sources conflict] | mega `climbTop = frnd(160,198)` = 1.0–1.25x the 158 m element; terrain assist takes measured crest-to-valley drops to ~175–250 m = 1.0–1.25x the elevation change |
| Fastest launch (acceleration) | **Formula Rossa**, Ferrari World Abu Dhabi, 2010, Intamin | 240 km/h, hydraulic 20,800 hp, 0–240 in 4.9 s (~1.7 g launch), ride max 4.8 g, 52 m tall, 2,070 m track [official]. Lost outright "fastest" to Falcon's Flight; still fastest *acceleration* | LAUNCH/BOOST thrust curves in `main.cpp` |
| Tallest operating top hat | **Top Thrill 2**, Cedar Point, 2024 (Zamperla rebuild) | 130 m top hat + 130 m spike; triple launch 119→163→190 km/h; 120 m drop [official]. (Kingda Ka, 139 m, demolished — tower imploded Feb 28 2025) | non-mega `climbTop = frnd(100,139)` |
| Tallest lift-hill coaster | **Fury 325**, Carowinds, 2015, B&M | 99 m lift, 81° drop, 153 km/h, 2,012 m [official] | terrain+drop system |
| Tallest inversion | **Spitfire**, Six Flags Qiddiya, opened Dec 31 2025, Intamin | 73 m inverted top hat [official]; 127 km/h; beat Steel Curtain's 60 m | ceiling check for inversion sizes |
| Steepest drop | **TMNT Shellraiser**, Nickelodeon Universe, Gerstlauer | 121.5°, 43 m drop [official/Guinness] | DROP dy face clamp (~near-vertical) |

## Element-by-element

### Vertical loop
- **Full Throttle**, Six Flags Magic Mountain, 2013, Premier Rides: loop **48.8 m tall x 38.7 m wide (H/W ≈ 1.26 teardrop)**; LSM entry 0–113 km/h; ride max 4.0 g [official]. Record shared at 48.8/49 m with **Flash** (Lewa Adventure 2016) and **Hyper Coaster** (Land of Legends 2018); Guinness separately tracks "largest loop diameter" 42.52 m (different metric).
- **Tormenta Rampaging Run**, Six Flags Over Texas, B&M: claims a 54.6 m loop + **66.4 m Immelmann** — **not yet open** (delayed to July 9 2026); record pending [est until opening].
- Clothoid practice (Werner Stengel, since Revolution SFMM 1976): **bottom radius ≈ 2x top radius**, bottom 3.5–4.5 g, top 1–1.6 g [design literature/est].
- Code: `invSpec(M_LOOP) rMaxRec 22` (≈48.8/2.16 as-built ≈ 2.6x lR height); `stepLoop` radius factor 1.6 bottom → 1.0 top ≈ the clothoid 2:1; entry window ≈ 187–224 km/h = 1.65–2x Full Throttle's 113.

### Immelmann / dive loop
- **Valravn**, Cedar Point, 2016, B&M dive: 68 m tall, 90°/65 m drop, 121 km/h, **50 m Immelmann** [official].
- **Yukon Striker**, Canada's Wonderland, 2019, B&M: 75 m drop (longest on a dive machine), 130 km/h, 50 m Immelmann, first dive-coaster vertical loop [official]. Entry ≈ full drop speed.
- **Steel Curtain**, Kennywood, 2019, S&S: 60 m "dive drop" inversion (US record; world record until Spitfire); 9 inversions; reopened May 2025 after a year closed [official].
- Rule: B&M sizes the Immelmann ~0.67–0.75x the drop height, entered at drop speed, ride-wide max 3.5–4 g [official ride-wide/est per-element].
- Code: `rMaxRec` IMMEL 33 (66.4 m Tormenta pending — the built cap 1.25x lands ≤ ~82 m; today's operating record is 50 m, so flag: consider 25 if Tormenta slips), DIVELOOP 28 (Steel Curtain 60 m).

### Zero-g stall (the ONE inverting-crest roll kept; banana roll & heartline roll were cut as near-duplicates)
- **Goliath**, Six Flags Great America, 2014, RMC: world's first zero-g stall; 55 m/85° drop, 116 km/h [official].
- **Wildfire**, Kolmarden, 2016, RMC: stall as first inversion off a 114 km/h drop; hang ~2–2.5 s ≈ 55–70 m of inverted track [est from POV timing].
- **ArieForce One**, Fun Spot Atlanta, 2023, RMC: longest stall, ~4.5 s [est/press].
- Code: quartic ballistic crest (`initStall`), span capped so the hang is ~2.5–4.5 s (was 7–10 s pre-fix), entry gate 56 m/s ≈ 2.2x real entries.

### Airtime camelbacks (the most common element on real coasters — heaviest pick weight)
- **Fury 325**, Carowinds, 2015: **34 m camelback** taken at ~150 km/h [official fact sheet].
- **Mako**, SeaWorld Orlando, 2016, B&M: 9 designed airtime moments; **speed hill −1.0 g, other hills −0.5 to −0.7 g floater, max +4 g** [official/press — best floater calibration found].
- **Kondaa**, Walibi Belgium, 2021, Intamin: 50 m tall, 113 km/h, **15 airtime moments** (steel record) [official].
- **Zadra**, Energylandia, 2019, RMC: 62.8 m, 121 km/h [official]; RMC ejector ≈ −1 to −1.5 g vs B&M floater 0 to −0.7 [est]. Strongest ejector cited: El Toro "Rolling Thunder" ~−2.2 g, Skyrush ~−2 g [est, untracked officially].
- Crest-to-crest spacing: unpublished; derived by the crest-g formula the game uses (`hillLenFor`: κ=(1−g_c)·G/v_c², L≈2π√(h/2κ)) — reproduces Mako's ~60 m hills at ~30 m/s crest with −0.5 g.
- Code: `hillH frnd(50,78)` vs tallest real camelbacks (Falcon's Flight's 163 m first camelback is structure, not a mid-ride hill; mid-ride record class ~34–60 m); crest target −3.2 felt ≈ 2x RMC ejector; hills only offered where ≥36 m is affordable (else the label lies).

### Stengel dive
- **Goliath**, Walibi Holland, 2002, Intamin (the original): camelback crest rolling **121° overbanked at the apex** into a 270° descending helix; 46.2 m, 107 km/h [official/wiki].
- Code: `initStengel` crest bank 1.95 rad ≈ 112°, needs ≥30 m dive room, entry gate 62 m/s ≈ 2x.

### Wave turn / outward-banked airtime
- **Steel Vengeance**, Cedar Point, 2018, RMC: **35 m outward-banked hill** off the first drop [official]; RMC wave turns ~90° outward [est].
- Code: M_WAVE/M_BANKAIR, bank ~35–40°, crest −3.2 felt.

### Overbanked turns — REMOVED from generation (user: roll overload)
- Reference kept for the record: **Millennium Force**, Cedar Point, 2000, Intamin: three **122°** overbanks at 52/30/21 m crests, entered up to ~150 km/h, ride max 4.5 g [official]. WINGOVER's init/step code remains for `--gtest`.

### Helix
- **Goliath**, Six Flags Magic Mountain, 2000, Giovanola: **585° descending helix, >4.5 g sustained ~6 s** [official/press] — the definitive sustained-g anchor.
- **Mindbender**, Galaxyland, 1985, Schwarzkopf (closed 2023): 5.5–5.6 g measured 1987 (in the loop) [measured].
- Code: `initHelix` coils 1.3–1.8 rev (≈470–650°, ~6–8 s) — was 2–3 rev/11–13 s, cut per user; sustained measured ~7.5 felt ≈ 1.7x Goliath; once-per-lap cap (a helix is a finale, not a recurring element).

### Top hat towers
- **Top Thrill 2** (above): 130 m, launches to 190 km/h; legacy Dragster 0–190 in 3.8 s ≈ 1.4 g [official].
- **Red Force**, Ferrari Land, 2017, Intamin: 112 m, 0–180 km/h in 5 s ≈ 1.35 g [official].
- **Superman: Escape from Krypton**, SFMM, 1997 (closed Mar 2025): 126 m spike, **6.5 s weightless** at apex [official] — the airtime-duration anchor for vertical spikes.
- Code: once-per-lap mega hat (see ride-level table); crest crown carved at −2.5 felt by the CLIMB crest-lead.

### First-drop pullout (gigas) — why the game's pullout is height-proportional
- **Intimidator 305**, Kings Dominion, 2010, Intamin: 91 m/85° drop at ~145 km/h; original pullout+turn **>5 g sustained → rider gray-outs**; fixed in 2011 by **widening the radius**, not slowing the train [official park statement].
- **Leviathan**, Canada's Wonderland, 2012, B&M: 93.3 m/80°, 148 km/h, ~4.5 g max [official]. **Fury 325**: pullout visibly longer/shallower than I305's [est].
- Pullout arc ≈ bottom **~1/3 of the drop height** on modern gigas [est, industry-observed].
- Code: continuous `dy ∝ remaining height` schedule + curvature budget = the same shape; DOUBLE-DOWN variant (El Toro/Maverick two-stage drop) added as a roll-free thrill.

### Heartline/barrel roll — REMOVED from generation (near-duplicate of the stall)
- Reference: **Colossus**, Thorpe Park, 2002: quadruple heartline finale ~3 m up, taken slow (~30–40 km/h), roll rate ~150–240°/s [official layout, est rate].

### Track pacing / transitions (the "no staircase" rule)
- **El Toro** (2006, Intamin prefab), **Steel Vengeance**, **VelociCoaster**: **no flat straights between elements** — every transition is itself a small force event (pops, banked dips). Flat, level track exists only at block sections (station, lift, launch, MCBR, brakes), which total ~25–40% of a real layout.
- The industry method is **Force Vector Design** (Stengel practice; tools: Newton2, openFVD, KexEdit): prescribe g_vert(t), g_lat(t), roll rate(t) and integrate the centerline — transitions are linear ramps in *force space* (clothoid = linear curvature ramp). ASTM F2291 measures onset over a 100 ms window; ~15 g/s is the transition guideline.
- Code: the g-budget engine (directional curvature limits + ~30 g/s jerk budget = 2x guideline) approximates FVD; connective FLAT/TURN track carries a ~245 m-wavelength ±1 g swell; drops flow directly into elements (no dead shelf); powered flats taper in like a real LSM entry instead of snapping level.


## Section durations — matched toward the longer / WR side

Real transit times per element/section, and where the game sits (deliberately at or a
little past the record end, per design). Game figures at typical ride speeds.

| Section | Real-world (WR side) | In-game | Knob |
|---|---|---|---|
| Full circuit (station to station) | Falcon's Flight **3:25–3:35** over 4,250 m [official]; The Beast **4:10** (all-time longest) [official] | ~3.5–4 min (station trigger 205 s + wait for a low flat spot) | `sinceStation > 205` (main.cpp) |
| Main launch | Formula Rossa **4.9 s / ~163 m** [official]; Red Force **5.0 s** [official]; TT2 3.8 s [official] | ~3–4 s / 126–168 m from a rolling start | `startLaunch remain irnd(9,12)` |
| Mid-course LSM boost | Maverick 122 m [official], Taron second launch 118 m [official]; Falcon's Flight runs 3 long segments incl. an inclined lift [official] | ~1.5–2.5 s / 84–140 m, ~45% inclined +4–8° | `startBoost remain irnd(6,10)`, `boostGrade` |
| Mid-course brake run | typical transit ~3–6 s | ~2–3 s / 126–196 m, dead flat (real MCBRs are) | mcbr `remain irnd(9,14)` |
| Top hat (climb–crest–drop) | TT2/Kingda Ka tower transit ~8–12 s [est from POV] | ~10–15 s (160–198 m structure) | physics-driven |
| Airtime hill (per hump) | Fury 325's 34 m hill ~2 s at 150 km/h [derived]; record-class 50–60 m humps ~2.5–3 s | ~4–6 s per hump (1.25x-record heights at 2x speed stretch the arc) — the "longer side" by design | `hillLenFor` crest-g sizing |
| Vertical loop transit | Full Throttle ~3–5 s [est from POV] | ~4–6 s (1.25–1.45x-record size) | `stepLoop lsteps` |
| Zero-g stall hang | Wildfire ~2–2.5 s, **ArieForce One ~4.5 s (record)** [est/press] | **2.5–4.5 s** (capped at the record) | `initStall stallLen ≤16` |
| Helix | **Goliath SFMM 585° held ~6 s (record)** [official/press] | ~6–8 s, 470–650°, once per lap | `initHelix coils 1.3–1.8` |
| Inversion cluster / arc | real launch coasters run 1–3 energy arcs per circuit | ~2.5 arcs/lap, signatures at each arc's bleed end | `pickFromPool arcT` |

## Known gaps (genuinely unpublished — not research shortfalls)
- Turn/helix/crest radii: never published by manufacturers; back-solved from speed+g.
- "Tallest" records for cobra roll / zero-g roll / corkscrew / heartline: untracked by RCDB/Guinness.
- Fury 325 pullout g, Zadra airtime g, post-2011 I305 g: not published.
- Tormenta Rampaging Run's loop/Immelmann records: pending its (delayed) opening.
