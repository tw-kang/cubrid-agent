#!/bin/bash
# Prep-phase reconnaissance in ONE call: the environment this run needs, where the testcase goes,
# what the corpus already covers, and how far the run has got. Installed to ~/.cubrid-agent/bin/ by
# /setup-cubrid-agent.
#
# Why one call: a tool call costs ~13s here, most of it the thinking that precedes it, so eight
# separate look-ups cost eight times that plus eight separate deliberations (CUBRIDQA-1507).
#
# Everything here is a READ — no writes, no network. That is what lets the orchestrator and the
# author lane both call it, in any order, without one of them having to run first.
#
# It reports facts and never decides — the two it deliberately hands back are named in its own
# closing line, so the caller reads them without opening this file.
#
# usage: scout.sh [CBRD-XXXXX] [--grep PATTERN]...
#   With no key, the environment and the pattern search still answer; the three things that need an
#   issue (its tree, its own TC, its run state) say that a key was not given.
set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=common.sh disable=SC1091
. "$SELF_DIR/common.sh" || { printf 'scout: common.sh is not next to me (%s) — re-run /setup-cubrid-agent.\n' "$SELF_DIR" >&2; exit 1; }

USAGE='usage: scout.sh [CBRD-XXXXX] [--grep PATTERN]...'
KEY=""; PATTERNS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --grep)    PATTERNS="$PATTERNS${2:?$USAGE}"$'\n'; shift 2 ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*)        reject_unknown "$USAGE" "$1" ;;
    *)         KEY=$(parse_issue_key "$1"); shift ;;
  esac
done
# A missing prerequisite for the scout ITSELF is a stop, not a finding: with no jq there is no
# manifest to read and no answer to give.
for c in git jq; do
  command -v "$c" >/dev/null 2>&1 \
    || { printf 'scout: %s is not installed, so nothing here can be answered — run /setup-cubrid-agent --install-clis.\n' "$c" >&2; exit 1; }
done
git -C "$TC" rev-parse --git-dir >/dev/null 2>&1 \
  || { printf 'scout: %s is not a git clone, so there is no corpus to scout — run /setup-cubrid-agent (or point CUBRID_TESTCASES at the clone).\n' "$TC" >&2; exit 1; }

# The key is optional, because the environment half of the answer does not depend on one and
# create-sql is reachable without a CBRD number ("새 sql testcase" with no issue). Without a key the
# three answers that need an issue say so rather than the whole call refusing.
NUM=""; BR=""; RUN_DIR=""; MANIFEST=""
if [ -n "$KEY" ]; then
  NUM=$(printf '%s' "$KEY" | grep -oE '[0-9]+')
  BR="tc/$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')"
  RUN_DIR="$HOME/.cubrid-agent/$KEY"
  MANIFEST="$RUN_DIR/manifest.json"
fi

# Each entry names the thing and what its absence costs, because "not found" alone sends the reader
# looking for the wrong fix.
MISS=""
miss() { MISS="$MISS  MISSING: $1"$'\n'; }

# ── 1. environment ───────────────────────────────────────────────────────────────────────────────
# The list is the one setup.sh installs (check-invariants pins the two together): a helper absent
# here fails at its own stage with an errno and no cause.
HELPERS='common.sh ground-issue.sh select-queue.sh prepare-tc-workspace.sh render-pr-body.sh verify-run.sh build-swap.sh failpass-run.sh debug-check.sh record-preconditions.sh render-report.sh scout.sh'
NH=0; NOK=0; HMISS=""
for h in $HELPERS; do
  NH=$((NH+1))
  if [ -f "$HOME/.cubrid-agent/bin/$h" ]; then NOK=$((NOK+1)); else HMISS="$HMISS $h"; fi
done
[ -z "$HMISS" ] || miss "helper(s)$HMISS not in ~/.cubrid-agent/bin/ — the stage that calls one dies on an errno with no reason given. Run /setup-cubrid-agent to install them."

# Same resolution order as verify-run.sh, so what the scout reports is what CTP will actually use.
CTP=${CTP_HOME:-}
if [ -z "$CTP" ] || [ ! -x "$CTP/bin/ctp.sh" ]; then
  CTP=""
  for d in "$HOME/CTP" "$HOME/cubrid-testtools/CTP"; do [ -x "$d/bin/ctp.sh" ] && CTP=$d && break; done
