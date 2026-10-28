#!/bin/bash
# Behavioural test for lint-rulebook.sh — the shape check `validate` runs on every rulebook canonical copy.
#
# Dev-only, run by check-invariants.sh. Offline: every case lints a throwaway tree. Only the CLI seam is
# observed: exit code and stdout. The fixture's categories are sql and medium, not shell, because the
# rulebooks of other categories and tc repos go through the same lint: a check that only fits shell
# fails here.
set -u

LINT=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/lint-rulebook.sh
[ -f "$LINT" ] || { echo "test-lint-rulebook: script not found at $LINT" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
flat() { printf '%s' "$1" | tr '\n' '|'; }

N=0; D=
tree() {  # tree -> D holds a fresh rulebook tree that passes
  N=$((N+1)); D="$T/$N"; mkdir -p "$D"
  cat > "$D/AGENTS.md" <<'EOF'
# Rulebook

A fact is a plain paragraph and needs no example.

**Open the clone as the working directory.** Example: `cd ~/repo && claude`

## Terms

| Term | Korean | Meaning |
|---|---|---|
| verdict | OK/NOK 판정 | One `write_ok` or `write_nok` call. |
| answer file | 답지 | The expected output a case is compared with. |
EOF
  for c in sql medium; do
    mkdir -p "$D/$c/rules"
    cat > "$D/$c/AGENTS.md" <<'EOF'
# Category

**Read both rule files before you write a TC.** Example: [writing rules](rules/writing-rules.md)
EOF
    cat > "$D/$c/rules/test-perspectives.md" <<'EOF'
# Test perspectives

**Check every *verdict* the issue names.** The fix changes it.
Example:
```bash
write_ok
```
EOF
    cat > "$D/$c/rules/writing-rules.md" <<'EOF'
# Writing rules

## New TC

**Put the *answer file* next to the case.** Example: `cases/a.answer`

## Changing an existing TC

**Keep the *verdict* when you change a case.** Example: `write_ok` stays.
EOF
  done
}

expect() {  # expect <want-exit> <want-stdout, exact; "-" skips> <label> [args...]  (no args: lint $D)
  local want=$1 wout=$2 label=$3 out rc; shift 3
  [ $# -eq 0 ] && set -- "$D"
  out=$(bash "$LINT" "$@" 2>/dev/null); rc=$?
  if [ "$rc" -ne "$want" ]; then note_fail "$label: exit $rc, expected $want — output: $(flat "$out")"; return; fi
  if [ "$wout" != "-" ] && [ "$out" != "$wout" ]; then
    note_fail "$label: output was: $(flat "$out") — expected: $(flat "$wout")"; return
  fi
  T_PASS=$((T_PASS+1))
}

tree
expect 0 "" "a tree in the agreed shape passes silently"

tree; rm "$D/medium/rules/writing-rules.md"
expect 1 $'medium/rules/writing-rules.md: missing\nmedium/AGENTS.md:3: link "rules/writing-rules.md" is not a file of the rulebook' \
  "a missing file is reported, and so is every link to it"

# The deploy makes the CLAUDE.md symlinks in the tc repo; one kept in the canonical copy is the usual extra.
tree; ln -s AGENTS.md "$D/sql/CLAUDE.md"
expect 1 "sql/CLAUDE.md: not in the rulebook file set" "an extra file, a symlink included, is reported"

tree; rm -r "$D/sql" "$D/medium"
expect 1 ".: no category directory" "a tree with only the root file is reported"

tree; sed -i '/^## Changing an existing TC$/d' "$D/medium/rules/writing-rules.md"
expect 1 'medium/rules/writing-rules.md: missing section "## Changing an existing TC"' "a writing-rules file without one of its two sections is reported"

pad() { local i=$(awk 'END{print NR}' "$1"); while [ "$i" -lt "$2" ]; do echo >> "$1"; i=$((i+1)); done; }
tree; pad "$D/sql/AGENTS.md" 200
expect 0 "" "an AGENTS.md of exactly 200 lines passes"
tree; pad "$D/sql/AGENTS.md" 201
expect 1 "sql/AGENTS.md: 201 lines, over 200" "an AGENTS.md over 200 lines is reported"

B=sql/rules/test-perspectives.md
rule() { printf '# Test perspectives\n\n%s\n' "$1" > "$D/$B"; }  # the rule paragraph starts on line 3

tree; rule '**Drop what you create.** It keeps the DB clean.'
expect 1 "$B:3: rule has no \"Example:\"" "a rule paragraph without an example is reported"

tree; rule $'**Drop what you create.** Example:\n\n```sql\ndrop table t;\n```'
expect 1 "$B:3: rule has no \"Example:\"" "a blank line ends the paragraph, so a fence below it is not the rule's example"

tree; rule '**Drop what you create. Do it last.** Example: `drop table t;`'
expect 1 "$B:3: rule sentence must be one sentence ending in \".\"" "two sentences in the bold rule sentence are reported"

tree; rule '**Drop what you create** at the end. Example: `drop table t;`'
expect 1 "$B:3: rule sentence must be one sentence ending in \".\"" "a bold rule sentence without its period is reported"

tree; rule '**The case drops what it creates.** Example: `drop table t;`'
expect 1 "$B:3: rule sentence must be imperative, not start with \"The\"" "a declarative rule sentence is reported"

tree; rule '**Retry a *flaky case* once.** Example: `retry 1`'
expect 1 "$B:3: \"flaky case\" is not in the term table" "an italic term the term table lacks is reported"

tree; rule '**Keep both *Answer files*.** Example: `a.answer`'
expect 0 "" "a term matches its table row in any case and with a plural s"

tree; rule '**Remove the logs.** Example: `rm -f *.log *.err`'
expect 0 "" "asterisks inside a code span are not a term"

tree; rule '**Drop what you create.** Example: `drop table t;` 정리한다'
expect 1 "$B:3: Hangul outside the term table" "Hangul outside the term table is reported"

tree; rule '**Read the cleanup rules.** Example: [cleanup](cleanup.md)'
expect 1 "$B:3: link \"cleanup.md\" is not a file of the rulebook" "a link to a file the tree lacks is reported"

tree; printf '\n## Medium only\n' >> "$D/medium/rules/writing-rules.md"
rule '**Keep the *verdict* of a medium case.** Example: [change](../../medium/rules/writing-rules.md#medium-only)'
expect 0 "" "a link to a heading of another category resolves"

# The tree is the tc repo: a file beside it on disk is not deployed, so the link breaks there.
tree; touch "$T/AGENTS.md"; rule '**Read the note.** Example: [note](../../../AGENTS.md)'
expect 1 "$B:3: link \"../../../AGENTS.md\" is not a file of the rulebook" "a link that climbs out of the tree is reported"

tree; rule '**Read the root.** Example: [root](../../AGENTS.md/..)'
expect 1 "$B:3: link \"../../AGENTS.md/..\" is not a file of the rulebook" "a link that folds back to the tree root is reported"

tree; rule '**Read the rules.** Example: [rules](/writing-rules.md)'
expect 1 "$B:3: link \"/writing-rules.md\" is not a file of the rulebook" "a link that starts with / is reported"

tree; rule '**Read the rules for a new TC.** Example: [new TC](writing-rules.md#new-tcs)'
expect 1 "$B:3: link \"writing-rules.md#new-tcs\": sql/rules/writing-rules.md has no heading \"#new-tcs\"" \
  "a link to a heading the file lacks is reported"

# Expected anchors are the ones GitHub renders for the same heading shapes in this repo's docs.
headed() {  # the paragraph is on line 11
  printf '# Test perspectives\n\n## Plans, hints, and data size\n\n## The `write_ok` call — once per path\n\n## Notes\n\n## Notes\n\n%s\n' "$1" > "$D/$B"
}
tree; headed '**Follow the anchors.** Example: [a](#plans-hints-and-data-size) [b](#the-write_ok-call--once-per-path) [c](#notes-1)'
expect 0 "" "an anchor follows GitHub's heading rule, and a repeated heading takes -1"
tree; headed '**Follow the anchors.** Example: [d](#notes-2)'
expect 1 "$B:11: link \"#notes-2\": $B has no heading \"#notes-2\"" "a heading repeated twice has no -2 anchor"
tree; printf '# Test perspectives\n\n## Notes \n\n%s\n' '**Read the notes.** Example: [notes](#notes)' > "$D/$B"
expect 0 "" "trailing blanks of a heading are not part of its anchor"

tree; rule '**Cite the issue.** Example: [CUBRIDQA-1505](https://jira.cubrid.org/browse/CUBRIDQA-1505)'
expect 0 "" "an external URL is not checked"

tree; rule $'**Write a link as markdown.** Example: `[a](none.md)`\n```md\n[b](none.md)\n```'
expect 0 "" "a link inside a code span or a fence is not checked"

tree; rule $'**Name the step.** Example: [setup](#setup)\n```bash\n# setup\n```'
expect 1 "$B:3: link \"#setup\": $B has no heading \"#setup\"" "a comment line inside a fence is not a heading"

# One awk reads every file, and sql/rules/writing-rules.md is read right after $B.
tree; rule $'**Read the rules for a new TC.** Example: [new TC](writing-rules.md#new-tc)\n```bash\nwrite_ok'
expect 0 "" "a fence left open in one file does not hide the headings of the next"

# A dangling symlink is in the file set but cannot be read; root reads a chmod 000 file anyway.
tree; rm "$D/$B" && ln -s gone.md "$D/$B"
expect 1 "$B: could not be read" "a file the lint cannot read is reported"

tree; sed -i '/^## Terms$/,$d' "$D/AGENTS.md"
expect 1 'AGENTS.md: no term table (a "| Term |" header row)' "a root AGENTS.md without the term table is reported once"

# check-invariants.sh compares these terms with GLOSSARY.md, so the table has one parser.
tree
expect 0 $'verdict\nanswer file' "--terms prints the first column of the root term table as written" --terms "$D"

expect 2 - "a path that is not a directory is a usage error" "$T/none"
if bash "$LINT" >/dev/null 2>&1; [ $? -eq 2 ]; then T_PASS=$((T_PASS+1)); else note_fail "no argument: exit was not 2"; fi

if [ "$T_FAIL" -eq 0 ]; then
  printf 'lint-rulebook: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'lint-rulebook: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
