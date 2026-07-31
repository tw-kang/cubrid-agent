#!/bin/bash
# Prove the testcase catches the bug: run it on a PRE-FIX build (must FAIL), then on the fixed build
# (must PASS) — and always put the fixed build back, even when something in between dies.
# Installed to ~/.cubrid-agent/bin/ by /setup-cubrid-agent.
#
# Why this is a script (DP6): the sequence is fully determined — install, run, install, run — and by
# hand it cost 6 model turns and ~12 minutes, paid once per review round instead of once per TC
# (CUBRIDQA-1487). The turns are not the dangerous part. Every step in the middle can fail, and a prose
# sequence that dies after the first install leaves the machine on a PRE-FIX build with nothing
# recording that fact — after which every later verify quietly runs against an engine that still has
# the bug, and its green result means nothing. So here: the fixed build's URL is proven reachable
# BEFORE the first install, the restore is an EXIT trap rather than a later step, and the installed
# version is asserted after every install (run_cubrid_install can exit 0 having failed).
#
# It does NOT decide: whether the build you named is actually pre-fix (that is the fix commit against
# the build's date — your call), nor whether a timing-sensitive repro deserves `best_effort`. It writes
# `confirmed` only for FAIL-then-PASS; anything else is recorded as what it was, which the submit gate
# treats as not satisfied.
#
# usage: failpass-run.sh CBRD-XXXXX --prefix-build <url|version> [--fixed-build <url|version>]
#                                   [--tc-path PATH] [--timeout SECONDS]
set -u

