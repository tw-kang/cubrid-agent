#!/bin/bash
# TC PR submission gate — block submission until the run manifest confirms every gate.
# Event: PreToolUse / Bash. Manifest: $HOME/.cubrid-agent/<CBRD-XXXXX>/manifest.json (written by author-testcase).
# Trusted-teammate guardrail: catches a skipped gate, not adversarial bypass.
set -u

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Gate only TC PR creation against cubrid-testcases; leave every other command alone.
printf '%s' "$COMMAND" | grep -qE 'gh[[:space:]]+pr[[:space:]]+create' || exit 0
printf '%s' "$COMMAND" | grep -q 'cubrid-testcases' || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' >&2
  exit 2
}

KEY=$(printf '%s' "$COMMAND" | grep -oiE 'tc/cbrd-[0-9]+' | head -1 | grep -oiE 'cbrd-[0-9]+' | tr '[:lower:]' '[:upper:]')
[ -n "$KEY" ] || deny "TC PR submission gate: could not find a tc/cbrd-XXXXX branch in the command (expects the --head <your-fork>:tc/cbrd-XXXXX form)."

MANIFEST="$HOME/.cubrid-agent/$KEY/manifest.json"
[ -f "$MANIFEST" ] || deny "TC PR submission gate: no manifest for $KEY ($MANIFEST). author-testcase must record the gate results before submission is allowed."

det=$(jq -r '.verify.determinism.all_pass // false' "$MANIFEST")
ftp=$(jq -r '.verify.fail_to_pass.status // "missing"' "$MANIFEST")
note=$(jq -r '.verify.fail_to_pass.note // ""' "$MANIFEST")
appr=$(jq -r '.review.failpass_approved // false' "$MANIFEST")
verdict=$(jq -r '.review.verdict // "missing"' "$MANIFEST")
cci=$(jq -r '.verify.cci.checked // false' "$MANIFEST")
# Absent means "not run", so it denies — unlike the lint keys below, which default to true when absent
# because those manifests predate the check and the hook writes them on every TC write. A verification
# nobody performed cannot be inferred from a file, which is why cci and debug are the other way round.
# `has`, not `//`: jq's // substitutes for `false` too, so `.verify.debug.checked // false` cannot tell
# a recorded false from a missing key — and this check has to distinguish "the debug run said so" from
# "nobody ran it". Same reason the lint block below tests for the key.
dbg=$(jq -r 'if ((.verify.debug // {}) | has("checked")) then (.verify.debug.checked|tostring) else "missing" end' "$MANIFEST")
dbgr=$(jq -r '.verify.debug.result // "missing"' "$MANIFEST")
dbgn=$(jq -r '.verify.debug.note // ""' "$MANIFEST")
# header_scope / header_size / header_no_dashdash / placement default to true only when ABSENT: all three were added
# after the first runs (CUBRIDQA-1481, -1486), and the lint hook writes them on every TC .sql write,
# so only pre-existing manifests lack them. Test for the key rather than writing
# `.lint.header_scope // true` — jq's `//` substitutes for `false` as well as null, so that form
# would turn a real violation into a pass, i.e. a check that cannot fail. It also matters for
# `placement`, which the hook writes as **null** when Select did not record the issue type needed
# to decide: present-but-null must block (unverifiable placement is not a pass), while a manifest
# that predates the check keeps passing.
_dflt='def d(k): if ((.lint // {})|has(k)) then .lint[k] else true end;'
lint=$(jq -r "$_dflt"'[.lint.header,.lint.evaluate,.lint.cleanup,.lint.answer_not_handwritten,.lint.english_comments,d("header_scope"),d("header_size"),d("header_no_dashdash"),d("placement")]|all' "$MANIFEST" 2>/dev/null)

p=""
[ "$det" = true ] || p="$p\n- determinism not confirmed (verify.determinism.all_pass≠true)"
if [ "$ftp" = confirmed ] || { [ "$ftp" = best_effort ] && [ "$appr" = true ] && [ -n "$note" ]; }; then :; else
  p="$p\n- fail→pass not satisfied (status=$ftp, approved=$appr, note=$([ -n "$note" ] && echo present || echo absent)) — needs confirmed, or best_effort + review approval + note"