fi
[ -n "$CTP" ] \
  || miss "CTP — not at \$CTP_HOME, ~/CTP or ~/cubrid-testtools/CTP. Select/Ground/Author still run; Verify cannot, and its terminal state is verify.status=\"blocked_no_ctp\" + verify.note."

CUB=${CUBRID:-$HOME/CUBRID}
BUILD=""; BTYPE=""
if [ -x "$CUB/bin/cubrid_rel" ]; then
  _rel=$("$CUB/bin/cubrid_rel" 2>/dev/null)
  BUILD=$(printf '%s' "$_rel" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(-[0-9a-f]+)?' | head -1)
  BTYPE=$(printf '%s' "$_rel" | grep -oiE '(release|debug) build' | head -1 | tr '[:upper:]' '[:lower:]' | cut -d' ' -f1)
fi
[ -n "$BUILD" ] \
  || miss "CUBRID build — cubrid_rel reports no version under $CUB. Authoring still runs; the answer cannot be generated, and its terminal state is verify.status=\"blocked_no_build\" + verify.note. /setup-cubrid-agent --build <url> installs one."

# Identity is read, never resolved over the network (ADR 0004: read it, never hardcode a person).
QA_USER=${CUBRID_JIRA_USER:-}
case "$QA_USER" in
  '')    miss "JIRA username — CUBRID_JIRA_USER is empty and ~/.cubrid-agent/env.sh did not set it. An empty value yields a 0-issue queue instead of an error. Run /setup-cubrid-agent once, or export it; do not guess it and do not parse ~/.netrc." ;;
  *.*|*@*) miss "JIRA username — CUBRID_JIRA_USER=\"$QA_USER\" looks like a hostname or an e-mail rather than a JIRA username, which returns an empty queue instead of an error."; QA_USER="" ;;
esac
# The fork remote already carries the owner, so the answer costs no `gh api user` round trip.
FORK=${CUBRID_GH_FORK:-}
[ -n "$FORK" ] || FORK=$(git -C "$TC" remote get-url fork 2>/dev/null | sed -n 's#.*[/:]\([^/]*\)/cubrid-testcases\(\.git\)\{0,1\}$#\1#p')
[ -n "$FORK" ] \
  || miss "fork owner — no \$CUBRID_GH_FORK and no 'fork' remote on $TC, so Submit has no head to push to. /setup-cubrid-agent adds the remote."
command -v cubrid-jira >/dev/null 2>&1 \
  || miss "cubrid-jira — Ground cannot read the issue body, comments or attachments. /setup-cubrid-agent --install-clis"
if ! command -v gh >/dev/null 2>&1; then
  miss "gh — Submit cannot open the PR, and Select's PR screen degrades to branch-only. /setup-cubrid-agent --install-clis"
# `gh auth token` reads the local credential store; `gh auth status` would call the API and break the
# no-network contract. The token itself is discarded — only whether one exists is worth reporting,
# and echoing it would put a credential in a transcript (CUBRIDQA-1488).
elif [ -z "${GH_TOKEN:-}" ] && ! gh auth token >/dev/null 2>&1; then
  miss "gh credentials — gh is installed but holds no token, so the PR call fails at the very end of the run. Run gh auth login (or export GH_TOKEN)."
fi

# Ground reads the fix diff here. Without the clone, grounding reports "no commit mentioning this
# key" — which reads as "the fix is not on develop" rather than "there is nothing here to search".
CUBRID_SRC=${CUBRID_SRC:-$HOME/cubrid}
git -C "$CUBRID_SRC" rev-parse --git-dir >/dev/null 2>&1 \
  || miss "cubrid source — $CUBRID_SRC is not a git clone, so Ground cannot mark the fix's code path and reports the fix commit as simply not found. /setup-cubrid-agent clones it."

ORIGIN=$(git -C "$TC" remote get-url origin 2>/dev/null)
case "$ORIGIN" in
  *[Cc][Uu][Bb][Rr][Ii][Dd]/cubrid-testcases*) ;;
  *) miss "upstream origin — origin of $TC is ${ORIGIN:-unset}, not CUBRID/cubrid-testcases, so the branch would be based on another repository's develop and the submit gate denies it." ;;
