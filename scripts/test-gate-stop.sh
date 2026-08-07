#!/bin/bash
# Behavioural test for gate-stop.sh — the reminder that fires when a TC run stopped with gates open.
#
# Dev-only, run by check-invariants.sh. Offline: every case builds manifests under a throwaway $HOME,
# and the hook only reads files.
#
# What it pins, in the two directions a reminder gets it wrong:
#   fires when it should not — a manifest with no gate to close (grounding, a standalone verify, a
#     submitted run, a run whose gates passed) must stay silent. A gate that cries every stop is
#     noise, and this one did exactly that for seven days over one standalone verify manifest.
#   silent when it should fire — an authoring run with an open gate must be named, and named by
#     something the operator can find on disk.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/gate-stop.sh
[ -f "$SRC" ] || { echo "test-gate-stop: script not found at $SRC" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-gate-stop: jq is required." >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
H="$T/home"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
pass() { T_PASS=$((T_PASS+1)); }

reset() { rm -rf "$H"; mkdir -p "$H"; }
mk() {  # mk <run-dir-name> <manifest json>
  mkdir -p "$H/.cubrid-agent/$1"
  printf '%s\n' "$2" > "$H/.cubrid-agent/$1/manifest.json"
}
report_for() { mkdir -p "$H/.cubrid-agent/reports/author-testcase"; : > "$H/.cubrid-agent/reports/author-testcase/$1.md"; }

# The reminder rides on additionalContext; anything else on stdout is not a reminder.
say() {  # say [hook-input json]
  printf '%s' "${1:-{\}}" | HOME="$H" bash "$SRC" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

silent() {  # silent <label>
  local out; out=$(say)
  [ -z "$out" ] && pass || note_fail "$1: it spoke — $out"
}
speaks() {  # speaks <pattern> <label>
  local out; out=$(say)
  if [ -z "$out" ]; then note_fail "$2: it stayed silent"; return; fi
  printf '%s\n' "$out" | grep -qE "$1" && pass || note_fail "$2: said \"$out\", expected /$1/"
}

AUTHORING='{"issue":"CBRD-11111","author":{"path":"x.sql","sql_writes":1},"verify":{"determinism":{"all_pass":false}}}'

# ── nothing to report ─────────────────────────────────────────────────────────────────────────────
reset
silent "no run directory at all"

reset; mk CBRD-20001 '{"issue":"CBRD-20001","ground":{"issue_txt":"issue.txt"}}'
silent "a grounding-only manifest has no gate to close"

# The regression. A standalone verify-sql run carries `verify` and nothing else — no author, no
# review, and no issue key. It has no gate that could ever close, and it named itself "?" while
# saying so, which left nobody able to find it.
reset; mk CBRD-26431 '{"verify":{"status":"passed","determinism":{"runs":3,"all_pass":true}}}'
silent "a standalone verify run has no authoring gate"

reset; mk CBRD-20002 '{"issue":"CBRD-20002","author":{"path":"x.sql"},"verify":{"determinism":{"all_pass":false}},"submitted":true}'
silent "a submitted run is finished"

reset; mk CBRD-20003 '{"issue":"CBRD-20003","author":{"path":"x.sql"},"verify":{"determinism":{"all_pass":true}},"review":{"verdict":"PASS"}}'
silent "both gates closed"

# The sanctioned terminal state: it cannot pass, it said why, and it left a report.
reset; mk CBRD-20004 '{"issue":"CBRD-20004","author":{"path":"x.sql"},"verify":{"status":"blocked_review_unresolved","note":"oracle needs the fix","determinism":{"all_pass":false}}}'
report_for CBRD-20004
silent "a blocked run with a note and a report is a terminal state"

# A stop chain this hook started must not re-arm itself, or the reminder never ends.
reset; mk CBRD-20005 "$AUTHORING"
out=$(say '{"stop_hook_active":true}')
[ -z "$out" ] && pass || note_fail "it re-arms inside its own stop chain: $out"

# ── must report ───────────────────────────────────────────────────────────────────────────────────
reset; mk CBRD-20006 '{"issue":"CBRD-20006","author":{"path":"x.sql"},"verify":{"determinism":{"all_pass":false}}}'
speaks 'Incomplete TC manifest' "an authoring run with determinism open"
speaks 'CBRD-20006' "it names the issue"

# Named by the run directory when the manifest never recorded the key: "?" told the operator nothing.
reset; mk CBRD-26431 '{"author":{"path":"x.sql"},"verify":{"determinism":{"all_pass":false}}}'
speaks 'CBRD-26431' "a manifest with no issue key is named by its directory"
out=$(say); case "$out" in *'?'*) note_fail "it still reports \"?\": $out" ;; *) pass ;; esac

reset; mk CBRD-20007 '{"issue":"CBRD-20007","author":{"path":"x.sql"},"verify":{"determinism":{"all_pass":true}},"review":{"verdict":"FAIL"}}'
speaks 'CBRD-20007' "a failed review is an open gate"

# Blocked, but without the report the terminal state is not recorded — that is still an open run.
reset; mk CBRD-20008 '{"issue":"CBRD-20008","author":{"path":"x.sql"},"verify":{"status":"blocked_review_unresolved","note":"why","determinism":{"all_pass":false}}}'
speaks 'CBRD-20008' "blocked without the written report is not terminal"

# Past the loop bound the advice changes: stop iterating, record the terminal state.
reset; mk CBRD-20009 '{"issue":"CBRD-20009","author":{"path":"x.sql","sql_writes":6},"verify":{"determinism":{"all_pass":false}}}'
speaks 'Past the loop bound' "six rewrites is past the bound"
speaks 'blocked_review_unresolved' "it names the sanctioned exit"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'gate-stop: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'gate-stop: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