fi
[ "$verdict" = PASS ] || p="$p\n- review not passed (review.verdict=$verdict)"
[ "$cci" = true ] || p="$p\n- CCI cross-check not run (verify.cci.checked≠true) — cross-check with sql_by_cci; if it differs from the default sql (JDBC) output, add .answer_cci"
[ "$lint" = true ] || p="$p\n- convention lint not satisfied (some lint.* is false — see the PostToolUse lint hook)"
# The debug build is where CI finds an assert this TC trips, and it attributes it to the TC. An assert
# is never an answer to adjust — it is an engine finding — so it blocks rather than asking for a note,
# while a plain output difference can be explained (debug-only messages are a real cause).
case "$dbg/$dbgr" in
  true/clean) ;;
  true/differs)
    [ -n "$dbgn" ] || p="$p\n- the debug run's output differs from the release answer and nothing explains it — put why in verify.debug.note (debug-only messages are a legitimate cause), or fix the testcase; never promote debug output into .answer" ;;
  true/assert)
    # The only result with no self-service escape, because "the engine asserted" is not something the
    # author can answer away. It can still be cleared, but only by a reviewer accepting it as outside
    # this TC's scope — the same shape as review.failpass_approved for a best_effort fail→pass.
    if [ "$(jq -r '.review.debug_approved // false' "$MANIFEST")" = true ] && [ -n "$dbgn" ]; then :; else
      p="$p\n- the debug build tripped an assertion or crashed on this testcase (see verify.debug.marker) — an engine finding for the developer, not an answer to adjust. It clears only when a reviewer accepts it as out of this testcase's scope: review.debug_approved=true plus verify.debug.note"
    fi ;;
  *)
    p="$p\n- debug build not checked (verify.debug.checked=$dbg, result=$dbgr) — run ~/.cubrid-agent/bin/debug-check.sh $KEY; CI runs debug regression and an assert found there is attributed to this testcase" ;;
esac

# The body must be render-pr-body.sh's output, not prose (CUBRIDQA-1487). author-testcase says
# "generate it, do not compose it" and nothing enforced it, so two defects reached reviewers: the
# renderer's `TODO` placeholders shipping as the body, and a hand-composed count disagreeing with
# the .sql ("8 cases" against 7 — PR #3041). The generated path is derived from the key, so the
# check is exact; requiring it also enforces the generate rule itself, where reading whatever body
# happens to be readable would go silent in precisely the case it exists for.
# --draft is NOT exempt: the renderer runs for batch calls too, and a draft body is still what a
# reviewer reads. The command text is pre-expansion, so $HOME/~ can arrive literal — normalize both.
BODY_EXPECT="$HOME/.cubrid-agent/$KEY/pr-body.md"
BODY=$(printf '%s' "$COMMAND" | grep -oE -- '(--body-file|-F)[= ]*[^[:space:]]+' | head -1 \
  | sed -E "s/^(--body-file|-F)[= ]*//; s/^['\"]//; s/['\"]$//")
