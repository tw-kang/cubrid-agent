#!/bin/bash
# Move a review lane's preconditions from its report into the run manifest. Installed to
# ~/.cubrid-agent/bin/ by /setup-cubrid-agent.
#
# The judgment is R1's and stays R1's — what a precondition says cannot be derived from a log. What
# this removes is the orchestrator retyping it: reading the lane report and hand-writing the same
# sentences back as manifest JSON cost 4,665 output tokens against 2 seconds of tool time
# (CUBRIDQA-1507), and it was the last place the orchestrator re-read a lane report to relay its
# contents at all.
#
# Two halves of one contract, split by lane:
#   review-r1 opens each precondition (id + cond), always unverified — it runs before Verify.
#   review-r2 closes it (verified + evidence) against what execution produced.
# Neither can do the other's half, because that is what makes the pair a check rather than a claim.
#
# Usage: record-preconditions.sh CBRD-XXXXX --from <lane-report.json>
set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=common.sh disable=SC1091
. "$SELF_DIR/common.sh" || { printf 'record-preconditions: common.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }

USAGE='record-preconditions.sh CBRD-XXXXX --from <lane-report.json>'
die() { printf 'record-preconditions: %s\n' "$1" >&2; exit 1; }

KEY=""; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from)    FROM=${2:-}; [ -n "$FROM" ] || die "--from needs a path"; shift 2 ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*)        reject_unknown "$USAGE" "$1" ;;
    *)         KEY=$(parse_issue_key "$1"); shift ;;
  esac
done
[ -n "$KEY" ]  || die "need an issue key
$USAGE"
[ -n "$FROM" ] || die "need --from <lane-report.json> — the lane wrote one, pass its path
$USAGE"
command -v jq >/dev/null 2>&1 || die "jq is required."
[ -f "$FROM" ] || die "no lane report at $FROM — a missing report is a lane failure (re-run that lane with the path restated), not something to work around."
# An empty file passes `jq -e .` silently, so size is checked before shape.
[ -s "$FROM" ] || die "$FROM is empty — the lane wrote no report."
jq -e 'type == "object"' "$FROM" >/dev/null 2>&1 \
  || die "$FROM is not a JSON object — the lane report is JSON so this transfer can check it; fix the report and re-run."

LANE=$(jq -r '.lane // empty' "$FROM" 2>/dev/null)
case "$LANE" in
  review-r1|review-r2) ;;
  "") die "$FROM has no .lane field — it names which half of the contract applies and cannot be guessed." ;;
  *)  die "lane \"$LANE\" is not a precondition source — only review-r1 (opens them) and review-r2 (closes them) are." ;;
esac
ROUND=$(jq -r '.round // "?"' "$FROM" 2>/dev/null)

# The field being absent is the failure this exists to catch: a lane that dropped the block would
# otherwise record nothing and read as a clean run.
jq -e '(.preconditions | type) == "array"' "$FROM" >/dev/null 2>&1 \
  || die "$FROM has no .preconditions array. Write [] if this run genuinely needs none — an omitted field is indistinguishable from a lane that forgot."

RUN_DIR="$HOME/.cubrid-agent/$KEY"
MANIFEST="$RUN_DIR/manifest.json"
mkdir -p "$RUN_DIR"
[ -f "$MANIFEST" ] || printf '{}\n' > "$MANIFEST"
jq -e 'type == "object"' "$MANIFEST" >/dev/null 2>&1 \
  || die "$MANIFEST is not a JSON object — refusing to write over it."

if [ "$LANE" = review-r1 ]; then
  _bad=$(jq -r '[.preconditions[] | select((.id // "") == "" or (.cond // "") == "")] | length' "$FROM")
  [ "$_bad" = 0 ] || die "R1: $_bad precondition(s) miss id or cond. Both are required — the id is the identity R2 closes against, the cond is the judgment."
else
  _bad=$(jq -r '[.preconditions[] | select((.id // "") == "" or (.verified | type) != "boolean" or (.evidence // "") == "")] | length' "$FROM")
  [ "$_bad" = 0 ] || die "R2: $_bad precondition(s) miss id, a boolean verified, or evidence. Evidence is required either way — \"verified\" without it is an assertion, and a precondition that failed needs to say what it measured."
  # R2 judges what R1 raised. An id R1 never opened means the lanes disagree about what was checked,
  # and quietly adding it would hide that.
  _unknown=$(jq -r --slurpfile m "$MANIFEST" \
    '[.preconditions[].id] - [($m[0].verify.preconditions // [])[].id] | join(", ")' "$FROM")
  [ -z "$_unknown" ] || die "R2 closes a precondition R1 never raised: $_unknown. Either R1's report was not recorded, or the two lanes are judging different things."
fi

# Merge on id. R1 refreshes cond and may add; R2 only updates what is already there. Neither drops a
# recorded precondition — removing one is a judgment, and dropping it would also drop the
# "inconclusive" it forces on the result.
_add=false; [ "$LANE" = review-r1 ] && _add=true
tmp=$(mktemp) || die "cannot create a temporary file"
if jq --slurpfile r "$FROM" --argjson add "$_add" '
     ($r[0].preconditions) as $new
     | (.verify.preconditions // []) as $old
     | ($old | map(.id)) as $ids
     | .verify.preconditions = (
         ($old | map(. as $o
                     | ($new | map(select(.id == $o.id)) | last) as $u
                     | if $u == null then $o else $o + ($u | del(.id)) end))
         + (if $add
            then ($new | map(select(([.id] - $ids) != [])) | map({id: .id, cond: .cond, verified: false}))
            else [] end))' \
     "$MANIFEST" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$MANIFEST"
else
  rm -f "$tmp"; die "the merge failed — $MANIFEST is unchanged."
fi

TOTAL=$(jq -r '(.verify.preconditions // []) | length' "$MANIFEST")
OPEN=$(jq -r '[(.verify.preconditions // [])[] | select(.verified != true) | .id] | join(", ")' "$MANIFEST")
NOPEN=$(jq -r '[(.verify.preconditions // [])[] | select(.verified != true)] | length' "$MANIFEST")

# An unverified precondition means the result is inconclusive, so the caller is told rather than
# left to notice. The renderers read the same field and carry it into the report and the PR body.
if [ "$NOPEN" -eq 0 ]; then
  printf '[precond] %s %s round %s — %s recorded, all verified\n' "$KEY" "$LANE" "$ROUND" "$TOTAL"
else
  printf '[precond] %s %s round %s — %s recorded, %s unverified: %s\n' \
    "$KEY" "$LANE" "$ROUND" "$TOTAL" "$NOPEN" "$OPEN"
  printf '  An unverified precondition leaves the result inconclusive. R2 closes each one with its evidence; whatever is still open at Submit has to be said in the report.\n'
fi
