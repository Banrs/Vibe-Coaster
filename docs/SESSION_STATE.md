# Session state — full redesign in progress (updated 2026-07-20, pre-compact snapshot)

Working doc for the ACTIVE session (and any successor). Authoritative plan: docs/REFACTOR_PLAN.md.
Branch: `claude/vibe-coaster-refactor-plan-jkxn0h` (push here ONLY — user chose designated branch,
NOT main). Ultracode is ON: user opted into Workflow-tool orchestration for all substantive tasks.

## User directives (accumulated, binding)
1. Full REDESIGN + remediation, not patching — replace hacks, don't compensate them. Refactor only
   where spaghetti blocks the redesign.
2. Sizing: elements 0.75–1.5x real record (RECORD_SCALE_MIN=0.75 approved). Element DURATION
   0.9–1.0x the real element's duration (soft constraint in sizing).
3. Water 10–15% measured (done: 12.9%). Element mix balanced to Falcon's Flight+Tormenta averages,
   share-based not count-based. Speed: realistic base pushed toward 240 km/h avg. ~120 s laps,
   act-structured (each lap = composed act; themes rotate). Shadows + broader visual pass; user's
   GPU is final judge. Census 8 complete=yes after EVERY change — never trade completion.
4. Net line growth must be justified (probes/guides OK); remove stale docs/comments (done once).
5. User rejected the first shadow attempt ("constant shade dim" on their GPU) → quantitative-only
   acceptance now (--shadowtest). Verify visuals by close-up screenshots + metrics, never vibes.
6. Delegate execution to opus/sonnet agents / workflows; lead session = architecture + review.

## Commit history this session (oldest first)
- 90d6645 plan doc | 0cbcbf4 probes (--overlap/--waterfrac/census shares) + baseline
- cd0b540 Phase1a constants+tprobe (byte parity) | 867ffcb+2a183e9 first shadow pass (superseded)
- d8435c6 Phase1b CommittedTrack/GenCursor + TxnSnapshot (byte parity, all 8 seeds)
- 067f7a0+ad87654 ShadowSys refactor + --shadowtest toolkit (all metrics PASS)
- 6fd6c3e stale-docs cleanup | 985beca..2b0fac2 Phase6b (water mesh+material, support cache,
  rail tangent attr, spinning wheels)
- f0fdfb4 Phase2 occupancy (16m grid+archive in CommittedTrack, 6m envelope, rollback-aware)
- 4b0134d Phase3 water 46.8%→12.9%, relief preserved (A/B verified 18..89m → 18..108m)

## Phase status
- DONE: 0 (probes/baseline), 1 (split), 2 (occupancy), 3 (water), 4 (composition director,
  CHECKPOINT — see below), 6 (shadows+renderer+wheels).
- Phase 4 checkpoint state (census 8 complete=yes verified): share controller (48-window,
  hi-gate + weight bias), time-based ~120s laps (ds/genV), act themes, 0.75x scale sweep,
  duration table, HELIX resurrected (3.6% share IN, scale mean 1.05x, n=15; fix = 0.75x bands
  widening speed window to ~46.9-71.1 m/s + clearance-matched drop + descent pre-gate),
  inversion-budget undercount bugfix (same-subtype chains). OPEN (owned by Phase 5, root cause =
  eligibility scarcity -> escapes -> forced lap closes at coaster_track.cpp ~:5005): lap-seconds
  mean 100.1 OUT [105,135] (min 2.2 degenerate lap), HILLS/DROP/IMMEL/LOOP LOW, TURN family 45.3%
  at band edge, fallbacks 211 escapes/104 relaxed per 8 seeds. Do NOT re-tune weights to fix these
  — fix routing (phase5 spec §1).
- USER DIRECTIVES added this session: no artificial speed pushing (physics constants only as
  documented REALISM calibration toward record-class values, never gate-fitting); top-hat exit
  ground clearance must drop to <10m (asymmetric top hat OK, symmetry rescinded); cliff-dive max
  90° pitch tracking the local face slope (face-hug binding, no mega-towers, setback 4-12m,
  support ≤22m); Falcon's Flight + Tormenta are THE references (Falcon's ~160m Tuwaiq cliff dive
  primary for the set piece); supervise agents' work every ~20-30 min, don't trust unsupervised
  fix loops. Specs: scratchpad/phase5_design.md (reviewed+amended), phase7_design.md (ditto).
- NEXT: Phase 5 (fallbacks→≤1/10 seeds via occupancy-AWARE routing; two known near-misses to kill:
  seed4 1.24m TURN↔FLAT-escape, seed2 0.21m IMMEL↔FLAT-escape — both from completion-guarantee
  escape tiers; joint anomalies seed2 ROLL→FLAT 0.312m/33°, seed4 TURN→CLIMB; authored-frame
  audits (Track::upAt, kill parallel-transport reconstruction); centralize drifted thresholds
  (0.18 vs 0.15 curvature-jerk; fog-warning dup game_state.cpp:45 vs main.cpp:1642); dedupe the
  5x copy-pasted drive loop). Then Phase 7 (cliff-dive set piece 88–95° with crest hold; avg
  speed 215→toward 240; full gate suite + orbitshot/watershot/wheels GPU gallery for user).

## Build & verify (container)
- raylib: /root/raylib55/libraylib.a (built; GLFW objs compiled individually). Build:
  g++ -std=c++17 -O2 -DNDEBUG -I/root/raylib55/src src/main.cpp /root/raylib55/libraylib.a \
      -lGL -lm -lpthread -ldl -lrt -lX11 -o <bin>
- Session binary: scratchpad/minecoaster. Headless render: xvfb-run -a <bin> --orbitshot
  (MC_CAPTURE_W/H=640/360 speeds llvmpipe; --watershot water vantage; MC_WATER_XZ override).
