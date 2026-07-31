#!/bin/bash
# Print, or diff, the rule inventory of a skill body — the thing that must NOT change when a SKILL.md is
# slimmed. Everything goes to stdout: an earlier ad-hoc version of this check wrote its two inventory
# files next to the skill it was measuring, and `git add -A` shipped them inside the plugin (cdc3d43).
#
# The inventory is deliberately crude: every bold span, every backticked token, and every heading. A rule
# in these bodies is almost always written as one of the three, so a rule that disappears shows up here —
# while re-wording a sentence around it does not. It cannot prove a rule was kept (a rule can survive as
# a token while losing its meaning), so read the diff, do not just count it.
#
# usage: rule-inventory.sh <file>                 print the inventory
#        rule-inventory.sh <git-ref> <file>       diff that ref's version against the working tree
set -u

USAGE='usage: rule-inventory.sh <file> | rule-inventory.sh <git-ref> <file>'
extract() {  # extract <path-or-->
  local _src=$1
  { grep -oE '\*\*[^*]+\*\*' "$_src"
    grep -oE '`[^`]+`'       "$_src"
    grep -oE '^#{1,6} .*'    "$_src"
  } 2>/dev/null | sort -u
}

case $# in
  1) [ -f "$1" ] || { printf 'rule-inventory: no such file: %s\n' "$1" >&2; exit 1; }
     extract "$1" ;;
  2) _ref=$1; _file=$2
     [ -f "$_file" ] || { printf 'rule-inventory: no such file: %s\n' "$_file" >&2; exit 1; }
     _t=$(mktemp -d) || exit 1
     trap 'rm -rf "$_t"' EXIT
     git show "$_ref:$_file" > "$_t/before" 2>/dev/null \
       || { printf 'rule-inventory: %s has no %s\n' "$_ref" "$_file" >&2; exit 1; }
     extract "$_t/before" > "$_t/before.inv"
     extract "$_file"     > "$_t/after.inv"
     printf '# rule inventory: %s (%s) -> working tree (%s)\n' \
       "$_ref" "$(wc -c < "$_t/before" | tr -d ' ')B" "$(wc -c < "$_file" | tr -d ' ')B"
     printf '# lost (each one has to be justified as an example or a rationale, never a rule):\n'
     comm -23 "$_t/before.inv" "$_t/after.inv" | sed 's/^/  - /'
     printf '# gained:\n'
     comm -13 "$_t/before.inv" "$_t/after.inv" | sed 's/^/  + /'
     _n=$(comm -23 "$_t/before.inv" "$_t/after.inv" | grep -c . || true)
     printf '# %s item(s) lost\n' "$_n" ;;
  *) printf '%s\n' "$USAGE" >&2; exit 1 ;;
esac
