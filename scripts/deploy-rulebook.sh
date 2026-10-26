#!/bin/bash
# deploy-rulebook.sh — copy the canonical rulebook of one tc repo into a clone of that repo.
#
#   deploy-rulebook.sh [--key CUBRIDQA-<n>] <tc repo clone>
#   deploy-rulebook.sh --check <tc repo clone>
#
# The clone's origin URL picks the canonical tree rulebook/<repo>/. A deploy branches from the fetched
# origin/develop, copies the tree, puts a CLAUDE.md symlink next to every AGENTS.md, commits, and prints
# the PR body skeleton with the reviewers from rulebook/category-owners.txt. It never pushes. --check
# names every path on origin/develop that a deploy would change. The head key comes from
# .github/head-keys.txt unless --key names it.
#
# Dev-only, not shipped. Exit 0 = deployed, nothing to deploy, or no drift; 1 = refused or drift found;
# 2 = bad input.
set -u
export LC_ALL=C

die() { echo "deploy-rulebook: $2" >&2; exit "$1"; }
usage() { sed -n 's/^#   \(deploy-rulebook\.sh .*\)/\1/p' "$0" >&2; exit 2; }

ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

CHECK=0 KEY=
while [ $# -gt 1 ]; do
  case $1 in
    --check) CHECK=1; shift ;;
    --key) KEY=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ $# -eq 1 ] || usage
CLONE=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || die 2 "not a git clone: $1"
URL=$(git -C "$CLONE" remote get-url origin 2>/dev/null) || die 2 "$CLONE has no origin remote"
# A local path, as the tests use, names no owner.
if [[ $URL =~ github\.com[:/]([^/]+)/ ]] && [ "${BASH_REMATCH[1],,}" != cubrid ]; then
  die 2 "origin is $URL, not a CUBRID repo, so the branch would start from a fork; point origin at \
github.com/CUBRID and keep the fork as another remote"
fi
NAME=$(basename "${URL%/}" .git)
CANONICAL=$ROOT/rulebook/$NAME
[ -d "$CANONICAL" ] || die 2 "no canonical rulebook for $NAME at rulebook/$NAME"
mapfile -t FILES < <(cd "$CANONICAL" && find . -type f | sed 's|^\./||' | sort)
mapfile -t LINKS < <(printf '%s\n' "${FILES[@]}" | sed -nE 's#(^|/)AGENTS\.md$#\1CLAUDE.md#p')
mapfile -t UNITS < <(printf '%s\n' "${FILES[@]}" | sed -n 's|/.*||p' | sort -u)

expected() {  # "<mode> <blob><TAB><path>" for every path a deploy writes
  local p link
  for p in "${FILES[@]}"; do
    printf '100644 %s\t%s\n' "$(git -C "$CLONE" hash-object "$CANONICAL/$p")" "$p"
  done
  link=$(printf 'AGENTS.md' | git -C "$CLONE" hash-object --stdin)
  for p in "${LINKS[@]}"; do printf '120000 %s\t%s\n' "$link" "$p"; done
}
drift() {  # one line per path whose origin/develop entry is not what a deploy writes
  local ms p
  declare -A have
  while IFS=$'\t' read -r ms p; do have[$p]=$ms; done < <(
    git -C "$CLONE" ls-tree -r origin/develop -- "${FILES[@]}" "${LINKS[@]}" | sed -E 's/^([0-9]+) [a-z]+ /\1 /')
  while IFS=$'\t' read -r ms p; do
    if [ -z "${have[$p]:-}" ]; then echo "missing  $p"
    elif [ "${have[$p]}" != "$ms" ]; then echo "differs  $p"; fi
  done < <(expected)
}

