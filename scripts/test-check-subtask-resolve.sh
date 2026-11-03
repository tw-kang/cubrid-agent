#!/bin/bash
# Behavioural test for check-subtask-resolve.sh — may a sub-task shared by several PRs be resolved now?
#
# Dev-only, run by check-invariants.sh. Offline: `gh` is a stub on PATH that serves canned search hits
# and per-PR live states, and honours --jq the way gh does.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/check-subtask-resolve.sh
[ -f "$SRC" ] || { echo "test-check-subtask-resolve: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

STUBBIN="$T/stub"; mkdir -p "$STUBBIN"; export PATH="$STUBBIN:$PATH"
cat > "$STUBBIN/gh" <<'STUB'
#!/bin/bash
jqexpr=; prev=
for a in "$@"; do [ "$prev" = --jq ] && jqexpr=$a; prev=$a; done
case "$1 $2" in
  "search prs")
    [ -n "${STUB_SEARCH_FAIL:-}" ] && { echo "gh: HTTP 502" >&2; exit 1; }
    out=$(cat "$STUB_SEARCH") ;;
  "pr view")
    [ -n "${STUB_VIEW_FAIL:-}" ] && { echo "gh: HTTP 502" >&2; exit 1; }
    st=$(awk -v u="$3" '$1 == u { print $2 }' "$STUB_STATES")
    [ -n "$st" ] || { echo "gh: no pull request $3" >&2; exit 1; }
    out=$(printf '{"state":"%s"}' "$st") ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 99 ;;
esac
if [ -n "$jqexpr" ]; then printf '%s\n' "$out" | jq -r "$jqexpr"; else printf '%s\n' "$out"; fi
STUB
chmod +x "$STUBBIN/gh"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
pass() { T_PASS=$((T_PASS+1)); }
flat() { printf '%s' "$1" | tr '\n' '|'; }

# search_returns <json array of {url,title}>; live_states <url STATE>... — each PR's state on the PR itself.
search_returns() { printf '%s\n' "$1" > "$T/search.json"; }
live_states()    { printf '%s\n' "$@" > "$T/states.txt"; }
export STUB_SEARCH="$T/search.json" STUB_STATES="$T/states.txt"

expect() {  # expect <expected-exit> <pattern|""> <label> -- <args...>
  local want=$1 pat=$2 label=$3 rc; shift 4
  OUT=$(bash "$SRC" "$@" 2>&1); rc=$?
  if [ "$rc" -ne "$want" ]; then note_fail "$label: exit $rc, expected $want — output: $(flat "$OUT")"; return; fi
  if [ -n "$pat" ] && ! printf '%s\n' "$OUT" | grep -qE "$pat"; then
    note_fail "$label: no line matching /$pat/ — output: $(flat "$OUT")"; return
  fi
  pass
}

search_returns '[]'; live_states
expect 0 "resolve" "no open PR carries the key: resolve it" -- CUBRIDQA-1684

# A tc repo PR counts as much as one here: PR flow 4 lets it reuse the sub-task.
U1=https://github.com/CUBRID/cubrid-testcases/pull/3912
search_returns "[{\"url\":\"$U1\",\"title\":\"[CUBRIDQA-1684] Add a rule\"}]"; live_states "$U1 OPEN"
expect 1 "cubrid-testcases/pull/3912" "an open PR headed by the key holds the sub-task open" -- CUBRIDQA-1684

# An empty answer from a failed search reads as "none open", and that resolves a sub-task too early.
STUB_SEARCH_FAIL=1 expect 2 "" "a failed search is no verdict" -- CUBRIDQA-1684

# A bare number or an empty key searches for something else and finds nothing, which reads as resolve.
search_returns '[]'; live_states
expect 2 "" "no key is refused" --
expect 2 "" "a bare number is not a key" -- 1684
expect 2 "" "a key from another project is refused" -- CBRD-26722

# The title, not the search match, decides. A longer key that starts the same is another issue.
U2=https://github.com/tw-kang/cubrid-agent/pull/90
search_returns "[{\"url\":\"$U2\",\"title\":\"[CUBRIDQA-16840] Another sub-task\"}]"; live_states "$U2 OPEN"
expect 0 "resolve" "a PR headed by a longer key does not hold the sub-task" -- CUBRIDQA-1684

# The tool runs right after a merge, and the search index can still list that PR as open.
U3=https://github.com/tw-kang/cubrid-agent/pull/29
search_returns "[{\"url\":\"$U3\",\"title\":\"[CUBRIDQA-1684] Just merged\"},{\"url\":\"$U1\",\"title\":\"[CUBRIDQA-1684] Add a rule\"}]"
live_states "$U3 MERGED" "$U1 OPEN"
expect 1 "cubrid-testcases/pull/3912" "the PR still open is listed" -- CUBRIDQA-1684
if printf '%s\n' "$OUT" | grep -q 'pull/29'; then note_fail "a merged PR the index still lists as open is listed: $(flat "$OUT")"
else pass; fi
live_states "$U3 MERGED" "$U1 CLOSED"
expect 0 "resolve" "hits the index lists as open but that are merged or closed do not hold the sub-task" -- CUBRIDQA-1684

STUB_VIEW_FAIL=1 expect 2 "" "a failed state read is no verdict" -- CUBRIDQA-1684

if [ "$T_FAIL" -eq 0 ]; then
  printf 'check-subtask-resolve: %d/%d\n' "$T_PASS" "$T_PASS"; exit 0
else
  printf 'check-subtask-resolve: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"; exit 1
fi
