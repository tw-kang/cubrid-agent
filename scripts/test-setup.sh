#!/bin/bash
# Behavioural test for setup.sh — where it provisions the testcases clone.
#
# Dev-only, run by check-invariants.sh. Offline: `git clone` is stubbed, so no case can reach the
# network whether or not the fix is in place. Nothing outside a throwaway $HOME is touched.
#
# What it pins: setup provisions the clone the part-skills will read — the override path when one is
# set, the default otherwise — creates neither the other one, records it in env.sh without overruling
# the caller, and re-runs clean. Why the override exists is deployment.md D7.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")/../skills/qa/setup-cubrid-agent/scripts" && pwd)/setup.sh
[ -f "$SRC" ] || { echo "test-setup: script not found at $SRC" >&2; exit 1; }
REAL_GIT=$(command -v git) || { echo "test-setup: git is required." >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
pass() { T_PASS=$((T_PASS+1)); }

# A git whose `clone` records its target and makes an empty repo instead of fetching. Without it the
# reverted script clones the real cubrid-testcases (~17k files) into the default path: the run would
# hang or fail for an unrelated reason, and "default path untouched" would pass spuriously, since git
# removes the target of a failed clone. It also makes the clone TARGET observable, which is the thing
# under test — a stub that only blocked the network could not tell the two paths apart.
mkdir -p "$T/bin"
cat > "$T/bin/git" <<STUB
#!/bin/sh
if [ "\$1" = clone ]; then
  for a in "\$@"; do case "\$a" in -*|clone|http*|git@*) ;; *) d=\$a ;; esac; done
  printf '%s\n' "\$d" >> "\$CLONE_LOG"
  exec "$REAL_GIT" init -q "\$d"
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$T/bin/git"
PATH="$T/bin:$PATH"; export PATH

fork_url() { git -C "$1" remote get-url fork 2>/dev/null; }
run_setup() {  # run_setup <home> [env assignments...]  — CLONE_LOG is per-run
  CLONE_LOG="$1/cloned"; export CLONE_LOG
  # -u CUBRID_TESTCASES so the no-override case really is one. Inheriting the operator's export would
  # point the run at their real clone — outside the throwaway $HOME the trap reclaims, and on exactly
  # the machine this behaviour exists for. A later assignment in "$@" still sets it for the cases that want it.
  env -u CUBRID_TESTCASES HOME="$1" CUBRID_GH_FORK=testowner "${@:2}" bash "$SRC" >"$1/out" 2>&1
}

# ── override set, nothing provisioned yet: the clone goes to the named path ───────────────────────
H1="$T/h1"; OVR="$T/separate-tc"; mkdir -p "$H1"
run_setup "$H1" CUBRID_TESTCASES="$OVR"
_rc=$?
[ "$_rc" -eq 0 ] && pass || note_fail "fresh override run exits cleanly: setup.sh exited $_rc — see $H1/out"

grep -qx "$OVR" "$H1/cloned" 2>/dev/null && pass \
  || note_fail "clone target is the override: \$CUBRID_TESTCASES was never cloned (log: $(tr '\n' ' ' < "$H1/cloned" 2>/dev/null))"

# The default path is a human's working tree on the machines this override exists for. Not created.
[ -e "$H1/cubrid-testcases" ] \
  && note_fail "default path untouched: setup created \$HOME/cubrid-testcases even though the override was set" \
  || pass

case "$(fork_url "$OVR")" in
  *testowner/cubrid-testcases*) pass ;;
  *) note_fail "fork remote on the override clone: got \"$(fork_url "$OVR")\"" ;;
esac

# Assert env.sh by sourcing it, not by grepping for a line: a missing line then fails here too,
# instead of quietly skipping the assertion that matters.
_seen=$(env -u CUBRID_TESTCASES HOME="$H1" sh -c '. "$0"/.cubrid-agent/env.sh >/dev/null 2>&1; printf %s "${CUBRID_TESTCASES:-}"' "$H1")
[ "$_seen" = "$OVR" ] && pass \
  || note_fail "env.sh carries the clone: sourcing it yields \"$_seen\", expected $OVR — a session that sources it would read the default path"

# It records what setup found; it must not overrule a session that already chose a clone.
_seen=$(HOME="$H1" CUBRID_TESTCASES=/elsewhere sh -c '. "$0"/.cubrid-agent/env.sh >/dev/null 2>&1; printf %s "${CUBRID_TESTCASES:-}"' "$H1")
[ "$_seen" = /elsewhere ] && pass \
  || note_fail "env.sh defers to the caller: sourcing it turned /elsewhere into \"$_seen\""

# ── override set and already a clone: nothing is cloned at all ────────────────────────────────────
H2="$T/h2"; OVR2="$T/existing-tc"; mkdir -p "$H2"; git init -q "$OVR2"
run_setup "$H2" CUBRID_TESTCASES="$OVR2"
grep -q 'cubrid-testcases' "$H2/cloned" 2>/dev/null \
  && note_fail "existing override clone is left alone: setup cloned over it" \
  || pass
case "$(fork_url "$OVR2")" in
  *testowner/cubrid-testcases*) pass ;;
  *) note_fail "fork remote on the existing override clone: got \"$(fork_url "$OVR2")\"" ;;
esac

