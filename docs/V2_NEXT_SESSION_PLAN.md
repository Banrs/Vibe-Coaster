# MINECOASTER — V2 status & next-session plan

Self-contained resume document (2026-07-10, branch `claude/minecoaster-v2-rewrite-5f7f00`, pushed
to `origin` / GitHub `Banrs/Vibe-Coaster`). Written to survive context compaction: everything a
fresh session needs is here plus the repo docs it points to. Read alongside
`opengl/COASTER_REWRITE.md`, `docs/SHAPES.md`, `docs/TERRAIN_CONTRACT.md`, `docs/REALISM_SCALE.md`,
and the memory file `coaster-v2-working-rules.md`.

---

## 1. Where the project is (DONE)

**The V2 track rewrite is complete — migration steps 1–7 all landed.** The live OpenGL host
generates every ride from the V2 `opengl/src/track/` module; the V1 generator is retired.

- Steps 1–5: full primitive library (line, connector, top-hat, camelback, drop, turn, s-curve,
  helix, cliff dive) + all five inversions (loop, immelmann, dive loop, corkscrew, zero-g stall),
  each built from cited real-world physics, validated by a 270-check acceptance harness.
- Step 6: whole-ride planner (`buildRide`) — closed Falcon-inspired circuits at the locked
  ~1.4–1.5× WR sizes, terrain-integrated (escarpment scan, bounded cuts), speed matched to
  transit≈1× (`k_v≈k_r`), researched two-term drag model. Host switched to `TrackV2`.
- Step 7: V1 archived to `opengl/legacy/` **byte-identical and unbuilt** (user chose preserve, not
  delete); V1 CLI diagnostics replaced by headless `--v2audit N`.

### Verified (headless gates, all green)
- `cmake --build opengl/build -j` — clean, both targets.
- `./opengl/build/v2track_tests` — **PASS: 270 checks, 0 failures** (seeds 1–6 ride suite clean).
- `./opengl/minecoaster --v2audit 8` — 7/8 clean (seed 8 trips the clearance policy — the known
  unsupported-span follow-up below; seeds 1–6, the tuned set, all clean; exits 1 honestly).
- Determinism: `build(1337)` identical across runs (11173 m / 215 segs), 264 ms build time
  (< 0.5 s, no loading overlay needed).

### NOT verified — the one true blocker
- **The fixed-seed VISUAL regression has never been run.** This dev environment cannot open a GL
  context (`InitWindow`/`rlglInit` segfaults with no WindowServer session — environmental; the
  pre-V2 binary crashes identically). Screen-control launch was declined. **This is a human
  action** and it is `COASTER_REWRITE.md` step-6 gate #6, still open. See Phase 0.

---

## 2. The reframe that changes the next phase

> **SUPERSEDED IN PART (2026-07-10, later same day):** a deeper 6-subsystem audit confirmed the
> user's report that the shader layer was broken by a prior agent — reflections gutted (SSR
> plumbing bound every frame, shader never samples it), cascade0 rendered but never used, shadow
> distance hardcoded ~256 m, frozen tree wind, tonemap divergence. See
> **`docs/RENDER_REWRITE_INVENTORY.md`** — it is now the authoritative render-rewrite spec and
> execution order; the survey text below stands only for what exists, not for what works.

`docs/REALISM_SCALE.md` "Core philosophy" describes the renderer as "V1 rendering byte-for-byte…
a starting point to rewrite from." **A full code survey found this is wrong about the starting
point.** `render_fx.cpp` (1262 lines) is already a modern forward-HDR engine:

- 3-cascade shadow maps with **PCSS soft shadows** (blocker search + Poisson PCF, per-cascade bias).
- **Atmospheric sky**: Rayleigh+Mie scattering, sun disc/corona, god-rays, lens flare, **raymarched
  volumetric clouds**.
- **HDR R16G16B16A16 scene target → ACES tonemap** with bloom, depth SSAO, chromatic aberration,
  vignette, film grain.
- **PBR-ish materials**: two-lobe specular, sky-Fresnel metal (gold/steel tile-gated), **Ward
  anisotropic rail highlight**; shader-shaded animated Fresnel water with foam.
