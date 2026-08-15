class_name RideFidelityCounterparts
extends RefCounted

## Per-element counterpart bands: measured real-ride values from the committed telemetry
## documents, paired with the design target obtained by applying the per-axis envelope stretch
## to FORCE VALUES ONLY. Measured hold durations are carried through unchanged and geometry is
## never scaled. Human-readable derivation: docs/evidence/fidelity/counterpart-bands.md.
##
## This is DESIGN GROUNDING data. It promotes no source to `executable`, creates no catalog
## targets or selectors, and is deliberately not wired into fidelity.gd, verify.gd or smoke.gd.
## Nothing here is a gate.
##
## Axis stretch factors (root CLAUDE.md, final paragraph). There is NO Gx+ multiplier and none
## may be inferred: accelerating longitudinal targets are the measured values, unstretched.
const STRETCH_GZ_POSITIVE := 1.333
const STRETCH_GZ_NEGATIVE := 1.5
const STRETCH_GY := 1.567
const STRETCH_GX_NEGATIVE := 1.71
const STRETCH_NONE := 1.0

const DERIVED_ON := "2026-08-15"

const TELEMETRY_FALCON := "docs/TELEMETRY.md lines 52-176 (section 1.1)"
const TELEMETRY_TORMENTA := "docs/TELEMETRY.md lines 347-423 (section 1.2)"
const TELEMETRY_SOURCE_2 := "docs/TELEMETRY.md lines 822-943 (source 2, CoasterTalk Insta360)"
const TELEMETRY_I305 := "docs/TELEMETRY-I305.md lines 36-141"

## Caveats that apply to every row drawn from the named source.
const STANDING_CAVEATS := {
	"rideforcesdb.falcon.4804": [
		"RideForcesDB flags this recording unreliable; it is the sole recording of the ride (docs/TELEMETRY.md lines 67-71).",
		"Wrist-worn Apple Watch, Row 7 L seat; raw plus/minus 5-10 g extremes cluster at t 99.3-100.3 s and are shock artefacts (docs/TELEMETRY.md lines 61, 74-76).",
		"Source 2 measures the same ride's longitudinal peak at +0.87/+0.91 g against this recording's +2.53 g (docs/TELEMETRY.md lines 912-916, 931-943).",
	],
	"rideforcesdb.tormenta.6369+6383": [
		"Neither recording carries a gravity/angle channel; element identity comes from RCDB order matched to trace shape (docs/TELEMETRY.md lines 373-376).",
		"6369 is a pocket-carried phone the author flags for sliding; 6383 is an iPhone, Row 2 Seat 8.",
		"Durations and magnitudes are comparable across the pair; absolute t is not.",
		"Seat position alone moves the peak by up to 0.7 g on the same element (docs/TELEMETRY.md line 395).",
	],
	"youtube.i305": [
		"Values read from a video overlay to plus/minus 0.15 g and 0.15 s; quoted peaks are the local mean of a plus/minus 0.2 g noise band (docs/TELEMETRY-I305.md lines 22-30).",
		"The g data and the imagery come from different sources, so element-to-time attribution is the uploader's sync; element labels are good-confidence, not certified.",
		"The overlay carries one signed vertical trace only: no lateral and no longitudinal channel (docs/TELEMETRY-I305.md lines 12-14).",
	],
	"youtube.coastertalk.falcon": [
		"Camera-IMU derived from an edited review video, two runs (front row and back row); absolute ride timeline cannot be reconstructed (docs/TELEMETRY.md lines 830-851).",
	],
}

