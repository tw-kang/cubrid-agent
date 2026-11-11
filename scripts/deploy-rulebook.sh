#!/bin/bash
# deploy-rulebook.sh — copy the canonical rulebook of one tc repo into a clone of that repo.
#
#   deploy-rulebook.sh [--key CUBRIDQA-<n>] <tc repo clone>
#   deploy-rulebook.sh --check <tc repo clone>
#
# The clone's origin URL picks the canonical tree rulebook/<repo>/. A deploy branches from the fetched
# origin/develop, copies the tree, puts a CLAUDE.md that imports AGENTS.md next to every AGENTS.md,
# commits, and prints the PR body skeleton with the reviewers from rulebook/category-owners.txt. If the
# branch exists, the deploy commits on top of it instead and merges origin/develop in when the branch is
# behind; a branch that already matches gets no commit. A branch whose change origin/develop already holds
# is merged: the deploy leaves it and takes the next name, -2, -3, and so on. It never pushes. --check
# names every path on origin/develop that a deploy would change. The head key comes from
# .github/head-keys.txt unless --key names it.
# Before it commits, a deploy reads the repo's squash_merge_commit_title with gh, or takes it from
# DEPLOY_RULEBOOK_SQUASH_TITLE: under PR_TITLE the commit subjects carry no key, under COMMIT_OR_PR_TITLE
# they start with it. A setting it cannot read stops the deploy.
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
# A local path, as the tests use, names no owner. Any other URL is read for its owner, the segment
# before the repo name, since an SSH host alias can stand in for github.com.
case $URL in
  /*|./*|../*|file://*) ;;
  *) OWNER=$(basename "$(dirname "${URL#*:}")")
     [ "${OWNER,,}" = cubrid ] || die 1 "origin is $URL, not a CUBRID repo, so the branch would start from a \
fork; point origin at github.com/CUBRID and keep the fork as another remote" ;;
esac
NAME=$(basename "${URL%/}" .git)
CANONICAL=$ROOT/rulebook/$NAME
[ -d "$CANONICAL" ] || die 2 "no canonical rulebook for $NAME at rulebook/$NAME"
mapfile -t FILES < <(cd "$CANONICAL" && find . -type f | sed 's|^\./||' | sort)
mapfile -t IMPORTS < <(printf '%s\n' "${FILES[@]}" | sed -nE 's#(^|/)AGENTS\.md$#\1CLAUDE.md#p')
IMPORT_LINE='@AGENTS.md'
mapfile -t UNITS < <(printf '%s\n' "${FILES[@]}" | sed -n 's|/.*||p' | sort -u)

expected() {
  local p import
  for p in "${FILES[@]}"; do
    printf '100644 %s\t%s\n' "$(git -C "$CLONE" hash-object "$CANONICAL/$p")" "$p"
  done
  import=$(printf '%s\n' "$IMPORT_LINE" | git -C "$CLONE" hash-object --stdin)
  for p in "${IMPORTS[@]}"; do printf '100644 %s\t%s\n' "$import" "$p"; done
}
drift() {
  local mode_blob p
  declare -A have
  while IFS=$'\t' read -r mode_blob p; do have[$p]=$mode_blob; done < <(
    git -C "$CLONE" ls-tree -r "$1" -- "${FILES[@]}" "${IMPORTS[@]}" | sed -E 's/^([0-9]+) [a-z]+ /\1 /')
  while IFS=$'\t' read -r mode_blob p; do
    if [ -z "${have[$p]:-}" ]; then echo "missing  $p"
    elif [ "${have[$p]}" != "$mode_blob" ]; then echo "differs  $p"; fi
  done < <(expected)
}

if [ "$CHECK" -eq 0 ]; then
  OWNERS=$ROOT/rulebook/category-owners.txt
  REVIEWERS=()
  for u in "${UNITS[@]}"; do
    owner=$(sed 's/#.*//' "$OWNERS" 2>/dev/null | awk -v c="$u" '$1 == c { print $2 }')
    [ -n "$owner" ] || die 1 "no owner for category $u in rulebook/category-owners.txt"
    REVIEWERS+=("$owner")
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

  # A guess would put keys where the repo wants none, or leave them out where it wants them.
  SQUASH_TITLE=${DEPLOY_RULEBOOK_SQUASH_TITLE:-} FROM=DEPLOY_RULEBOOK_SQUASH_TITLE
  if [ -z "$SQUASH_TITLE" ] && [ -n "${OWNER:-}" ]; then
    FROM="gh api repos/$OWNER/$NAME"
    SQUASH_TITLE=$(gh api "repos/$OWNER/$NAME" --jq .squash_merge_commit_title 2>/dev/null)
  fi
  case $SQUASH_TITLE in
    PR_TITLE) KEY_PREFIX= ;;
    COMMIT_OR_PR_TITLE) KEY_PREFIX="[$KEY] " ;;
    *) die 1 "could not read squash_merge_commit_title of $NAME (${FROM}: '$SQUASH_TITLE'); it decides whether \
the commit subjects carry $KEY. Read it with gh api repos/<owner>/$NAME and pass it as DEPLOY_RULEBOOK_SQUASH_TITLE" ;;
  esac
  echo "deploy-rulebook: squash_merge_commit_title is $SQUASH_TITLE ($FROM), so commit subjects carry" \
    "${KEY_PREFIX:-no key}"
