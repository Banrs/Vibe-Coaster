# Fidelity evidence catalog review

Reviewed on 2026-08-10 against `docs/TELEMETRY.md`, `docs/TELEMETRY-I305.md`, `docs/RESEARCH.md`, the nine YouTube metadata/retrieval records, and the three RideForcesDB retrieval diagnostics.

## Acquisition and integrity boundary

- No video, audio, frame, thumbnail, cookie, session, or RideForcesDB raw sample payload is committed here.
- Six YouTube files are labelled curated snapshots of provider fields already captured in the repository. They are metadata artifacts only and do not imply that video was downloaded.
- The AHjk, NFV, and wX metadata endpoints were unavailable during artifact preparation. Their files explicitly record unavailable retrieval; repository display/channel labels are separate from provider-returned metadata, and no missing exact provider title is invented.
- All three RideForcesDB sources use the mutually exclusive `raw_fetch_unavailable` branch: a diagnostic path and digest plus non-empty, structured `docs/TELEMETRY.md` fallback citations. None has an artifact path or digest for a raw payload.
- The 50 Hz and 11-sample/0.22 s smoothing statements in RideForcesDB reviews are provenance of the already-reviewed telemetry corpus only. With no raw payload committed, they are not represented as independently reverified native cadence or newly executed processing.
- Empty `alignment` arrays are intentional evidence gaps. No cross-video clock, source-to-generated clock, visible-frame landmark, force-axis mapping for unknown-axis video, or executable comparison band has been invented.

## Mandatory adjudications

1. `youtube.coastertalk.continuous.0Ua` (`0UaOSBGSx20`) and `youtube.coastertalk.edited.seNR` (`seNRpi4wP-s`) remain separate sources. The former retains its own continuous playback timeline; the latter contains edits, b-roll, and two runs and therefore has no absolute continuous ride timeline.
2. `J54WKu2nU6o`, `sdXGD9kMR7s`, `0UaOSBGSx20`, and `poco8rOnW18` retain independent timeline origins. Their current alignment arrays are explicitly empty because no reviewed source-local landmark-to-generated mapping is committed. A future mapping must be landmark-to-landmark and source-local; no timestamp is transferred between them.
3. `poco8rOnW18` is a NoLimits2 simulation. It remains corroborative model-to-model geometry/order evidence only and cannot provide measured truth.
4. No unknown-rate video becomes a dense trace. Unknown row, device, cadence, axes, or synchronization stays an evidence gap.
5. RideForcesDB recording 4804 remains corroborative. It is a sole wrist-mounted recording flagged unreliable by RideForcesDB and cannot independently define an executable band.
6. Recording 6383 remains `Row 2, Seat 8, Train 1`. Recording 6369 remains a separate back-right-seat, pocket-carried phone recording with the author's possible-sliding caveat. Their absolute clocks are not interchangeable. Because raw acquisition is unavailable, the reviewed telemetry table is labelled fallback evidence, never raw data. Only a derived observation corroborated across 6383, 6369, and the Tormenta POV may be considered for executable promotion.
7. The former `terrain.act_one_hugging_share = [0.8, 1.0]` is an evidence gap. The source describes terrain-hugging qualitatively and does not justify that numeric interval.
8. The former I305 `transition_force_swing = [3.5, 4.7]` is removed from executable consideration. `docs/TELEMETRY-I305.md` describes several distinct transitions, but no single exact, non-coincident source window establishes that aggregate interval as the requested metric.
9. The former Do-Dodonpa positive-longitudinal scale factor `1.1` is removed. No approved fictional positive-longitudinal (`Gx+`) multiplier exists.
10. CGI, including `NFVNGgwZk3c`, remains model-to-model visual evidence. It yields no measured-truth target, and real POV evidence controls wherever they disagree.

## Axis and contribution limits

- `youtube.i305.overlay.wX7` is limited to reviewed vertical/normal-g windows. Lateral and longitudinal axes are not present and may not be inferred.
- `youtube.coastertalk.continuous.0Ua` may contribute displayed-channel landmarks only; axes remain unpermitted until separately reviewed.
- `youtube.coastertalk.edited.seNR` may contribute edited visual landmarks only, not a force trace or absolute timeline.
- `youtube.falcon.poco8rOnW18` and `youtube.falcon.cgi.NFV` are model-only.
- RideForcesDB table columns may be cited only through the exact fallback anchors/windows in each review. The table axis headings do not establish a verified raw-payload schema or stable pocket-device transform.

## Promotion decision

No source or observation in this artifact set is executable. Promotion requires the source-specific manifest prerequisites and cannot expand the source's permitted contributions or axes without a reviewed manifest version change.
