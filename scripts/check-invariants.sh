#!/bin/bash
# Repo invariants — the machine seam for rules this repo has broken silently before.
#
# Dev-only: not a hook, never invoked by a skill. Run by hand or from CI.
# Deterministic and offline (git, jq, grep, sed only). `claude plugin validate` runs when present.
set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 1; }

FAILED=0
group() { printf '\n== %s ==\n' "$1"; }
pass()  { printf '  ok   %s\n' "$1"; }
fail()  { printf '  FAIL %s\n' "$1"; FAILED=$((FAILED+1)); }

# Rule checks glob `skills/*/` so they sweep both trees; only shipped-set checks name skills/qa/.

# Skills that read a CBRD issue. `cubrid-jira search` returns an empty body with a SUCCESS exit when
# pandoc lacks the `jira` reader, so each must use the raw JSON read.
ISSUE_READERS=$(printf '%s\n' skills/*/create-*/SKILL.md skills/*/verify-*/SKILL.md \
  skills/qa/author-testcase/SKILL.md skills/qa/gate-resolved/SKILL.md \
  skills/qa/review-testcase/SKILL.md)

# ---------------------------------------------------------------------------
group "Non-product doc set (CUBRIDQA-1454: repo keeps the product, design lives in Jira)"

# .agents/ is the normative set: four norm docs plus numbered ADRs. Nothing else.
_agents_unexpected=$(git ls-files '.agents/*' \
  | grep -v -E '^\.agents/(domain|design-principles|issue-tracker|triage-labels)\.md$' \
  | grep -v -E '^\.agents/adr/[0-9]{4}-[a-z0-9-]+\.md$')
if [ -z "$_agents_unexpected" ]; then pass ".agents/ holds only the norm docs + numbered ADRs"
else fail ".agents/ has unexpected files:"; printf '         %s\n' $_agents_unexpected; fi

# docs/ keeps runbooks, the reference shelf, and PoC evidence reports — not design docs.
_docs_unexpected=$(git ls-files 'docs/*' \
  | grep -v -E '^docs/(deployment|dev-process|setup)\.md$' \
  | grep -v -E '^docs/reference/' \
  | grep -v -E '^docs/agents/[a-z-]+/reports/')
if [ -z "$_docs_unexpected" ]; then pass "docs/ holds only runbooks, reference and PoC reports"
else fail "docs/ has unexpected files:"; printf '         %s\n' $_docs_unexpected; fi

