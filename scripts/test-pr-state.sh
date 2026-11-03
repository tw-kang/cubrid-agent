#!/bin/bash
# Behavioural test for pr-state.sh — one read of everything a PR has before Ready and before merge.
#
# Dev-only, run by check-invariants.sh. Offline: `gh` is a stub on PATH that serves a canned
# `gh pr view` answer and canned `gh api --paginate --slurp` pages for the three comment kinds.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/pr-state.sh
[ -f "$SRC" ] || { echo "test-pr-state: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

STUBBIN="$T/stub"; mkdir -p "$STUBBIN"; export PATH="$STUBBIN:$PATH"
cat > "$STUBBIN/gh" <<'STUB'
#!/bin/bash
# Every call has to name the PR under test, or the script read another PR.
case "$1 $2" in
  "pr view")
    [ "$3" = 7 ] && [ "$4" = --repo ] && [ "$5" = acme/tc ] || { echo "stub gh: wrong PR: $*" >&2; exit 99; }
    kind=view ;;
  "api --paginate")
    [ "$3" = --slurp ] || { echo "stub gh: pages not slurped: $*" >&2; exit 99; }
    case "$4" in
      repos/acme/tc/issues/7/comments) kind=issue-comments ;;
      repos/acme/tc/pulls/7/reviews)   kind=reviews ;;
      repos/acme/tc/pulls/7/comments)  kind=line-comments ;;
      *) echo "stub gh: unexpected path: $4" >&2; exit 99 ;;
    esac ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 99 ;;
esac
[ "${STUB_FAIL:-}" = "$kind" ] && { echo "gh: HTTP 502" >&2; exit 1; }
cat "$STUB_DIR/$kind.json"
STUB
chmod +x "$STUBBIN/gh"
export STUB_DIR="$T"

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
pass() { T_PASS=$((T_PASS+1)); }
flat() { printf '%s' "$1" | tr '\n' '|'; }

CR() { printf '{"__typename":"CheckRun","name":"%s","status":"%s","conclusion":%s}' "$1" "$2" "$3"; }
SC() { printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "$1" "$2"; }
by() { printf '{"user":{"login":"%s"}}' "$1"; }

# view <checks json array> [reviewDecision] [reviewRequests json array]
view() {
  printf '{"headRefOid":"4aba81841ddee9e9bb5c651852f79f7a044acd03","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":"%s","reviewRequests":%s,"statusCheckRollup":%s}\n' \
    "${2-REVIEW_REQUIRED}" "${3-[]}" "$1" > "$T/view.json"
}
# pages <kind> <json array of pages>
pages() { printf '%s\n' "$2" > "$T/$1.json"; }
quiet() { pages issue-comments '[[]]'; pages reviews '[[]]'; pages line-comments '[[]]'; }

# run <args...>: OUT holds stdout, ERR stderr, RC the exit.
run() { OUT=$(bash "$SRC" "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
has() {  # has <exact line> <label>
  if [ "$RC" -ne 0 ]; then note_fail "$2: exit $RC — stderr: $(flat "$ERR")"
  elif printf '%s\n' "$OUT" | grep -qxF -- "$1"; then pass
  else note_fail "$2: no line '$1' — output: $(flat "$OUT")"; fi
}
refused() {  # refused <label>: exit 2 and nothing on stdout a reader could take for the PR's state
  if [ "$RC" -ne 2 ]; then note_fail "$1: exit $RC, expected 2 — output: $(flat "$OUT")"
  elif [ -n "$OUT" ]; then note_fail "$1: printed a partial state on a failure: $(flat "$OUT")"
  else pass; fi
}

# 11-03: the check list cut with `tail -1` hid `Greptile Review` while it was still pending.
view "[$(CR code-style COMPLETED '"SUCCESS"'),$(CR build COMPLETED '"FAILURE"'),$(SC ci/jenkins PENDING),$(CR 'Greptile Review' IN_PROGRESS null)]"
quiet; run acme/tc 7
has "checks 4" "the check count covers every check"
has "  SUCCESS code-style" "a finished check shows its conclusion"
has "  FAILURE build" "a failed check is listed"
has "  PENDING ci/jenkins" "a commit status shows by its context and state"
has "  IN_PROGRESS Greptile Review" "the last check is listed, the one tail -1 cut"

has "head 4aba81841ddee9e9bb5c651852f79f7a044acd03" "the full head SHA"
has "draft false" "isDraft"
has "mergeable MERGEABLE" "mergeable"
has "mergeStateStatus BLOCKED" "mergeStateStatus"
has "reviewDecision REVIEW_REQUIRED" "reviewDecision"
has "reviewRequests -" "no review request shows as -"
has "issueComments 0 last -" "no issue comment shows as 0 and -"
has "reviews 0 last -" "no review shows as 0 and -"
has "lineComments 0 last -" "no line comment shows as 0 and -"

view '[]' '' "[{\"__typename\":\"User\",\"login\":\"rev-b\"},{\"__typename\":\"Team\",\"slug\":\"qa-team\"}]"
quiet; run acme/tc 7
has "checks 0" "a PR with no checks says 0"
has "reviewDecision -" "an empty reviewDecision (no review rule) shows as -"
has "reviewRequests rev-b,qa-team" "a requested user and a requested team both show"

# 10-30: a review that came as an issue comment was missed. Each kind is counted across all its pages,
# and the last author is the last item of all pages joined (the API lists each kind oldest first).
view '[]'
pages issue-comments "[[$(by rev-a),$(by author)],[$(by 'greptile-apps[bot]')]]"
pages reviews "[[$(by rev-b)]]"
pages line-comments "[[$(by rev-b),$(by author)],[$(by rev-b)],[]]"
run acme/tc 7
has "issueComments 3 last greptile-apps[bot]" "issue comments are counted over every page, the newest author last"
has "reviews 1 last rev-b" "reviews are counted with their last author"
has "lineComments 3 last rev-b" "line comments are counted over every page, an empty last page skipped"

# An empty answer from a failed call reads as "no comments", the very miss the script exists to stop.
view '[]'; quiet
for k in view issue-comments reviews line-comments; do
  STUB_FAIL=$k run acme/tc 7; refused "a failed $k read is no state"
done

run;              refused "no arguments are refused"
run acme/tc;      refused "a missing PR number is refused"
run acme/tc 7x;   refused "a PR number that is not a number is refused"
run acme 7;       refused "a repo without an owner is refused"
run acme/tc 7 8;  refused "an extra argument is refused"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'pr-state: %d/%d\n' "$T_PASS" "$T_PASS"; exit 0
else
  printf 'pr-state: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"; exit 1
fi
