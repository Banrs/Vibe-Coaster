#!/usr/bin/env bash
#
# fetch-reference-media.sh — acquire LOCAL photographic reference for element geometry.
#
# WHY THIS LIVES OUTSIDE godot/
#   The repository rule is absolute: there is no network client in godot/ and none may be added.
#   Every URL inside the engine is an inert provenance string. Acquisition therefore happens here,
#   in a shell script a human runs deliberately, and the engine only ever reads local files whose
#   digests it verifies.
#
# POLICY — read before running
#   * The media this downloads is PERSONAL-USE LOCAL REFERENCE. It is written to ./reference-media/,
#     which is gitignored, and it is NEVER committed. Only landmarks, provenance strings and
#     sha256 digests are ever fit to commit. See docs/evidence/fidelity/source-manifest.json.
#   * The committed sources are `observation_only`, `corroborative` or `review_pending`. Nothing
#     obtained here promotes any of them to `executable`, creates a catalog target or selector, or
#     closes a ride-quality issue. A frame is evidence to read.
#   * Video thumbnails (the fallback path below) are WEAK PROVENANCE: an unknown moment of the ride
#     chosen by the uploader or by YouTube. They are labelled `thumbnail-fallback` in the emitted
#     manifest entries and must stay labelled that way. A weak reference read as a strong one is
#     worse than no reference at all.
#
# WHAT IT DOES
#   1. Ensures yt-dlp is available (installs it with `uv tool install yt-dlp` if missing).
#   2. Reads the video ids from docs/evidence/fidelity/source-manifest.json.
#   3. Ensures ffmpeg is available; if not, downloads a static build into ./reference-media/bin/.
#   4. Extracts frames at the timestamps you list in ./reference-media/landmarks.txt.
#   5. Computes sha256 for every frame and prints manifest-ready JSON entries.
#
# USAGE
#   tools/fetch-reference-media.sh                 # full run: download, extract, hash, emit
#   tools/fetch-reference-media.sh --thumbnails    # thumbnails only (no video download)
#   tools/fetch-reference-media.sh --emit-only     # re-hash and re-emit from what is already there
#
#   Then:
#     export REF_MEDIA_MANIFEST="$PWD/reference-media/geometry-reference-manifest.json"
#     INSPECT_OUT=out/geometry-audit godot --headless --path godot --script res://_inspect.gd
#
# LANDMARK FILE FORMAT (./reference-media/landmarks.txt — you fill this in)
#   One record per line, '#' starts a comment:
#     <video_id> <timestamp_seconds> <element_id> [description...]
#   e.g.
#     cUURkqyn4Zs 61.5  outward-dive  cliff dive committing at the rim
#   `element_id` may name a compiled window ("marquee-camelback/crest/00"), a material role
#   ("camelback"), or a bare role id ("crest").

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEDIA_DIR="${REPO_ROOT}/reference-media"
BIN_DIR="${MEDIA_DIR}/bin"
VIDEO_DIR="${MEDIA_DIR}/video"
FRAME_DIR="${MEDIA_DIR}/frames"
SOURCE_MANIFEST="${REPO_ROOT}/docs/evidence/fidelity/source-manifest.json"
LANDMARKS="${MEDIA_DIR}/landmarks.txt"
OUT_MANIFEST="${MEDIA_DIR}/geometry-reference-manifest.json"

# A static ffmpeg build, used only when the system has no ffmpeg. Documented URL, pinned host:
FFMPEG_STATIC_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"

MODE="full"
case "${1:-}" in
  --thumbnails) MODE="thumbnails" ;;
  --emit-only)  MODE="emit" ;;
  --help|-h)    sed -n '1,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
  "")           ;;
  *)            echo "unknown option: $1" >&2; exit 2 ;;
esac

log() { printf '[reference-media] %s\n' "$*" >&2; }

mkdir -p "${MEDIA_DIR}" "${BIN_DIR}" "${VIDEO_DIR}" "${FRAME_DIR}"

# --------------------------------------------------------------------------------------------
# Video ids come from the committed source manifest — never from a list typed here, so the
# script can only ever reach for sources the repository has already reviewed and recorded.
# --------------------------------------------------------------------------------------------
read_video_ids() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$SOURCE_MANIFEST" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
for source in manifest["sources"]:
    video_id = source.get("video_id")
    if video_id:
        print(f'{video_id}\t{source["source_id"]}\t{source.get("current_state","")}')
