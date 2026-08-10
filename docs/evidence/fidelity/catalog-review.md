# Fidelity evidence catalog review

Reviewed on 2026-08-10 against `docs/TELEMETRY.md`, `docs/TELEMETRY-I305.md`, `docs/RESEARCH.md`, the nine YouTube metadata/retrieval records, and the three RideForcesDB retrieval diagnostics.

## Acquisition and integrity boundary

- No video, audio, frame, thumbnail, cookie, session, or RideForcesDB raw sample payload is committed here.
- Exact YouTube oEmbed response bodies are committed for `J54WKu2nU6o`, `sdXGD9kMR7s`, `poco8rOnW18`, and `0UaOSBGSx20`; they were genuinely retrieved on 2026-08-10. They contain metadata only and do not imply that video was downloaded. YouTube oEmbed supplies no duration; exact durations below come from live media-element readback.
- No provider response body or digest is retained for `cUURkqyn4Zs` or `seNRpi4wP-s`; their metadata diagnostics contain only labels and rounded durations explicitly cited to the repository review corpus.
- The AHjk, NFV, and wX metadata endpoints were unavailable during artifact preparation. Their current state is `review_pending` even though the manifest preserves the plan's original permission ceiling in `initial_state`. Repository labels are separate from provider-returned metadata, and NFV has no asserted provider channel or duration.
- Exact current `rideInfo` response bodies are committed for recording 4804 and the Tormenta response containing 6369/6383. The 6369 provider author (`Zonies`) disagrees with the older telemetry-corpus label (`(RFDB Web Client)`); the disagreement is retained rather than described as a match.
- Raw acquisition diagnostics now record session, `getRec`, and CSV-download attempts. Recording 4804 returned `false` from `getRec` and HTML rather than CSV from a direct download request; the session-cookie download retry and all 6369/6383 raw requests were blocked by the execution environment.
- All three RideForcesDB sources use the mutually exclusive `raw_fetch_unavailable` branch: a diagnostic path and digest plus non-empty, structured `docs/TELEMETRY.md` fallback citations. None has an artifact path or digest for a raw payload.
- The 50 Hz and 11-sample/0.22 s smoothing statements in RideForcesDB reviews are provenance of the already-reviewed telemetry corpus only. With no raw payload committed, they are not represented as independently reverified native cadence or newly executed processing.
- Sparse live-reviewed source-local landmarks are retained for the four named POVs. Empty `alignment` arrays and explicit `alignment_status` fields mean that none is mapped to a generated selector. No cross-video clock, source-to-generated clock, force-axis mapping for unknown-axis video, or executable comparison band has been invented.
- The final review SHA-256 values are:
  - J54 `a15e577ee4f0d9915eb48ce08ad8c71d68b12635af01179a80d645cd282d676d`;
  - sdX `9dd4b8ed8f5d4bfd8b67f2218c65ed681fcb912fe55a5599e34770919d6192df`;
  - poco `99f44129f2731e65170fc524b3dc32dc7e7e022034596ae96642cea0af1c9fd0`;
  - 0Ua `4e0af882b0280a9d7c7638b2f33a68af7909a6d1d085e61adac987d7869632ba`.
  The manifest and catalog mirror these exact file digests.

## Live POV adjudication

- The independent media durations and publish dates are J54 `240.881 s` / `2026-01-05`, sdX `239.061 s` / `2026-01-01`, poco `328.521 s` / `2023-06-04`, and 0Ua `213.541 s` / `2026-04-14`. Durations are source-local media-element readbacks, not ride-duration targets.
- J54 is a built-ride centered rear-facing view with exact row and mount undisclosed; sdX is a built-ride front-row view per title with mount undisclosed; poco is a NoLimits2 precreation mixing third-person and virtual POV; 0Ua is a built-ride leading-view appearance with exact row and mount undisclosed.
- The historical `docs/RESEARCH.md:64` “zero obstruction” wording was removed from reviewed provenance because the live review contradicted it.
  The structured obstruction list—watermark, night exposure, motion blur, and rapid camera roll—governs reviewed observations, while the
  rear-facing view and confirmed forward-time element order remain retained provenance.
