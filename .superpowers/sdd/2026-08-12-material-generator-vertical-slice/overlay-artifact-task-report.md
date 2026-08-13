# Overlay artifact task report

## Status

GREEN.

## Files and line delta

- `godot/_inspect.gd`: +44 / -99
- `godot/fidelity_artifacts.gd`: +206 / -5
- `godot/fidelity_artifact_tests.gd`: +355 / -22
- Production total: +250 / -104
- Owned-code total: +605 / -126
- This report is the only additional task file.

No focused-test manifest edit was needed; both focused entries were already present in the shared worktree.

## Exact verification commands and results

All Godot invocations used only `out/tools/godot-4.7.1/Godot_v4.7.1-stable_win64_console.exe`, `--headless`, isolated `APPDATA`/`LOCALAPPDATA`, one process at a time, and a 180-second hard command timeout.

1. Baseline before production edits:

   `$env:APPDATA='D:\Coding\ClaudeCode\Vibe-Coaster\.tmp\overlay-artifact-baseline\Roaming'; $env:LOCALAPPDATA='D:\Coding\ClaudeCode\Vibe-Coaster\.tmp\overlay-artifact-baseline\Local'; & 'D:\Coding\ClaudeCode\Vibe-Coaster\out\tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe' --headless --path godot --script res://fidelity_artifact_tests.gd`

   Result: exit 0 in 3.6 s.

2. Final nine-case artifact suite:

   `$env:APPDATA='D:\Coding\ClaudeCode\Vibe-Coaster\.tmp\overlay-artifact-verify-artifact-2\Roaming'; $env:LOCALAPPDATA='D:\Coding\ClaudeCode\Vibe-Coaster\.tmp\overlay-artifact-verify-artifact-2\Local'; & 'D:\Coding\ClaudeCode\Vibe-Coaster\out\tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe' --headless --path godot --script res://fidelity_artifact_tests.gd`

   Result: exit 0 in 12.5 s. The printed `Z:/path-that-does-not-exist/frame.png` error is the suite's existing intentional negative checked-write case.

3. Final overlay-core regression suite:

   `$env:APPDATA='D:\Coding\ClaudeCode\Vibe-Coaster\.tmp\overlay-artifact-verify-core\Roaming'; $env:LOCALAPPDATA='D:\Coding\ClaudeCode\Vibe-Coaster\.tmp\overlay-artifact-verify-core\Local'; & 'D:\Coding\ClaudeCode\Vibe-Coaster\out\tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe' --headless --path godot --script res://fidelity_overlay_tests.gd`

   Result: exit 0 in 0.7 s.

4. Static scope/whitespace check:

   `git diff --check -- godot/_inspect.gd godot/fidelity_artifacts.gd godot/fidelity_artifact_tests.gd`

   Result: exit 0, no output.

## Legacy byte parity

PASS. `test_default_off_preserves_report_and_pack` was GREEN before production edits, includes a retained unaligned side-view beat, and remains GREEN. The five-argument report path adds no midpoint request, the three-argument writer adds no overlay files, repeated complete file sets are equal, and every repeated artifact byte (including `audit.json`, `audit.md`, PNGs, sidecars, and `manifest.json`) is identical.

## Nine-case result

PASS. The focused suite covers all nine named cases: default/off parity; opt-in midpoint POV request/dedup/conflict; four overlay additions plus both valid gap modes; disjoint native plot domains and source-only markers; redaction/dictionary-order determinism; guarded malformed explicit projections; inspector manifest/environment boundary; read-only diagnostics/no root PNG; and retained identity/one-build-per-seed behavior.

## Deletion and reuse notes

- Deleted the inspector's root PNG writes and their `_save`, `_render_channels`, `_stats`, `_print_phases`, and `_diagnostic_windows` path.
- Reused `RideFidelityOverlay.build` unchanged.
- Reused the existing request sorting/deduplication, `_write`, `_draw_line`, canonical JSON, and `_manifest_files` reopen/hash/dimension/sort path.
- Added one fixed raster overlay renderer; source and generated panels retain independent native clocks, with no normalized/common clock or fabricated generated gap window.
- Writer preflight validates every nested value consumed by Markdown/JSON/PNG rendering before any overlay write.

