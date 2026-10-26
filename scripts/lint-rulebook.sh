#!/bin/bash
# Shape lint for the rulebook canonical copy of one tc repo (rulebook/<tc repo>/). One line per
# violation, exit 0 only when there is none.
#
# Dev-only, run by check-invariants.sh.
set -u
export LC_ALL=C

[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: lint-rulebook.sh <rulebook tree of one tc repo>" >&2; exit 2; }
cd "$1" || exit 2

# The stoplist of declarative openers stands in for a POS tagger, which CI does not have.
#
# Terms: general English cannot be listed, so the check reads what the writer marks. An italic span is a
# term and must be a row of the root term table; Hangul belongs only in that table's Korean column.
PARAGRAPH_AWK='
BEGIN { n = split(TERMS, t, "\n"); for (i = 1; i <= n; i++) if (t[i] != "") term[t[i]] = 1 }
function terms_in(line,   s, w, x, y) {
  s = line; gsub(/`[^`]*`/, "", s); gsub(/\*\*/, "", s)
  while (match(s, /\*[^* \t][^*]*\*/)) {
    w = substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH)
    x = tolower(w); y = x; sub(/s$/, "", y)
    if (!(x in term) && !(y in term)) print FILENAME ":" FNR ": \"" w "\" is not in the term table"
  }
}
function flush(   p, i, lead, w) {
  if (start) {
    p = para; gsub(/\n/, " ", p)
    i = index(substr(p, 3), "**")
    lead = i ? substr(p, 3, i - 1) : ""
    if (lead !~ /\.$/ || lead ~ /[.!?][ \t]/)
      print FILENAME ":" start ": rule sentence must be one sentence ending in \".\""
    else {
      w = lead; sub(/[^A-Za-z].*/, "", w)
      if (tolower(w) ~ /^(the|a|an|this|that|these|those|it|its|you|we|they|there|each|every|all|our|your|their)$/)
        print FILENAME ":" start ": rule sentence must be imperative, not start with \"" w "\""
    }
    if (!match(para, /Examples?:/) || substr(para, RSTART + RLENGTH) !~ /[^ \t\n]/)
      print FILENAME ":" start ": rule has no \"Example:\""
  }
  start = 0; para = ""
}
{ table = FILENAME == "AGENTS.md" && ($0 ~ /^\|[ \t]*Term[ \t]*\|/ || (table && /^\|/)) }
!table && $0 ~ HANGUL { print FILENAME ":" FNR ": Hangul outside the term table" }
/^[ \t]*(```|~~~)/ { fence = !fence; if (start) para = para "\n" $0; next }
fence              { if (start) para = para "\n" $0; next }
/^[ \t]*$/         { flush(); blank = 1; next }
{
  if (blank && /^\*\*/) { start = FNR; para = $0 }
  else if (start)       para = para "\n" $0
  blank = 0
  if (TERMED) terms_in($0)
}
END { flush() }
'

checks() {
  local cats want have f terms="" termed=0
  cats=$(find . -mindepth 1 -maxdepth 1 -type d | sed 's|^\./||' | sort)
  want=$({ echo AGENTS.md
           for c in $cats; do printf '%s\n' "$c/AGENTS.md" "$c/rules/test-perspectives.md" "$c/rules/writing-rules.md"; done
         } | sort)
  have=$(find . \( -type f -o -type l \) | sed 's|^\./||' | sort)
  [ -n "$cats" ] || echo ".: no category directory"
  comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$have") | while read -r f; do
    [ -n "$f" ] && echo "$f: missing"
  done
  comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$have") | while read -r f; do
    [ -n "$f" ] && echo "$f: not in the rulebook file set"
  done

  if grep -q '^|[[:space:]]*Term[[:space:]]*|' AGENTS.md 2>/dev/null; then
    termed=1
    terms=$(awk '/^\|[ \t]*Term[ \t]*\|/ { t = 1; next } t && !/^\|/ { exit }
                 t { c = $0; sub(/^\|[ \t]*/, "", c); sub(/[ \t]*\|.*/, "", c); if (c !~ /^:?-+:?$/) print tolower(c) }' AGENTS.md)
  elif [ -f AGENTS.md ]; then echo 'AGENTS.md: no term table (a "| Term |" header row)'; fi

  comm -12 <(printf '%s\n' "$want") <(printf '%s\n' "$have") | while read -r f; do
    [ -n "$f" ] || continue
    awk -v blank=1 -v TERMED="$termed" -v TERMS="$terms" -v HANGUL="$(printf '[\352-\355]')" "$PARAGRAPH_AWK" "$f" \
      | sort -t: -k2,2n -s
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "$f: could not be read"; continue; }
    case "$f" in
      */writing-rules.md)
        for s in '## New TC' '## Changing an existing TC'; do
          grep -qxF "$s" "$f" || echo "$f: missing section \"$s\""
        done ;;
      AGENTS.md|*/AGENTS.md)
        n=$(awk 'END{print NR}' "$f")
        [ "$n" -le 200 ] || echo "$f: $n lines, over 200" ;;
    esac
  done
}

out=$(checks)
[ -z "$out" ] && exit 0
printf '%s\n' "$out"
exit 1
