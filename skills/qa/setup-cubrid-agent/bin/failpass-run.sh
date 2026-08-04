#!/bin/bash
# Prove the testcase catches the bug: run it on a PRE-FIX build (must FAIL), then on the fixed build
# (must PASS) — and always put the fixed build back, even when something in between dies.
# Installed to ~/.cubrid-agent/bin/ by /setup-cubrid-agent.
#
# A sequence that dies after the first install leaves the machine on a PRE-FIX build with nothing
# recording it, after which every later verify silently runs against an engine that still has the bug.
# So: the fixed build's URL is proven reachable BEFORE the first install, the restore is an EXIT trap,
# and the installed version is asserted after every install.
#
# It does NOT decide whether the build you named is really pre-fix, nor whether a timing-sensitive
# repro deserves `best_effort`. `confirmed` is written only for FAIL-then-PASS.
#
# usage: failpass-run.sh CBRD-XXXXX --prefix-build <url|version> [--fixed-build <url|version>]
#                                   [--tc-path PATH] [--timeout SECONDS]
set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=common.sh disable=SC1091
. "$SELF_DIR/common.sh" || { printf 'failpass-run: common.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }

USAGE='usage: failpass-run.sh CBRD-XXXXX --prefix-build <url|version> [--fixed-build <url|version>] [--with-debug-check] [--tc-path PATH] [--timeout SECONDS]'
KEY=""; PREFIX_IN=""; FIXED_IN=""; TCPATH=""; TIMEOUT=900; WITH_DEBUG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix-build) PREFIX_IN="${2:?$USAGE}"; shift 2 ;;
    --fixed-build)  FIXED_IN="${2:?$USAGE}"; shift 2 ;;
    --tc-path)      TCPATH="${2:?$USAGE}"; shift 2 ;;
    --timeout)      TIMEOUT="${2:?$USAGE}"; shift 2 ;;
    # One swap phase instead of two: ordered pre-fix → fix-debug → fix-release, three questions cost
    # three installs, and the last install IS the restore.
    --with-debug-check) WITH_DEBUG=1; shift ;;
    -h|--help)      printf '%s\n' "$USAGE"; exit 0 ;;
    -*)             reject_unknown "$USAGE" "$1" ;;
    *)              KEY=$(parse_issue_key "$1"); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'failpass-run: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }
[ -n "$PREFIX_IN" ] || { printf 'failpass-run: --prefix-build is required (a build from before the fix but after the feature that introduced the bug).\n%s\n' "$USAGE" >&2; exit 1; }

VERIFY="$SELF_DIR/verify-run.sh"
[ -x "$VERIFY" ] || { printf 'failpass-run: verify-run.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$VERIFY" >&2; exit 1; }

CTP_HOME=${CTP_HOME:-}
[ -n "$CTP_HOME" ] || { for d in "$HOME/CTP" "$HOME/cubrid-testtools/CTP"; do [ -x "$d/bin/ctp.sh" ] && CTP_HOME=$d && break; done; }
CUB=${CUBRID:-$HOME/CUBRID}
RUN_DIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$RUN_DIR/manifest.json"
mkdir -p "$RUN_DIR"

HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
record() {  # record <status> <note>
  [ "$HAVE_JQ" = 1 ] || { printf '  (jq missing — verify.fail_to_pass NOT recorded)\n'; return 0; }
  [ -f "$MANIFEST" ] || printf '{}\n' > "$MANIFEST"
  jq --arg s "$1" --arg n "$2" --arg pb "${PREFIX_VER:-$PREFIX_IN}" --arg fb "${FIXED_VER:-}" \
     --arg pr "${PREFIX_OUTCOME:-not run}" --arg fr "${FIXED_OUTCOME:-not run}" \
     '.verify.fail_to_pass = {status: $s, note: $n, prefix_build: $pb, fixed_build: $fb,
                              prefix_run: $pr, fixed_run: $fr}' \
     "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
}

INSTALLER="$CTP_HOME/common/script/run_cubrid_install"
[ -n "$CTP_HOME" ] && [ -f "$INSTALLER" ] || {
  printf 'failpass-run: %s not found — CTP provides the installer, so this cannot swap builds. Install CTP (/setup-cubrid-agent) first.\n' "${INSTALLER:-<no CTP_HOME>}" >&2
  record inconclusive "CTP installer not found; no build was swapped"; exit 3; }