const BANDS := {
	"station-launch": {
		"counterpart": {
			"ride": "Do-Dodonpa (propulsion) and Falcon's Flight (layout)",
			"element": "S&S compressed-air launch, RFDB 4721; Falcon's Flight LSM launch 1 and opener coast",
			"telemetry_anchor": "docs/TELEMETRY.md lines 742-751, 793, 816; lines 104-105",
		},
		"axes": [
			{
				"axis": "gx_positive", "label": "launch acceleration (Do-Dodonpa)",
				"measured": 3.17, "stretch": STRETCH_NONE, "target": 3.17,
				"hold_s": 1.9, "threshold_g": 0.6,
				"note": "G >= 0.6 g sustained t=2.0-3.9 s, peaking +3.17 g (line 745). No Gx+ multiplier exists.",
			},
			{
				"axis": "gx_positive", "label": "launch acceleration, cross-recording spread",
				"measured": [3.17, 3.77], "stretch": STRETCH_NONE, "target": [3.17, 3.77],
				"note": "Highest launch longitudinal in the whole database, across all 5 recordings (lines 746-747, 793).",
			},
			{
				"axis": "gx_positive", "label": "opener launch (Falcon), shape reference",
				"measured": 0.96, "stretch": STRETCH_NONE, "target": 0.96,
				"note": "Range +0.55 to +0.96 g (line 104); corroborated by Source 2 narration 'peak acceleration of 0.9 G' (line 900).",
			},
			{
				"axis": "gz_positive", "label": "pull-up out of the launch",
				"measured": 1.98, "stretch": STRETCH_GZ_POSITIVE, "target": 2.64,
				"note": "V 1.98 g at t approx 5 s (line 104).",
			},
			{
				"axis": "gz_level", "label": "unpowered coast over the opener crest",
				"measured": 0.93, "stretch": STRETCH_NONE, "target": 0.93,
				"hold_s": 7.5,
				"note": "Mean 0.93 g, range 0.82-1.04, with Gx +0.10 to +0.55 sustained: V=cos21deg, G=sin21deg, a near-constant-speed 20 degree grade (line 105). A ~1 g cruise is the gravity baseline and is not stretched.",
			},
		],
		"caveats": [
			"The design's ~4 g entry launch exceeds every measured launch; Do-Dodonpa at 3.17-3.77 g is the honest ceiling of measurement and the design extrapolates past it.",
			"Do-Dodonpa produces essentially no airtime: flojector and ejector both 0.00 s in all five recordings (docs/TELEMETRY.md lines 748-749).",
			"Falcon's own opener launch grounds the shape (short kick then sustained boost into a climb, line 901), not the magnitude.",
		],
	},
	"opener-twisted-drop": {
		"counterpart": {
			"ride": "Falcon's Flight",
			"element": "first drop - twisted side-drop, t 16.30-17.38 s, with pullout t 17.88-19.84 s",
			"telemetry_anchor": "docs/TELEMETRY.md lines 107-108, 168",
		},
		"axes": [
			{
				"axis": "gz_negative", "label": "drop unloading",
				"measured": -0.99, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.49,
				"hold_s": [1.10, 0.80], "threshold_g": [0.0, -0.5],
				"note": "1.10 s below 0 g and 0.80 s at or below -0.5 g: the ride's longest ejector-class hold (lines 107, 168).",
			},
			{
				"axis": "gy", "label": "lateral peak, first side",
				"measured": 1.64, "stretch": STRETCH_GY, "target": 2.57,
				"note": "Peak at t 16.94-17.16 s; strongest lateral of the whole recording.",
			},
			{
				"axis": "gy", "label": "lateral reversal, other side",
				"measured": -1.35, "stretch": STRETCH_GY, "target": -2.12,
				"hold_s": 0.5,
				"note": "Full reversal from +1.64 to -1.35 g in 0.50 s (line 107). The 0.50 s reversal time is the more robust quantity than either magnitude.",
			},
			{
				"axis": "gz_positive", "label": "first-drop pullout",
				"measured": 3.35, "stretch": STRETCH_GZ_POSITIVE, "target": 4.47,
				"hold_s": [1.98, 0.34], "threshold_g": [2.0, 3.0],
				"note": "Range 2.00-3.35 g (line 108). Thresholds are the measured ones; the stretched analogue of the 3 g threshold is 4.00 g.",
			},
			{
				"axis": "gx_negative", "label": "longitudinal during the drop",
				"measured": -0.76, "stretch": STRETCH_GX_NEGATIVE, "target": -1.30,
				"note": "Range -0.76 to +1.09 g (line 107).",
			},
		],
		"caveats": [
			"Source 2 measures Falcon's whole-ride lateral envelope at only -0.79 to +0.66 g, less than half the 4804 figure (docs/TELEMETRY.md lines 895, 919, 938).",
			"A wrist device that rotates mid-ride smears energy between axes (docs/TELEMETRY.md line 44), so treat +1.64/-1.35 g as an upper reading.",
			"The two sources agree closely on minimum vertical, -0.96 to -1.15 g (docs/TELEMETRY.md line 941).",
			"Angle sweeps 30 to 84 degrees: the drop is taken nearly on the side. Geometry is context, never scaled.",
		],
	},
	"opener-teardrop": {
		"counterpart": {
			"ride": "Falcon's Flight, with Intimidator 305 as class exemplar",
			"element": "near-90 degree banked wall turn, t 113.0-119.0 s; I305 sustained banked turns",
			"telemetry_anchor": "docs/TELEMETRY.md line 130; docs/TELEMETRY-I305.md lines 46, 51, 55, 117-122",
		},
		"axes": [
			{
				"axis": "gz_positive", "label": "held plateau (Falcon wall turn)",
				"measured": 2.95, "stretch": STRETCH_GZ_POSITIVE, "target": 3.93,
				"hold_s": 2.58, "threshold_g": 2.0,
				"note": "Range 2.10-2.95 g; hold at t 116.12-118.68 s. Steepest bank of that ride, 89-90 degrees.",
			},
			{
				"axis": "gy", "label": "lateral (Falcon wall turn)",
				"measured": [-0.80, 0.97], "stretch": STRETCH_GY, "target": [-1.25, 1.52],
			},
			{
				"axis": "gx_negative", "label": "longitudinal (Falcon wall turn)",
				"measured": -1.04, "stretch": STRETCH_GX_NEGATIVE, "target": -1.78,
			},
			{
				"axis": "gz_positive", "label": "held plateau (I305 turn #3, the outlier)",
				"measured": 4.80, "stretch": STRETCH_GZ_POSITIVE, "target": 6.40,
				"hold_s": 4.1, "threshold_g": 3.5,
				"note": "Never drops below 3.7 g inside the 4.1 s hold, and the load rises through the hold rather than decaying (docs/TELEMETRY-I305.md lines 46, 120).",
			},
			{
				"axis": "gz_positive", "label": "held plateau (I305 turns #6/#8/#12)",
				"measured": [4.30, 4.30, 4.25], "stretch": STRETCH_GZ_POSITIVE, "target": [5.73, 5.73, 5.67],
				"hold_s": [1.4, 3.1, 2.4], "threshold_g": 3.5,
				"note": "Flat-topped 4.0-4.3 g plateaus with plus/minus 0.2 g of chassis noise.",
			},
		],
		"caveats": [
			"Falcon's wall turn is the geometric analogue (an overbank) but a low-g one at 2.1-2.95 g; I305's sustained turns are the high-g analogue at 3.5-4.8 g. Both bands are recorded rather than averaged.",
			"I305's four sustained turns account for 11 of the 12.3 s that ride spends above 3.5 g (docs/TELEMETRY-I305.md lines 117-122).",
		],
	},
	"opener-release": {
		"counterpart": {
			"ride": "Falcon's Flight",
			"element": "airtime hills 1, 3 and 4 with the following valley",
			"telemetry_anchor": "docs/TELEMETRY.md lines 109, 113, 117, 118",
		},
		"axes": [
			{
				"axis": "gz_negative", "label": "airtime hill 4, deepest",
				"measured": -0.73, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.10,
				"hold_s": [0.52, 0.22], "threshold_g": [0.0, -0.5],
				"note": "Taken at 66-88 degrees of bank while unloaded (line 117).",
			},
			{
				"axis": "gz_negative", "label": "airtime hill 1",
				"measured": -0.58, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.87,
				"hold_s": 1.06, "threshold_g": 0.0,
			},
			{
				"axis": "gz_negative", "label": "airtime hill 3, longest",
				"measured": -0.57, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.86,
				"hold_s": 1.30, "threshold_g": 0.0,
				"note": "Taken at 75-86 degrees of bank while unloaded (line 113).",
			},
			{
				"axis": "gz_positive", "label": "following valley (valley 6)",
				"measured": 2.84, "stretch": STRETCH_GZ_POSITIVE, "target": 3.79,
				"hold_s": 1.36, "threshold_g": 2.0,
				"note": "Range 2.01-2.84 g (line 118).",
			},
		],
		"caveats": [
			"Amplitude and duration trade against each other: the deepest hill is the shortest below zero and the longest is the shallowest.",
			"Falcon's whole-ride ejector time is only 0.38 s (docs/TELEMETRY.md line 92); this ride class is floater/flojector dominant.",
		],
	},
	"act-one-immelmann": {
		"counterpart": {
			"ride": "Tormenta: Rampaging Run (recordings 6383 and 6369)",
			"element": "Immelmann #1 (218 ft), with Immelmann #2 as secondary",
			"telemetry_anchor": "docs/TELEMETRY.md lines 397, 403",
		},
		"axes": [
			{
				"axis": "gz_positive", "label": "Immelmann #1 peak (6383 / 6369)",
				"measured": [4.34, 4.43], "stretch": STRETCH_GZ_POSITIVE, "target": [5.79, 5.91],
				"note": "Strongest cross-recording agreement of the whole ride: peak within 0.09 g.",
			},
			{
				"axis": "gz_positive", "label": "Immelmann #1 held at or above 3 g",
				"measured": 3.0, "stretch": STRETCH_GZ_POSITIVE, "target": 4.0,
				"hold_s": [2.70, 2.52], "threshold_g": 3.0,
				"note": "Target is the stretched analogue of the measured 3 g threshold, given for reading convenience; the measured threshold is 3 g.",
			},
			{
				"axis": "gz_positive", "label": "Immelmann #1 held at or above 2 g",
				"measured": 2.0, "stretch": STRETCH_GZ_POSITIVE, "target": 2.67,
				"hold_s": [3.58, 3.56], "threshold_g": 2.0,
				"note": "Durations agree across recordings to 0.02 s.",
			},
			{
				"axis": "gz_positive", "label": "Immelmann #2 peak (6383 / 6369)",
				"measured": [4.14, 4.22], "stretch": STRETCH_GZ_POSITIVE, "target": [5.52, 5.63],
				"hold_s": [1.24, 1.14], "threshold_g": 3.0,
				"note": "Also 2.24 / 1.90 s at or above 2 g (line 403).",
			},
		],
		"caveats": [
			"The peak spread between the two recordings is the seat-position effect; the durations are the transferable numbers.",
			"Tormenta reaches these values at 140 km/h on a 94 m dive coaster. The g band transfers; the geometry does not, and is never scaled.",
			"Immelmann #2 is assigned by RCDB order (Immelmann before Cutback), an assignment rather than a direct observation (line 403).",
		],
	},
	"act-one-cutback": {
		"counterpart": {
			"ride": "Tormenta: Rampaging Run (recordings 6383 and 6369)",
			"element": "Cutback, 6383 t 54.50-56.24 s / 6369 t 56.34-58.02 s",
			"telemetry_anchor": "docs/TELEMETRY.md line 404",
		},
		"axes": [
			{
				"axis": "gz_positive", "label": "cutback peak (6383 / 6369)",
				"measured": [4.20, 3.86], "stretch": STRETCH_GZ_POSITIVE, "target": [5.60, 5.15],
				"note": "Peaks differ by 0.34 g; the band is reported rather than a single value.",
			},
			{
				"axis": "gz_positive", "label": "held at or above 3 g",
				"measured": 3.0, "stretch": STRETCH_GZ_POSITIVE, "target": 4.0,
				"hold_s": [0.96, 0.98], "threshold_g": 3.0,
				"note": "The agreement is here, not in the peak: 0.02 s apart.",
			},
			{
				"axis": "gz_positive", "label": "held at or above 2 g",
				"measured": 2.0, "stretch": STRETCH_GZ_POSITIVE, "target": 2.67,
				"hold_s": [1.76, 1.70], "threshold_g": 2.0,
			},
		],
		"caveats": [
			"Shortest of Tormenta's big elements: a cutback is a brief high-g snap and must not grow into an Immelmann-length hold.",
			"The repo's own measured constraint, cutback entry pitch at most about 22 degrees, is a geometry finding and is not stretched.",
		],
	},
	"act-one-loop": {
		"counterpart": {
			"ride": "Tormenta: Rampaging Run (recordings 6383 and 6369); Full Throttle as contrast",
			"element": "Loop (179 ft), twin-lobe with loaded apex; Full Throttle giant loop with unloaded apex",
			"telemetry_anchor": "docs/TELEMETRY.md line 398; lines 679-681, 695-696",
		},
		"axes": [
			{
				"axis": "gz_positive", "label": "entry lobe peak (6383 / 6369)",
				"measured": [3.84, 3.86], "stretch": STRETCH_GZ_POSITIVE, "target": [5.12, 5.15],
				"hold_s": 1.22, "threshold_g": 3.0,
				"note": "Peak agreement of 0.02 g: the tightest pair in the whole document.",
			},
			{
				"axis": "gz_positive", "label": "apex dip, a local MINIMUM that never unloads",
				"measured": [2.50, 2.52], "stretch": STRETCH_GZ_POSITIVE, "target": [3.33, 3.36],
				"note": "6383 t=25 s min 2.52 g. The twin-lobe signature is the point: entry 3.84 -> apex 2.5 -> exit 3.74 g.",
			},
			{
				"axis": "gz_positive", "label": "exit lobe peak",
				"measured": 3.74, "stretch": STRETCH_GZ_POSITIVE, "target": 4.99,
				"hold_s": 1.26, "threshold_g": 3.0,
			},
			{
				"axis": "gz_positive", "label": "whole loop held at or above 2 g",
				"measured": 2.0, "stretch": STRETCH_GZ_POSITIVE, "target": 2.67,
				"hold_s": [4.66, 5.04], "threshold_g": 2.0,
			},
			{
				"axis": "gz_negative", "label": "CONTRAST ONLY - Full Throttle unloaded apex, inverted",
				"measured": -0.67, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.01,
				"hold_s": [2.62, 1.22], "threshold_g": [0.0, -0.5],
				"note": "Apex range -0.40 to -0.67 g with a confirmed angle channel reaching 166.9 degrees. Recorded as the opposite case, not as a target.",
			},
		],
		"caveats": [
			"The design's loop is a helical lateral with the sign reversed at the top, because a planar loop self-intersects at these speeds. That places it in Tormenta's loaded-apex family rather than Full Throttle's, but both bands are recorded so the choice stays explicit.",
			"Neither Tormenta recording has an angle channel, so inversion state is inferred from RCDB order.",
		],
	},
	"act-one-airtime": {
		"counterpart": {
			"ride": "Intimidator 305 (ejector reference) and Falcon's Flight (floater reference)",
			"element": "I305 ejector hills #1/#2/#3; Falcon airtime hills, sustained float and valleys",
			"telemetry_anchor": "docs/TELEMETRY-I305.md lines 48, 50, 56, 124-129; docs/TELEMETRY.md lines 109-119",
		},
		"axes": [
			{
				"axis": "gz_negative", "label": "I305 ejector hill #1, deepest",
				"measured": -1.15, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.73,
				"hold_s": [2.40, 1.5], "threshold_g": [0.0, -0.7],
			},
			{
				"axis": "gz_negative", "label": "I305 ejector hill #2",
				"measured": -0.90, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.35,
				"hold_s": 1.33, "threshold_g": 0.0,
			},
			{
				"axis": "gz_negative", "label": "I305 ejector hill #3, longest float",
				"measured": -0.75, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.13,
				"hold_s": [2.30, 2.60], "threshold_g": [0.0, 0.5],
			},
			{
				"axis": "gz_negative", "label": "Falcon deepest mid-course hill",
				"measured": -0.73, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.10,
				"hold_s": [0.52, 0.22], "threshold_g": [0.0, -0.5],
			},
			{
				"axis": "gz_level", "label": "Falcon sustained float",
				"measured": 0.05, "stretch": STRETCH_NONE, "target": 0.05,
				"hold_s": 1.0, "threshold_g": 0.22,
				"note": "Range 0.05-0.44 g, mean about 0.05 g at t=35 s; about 1.0 s continuously at or below 0.22 g (line 115). Near-zero, not negative: not stretched.",
			},
			{
				"axis": "gz_positive", "label": "Falcon valleys between the hills",
				"measured": [2.68, 2.84], "stretch": STRETCH_GZ_POSITIVE, "target": [3.57, 3.79],
				"hold_s": [1.30, 1.42], "threshold_g": 2.0,
			},
		],
		"caveats": [
			"Two different airtime characters are on record. I305 is the ejector reference: four of six hills hold below -0.35 g for over a second and the first two hold below -0.7 g for about 1.5 s each. Falcon is the floater reference: 23.00 s total airtime but only 0.38 s of ejector.",
			"I305 onset: sharpest unloading +3.8 to -0.9 g in 0.80 s (5.9 g/s), and nothing in that recording exceeds about 7 g/s (docs/TELEMETRY-I305.md lines 132-141). A character reference, well under the design's 25 g/s ceiling, not a limit.",
		],
	},
	"act-one-wave": {
		"evidence_gap": true,
		"reason": "No wave turn - a laterally-banked twin-peak airtime element - is identified in any committed source. Falcon's 'upper-cliff turns/hills' (docs/TELEMETRY.md line 122) is an unresolved multi-element block in the source's own assignment, and its -1.13 g lateral is held only 2x0.22 s and cannot be attributed to a single element. Tormenta's post-loop turn (line 399) carries that ride's lateral maximum but is a plain 2 s banked turn at 1.18-1.97 g with no airtime component; that ride has zero ejector airtime in both recordings (line 387). I305's final low twisted turn has no lateral channel at all (docs/TELEMETRY-I305.md lines 12-14). No number is assigned.",
		"bounding_reference_only": "The highest attributable lateral anywhere in the primary sources is Falcon's first drop at +1.64 g (line 107, itself contested by Source 2) and Tormenta's +1.15 g (line 399). Bounding context, explicitly not a target.",
		"closes_with": "A recording of an actual wave turn carrying a lateral channel.",
	},
	"climb-lsm2": {
		"counterpart": {
			"ride": "Falcon's Flight, with the database LSM class band and Pantheon as corroboration",
			"element": "LSM launch 2 at t 44.5-48.5 s and the escarpment climb at t 48.5-56.0 s",
			"telemetry_anchor": "docs/TELEMETRY.md lines 120-121, 816, 735-737",
		},
		"axes": [
			{
				"axis": "gx_positive", "label": "boost peak (4804)",
				"measured": 1.78, "stretch": STRETCH_NONE, "target": 1.78,
				"hold_s": [0.30, 0.40], "threshold_g": 0.8,
				"note": "Range +0.53 to +1.78 g, peak at t 48.0-48.4 s. Outside the t 99-100 s artefact burst. No Gx+ multiplier exists.",
			},
			{
				"axis": "gx_positive", "label": "LSM class band across the database",
				"measured": [0.75, 1.57], "stretch": STRETCH_NONE, "target": [0.75, 1.57],
				"note": "Against 1.37-2.73 g hydraulic and 3.17-3.77 g compressed air (line 816). The more defensible design reference.",
			},
			{
				"axis": "gx_positive", "label": "Pantheon LSM boosts",
				"measured": [0.9, 1.3], "stretch": STRETCH_NONE, "target": [0.9, 1.3],
				"hold_s": [0.3, 1.5], "threshold_g": 0.6,
				"note": "Every LSM boost on that ride is 0.3-1.5 s long and peaks between 0.9 and 1.3 g (line 737). Closest structural analogue to a three-booster layout.",
			},
			{
				"axis": "gz_positive", "label": "pull-up into the climb",
				"measured": 2.96, "stretch": STRETCH_GZ_POSITIVE, "target": 3.95,
				"note": "At t 47.64-48.02 s (line 120).",
			},
			{
				"axis": "gz_positive", "label": "escarpment climb peak",
				"measured": 2.13, "stretch": STRETCH_GZ_POSITIVE, "target": 2.84,
				"hold_s": 7.5,
				"note": "Range 0.57-2.13 g over a sustained ~30 degree grade (line 121).",
			},
			{
				"axis": "gx_negative", "label": "longitudinal on the climb",
				"measured": -0.34, "stretch": STRETCH_GX_NEGATIVE, "target": -0.58,
			},
		],
		"caveats": [
			"Source 2 puts the whole ride's longitudinal maximum at +0.87/+0.91 g, which would make even +1.78 g high (docs/TELEMETRY.md lines 912-916).",
			"The escarpment climb confirms a booster may run into a sustained grade rather than staying flat (line 121), which the design relies on.",
			"Pantheon's measured 0.3-1.5 s boost lengths give direct support to the design's 'shorter than Falcon's booster sections' constraint.",
		],
	},
	"clifftop-slow-crest": {
		"counterpart": {
			"ride": "Falcon's Flight",
			"element": "clifftop crest crawl / slow beat, t 78.0-90.3 s",
			"telemetry_anchor": "docs/TELEMETRY.md lines 123, 169",
		},
		"axes": [
			{
				"axis": "gz_level", "label": "level hold",
				"measured": [0.98, 1.00], "stretch": STRETCH_NONE, "target": [0.98, 1.00],
				"hold_s": 12.0,
				"note": "The ride's longest ~1 g level hold (line 169). Not stretched: 1 g is the gravity baseline of a level crawl, not a load excursion.",
			},
			{
				"axis": "gy", "label": "lateral, laterally dead",
				"measured": 0.15, "stretch": STRETCH_GY, "target": 0.24,
				"hold_s": 12.0,
				"note": "Measured about 0.00 g with a plus/minus 0.15 g bound over the full section.",
			},
			{
				"axis": "gx_negative", "label": "gentle deceleration, deepest",
				"measured": -0.95, "stretch": STRETCH_GX_NEGATIVE, "target": -1.62,
				"note": "At t 82-83 s; a shallower -0.28 to -0.43 g at t 88-90 s (targets -0.48 to -0.74 g).",
			},
		],
		"caveats": [
			"The most directly transferable row in the table: the design's one deliberate slow beat has an exact measured counterpart in the same ride and the same structural position.",
			"Angle 1-15 degrees. Geometry is context, never scaled.",
			"I305 has no dwell at 1 g anywhere between lift crest and brakes (docs/TELEMETRY-I305.md lines 95-99): the slow beat is a Falcon trait, not a universal one.",
		],
	},
	"clifftop-outward-rim": {
		"evidence_gap": true,
		"reason": "No element in either telemetry document is identified as outward-banked, and the sign convention blocks inference: lateral positive is 'one side (recording-dependent)' (docs/TELEMETRY.md line 14), so an outward bank cannot be distinguished from an inward one without a gravity/angle channel plus a known turn direction - a combination no source here provides. Falcon's clifftop section, where the design places this element, is measured laterally dead at about 0.00 g plus/minus 0.15 over the full 12 s (line 123): there is no rim turn in the measured trace at all. No number is assigned.",
		"closes_with": "A recording of an outward-banked turn with an angle channel and documented turn direction.",
	},
	"outward-dive": {
		"counterpart": {
			"ride": "Falcon's Flight and Source 2 (same ride), with Yukon Striker (90 deg) and Tormenta (95 deg) as class exemplars",
			"element": "cliff-dive entry/free-fall t 90.5-92.7 s and pullout t 93.0-96.0 s; Yukon Striker dive drop; Tormenta 95 degree drop",
			"telemetry_anchor": "docs/TELEMETRY.md lines 124-125, 882-883, 923-925, 764-773, 394-395",
		},
		"axes": [
			{
				"axis": "gz_negative", "label": "dive entry (4804)",
				"measured": -0.52, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.78,
				"hold_s": 1.14, "threshold_g": 0.0,
				"note": "At t 91.56-92.68 s. Combined vector minimum 0.043 g at t 91.36 s: near-total free-fall.",
			},
			{
				"axis": "gz_level", "label": "on the face (Source 2, front / back run)",
				"measured": [0.17, -0.05], "stretch": STRETCH_NONE, "target": [0.17, -0.05],
				"note": "Source 2 states explicitly that this is an unloading event, not a negative-g event (line 925).",
			},
			{
				"axis": "gx_negative", "label": "on the face, nose-down (Source 2, front)",
				"measured": -0.82, "stretch": STRETCH_GX_NEGATIVE, "target": -1.40,
			},
			{
				"axis": "gz_negative", "label": "Yukon Striker 90 degree drop",
				"measured": -0.24, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.36,
				"hold_s": 1.10, "threshold_g": 0.0,
				"note": "A 90 degree dive drop produces no meaningful airtime, only unloading to about 0 (line 770).",
			},
			{
				"axis": "gz_negative", "label": "Tormenta 95 degree drop (6383 / 6369)",
				"measured": [-0.52, -0.66], "stretch": STRETCH_GZ_NEGATIVE, "target": [-0.78, -0.99],
				"hold_s": [1.80, 1.88], "threshold_g": 0.0,
				"note": "Durations agree within 0.08 s; 6369 additionally holds at or below -0.5 g for 0.18+0.22 s.",
			},
			{
				"axis": "gz_positive", "label": "pullout (4804)",
				"measured": 2.99, "stretch": STRETCH_GZ_POSITIVE, "target": 3.99,
				"hold_s": 1.58, "threshold_g": 2.0,
				"note": "Range 2.04-2.99 g at t 93.74-95.30 s.",
			},
			{
				"axis": "gz_positive", "label": "pullout (Yukon Striker)",
				"measured": 3.91, "stretch": STRETCH_GZ_POSITIVE, "target": 5.21,
				"hold_s": 3.0, "threshold_g": 3.0,
			},
			{
				"axis": "gz_positive", "label": "pullout (Tormenta 6383 / 6369)",
				"measured": [4.33, 5.02], "stretch": STRETCH_GZ_POSITIVE, "target": [5.77, 6.69],
				"hold_s": [2.80, 2.82], "threshold_g": 3.0,
				"note": "Also 3.74 / 3.62 s at or above 2 g and 0.36 / 0.50 s at or above 4 g. The 0.02 s duration agreement against a 0.7 g peak difference makes duration the transferable number.",
			},
			{
				"axis": "gx_negative", "label": "CONTEXT ONLY - Yukon Striker holding brake before the drop",
				"measured": [-0.60, -0.81], "stretch": STRETCH_GX_NEGATIVE, "target": [-1.03, -1.39],
				"hold_s": 4.1,
				"note": "The measured precedent for a controlled crest hold before a vertical face. The design permits no mid-course brake, so this is context only.",
			},
		],
		"caveats": [
			"The most important measured finding is negative: a 90 degree dive drop produces no meaningful airtime. Three independent sources agree.",
			"The violence is in the pullout, not the drop.",
			"The 4804 dive rows are outside the t 99-100 s artefact burst.",
		],
	},
	"tunnel-lsm3": {
		"counterpart": {
			"ride": "Falcon's Flight, with Source 2, the LSM class band and Pantheon as corroboration",
			"element": "LSM launch 3 (tunnel), t 96.5-99.7 s",
			"telemetry_anchor": "docs/TELEMETRY.md line 126; lines 912-916, 816, 735-737",
		},
		"axes": [
			{
				"axis": "gx_positive", "label": "SUSPECT - NOT ADOPTED - boost peak (4804)",
				"measured": 2.53, "stretch": STRETCH_NONE, "target": null,
				"hold_s": [0.32, 0.32, 0.30, 0.36],
				"note": "Range +1.02 to +2.53 g in four bursts. The peak sits at t=99.52 s, inside the plus/minus 5-10 g raw shock burst at t 99.3-100.3 s, and the source flags it as suspect on its own terms (lines 76, 79, 126). Deliberately not adopted as a target.",
			},
			{
				"axis": "gx_positive", "label": "corroborated whole-ride maximum (Source 2)",
				"measured": [0.87, 0.91], "stretch": STRETCH_NONE, "target": [0.87, 0.91],
				"note": "Corroborated by on-screen narration 'I measured a peak acceleration of 0.9 G' (line 900). The document's own conclusion: treat about 0.9 g as the ride's real launch longitudinal magnitude (line 916).",
			},
			{
				"axis": "gx_positive", "label": "LSM class band, the adopted reference",
				"measured": [0.75, 1.57], "stretch": STRETCH_NONE, "target": [0.75, 1.57],
				"hold_s": [0.3, 1.5], "threshold_g": 0.6,
				"note": "Hold band from Pantheon's measured boost lengths (line 737). No Gx+ multiplier exists.",
			},
			{
				"axis": "gz_positive", "label": "vertical through the boost",
				"measured": 1.67, "stretch": STRETCH_GZ_POSITIVE, "target": 2.23,
				"note": "Range 0.47-1.67 g rising.",
			},
		],
		"caveats": [
			"This is the worst-supported magnitude in the table and the 4804 figure is deliberately not adopted; the target comes from the class band.",
			"The burst STRUCTURE - four bursts of 0.30-0.36 s - is worth carrying from 4804, because burst timing is a shape and is not distorted by an amplitude artefact the way the magnitude is. It matches Pantheon's measured 0.3-1.5 s boost lengths.",
		],
	},
	"camelback": {
		"counterpart": {
			"ride": "Falcon's Flight, corroborated by Source 2, with Top Thrill 2 and Red Force top-hats as class exemplars",
			"element": "record camelback: pull-up t 99.02-102.32, crest t 102.90-109.66, exit pullout t 110.24-112.54 s",
			"telemetry_anchor": "docs/TELEMETRY.md lines 127-129, 166-167; lines 886, 903-904; lines 626-629, 650-654",
		},
		"axes": [
			{
				"axis": "gz_positive", "label": "SUSPECT WINDOW - pull-up peak (4804)",
				"measured": 3.894, "stretch": STRETCH_GZ_POSITIVE, "target": 5.19,
				"hold_s": [3.32, 1.10], "threshold_g": [2.0, 3.0],
				"note": "Peak at t 99.82 s, range 2.14-3.89 g; the 1.10 s hold at or above 3 g runs t 101.12-102.20 s and is the ride's longest. Inside the t 99-100 s artefact window; the vertical channel is the least affected of the three.",
			},
			{
				"axis": "gz_positive", "label": "pull-up peak (Source 2, back / front run)",
				"measured": [3.23, 3.65], "stretch": STRETCH_GZ_POSITIVE, "target": [4.31, 4.87],
				"note": "Independent instrument, same order of magnitude as 4804.",
			},
			{
				"axis": "gz_negative", "label": "crest, first negative pass",
				"measured": -0.87, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.31,
				"hold_s": 1.60, "threshold_g": 0.0,
			},
			{
				"axis": "gz_negative", "label": "crest, second negative pass",
				"measured": -0.61, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.92,
				"hold_s": 2.78, "threshold_g": 0.0,
				"note": "At t 106.90-109.66 s: the longest negative-g hold of the whole ride (line 167).",
			},
			{
				"axis": "gz_level", "label": "crest, continuously unloaded",
				"measured": 0.2, "stretch": STRETCH_NONE, "target": 0.2,
				"hold_s": 6.8, "threshold_g": 0.2,
				"note": "At or below 0.2 g essentially continuous from t 102.9 to 109.7 s: the longest unloaded stretch of the ride. Not in the artefact window.",
			},
			{
				"axis": "gz_negative", "label": "crest apex (Source 2)",
				"measured": -0.13, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.20,
				"note": "Narration on the same element: 'off to about 0.5 G at the top and ramps back up in the descent' (line 903).",
			},
			{
				"axis": "gy", "label": "SUSPECT WINDOW - lateral through the pull-up",
				"measured": [-1.16, 1.03], "stretch": STRETCH_GY, "target": [-1.82, 1.61],
				"note": "Inside the t 99-100 s artefact window; the document identifies lateral and longitudinal as the channels smeared by the wrist shock.",
			},
			{
				"axis": "gx_negative", "label": "SUSPECT WINDOW - longitudinal through the pull-up",
				"measured": -1.70, "stretch": STRETCH_GX_NEGATIVE, "target": -2.91,
				"note": "Range -1.70 to +1.81 g. Inside the artefact window.",
			},
			{
				"axis": "gz_positive", "label": "exit pullout",
				"measured": 3.44, "stretch": STRETCH_GZ_POSITIVE, "target": 4.59,
				"hold_s": [2.32, 0.38, 0.22, 0.18, 0.26], "threshold_g": [2.0, 3.0],
				"note": "Range 2.16-3.44 g; the 2.32 s hold is at or above 2 g, the four short holds are at or above 3 g.",
			},
			{
				"axis": "gz_negative", "label": "CLASS - Top Thrill 2 top-hat crest",
				"measured": -1.08, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.62,
				"hold_s": [2.94, 1.42], "threshold_g": [0.0, -0.5],
			},
			{
				"axis": "gz_negative", "label": "CLASS - Red Force top-hat descent airtime",
				"measured": -0.88, "stretch": STRETCH_GZ_NEGATIVE, "target": -1.32,
				"hold_s": [1.82, 1.04], "threshold_g": [0.0, -0.5],
			},
		],
		"caveats": [
			"The pull-up rows sit inside the t 99-100 s artefact burst; every row marked SUSPECT WINDOW carries that flag (docs/TELEMETRY.md lines 74-79).",
			"The document's onset maxima (V +14.5, L -14.6, G +22.1/-26.0 g/s) all fall inside this burst and are upper bounds, not clean measurements (lines 171-176).",
			"The crest is the strong part and is outside the burst, independently corroborated by Source 2 at -0.13 g at the apex (line 886).",
			"Source 2 reports greyout at the camelback base (line 904), consistent with a genuine high-g pull-up.",
		],
	},
	"return-turn-a": {
		"counterpart": {
			"ride": "Falcon's Flight",
			"element": "return-run turn A, t 124.16-127.02 s",
			"telemetry_anchor": "docs/TELEMETRY.md lines 132, 163",
		},
		"axes": [
			{
				"axis": "gz_positive", "label": "held plateau",
				"measured": 3.14, "stretch": STRETCH_GZ_POSITIVE, "target": 4.19,
				"hold_s": [2.88, 0.10], "threshold_g": [2.0, 3.0],
				"note": "Range 2.02-3.14 g. The second-longest at-or-above-2 g run of the recording (line 163). Only 0.10 s above 3 g against 2.88 s above 2 g: a long flat-topped ~2.5 g plateau with a brief tip, not a spike.",
			},
			{
				"axis": "gy", "label": "lateral",
				"measured": [-0.56, 0.99], "stretch": STRETCH_GY, "target": [-0.88, 1.55],
			},
			{
				"axis": "gx_negative", "label": "longitudinal",
				"measured": -0.91, "stretch": STRETCH_GX_NEGATIVE, "target": -1.56,
			},
		],
		"caveats": [
			"Clean row: outside the artefact burst, on the same ride, in the same structural position (a banked turn on the unpowered return run).",
			"Source 2's independent return-run readings (+2.68 g at video t=315 s, +0.08 g unloaded at t=320 s, lines 887-888) are consistent in magnitude.",
			"Angle 15-64 degrees. Geometry is context, never scaled.",
		],
	},
	"return-height-a": {
		"counterpart": {
			"ride": "Falcon's Flight, with Intimidator 305 late-course hills as class corroboration",
			"element": "return-run float, t 119.0-123.0 s; I305 ejector hills #15/#17/#19",
			"telemetry_anchor": "docs/TELEMETRY.md line 131; docs/TELEMETRY-I305.md lines 58, 60, 62, 124-129",
		},
		"axes": [
			{
				"axis": "gz_level", "label": "return-run float (Falcon)",
				"measured": [0.22, 0.79], "stretch": STRETCH_NONE, "target": [0.22, 0.79],
				"hold_s": 4.0, "threshold_g": 0.79,
				"note": "Never goes negative: a floater beat, not an airtime hill. Grounds placement and duration, not a negative-g target.",
			},
			{
				"axis": "gy", "label": "lateral (Falcon)",
				"measured": [-0.46, 0.43], "stretch": STRETCH_GY, "target": [-0.72, 0.67],
			},
			{
				"axis": "gx_negative", "label": "longitudinal (Falcon)",
				"measured": -0.61, "stretch": STRETCH_GX_NEGATIVE, "target": -1.04,
			},
			{
				"axis": "gz_negative", "label": "I305 ejector hill #15",
				"measured": -0.50, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.75,
				"hold_s": 1.25, "threshold_g": 0.0,
			},
			{
				"axis": "gz_negative", "label": "I305 last airtime pop (#19)",
				"measured": -0.45, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.68,
				"hold_s": 0.78, "threshold_g": 0.0,
			},
		],
		"caveats": [
			"Thin evidence, carried as a caveat rather than declared a gap: no same-ride counterpart supplies a negative-g value for a late-course height.",
			"I305 notes the pattern directly: the late hills are shallow-and-short, -0.4 to -0.5 g for 0.4-1.3 s, deliberately less than the mid-course hills (docs/TELEMETRY-I305.md lines 124-129). Return heights stronger than the mid-course airtime would contradict both sources.",
		],
	},
	"return-turn-b": {
		"counterpart": {
			"ride": "Falcon's Flight",
			"element": "long sustained banked turn t 132.0-139.4 s, with return-run turn B t 128.0-131.0 s and turn C t 142.36-144.34 s",
			"telemetry_anchor": "docs/TELEMETRY.md lines 133, 134, 136, 163",
		},
		"axes": [
			{
				"axis": "gz_positive", "label": "long sustained turn, held plateau",
				"measured": 2.46, "stretch": STRETCH_GZ_POSITIVE, "target": 3.28,
				"hold_s": [2.76, 8.0], "threshold_g": [2.0, 1.7],
				"note": "Range 1.69-2.46 g; 2.76 s at or above 2 g at t 136.64-139.38, inside about 8 s continuously between 1.7 and 2.5 g. Third-longest at-or-above-2 g run of the ride (line 163).",
			},
			{
				"axis": "gx_negative", "label": "longitudinal in the long turn",
				"measured": -1.52, "stretch": STRETCH_GX_NEGATIVE, "target": -2.60,
				"note": "A real energy-bleed retard on the unpowered return, not a brake application.",
			},
			{
				"axis": "gy", "label": "lateral in the long turn",
				"measured": [-0.63, 0.35], "stretch": STRETCH_GY, "target": [-0.99, 0.55],
			},
			{
				"axis": "gz_positive", "label": "return-run turn B",
				"measured": 2.39, "stretch": STRETCH_GZ_POSITIVE, "target": 3.19,
				"note": "Range 1.54-2.39 g.",
			},
			{
				"axis": "gy", "label": "lateral (turn B)",
				"measured": [-0.95, 0.48], "stretch": STRETCH_GY, "target": [-1.49, 0.75],
			},
			{
				"axis": "gz_positive", "label": "turn C",
				"measured": 2.31, "stretch": STRETCH_GZ_POSITIVE, "target": 3.08,
				"hold_s": 1.74, "threshold_g": 2.0,
				"note": "Range 2.03-2.31 g.",
			},
		],
		"caveats": [
			"The signature is length, not amplitude: about 8 s continuously between 1.7 and 2.5 g, reaching 89 degrees of bank at its middle.",
			"Three return turns are given because the measured ride shows this whole family living in a consistent 2.3-2.5 g band.",
			"Angle 16-89 degrees. Geometry is context, never scaled.",
		],
	},
	"return-height-b": {
		"counterpart": {
			"ride": "Falcon's Flight, with Intimidator 305 as class corroboration",
			"element": "float t 140.0-142.0 s; I305 ejector hill #17",
			"telemetry_anchor": "docs/TELEMETRY.md line 135; docs/TELEMETRY-I305.md line 60",
		},
		"axes": [
			{
				"axis": "gz_negative", "label": "float (Falcon)",
				"measured": -0.16, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.24,
				"hold_s": 2.0, "threshold_g": 0.0,
				"note": "Range -0.16 to +1.12 g: barely crosses zero, the shallowest airtime beat on the record.",
			},
			{
				"axis": "gy", "label": "lateral (Falcon)",
				"measured": [-0.37, 0.23], "stretch": STRETCH_GY, "target": [-0.58, 0.36],
			},
			{
				"axis": "gx_negative", "label": "longitudinal (Falcon)",
				"measured": -0.60, "stretch": STRETCH_GX_NEGATIVE, "target": -1.03,
			},
			{
				"axis": "gz_negative", "label": "I305 ejector hill #17",
				"measured": -0.40, "stretch": STRETCH_GZ_NEGATIVE, "target": -0.60,
				"hold_s": 0.38, "threshold_g": 0.0,
			},
		],
		"caveats": [
			"Same caveat as return-height-a, and weaker.",
			"Both sources agree the last airtime beat before the brakes is the smallest of the ride. A last height beat between -0.2 and -0.6 g for well under a second is inside both sources; anything deeper is unsupported by measurement, though not by itself wrong.",
		],
	},
	"terminal-capture-brakes": {
		"counterpart": {
			"ride": "Falcon's Flight, cross-checked against Tormenta and Source 2",
			"element": "trim/brake bite t 145.58-145.88 s and final brake run t 151.6-156.0 s; Tormenta brake bite and brake run",
			"telemetry_anchor": "docs/TELEMETRY.md lines 137, 139-140, 405-406, 917",
		},
		"axes": [
			{
				"axis": "gx_negative", "label": "brake bite (4804)",
				"measured": -1.89, "stretch": STRETCH_GX_NEGATIVE, "target": -3.23,
				"hold_s": 0.32, "threshold_g": -1.0,
				"note": "The ride's longitudinal minimum. NOT inside the t 99-100 s artefact burst, so defensible as a real value, but read the stretched -3.23 g as an upper bound rather than a design centre.",
			},
			{
				"axis": "gx_negative", "label": "maximum deceleration (Source 2, front / back run)",
				"measured": [-1.34, -0.93], "stretch": STRETCH_GX_NEGATIVE, "target": [-2.29, -1.59],
			},
			{
				"axis": "gx_negative", "label": "brake bite (Tormenta 6383 / 6369) - the trustworthy pair",
				"measured": [-0.94, -1.06], "stretch": STRETCH_GX_NEGATIVE, "target": [-1.61, -1.81],
				"hold_s": [0.82, 0.80],
				"note": "Two independent devices in two different seats, magnitudes within 0.12 g and hold durations within 0.02 s.",
			},
			{
				"axis": "gx_negative", "label": "final brake run (4804)",
				"measured": [-0.25, -1.06], "stretch": STRETCH_GX_NEGATIVE, "target": [-0.43, -1.81],
				"hold_s": 4.4,
				"note": "Sustained over t 151.6-156.0 s.",
			},
			{
				"axis": "gz_level", "label": "vertical on the brake run (4804)",
				"measured": 1.00, "stretch": STRETCH_NONE, "target": 1.00,
				"hold_s": 4.4,
				"note": "Range 0.90-1.09 g. Gravity baseline, not stretched.",
			},
			{
				"axis": "gx_negative", "label": "brake run (Tormenta)",
				"measured": [-0.3, -0.7], "stretch": STRETCH_GX_NEGATIVE, "target": [-0.51, -1.20],
				"hold_s": 22.0,
				"note": "Repeating over about 22 s at V about 0.97 g.",
			},
			{
				"axis": "gz_level", "label": "station (4804)",
				"measured": 1.00, "stretch": STRETCH_NONE, "target": 1.00,
				"hold_s": 2.0,
				"note": "Range 0.64-1.01 g. Capture is a 1 g level state, not stretched.",
			},
		],
		"caveats": [
			"The Tormenta cross-recording pair is the trustworthy number here, not the single 4804 reading.",
			"A brake bite of about -1.6 to -1.8 g stretched, held under a second, then a sustained run at -0.4 to -1.2 g, is supported by both rides.",
		],
	},
}

const EVIDENCE_GAPS := ["act-one-wave", "clifftop-outward-rim"]


static func bands() -> Dictionary:
	return BANDS
