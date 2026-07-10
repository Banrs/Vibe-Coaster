# Step-6 host-switch execution plan (working doc — delete with V1 at step 7)

Status: actionable change plan produced 2026-07-10 (read-only audit of the current tree;
main.cpp is 2670 lines). Execute AFTER the multi-seed ride suite (testStep6Rides) is green.
Landing order at the bottom. Line numbers verified against the tree at commit time.

## Consumer-surface audit

Live game loop + pathtrace + car/station renderers touch exactly: cp, up, kind, chainf, arc,
pos(), tangent(), upAt(), tagAt(), chainAt(), speedScale(), ensureAhead(), popFront(),
startPos, startYaw (all on TrackV2) — plus stationActive/Pending/Pos/Yaw/Stop and
railC/spineC/trainBody/trainAccent (NOT on TrackV2: host must own), and V1-only diagnostics
(reset/genPoint/base/gvlog — die at step 7).

Two structural facts drive the risk:
1. u-scale changes ~14 m/unit -> 1 m/unit: every hard-coded u+N / k+N lookahead and clamp
   bakes in the 14 m scale and must be rescaled to meters.
2. Route is finite+closed; popFront is a no-op: the V1 streaming idiom becomes a
   TRAIN-FREEZING bug; integer cp[] loops must wrap modulo n at the seam.

## v2::Tag -> SegMode mapping (host-side table in game_state.cpp, used by TrackV2 at the boundary)

| v2::Tag | SegMode | note |
|---|---|---|
| Station | M_STATION | kicker-exempt, no banner, decel logic |
| Brake | M_STATION | no M_BRAKE exists; folded (benign, documented) |
| Launch | M_LAUNCH | LSM thrust +112, grate + powered spine |
| Line | M_FLAT | neutral |
| Connector | M_FLAT | must NOT be M_CLIMB (auto-lift at main.cpp:762) |
| TopHat | M_CLIMB | banner TOP HAT; caveat: M_CLIMB && !chain draws lift-assist spine — set chain=true on the powered face or accept cosmetic |
| Camelback | M_HILLS | AIRTIME HILL |
| Drop | M_DROP | |
| Turn | M_TURN | |
| SCurve | M_SCURVE | |
| Helix | M_HELIX | drives helix-annulus terrain carve (main.cpp:1067-1106) |
| CliffDive | M_CLIFFDIVE | special |
| Loop | M_LOOP | tightShape support-skip |
| Immelmann | M_IMMEL | tightShape |
| DiveLoop | M_DIVELOOP | tightShape |
| Corkscrew | M_ROLL | banner CORKSCREW |
| ZeroGStall | M_STALL | tightShape |

Never-emitted M_*: M_DIP (splashdown banner never fires), M_BOOST (+160 punch never fires; V2
conditions speed by geometry/Launch), M_DIVE, M_BANKAIR, M_WAVE, M_COBRA, M_WINGOVER,
M_HEARTLINE, M_PRETZEL, M_STENGEL, M_BANANA — all harmless.

Sketch (game_state.cpp after :103):
    static const unsigned char kV2ToSeg[/*v2::Tag::COUNT==17*/] = {
        M_STATION, M_STATION, M_LAUNCH, M_FLAT, M_FLAT, M_CLIMB, M_HILLS, M_DROP,
        M_TURN, M_SCURVE, M_HELIX, M_CLIFFDIVE, M_LOOP, M_IMMEL, M_DIVELOOP, M_ROLL, M_STALL };
+ static_assert on COUNT. track_v2.cpp: kind[i] and tagAt() route through kV2ToSeg.

## Checklist (dependency order)

1. **Tag table** (above) — prerequisite for everything tag-related.
2. **Rehome submergedGround -> game_state.cpp (after WATER_Y) and rideElemName ->
   presentation.cpp** (unchanged signatures; both currently in coaster_track.cpp, die step 7;
   rideElemName already speaks M_* so works on mapped tagAt output).