# CUB, INSTALLER and RUN_DIR above are build-swap.sh's contract.
# shellcheck source=build-swap.sh disable=SC1091
. "$SELF_DIR/build-swap.sh" || { printf 'failpass-run: build-swap.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }

# swap_restore calls this when the machine is left on the pre-fix build, so the manifest says so
# even when the only thing still running is the EXIT trap.
swap_record_failure() { record inconclusive "$1"; }

FIXED_VER=$(installed_version) || FIXED_VER=""
[ -n "$FIXED_VER" ] || { printf 'failpass-run: no CUBRID build under %s — the fixed build must already be installed (it is what gets restored).\n' "$CUB" >&2
                         record inconclusive "no build installed at start; nothing was swapped"; exit 3; }

PREFIX_URL=$(to_url "$PREFIX_IN"); PREFIX_VER=$(url_version "$PREFIX_URL")
FIXED_URL=$(to_url "${FIXED_IN:-$FIXED_VER}")
FIXED_TYPE=$(installed_build_type) || FIXED_TYPE=""
DEBUG_URL=$(debug_url "${FIXED_IN:-$FIXED_VER}")
# The baseline carries its TYPE here: with --with-debug-check the machine passes through the debug twin,
# whose version is identical, so a version-only baseline would call the restore already done.
swap_set_baseline "$FIXED_VER" "$FIXED_URL" "$FIXED_TYPE" "PRE-FIX"

# Order matters: BOTH URLs are proven before anything is installed. Discovering that the fixed build
# has been pruned from the server *after* installing the pre-fix one is how a machine gets stranded —
# and build pruning is normal here, so this is not a theoretical case.
_urls="prefix:$PREFIX_URL fixed:$FIXED_URL"
[ "$WITH_DEBUG" = 1 ] && _urls="$_urls debug:$DEBUG_URL"
for _p in $_urls; do
  _n=${_p%%:*}; _u=${_p#*:}
  reachable "$_u" || {
    if [ "$_n" = fixed ]; then
      printf 'failpass-run: the FIXED build is not reachable at\n  %s\nRefusing to install anything: this run would leave the machine on the pre-fix build with no way back. Pass --fixed-build with a URL that exists (old builds get pruned).\n' "$_u" >&2
      record inconclusive "refused before any install: the fixed build ($_u) is not reachable, so the swap could not be undone"
    else
      printf 'failpass-run: the pre-fix build is not reachable at\n  %s\nNothing was installed. Check the version — a build named in an issue may already be pruned.\n' "$_u" >&2
      record inconclusive "refused before any install: the pre-fix build ($_u) is not reachable"
    fi
    exit 3; }
done
[ "$PREFIX_VER" != "$FIXED_VER" ] || {
  printf 'failpass-run: the pre-fix URL names %s, which is the build already installed — a fail→pass check against itself proves nothing.\n' "$PREFIX_VER" >&2
  record inconclusive "refused: --prefix-build names the installed build ($FIXED_VER)"; exit 1; }

# NOT silenced: on the path where the trap is the only caller (Ctrl-C mid-run) this is the message
# naming the stranded build. swap_restore's own flags already prevent duplicate output.
trap 'swap_restore || true' EXIT
trap 'printf "\n  interrupted — restoring the fixed build before exiting\n"; swap_restore || true; exit 130' INT TERM

printf '[failpass] %s\n  fixed  : %s\n  prefix : %s\n' "$KEY" "$FIXED_VER" "${PREFIX_VER:-$PREFIX_URL}"

TC_ARGS=()
[ -n "$TCPATH" ] && TC_ARGS=(--tc-path "$TCPATH")
run_case() {  # run_case <label> -> 0 pass, 1 fail(mismatch), 3 blocked
  _out="$RUN_DIR/failpass-$1.out"
  # --no-manifest: a deliberate pre-fix failure must never become the record the submit gate reads.
  # --log-label: without it both runs here and the release verification all write verify-sql.log, so each
  # overwrote the evidence of the one before — and this script's own diagnosis then read another run.
  "$VERIFY" "$KEY" --runs 1 --no-manifest --log-label "$1" --timeout "$TIMEOUT" "${TC_ARGS[@]+"${TC_ARGS[@]}"}" > "$_out" 2>&1
  _rc=$?
  sed -n '/^  runs :/p' "$_out" | sed "s/^/  $1/"
  return $_rc
}

install_build "$PREFIX_URL" "$PREFIX_VER" prefix || {
  record inconclusive "the pre-fix build ($PREFIX_VER) did not install; see $RUN_DIR/install-prefix.log"
  exit 3; }

run_case prefix; PRC=$?
case $PRC in
  1) PREFIX_OUTCOME=FAIL ;;
  0) PREFIX_OUTCOME=PASS ;;
  *) PREFIX_OUTCOME=blocked ;;