# ── no override: the default path is still the clone ──────────────────────────────────────────────
H3="$T/h3"; mkdir -p "$H3"
run_setup "$H3"
grep -qx "$H3/cubrid-testcases" "$H3/cloned" 2>/dev/null && pass \
  || note_fail "no override: ~/cubrid-testcases was not the clone target (log: $(tr '\n' ' ' < "$H3/cloned" 2>/dev/null))"
case "$(fork_url "$H3/cubrid-testcases")" in
  *testowner/cubrid-testcases*) pass ;;
  *) note_fail "no override: ~/cubrid-testcases has no 'fork' remote (got \"$(fork_url "$H3/cubrid-testcases")\")" ;;
esac

_seen=$(env -u CUBRID_TESTCASES HOME="$H3" sh -c '. "$0"/.cubrid-agent/env.sh >/dev/null 2>&1; printf %s "${CUBRID_TESTCASES:-}"' "$H3")
[ "$_seen" = "$H3/cubrid-testcases" ] && pass \
  || note_fail "no override: env.sh yields \"$_seen\", expected the default path"

# setup.sh's header states it is idempotent and never touches an existing clone, so a re-run on a
# provisioned machine must fetch nothing at all.
: > "$H3/cloned"
run_setup "$H3"
grep -q . "$H3/cloned" 2>/dev/null \
  && note_fail "re-run provisions nothing new: it cloned $(tr '\n' ' ' < "$H3/cloned")" \
  || pass

# ── plugin auto-update: the flag, and the registry that is not ours ──────────────────────────────
# A teammate who installs once and never updates keeps running the commit they first got. Measured:
# settings.json alone is enough — Claude Code copies the flag into known_marketplaces.json itself.
H4="$T/h4"; mkdir -p "$H4/.claude/plugins"
printf '{"extraKnownMarketplaces":{"cubrid-agent":{"source":{"source":"github","repo":"tw-kang/cubrid-agent"}}}}\n' > "$H4/.claude/settings.json"
printf '{"cubrid-agent":{"source":{"source":"github","repo":"tw-kang/cubrid-agent"}}}\n' > "$H4/.claude/plugins/known_marketplaces.json"
_reg_before=$(cat "$H4/.claude/plugins/known_marketplaces.json")
run_setup "$H4"
[ "$(jq -r '.extraKnownMarketplaces["cubrid-agent"].autoUpdate' "$H4/.claude/settings.json" 2>/dev/null)" = true ] && pass \
  || note_fail "auto-update: settings.json was not set"
# known_marketplaces.json belongs to Claude Code — setup reads nothing from it and writes nothing to it.
[ "$(cat "$H4/.claude/plugins/known_marketplaces.json")" = "$_reg_before" ] && pass \
  || note_fail "auto-update: setup modified known_marketplaces.json, which Claude Code owns"
[ -e "$H4/.claude/plugins/known_marketplaces.json.bak" ] \
  && note_fail "auto-update: setup left a backup inside Claude Code's plugins directory" || pass

# No marketplace entry means this channel is not in use: nothing to set, and no file to invent.
H5="$T/h5"; mkdir -p "$H5/.claude"
printf '{}\n' > "$H5/.claude/settings.json"
run_setup "$H5"
grep -q 'nothing to set' "$H5/out" 2>/dev/null && pass \
  || note_fail "auto-update: with no marketplace entry it should say nothing to set (got: $(grep -i 'auto-update' "$H5/out" | head -1))"
[ -f "$H5/.claude/plugins/known_marketplaces.json" ] \
  && note_fail "auto-update: it created a registry file that Claude Code owns" || pass

# A write that fails must be reported as a TODO. The first version chained cp && mv && printf, so a
# failed cp printed nothing, the caller read an empty string and announced success.
H6="$T/h6"; mkdir -p "$H6/.claude"
printf '{"extraKnownMarketplaces":{"cubrid-agent":{"source":{"source":"github","repo":"tw-kang/cubrid-agent"}}}}\n' > "$H6/.claude/settings.json"
chmod 500 "$H6/.claude"
run_setup "$H6"
chmod 700 "$H6/.claude"
grep -q 'could not enable plugin auto-update' "$H6/out" 2>/dev/null && pass \
  || note_fail "auto-update: an unwritable settings.json must report a TODO (got: $(grep -i 'auto-update' "$H6/out" | head -1))"
grep -q 'auto-update enabled' "$H6/out" 2>/dev/null \
  && note_fail "auto-update: it reported success after failing to write" || pass

# The pull closes the ten-minute gap for the run that just installed the plugin.
H7="$T/h7"; mkdir -p "$H7/.claude" "$T/bin"
printf '{}\n' > "$H7/.claude/settings.json"
cat > "$T/bin/claude" <<'CLAUDESTUB'
#!/bin/sh
printf '%s\n' "$*" >> "$CLAUDE_LOG"
exit 0
CLAUDESTUB
chmod +x "$T/bin/claude"
CLAUDE_LOG="$H7/claude-calls"; export CLAUDE_LOG; : > "$CLAUDE_LOG"
run_setup "$H7"
grep -q 'plugin update cubrid-agent@cubrid-agent' "$H7/claude-calls" 2>/dev/null && pass \
  || note_fail "setup does not pull the plugin (calls: $(tr '\n' ';' < "$H7/claude-calls" 2>/dev/null))"
unset CLAUDE_LOG

if [ "$T_FAIL" -eq 0 ]; then
  printf 'setup: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'setup: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