PY
  else
    grep -o '"video_id": "[^"]*"' "$SOURCE_MANIFEST" | cut -d'"' -f4 | sed 's/$/\t\t/'
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# --------------------------------------------------------------------------------------------
# Tooling
# --------------------------------------------------------------------------------------------
ensure_yt_dlp() {
  if command -v yt-dlp >/dev/null 2>&1; then YT_DLP="$(command -v yt-dlp)"; return; fi
  if [ -x "${BIN_DIR}/yt-dlp" ]; then YT_DLP="${BIN_DIR}/yt-dlp"; return; fi
  if command -v uv >/dev/null 2>&1; then
    log "installing yt-dlp with uv"
    uv tool install yt-dlp >&2 || true
    if command -v yt-dlp >/dev/null 2>&1; then YT_DLP="$(command -v yt-dlp)"; return; fi
    for candidate in "$HOME/.local/bin/yt-dlp" "$HOME/.local/share/uv/tools/yt-dlp/bin/yt-dlp"; do
      [ -x "$candidate" ] && { YT_DLP="$candidate"; return; }
    done
  fi
  log "yt-dlp is unavailable and could not be installed; video download will be skipped"
  YT_DLP=""
}

ensure_ffmpeg() {
  if command -v ffmpeg >/dev/null 2>&1; then FFMPEG="$(command -v ffmpeg)"; return; fi
  if [ -x "${BIN_DIR}/ffmpeg" ]; then FFMPEG="${BIN_DIR}/ffmpeg"; return; fi
  log "ffmpeg not found; fetching a static build from ${FFMPEG_STATIC_URL}"
  if curl -fsSL "${FFMPEG_STATIC_URL}" -o "${BIN_DIR}/ffmpeg.tar.xz" 2>/dev/null; then
    tar -xJf "${BIN_DIR}/ffmpeg.tar.xz" -C "${BIN_DIR}" --strip-components=1 --wildcards '*/ffmpeg' \
      && chmod +x "${BIN_DIR}/ffmpeg" && FFMPEG="${BIN_DIR}/ffmpeg" && return
  fi
  log "no ffmpeg available; frame extraction will be skipped"
  FFMPEG=""
}

# --------------------------------------------------------------------------------------------
# Acquisition
# --------------------------------------------------------------------------------------------
download_thumbnail() {
  # Weak provenance by construction. Try maxresdefault, fall back to hqdefault.
  local video_id="$1" target
  for name in maxresdefault hqdefault; do
    target="${FRAME_DIR}/${video_id}.${name}.jpg"
    [ -s "$target" ] && { echo "$target"; return 0; }
    if curl -fsSL "https://i.ytimg.com/vi/${video_id}/${name}.jpg" -o "$target" 2>/dev/null \
        && [ -s "$target" ]; then
      echo "$target"; return 0
    fi
    rm -f "$target"
  done
  return 1
}

download_video() {
  local video_id="$1"
  local existing
  existing="$(find "${VIDEO_DIR}" -name "${video_id}.*" -type f -print -quit 2>/dev/null || true)"
  [ -n "$existing" ] && { echo "$existing"; return 0; }
  [ -z "${YT_DLP}" ] && return 1
  log "downloading ${video_id}"
  "${YT_DLP}" -f 'bv*[height<=1080]+ba/b[height<=1080]' \
    -o "${VIDEO_DIR}/${video_id}.%(ext)s" \
    "https://www.youtube.com/watch?v=${video_id}" >&2 || return 1
  find "${VIDEO_DIR}" -name "${video_id}.*" -type f -print -quit
}

extract_frame() {
  local video="$1" timestamp="$2" target="$3"
  [ -z "${FFMPEG}" ] && return 1
  "${FFMPEG}" -y -loglevel error -ss "${timestamp}" -i "${video}" -frames:v 1 "${target}" >&2 \
    && [ -s "${target}" ]
}

# --------------------------------------------------------------------------------------------
# Run
# --------------------------------------------------------------------------------------------
if [ ! -f "${LANDMARKS}" ]; then
  cat > "${LANDMARKS}" <<'EOF'
# <video_id> <timestamp_seconds> <element_id> [description...]
# Fill this in from your own viewing of the source POV. One frame per element you want to check.
# Committed source video ids are listed by tools/fetch-reference-media.sh on every run.
#
# cUURkqyn4Zs  61.5   outward-dive   cliff dive committing at the rim
# cUURkqyn4Zs  74.0   camelback      camelback crest against the sky
# AHjk2R4da_I  38.0   return-turn-a  overbanked return turn
EOF
  log "wrote a landmark template to ${LANDMARKS} — fill it in and re-run"
fi

log "committed source video ids:"
read_video_ids | while IFS=$'\t' read -r video_id source_id state; do
  log "  ${video_id}  ${source_id}  ${state}"
done

declare -a ENTRY_FILES=()
declare -a ENTRY_IDS=()
declare -a ENTRY_SOURCES=()
declare -a ENTRY_TIMES=()
declare -a ENTRY_ACQ=()
declare -a ENTRY_DESC=()

source_id_for() {
  local video_id="$1"
  read_video_ids | awk -F'\t' -v v="$video_id" '$1 == v {print $2; exit}'
}

if [ "${MODE}" != "emit" ]; then
  ensure_yt_dlp
  ensure_ffmpeg
fi