esac

if [ "$WITH_DEBUG" = 1 ]; then
  printf '  debug   : %s\n' "$DEBUG_URL"
  STAMP="$RUN_DIR/.debug-stamp"; : > "$STAMP"
  if install_build "$DEBUG_URL" "$FIXED_VER" debug debug; then
    run_case debug; DRC=$?
    _dlog="$RUN_DIR/verify-sql.debug.log"
    _marker=$(engine_markers "$_dlog" "$STAMP")
    if [ -n "$_marker" ]; then
      printf '  *** the debug engine reported an assertion or a crash ***\n    %s\n' "$_marker"
      record_debug true assert "the debug build tripped an assertion or crashed while running this testcase" "$_marker" "$FIXED_VER" "$_dlog"
    elif [ "$DRC" = 0 ]; then
      record_debug true clean "ran clean on the debug build ($FIXED_VER): no assertion, output matches the release answer" "" "$FIXED_VER" "$_dlog"
    elif [ "$DRC" = 1 ]; then
      record_debug true differs "output differs from the release answer on the debug build, with no assertion — debug-only messages are one legitimate cause" "" "$FIXED_VER" "$_dlog"
    else
      record_debug false inconclusive "the debug run was blocked (verify-run exit $DRC)" "" "$FIXED_VER" "$_dlog"
    fi
  else
    record_debug false inconclusive "the debug build ($FIXED_VER) did not install; see $RUN_DIR/install-debug.log" "" "$FIXED_VER" ""
  fi
fi

swap_restore || exit 3
run_case fixed; FRC=$?
case $FRC in
  0) FIXED_OUTCOME=PASS ;;
  1) FIXED_OUTCOME=FAIL ;;
  *) FIXED_OUTCOME=blocked ;;
esac

printf '  prefix %s → fixed %s\n' "$PREFIX_OUTCOME" "$FIXED_OUTCOME"
if [ "$PREFIX_OUTCOME" = FAIL ] && [ "$FIXED_OUTCOME" = PASS ]; then
  record confirmed "pre-fix $PREFIX_VER FAIL → fixed $FIXED_VER PASS (one run each)"
  printf '  recorded: verify.fail_to_pass.status=confirmed\n'
  printf '  NOT decided (yours): that %s really predates the fix, and whether one run is enough for a timing-sensitive repro\n' "$PREFIX_VER"
  exit 0
fi
if [ "$FIXED_OUTCOME" != PASS ]; then
  record inconclusive "the fixed build $FIXED_VER did not pass ($FIXED_OUTCOME) — either the answer is wrong or this machine is not in the state the answer was generated in; the pre-fix run said $PREFIX_OUTCOME"
  printf '  recorded: status=inconclusive — the fixed build did not pass, so the pre-fix result proves nothing.\n'
  printf '  Read %s before touching the .sql.\n' "$RUN_DIR/failpass-fixed.out"
  exit 1
fi
record contradicted "the testcase PASSED on the pre-fix build $PREFIX_VER — it does not detect this bug"
printf '  recorded: status=contradicted — the testcase passes without the fix, so it has no regression value.\n'
printf '  Either it never reaches the fix path (size the data / force the plan) or %s already contains the fix.\n' "$PREFIX_VER"
printf '  A timing-sensitive race may legitimately not reproduce: that is best_effort, which is YOUR call —\n'
printf '  it needs verify.fail_to_pass.note plus review.failpass_approved, and only then does submit unblock.\n'
exit 1