fi

git -C "$CLONE" fetch -q origin +refs/heads/develop:refs/remotes/origin/develop || die 1 "fetch from origin failed"

DRIFT=$(drift origin/develop)
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

# A squash merge leaves the branch tip off origin/develop, so a merged branch is found by its net change:
# GitHub's squash commit carries it as one commit, and a branch that took origin/develop after its merge
# has none left.
merged_at() {  # <branch>: print the origin/develop commit that holds the branch's change, or nothing
  local base id paths
  base=$(git -C "$CLONE" merge-base origin/develop "$1") || return
  mapfile -t paths < <(git -C "$CLONE" diff --name-only "$base" "$1")
  [ ${#paths[@]} -gt 0 ] || { echo "$base"; return; }
  id=$(git -C "$CLONE" diff "$base" "$1" | git -C "$CLONE" patch-id --stable | cut -d' ' -f1)
  git -C "$CLONE" log -p "$base..origin/develop" -- "${paths[@]}" | git -C "$CLONE" patch-id --stable \
    | awk -v id="$id" '$1 == id { print $2; exit }'
}

# A branch that is not merged carries an open PR, which takes new commits on top and is never rewritten.
STEM=$BRANCH N=1
while git -C "$CLONE" show-ref --verify -q "refs/heads/$BRANCH" && AT=$(merged_at "$BRANCH") && [ -n "$AT" ]; do
  echo "deploy-rulebook: $BRANCH is already in origin/develop at ${AT:0:12}; it is left as it is"
  N=$((N+1)) BRANCH=$STEM-$N
done
if git -C "$CLONE" show-ref --verify -q "refs/heads/$BRANCH"; then
  [ -n "$(drift "refs/heads/$BRANCH")" ] \
    || { echo "deploy-rulebook: $BRANCH already matches rulebook/$NAME, no commit made"; exit 0; }
  BASE=$(git -C "$CLONE" rev-parse --short=12 "refs/heads/$BRANCH")
  git -C "$CLONE" switch -q "$BRANCH" || die 1 "could not switch to $BRANCH"
  if ! git -C "$CLONE" merge-base --is-ancestor origin/develop HEAD; then
    git -C "$CLONE" merge -q --no-edit -m "${KEY_PREFIX}Merge origin/develop into $BRANCH" origin/develop \
      || { git -C "$CLONE" merge --abort; die 1 "merging origin/develop into $BRANCH failed; merge it by hand"; }
  fi
else
  BASE=origin/develop
  git -C "$CLONE" switch -q --no-track -c "$BRANCH" origin/develop || die 1 "could not create $BRANCH"
fi

# cp keeps the mode of a file it overwrites, and drift() expects 100644.
for p in "${FILES[@]}"; do
  mkdir -p "$(dirname "$CLONE/$p")" && cp "$CANONICAL/$p" "$CLONE/$p" && chmod 644 "$CLONE/$p" || die 1 "copy failed: $p"
done
# rm first: a branch from an older deploy holds a CLAUDE.md symlink, and a write would follow it into AGENTS.md.
for p in "${IMPORTS[@]}"; do
  rm -f "$CLONE/$p" && printf '%s\n' "$IMPORT_LINE" > "$CLONE/$p" || die 1 "write failed: $p"
done

commit_unit() {  # <subject> <paths...>
  local subject=$1; shift
  [ $# -gt 0 ] && git -C "$CLONE" add -- "$@"
  git -C "$CLONE" diff --cached --quiet && return
  git -C "$CLONE" commit -q -m "$subject" -m "Copied from cubrid-agent rulebook/$NAME/ at $SOURCE." \
    || die 1 "commit failed: $subject"
}
paths_matching() { printf '%s\n' "${FILES[@]}" "${IMPORTS[@]}" | grep -E "$1" | sort; }

# One commit per unit, so that each reverts alone.
mapfile -t UNIT_PATHS < <(paths_matching '^[^/]+$')
commit_unit "${KEY_PREFIX}Deploy the repo-wide rulebook" "${UNIT_PATHS[@]}"
for u in "${UNITS[@]}"; do
  mapfile -t UNIT_PATHS < <(paths_matching "^$u/")
  commit_unit "${KEY_PREFIX}Deploy the $u rulebook" "${UNIT_PATHS[@]}"
done

NCOMMITS=$(git -C "$CLONE" rev-list --count --first-parent "$BASE..HEAD")
printf 'deploy-rulebook: branch %s in %s, %d commit(s) on %s\n' "$BRANCH" "$CLONE" "$NCOMMITS" "$BASE"
git -C "$CLONE" log --reverse --first-parent --format='  %h %s' "$BASE..HEAD"
if [ "$BASE" != origin/develop ]; then
  echo "Not pushed: push $BRANCH to your fork as it is to update its open PR. The new commits sit on top, so no force."
  exit 0
fi
[ "$NCOMMITS" -eq 1 ] && [ -n "$KEY_PREFIX" ] && echo "deploy-rulebook: warning: one commit." \
  "With squash_merge_commit_title COMMIT_OR_PR_TITLE, a one-commit PR merges under this commit's subject," \
  "which carries the head key, not the PR title's sub-task key. Ask the merger to use the PR title as the squash title." >&2
echo "Not pushed: push it to your fork and open a Draft PR (docs/agents/issue-tracker.md, PR 흐름)."
echo "reviewers: $(IFS=,; echo "${REVIEWERS[*]}")"
cat <<EOF

----- PR body -----
<http://jira.cubrid.org/browse/$KEY>

### Purpose

TODO: 배경과 문제. 이 변경 전에 TC를 쓰는 사람이 무엇을 몰랐나. 본문 전체를 리뷰어가 쓰는 말로 쓴다. 정본, 배포본, 결정 번호 같은 내부 용어는 쓰지 않는다.

### Implementation

- 제안: TODO: 제안 링크 (\`cubrid-agent\` PR 또는 CUBRIDQA-1505 코멘트)
- 원본: 이 PR의 룰북 파일은 \`cubrid-agent\` repo \`rulebook/$NAME/\`(커밋 \`${SOURCE:0:12}\`)을 복사한 것이다.
- TODO: 고친 규칙과 더한 규칙만 규칙마다 한 줄로 적는다. 그대로 둔 규칙과 고친 과정은 적지 않는다.

### Remarks

담당자 확인 목록 — 리뷰에서 그대로 두거나 고친다.

- TODO: 설문이나 이력과 다르게 정한 것, 확인이 필요한 것. 이력 수치를 함께 적는다. 없으면 "없음".
EOF