esac
TC_BRANCH=$(git -C "$TC" rev-parse --abbrev-ref HEAD 2>/dev/null)
TC_DIRTY=$(git -C "$TC" status --porcelain 2>/dev/null | head -1)
# Where the branch already lives, if anywhere: on a retry that path IS the workspace, and knowing it
# here is what keeps the caller from authoring into the clone by mistake.
BR_AT=$(tc_root_for_branch "$TC" "$BR")

# ── 2. where the testcase goes ───────────────────────────────────────────────────────────────────
# The issue type alone selects the tree, and it comes from JIRA via grounding — never from a version
# field. Reported, not decided: create-sql's directory convention names the file.
ITYPE=""
[ -n "$MANIFEST" ] && ITYPE=$(jq -r '.select.issue_type // empty' "$MANIFEST" 2>/dev/null)
CURHY="_$(date +%y)_$([ "$(date +%-m)" -le 6 ] && echo 1 || echo 2)h"
TARGET=""; WHERE=""
if [ -z "$KEY" ]; then
  WHERE="no issue key given — the tree follows from the issue type, so name CBRD-XXXXX to have it reported"
elif [ -z "$ITYPE" ]; then
  WHERE="issue type not recorded — ground-issue.sh writes select.issue_type, and until it does the tree cannot be named and lint.placement stays unverifiable (which blocks submit)"
elif [ "$ITYPE" = "Correct Error" ]; then
  TARGET="sql/_13_issues/$CURHY"
  if [ -d "$TC/$TARGET/cases" ]; then
    WHERE="\"$ITYPE\" (a bug fix) → $TARGET/cases/ — exists, $(find "$TC/$TARGET/cases" -maxdepth 1 -name 'cbrd_*.sql' 2>/dev/null | grep -c .) case(s)"
  else
    WHERE="\"$ITYPE\" (a bug fix) → $TARGET/cases/ — does NOT exist yet; create it (the half-year you write in, not any date on the issue)"
  fi
else
  WHERE="\"$ITYPE\" (not a bug fix) → a release dir, sql/_NN_<release>/cbrd_$NUM/cases/ — create-sql's convention picks the release; the ones here: $(find "$TC/sql" -maxdepth 1 -type d -name '_[0-9][0-9]_*' -printf '%f\n' 2>/dev/null | grep -v '^_13_issues$' | sort | tr '\n' ' ')"
fi
# Paths are printed relative to the clone: the caller reads them, and an absolute prefix repeated on
# every line pushes the part that differs off the end.
rel() { printf '%s' "${1#"$TC"/}"; }
rel_list() { while IFS= read -r _p; do [ -n "$_p" ] && printf '%s ' "$(rel "$_p")"; done; }

# Read one sibling before writing: it documents the area's conventions (which hints force the plan,
# how the data is sized). Fall back to the newest half-year that has cases, so a not-yet-created
# target still yields a reference.
SIB_DIR="$TC/$TARGET/cases"
[ -n "$TARGET" ] && [ -d "$SIB_DIR" ] \
  || SIB_DIR=$(find "$TC/sql/_13_issues" -maxdepth 2 -type d -name cases 2>/dev/null | sort | tail -1)
SIBS=$(find "$SIB_DIR" -maxdepth 1 -name 'cbrd_*.sql' 2>/dev/null | sort -r | head -3 | rel_list)

# ── 3. existing coverage ─────────────────────────────────────────────────────────────────────────
# By name first — cheap and exact. By repro second, because the same repro may already exist under
# another name, which no name search can see.
COVER=""; BYNAME=""
if [ -z "$KEY" ]; then
  COVER="no issue key given — name CBRD-XXXXX to have its own TC looked for by name"
else
  BYNAME=$(find "$TC/sql" -maxdepth 6 -name "cbrd_$NUM*" 2>/dev/null | sort | head -10 | rel_list)
  if [ -n "$BYNAME" ]; then
    COVER="cbrd_$NUM already exists in the corpus: $BYNAME"
  else
    COVER="no cbrd_$NUM file or directory in the corpus"
  fi
