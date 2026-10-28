#!/bin/bash
# check-subtask-resolve.sh — may this sub-task be moved to Resolved now? PR flow 3.3 runs it right after a merge.
#
#   check-subtask-resolve.sh <CUBRIDQA-n>
#
# Several PRs can share one sub-task, and it is resolved once, after the last of them merges.
# Dev-only. Exit 0 = no open PR carries the key in its title: resolve it. 1 = open PRs still carry it
# (listed): leave it to the session that merges the last one. 2 = bad input or gh failed: no verdict.
set -u

key=${1:-}
[[ $key =~ ^CUBRIDQA-[1-9][0-9]*$ ]] || { echo "usage: check-subtask-resolve.sh <CUBRIDQA-n>" >&2; exit 2; }

# No repo list: the search spans every repo the token reads, so a tc repo PR counts without one.
# The title, not the search match, decides whether the key itself is there.
hits=$(gh search prs "\"$key\"" --match title --state open --limit 100 --json url,title \
         --jq ".[] | select(.title | test(\"$key([^0-9]|\$)\")) | .url") \
  || { echo "check-subtask-resolve: gh search failed — no verdict" >&2; exit 2; }

# The search index can still list the PR merged a moment ago as open, so the PR itself has the last word.
open=""
for url in $hits; do
  state=$(gh pr view "$url" --json state --jq .state) \
    || { echo "check-subtask-resolve: gh pr view $url failed — no verdict" >&2; exit 2; }
  [ "$state" = OPEN ] && open="$open $url"
done

if [ -z "$open" ]; then
  echo "resolve: no open PR carries $key in its title"
  exit 0
fi
echo "keep: open PRs still carry $key in their title:"
printf '  %s\n' $open
exit 1
