#!/bin/bash
# Build the author-testcase Select queue: the field screen and the idempotency screen in ONE command,
# leaving only the body judgment to the model. Installed to ~/.cubrid-agent/bin/ by /setup-cubrid-agent.
#
# Why this is a script (DP6): Select is mechanical up to the point where a body has to be read, but the
# prose spelled it as one JQL plus a `gh` lookup per candidate — 13 model turns in the measured run
# (CUBRIDQA-1487), each paying a full model round-trip to learn one boolean. The screens are also the
# kind of thing prose gets subtly wrong under pressure: the measured run judged 8 bodies to process 0,
# and the branch check that would have removed 2 of them ran last instead of first.
#
# Three facts this encodes that a per-candidate loop cannot:
#   * the whole idempotency screen is O(1) network calls, not O(N) — `git ls-remote --heads <url>
#     'tc/cbrd-*'` returns every processed key at once (~0.4s), so the cost no longer grows with the
#     queue.
#   * upstream carries no `tc/cbrd-*` branches at all (every TC PR comes from a fork), so the upstream
#     *branch* check can never fire and only the per-key PR lookup covers "someone else's fork".
#     Checking branches alone silently duplicates another operator's work.
#   * a lookup that FAILED is not a lookup that found nothing. A network error is reported as an
#     incomplete check, never as "no branch exists" — the latter is what makes two people author the
#     same TC.
#
# usage: select-queue.sh [--max N] [--version VER] [--assignee USER] [--json]
set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=common.sh disable=SC1091
. "$SELF_DIR/common.sh" || { printf 'select-queue: common.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }

USAGE='usage: select-queue.sh [--max N] [--version VER] [--assignee USER] [--json]'
MAX=50; VERSION=${CUBRID_PLANNED_VERSION:-guava}; ASSIGNEE=""; AS_JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --max)      MAX="${2:?$USAGE}"; shift 2 ;;
    --version)  VERSION="${2:?$USAGE}"; shift 2 ;;
    --assignee) ASSIGNEE="${2:?$USAGE}"; shift 2 ;;
    --json)     AS_JSON=1; shift ;;
    -h|--help)  printf '%s\n' "$USAGE"; exit 0 ;;
    *)          reject_unknown "$USAGE" "$1" argument ;;
  esac
done

case "$MAX" in ''|*[!0-9]*) printf 'select-queue: --max must be a number\n' >&2; exit 1 ;; esac

for c in cubrid-jira jq git; do
  command -v "$c" >/dev/null 2>&1 || {
    printf 'select-queue: %s is not installed — run /setup-cubrid-agent --install-clis and try again.\n' "$c" >&2
    exit 1; }
done

# env.sh and $TC come from common.sh, sourced at the top.

# ── identity (ADR 0004: resolved per user, never hardcoded) ───────────────────────────────────────
# The guard matters more than the resolution: a wrong-but-plausible $QA_USER returns 0 issues with a
# success exit, which reads as "nothing to author" instead of "your credentials are unresolved". The
# hostname case is the one that actually happened — ad-hoc ~/.netrc parsing yields `jira.cubrid.org`.
QA_USER=${ASSIGNEE:-${CUBRID_JIRA_USER:-}}
if [ -z "$QA_USER" ]; then
  printf 'select-queue: the JIRA username is unresolved (CUBRID_JIRA_USER is empty and ~/.cubrid-agent/env.sh did not set it).\n'   >&2
  printf '  Run /setup-cubrid-agent once, or export CUBRID_JIRA_USER. Do NOT guess it and do NOT parse ~/.netrc.\n' >&2
  exit 1
fi
case "$QA_USER" in
  *.*|*@*) printf 'select-queue: CUBRID_JIRA_USER="%s" looks like a hostname or an e-mail, not a JIRA username — that value returns an empty queue instead of an error. Fix it (or pass --assignee) before running the queue.\n' "$QA_USER" >&2
           exit 1 ;;
