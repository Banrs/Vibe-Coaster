#!/usr/bin/env bash
#
# tools/gates.sh — parallel gate runner for Vibe-Coaster.
#
# Runs the same battery CI runs (see .github/workflows/*.yml and
# .github/focused-tests.txt): the import gate, the 12 focused test suites,
# and smoke.gd. The import gate is serial (it mutates the .godot import
# cache and must land before anything else runs). The 12 focused suites and
# smoke.gd are then run concurrently across a bounded worker pool.
#
# Usage:
#   tools/gates.sh                 Import gate, then focused suites + smoke.gd in parallel.
#   tools/gates.sh --serial        Fallback: run everything serially, fail-fast, like CI does.
#   tools/gates.sh --only PATTERN  Only run jobs whose res://... path contains PATTERN
#                                  (substring match). The import gate always runs first.
#   tools/gates.sh -j N            Worker pool size (default: nproc).
#
# Suite list source of truth: .github/focused-tests.txt is read at run time, never
# duplicated here, so this runner cannot drift from what CI executes.
#
# --- user:// isolation (read this before touching the runner) ---------------
# fidelity_artifact_tests.gd writes real files under the Godot user:// directory,
# and smoke.gd runs FidelityArtifactTests.run() inline (see smoke.gd's
# _initialize), so it does the same writes. By default user:// resolves to a
# single directory fixed by project name
# (~/.local/share/godot/app_userdata/<project name>/) with no per-process
# distinction, so two of these suites running at once would race on the same
# files.
#
# Investigated on this exact binary (Godot 4.7.1.stable.official, headless):
#   - `--user-data-dir <dir>` is a NO-OP on this build. A probe script that
#     prints OS.get_user_data_dir() reports the same default path whether or
#     not --user-data-dir is passed (both `--user-data-dir=X` and
#     `--user-data-dir X` forms tested). Do not rely on this flag.
#   - `XDG_DATA_HOME=<dir>` per process DOES work: user:// resolves to
#     "$XDG_DATA_HOME/godot/app_userdata/<project name>", confirmed via the
#     same probe. This is the mechanism this runner uses: every worker gets
#     its own XDG_DATA_HOME under a private per-run scratch directory in /tmp.
#   - Proved, not assumed: fidelity_artifact_tests.gd and smoke.gd were run
#     concurrently, with isolation, three times in a row -> 3/3 green (no
#     cross-talk). Run once more concurrently WITHOUT isolation to confirm the
#     collision is real before trusting the fix; see the timestamped
#     PROOF notes kept with the implementing change for the actual logs.
#
# If a future suite becomes flaky specifically under this runner's
# parallelism (not under plain `--serial`), do not "fix" it by weakening the
# suite — add its res://... path to SERIAL_TAIL_PATTERNS below so it runs
# alone, serially, after the parallel batch, with everything else already
# proven green. Empty today because nothing needed it.
SERIAL_TAIL_PATTERNS=()

set -uo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_DIR="$REPO_ROOT/godot"
MANIFEST="$REPO_ROOT/.github/focused-tests.txt"
GODOT_BIN="${GODOT_BIN:-$(command -v godot 2>/dev/null || echo /usr/local/bin/godot)}"
JOBS="${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
MODE="parallel"
ONLY_PATTERN=""

usage() {
	sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--serial)
		MODE="serial"
		shift
		;;
	--only)
		ONLY_PATTERN="${2:?--only requires a pattern}"
		shift 2
		;;
	-j | --jobs)
		JOBS="${2:?-j requires a number}"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "gates.sh: unrecognized argument: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

if [[ ! -x "$GODOT_BIN" ]] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "gates.sh: godot binary not found/executable: $GODOT_BIN" >&2
	exit 2
fi
test -s "$MANIFEST" || {
	echo "gates.sh: manifest missing or empty: $MANIFEST" >&2
	exit 2
}

RUN_ID="gates.$$.$(date +%s)"
RUNDIR="/tmp/vibecoaster-$RUN_ID"
LOGDIR="$RUNDIR/logs"
XDGDIR="$RUNDIR/xdg"
mkdir -p "$LOGDIR" "$XDGDIR"
echo "gates.sh: logs and isolated user:// dirs under $RUNDIR"