if [ "$CHECK" -eq 0 ]; then
  OWNERS=$ROOT/rulebook/category-owners.txt
  REVIEWERS=()
  for u in "${UNITS[@]}"; do
    o=$(sed 's/#.*//' "$OWNERS" 2>/dev/null | awk -v c="$u" '$1 == c { print $2 }')
    [ -n "$o" ] || die 2 "no owner for category $u in rulebook/category-owners.txt"
    REVIEWERS+=("$o")
  done
  mapfile -t REVIEWERS < <(printf '%s\n' "${REVIEWERS[@]}" | sort -u)

  if [ -z "$KEY" ]; then
    KEY=$(sed 's/#.*//' "$ROOT/.github/head-keys.txt" | tr -d ' \t' | grep -v '^$' | sort -u)
    [ "$(printf '%s\n' "$KEY" | grep -c .)" -eq 1 ] \
      || die 2 ".github/head-keys.txt does not list exactly one head key; name this deploy's with --key CUBRIDQA-<n>"
  fi
  [[ $KEY =~ ^CUBRIDQA-[1-9][0-9]*$ ]] || die 2 "not a CUBRIDQA key: $KEY"
  BRANCH=cubridqa-${KEY#CUBRIDQA-}-rulebook

  [ -z "$(git -C "$ROOT" status --porcelain -- "rulebook/$NAME")" ] \
    || die 1 "rulebook/$NAME has uncommitted changes; commit them first so the deploy commits can name their source"
  SOURCE=$(git -C "$ROOT" rev-parse HEAD)

  # Untracked files count too: one at a path the rulebook lands on would be overwritten.
  DIRTY=$(git -C "$CLONE" status --porcelain)
  [ -z "$DIRTY" ] || die 1 "$CLONE has uncommitted changes; commit or stash them first:
$DIRTY"
fi

git -C "$CLONE" fetch -q origin +refs/heads/develop:refs/remotes/origin/develop || die 1 "fetch from origin failed"

DRIFT=$(drift)
if [ -z "$DRIFT" ]; then
  echo "deploy-rulebook: origin/develop matches rulebook/$NAME"
  [ "$CHECK" -eq 1 ] || echo "deploy-rulebook: nothing to deploy, no branch made"
  exit 0
fi
if [ "$CHECK" -eq 1 ]; then
  printf '%s\n' "$DRIFT"
  echo "deploy-rulebook: $(printf '%s\n' "$DRIFT" | grep -c .) path(s) on origin/develop differ from rulebook/$NAME"
  exit 1
fi

git -C "$CLONE" switch -q --no-track -c "$BRANCH" origin/develop || die 1 "could not create $BRANCH"

# cp keeps the mode of a file it overwrites, and drift() expects 100644.
for p in "${FILES[@]}"; do
  mkdir -p "$(dirname "$CLONE/$p")" && cp "$CANONICAL/$p" "$CLONE/$p" && chmod 644 "$CLONE/$p" || die 1 "copy failed: $p"
done
for l in "${LINKS[@]}"; do
  ln -sfn AGENTS.md "$CLONE/$l" || die 1 "symlink failed: $l"
done

commit_unit() {  # <subject> <paths...>
  local subject=$1; shift
  [ $# -gt 0 ] && git -C "$CLONE" add -- "$@"
  git -C "$CLONE" diff --cached --quiet && return
  git -C "$CLONE" commit -q -m "$subject" -m "Copied from cubrid-agent rulebook/$NAME/ at $SOURCE." \
    || die 1 "commit failed: $subject"
}
in_unit() { printf '%s\n' "${FILES[@]}" "${LINKS[@]}" | grep -E "$1" | sort; }

# One commit per unit, so that each reverts alone.
mapfile -t UNIT_PATHS < <(in_unit '^[^/]+$')
commit_unit "[$KEY] Deploy the repo-wide rulebook" "${UNIT_PATHS[@]}"
for u in "${UNITS[@]}"; do
  mapfile -t UNIT_PATHS < <(in_unit "^$u/")
  commit_unit "[$KEY] Deploy the $u rulebook" "${UNIT_PATHS[@]}"
done

NCOMMITS=$(git -C "$CLONE" rev-list --count origin/develop..HEAD)
printf 'deploy-rulebook: branch %s in %s, %d commit(s) on origin/develop\n' "$BRANCH" "$CLONE" "$NCOMMITS"
git -C "$CLONE" log --reverse --format='  %h %s' origin/develop..HEAD
[ "$NCOMMITS" -eq 1 ] && echo "deploy-rulebook: warning: one commit. Where squash_merge_commit_title is" \
  "COMMIT_OR_PR_TITLE, a one-commit PR merges under this commit's subject, which carries the head key," \
  "not the PR title's sub-task key. Ask the merger to use the PR title as the squash title." >&2
echo "Not pushed: push it to your fork and open a Draft PR (docs/agents/issue-tracker.md, PR 흐름)."
echo "reviewers: $(IFS=,; echo "${REVIEWERS[*]}")"
cat <<EOF

----- PR body -----
<http://jira.cubrid.org/browse/$KEY>

### Purpose

TODO: 배경과 문제. 이 변경 전에 개발자와 에이전트가 무엇을 못 했나.

### Implementation

- 제안: TODO: 제안 링크 (\`cubrid-agent\` PR 또는 CUBRIDQA-1505 코멘트)
- 정본: \`cubrid-agent\`의 \`rulebook/$NAME/\` (커밋 \`${SOURCE:0:12}\`)
- TODO: 바뀐 동작. 개발자가 어느 디렉터리의 파일을 열 때 에이전트가 무엇을 읽게 되나.

### Remarks

담당자 확인 목록 — 리뷰에서 그대로 두거나 고친다.

- TODO: 설문이나 이력과 다르게 정한 것, 확인이 필요한 것. 이력 수치를 함께 적는다. 없으면 "없음".
EOF