## Concerns

No functional concerns. The artifact suite intentionally prints the existing negative PNG-save diagnostic while still exiting 0.

## Review round 1 fixes

Status: GREEN for all five technically valid Important findings.

- The inspector now selects the exact legacy five-argument report and three-argument writer when both RFDB environment variables are absent. Manifest read/build and midpoint/overlay additions occur only for a nonempty explicit local map.
- Opt-in midpoint construction now returns a stable invalid report when a retained element lacks exactly one finite, ordered, in-duration zero-offset row.
- Overlay samples now obey native half-open windows; a sample at `window_s[1]` fails preflight.
- The redaction test injects `C:/Users/fixture/secret-rfdb.csv` through the inspector/core boundary and checks every emitted file for absence.
- Overlay Markdown is now a sorted concise comparison/status/clock/artifact table plus gaps; it contains no per-sample JSON.

Round line delta from `bff59ef`: `_inspect.gd` +32/-11, `fidelity_artifacts.gd` +49/-11, `fidelity_artifact_tests.gd` +62/-12.

### Round commands/results

Each command used the repository's console binary, `--headless`, isolated appdata, one process, and a 180 s timeout.

- Finding 1 final: `...Godot_v4.7.1-stable_win64_console.exe --headless --path godot --script res://fidelity_artifact_tests.gd` — exit 0, 14.3 s.
- Finding 2 RED — exit 1 with only the two expected zero/multiple-center assertions; GREEN — exit 0, 12.3 s.
- Finding 3 RED — exit 1 with only the expected excluded-end malformed-projection assertions; GREEN — exit 0, 13.7 s.
- Finding 4 boundary/redaction test — exit 0, 13.5 s.
- Finding 5 RED — exit 1 with only the three expected concise-Markdown assertions; GREEN — exit 0, 12.2 s.
- Final artifact verification: `...Godot_v4.7.1-stable_win64_console.exe --headless --path godot --script res://fidelity_artifact_tests.gd` — exit 0, 12.2 s, no artifact-suite assertion failures.
- Final overlay-core verification: `...Godot_v4.7.1-stable_win64_console.exe --headless --path godot --script res://fidelity_overlay_tests.gd` — exit 0, 0.8 s.
- `git diff --check -- godot/_inspect.gd godot/fidelity_artifacts.gd godot/fidelity_artifact_tests.gd` — exit 0.

Concern: the final artifact run printed compile diagnostics from concurrently edited, out-of-scope `ride_program.gd`/generator dependencies (`RETURN_*` identifiers), while this focused script still exited 0 with no artifact-suite assertion failures. The unchanged overlay-core suite was clean. No out-of-scope file was edited for this task.

## Review round 2 fix

Status: GREEN for the single Important malformed-gap finding.

- Added the exact `gaps: ["bad"]` malformed explicit-projection regression.
- Preflight now validates every gap entry as a Dictionary and validates each Markdown-consumed field (`comparison_id`, `role`, and `reason`) as a String before any overlay sort, render, or write.
- Round line delta from `d2bda61`: `fidelity_artifact_tests.gd` +1/-0; `fidelity_artifacts.gd` +9/-0.

Commands/results (console-only Godot, headless, isolated appdata, one process, 180 s timeout):

- RED: `...Godot_v4.7.1-stable_win64_console.exe --headless --path godot --script res://fidelity_artifact_tests.gd` — exit 1 in 13.7 s; `gaps: ["bad"]` reached the expected typed Dictionary assignment in `_overlay_markdown`, and the two malformed-case assertions failed.
- GREEN: `...Godot_v4.7.1-stable_win64_console.exe --headless --path godot --script res://fidelity_artifact_tests.gd` — exit 0 in 12.6 s; only the suite's intentional negative PNG-save diagnostic was printed.
- `git diff --check -- godot/fidelity_artifacts.gd godot/fidelity_artifact_tests.gd` — exit 0, no output.

Concern: none for this focused fix.