# Paths 1454 removed. Their return means design crept back into the repo.
for p in docs/adr docs/CONTEXT-MAP.md docs/staging.md docs/guides; do
  if [ -n "$(git ls-files "$p" "$p/*" 2>/dev/null)" ]; then fail "removed by 1454, back in git: $p"; fi
done
_design_back=$(git ls-files 'docs/agents/*' | grep -E '/(DESIGN|CONTEXT)\.md$')
if [ -z "$_design_back" ]; then pass "no DESIGN.md / CONTEXT.md under docs/agents/ (they live in Jira)"
else fail "design docs back in repo:"; printf '         %s\n' $_design_back; fi

# Stage numbering belongs in Jira, not the product. CHANGELOG, the ADRs and this file are excluded.
_staged=$(git ls-files | grep -v -E '^(CHANGELOG\.md|\.agents/adr/|scripts/check-invariants\.sh$)' \
  | while read -r f; do [ -f "$f" ] && grep -lE '[Ss]tage[ _-]?[0-9]|스테이지' "$f" 2>/dev/null; done)
if [ -z "$_staged" ]; then
  pass "no stage bookkeeping outside CHANGELOG and the ADRs (rollout lives in CUBRIDQA-1425)"
else
  fail "rollout-stage labels are back in the repo — move them to CUBRIDQA-1425:"; printf '         %s\n' $_staged
fi

# An agent reads AGENTS.md first, so the two method rules must be in that file, not only in .agents/.
_m=""
grep -q '개발 방식' AGENTS.md                      || _m="$_m the-section"
grep -q '코드로 가능한 것은 최대한 코드로' AGENTS.md  || _m="$_m code-first-rule"
grep -q '/code-review' AGENTS.md                    || _m="$_m skill-chain"
grep -q 'CUBRIDQA-1425' AGENTS.md                   || _m="$_m ticket-first-check"
grep -q '^## DP6' .agents/design-principles.md      || _m="$_m DP6"
grep -q '한 가지로만 읽히게' AGENTS.md               || _m="$_m unambiguous-once-short"
grep -q '^## DP7' .agents/design-principles.md      || _m="$_m DP7"
# The PR template is a file, linked rather than copied; $FORK guards against a hardcoded person.
grep -qF '.github/PULL_REQUEST_TEMPLATE.md' AGENTS.md || _m="$_m pr-template-link"
grep -q '### Purpose' .github/PULL_REQUEST_TEMPLATE.md || _m="$_m pr-template-headings"
grep -q '### Remarks' .github/PULL_REQUEST_TEMPLATE.md || _m="$_m pr-template-headings"
grep -qF '$FORK:<branch>' AGENTS.md                 || _m="$_m fork-not-a-person"
grep -q '없으면 dry-run' AGENTS.md                  || _m="$_m jira-write-is-dry-run"
if [ -z "$_m" ]; then
  pass "AGENTS.md states the development method (code-first + skill chain) and DP6 backs it"
else
  fail "the development method is missing from where an agent would read it:$_m — a fresh contributor's agent would not see it"
fi

# A pointer whose target is silent reads as "already covered", so the target must carry the rule.
_t=""
grep -q 'CUBRIDQA-1425' .agents/issue-tracker.md          || _t="$_t parent-key"
grep -q '새로 만들지 않는다' .agents/issue-tracker.md      || _t="$_t default-is-no-new-ticket"
grep -q 'to-spec' .agents/issue-tracker.md                || _t="$_t subtask-is-a-spec"
grep -q 'to-tickets' .agents/issue-tracker.md             || _t="$_t task-is-a-work-item"
grep -q 'linkedIssues' .agents/issue-tracker.md           || _t="$_t how-to-read-the-tree"
if [ -z "$_t" ]; then
  pass ".agents/issue-tracker.md carries the ticket rule AGENTS.md points at (default: no new ticket)"
else
  fail "the ticket rule is missing from the file AGENTS.md links for it:$_t — the link would dead-end"
fi

# DP7-2: one fact, one place. CLAUDE.md is excluded — it is the symlink to AGENTS.md.
_dup=""
_lang=$(git ls-files '*.md' | grep -v '^CLAUDE\.md$' | xargs grep -l '\*\*영문(배포 대상)\*\*' 2>/dev/null)
[ "$(printf '%s\n' "$_lang" | grep -c .)" = 1 ] || _dup="$_dup language-policy-list[$(echo $_lang)]"
_lbl=$(git ls-files '*.md' | grep -v '^CLAUDE\.md$' | xargs grep -l '현재 라벨을 읽' 2>/dev/null)
[ "$(printf '%s\n' "$_lbl" | grep -c .)" = 1 ] || _dup="$_dup label-procedure[$(echo $_lbl)]"
if [ -z "$_dup" ]; then
  pass "the language-policy list and the label procedure each live in exactly one file (DP7-2)"
else
  fail "a rule is written in two places and will drift:$_dup — keep one, link from the other"
fi

# ---------------------------------------------------------------------------
group "ADR numbering"

_nums=$(git ls-files '.agents/adr/*.md' | sed -E 's|.*/([0-9]{4})-.*|\1|' | sort)
_dupes=$(printf '%s\n' "$_nums" | uniq -d)
[ -z "$_dupes" ] && pass "ADR numbers unique" || fail "duplicate ADR numbers: $(echo $_dupes)"

_i=0; _gap=""
for n in $_nums; do _i=$((_i+1)); [ "$n" = "$(printf '%04d' $_i)" ] || _gap="$_gap $n"; done
[ -z "$_gap" ] && pass "ADR numbers contiguous from 0001 ($_i ADRs)" \
               || fail "ADR numbering has a gap or does not start at 0001 — at:$_gap"

# ---------------------------------------------------------------------------
group "Agent-instruction entrypoint"

# CLAUDE.md must stay a symlink to AGENTS.md; a copy is how the two drift apart unnoticed.
if [ -L CLAUDE.md ] && [ "$(readlink CLAUDE.md)" = "AGENTS.md" ]; then
  pass "CLAUDE.md is a symlink to AGENTS.md"
else fail "CLAUDE.md must be a symlink to AGENTS.md (found: $(readlink CLAUDE.md 2>/dev/null || echo 'a regular file'))"; fi

# ---------------------------------------------------------------------------
group "Internal markdown links"

_dead=0
while IFS= read -r f; do
  _dir=$(dirname "$f")
  # Every ](target): drop external schemes and pure anchors, resolve the rest relative to the file.
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    case "$t" in http://*|https://*|mailto:*|\#*) continue ;; esac
    t=${t%%#*}; [ -z "$t" ] && continue
    if [ ! -e "$_dir/$t" ]; then fail "dead link in $f -> $t"; _dead=$((_dead+1)); fi
  done <<INNER
$(grep -o ']([^)]*)' "$f" 2>/dev/null | sed 's/^](//; s/)$//')
INNER
done <<EOF
$(git ls-files '*.md')
EOF
[ "$_dead" -eq 0 ] && pass "no dead internal links in $(git ls-files '*.md' | wc -l | tr -d ' ') tracked markdown files"

# ---------------------------------------------------------------------------
group "Plugin manifest vs. what is on disk"

_declared=$(jq -r '.skills[]' .claude-plugin/plugin.json)
for s in $_declared; do
  if [ ! -f "$s/SKILL.md" ]; then fail "plugin.json declares $s but $s/SKILL.md is missing"; continue; fi
  _fm_name=$(sed -n '/^---$/,/^---$/p' "$s/SKILL.md" | sed -n 's/^name:[[:space:]]*//p' | head -1 | tr -d '"')
  [ "$_fm_name" = "$(basename "$s")" ] \
    && pass "declared: $(basename "$s")" \
    || fail "$s/SKILL.md frontmatter name is '$_fm_name', not '$(basename "$s")' — the invocation name would not match the path"
done

# Docs may only advertise `/cubrid-agent:<skill>` for skills the plugin actually loads.
_declared_names=$(for s in $_declared; do basename "$s"; done)
# The leading-character guard keeps a git refspec (`owner/repo:branch`) from reading as a command.
_advertised=$(git ls-files '*.md' | xargs grep -ohE '(^|[^A-Za-z0-9_/-])/cubrid-agent:[a-z0-9-]*' 2>/dev/null | sed -E 's|.*/cubrid-agent:||' | sort -u)
for n in $_advertised; do
  case "$n" in ''|'<skill>'|'<스킬>') continue ;; esac
  printf '%s\n' "$_declared_names" | grep -qx "$n" \
    && pass "advertised /cubrid-agent:$n is declared" \
    || fail "docs advertise /cubrid-agent:$n but plugin.json does not declare it — the command does not exist"
done

# Promotion is one move plus one manifest line; forgetting either half must fail loudly.
_split=""
for s in $_declared; do
  case "$s" in ./skills/qa/*|skills/qa/*) ;; *) _split="$_split declared-outside-qa($s)" ;; esac
done
for d in skills/qa/*/; do
  d=${d%/}; printf '%s\n' "$_declared" | grep -qx "\./$d" || _split="$_split in-qa-but-unregistered($(basename "$d"))"
done
for d in skills/in-progress/*/; do
  d=${d%/}; printf '%s\n' "$_declared" | grep -qx "\./$d" && _split="$_split in-progress-but-registered($(basename "$d"))"
done
if [ -z "$_split" ]; then
  pass "skills/qa/ is exactly the registered set ($(printf '%s\n' "$_declared" | wc -l | tr -d ' ')), skills/in-progress/ ($(ls -d skills/in-progress/*/ 2>/dev/null | wc -l | tr -d ' ')) ships nothing"