BODY=${BODY/#\~/$HOME}; BODY=${BODY//\$\{HOME\}/$HOME}; BODY=${BODY//\$HOME/$HOME}
_fix="generate it: ~/.cubrid-agent/bin/render-pr-body.sh $KEY, write the two TODO sections, then pass --body-file $BODY_EXPECT"
if [ -z "$BODY" ]; then
  _how=$(printf '%s' "$COMMAND" | grep -qE -- '(--body|-b)[= ]|--fill' && printf ' (the command passes --body/--fill instead)')
  p="$p\n- PR body is not the generated one — no --body-file/-F in the command${_how:-} — $_fix"
elif [ "$BODY" != "$BODY_EXPECT" ]; then
  p="$p\n- PR body comes from $BODY, not the generated $BODY_EXPECT — a hand-composed body is how the case count drifts from the .sql; $_fix"
elif [ ! -f "$BODY" ]; then
  p="$p\n- PR body file $BODY does not exist — $_fix"
else
  _miss=""
  for _h in '### Purpose' '### Implementation' '### Remarks'; do
    grep -qF "$_h" "$BODY" || _miss="$_miss ${_h#'### '}"
  done
  [ -n "$_miss" ] && p="$p\n- PR body is missing section(s):$_miss — re-render with --force (your Purpose/Implementation text would be lost, so copy it out first)"
  grep -q "browse/$KEY" "$BODY" || p="$p\n- PR body has no jira link for $KEY"
  grep -qE '^TODO[[:space:]]*$' "$BODY" \
    && p="$p\n- PR body still carries the renderer's TODO placeholder — Purpose and Implementation are yours to write (Korean, user-perspective: what was wrong, and what this TC verifies)"
  grep -q '케이스 ?개' "$BODY" \
    && p="$p\n- PR body's case count is '?' — the renderer could not read the .sql (author.path missing from the manifest). Fix the manifest, then re-render with --force"
fi

# Base sanity: the branch must differ from CUBRID's develop ONLY inside this TC's own directory.
# author-testcase says to cut the branch from `origin/develop`, which assumes a clone that setup.sh
# provisioned (it clones from CUBRID, so origin points there). A hand-made clone can have no origin
# at all, or origin pointing at a fork, and then the base is whatever branch happened to be checked
# out — on this developer's machine that was a fork-only feature branch sitting 62 commits behind
# upstream with 1,630 files changed. Cutting a TC branch there produces a PR carrying all of it, and
# nothing upstream would have stopped it. The stray-file test catches every version of this (wrong
# base, unrelated commits, an accidental edit) without a network call.
# Limits, on purpose: if the clone is not at $CUBRID_TESTCASES or ~/cubrid-testcases we skip rather
# than guess — a false deny here strands an hour of finished work. Same reason the message names the
# stray files and the recovery: a stale origin/develop ref is the one way this can misfire.
TC=${CUBRID_TESTCASES:-$HOME/cubrid-testcases}
BR=$(printf '%s' "$COMMAND" | grep -oiE 'tc/cbrd-[0-9]+' | head -1)
_base=$(printf '%s' "$KEY" | tr '[:upper:]-' '[:lower:]_')   # CBRD-26431 -> cbrd_26431
# Ask git rather than testing for a .git directory: in a worktree .git is a file, and that test
# would make this whole check skip silently on any worktree-based clone.
if git -C "$TC" rev-parse --git-dir >/dev/null 2>&1 && [ -n "$BR" ] && git -C "$TC" rev-parse --verify -q "$BR" >/dev/null 2>&1; then
  _ourl=$(git -C "$TC" config --get remote.origin.url 2>/dev/null) || _ourl=""
  case "$_ourl" in
    *CUBRID/cubrid-testcases*) ;;
    "") p="$p\n- $TC has no 'origin' remote, so the base the skill cuts from (origin/develop) does not exist — git -C $TC remote add origin https://github.com/CUBRID/cubrid-testcases.git && git -C $TC fetch origin develop" ;;
    *)  p="$p\n- $TC's 'origin' is $_ourl, not CUBRID/cubrid-testcases — the branch would be based on someone's fork; point origin at CUBRID (keep your fork as the 'fork' remote)" ;;
  esac
  if git -C "$TC" rev-parse --verify -q origin/develop >/dev/null 2>&1; then
    _mb=$(git -C "$TC" merge-base origin/develop "$BR" 2>/dev/null)
    if [ -n "$_mb" ]; then
      # A TC directory exists only in the release layout; every bug fix goes to _13_issues/_YY_Nh/,
      # whose cases/ and answers/ the whole half-year shares. Filtering on a directory therefore
      # called the TC's own files strays and denied a correct submission — with a recovery hint
      # (fetch origin/develop) that could never clear it. Both layouts name the files after the key,
      # and so do an issue's suffixed .sql files, so the filename is what decides membership.
      _out=$(git -C "$TC" diff --name-only "$_mb".."$BR" 2>/dev/null | grep -vE "/${_base}[._]")
      _n=$(printf '%s' "$_out" | grep -c . )
      if [ "${_n:-0}" -gt 0 ]; then
        p="$p\n- the branch changes $_n file(s) that are not this TC's ($_base.*) — the base is wrong or unrelated commits came along: $(printf '%s' "$_out" | head -3 | tr '\n' ' ')… If the branch really is based on a newer develop, run: git -C $TC fetch origin develop, then submit again"
      fi
    fi
  else
    p="$p\n- origin/develop is not in $TC, so the branch's base cannot be verified — git -C $TC fetch origin develop"
  fi
fi

# Re-authoring an issue that already has an upstream PR has to be a decision, not an accident. A
# targeted call (/author-testcase CBRD-XXXXX) deliberately skips Select's already-processed screen —
# that is how a TC gets redone on purpose — so this does not forbid it, it requires the reason to be
# recorded. What it actually catches is the case branch checks cannot: a PR opened from ANOTHER
# operator's fork, or one whose branch was since deleted. For a PR on your own fork §7's push has
# already updated it before this hook runs, so the deny arrives late — it still says where to look.
# `gh` failure is never a deny (a false deny strands an hour of finished work, same trade as the base
# check above), and neither is a recorded reason, however short.
_reason=$(jq -r '(.select.reauthor_reason // "") | tostring' "$MANIFEST" 2>/dev/null)
if [ -z "$_reason" ] && [ -n "$BR" ] && command -v gh >/dev/null 2>&1; then
  _lbr=$(printf '%s' "$BR" | tr '[:upper:]' '[:lower:]')
  if _prs=$(gh pr list --repo CUBRID/cubrid-testcases --state all --head "$_lbr" \
              --json number,state,author 2>/dev/null); then
    _pr=$(printf '%s' "$_prs" | jq -r '.[0] | select(.number) | "#\(.number) (\(.state), \(.author.login // "?"))"' 2>/dev/null)
    [ -n "$_pr" ] && p="$p\n- PR $_pr already exists upstream for $_lbr, and the manifest records no reason for redoing it — if this is a deliberate re-author, put why in .select.reauthor_reason (jq '.select.reauthor_reason = \"<why>\"'); if it is not, you are about to duplicate that PR's work"
  fi
fi

[ -z "$p" ] || deny "$(printf 'TC PR submission gate: %s not satisfied:%b' "$KEY" "$p")"
exit 0
