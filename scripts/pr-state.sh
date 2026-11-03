#!/bin/bash
# pr-state.sh — everything a PR carries, in one read: PR flow 2.5 (Ready) and 3.2 (right before the merge) run it.
#
#   pr-state.sh <owner/repo> <N>
#
# Dev-only. Prints every check uncut, the count and last author of each comment kind (issue comments,
# reviews, line comments), review requests, head SHA, isDraft, mergeable, mergeStateStatus and
# reviewDecision. Exit 0 = printed. 2 = bad input or a gh call failed: nothing printed.
set -u
export LC_ALL=C

repo=${1:-} n=${2:-}
[ $# -eq 2 ] && [[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $n =~ ^[1-9][0-9]*$ ]] \
  || { echo "usage: pr-state.sh <owner/repo> <N>" >&2; exit 2; }

# Everything is read before anything is printed: a half-printed state reads as a PR with no comments.
view=$(gh pr view "$n" --repo "$repo" \
         --json headRefOid,isDraft,mergeable,mergeStateStatus,reviewDecision,reviewRequests,statusCheckRollup) \
  || { echo "pr-state: gh pr view $repo#$n failed — no state" >&2; exit 2; }
for kind in issues/$n/comments pulls/$n/reviews pulls/$n/comments; do
  pages=$(gh api --paginate --slurp "repos/$repo/$kind") \
    || { echo "pr-state: gh api repos/$repo/$kind failed — no state" >&2; exit 2; }
  # Each kind comes oldest first, so the last item is the newest.
  counts+=("$(printf '%s\n' "$pages" | jq -r 'add // [] | "\(length) last \(last.user.login // "-")"')")
done

printf '%s\n' "$view" | jq -r '
  def dash: if . == null or . == "" then "-" else . end;
  "head \(.headRefOid)", "draft \(.isDraft)", "mergeable \(.mergeable)", "mergeStateStatus \(.mergeStateStatus)",
  "reviewDecision \(.reviewDecision | dash)",
  "reviewRequests \([.reviewRequests[] | .login // .slug] | join(",") | dash)",
  "checks \(.statusCheckRollup | length)",
  (.statusCheckRollup[] | "  \(.state // if .status == "COMPLETED" then .conclusion else .status end) \(.context // .name)")'
printf 'issueComments %s\nreviews %s\nlineComments %s\n' "${counts[@]}"
