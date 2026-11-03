#!/bin/bash
# Behavioural test for rule-inventory.sh — the "no rule lost" check AGENTS.md asks for when a doc is slimmed.
#
# Dev-only, run by check-invariants.sh. Offline: a throwaway git repo.
#
# Runs under en_US.UTF-8 on purpose. That collation ranks many two-syllable Hangul tokens equal, so
# `sort | uniq -c` folded **다라** into **가나** and a renamed rule read as "0 lost". Where the locale is
# not installed the cases still pin the right answer, they just cannot reproduce the fold.
set -u

INV=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/rule-inventory.sh
[ -f "$INV" ] || { echo "test-rule-inventory: script not found at $INV" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
git -C "$T" init -q
git -C "$T" -c user.name=t -c user.email=t@t commit -q --allow-empty -m root

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }

case_() {  # case_ <name> <before body> <after body> <expected lost count> <item that must be listed as lost or "">
  printf '%s\n' "$2" > "$T/doc.md"
  git -C "$T" add doc.md && git -C "$T" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"
  printf '%s\n' "$3" > "$T/doc.md"
  OUT=$(cd "$T" && LC_ALL=en_US.UTF-8 bash "$INV" HEAD doc.md 2>&1)
  if ! printf '%s\n' "$OUT" | grep -q "^# $4 line(s) lost$"; then
    note_fail "$1: expected $4 lost, got: $(printf '%s' "$OUT" | tail -1)"; return
  fi
  if [ -n "$5" ] && ! printf '%s\n' "$OUT" | grep -qF -- "  - $5"; then
    note_fail "$1: expected $5 among the lost items, got:
$OUT"; return
  fi
  T_PASS=$((T_PASS+1))
}

case_ "renamed Hangul rule is lost"   $'**가나**\n**다라**' $'**가나**\n**마바**' 1 '**다라**'
case_ "removed Hangul rule is lost"   $'**가나**\n**다라**' $'**가나**'           1 '**다라**'
case_ "unchanged Hangul rules"        $'**가나**\n**다라**' $'**가나**\n**다라**' 0 ''
case_ "one of two occurrences gone"   $'`x`\n`x`'          $'`x`'               1 '`x`'

if [ "$T_FAIL" -eq 0 ]; then
  printf 'rule-inventory: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'rule-inventory: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
