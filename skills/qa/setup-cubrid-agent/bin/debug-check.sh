#!/bin/bash
# Run the testcase once on the DEBUG build of the same version, then put the release build back.
# Installed to ~/.cubrid-agent/bin/ by /setup-cubrid-agent.
#
# Why it exists: CI runs debug regression too, and a new TC that trips an engine assert or produces
# debug-only output is found there and attributed to whoever wrote the TC. Worse, an assert firing is
# often a real engine defect the TC just exposed — worth more when it is found while authoring than in
# somebody's nightly. Nothing in the pipeline looked at a debug build before this; the only mention was
# "release is CI mode, debug is for diagnosis".
#
# What it does NOT decide: whether an assert is an engine bug or a testcase misusing the engine (that
# goes to the developer, with the marker), and whether debug-only output differences are acceptable. It
# never promotes debug output into `.answer` — the answer is confirmed on release, which is CI's mode.
#
# usage: debug-check.sh CBRD-XXXXX [--version <version|url>] [--tc-path PATH] [--timeout SECONDS]
set -u

USAGE='usage: debug-check.sh CBRD-XXXXX [--version <version|url>] [--tc-path PATH] [--timeout SECONDS]'
KEY=""; VERSION_IN=""; TCPATH=""; TIMEOUT=900
while [ $# -gt 0 ]; do
  case "$1" in
    --version)  VERSION_IN="${2:?$USAGE}"; shift 2 ;;
    --tc-path)  TCPATH="${2:?$USAGE}"; shift 2 ;;
    --timeout)  TIMEOUT="${2:?$USAGE}"; shift 2 ;;
    -h|--help)  printf '%s\n' "$USAGE"; exit 0 ;;
    -*)         printf 'debug-check: unknown option: %s\n%s\n  If that is a documented flag, this installed copy is stale (the plugin updated, ~/.cubrid-agent/bin did not) — run /setup-cubrid-agent to refresh it.\n' "$1" "$USAGE" >&2; exit 1 ;;
    *)          KEY=$(printf '%s' "$1" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'debug-check: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
VERIFY="$SELF_DIR/verify-run.sh"
[ -x "$VERIFY" ] || { printf 'debug-check: verify-run.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$VERIFY" >&2; exit 1; }

# env.sh sources CUBRID's .cubrid.sh, which appends to LD_LIBRARY_PATH and PATH without guarding them —
# fatal under `set -u` wherever they are not already exported (a non-interactive ssh session).
# shellcheck disable=SC1090
if [ -f "$HOME/.cubrid-agent/env.sh" ]; then set +u; . "$HOME/.cubrid-agent/env.sh"; set -u; fi
CTP_HOME=${CTP_HOME:-}
[ -n "$CTP_HOME" ] || { for d in "$HOME/CTP" "$HOME/cubrid-testtools/CTP"; do [ -x "$d/bin/ctp.sh" ] && CTP_HOME=$d && break; done; }
CUB=${CUBRID:-$HOME/CUBRID}
RUN_DIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$RUN_DIR/manifest.json"
mkdir -p "$RUN_DIR"

HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
# Every terminal state is recorded, including the ones where nothing was tested: `checked` says whether
# the debug run actually happened, and the submit gate reads that rather than inferring it from silence.
record() {  # record <checked true|false> <result> <note> [marker]
  [ "$HAVE_JQ" = 1 ] || { printf '  (jq missing — verify.debug NOT recorded)\n'; return 0; }
  [ -f "$MANIFEST" ] || printf '{}\n' > "$MANIFEST"
  jq --argjson c "$1" --arg r "$2" --arg n "$3" --arg m "${4:-}" \
     --arg b "${DBG_VER:-${VERSION_IN:-}}" --arg l "${RUN_LOG:-}" \
     '.verify.debug = ({checked: $c, result: $r, type: "debug", build: $b, note: $n}
        | (if $m != "" then . + {marker: $m} else . end)
        | (if $l != "" then . + {log: $l} else . end))' \
     "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
}

INSTALLER="$CTP_HOME/common/script/run_cubrid_install"
[ -n "$CTP_HOME" ] && [ -f "$INSTALLER" ] || {
  printf 'debug-check: %s not found — CTP provides the installer, so this cannot swap builds. Install CTP (/setup-cubrid-agent) first.\n' "${INSTALLER:-<no CTP_HOME>}" >&2
  record false inconclusive "CTP installer not found; no build was swapped"; exit 3; }

# shellcheck source=build-swap.sh disable=SC1091
. "$SELF_DIR/build-swap.sh" || { printf 'debug-check: build-swap.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }
swap_record_failure() { record false inconclusive "$1"; }

# The release build now installed is the baseline: it is what gets restored, and its answer is the one
# CI compares against.
REL_VER=$(installed_version) || REL_VER=""
[ -n "$REL_VER" ] || { printf 'debug-check: no CUBRID build under %s — the release build must already be installed (it is the baseline this restores, and the build the .answer was confirmed on).\n' "$CUB" >&2
                       record false inconclusive "no build installed at start; nothing was swapped"; exit 3; }
REL_TYPE=$(installed_build_type) || REL_TYPE=""
[ "$REL_TYPE" = debug ] && { printf 'debug-check: the installed build is already a DEBUG build (%s). Install the release build first — the baseline this restores has to be the build the .answer was confirmed on.\n' "$REL_VER" >&2
                             record false inconclusive "refused: the installed build is already debug ($REL_VER)"; exit 1; }

DBG_URL=$(debug_url "${VERSION_IN:-$REL_VER}")
DBG_VER=$(url_version "$DBG_URL"); [ -n "$DBG_VER" ] || DBG_VER=$REL_VER
REL_URL=$(to_url "$REL_VER")
RUN_LOG="$RUN_DIR/verify-sql.log"

# Both URLs are proven before anything is installed: finding out that the release build cannot be
# reinstalled *after* swapping to debug is how a machine ends up stuck on an engine full of asserts.
reachable "$REL_URL" || {
  printf 'debug-check: the RELEASE build is not reachable at\n  %s\nRefusing to install anything: this run would leave the machine on the debug build with no way back.\n' "$REL_URL" >&2
  record false inconclusive "refused before any install: the release build ($REL_URL) is not reachable, so the swap could not be undone"; exit 3; }
reachable "$DBG_URL" || {
  printf 'debug-check: the debug build is not reachable at\n  %s\nNothing was installed. Check the version — the debug twin lives next to the release one under the same version directory.\n' "$DBG_URL" >&2
  record false inconclusive "refused before any install: the debug build ($DBG_URL) is not reachable"; exit 3; }

swap_set_baseline "$REL_VER" "$REL_URL" release DEBUG
# Not silenced, and not left to the end: the trap is the only caller on the path where this is
# interrupted mid-run, and that is exactly when the machine must not be left on a debug engine.
trap 'swap_restore || true' EXIT
trap 'printf "\n  interrupted — restoring the release build before exiting\n"; swap_restore || true; exit 130' INT TERM

printf '[debug-check] %s\n  release : %s\n  debug   : %s\n' "$KEY" "$REL_VER" "$DBG_VER"

install_build "$DBG_URL" "$DBG_VER" debug debug || {
  record false inconclusive "the debug build ($DBG_VER) did not install; see $RUN_DIR/install-debug.log"
  exit 3; }

TC_ARGS=()
[ -n "$TCPATH" ] && TC_ARGS=(--tc-path "$TCPATH")
OUT="$RUN_DIR/debug-check.out"
# --no-manifest: this run must not become the verification the submit gate reads. The answer is
# confirmed on release, and a debug run's numbers are not that.
"$VERIFY" "$KEY" --runs 1 --no-manifest --timeout "$TIMEOUT" "${TC_ARGS[@]+"${TC_ARGS[@]}"}" > "$OUT" 2>&1
RC=$?
sed -n '/^  runs :/p' "$OUT" | sed 's/^/  debug /'

# An assert or a crash outranks the pass/fail comparison: a case can print exactly the expected rows
# and still have tripped an assertion on the way. `abort` is deliberately NOT a marker — "transaction
# aborted" is ordinary SQL output.
MARKER=$(grep -hiE 'assert|Segmentation fault|core dumped|SIGSEGV|SIGABRT' "$RUN_LOG" "$OUT" 2>/dev/null | head -1)

swap_restore || exit 3

if [ -n "$MARKER" ]; then
  printf '  *** the debug engine reported an assertion or a crash ***\n    %s\n' "$MARKER"
  record true assert "the debug build tripped an assertion or crashed while running this testcase" "$MARKER"
  printf '  recorded: verify.debug.result=assert — submission stays blocked.\n'
  printf '  This is NOT an answer to fix: an assert firing on a supported statement is an engine defect,\n'
  printf '  so it goes to the developer with the marker and the log (%s). If instead the testcase drives\n' "$RUN_LOG"
  printf '  the engine outside what it supports, that is the testcase to change — your call, not this script'"'"'s.\n'
  exit 1
fi
case $RC in
  0) record true clean "ran clean on the debug build ($DBG_VER): no assertion, output matches the release answer"
     printf '  recorded: verify.debug.result=clean\n'
     printf '  NOT decided (yours): nothing — a clean debug run only says CI will not blame this TC for an assert.\n'
     exit 0 ;;
  1) record true differs "output differs from the release answer on the debug build, with no assertion — debug-only messages are one legitimate cause"
     printf '  recorded: verify.debug.result=differs — submission stays blocked until you explain it.\n'
     printf '  Do NOT promote the debug output into `.answer`: the answer is confirmed on release, which is\n'
     printf '  what CI compares. Read the diff in %s. If the difference is debug-only noise, say so in\n' "$OUT"
     printf '  verify.debug.note; if the testcase is genuinely build-dependent, that is a testcase problem.\n'
     exit 1 ;;
  *) record false inconclusive "the debug run was blocked (verify-run exit $RC) — see $OUT"
     printf '  recorded: verify.debug.result=inconclusive — the debug run never produced a comparison.\n'
     exit 3 ;;
esac