- A second renderer: `pathtrace.cpp` (1130 L) is a live/offline **voxel path-tracer** (KEY_T
  toggle; `--shot`/`--rttest` capture), already wired to `TrackV2`.

And the game is a real game: on-foot walking, board/dispatch, 3 ride cams + free-look, coins/score,
boost meter, live 2-axis g-force gauge, procedural audio (wind/rumble/coin/clack/whoosh), pause
menu, R-to-regenerate.

**Consequence:** the "next phase" is **validate → tune → gap-fill → reconcile the docs**, NOT a
from-scratch shader build. But nobody has *seen* the current output (GL blocker), so whether it's
"polish a nearly-done engine" (likely, from the code) or "fix a V2-host-switch regression"
(possible — the rail/support/window-rescale/seam-wrap/tie-density logic was all touched in step 6
and never visually confirmed) is **unknown until Phase 0**.

---

## 3. Loose ends carried out of the V2 track work

| Loose end | State | Fix lever | Effort |
|---|---|---|---|
| **Fixed-seed visual regression NEVER RUN** | Blocked on GL context (human-only) | Launch `./opengl/minecoaster` (play; or `--shot`→shot1-4.png @ frames 200/500/900/1200, seed 1337; `--rttest` for path-traced frame) | S (human) |
| **Host physics drag ≠ planner model** (CONFIRMED) | Host `ride_constants.h`: `DRAG=0.00028` v² + `FRICTION=0.015`. Planner `track_planner.cpp:42-48`: `cAero=1.0e-4` v² + rolling `0.008 g≈0.0785`. Host air-drag ~2.8× high, rolling ~5× low. | Rewrite host loss term (`main.cpp` physics ~:456 region) to the two-term model so the train carries the speeds the planner shed geometry to hit | M, judgment |
| **Unsupported spans ~42% of track** | `gradeTurnToTerrain` errs above ground; unsupported spans don't trip the clearance gate. Seed 8 rejects on it. | Lower the terrain-follow `clearance` (`track_planner.cpp:108/154`) to trade toward small cuts (TERRAIN_CONTRACT prefers cuts); re-run `--v2audit 8` | S/M, judgment |
| **elemShot/cobraShot forcing inert on V2** | `gForceElem` steers camera/speed only; V2 `buildRide` has no force hook, so these shots film whatever seed 1337 emits | Re-author against a per-element planner override | M |
| **Corkscrew roll-rate flag** | Locked 90–100°/s; genuine data gap (`REALISM_SCALE.md`) | Re-research only if real data surfaces | — |
| **Top-hat lift-assist cosmetic** | `M_CLIMB && !chain` draws amber chain-dog on the LSM-launched top-hat face | Set `chain=true` on the powered face in the tag map, or accept | S |

---

## 4. Prioritized phase plan for next session(s)

Effort: S ≈ <½ day, M ≈ 1–2 days, L ≈ 3+. "Deleg." = safe for a sub-agent (opus/sonnet);
"Judgment" = needs design/visual taste (do on Fable or with a human in the loop).

### Phase 0 — GROUND TRUTH (blocker; do first; human-gated)
Run the fixed-seed visual regression: human launches `./opengl/minecoaster` (+ `--shot`, `--rttest`).
Check at the station seam and through the ride: rail/support continuity, tie/grate density,
station docking, camera through inversions, the top-hat lift-assist spine, moderated-peak terrain,
water. **Everything visual below is speculative until this happens.** Effort: S (observation).

### Phase A — Track loose ends & final cleanup (mostly deleg.; start immediately, parallel with 0)
- Calibrate **host physics to the two-term loss model** (drag mismatch above). M, judgment.
- Lower `gradeTurnToTerrain` clearance to cut the **42% unsupported** toward small cuts; re-run
  `--v2audit 8` until 8/8. S/M, judgment.
- Top-hat lift-assist: `chain=true` on the powered face, or accept. S, deleg.
- Re-author `elemShot`/`cobraShot` element-forcing against a `buildRide` per-element override. M.
- Dead-code sweep: `voxel_render.cpp:1-168` (`#if 0` block), `pathtrace.cpp:54` (stale V1
  `struct Track` forward-decl), dead `ride_constants.h` mutables (`DRAG`/`BOOST_V`/`BOOST_TRIG`
  never reassigned), stale comments (`main.cpp:2088/2091`, `presentation.cpp:100`). S, deleg.
