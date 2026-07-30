#!/bin/bash
# Ground one CBRD issue into the run directory: the issue body + every comment as readable text,
# every attachment downloaded and classified by what it actually is.
#
# Not a hook — skills call it directly, so that "read the issue and all of its attachments" is one
# command instead of the same nine lines of prose repeated in every skill that grounds an issue.
# What it centralises, and why prose could not:
#
#   * `jql`, never `search` — `search` renders markdown through pandoc, and a pandoc without the
#     `jira` reader (the RHEL 8 package is one) returns a degraded or empty body with a success exit.
#   * classification by content, not by mimeType or filename. Jira's mimeType is wrong often enough
#     to matter: CBRD-27141's `qa27141.out` (the expected output of the repro) is served as
#     `application/octet-stream` but is ASCII text, and "skip the binaries" loses it.
#   * archives are opened. CBRD-26909 ships the developer's whole intended case set as `cases.tgz`
#     (23 .sql/.result files) — the one attachment that matters most, and the one a mimeType rule
#     discards as a binary.
#   * a PDF needs `pdftotext` (poppler-utils); without it the file is recorded as unread WITH the
#     reason, never guessed at from its name (CUBRIDQA-1488).
#   * `select.issue_type` lands in the manifest from Jira itself, so the placement lint always has
#     the input it needs to decide the TC's tree (CUBRIDQA-1486).
#
# usage: ground-issue.sh <KEY> [--run-dir DIR] [--refresh]
set -u

USAGE="usage: ground-issue.sh <CBRD-XXXXX> [--run-dir DIR] [--refresh]"
KEY=""; RUN_DIR=""; REFRESH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:?$USAGE}"; shift 2 ;;
    --refresh) REFRESH=1; shift ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*)        printf 'ground-issue: unknown option: %s\n%s\n' "$1" "$USAGE" >&2; exit 1 ;;
    *)         KEY=$(printf '%s' "$1" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'); shift ;;
  esac
done
[ -n "$KEY" ] || { printf 'ground-issue: need an issue key\n%s\n' "$USAGE" >&2; exit 1; }

for c in cubrid-jira jq; do
  command -v "$c" >/dev/null 2>&1 || {
    printf 'ground-issue: %s is not installed — run /setup-cubrid-agent --install-clis (or install %s) and ground again.\n' "$c" "$c" >&2
    exit 1; }
done

: "${RUN_DIR:=$HOME/.cubrid-agent/$KEY}"
ATT_DIR="$RUN_DIR/attachments"
ISSUE_JSON="$RUN_DIR/issue.json"
ISSUE_TXT="$RUN_DIR/issue.txt"
ATT_JSON="$RUN_DIR/attachments.json"
mkdir -p "$ATT_DIR" || exit 1

# One CLI failure must not become many: a repeated 401 is what trips JIRA's CAPTCHA lockout, so a
# failed fetch reports the cause and stops. Codes are the CLI's contract (2=401, 3=403, 4=404).
cli_fail() {
  case "$1" in
    2) printf 'ground-issue: JIRA rejected the credentials (401). Do NOT retry — repeated 401s trigger a CAPTCHA account lock. Fix the jira.cubrid.org entry in ~/.netrc, then ground again.\n' >&2 ;;
    3) printf 'ground-issue: JIRA denied access to %s (403) — your account cannot read this issue.\n' "$KEY" >&2 ;;
    4) printf 'ground-issue: %s does not exist (404).\n' "$KEY" >&2 ;;
    5) printf 'ground-issue: JIRA rejected the query for %s (400) — most often a key that does not exist.\n' "$KEY" >&2 ;;
    *) printf 'ground-issue: cubrid-jira %s failed (exit %s).\n' "$2" "$1" >&2 ;;
  esac
  [ -s "$RUN_DIR/.ground.err" ] && sed -n '1,3p;$p' "$RUN_DIR/.ground.err" >&2
  exit "$1"
}

FIELDS=summary,issuetype,status,resolution,description,comment,attachment,fixVersions,customfield_210441,customfield_210565,customfield_213834,assignee,reporter,parent,subtasks,labels,components,priority

