#!/bin/bash
# Shared build-swap machinery. SOURCED by failpass-run.sh and debug-check.sh, never run on its own.
#
# Both callers do the same dangerous thing: install a different CUBRID, run one testcase, put the
# original back.
#
# Contract: the caller defines CUB (the CUBRID install dir), INSTALLER (CTP's run_cubrid_install) and
# RUN_DIR (where install logs go) BEFORE sourcing this, and may define a `swap_record_failure <note>`
# function — swap_restore calls it when the machine is left on the wrong build, so the manifest says so
# even when nothing but an EXIT trap is still running.

# A bare version is accepted as well as a URL, because that is what an issue comment names. It needs
# the FULL version including the commit hash — the truncated form 404s.
# The public archive is the default: it keeps a build until develop is released, while the internal
# store prunes, and a fail→pass check needs an OLD build. CUBRID_BUILD_BASE points elsewhere.
# The contract, asserted rather than described: a caller that sources this before setting them would
# otherwise fail later, inside an install, with a message about something else.
: "${CUB:?build-swap.sh: the caller must set CUB (the CUBRID install dir) before sourcing}"
: "${INSTALLER:?build-swap.sh: the caller must set INSTALLER (CTP run_cubrid_install) before sourcing}"
: "${RUN_DIR:?build-swap.sh: the caller must set RUN_DIR (where install logs go) before sourcing}"