else
  fail "the shipped/in-progress split is broken:$_split — promote by moving into skills/qa/ AND adding the plugin.json line, in one commit"
fi

# ---------------------------------------------------------------------------
group "Rules that must hold in EVERY skill, not most of them"

# Ground on the pandoc-free read (ground-issue.sh or an inline `jql … json`).
_bad=0
for f in $ISSUE_READERS; do
  if grep -q 'ground-issue.sh' "$f"; then :
  elif grep -q 'jql' "$f" && grep -q -- '--output json' "$f"; then :
  else fail "$f reads an issue without a pandoc-free path (ground-issue.sh, or inline \`jql ... --output json\`)"; _bad=$((_bad+1)); fi
done
[ "$_bad" -eq 0 ] && pass "all $(printf '%s\n' $ISSUE_READERS | wc -l | tr -d ' ') issue-reading skills use the pandoc-free read"

# An orchestrator with no work-directory instruction invents one in $HOME.
_bad=0
for f in skills/qa/gate-resolved/SKILL.md skills/qa/author-testcase/SKILL.md \
         skills/qa/review-testcase/SKILL.md; do
  grep -q 'Run directory' "$f" \
    || { fail "$f does not name its run directory — the run will scatter files into \$HOME"; _bad=$((_bad+1)); }
done
[ "$_bad" -eq 0 ] && pass "every orchestrator names its run directory"