- The three retained 0Ua `Long.` labels are negative (`-0.30 g`, `-0.19 g`, and approximately
  `-0.58 g`) and remain approximate, unmapped uploader-rendered spot checks.
  Uploader warnings cover consumer-grade sensors, presentation editing, limited sampling,
  interpolation, and video-frame-rate data loss; raw cadence, calibration, orientation, filtering,
  sensor location, row/device, and edit decisions remain unknown.
- Sparse points are not a dense trace. Separate video clocks may be compared only landmark-to-landmark: no global offset, duration ratio, proportional scaling, warping, or source-to-generated alignment exists.
- Poco is historical model-to-model context only and cannot constrain as-built geometry, timing, clifftop order, or telemetry; real built-ride POV governs wherever sources disagree.

## Mandatory adjudications

1. `youtube.coastertalk.continuous.0Ua` (`0UaOSBGSx20`) and `youtube.coastertalk.edited.seNR` (`seNRpi4wP-s`) remain separate sources. The former retains its own continuous playback timeline; the latter contains edits, b-roll, and two runs and therefore has no absolute continuous ride timeline.
2. `J54WKu2nU6o`, `sdXGD9kMR7s`, `0UaOSBGSx20`, and `poco8rOnW18` retain independent timeline origins. Their alignment arrays are explicitly empty because no source-local landmark-to-generated mapping is committed. A future mapping must be landmark-to-landmark and source-local; no timestamp is transferred between them.
3. `poco8rOnW18` is a NoLimits2 simulation. It remains corroborative model-to-model geometry/order evidence only and cannot provide measured truth, as-built constraints, or a transferable clock.
4. No unknown-rate video becomes a dense trace. Unknown row, device, cadence, axes, or synchronization stays an evidence gap.
5. RideForcesDB recording 4804 remains corroborative. It is a sole wrist-mounted recording flagged unreliable by RideForcesDB and cannot independently define an executable band.
6. Recording 6383 remains `Row 2, Seat 8, Train 1`. Recording 6369 remains a separate back-right-seat recording from a phone in an unspecified pocket, with the author's possible-sliding caveat. Its current provider author conflicts with the corpus label. Their absolute clocks are not interchangeable. Because raw acquisition is unavailable, the reviewed telemetry table is labelled fallback evidence, never raw data. Only a derived observation corroborated across 6383, 6369, and the Tormenta POV may be considered for executable promotion.
7. The former `terrain.act_one_hugging_share = [0.8, 1.0]` is an evidence gap. The source describes terrain-hugging qualitatively and does not justify that numeric interval.
8. The former I305 `transition_force_swing = [3.5, 4.7]` is removed from executable consideration. `docs/TELEMETRY-I305.md` describes several distinct transitions, but no single exact, non-coincident source window establishes that aggregate interval as the requested metric.
9. The former Do-Dodonpa positive-longitudinal scale factor `1.1` is removed. No approved fictional positive-longitudinal (`Gx+`) multiplier exists.
10. CGI, including `NFVNGgwZk3c`, remains model-to-model visual evidence. It yields no measured-truth target, and real POV evidence controls wherever they disagree.

## Axis and contribution limits

- `youtube.i305.overlay.wX7` is limited to reviewed vertical/normal-g windows. Lateral and longitudinal axes are not present and may not be inferred.
- `youtube.coastertalk.continuous.0Ua` may contribute displayed-channel landmarks only; axes remain unpermitted until separately reviewed.
- `youtube.coastertalk.edited.seNR` may contribute edited visual landmarks only, not a force trace or absolute timeline.
- `youtube.falcon.poco8rOnW18` and `youtube.falcon.cgi.NFV` are model-only.
- RideForcesDB table columns may be cited only through the exact fallback anchors/windows in each review. `reviewed_table_column_semantics` describes those table headings; `raw_axis_mapping` remains null, and no stable device-to-rider transform is claimed.

## Promotion decision

No source or observation in this artifact set is executable. The live POV landmarks and prompts are unscored review evidence only: they create no selector, observation, target, force band, axis mapping, duration scaling, or generated alignment. Promotion requires the source-specific manifest prerequisites and cannot expand the source's permitted contributions or axes without a reviewed manifest version change.