BUILD_BASE=${CUBRID_BUILD_BASE:-https://ftp.cubrid.org/CUBRID_Engine/nightly/daily_build}

# One builder, two entry points: the release and debug artifacts differ only by that suffix, and the
# pass-a-URL-through case is the same rule for both.
to_url() {  # to_url <version|url> [artifact suffix]
  case "$1" in
    http://*|https://*|/*) printf '%s' "$1" ;;
    *) printf '%s/%s/drop/CUBRID-%s-Linux.x86_64%s.sh' "$BUILD_BASE" "$1" "$1" "${2:-}" ;;
  esac
}
# The debug twin sits next to the release one under the same version directory.
debug_url() { to_url "$1" -debug; }
url_version() { printf '%s' "$1" | grep -oE 'CUBRID-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+' | sed 's/^CUBRID-//' | head -1; }
reachable() {
  case "$1" in
    /*) [ -f "$1" ] ;;
    *)  command -v curl >/dev/null 2>&1 || return 0   # cannot check; let the installer report it
        curl -fsI --max-time 20 "$1" >/dev/null 2>&1 ;;
  esac
}

installed_version() {
  [ -x "$CUB/bin/cubrid_rel" ] || return 1
  "$CUB/bin/cubrid_rel" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+' | head -1
}
# release | debug. A debug build reports the SAME version as its release twin, so for a debug swap this
# is the only thing that can be asserted after the install — the version check would pass on a machine
# that never left release, and the run would then report a verdict about a build nobody tested.
installed_build_type() {
  [ -x "$CUB/bin/cubrid_rel" ] || return 1
  "$CUB/bin/cubrid_rel" 2>/dev/null | grep -oiE '(release|debug) build' | head -1 \
    | grep -oiE 'release|debug' | tr '[:upper:]' '[:lower:]'
}

install_build() {  # install_build <url> <expected version or ""> <label> [expected type]
  local _log="$RUN_DIR/install-$3.log"
  local _before=$(installed_version) || _before=""
  printf '  install %s: %s\n' "$3" "$1"
  sh "$INSTALLER" "$1" > "$_log" 2>&1
  # run_cubrid_install can return 0 having failed, so the binary is the authority. Version: exact when
  # the URL names one, otherwise the weaker fact that still has to hold — it CHANGED.
  local _got=$(installed_version) || _got=""
  local _why=""
  if [ -n "$2" ]; then
    [ "$_got" = "$2" ] || _why="cubrid_rel reports \"${_got:-nothing}\", expected \"$2\""
  else
    [ -n "$_got" ] || _why="cubrid_rel reports nothing"
    [ -z "$_why" ] && [ "$_got" = "$_before" ] && _why="cubrid_rel still reports \"$_got\" — the URL names no version to check against, and nothing changed, so nothing was installed"
  fi
  # Type, when the caller asks for one: this is what catches a no-op debug install, whose version is
  # identical to the release build that is already there.
  if [ -z "$_why" ] && [ -n "${4:-}" ]; then
    local _gt=$(installed_build_type) || _gt=""
    [ "$_gt" = "$4" ] || _why="cubrid_rel reports a \"${_gt:-unknown}\" build, expected \"$4\" (the version matches either way, so nothing was installed)"
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
  printf '  now on %s%s\n' "${_got:-unknown}" "$([ -n "${4:-}" ] && printf ' (%s)' "$4")"
  return 0
}

# ── the restore, which must happen even when nothing else does ────────────────────────────────────
swap_baseline_ver=""; swap_baseline_url=""; swap_baseline_type=""; swap_stuck_label="WRONG"
swap_restored=0; swap_restore_failed=0
swap_set_baseline() {  # swap_set_baseline <version> <url> <type or ""> <label for the stuck message>
  swap_baseline_ver=$1; swap_baseline_url=$2; swap_baseline_type=$3; swap_stuck_label=$4
}
swap_restore() {
  [ "$swap_restored" = 1 ] && return 0
  # A second attempt from the EXIT trap would repeat a minutes-long install that already failed, and
  # bury the recovery command it printed under a duplicate of the same failure.
  [ "$swap_restore_failed" = 1 ] && return 1
  local _cur _curt
  _cur=$(installed_version) || _cur=""
  _curt=$(installed_build_type) || _curt=""
  if [ "$_cur" = "$swap_baseline_ver" ] && { [ -z "$swap_baseline_type" ] || [ "$_curt" = "$swap_baseline_type" ]; }; then
    swap_restored=1; return 0
  fi
  printf '  restoring %s%s\n' "$swap_baseline_ver" "$([ -n "$swap_baseline_type" ] && printf ' (%s)' "$swap_baseline_type")"
  if install_build "$swap_baseline_url" "$swap_baseline_ver" restore "$swap_baseline_type"; then
    swap_restored=1; return 0
  fi
  # The loudest failure here is: the machine is on the wrong engine and every later verify is
  # meaningless. Name the build and the command, not just "restore failed".
  printf '\n  *** THIS MACHINE IS STILL ON A %s BUILD (%s%s) ***\n' \
    "$swap_stuck_label" "${_cur:-unknown}" "$([ -n "$_curt" ] && printf ', %s' "$_curt")"
  printf '  Restore it before any further verification:\n    sh %s %s\n\n' "$INSTALLER" "$swap_baseline_url"
  command -v swap_record_failure >/dev/null 2>&1 && \
    swap_record_failure "RESTORE FAILED — machine left on ${_cur:-unknown}${_curt:+ ($_curt)}; $swap_baseline_ver must be reinstalled before any verify result means anything"
  swap_restore_failed=1
  return 1
}

# ── engine markers ────────────────────────────────────────────────────────────────────────────────
# Only ENGINE-owned output is searched, never captured stdout: a testcase whose own output contains
# "assert" would otherwise be recorded as tripping one. `abort` is not a marker — "transaction
# aborted" is ordinary SQL output.
engine_markers() {  # engine_markers <ctp log> [stamp file for server logs]
  local _m=""
  _m=$(grep -hiE 'assert|Segmentation fault|core dumped|SIGSEGV|SIGABRT' "$1" 2>/dev/null | head -1)
  if [ -z "$_m" ] && [ -n "${2:-}" ] && [ -d "$CUB/log" ]; then
    _m=$(find "$CUB/log" -type f -name '*.err' -newer "$2" 2>/dev/null \
         | xargs -r grep -hiE 'assert|Segmentation fault|core dumped|SIGSEGV|SIGABRT' 2>/dev/null | head -1)
  fi
  printf '%s' "$_m"
}

# verify.debug has one shape and two writers (debug-check.sh, and the debug half of a combined
# fail→pass run), so the shape lives here. `checked` says whether the debug run actually happened; the
# submit gate reads that rather than inferring it from silence.
record_debug() {  # record_debug <checked true|false> <result> <note> <marker> <build> <log>
  command -v jq >/dev/null 2>&1 || { printf '  (jq missing — verify.debug NOT recorded)\n'; return 0; }
  [ -f "$MANIFEST" ] || printf '{}\n' > "$MANIFEST"
  jq --argjson c "$1" --arg r "$2" --arg n "$3" --arg m "$4" --arg b "$5" --arg l "$6" \
     '.verify.debug = ({checked: $c, result: $r, type: "debug", build: $b, note: $n}
        | (if $m != "" then . + {marker: $m} else . end)
        | (if $l != "" then . + {log: $l} else . end))' \
     "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST" || rm -f "$MANIFEST.tmp"
}