- Consider whether to now delete `opengl/legacy/` + `STEP6_HOST_SWITCH.md` (user chose to KEEP V1
  for reference — confirm before deleting). Deleg. once decided.

### Phase B — Renderer validation & reconciliation (depends on Phase 0)
- Reframe `REALISM_SCALE.md`/`README.md`: the renderer is already advanced; the work is
  tune/validate/gap-fill, not rewrite. S, judgment.
- Decide the **two-renderer question**: keep `pathtrace.cpp` as a live toggle vs demote to
  shot-only. If demoting, drop `legacyTonemap` branches + the SSR-remnant machinery
  (`render_fx.cpp:54-59`, `984-1045`; `main.cpp:1560-1572` — built, bound every frame, shader never
  samples it). M, judgment.

### Phase C — Shader/atmosphere polish (depends on B; needs real screenshots)
- Tune shadow bias/penumbra, bloom threshold, SSAO strength, fog distance against captured frames
  (all named constants in `render_fx.cpp`). S–M, judgment.
- Fix the metal-vs-`sheen` heuristic so pale stone/concrete stops reading as satin metal
  (`render_fx.cpp:331-332, 385-405`). M, judgment.
- Optional: per-seed curated sun angle or slow day/night (mind the FOG concurrency caveat at
  `game_state.cpp:44-51` — the TerrainMesh worker reads FOG). M–L, judgment.

### Phase D — World visual polish (depends on Phase 0)
- Biome color/tree-density tuning, water tint/foam, beach transitions (`main.cpp:944-956,
  1127-1155`, `render_fx.cpp:261-325`). S–M, judgment.

### Phase E — Game UX / audio (independent; parallelizable)
- Title/menu + seed entry + run-summary (extend the pause-panel pattern, `main.cpp:2180-2200`). M.
- In-game settings (volume/FOV/quality vs the current env-vars). S–M, deleg.
- Element-triggered SFX (launch roar, brake) over the existing wind/rumble stream
  (`presentation.cpp:1-75`). M, judgment.

### Phase F — Test / CI (independent; high durability)
- GitHub Actions: build + `v2track_tests` + `--v2audit 8` on push. S, deleg.
- Headless host-physics regression (build seed → sim laps → assert no NaN/stall + transit-time
  band), extending `--bench`/`--v2audit`. M, deleg.
- Golden-frame render check once Phase 0 gives a stable seed. M, judgment.

### Single highest-value first move
**Phase 0 — get a human to run and screenshot the game.** The entire rendering plan is currently
planning against an assumption (docs say "flat V1") that the code contradicts (advanced engine).
Until someone sees the fixed-seed output we can't tell if the next session is "polish a nearly-done
shader engine" or "fix a V2-host-switch render regression." Cheapest action, hard gate the rewrite
plan already defined, and the only thing that converts the whole render plan from speculative to
grounded.

---

## 5. How to build, verify, resume

```sh
cmake -B opengl/build -S opengl && cmake --build opengl/build -j   # both targets
./opengl/build/v2track_tests            # geometry harness — must stay PASS 270/0
./opengl/minecoaster --v2audit 8        # headless ride-suite audit (exit 0 iff all clean)
./opengl/minecoaster                    # the game (needs a real display; human launch)
```

- **Never loosen** the harness checks or `ClearanceLimits` to make something pass — gates are
  honest; strengthen, don't relax.
- **No-patch rule:** fix by rebuilding the affected unit + rechecking its call sites, not by
  bolting guards (this is why V1 rotted).
- **`opengl/legacy/` is frozen** — do not modify, re-include, or consult V1 as a reference.
- The track module (`opengl/src/track/`) is frozen-green; changing it means re-running the harness.
- User rules, locked element targets, and the full gotcha log live in the memory file
  `coaster-v2-working-rules.md` and in `docs/REALISM_SCALE.md`.
</content>