# A skill documenting an artifact header must also say what the header is NOT for. create-cci /
# create-jdbc / create-unittest are absent on purpose — their header is an include, not a comment.
_bad=0
for f in create-sql create-cdc-repl create-ha-repl create-shell create-ha-shell create-isolation; do
  # The rule follows the skill, not the tree: create-sql ships, the other five are in-progress.
  _p=$(ls -d skills/*/"$f"/SKILL.md 2>/dev/null | head -1)
  [ -n "$_p" ] || { fail "$f is named by this check but exists in neither skills tree"; _bad=$((_bad+1)); continue; }
  grep -q 'describes the test, not the run' "$_p" \
    || { fail "$_p documents a header but not what the header is not for"; _bad=$((_bad+1)); }
  grep -q 'within 20 lines' "$_p" \
    || { fail "$_p documents a header but not the 20-line scannability bound"; _bad=$((_bad+1)); }
done
[ "$_bad" -eq 0 ] && pass "every header-documenting create-* skill bounds both header scope and size"

# Satisfied by delegating to ground-issue.sh, or by the hand-run rule until a skill is migrated.
_bad=0
for f in skills/*/create-*/SKILL.md; do
  grep -q 'ground-issue.sh' "$f" || grep -q 'attachment <KEY>' "$f" \
    || { fail "$f is missing the mandatory attachment-reading rule"; _bad=$((_bad+1)); }
done
[ "$_bad" -eq 0 ] && pass "every create-* skill carries the attachment rule"

# Helpers are invoked by absolute path, so only setup.sh puts them there. Three silent breakages are
# checked: referenced but absent, present but never installed, installed under a name nobody calls.
# The list is DERIVED from the directory — a hardcoded one would make the next helper invisible here.
# One definition of "this file is a library another helper sources", used by both checks below.
_is_lib() { grep -q "\. \"\$SELF_DIR/$1\"" skills/qa/setup-cubrid-agent/bin/*.sh 2>/dev/null; }
_bad=""; _refs=0; _nh=0
for _src in skills/qa/setup-cubrid-agent/bin/*.sh; do
  _h=$(basename "$_src"); _nh=$((_nh+1))
  [ -f "$_src" ] || _bad="$_bad missing-source($_src)"
  [ -x "$_src" ] || _bad="$_bad not-executable($_h)"
  grep -q "for h in .*$_h" skills/qa/setup-cubrid-agent/scripts/setup.sh || _bad="$_bad setup.sh-does-not-install($_h)"
  # Per helper, not once for the set: a helper nobody calls is dead weight that still gets installed,
  # and the check that only counted ground-issue.sh would have passed while the other two rotted.
  # A library another helper sources is exempt from the skill-reference rule — no skill invokes it by
  # path, and it still has to be installed, which the check above covers.
  _n=$(grep -l "bin/$_h" skills/*/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$_n" -gt 0 ] || _is_lib "$_h" || _bad="$_bad no-skill-calls($_h)"
  _refs=$((_refs + _n))
done
grep -q 'AGENT_DIR/bin' skills/qa/setup-cubrid-agent/scripts/setup.sh || _bad="$_bad no-bin-dir"
if [ -z "$_bad" ]; then
  pass "all $_nh installed helpers ship in the setup skill's bin/, install to ~/.cubrid-agent/bin/, and are called there ($_refs skill references)"
else
  fail "grounding helper wiring broken:$_bad — the skills call an absolute path that nothing puts on disk"
fi

# The scout names the half-year dir a new case belongs in; the lint hook judges whether the file
# landed there. Same fact, two files — and they cannot share code, because a hook ships through the
# plugin while a helper is installed into ~/.cubrid-agent/bin (ADR 0003). If the two expressions ever
# disagree, the pipeline sends the author to a directory its own gate then refuses.
_hy_lint=$(sed -n 's/^[[:space:]]*_curhy=\(.*\)$/\1/p' scripts/lint-sql-tc.sh)
_hy_scout=$(sed -n 's/^[[:space:]]*CURHY=\(.*\)$/\1/p' skills/qa/setup-cubrid-agent/bin/scout.sh)
if [ -n "$_hy_lint" ] && [ "$_hy_lint" = "$_hy_scout" ]; then
  pass "the scout and the lint hook compute the same half-year directory"
else
  fail "half-year expression drifted — lint: ${_hy_lint:-(not found)} / scout: ${_hy_scout:-(not found)}; the scout would name a directory the lint hook then rejects"
fi

# scout.sh reports which helpers are installed, so it carries its own copy of the list — the only
# thing on the machine that can say "this one is absent". The two lists are written by hand in
# different files and each drifts silently: a helper setup installs but scout does not know about is
# never reported missing, and one only scout knows about is reported missing forever.
_inst=$(sed -n 's/^for h in \(.*\); do$/\1/p' skills/qa/setup-cubrid-agent/scripts/setup.sh | tr ' ' '\n' | grep . | sort)
_scout=$(sed -n "s/^HELPERS='\(.*\)'\$/\1/p" skills/qa/setup-cubrid-agent/bin/scout.sh | tr ' ' '\n' | grep . | sort)
if [ -n "$_inst" ] && [ "$_inst" = "$_scout" ]; then
  pass "scout.sh knows exactly the helper set setup.sh installs ($(printf '%s\n' "$_inst" | wc -l | tr -d ' ') names)"
else
  fail "the helper list drifted between setup.sh and scout.sh — only in setup:$(comm -23 <(printf '%s\n' "$_inst") <(printf '%s\n' "$_scout") | tr '\n' ' ') only in scout:$(comm -13 <(printf '%s\n' "$_inst") <(printf '%s\n' "$_scout") | tr '\n' ' ')"
fi

# This repo ships publicly as a plugin, so an internal address in it is both an information leak and a
# dead end for anyone outside that network — the build-server URL was hardcoded in 9 places, including
# the default a script actually downloaded from. The public archive serves the same artifact and keeps a
# build until develop is released, so the internal server is now reachable only through
# CUBRID_BUILD_BASE, and nothing names it.
# The 10/8 range is matched only in a URL or host:port context on purpose: CUBRID's own versions look
# like 10.1.3.7698, and a check that cannot tell those apart would be turned off within a week.
_ips=$(git grep -nE '192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|(//|@)10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+' \
        -- . ':!scripts/check-invariants.sh' 2>/dev/null)
if [ -z "$_ips" ]; then
  pass "no internal IP address is named anywhere in the repo (the build archive is a public hostname)"
else
  fail "internal address(es) in tracked files — use the public archive, or CUBRID_BUILD_BASE:"
  printf '         %s\n' "$_ips"
fi

# Progressive disclosure only works if the body points at the file: a reference nothing links to is not
# "loaded on demand", it is deleted with extra steps. This is the failure mode of the very refactor that
# creates references/ — detail moves out, the link is forgotten, and the rule silently stops existing.
_unlinked=""; _nref=0
# The skill directory is whatever precedes /references/ — `dirname` twice would resolve a nested
# references/sub/x.md to the references dir itself and report every one of them unlinked.
while IFS= read -r _r; do
  [ -n "$_r" ] || continue
  _nref=$((_nref+1))
  _skill=${_r%%/references/*}
  grep -qF "references/${_r#*/references/}" "$_skill/SKILL.md" 2>/dev/null \
    || _unlinked="$_unlinked ${_r#skills/}"
done <<EOF
$(git ls-files 'skills/*/*/references/*')
EOF
if [ -z "$_unlinked" ]; then
  pass "every references/ file is named by the SKILL.md that owns it ($_nref files)"
else
  fail "reference file(s) no SKILL.md names — moving detail there without a link deletes it:$_unlinked"
fi

# A skill directory is a distribution unit: whatever sits in it reaches every teammate who installs the
# plugin. A measurement byproduct (SKILL.md.bold / SKILL.md.tokens, from the body-slimming check) was
# swept in by `git add -A` and shipped in one commit — deleting the two files fixed that instance and
# nothing else, so the surface is asserted here instead. Only the four asset kinds the skills actually
# use are allowed; anything else has to justify itself by being added to this list.
_bad=""
for _f in $(git ls-files 'skills/*/*/*'); do
  case ${_f#skills/*/*/} in
    SKILL.md|references/*|evals/*|examples/*|bin/*|scripts/*) ;;
    *) _bad="$_bad $_f" ;;
  esac
done
if [ -z "$_bad" ]; then
  pass "skill directories carry only skill assets (SKILL.md, references/, evals/, examples/, bin/, scripts/)"
else
  fail "these files ship inside a skill directory but are not skill assets:$_bad — every teammate who installs the plugin receives them"
fi

# The stale-copy hint is byte-identical in every helper on purpose (one sentence, one wording), and it
# is the sort of copy that rots: the next helper is written by copying an older one. Same directory and
# same install unit, so unlike the cross-skill duplication forced by ADR 0003 this one is checkable.
_hint='this installed copy is stale'
_miss=""; _n=0
for _f in skills/qa/setup-cubrid-agent/bin/*.sh; do
  # A sourced library parses no arguments, so it has no unknown-option path to carry the hint.
  _is_lib "$(basename "$_f")" && continue
  # A helper may carry the hint itself or delegate to common.sh's reject_unknown, which carries the
  # one canonical copy — the wording count below still holds it to a single variant. Merely sourcing
  # common.sh is not delegation: the call has to be there, or an unknown flag dies hintless.
  _n=$((_n+1))
  grep -qF "$_hint" "$_f" || grep -q 'reject_unknown' "$_f" || _miss="$_miss $(basename "$_f")"
done
_variants=$(grep -hoF -e "$_hint (the plugin updated, ~/.cubrid-agent/bin did not) — run /setup-cubrid-agent to refresh it." skills/qa/setup-cubrid-agent/bin/*.sh | sort -u | wc -l | tr -d ' ')
if [ -z "$_miss" ] && [ "$_variants" = 1 ]; then
  pass "all $_n helpers tell the operator when their installed copy is stale, in one wording"
else
  fail "stale-copy hint drifted:${_miss:+ missing in$_miss}${_variants:+ ($_variants wordings)} — a helper whose flags moved on would only say 'unknown option'"
fi
# One resolution rule for the testcases clone, in one wording. Two wordings coexisted for a month: the
# part skills kept a June sentence (discover the checkout from the cwd, else ask the user) while the
# orchestrators and every helper moved to the $HOME standard, and nothing said so because each copy read
# fine on its own. The duplication is sanctioned — ADR 0003's channel constraint means a part skill
# cannot link to a shared file — the drift is not.
_rule='`$CUBRID_TESTCASES` if set, else `~/cubrid-testcases`'
_miss=""; _n=0
for _s in $(grep -lF 'CUBRID_TESTCASES' skills/qa/*/SKILL.md); do
  # setup-cubrid-agent names the variable while listing what env.sh exports; that is not a resolution rule.
  case "$_s" in */setup-cubrid-agent/*) continue ;; esac
  _n=$((_n+1))
  grep -qF "$_rule" "$_s" || _miss="$_miss $(basename "$(dirname "$_s")")"
done
if [ -z "$_miss" ] && [ "$_n" -gt 0 ]; then
  pass "all $_n skills resolve the testcases clone in one wording"
else
  fail "testcases-clone rule drifted:${_miss:+ different wording in$_miss} — a skill that resolves it its own way runs against a different clone than the helpers do"
fi

# The hook covering the other half of that cause must prescribe the same fix, or the two drift.
if grep -qF 'run /setup-cubrid-agent' scripts/hint-missing-helper.sh; then
  pass "the missing-helper hint prescribes the same fix as the helpers' stale hint"
else
  fail "hint-missing-helper.sh no longer names 'run /setup-cubrid-agent' — it and the helpers' stale hint now send the reader different places for one cause"
fi

# The identity rule is duplicated on purpose — `npx skills add` copies one skill's own directory, so a
# skill that resolves $QA_USER cannot link to a shared file (ADR 0003's channel constraint). What is
# checkable is that no copy drifts into losing a part: the two copies already differ in wording, and
# the part most likely to be dropped as boilerplate is the credential-safety half. Atoms, not byte
# equality — each skill states the rule in its own context, and equality would fight that.
_bad=""; _nid=0
for _f in $(grep -l 'QA_USER' skills/*/*/SKILL.md 2>/dev/null); do
  _nid=$((_nid+1))
  grep -qF 'ADR 0004' "$_f"    || _bad="$_bad $(basename "$(dirname "$_f")"):no-ADR-0004"
  grep -qF 'never parse' "$_f" || _bad="$_bad $(basename "$(dirname "$_f")"):may-parse-netrc"
  grep -qF 'netrc' "$_f"       || _bad="$_bad $(basename "$(dirname "$_f")"):no-netrc-rule"
  grep -qF 'hostname' "$_f"    || _bad="$_bad $(basename "$(dirname "$_f")"):no-hostname-guard"
done
if [ -z "$_bad" ] && [ "$_nid" -gt 0 ]; then
  pass "all $_nid skills that resolve \$QA_USER carry the whole identity rule (ADR 0004 + never-parse-netrc + hostname guard)"
else
  fail "identity rule drifted:${_bad:- no skill resolves \$QA_USER, which cannot be right} — a copy that lost the credential half is how a password reaches a transcript"
fi

# The guard that keeps ground-issue.sh's manifests from becoming permanent stop-reminders used to be
# pinned here by grepping gate-stop.sh for one jq expression. That pinned the wording, not the
# behaviour, and it blocked a correct narrowing of the same guard. scripts/test-gate-stop.sh pins the
# behaviour instead, in both directions, and check-invariants runs it under "Hook wiring".

# DP5: no skill may instruct reading or writing agent memory. Match memory ARTIFACTS and the
# cached-verdict shape, not the bare word — "frees broker shared memory" must stay clean.
_mem_scope=$(git ls-files 'skills/*/*/SKILL.md' 'skills/*/*/references/*.md' 'skills/*/*/evals/*.json')
_mem=$(grep -lEi \
  -e '~/\.claude/|CLAUDE\.md|MEMORY\.md' \
  -e '(auto|project|agent|session|persistent)[- ]memor(y|ies)' \
  -e 'memor(y|ies) (tool|file|dir|directory|store|entry|entries)' \
  -e '(cach|reus|carry|carri|persist)[a-z]* [^.]{0,40}verdict|verdict[^.]{0,40} (cach|reus)[a-z]*' \
  -e '\.omc/|notepad' \
  $_mem_scope 2>/dev/null | sort -u)
if [ -z "$_mem" ]; then
  pass "no skill instructs the agent to depend on memory (DP5; $(printf '%s\n' $_mem_scope | wc -l | tr -d ' ') files scanned)"
else
  fail "these files reference agent memory or a cached verdict — the knowledge belongs in the skill body, references/, env.sh or the manifest (DP5, CUBRIDQA-1488): $(printf '%s' "$_mem" | tr '\n' ' ')"
fi

# The TC's directory is create-sql's call: author-testcase must defer instead of pinning a path, and
# must record the two issue facts the placement check needs. Checking the fix is PRESENT (not that
# the old string is absent) is what catches a rewrite that drops it.
_at=skills/qa/author-testcase/SKILL.md
_miss=""
grep -q "directory convention" "$_at" || _miss="$_miss deferral-to-create-sql"
grep -q "select.issue_type" "$_at"   || _miss="$_miss select.issue_type-recording"
if [ -z "$_miss" ]; then
  pass "author-testcase defers the TC path to create-sql and records the placement facts"
else
  fail "author-testcase lost:$_miss — without both, the TC path is decided by whoever guesses first and the placement check cannot run"
fi

# A lint flag is written by one script and read by another; a half-move silently disables it. Every
# field the hook records has to reach the gate's aggregate, so the enumeration lives here rather than a
# named few — a rule added to the hook and forgotten in the gate blocks nothing and still reports green.
# Both directions, because each half goes silent on its own: a flag the gate never reads blocks nothing,
# and a flag nothing writes stays absent, which `d()` reads as clean — a check that cannot fail.
_unread=""; _unwritten=""
for _k in $(grep -oE '\.lint\.[a-z_]+=' scripts/lint-sql-tc.sh | sed 's/^\.lint\.//; s/=$//' | sort -u); do
  grep -qE "(d\(\"$_k\"\)|\.lint\.$_k[,]|\.lint\.$_k\])" scripts/gate-pr-submit.sh || _unread="$_unread $_k"
done
for _k in $(grep -oE 'd\("[a-z_]+"\)|\.lint\.[a-z_]+[,\]]' scripts/gate-pr-submit.sh \
              | sed 's/^d("//; s/")$//; s/^\.lint\.//; s/[,]$//' | sort -u); do
  # answer_not_handwritten is the one flag the hook cannot judge: it is provenance the orchestrator
  # records, since no reading of the file says whether a human typed the .answer.
  [ "$_k" = answer_not_handwritten ] && continue
  grep -q "\.lint\.$_k=" scripts/lint-sql-tc.sh || _unwritten="$_unwritten $_k"
done
if [ -z "$_unread" ] && [ -z "$_unwritten" ]; then
  pass "every lint.* flag is written by the hook and read by the submit gate"
else
  [ -z "$_unread" ]    || fail "lint flag(s) written by the hook but never read by the submit gate:$_unread — a violation of those would not block anything"
  [ -z "$_unwritten" ] || fail "lint flag(s) read by the submit gate but never written:$_unwritten — they stay absent, which the gate reads as clean, so the check cannot fail"
fi

# The flag the skill tells the operator to pass must exist in the script it points at; drift either
# way is silent.
_setup_sh=skills/qa/setup-cubrid-agent/scripts/setup.sh
_in_script=0; _in_skill=0
grep -q -- '--install-clis)' "$_setup_sh" && _in_script=1
grep -q -- '--install-clis' skills/qa/setup-cubrid-agent/SKILL.md && _in_skill=1
if [ "$_in_script" -eq 1 ] && [ "$_in_skill" -eq 1 ]; then
  pass "setup skill and setup.sh agree on --install-clis"
else
  fail "--install-clis is in $([ "$_in_script" -eq 1 ] && echo 'setup.sh but not the SKILL' || echo 'the SKILL but not setup.sh') — the setup skill would tell the operator to run a flag that does not exist, or ship a flag nobody invokes"
fi

# DP7 measures skill body size instead of capping it: size alone cannot separate a body that is long
# because the domain is, from one nobody cut.
_sizes=$(for f in $(git ls-files 'skills/*/*/SKILL.md'); do printf '%s %s\n' "$(wc -c < "$f")" "$f"; done | sort -rn)
_total=$(printf '%s\n' "$_sizes" | awk '{s+=$1} END {printf "%d", s/1024}')
_top=$(printf '%s\n' "$_sizes" | head -1 | awk '{printf "%s (%dKB)", $2, $1/1024}' | sed 's|skills/[a-z-]*/||;s|/SKILL.md||')
pass "skill bodies: $(printf '%s\n' "$_sizes" | wc -l | tr -d ' ') files, ${_total}KB total, largest $_top — no cap, DP7 measures only"

# ---------------------------------------------------------------------------
group "Skill frontmatter"

# The Agent Skills spec caps `description` at 1024 characters, and the skills CLI channel (Codex,
# Cursor, Gemini) enforces it while Claude Code only truncates. Take the stricter bound.
# Count CHARACTERS, not bytes: the Korean trigger keywords inflate `wc -c` threefold.
_utf8=$(locale -a 2>/dev/null | grep -ix -m1 -E 'C\.utf-?8|en_US\.utf-?8')
[ -z "$_utf8" ] && _utf8=$(locale -a 2>/dev/null | grep -i -m1 -E 'utf-?8$')
if [ -z "$_utf8" ]; then
  fail "no UTF-8 locale on this machine — description length would be measured in bytes and misjudge the Korean trigger keywords"
else
  _bad=0
  while IFS= read -r f; do
    _desc=$(sed -n '/^---$/,/^---$/p' "$f" | sed -n 's/^description:[[:space:]]*//p' | head -1)
    _desc=${_desc%\"}; _desc=${_desc#\"}
    _len=$(printf '%s' "$_desc" | LC_ALL="$_utf8" wc -m | tr -d ' ')
    if [ "$_len" -gt 1024 ]; then
      fail "$f description is $_len characters (> 1024, the Agent Skills spec limit)"; _bad=$((_bad+1))
    fi
  done <<EOF
$(git ls-files 'skills/*/*/SKILL.md')
EOF
  [ "$_bad" -eq 0 ] && pass "every skill description is within the spec's 1024-character limit"
fi

# ---------------------------------------------------------------------------
group "Hook wiring"

# A hook command quotes the root, so drop the quotes before matching or the group looks clean.
_hooks=$(jq -r '.. | .command? // empty' hooks/hooks.json \
  | tr -d '"' | grep -o '\${CLAUDE_PLUGIN_ROOT}/[^[:space:]]*' | sort -u)
if [ -z "$_hooks" ]; then
  fail "found no \${CLAUDE_PLUGIN_ROOT} command in hooks/hooks.json — either the hooks are gone or this check no longer matches their shape"
fi
for h in $_hooks; do
  _p=${h#\$\{CLAUDE_PLUGIN_ROOT\}/}
  if [ ! -f "$_p" ]; then fail "hooks.json points at $_p, which does not exist"
  elif [ ! -x "$_p" ]; then fail "$_p is referenced by a hook but is not executable"
  else pass "hook script present and executable: $_p"; fi
done

# release.sh decides what obliges a version bump from its SHIPPED_PATHS list. A hook script missing
# from that list can change release after release without anyone declaring it, and check 7 would
# report the surface as unchanged. The two lists are written by hand in different files, so pin them.
_shipped=$(sed -n '/^SHIPPED_PATHS=(/,/^)/p' scripts/release.sh | sed '1d;$d' | tr -d ' 	')
_unlisted=""
for h in $_hooks; do
  _p=${h#\$\{CLAUDE_PLUGIN_ROOT\}/}
  printf '%s\n' "$_shipped" | grep -qxF "$_p" || _unlisted="$_unlisted $_p"
done
if [ -z "$_unlisted" ]; then pass "every hook script is listed in release.sh's SHIPPED_PATHS"
else fail "hook scripts missing from SHIPPED_PATHS in scripts/release.sh:$_unlisted"; fi

# The submit gate is the only check that can strand finished work, so it gets a behavioural test
# pinning both directions rather than a grep for a marker string.
if _t=$(bash scripts/test-gate-pr-submit.sh 2>&1); then pass "submit gate behaves: $_t"
else fail "submit gate test failed — run scripts/test-gate-pr-submit.sh:"; printf '         %s\n' "$_t"; fi

# The stop reminder is the other direction of the same risk: it fired on every stop for seven days
# over a manifest that had no gate to close, and named it "?" so nobody could find it. A gate that
# cries wolf is ignored, so both directions get pinned.
if _t=$(bash scripts/test-gate-stop.sh 2>&1); then pass "stop reminder behaves: $_t"
else fail "stop reminder test failed — run scripts/test-gate-stop.sh:"; printf '         %s\n' "$_t"; fi

# Select's screens get the same treatment for the opposite reason: they run FIRST, and a screen that
# wrongly reports "nothing found" when the lookup failed sends two operators at the same TC. Only a
# stubbed network can reach that path, so it is a behavioural test, not a grep.
# The lint hook writes the fields the submit gate refuses work over, and it had no test at all: its
# header check matched `/**` and the key on one line while the corpus puts the key on the next, so
# lint.header was false for all 47 corpus testcases that have a header block. A gate that blocks correct
# work is worse than no gate, and only a test against corpus-shaped fixtures says so.
if _t=$(bash scripts/test-lint-sql-tc.sh 2>&1); then pass "TC lint behaves: $_t"
else fail "TC lint test failed — run scripts/test-lint-sql-tc.sh:"; printf '         %s\n' "$_t"; fi

if _t=$(bash scripts/test-select-queue.sh 2>&1); then pass "select queue behaves: $_t"
else fail "select queue test failed — run scripts/test-select-queue.sh:"; printf '         %s\n' "$_t"; fi

# A half-finished build swap leaves a pre-fix engine installed while every later verify reports green.
# The test stubs the installer and CTP so all four stranding paths are reachable offline.
if _t=$(bash scripts/test-failpass-run.sh 2>&1); then pass "fail→pass swap behaves: $_t"
else fail "fail→pass test failed — run scripts/test-failpass-run.sh:"; printf '         %s\n' "$_t"; fi

# A debug build reports the SAME version as its release twin, so only the build TYPE proves the
# install happened; without it a no-op install reports `clean`.
if _t=$(bash scripts/test-debug-check.sh 2>&1); then pass "debug check behaves: $_t"
else fail "debug check test failed — run scripts/test-debug-check.sh:"; printf '         %s\n' "$_t"; fi

# A commit proof that passes when the work is missing is worse than no proof.
if _t=$(bash scripts/test-render-report.sh 2>&1); then pass "report commit proof behaves: $_t"
else fail "render-report test failed — run scripts/test-render-report.sh:"; printf '         %s\n' "$_t"; fi

# Authoring may have happened in a worktree the variable no longer names, so the renderer must read
# from the branch's real checkout.
if _t=$(bash scripts/test-render-pr-body.sh 2>&1); then pass "PR body renderer behaves: $_t"
else fail "render-pr-body test failed — run scripts/test-render-pr-body.sh:"; printf '         %s\n' "$_t"; fi

# A clone setup puts in the wrong place is wrong for the whole pipeline. The fixture stubs `git clone`.
if _t=$(bash scripts/test-setup.sh 2>&1); then pass "setup honours the testcases override: $_t"
else fail "setup test failed — run scripts/test-setup.sh:"; printf '         %s\n' "$_t"; fi

# The hint fires on a command that already fails, so the test pins first that it never blocks.
if _t=$(bash scripts/test-hint-missing-helper.sh 2>&1); then pass "missing-helper hint behaves: $_t"
else fail "missing-helper hint test failed — run scripts/test-hint-missing-helper.sh:"; printf '         %s\n' "$_t"; fi

# Both directions are load-bearing: isolating with nothing to lose leaves a worktree per issue on CI,
# and not isolating loses someone's staged work to a branch they do not own.
if _t=$(bash scripts/test-prepare-tc-workspace.sh 2>&1); then pass "TC worktree decision behaves: $_t"
else fail "prepare-tc-workspace test failed — run scripts/test-prepare-tc-workspace.sh:"; printf '         %s\n' "$_t"; fi

if _t=$(bash scripts/test-verify-run.sh 2>&1); then pass "verify-run writes where it is told: $_t"
else fail "verify-run test failed — run scripts/test-verify-run.sh:"; printf '         %s\n' "$_t"; fi

# The prep call replaces eight look-ups, so it is trusted rather than re-checked — which makes a
# capability it reports as present but is not the one failure nobody would catch until Verify.
if _t=$(bash scripts/test-scout.sh 2>&1); then pass "prep scout behaves: $_t"
else fail "scout test failed — run scripts/test-scout.sh:"; printf '         %s\n' "$_t"; fi

# A release reaches an installed copy through the declared version, so a state that drifts from the
# CHANGELOG ships under a number nobody can look up. release.sh owns that judgement; this runs it
# against the working tree, and the test below runs it against states this repo is not in.
if _t=$(bash scripts/release.sh check 2>&1); then pass "release state: $(printf '%s' "$_t" | tail -1)"
else fail "not in a releasable state — run scripts/release.sh check:"; printf '         %s\n' "$_t"; fi

if _t=$(bash scripts/test-release.sh 2>&1); then pass "release tooling behaves: $_t"
else fail "release test failed — run scripts/test-release.sh:"; printf '         %s\n' "$_t"; fi

# marketplace.json is read from the catalog clone, not from the versioned cache, so an edit there
# reaches every install without a version bump. `claude plugin validate` checks its shape, not whether
# it still points at this plugin — a renamed entry or a moved source would silently redirect installs.
_mp_name=$(jq -r '.plugins[0].name // empty' .claude-plugin/marketplace.json 2>/dev/null)
_mp_src=$(jq -r '.plugins[0].source // empty' .claude-plugin/marketplace.json 2>/dev/null)
_pl_name=$(jq -r '.name // empty' .claude-plugin/plugin.json 2>/dev/null)
if [ -n "$_pl_name" ] && [ "$_mp_name" = "$_pl_name" ] && [ "$_mp_src" = "./" ]; then
  pass "marketplace.json advertises $_pl_name from this repo (source \"./\")"
else
  fail "marketplace.json offers \"$_mp_name\" from \"$_mp_src\" but plugin.json is \"$_pl_name\" — an install would resolve somewhere else"
fi

# ---------------------------------------------------------------------------
group "Plugin manifest validation (optional — needs the claude CLI)"

if command -v claude >/dev/null 2>&1; then
  # --strict warned about one thing only, the deliberate `version` omission; 1.0.0 retired it (ADR 0003).
  if claude plugin validate . --strict >/dev/null 2>&1; then pass "claude plugin validate . --strict passed"
  else fail "claude plugin validate . --strict failed — run it directly to see why"; fi
else
  pass "skipped: claude CLI not on PATH"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$FAILED" -eq 0 ]; then echo "all invariants hold"; exit 0; fi
echo "$FAILED invariant(s) violated"; exit 1
