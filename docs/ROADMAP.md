# Roadmap

> **Directional, not a schedule.** A dependency order. Some steps will split, some will merge.

**Governing rule: no step may introduce a special case that a later step patches.** Build order is
allowed to be incremental; the *model* is not. If a step needs a shortcut to work, the design is
wrong — fix the design rather than leaving a fixup behind.

1. ~~Rust workspace, crate split, test harness, CI~~ — **done.** Workspace, `vc-math`, GitHub
   Actions running fmt, clippy, tests and docs with warnings denied.
2. ~~Math foundations — frames, splines, arclength, integrators, SI units~~ — **done.** See the
   Numerics section of `ARCHITECTURE.md` for the decisions that came out of it.
3. ~~The ride model, complete — spec, site, vehicle~~ — **done.** Elements are force-profile
   templates; the human pins element identity, order and height. See `MODEL.md`.
4. ~~Evaluator — force profile → heartline → geometry, plus measurement~~ — **done.**
5. Multibody train — **partial.** Rigid couplers and mass-weighted gravity over every row give the
   back-row snap; elastic couplers and snatch loads are not modelled.
6. The global solve — **partial.** Geometric pins now bind: each element carries two demands —
   trim sets the pitch it hands on, length sets its size — seeded by damped Newton before the
   solve, then solve/re-seed/solve. Closure reaches 18.7 m over 6.9 km. Still basin-sensitive, and
   three limits remain slightly over. See `MODEL.md`.
7. Godot client — GDExtension binding, track render, free camera. *Not started; an HTML POV viewer
   stands in for now*
8. ~~POV ride — true seat position, row selectable~~ — **done, in the stand-in viewer.**
9. Analysis surfaced — envelopes, jerk, clearance, buildability cost, pacing score
10. Falcon's Flight validation — reproduces published figures within a written-down tolerance
11. Records and cliff terrain — **mostly done as data, as predicted.** Every geometric record
    target is beaten by feeding the model a taller escarpment, maglev running gear and 1.25x
    figures. No new features were needed. Real heightmaps still to come
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