3. **Swap instantiation** (main.cpp:525-526): TrackV2 trk; bind trk.terrain.height =
   groundTopAt, waterY = WATER_Y; trk.build(trackSeed). Seed setup (:445-449): explicit
   trackSeed (1337 for shot/bench modes; time|1 otherwise) — g_rng no longer drives track.
   Reseed R (:652-659): trk.build(newSeed) — atomic, satisfies "only show when fixed"
   (optional 1-frame "Generating..." gate if slow). Unity chain gains track/ modules
   ALONGSIDE coaster_track.cpp until step 7. CHECK: TerrainQuery.height contract vs
   groundTopAt's WATER_Y flooring (scan expects what track_terrain.cpp binds in tests: floored
   groundTopAt — consistent).
   **Theme colors rehome**: host locals from THEMES[trackSeed % THEME_N]; drawStation +
   bakeVoxelsCPU signatures take colors + platform pose explicitly (drawStation reads
   trk.spineC/.trainAccent at coaster_car.cpp:71-72; pathtrace reads at :952-954, :1009,
   :889-890). AsyncBaker copies Track by value -> copies TrackV2 by value (profile; snapshot
   windowed slices if heavy).
4. **u-wrap replaces popFront** (main.cpp:827): the while(u>13 && cp.size()>18){popFront; u-=1}
   loop FREEZES the train on V2 (cp never shrinks). Replace with: mu=trk.maxU(); while(u>=mu)
   u-=mu; Park/lap logic hooks on the wrap event. du clamp :825 fminf(du,1.5f) was 1.5 units
   ≈ 21 m/f — now caps at 90 m/s; raise to ~6.0f (metre budget).
5. **Window rescales (~14x) + seam wrapping** (CRITICAL, silently-short-track class):
   main.cpp:1517 (k1=u+64 -> ~u+896 or arc-based), :1646-1648 (kS=u-14,kE=u+46), :1136
   (carve u+64/u-14), :1068 (helix scan u+46), :747/:754 (tag lookahead ±10 -> element-length),
   :1601-1602 (tightShape ±48 -> ±300 or contiguous-run walk). pathtrace: :775, :844, :881,
   :936-937, :964. Support cadence :1618-1620 keys off arc[] METERS (SUP_SP=9) — correct
   as-is. Tie cadence :1711 and LSM grate :1624-1643 need arc-spacing gates (dense samples
   would stack 14 boxes/m). All integer cp[] loops must wrap mod n at the closed seam (or
   march by float uu through the wrapping accessors); support de-dup :1603-1608 and helix
   run-walk assume contiguity — handle the seam explicitly.
6. **Station/brake seam** : delete mid-course request machinery (:797-804); decel whenever
   tagAt==M_STATION; park at the wrap event (v=0, platform = startPos/startYaw). Retarget
   stationActive/Pos/Yaw reads (:1128, :1509-1510, pathtrace :889-890) to the single seam
   platform. Document: random mid-ride stops are gone (one continuous fixed lap docks at the
   sole station). Tune brake decel vs return speed so the train doesn't stall pre-seam.
7. **Curvature/g clamp rescale** (main.cpp:857-861): du=Clamp(7.5f/ss, 0.35f, 1.1f) — the max
   1.1 assumed units; at ss=1 the 7.5 m baseline clamps to 1.1 m (noisy g). Raise max to ~9.0.
   backU/backUProxy integrate meters — correct as-is. LAUNCH_V/CLIMB_V/CHAIN_V etc. are m/s —
   unaffected. Anti-stall kicker (v<30) unaffected.
8. **Hard swap, no --v2 flag** (u-scales incompatible; V1 dies at step 7 anyway). V1 CLI
   diagnostics (--audit/--census/--rollingdump/--profile/--exporttrack/--pacing/--gtest/
   elemShot; main.cpp:35-443 + audit_diagnostics.cpp) stay on V1 Track until step 7, then are
   deleted or re-authored against buildRide+validateRoute. Fixed-seed visual regression:
   trackSeed=1337 + g_rng=1337 keeps shots pixel-stable.

## Highest-risk items to test first
- u-wrap replacing popFront (silent train-freeze if missed)
- u+N window rescale (silently short track ahead)
- closed-seam cp[] wrapping (rail/supports vanish at the seam)