esac
FORK=${CUBRID_GH_FORK:-}
[ -n "$FORK" ] || FORK=$(gh api user --jq .login 2>/dev/null) || FORK=""

OUT="$HOME/.cubrid-agent/select-queue.json"
mkdir -p "$HOME/.cubrid-agent" || exit 1
BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── 1. field screen (one JQL) ─────────────────────────────────────────────────────────────────────
# `jql`, never `search`: search renders through pandoc, and a pandoc without the `jira` reader returns
# an empty body with a success exit. Not Required is excluded by the field clause; Duplicate and
# Sub-task are excluded here rather than by reading bodies (they removed 3 of 8 in the measured queue).
JQL="project = CBRD AND cf[213834] = \"$QA_USER\" AND cf[210441] = $VERSION AND status = Resolved"
JQL="$JQL AND cf[210565] in (\"Required\",\"Not Yet\") AND resolution != Duplicate AND issuetype != Sub-task"
JQL="$JQL ORDER BY resolved ASC"
ERR=$(mktemp); trap 'rm -f "$ERR"' EXIT
RAW=$(cubrid-jira jql "$JQL" --fields summary,issuetype,resolutiondate,customfield_210565 \
        --max "$MAX" --output json 2>"$ERR") || {
  rc=$?
  case $rc in
    # One CLI failure must not become many: repeated 401s trip JIRA's CAPTCHA account lock.
    2) printf 'select-queue: JIRA rejected the credentials (401). Do NOT retry — repeated 401s trigger a CAPTCHA account lock. Fix the jira.cubrid.org entry in ~/.netrc first.\n' >&2 ;;
    5) printf 'select-queue: JIRA rejected the query (400) — most often a Planned Version that does not exist (--version %s).\n' "$VERSION" >&2 ;;
    *) printf 'select-queue: cubrid-jira jql failed (exit %s).\n' "$rc" >&2 ;;
  esac
  sed -n '1,3p' "$ERR" >&2
  exit "$rc"
}
CAND=$(printf '%s' "$RAW" | jq -c '[.issues[] | {
          key, resolved: ((.fields.resolutiondate // "")[:10]),
          type: (.fields.issuetype.name // "?"),
          scenario: (.fields.customfield_210565.value // "-"),
          summary: (.fields.summary // "")}]') || {
  printf 'select-queue: could not parse the JQL response.\n' >&2; exit 1; }
NCAND=$(printf '%s' "$CAND" | jq 'length')

# ── 2. idempotency screen (O(1) network calls) ────────────────────────────────────────────────────
# GitHub is the source of truth for "already processed". Each lookup records whether it SUCCEEDED;
# a failed lookup becomes an incomplete-check note, never a silent pass.
INCOMPLETE=""
note_incomplete() { INCOMPLETE="$INCOMPLETE$1"$'\n'; }

remote_keys() { # url -> upper-case keys that have a tc/cbrd-* branch, one per line
  # ls-remote's status is read on its own, NOT at the end of a pipeline: a pipeline reports its last
  # command, so `ls-remote | grep | sort` returns success even when the fetch failed — turning "could
  # not check" into "nothing found", which is the one outcome that duplicates another operator's work.
  local _refs
  _refs=$(git ls-remote --heads "$1" 'tc/cbrd-*' 2>/dev/null) || return 1
  printf '%s\n' "$_refs" | grep -oE 'cbrd-[0-9]+' | tr '[:lower:]' '[:upper:]' | sort -u
}
FORK_KEYS=""
if [ -n "$FORK" ]; then
  if FORK_KEYS=$(remote_keys "https://github.com/$FORK/cubrid-testcases.git"); then :; else
    FORK_KEYS=""; note_incomplete "fork branch check failed (git ls-remote on $FORK/cubrid-testcases) — an issue you already pushed can reappear in this queue"
  fi
else
  note_incomplete "fork owner unknown (CUBRID_GH_FORK unset and gh api user failed) — your own pushed branches were NOT checked"
fi
# Kept even though upstream currently holds no tc/cbrd-* branch: if the convention ever changes, a
# missing check here is a duplicated TC, and the call is 0.4s.
UP_KEYS=$(remote_keys 'https://github.com/CUBRID/cubrid-testcases.git') \
  || { UP_KEYS=""; note_incomplete "upstream branch check failed (git ls-remote on CUBRID/cubrid-testcases)"; }

# Local signals: a committed TC directory, or a local branch. Both are weaker than GitHub (they miss
# what another operator pushed), so they are used as extra drops, never as the only screen.
LOCAL_TC=""; LOCAL_BR=""
if [ -d "$TC/sql" ]; then
  LOCAL_TC=$(find "$TC/sql" -maxdepth 3 -type d -name 'cbrd_[0-9]*' -printf '%f\n' 2>/dev/null \
             | sed 's/^cbrd_/CBRD-/' | sort -u)
fi
if git -C "$TC" rev-parse --git-dir >/dev/null 2>&1; then
  LOCAL_BR=$(git -C "$TC" for-each-ref --format='%(refname:short)' 'refs/heads/tc/cbrd-*' 2>/dev/null \
             | grep -oE 'cbrd-[0-9]+' | tr '[:lower:]' '[:upper:]' | sort -u)
fi

has() { printf '%s\n' "$2" | grep -qx "$1"; }
GH_OK=1
DROPPED='[]'; QUEUE='[]'
while IFS= read -r row; do
  [ -n "$row" ] || continue
  k=$(printf '%s' "$row" | jq -r .key)
  reason=""
  if [ -n "$FORK_KEYS" ] && has "$k" "$FORK_KEYS"; then reason="branch tc/${k,,} exists on your fork ($FORK)"
  elif [ -n "$UP_KEYS" ] && has "$k" "$UP_KEYS"; then reason="branch tc/${k,,} exists upstream"
  # The directory form is cbrd_NNNNN (underscore) while the branch form is tc/cbrd-NNNNN (hyphen);
  # naming the branch form here would send the reader looking for a path that does not exist.
  elif [ -n "$LOCAL_TC" ] && has "$k" "$LOCAL_TC"; then reason="a $(printf '%s' "${k,,}" | tr '-' '_') TC directory already exists in $TC"
  elif [ -n "$LOCAL_BR" ] && has "$k" "$LOCAL_BR"; then reason="local branch tc/${k,,} exists in $TC"
  elif [ "$GH_OK" = 1 ]; then
    # Only reached for keys that survived the free checks, so this is the one per-key call — and the
    # only thing that sees a PR opened from someone else's fork, or one whose branch was deleted.
    if pr=$(gh pr list --repo CUBRID/cubrid-testcases --state all --head "tc/${k,,}" \
              --json number,state,isDraft 2>/dev/null); then
      _p=$(printf '%s' "$pr" | jq -r '.[0] | select(.number) | "PR #\(.number) (\(.state)\(if .isDraft then ", draft" else "" end))"' 2>/dev/null)
      [ -n "$_p" ] && reason="$_p already exists upstream for tc/${k,,}"
    else
      GH_OK=0
      note_incomplete "PR check unavailable (gh is not authenticated) — branch-only detection, so a PR from another fork or one whose branch was deleted is NOT excluded; say this in the report"
    fi
  fi
  if [ -n "$reason" ]; then
    DROPPED=$(printf '%s' "$DROPPED" | jq -c --arg k "$k" --arg r "$reason" '. + [{key:$k, reason:$r}]')
  else
    QUEUE=$(printf '%s' "$QUEUE" | jq -c --argjson row "$row" '. + [$row]')
  fi
done < <(printf '%s' "$CAND" | jq -c '.[]')

# Built once: the same lines land in the queue file and in the head candidate's manifest, and a
# second copy of the conversion is a second place to get it wrong.
INCOMPLETE_JSON=$(printf '%s' "$INCOMPLETE" | jq -R -s 'split("\n") | map(select(length>0))')
NQ=$(printf '%s' "$QUEUE" | jq 'length')
ND=$(printf '%s' "$DROPPED" | jq 'length')
HEAD_KEY=$(printf '%s' "$QUEUE" | jq -r '.[0].key // empty')
# Korean, because this string is report content: render-report.sh prints it verbatim into the Select
# section, and that report is read by the team (AGENTS.md's language policy puts report bodies in Korean while this
# script's own agent-facing output stays English).
SUMMARY="JQL 후보 $NCAND건 → 기계 스크리닝으로 $ND건 제외 → 판단 대기 $NQ건 (assignee=$QA_USER, version=$VERSION, $BUILT)"

jq -n --argjson q "$QUEUE" --argjson d "$DROPPED" --arg j "$JQL" --arg b "$BUILT" \
      --arg u "$QA_USER" --arg v "$VERSION" --arg f "$FORK" --arg s "$SUMMARY" \
      --argjson n "$NCAND" --argjson inc "$INCOMPLETE_JSON" \
  '{built:$b, assignee:$u, version:$v, fork:$f, jql:$j, candidates:$n,
    summary:$s, dropped:$d, queue:$q, checks_incomplete:$inc}' > "$OUT" || exit 1

# The head candidate's manifest gets the queue basis, so the report cites screened numbers instead of
# retyped ones. Only the head: creating run directories for candidates that are never processed would
# litter $HOME with dirs indistinguishable from a human's own (and grounding creates this one anyway).
if [ -n "$HEAD_KEY" ]; then
  _m="$HOME/.cubrid-agent/$HEAD_KEY/manifest.json"
  mkdir -p "$(dirname "$_m")" && { [ -f "$_m" ] || printf '{}' > "$_m"; }
  _t=$(mktemp)
  if jq --arg k "$HEAD_KEY" --arg s "$SUMMARY" --arg b "$BUILT" --argjson d "$DROPPED" \
        --argjson inc "$INCOMPLETE_JSON" \
     '.issue = (.issue // $k)
      | .select.queue = {built:$b, summary:$s, dropped:$d, checks_incomplete:$inc}' \
     "$_m" > "$_t" 2>/dev/null; then mv "$_t" "$_m"; else rm -f "$_t"; fi
fi

if [ "$AS_JSON" = 1 ]; then cat "$OUT"; exit $([ "$NQ" -gt 0 ] && echo 0 || echo 3); fi

printf '[select] %s candidate(s) from JQL, %s screened out, %s left to judge (assignee=%s, version=%s)\n' \
  "$NCAND" "$ND" "$NQ" "$QA_USER" "$VERSION"
printf '%s' "$DROPPED" | jq -r '.[] | "  drop \(.key)  \(.reason)"'
if [ "$NQ" -gt 0 ]; then
  printf '  ---- queue (oldest resolved first) ----\n'
  printf '%s' "$QUEUE" | jq -r 'to_entries[] | "  \(.key+1) \(.value.key)  \(.value.resolved)  \(.value.type) / \(.value.scenario)  \(.value.summary[:64])"'
fi
printf '  queue  : %s\n' "$OUT"
[ -n "$HEAD_KEY" ] && printf '  recorded: select.queue in the manifest of %s\n' "$HEAD_KEY"
printf '%s' "$INCOMPLETE" | while IFS= read -r l; do [ -n "$l" ] && printf '  INCOMPLETE: %s\n' "$l"; done
if [ "$NQ" -eq 0 ]; then
  printf '  queue is empty — every candidate is already processed or was screened out. Say so and STOP;\n'
  printf '  broadening Select (another Planned Version or QA Assignee) is the human'\''s decision.\n'
  exit 3
fi
printf '  NOT decided (your judgment): reproduction present · SQL-reproducible via the sql driver · whether an existing TC already covers the repro under another name\n'
printf '  next   : ground-issue.sh %s, judge that ONE body, and stop at the first candidate that passes.\n' "$HEAD_KEY"
exit 0
