#!/bin/bash
# Shape lint for the rulebook canonical copy of one tc repo (rulebook/<tc repo>/). One line per
# violation, exit 0 only when there is none. --terms prints the term column of the root term table.
#
# Dev-only, run by check-invariants.sh.
set -u
export LC_ALL=C

TERMS_ONLY=0
[ "${1:-}" = --terms ] && { TERMS_ONLY=1; shift; }
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: lint-rulebook.sh [--terms] <rulebook tree of one tc repo>" >&2; exit 2; }
cd "$1" || exit 2

term_column() {
  awk '/^\|[ \t]*Term[ \t]*\|/ { t = 1; next } t && !/^\|/ { exit }
       t { c = $0; sub(/^\|[ \t]*/, "", c); sub(/[ \t]*\|.*/, "", c); if (c !~ /^:?-+:?$/) print c }' AGENTS.md
}
[ "$TERMS_ONLY" -eq 1 ] && { term_column; exit; }

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

# Links: the tree is what the tc repo receives, so a relative link must land on a file of the tree, never on
# the disk around it. A link starting with "/" is an absolute path to the agent that reads the file, so it
# never resolves. Anchors are GitHub's heading anchors. GitHub keeps non-ASCII letters, which this drops,
# but the body is English and Hangul outside the term table is a violation already.
LINK_AWK='
BEGIN { for (i = 1; i < ARGC; i++) file[ARGV[i]] = 1 }
function resolve(from, path,   n, i, seg, p) {
  if (path ~ /^\//) return ""
  sub(/[^\/]*$/, "", from); n = split(from path, seg, "/")
  for (i = 1; i <= n; i++)
    if (seg[i] == "..") { if (p == "") return ""; sub(/\/?[^\/]*$/, "", p) }
    else if (seg[i] != "" && seg[i] != ".") p = p (p == "" ? "" : "/") seg[i]
  return p
}
FNR == 1           { fence = 0 }
/^[ \t]*(```|~~~)/ { fence = !fence; next }
fence              { next }
/^#+[ \t]/ {
  h = tolower($0); sub(/^#+[ \t]+/, "", h); sub(/[ \t]+$/, "", h); gsub(/[^a-z0-9_ -]/, "", h); gsub(/ /, "-", h)
  rep = seen[FILENAME, h]++; anchor[FILENAME, rep ? h "-" rep : h] = 1
}
{
  s = $0; gsub(/`[^`]*`/, "", s)
  while (match(s, /]\([^) \t]+/)) {
    t = substr(s, RSTART + 2, RLENGTH - 2); s = substr(s, RSTART + RLENGTH)
    if (t !~ /^[A-Za-z][A-Za-z0-9+.-]*:/) link[++nl] = FILENAME SUBSEP FNR SUBSEP t
  }
}
END {
  for (i = 1; i <= nl; i++) {
    split(link[i], l, SUBSEP); t = l[3]; a = ""
    if ((hash = index(t, "#"))) { a = substr(t, hash + 1); t = substr(t, 1, hash - 1) }
    p = t == "" ? l[1] : resolve(l[1], t)
    if (!(p in file)) print l[1] ":" l[2] ": link \"" l[3] "\" is not a file of the rulebook"
    else if (a != "" && !((p, a) in anchor)) print l[1] ":" l[2] ": link \"" l[3] "\": " p " has no heading \"#" a "\""
  }
}
'

violations() {
  local cats want have present f terms="" termed=0 readable=()
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
    terms=$(term_column | tr '[:upper:]' '[:lower:]')
  elif [ -f AGENTS.md ]; then echo 'AGENTS.md: no term table (a "| Term |" header row)'; fi

  present=$(comm -12 <(printf '%s\n' "$want") <(printf '%s\n' "$have"))
  printf '%s\n' "$present" | while read -r f; do
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

  mapfile -t readable < <(printf '%s\n' "$present" | while read -r f; do [ -r "$f" ] && printf '%s\n' "$f"; done)
  [ ${#readable[@]} -eq 0 ] || awk "$LINK_AWK" "${readable[@]}"
}

out=$(violations)
[ -z "$out" ] && exit 0
printf '%s\n' "$out"
exit 1