USAGE='usage: failpass-run.sh CBRD-XXXXX --prefix-build <url|version> [--fixed-build <url|version>] [--tc-path PATH] [--timeout SECONDS]'
KEY=""; PREFIX_IN=""; FIXED_IN=""; TCPATH=""; TIMEOUT=900
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix-build) PREFIX_IN="${2:?$USAGE}"; shift 2 ;;
    --fixed-build)  FIXED_IN="${2:?$USAGE}"; shift 2 ;;
    --tc-path)      TCPATH="${2:?$USAGE}"; shift 2 ;;
    --timeout)      TIMEOUT="${2:?$USAGE}"; shift 2 ;;
    -h|--help)      printf '%s\n' "$USAGE"; exit 0 ;;
    -*)             printf 'failpass-run: unknown option: %s\n%s\n  If that is a documented flag, this installed copy is stale (the plugin updated, ~/.cubrid-agent/bin did not) — run /setup-cubrid-agent to refresh it.\n' "$1" "$USAGE" >&2; exit 1 ;;
    *)              KEY=$(printf '%s' "$1" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'failpass-run: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }
[ -n "$PREFIX_IN" ] || { printf 'failpass-run: --prefix-build is required (a build from before the fix but after the feature that introduced the bug).\n%s\n' "$USAGE" >&2; exit 1; }

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
VERIFY="$SELF_DIR/verify-run.sh"
[ -x "$VERIFY" ] || { printf 'failpass-run: verify-run.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$VERIFY" >&2; exit 1; }

# shellcheck disable=SC1090
[ -f "$HOME/.cubrid-agent/env.sh" ] && . "$HOME/.cubrid-agent/env.sh"
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

installed_version() {
  [ -x "$CUB/bin/cubrid_rel" ] || return 1
  "$CUB/bin/cubrid_rel" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+' | head -1
}
# A bare version is accepted as well as a URL, because that is what an issue comment names. The shape
# is the build server's, and it needs the FULL version including the commit hash: the truncated form
# (11.5.0.2300 without -04192d6) 404s.
BUILD_BASE=${CUBRID_BUILD_BASE:-http://192.168.1.91:8080/REPO_ROOT/store_01}
to_url() {
  case "$1" in
    http://*|https://*|/*) printf '%s' "$1" ;;
    *) printf '%s/%s/drop/CUBRID-%s-Linux.x86_64.sh' "$BUILD_BASE" "$1" "$1" ;;
  esac
}
url_version() { printf '%s' "$1" | grep -oE 'CUBRID-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+' | sed 's/^CUBRID-//' | head -1; }
reachable() {
  case "$1" in
    /*) [ -f "$1" ] ;;
    *)  command -v curl >/dev/null 2>&1 || return 0   # cannot check; let the installer report it
        curl -fsI --max-time 20 "$1" >/dev/null 2>&1 ;;
  esac
}

FIXED_VER=$(installed_version) || FIXED_VER=""
[ -n "$FIXED_VER" ] || { printf 'failpass-run: no CUBRID build under %s — the fixed build must already be installed (it is what gets restored).\n' "$CUB" >&2
                         record inconclusive "no build installed at start; nothing was swapped"; exit 3; }

PREFIX_URL=$(to_url "$PREFIX_IN"); PREFIX_VER=$(url_version "$PREFIX_URL")
FIXED_URL=$(to_url "${FIXED_IN:-$FIXED_VER}")

# Order matters: BOTH URLs are proven before anything is installed. Discovering that the fixed build
# has been pruned from the server *after* installing the pre-fix one is how a machine gets stranded —
# and build pruning is normal here, so this is not a theoretical case.
for _p in "prefix:$PREFIX_URL" "fixed:$FIXED_URL"; do
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

# ── install, with the restore guaranteed by a trap rather than by reaching the end ────────────────
install_build() {  # install_build <url> <expected version or ""> <label>
  _log="$RUN_DIR/install-$3.log"
  _before=$(installed_version) || _before=""
  printf '  install %s: %s\n' "$3" "$1"
  sh "$INSTALLER" "$1" > "$_log" 2>&1
  # run_cubrid_install can return 0 having failed, so the binary is the authority, not the exit code.
  # Two assertions, because `[ -n "$2" ]` alone silently disables the check whenever the URL carries no
  # parsable version — a local installer path, or a filename that is not CUBRID-<ver>-Linux…. In that
  # case the run continued on the FIXED build and reported the testcase as `contradicted`: a false "this
  # TC has no regression value" verdict, which is worse than any error. So: exact version when the URL
  # names one, and otherwise the weaker fact that still has to hold — the installed version CHANGED.
  _got=$(installed_version) || _got=""
  if [ -n "$2" ]; then
    _why=""; [ "$_got" = "$2" ] || _why="cubrid_rel reports \"${_got:-nothing}\", expected \"$2\""
  else
    _why=""
    [ -n "$_got" ] || _why="cubrid_rel reports nothing"
    [ -z "$_why" ] && [ "$_got" = "$_before" ] && _why="cubrid_rel still reports \"$_got\" — the URL names no version to check against, and nothing changed, so nothing was installed"
  fi
  if [ -n "$_why" ]; then
    printf '  install %s FAILED — %s. Log: %s\n' "$3" "$_why" "$_log"
    grep -m3 '\[ERROR\]' "$_log" 2>/dev/null | sed 's/^/    /'
    return 1
  fi
  # sql.conf does not build the locale library, and a missing one fails DB startup on the fresh install.
  if [ ! -f "$CUB/lib/libcubrid_all_locales.so" ] && [ -x "$CUB/bin/make_locale.sh" ]; then
    sh "$CUB/bin/make_locale.sh" -t 64bit >> "$_log" 2>&1 \
      || printf '  warning: make_locale.sh failed (see %s) — DB startup may fail\n' "$_log"
  fi
  printf '  now on %s\n' "${_got:-unknown}"
  return 0
}

RESTORED=0; RESTORE_FAILED=0
restore_fixed() {
  [ "$RESTORED" = 1 ] && return 0
  # A second attempt from the EXIT trap would just repeat a minutes-long install that already failed,
  # and bury the recovery command it printed under a duplicate of the same failure.
  [ "$RESTORE_FAILED" = 1 ] && return 1
  _cur=$(installed_version) || _cur=""
  [ "$_cur" = "$FIXED_VER" ] && { RESTORED=1; return 0; }
  printf '  restoring the fixed build %s\n' "$FIXED_VER"
  if install_build "$FIXED_URL" "$FIXED_VER" restore; then RESTORED=1; return 0; fi
  # The loudest failure this script has: the machine is on a pre-fix engine and every later verify
  # would be meaningless. Say the version and the command, not just "restore failed".
  printf '\n  *** THIS MACHINE IS STILL ON A PRE-FIX BUILD (%s) ***\n' "${_cur:-unknown}"
  printf '  Restore it before any further verification:\n    sh %s %s\n\n' "$INSTALLER" "$FIXED_URL"
  record inconclusive "RESTORE FAILED — machine left on ${_cur:-unknown}; the fixed build $FIXED_VER must be reinstalled before any verify result means anything"
  RESTORE_FAILED=1
  return 1
}
# NOT silenced. The first version sent the trap's output to /dev/null so the normal path would not print
# the restore twice — but on the path where the trap is the ONLY caller (Ctrl-C during the pre-fix run)
# that threw away the loudest message this script has, the one naming the stranded build and the command
# to fix it. Duplicate output is already prevented by restore_fixed's own RESTORED/RESTORE_FAILED flags.
trap 'restore_fixed || true' EXIT
trap 'printf "\n  interrupted — restoring the fixed build before exiting\n"; restore_fixed || true; exit 130' INT TERM

printf '[failpass] %s\n  fixed  : %s\n  prefix : %s\n' "$KEY" "$FIXED_VER" "${PREFIX_VER:-$PREFIX_URL}"

TC_ARGS=()
[ -n "$TCPATH" ] && TC_ARGS=(--tc-path "$TCPATH")
run_case() {  # run_case <label> -> 0 pass, 1 fail(mismatch), 3 blocked
  _out="$RUN_DIR/failpass-$1.out"
  # --no-manifest: a deliberate pre-fix failure must never become the record the submit gate reads.
  "$VERIFY" "$KEY" --runs 1 --no-manifest --timeout "$TIMEOUT" "${TC_ARGS[@]+"${TC_ARGS[@]}"}" > "$_out" 2>&1
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

restore_fixed || exit 3
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
