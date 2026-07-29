#!/bin/bash
# Repo invariants — the machine seam for the rules this repo keeps breaking silently.
#
# Dev-only: not a hook, not listed in hooks.json, never invoked by a skill. Run it by
# hand or from CI (see .github/workflows/validate-plugin.yml).
#
# Deterministic and offline. Uses only git, jq, grep and sed — the tools setup.sh already
# requires — so it needs no network, no credentials, and no Python. `claude plugin validate`
# is the one optional step: it runs when the CLI is present and is skipped otherwise.
#
# Every check here exists because the invariant it guards was violated in a way that
# produced no error: docs told operators to invoke skills the plugin never loaded
# (CUBRIDQA-1472), a mandatory rule reached 4 of 12 skills (CUBRIDQA-1443), and grounding
# read an empty issue body and carried on (CUBRIDQA-1478). Decision: CUBRIDQA-1459.
set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 1; }

FAILED=0
group() { printf '\n== %s ==\n' "$1"; }
pass()  { printf '  ok   %s\n' "$1"; }
fail()  { printf '  FAIL %s\n' "$1"; FAILED=$((FAILED+1)); }

# The skills that read a CBRD issue. Each must ground on the raw JSON read, never on
# `cubrid-jira search`, whose markdown goes through pandoc and comes back empty — with a
# success exit — on a pandoc without the jira reader.
ISSUE_READERS=$(printf '%s\n' skills/qa/create-*/SKILL.md skills/qa/verify-*/SKILL.md \
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

# AGENTS.md is the canonical file shared by every CLI; CLAUDE.md is a symlink to it.
# A copy instead of a symlink is how the two drift apart unnoticed.
if [ -L CLAUDE.md ] && [ "$(readlink CLAUDE.md)" = "AGENTS.md" ]; then
  pass "CLAUDE.md is a symlink to AGENTS.md"
else fail "CLAUDE.md must be a symlink to AGENTS.md (found: $(readlink CLAUDE.md 2>/dev/null || echo 'a regular file'))"; fi

# ---------------------------------------------------------------------------
group "Internal markdown links"

_dead=0
while IFS= read -r f; do
  _dir=$(dirname "$f")
  # Every ](target) in the file — grep -o so several links on one line all count.
  # Drop external schemes and pure anchors, strip any #fragment, resolve the rest
  # relative to the linking file.
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
# 1472: README told operators to invoke the 16 component skills, which are never loaded.
_declared_names=$(for s in $_declared; do basename "$s"; done)
_advertised=$(git ls-files '*.md' | xargs grep -oh '/cubrid-agent:[a-z0-9-]*' 2>/dev/null | sed 's|/cubrid-agent:||' | sort -u)
for n in $_advertised; do
  case "$n" in ''|'<skill>'|'<스킬>') continue ;; esac
  printf '%s\n' "$_declared_names" | grep -qx "$n" \
    && pass "advertised /cubrid-agent:$n is declared" \
    || fail "docs advertise /cubrid-agent:$n but plugin.json does not declare it — the command does not exist"
done

# ---------------------------------------------------------------------------
group "Rules that must hold in EVERY skill, not most of them"

# CUBRIDQA-1478: ground on the raw read. `--output json` next to a jql call is the marker.
_bad=0
for f in $ISSUE_READERS; do
  if grep -q 'jql' "$f" && grep -q -- '--output json' "$f"; then :
  else fail "$f reads an issue without the raw \`jql ... --output json\` path"; _bad=$((_bad+1)); fi
done
[ "$_bad" -eq 0 ] && pass "all $(printf '%s\n' $ISSUE_READERS | wc -l | tr -d ' ') issue-reading skills use the raw read"

# CUBRIDQA-1443: the attachment rule reached 4 of 12 skills and nobody noticed.
_bad=0
for f in skills/qa/create-*/SKILL.md; do
  grep -q 'attachment <KEY>' "$f" \
    || { fail "$f is missing the mandatory attachment-reading rule"; _bad=$((_bad+1)); }
done
[ "$_bad" -eq 0 ] && pass "every create-* skill carries the attachment rule"

# ---------------------------------------------------------------------------
group "Skill frontmatter"

# Claude Code caps a listing entry's description + when_to_use at 1536 chars and silently
# truncates past it, which strips the trigger keywords the skill is matched on.
while IFS= read -r f; do
  _fm=$(sed -n '/^---$/,/^---$/p' "$f")
  _len=$(printf '%s' "$_fm" | sed -n 's/^description:[[:space:]]*//p' | head -1 | wc -c | tr -d ' ')
  if [ "$_len" -gt 1536 ]; then fail "$f description is $_len chars (> 1536, truncated in the skill listing)"; fi
done <<EOF
$(git ls-files 'skills/qa/*/SKILL.md')
EOF
pass "every skill description is within the 1536-char listing cap"

# ---------------------------------------------------------------------------
group "Hook wiring"

# A hook command quotes the root — "${CLAUDE_PLUGIN_ROOT}"/scripts/x.sh — so drop the
# quotes before matching, or the pattern silently finds nothing and the group looks clean.
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

# ---------------------------------------------------------------------------
group "Plugin manifest validation (optional — needs the claude CLI)"

if command -v claude >/dev/null 2>&1; then
  if claude plugin validate . >/dev/null 2>&1; then pass "claude plugin validate . passed"
  else fail "claude plugin validate . failed — run it directly to see why"; fi
else
  pass "skipped: claude CLI not on PATH"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$FAILED" -eq 0 ]; then echo "all invariants hold"; exit 0; fi
echo "$FAILED invariant(s) violated"; exit 1