# ── issue body + comments ────────────────────────────────────────────────────────────────────────
# Cached per run directory: two skills grounding the same issue in one run (author-testcase then
# create-sql) must not pay for the query twice. Source data only — never a verdict (DP5).
if [ "$REFRESH" = 1 ] || [ ! -s "$ISSUE_JSON" ]; then
  cubrid-jira jql "key = $KEY" --fields "$FIELDS" --output json > "$ISSUE_JSON.part" 2>"$RUN_DIR/.ground.err" \
    || cli_fail "$?" "jql"
  jq -e '.issues[0].key' "$ISSUE_JSON.part" >/dev/null 2>&1 \
    || { printf 'ground-issue: %s returned no issue — check the key.\n' "$KEY" >&2; rm -f "$ISSUE_JSON.part"; exit 4; }
  mv "$ISSUE_JSON.part" "$ISSUE_JSON"
fi

# Readable rendering: raw Jira wiki markup, which reads fine as-is — the point is that the
# description AND every comment sit in one file, because the repro is comment-only as often as not.
jq -r '
  def v: if . == null then "-"
         elif type == "array" then (if length == 0 then "-" else map(v) | join(", ") end)
         elif type == "object" then (.value // .name // .key // .displayName // tostring)
         else tostring end;
  .issues[0] as $i | $i.fields as $f |
  "== " + $i.key + "  " + ($f.summary // "-"),
  "type/status  : " + ($f.issuetype|v) + " / " + ($f.status|v) + " / " + ($f.resolution|v),
  "fixVersions  : " + ($f.fixVersions|v) + "   planned: " + ($f.customfield_210441|v),
  "QA scenario  : " + ($f.customfield_210565|v) + "   QA assignee: " + ($f.customfield_213834|v),
  "assignee     : " + ($f.assignee|v) + "   reporter: " + ($f.reporter|v),
  "parent       : " + ($f.parent|v) + "   subtasks: " + ([$f.subtasks[]?.key]|v),
  "labels       : " + ($f.labels|v) + "   components: " + ($f.components|v),
  "",
  "-- description ------------------------------------------------------------",
  ($f.description // "(empty)"),
  ( ($f.comment.comments // [])
    | to_entries[]
    | "\n-- comment " + ((.key+1)|tostring) + " — " + (.value.author|v) + ", " + (.value.created // "?")
      + " ------------\n" + (.value.body // "") )
' "$ISSUE_JSON" > "$ISSUE_TXT" || exit 1

ITYPE=$(jq -r '.issues[0].fields.issuetype.name // empty' "$ISSUE_JSON")
NCOMM=$(jq -r '(.issues[0].fields.comment.comments // []) | length' "$ISSUE_JSON")

# ── attachments ──────────────────────────────────────────────────────────────────────────────────
# The CLI applies the 5 MiB wire gate itself, so a core never lands on the disk; oversize files come
# back downloaded:false with a reason, which is exactly what "record it as unread with the reason"
# needs.
if [ "$REFRESH" = 1 ] || [ ! -s "$ATT_JSON" ]; then
  cubrid-jira attachment "$KEY" --out "$ATT_DIR" --output json > "$ATT_JSON.part" 2>"$RUN_DIR/.ground.err" \
    || { rc=$?; case $rc in 2|3|4) cli_fail "$rc" attachment ;; esac
         printf 'ground-issue: cubrid-jira attachment failed (exit %s). If the subcommand is missing the CLI is stale — uv tool upgrade cubrid-jira.\n' "$rc" >&2
         rm -f "$ATT_JSON.part"; exit "$rc"; }
  mv "$ATT_JSON.part" "$ATT_JSON"
fi

READ_LIST=""; VIEW_LIST=""; UNREAD_LIST=""; UNREAD_JSON="[]"
add_unread() { # filename, reason
  UNREAD_LIST="$UNREAD_LIST$1|$2"$'\n'
  UNREAD_JSON=$(printf '%s' "$UNREAD_JSON" | jq -c --arg f "$1" --arg r "$2" '. + [{filename:$f, reason:$r}]')
}

# Split on US (\x1f), not on tabs: bash collapses runs of IFS *whitespace*, so a not-downloaded
# attachment (empty `path`) would shift every later column and silently drop the skip reason.
while IFS=$'\x1f' read -r fname fsize fmime fpath fdown fskip; do
  [ -n "$fname" ] || continue
  if [ "$fdown" != true ] || [ -z "$fpath" ] || [ ! -f "$fpath" ]; then
    add_unread "$fname" "${fskip:-not downloaded}"
    continue
  fi
  mime=$(file -b --mime-type "$fpath" 2>/dev/null)
  enc=$(file -b --mime-encoding "$fpath" 2>/dev/null)
  desc=$(file -b "$fpath" 2>/dev/null | cut -c1-100)
  case "$mime" in
    image/*)
      VIEW_LIST="$VIEW_LIST$fpath|$desc"$'\n' ;;
    application/pdf)
      if command -v pdftotext >/dev/null 2>&1 && pdftotext -layout "$fpath" "$fpath.txt" 2>/dev/null; then
        READ_LIST="$READ_LIST$fpath.txt|pdf text, extracted"$'\n'
      else
        add_unread "$fname" "PDF and no pdftotext (poppler-utils) to extract it — its contents are unknown, do not guess them from the name"
      fi ;;
    *)
      # Archives carry the intended case set often enough that skipping them defeats the point.
      xdir="$fpath.d"
      if tar tf "$fpath" >/dev/null 2>&1; then
        mkdir -p "$xdir" && tar xf "$fpath" -C "$xdir" 2>/dev/null
      elif command -v unzip >/dev/null 2>&1 && unzip -l "$fpath" >/dev/null 2>&1; then
        mkdir -p "$xdir" && unzip -o -q "$fpath" -d "$xdir" 2>/dev/null
      elif [ "$mime" = application/gzip ]; then
        mkdir -p "$xdir" && gunzip -c "$fpath" > "$xdir/${fname%.gz}" 2>/dev/null
      fi
      if [ -d "$xdir" ]; then
        n=$(find "$xdir" -type f | wc -l | tr -d ' ')
        names=$(find "$xdir" -type f -printf '%P\n' 2>/dev/null | sort | head -8 | paste -sd, -)
        [ "$n" -gt 8 ] && names="$names, +$((n-8)) more"
        READ_LIST="$READ_LIST$xdir/|archive, $n file(s): $names"$'\n'
      elif [ "$enc" != binary ]; then
        note="$mime"
        case "$fmime" in application/octet-stream|"") note="$mime (JIRA said $fmime)" ;; esac
        READ_LIST="$READ_LIST$fpath|text, $fsize B, $note"$'\n'
      else
        add_unread "$fname" "binary — $desc"
      fi ;;
  esac
done < <(jq -r '.attachments[]? | [.filename, (.size|tostring), (.mimeType // ""), (.path // ""), ((.downloaded // false)|tostring), (.skipped // "")] | join("\u001f")' "$ATT_JSON")

NATT=$(jq -r '.count // 0' "$ATT_JSON")

# ── manifest ─────────────────────────────────────────────────────────────────────────────────────
# select.issue_type comes from JIRA rather than from the agent restating it: the lint hook needs it
# to check the TC's tree, and an unrecorded type makes placement unverifiable, which blocks submit.
MANIFEST="$RUN_DIR/manifest.json"
[ -f "$MANIFEST" ] || printf '{}' > "$MANIFEST"
tmp=$(mktemp)
if jq --arg k "$KEY" --arg t "$ITYPE" --argjson nc "$NCOMM" --argjson na "${NATT:-0}" \
      --argjson unread "$UNREAD_JSON" \
      --argjson nr "$(printf '%s' "$READ_LIST" | grep -c . || true)" \
      --argjson nv "$(printf '%s' "$VIEW_LIST" | grep -c . || true)" \
   '.issue = (.issue // $k)
    | (if $t != "" then .select.issue_type = $t else . end)
    | .ground = {comments: $nc, attachments: {total: $na, read: $nr, images: $nv, unread: $unread}}' \
   "$MANIFEST" > "$tmp" 2>/dev/null; then mv "$tmp" "$MANIFEST"; else rm -f "$tmp"; fi

# ── what the caller has to do next ───────────────────────────────────────────────────────────────
printf '[ground] %s → %s\n' "$KEY" "$RUN_DIR"
printf '  issue  : %s  (%s; description + %s comment(s), raw JIRA markup)\n' "$ISSUE_TXT" "${ITYPE:-type unknown}" "$NCOMM"
printf '  attach : %s total\n' "${NATT:-0}"
printf '%s' "$READ_LIST"   | while IFS='|' read -r p d; do [ -n "$p" ] && printf '    read : %s  (%s)\n' "$p" "$d"; done
printf '%s' "$VIEW_LIST"   | while IFS='|' read -r p d; do [ -n "$p" ] && printf '    view : %s  (%s)\n' "$p" "$d"; done
printf '%s' "$UNREAD_LIST" | while IFS='|' read -r p d; do [ -n "$p" ] && printf '  unread : %s  — %s\n' "$p" "$d"; done
printf '  next   : read issue.txt and every `read` path; open each `view` path with the Read tool (it renders images).\n'
[ -n "$UNREAD_LIST" ] && printf '           an `unread` attachment stays unread — say so in the report, and never infer its contents from its filename.\n'
exit 0