# ---------------------------------------------------------------------------
# Build the job list: manifest suites (filtered, exactly as CI parses them)
# plus smoke.gd, minus anything --only excludes.
# ---------------------------------------------------------------------------
declare -a JOB_LIST=()
while IFS= read -r line || [[ -n "$line" ]]; do
	[[ -z "$line" || "$line" == \#* ]] && continue
	if [[ "$line" != res://* ]]; then
		echo "gates.sh: focused test entry must start with res://: $line" >&2
		exit 2
	fi
	path="$GODOT_DIR/${line#res://}"
	test -f "$path" || {
		echo "gates.sh: manifest entry has no matching file: $line" >&2
		exit 2
	}
	JOB_LIST+=("$line")
done <"$MANIFEST"
JOB_LIST+=("res://smoke.gd")

if [[ -n "$ONLY_PATTERN" ]]; then
	declare -a filtered=()
	for suite in "${JOB_LIST[@]}"; do
		[[ "$suite" == *"$ONLY_PATTERN"* ]] && filtered+=("$suite")
	done
	JOB_LIST=("${filtered[@]}")
	if [[ ${#JOB_LIST[@]} -eq 0 ]]; then
		echo "gates.sh: --only '$ONLY_PATTERN' matched no suites" >&2
		exit 2
	fi
fi

# Split off any suite this runner has been told to always tail-run serially.
declare -a PARALLEL_JOBS=() SERIAL_JOBS=()
for suite in "${JOB_LIST[@]}"; do
	tail=0
	for pat in "${SERIAL_TAIL_PATTERNS[@]:-}"; do
		[[ -n "$pat" && "$suite" == *"$pat"* ]] && tail=1
	done
	if [[ $tail -eq 1 ]]; then
		SERIAL_JOBS+=("$suite")
	else
		PARALLEL_JOBS+=("$suite")
	fi
done

# ---------------------------------------------------------------------------
# Result bookkeeping (shared by serial and parallel paths)
# ---------------------------------------------------------------------------
declare -A RESULT_CODE=()
declare -A RESULT_TIME=()
declare -A RESULT_LOG=()
OVERALL_FAILED=0

log_path_for() {
	local suite="$1"
	local short="${suite#res://}"
	echo "$LOGDIR/${short//\//_}.log"
}

xdg_dir_for() {
	local suite="$1"
	local short="${suite#res://}"
	local d="$XDGDIR/${short//\//_}"
	mkdir -p "$d"
	echo "$d"
}

print_failure_detail() {
	local suite="$1" code="$2" log="$3"
	echo "--- FAIL: $suite (exit $code) — last 30 lines of $log ---"
	tail -n 30 "$log" 2>/dev/null || echo "(no log captured)"
	echo "--- end $suite ---"
}

print_summary_line() {
	local suite="$1" code="$2" dur="$3"
	if [[ "$code" == "0" ]]; then
		printf '  PASS  %-45s %7.1fs\n' "$suite" "$dur"
	else
		printf '  FAIL  %-45s %7.1fs  (exit %s)\n' "$suite" "$dur" "$code"
	fi
}

run_import_gate() {
	local log="$LOGDIR/import_gate.log"
	echo "== import gate =="
	local t0=$EPOCHREALTIME
	if (cd "$GODOT_DIR" && "$GODOT_BIN" --headless --path . --editor --quit) >"$log" 2>&1; then
		local dur
		dur=$(awk -v a="$EPOCHREALTIME" -v b="$t0" 'BEGIN{printf "%.1f", a-b}')
		printf '  PASS  import gate %41.1fs\n' "$dur"
		IMPORT_TIME="$dur"
	else
		local code=$?
		print_failure_detail "import gate" "$code" "$log"
		exit 1
	fi
}

run_one_serial() {
	local suite="$1"
	local log
	log="$(log_path_for "$suite")"
	local t0=$EPOCHREALTIME
	(cd "$GODOT_DIR" && "$GODOT_BIN" --headless --path . --script "$suite") >"$log" 2>&1
	local code=$?
	local dur
	dur=$(awk -v a="$EPOCHREALTIME" -v b="$t0" 'BEGIN{printf "%.1f", a-b}')
	RESULT_CODE["$suite"]=$code
	RESULT_TIME["$suite"]=$dur
	RESULT_LOG["$suite"]="$log"
	print_summary_line "$suite" "$code" "$dur"
	if [[ "$code" != "0" ]]; then
		print_failure_detail "$suite" "$code" "$log"
		exit 1
	fi
}

# ---------------------------------------------------------------------------
# Parallel path: bounded worker pool via `wait -n -p`.
# ---------------------------------------------------------------------------
declare -A PID_SUITE=()
declare -A PID_LOG=()
declare -A PID_START=()
RUNNING=0

start_job() {
	local suite="$1"
	local log xdg
	log="$(log_path_for "$suite")"
	xdg="$(xdg_dir_for "$suite")"
	(cd "$GODOT_DIR" && XDG_DATA_HOME="$xdg" "$GODOT_BIN" --headless --path . --script "$suite") >"$log" 2>&1 &
	local pid=$!
	PID_SUITE[$pid]="$suite"
	PID_LOG[$pid]="$log"
	PID_START[$pid]=$EPOCHREALTIME
	RUNNING=$((RUNNING + 1))
}

reap_one() {
	local donepid=""
	wait -n -p donepid
	local code=$?
	[[ -z "$donepid" ]] && return
	local suite="${PID_SUITE[$donepid]}"
	local dur
	dur=$(awk -v a="$EPOCHREALTIME" -v b="${PID_START[$donepid]}" 'BEGIN{printf "%.1f", a-b}')
	RESULT_CODE["$suite"]=$code
	RESULT_TIME["$suite"]=$dur
	RESULT_LOG["$suite"]="${PID_LOG[$donepid]}"
	print_summary_line "$suite" "$code" "$dur"
	if [[ "$code" != "0" ]]; then
		print_failure_detail "$suite" "$code" "${PID_LOG[$donepid]}"
		OVERALL_FAILED=1
	fi
	unset 'PID_SUITE[$donepid]' 'PID_LOG[$donepid]' 'PID_START[$donepid]'
	RUNNING=$((RUNNING - 1))
}

run_parallel_batch() {
	local -a jobs=("$@")
	[[ ${#jobs[@]} -eq 0 ]] && return
	echo "== ${#jobs[@]} suite(s) in parallel, -j $JOBS =="
	for suite in "${jobs[@]}"; do
		while ((RUNNING >= JOBS)); do reap_one; done
		start_job "$suite"
	done
	while ((RUNNING > 0)); do reap_one; done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
TOTAL_T0=$EPOCHREALTIME
run_import_gate

if [[ "$MODE" == "serial" ]]; then
	echo "== ${#JOB_LIST[@]} suite(s) serially =="
	for suite in "${JOB_LIST[@]}"; do
		run_one_serial "$suite"
	done
else
	run_parallel_batch "${PARALLEL_JOBS[@]}"
	if [[ ${#SERIAL_JOBS[@]} -gt 0 ]]; then
		echo "== ${#SERIAL_JOBS[@]} suite(s) tail-run serially (SERIAL_TAIL_PATTERNS) =="
		for suite in "${SERIAL_JOBS[@]}"; do
			log="$(log_path_for "$suite")"
			t0=$EPOCHREALTIME
			(cd "$GODOT_DIR" && "$GODOT_BIN" --headless --path . --script "$suite") >"$log" 2>&1
			code=$?
			dur=$(awk -v a="$EPOCHREALTIME" -v b="$t0" 'BEGIN{printf "%.1f", a-b}')
			RESULT_CODE["$suite"]=$code
			RESULT_TIME["$suite"]=$dur
			RESULT_LOG["$suite"]="$log"
			print_summary_line "$suite" "$code" "$dur"
			[[ "$code" != "0" ]] && {
				print_failure_detail "$suite" "$code" "$log"
				OVERALL_FAILED=1
			}
		done
	fi
fi

TOTAL_DUR=$(awk -v a="$EPOCHREALTIME" -v b="$TOTAL_T0" 'BEGIN{printf "%.1f", a-b}')
echo "== total: ${TOTAL_DUR}s (import ${IMPORT_TIME:-0}s + $MODE phase) =="

if [[ "$MODE" == "parallel" && $OVERALL_FAILED -ne 0 ]]; then
	exit 1
fi
exit 0
