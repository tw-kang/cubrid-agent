#!/bin/bash
# Behavioural test for hint-missing-helper.sh — the hook that answers "why is this helper not here?".
#
# Dev-only, run by check-invariants.sh. Deterministic and offline: a throwaway $HOME and a throwaway
# plugin root, so it never reads the real ~/.cubrid-agent.
#
# The contract every case also checks: this hook NEVER blocks. It is a hint on a command that is about
# to fail on its own, so a deny would only cost the rest of a compound command — and the parse has no
# notion of quoting, so an over-eager match must stay cheap.
set -u

HOOK=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/hint-missing-helper.sh
[ -f "$HOOK" ] || { echo "test-hint-missing-helper: hook not found at $HOOK" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export CLAUDE_PLUGIN_ROOT="$T/plugin"
BIN="$HOME/.cubrid-agent/bin"
SRC="$CLAUDE_PLUGIN_ROOT/skills/qa/setup-cubrid-agent/bin"
mkdir -p "$BIN" "$SRC"

# Installed: one helper. Shipped by the plugin: that one plus a newer one setup has not copied yet —
# the case the helpers' own "unknown flag" hint can never reach, because there is no process to print it.
printf '#!/bin/bash\n' > "$BIN/verify-run.sh";  chmod +x "$BIN/verify-run.sh"
printf '#!/bin/bash\n' > "$SRC/verify-run.sh"
printf '#!/bin/bash\n' > "$SRC/render-report.sh"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }

fire() {  # fire <command> -> sets OUT, RC
  OUT=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$HOOK" 2>&1)
  RC=$?
}
run() {  # run <name> <hint|silent> <fragment the hint must contain> <command>
  fire "$4"
  if [ "$RC" -ne 0 ]; then note_fail "$1: hook exited $RC — it must never block"; return; fi
  if [ "$2" = silent ]; then
    [ -z "$OUT" ] && T_PASS=$((T_PASS+1)) || note_fail "$1: expected no hint, got \"$OUT\""
  else
    printf '%s' "$OUT" | grep -qF -- "$3" && T_PASS=$((T_PASS+1)) \
      || note_fail "$1: the hint never says \"$3\" (got: $OUT)"
  fi
}
never_blocks() {  # never_blocks <name> <command>  — for input whose hint is not worth pinning
  fire "$2"
  [ "$RC" -eq 0 ] && T_PASS=$((T_PASS+1)) || note_fail "$1: hook exited $RC — it must never block"
}

# --- invoked and missing: say which, and why -----------------------------------------------------
run "missing helper, shipped by the plugin" hint "render-report.sh" \
    "~/.cubrid-agent/bin/render-report.sh CBRD-99999"
run "  ... and names the fix"               hint "/setup-cubrid-agent" \
    "~/.cubrid-agent/bin/render-report.sh CBRD-99999"
run "  ... and says the command will fail"  hint "will fail" \
    "~/.cubrid-agent/bin/render-report.sh CBRD-99999"

# Every spelling of the path a skill or a human actually types must resolve, or the hint goes silent
# exactly when it is needed.
run "\$HOME spelling"        hint "render-report.sh" "\$HOME/.cubrid-agent/bin/render-report.sh CBRD-1"
run "\${HOME} spelling"      hint "render-report.sh" "\${HOME}/.cubrid-agent/bin/render-report.sh CBRD-1"
run "double-quoted path"     hint "render-report.sh" "\"\$HOME/.cubrid-agent/bin/render-report.sh\" CBRD-1"
run "single-quoted path"     hint "render-report.sh" "'$BIN/render-report.sh' CBRD-1"
run "absolute path"          hint "render-report.sh" "$BIN/render-report.sh CBRD-1"
run "run through bash"       hint "render-report.sh" "bash ~/.cubrid-agent/bin/render-report.sh CBRD-1"
run "after env assignments"  hint "render-report.sh" "CUBRID_TESTCASES=/tmp/x ~/.cubrid-agent/bin/render-report.sh CBRD-1"
run "after a separator"      hint "render-report.sh" "cd /tmp && ~/.cubrid-agent/bin/render-report.sh CBRD-1"

# A name the plugin does not ship at all is a typo, not a stale install — different fix, different text.
run "helper that does not exist anywhere" hint "does not ship" \
    "~/.cubrid-agent/bin/rendre-report.sh CBRD-99999"

# Without the plugin root (npx skills channel, or the plugin uninstalled) the two causes are
# indistinguishable, so the hint must not assert either one: claiming "the plugin ships it" about a name
# nobody ships sends the reader to re-run setup forever.
( unset CLAUDE_PLUGIN_ROOT
  _o=$(printf '{"tool_input":{"command":"~/.cubrid-agent/bin/whatever.sh"}}' | bash "$HOOK" 2>&1) || exit 1
  printf '%s' "$_o" | grep -qF 'The plugin ships it' && exit 1
  printf '%s' "$_o" | grep -qF '/setup-cubrid-agent' || exit 1
  exit 0 )
[ $? -eq 0 ] && T_PASS=$((T_PASS+1)) \
  || note_fail "no plugin root: the hint states a cause it cannot know, or names no fix"

# --- must stay silent -------------------------------------------------------------------------------
run "installed helper"     silent "" "~/.cubrid-agent/bin/verify-run.sh CBRD-99999 --runs 3"
run "unrelated command"    silent "" "git status --short"
run "the directory itself" silent "" "ls ~/.cubrid-agent/bin/"
# The recovery this hint prescribes names a path that is legitimately absent. Hinting at it would be
# noise; denying it would trap the reader between a hook that says "install it" and one that objects.
run "installing the helper" silent "" "install -m 755 skills/qa/setup-cubrid-agent/bin/render-report.sh ~/.cubrid-agent/bin/render-report.sh"
run "copying it"            silent "" "cp src/render-report.sh \$HOME/.cubrid-agent/bin/render-report.sh"
run "diffing against it"    silent "" "diff -q ~/.cubrid-agent/bin/render-report.sh skills/qa/setup-cubrid-agent/bin/render-report.sh"

# --- never blocks, whatever the input --------------------------------------------------------------
# The parse has no notion of quoting, so a helper path inside a commit message or a heredoc can read as
# an invocation. That is accepted — but only because it costs a sentence. Pin the "only" part.
never_blocks "path quoted inside a commit message" \
    "git commit -m \"note
~/.cubrid-agent/bin/render-report.sh now works\""
never_blocks "path inside a heredoc body" \
    "cat > run.sh <<EOF
~/.cubrid-agent/bin/render-report.sh CBRD-1
EOF"
never_blocks "a glob in the command" "ls * ; ~/.cubrid-agent/bin/render-report.sh CBRD-1"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'hint-missing-helper: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'hint-missing-helper: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