- Probes: --census N (THE gate; now prints share-vs-band + fallbacks), --overlap N (occupancy
  truth; keeps whole deque, slow), --waterfrac, --clearance N, --jointaudit N, --forceaudit N
  (vert-g trustworthy, continuity metrics are sampling artifacts until Phase 5), --shadowtest
  (quantitative shadow PASS/FAIL + PNGs), --shadowdebug, --exporttrack f seed, --terrainaudit.
- Parity baselines (pre-refactor geometry, HISTORICAL now — behavior intentionally changed from
  Phase 2 on): scratchpad/baseline_track_seed{1,4}.txt; artifacts/baseline/.

## Architecture knowledge (hard-won)
- Unity build: main.cpp includes all .cpp in order (gen_constants.h → terrain_probe.cpp →
  committed_track.cpp → coaster_track.cpp...). No real TUs.
- Track : CommittedTrack (append-only deques + evaluator + OccupancyIndex) + GenCursor (ALL
  mutable gen state, ~110 fields). TxnSnapshot{deque sizes, run marks, occLive ledger, GenCursor}
  + rollback-on-self (RAII TxnGuard, LIFO, popFront asserted outside txns). RNG order was the
  parity ABI (now free to change — parity era over).
- Occupancy: 16m grid of self-contained OccSpan{a,b,arc,id}; grid entries persist popFront (=
  archive); live ledger rolls back. Query: 3×3×3 cells, arc-exclusion 120m, seg-seg distance.
  Envelopes genc:: ORDINARY 6 / ESCAPE 4 / RELAXED 4.5 / LASTRESORT 2.5 / off(0) final
  completion guarantee (source of the two known clips — Phase 5 kills via smarter routing).
- Terrain: FIXED unseeded world (terrainH pure noise fn of x,z). Water = solidTop<=WATER_Y(18).
  Phase 3 law: inland smooth01(-0.25,0.30), shoreShelf smooth01(-0.55,-0.15)*7, base WATER_Y+14
  + cont*28 + shelf; mountain amp 92 untouched. tprobe memo 2^20/probe16 (exact-key, epoch).
  PERF TRUTH: census time ≈91% vnoise/terrainH (was 1.31B calls); deep copies were NOT the cliff.
- Shadows: ShadowSys module (render_fx.cpp): 4096 map, ortho+texel snap, BACK-face depth pass,
  hardware sampler2DShadow compare (COMPARE_REF flipped on for lit pass, off after for pathtrace),
  3×3 taps, direct-only shadow, ambient NEVER modulated, FBO fallback + GL diagnostics.
  --shadowtest PASS: contrast 2.811, edge 8px, penumbraFrac 0.0151, A/B stddev 0.2416, occ 0.268.
  USER GPU still unverified — ground truth command: ./minecoaster --shadowtest (paste [shadowtest] lines).
- Water render: one static mesh (rebuild on terrain waterVersion), uIsWater material path (alpha
  heuristic DEAD), per-vertex depth → shallows/deep + shore foam; uTime waves; receives shadows.
- Renderer: supports cached per-16-cp-chunk meshes (merged; per-support meshes REGRESSED on
  llvmpipe); rail tangent = vertex attribute (1 draw/chunk); wheels spin (arc/radius).
- Audits: three parallel-transport reconstructions exist (main.cpp v1RiderAuditSample, live HUD,
  v1_geometry_audit) — replacing with authored frames is Phase 5. Census inversion caps are
  hardcoded duplicates in main.cpp:987-990 (sync if generator caps change in Phase 4!).
- Element mix state pre-Phase-4: TURN-family ~47% HIGH, HILLS 6.6/DROP 3.6/IMMEL 7.5/SCURVE 5.4/
  LOOP 2.7/HELIX ~0.6 LOW; fallbacks 54 escapes/62 relaxed/4 forcedLapCloses (8 seeds); helix
  near-dead (speed window: makeHelixPlan invalid above ~72.6 m/s entry — suspected root).
- Share targets (genc table, Phase 4): TURN 14 SCURVE 8 DIVE 4 WAVE 4 (family gate 26), HILLS 15,
  BANKAIR 6, DROP 13, IMMEL 12, LOOP 4, ROLL 2.5, DIVELOOP 3, STALL 3, HELIX 4, DIP 3; bands
  0.75–1.75x; keep count rules ONLY for: tophat 1/lap, splash finale ≤1/lap, corkscrew pairing,
  inversion adjacency+budget 4/lap. Lap = 120 target seconds (ds/genV accumulator).
- Real-world research (for geometry choices): ASTM envelope = 95th %ile reach + 76mm, no public
  number → project constant 6m; near-misses are structure just outside envelope; splashdowns are
  once-per-ride finale legacy (SheiKra/Griffon only); Falcon's Flight ~3.5 elem/km sparse, 0
  inversions, avg speed ~30% of peak; Tormenta 3-4 inversions front-loaded, ~7 elem/km.
- Known misc: main.cpp "Vulkan HUD" comment is stale (left, file was locked during cleanup);
  --overlap generation without popFront is slow (evaluator scans grow); llvmpipe bench variance
  ±40-60ms — only same-session A/B counts.

## Session mechanics
- Design specs live in scratchpad: phase1_design.md (historical), phase4_design.md (ACTIVE).
- Workflow tool had transient "permission stream closed" aborts; workaround: Write script to the
  workflows/scripts dir then launch with scriptPath.
- Usage-limit interruptions killed agents twice; SendMessage to the agent id resumes them with
  context. Stop-hook nags about uncommitted changes are expected while agents work — commit only
  after gates.
