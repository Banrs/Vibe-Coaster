# Roadmap

> **Directional, not a schedule.** A dependency order. Some steps will split, some will merge.

**Governing rule: no step may introduce a special case that a later step patches.** Build order is
allowed to be incremental; the *model* is not. If a step needs a shortcut to work, the design is
wrong — fix the design rather than leaving a fixup behind.

1. ~~Rust workspace, crate split, test harness, CI~~ — **done.** Workspace, `vc-math`, GitHub
   Actions running fmt, clippy, tests and docs with warnings denied.
2. ~~Math foundations — frames, splines, arclength, integrators, SI units~~ — **done.** See the
   Numerics section of `ARCHITECTURE.md` for the decisions that came out of it.
3. The ride model, complete — spec, site, vehicle. All three real from the start, even where nothing
   consumes them yet. *Blocked on the element vocabulary: what an element is, and whether the human
   pins forces or geometry.*
4. Evaluator — force profile → heartline → geometry, plus measurement: forces, energy, clearance
5. Multibody train inside the evaluator — couplers, drag, friction, propulsion and braking as
   parameters
6. The global solve — closure, energy, clearance, envelope, continuity, all at once
7. Godot client — GDExtension binding, track render, free camera. *First time you see it*
8. POV ride — true seat position, row selectable. *Rideable*
9. Analysis surfaced — envelopes, jerk, clearance, buildability cost, pacing score
10. Falcon's Flight validation — reproduces published figures within a written-down tolerance
11. Records and cliff terrain — feeding the model aggressive parameters and real heightmaps. Data
    work, not new features
12. Dress — speed cues, physics-driven audio, RTX

## Worth knowing

- **Steps 4 and 6 are the project.** The evaluator must be correct before the solver can be trusted,
  because a solver on a wrong evaluator converges confidently to nonsense.
- **Step 6 is the risk.** Global constrained solves fail by not converging. Budget for diagnostics —
  naming the failing constraint is as important as satisfying it.
- **Step 3 is where the leanness is won or lost.** If site and vehicle are fully modelled here, steps
  11 and 12 are configuration. If they're half-modelled, they become patches.
- **10 before 11, deliberately.** An unvalidated sim can produce a 400 m coaster and tell you
  nothing. Match something real, then push the parameters.
- **If the wait to step 7 grates**, a throwaway centreline viewer after step 4 is the cheap fix.
