#!/bin/bash
# Diff the rule inventory of a skill body between a git ref and the working tree — the thing that must NOT
# change when a SKILL.md is slimmed. Output goes to stdout only: an earlier ad-hoc version of this check
# wrote its two inventory files next to the skill it was measuring, and `git add -A` shipped them inside
# the plugin (cdc3d43).
#
# The inventory is deliberately crude: every bold span, every backticked token, every heading — with a
# count, so deleting ONE of two occurrences shows up too (that is the copy-paste case DP7 cares about).
# It cannot prove a rule was kept: a rule can survive as a token while losing its meaning, and a span
# wrapped across a newline is invisible to a line-based match. Read the diff; do not just count it.
#
# usage: rule-inventory.sh <git-ref> <path/to/SKILL.md>
set -u

[ $# -eq 2 ] || { printf 'usage: rule-inventory.sh <git-ref> <path/to/SKILL.md>\n' >&2; exit 1; }
# Paths are repo-relative, like every other script here: `git show <ref>:<path>` only accepts that form,
# and resolving one against the cwd while the other resolves against the root is how this silently
# compared two different files.
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "rule-inventory: not a git repo" >&2; exit 1; }

REF=$1; FILE=$2
[ -f "$FILE" ] || { printf 'rule-inventory: no such file (repo-relative): %s\n' "$FILE" >&2; exit 1; }

extract() {  # extract <path> -> "<item>\t×<count>", sorted by item
  { grep -oE '\*\*[^*]+\*\*' "$1"
    grep -oE '`[^`]+`'       "$1"
    grep -oE '^#{1,6} .*'    "$1"
  } 2>/dev/null | sort | uniq -c | awk '{c=$1; $1=""; sub(/^ /,""); printf "%s\t\303\227%s\n", $0, c}' | sort
}

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
git show "$REF:$FILE" > "$T/before" 2>/dev/null \
  || { printf 'rule-inventory: %s has no %s\n' "$REF" "$FILE" >&2; exit 1; }
extract "$T/before" > "$T/before.inv"
extract "$FILE"     > "$T/after.inv"

printf '# rule inventory: %s (%sB) -> working tree (%sB)\n' \
  "$REF" "$(wc -c < "$T/before" | tr -d ' ')" "$(wc -c < "$FILE" | tr -d ' ')"
printf '# lost (each one has to be justified as an example, a rationale now elsewhere, or a re-wording):\n'
comm -23 "$T/before.inv" "$T/after.inv" | sed 's/^/  - /'
printf '# gained:\n'
comm -13 "$T/before.inv" "$T/after.inv" | sed 's/^/  + /'
printf '# %s line(s) lost\n' "$(comm -23 "$T/before.inv" "$T/after.inv" | grep -c . || true)"