fi
# A pattern that matches hundreds of files has told you nothing about THIS repro, and printing the
# first few would read as "here is the prior art". Report the count and say to narrow it.
BYGREP=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  # `*.sql`, not `cbrd_*.sql`: the whole point of a content search is the testcase filed under
  # ANOTHER name, and only 854 of the corpus's 17,394 case files are named for a cbrd key. Every one
  # of them sits under a cases/ dir, so the extension alone excludes the answers and docs.
  # --include goes BEFORE the `--`: after it, it is a file operand rather than an option, and both
  # GNU grep 3.1 and ugrep 7.5 then read every file under sql/ while reporting the failure only on
  # the stderr this discards.
  _hits=$(grep -rlEi --include='*.sql' -- "$p" "$TC/sql" 2>/dev/null | sort)
  _n=$(printf '%s' "$_hits" | grep -c .)
  if [ "$_n" -eq 0 ]; then _w="→ 0 file(s)"
  elif [ "$_n" -gt 12 ]; then _w="→ $_n file(s) — too broad to be prior art; narrow it to the repro's own tables/query shape"
  else _w="→ $_n file(s): $(printf '%s\n' "$_hits" | rel_list)"
  fi
  BYGREP="$BYGREP    --grep '$p' $_w"$'\n'
done <<EOF
$PATTERNS
EOF
[ -n "$PATTERNS" ] \
  || BYGREP="    (no --grep pattern given — a testcase covering the same repro under another name stays invisible to the name search above; pass the repro's tables/query shape)"$'\n'

# ── 4. how far this run has got ──────────────────────────────────────────────────────────────────
if [ -z "$KEY" ]; then
  RUN="no issue key given — no run directory to read"
elif [ -f "$MANIFEST" ]; then
  RUN=$(jq -r '
    (([.lint // {} | to_entries[] | select(.value == false)] | length)) as $bad |
    (([.lint // {} | to_entries[] | select(.value != null)] | length)) as $all |
    "select " + (if .select.queue then "queued" else "-" end)
    + " · type " + (.select.issue_type // "-")
    + " · fix " + ((.ground.fix_commit // "-") | split(" ")[0])
    + " · lint " + (if $all == 0 then "-" else "\($all - $bad)/\($all)" end)
    + " · verify " + (.verify.status // "-")
    + " · review " + (.review.verdict // "-")
    + " · submitted " + ((.submitted // false) | tostring)' "$MANIFEST" 2>/dev/null)
  [ -n "$RUN" ] || RUN="manifest present but unreadable: $MANIFEST"
else
  RUN="no manifest yet — this is a fresh run (select-queue.sh and ground-issue.sh create it)"
fi

# ── report ───────────────────────────────────────────────────────────────────────────────────────
BUILD_S=${BUILD:+$BUILD (${BTYPE:-type unknown})}
printf '[scout] %s — one prep call%s\n' "${KEY:-(no issue key)}" "${RUN_DIR:+ (run dir: $RUN_DIR)}"
printf '  env    : helpers %s/%s · CTP %s · build %s · jira %s · fork %s\n' \
  "$NOK" "$NH" "${CTP:-none}" "${BUILD_S:-none}" "${QA_USER:-none}" "${FORK:-none}"
printf '  tc     : %s  (origin %s, on %s%s)\n' \
  "$TC" "${ORIGIN:-unset}" "${TC_BRANCH:-?}" "$([ -n "$TC_DIRTY" ] && printf ', uncommitted work — prepare-tc-workspace.sh will cut a worktree')"
[ -n "$BR_AT" ] && printf '           %s is already checked out at %s — that path is the workspace for this run\n' "$BR" "$BR_AT"
printf '  where  : %s\n' "$WHERE"
[ -n "$SIBS" ] && printf '           read a sibling header first (area conventions): %s\n' "$SIBS"
printf '  cover  : %s\n' "$COVER"
printf '%s' "$BYGREP"
printf '  run    : %s\n' "$RUN"
if [ -n "$MISS" ]; then
  printf '%s' "$MISS"
  printf '  stop   : the MISSING line(s) name what is absent and what each one costs. Install them, or take the reduced path each names — never verify on what is not there.\n'
  exit 3
fi
printf '  next   : read the sibling header(s) above and the fix diff; nothing else in the prep phase needs a call.\n'
printf '           NOT decided here (yours): whether this build contains the issue'\''s fix, and the TC'\''s final path (create-sql'\''s directory convention).\n'
exit 0