# Pass 1 — real frames at real timestamps, the strong path.
if [ "${MODE}" = "full" ] && [ -f "${LANDMARKS}" ]; then
  while read -r video_id timestamp element_id description; do
    case "${video_id}" in ''|\#*) continue ;; esac
    [ -z "${element_id:-}" ] && continue
    target="${FRAME_DIR}/${video_id}-t${timestamp}-${element_id//\//__}.png"
    if [ ! -s "${target}" ]; then
      video="$(download_video "${video_id}" || true)"
      if [ -z "${video}" ] || ! extract_frame "${video}" "${timestamp}" "${target}"; then
        log "could not extract ${video_id} @ ${timestamp}s (download blocked or ffmpeg missing)"
        continue
      fi
    fi
    ENTRY_FILES+=("${target}"); ENTRY_IDS+=("${element_id}")
    ENTRY_SOURCES+=("$(source_id_for "${video_id}")"); ENTRY_TIMES+=("${timestamp}")
    ENTRY_ACQ+=("yt-dlp-frame"); ENTRY_DESC+=("${description:-}")
  done < "${LANDMARKS}"
fi

# Pass 2 — thumbnail fallback. Weak provenance, and it says so.
if [ "${#ENTRY_FILES[@]}" -eq 0 ] || [ "${MODE}" = "thumbnails" ]; then
  log "falling back to video thumbnails (weak provenance: unknown moment of the ride)"
  while IFS=$'\t' read -r video_id source_id state; do
    [ -z "${video_id}" ] && continue
    if thumb="$(download_thumbnail "${video_id}")"; then
      ENTRY_FILES+=("${thumb}"); ENTRY_IDS+=("")
      ENTRY_SOURCES+=("${source_id}"); ENTRY_TIMES+=("null")
      ENTRY_ACQ+=("thumbnail-fallback")
      ENTRY_DESC+=("YouTube thumbnail for ${video_id}; unknown moment of the ride, chosen by the uploader or by YouTube")
    else
      log "no thumbnail available for ${video_id}"
    fi
  done < <(read_video_ids)
fi

# --------------------------------------------------------------------------------------------
# Emit manifest-ready entries
# --------------------------------------------------------------------------------------------
if [ "${#ENTRY_FILES[@]}" -eq 0 ]; then
  log "no reference media was obtained; nothing to emit"
  exit 0
fi

{
  printf '{\n'
  printf '  "schema_version": "geometry-reference-manifest@1",\n'
  printf '  "manifest_version": "local-%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "policy": [\n'
  printf '    "Local personal-use reference media. NEVER committed; only landmarks, provenance and digests are.",\n'
  printf '    "Diagnostic only: promotes no source, creates no catalog target, closes no issue.",\n'
  printf '    "thumbnail-fallback entries are weak provenance — an unknown moment of the ride."\n'
  printf '  ],\n'
  printf '  "entries": [\n'
  for index in "${!ENTRY_FILES[@]}"; do
    file="${ENTRY_FILES[$index]}"
    relative="${file#${MEDIA_DIR}/}"
    digest="$(sha256_of "${file}")"
    element="${ENTRY_IDS[$index]}"
    [ -z "${element}" ] && element="UNASSIGNED-${index}"
    time_field="${ENTRY_TIMES[$index]}"   # already "null" or a bare JSON number
    separator=","
    [ "$index" -eq $(( ${#ENTRY_FILES[@]} - 1 )) ] && separator=""
    printf '    {\n'
    printf '      "element_id": "%s",\n' "${element}"
    printf '      "image_path": "%s",\n' "${relative}"
    printf '      "provenance": {\n'
    printf '        "source_id": "%s",\n' "${ENTRY_SOURCES[$index]}"
    printf '        "evidence_class": "observation_only",\n'
    printf '        "acquisition": "%s",\n' "${ENTRY_ACQ[$index]}"
    printf '        "timestamp_s": %s,\n' "${time_field}"
    printf '        "description": "%s",\n' "${ENTRY_DESC[$index]//\"/\\\"}"
    printf '        "sha256": "%s"\n' "${digest}"
    printf '      },\n'
    if [ "${ENTRY_ACQ[$index]}" = "thumbnail-fallback" ]; then
      printf '      "caveats": ["Weak provenance: a video thumbnail, not a frame at a reviewed landmark. Coarse silhouette check only."]\n'
    else
      printf '      "caveats": []\n'
    fi
    printf '    }%s\n' "${separator}"
  done
  printf '  ]\n'
  printf '}\n'
} > "${OUT_MANIFEST}"

log "wrote ${OUT_MANIFEST} with ${#ENTRY_FILES[@]} entr(y|ies)"
log "entries with element_id UNASSIGNED-* need a real element id before they composite anything."
log "next: export REF_MEDIA_MANIFEST=\"${OUT_MANIFEST}\""
cat "${OUT_MANIFEST}"
