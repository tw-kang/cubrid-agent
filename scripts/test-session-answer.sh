#!/bin/bash
# Behavioural test for session-answer.sh — the time of a user's answer, found by the session's name.
#
# Dev-only, run by check-invariants.sh. Offline: HOME is a temp dir whose ~/.claude/projects holds canned
# session logs. The project directories start with `-`, as real ones do: that broke `ls -t */*.jsonl` on 11-03.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/session-answer.sh
[ -f "$SRC" ] || { echo "test-session-answer: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P="$T/.claude/projects"; mkdir -p "$P/-proj-a" "$P/-proj-b"

# Every line holds the phrase 새 브랜치 and has its own timestamp, so a line that leaks shows by its time.
cat > "$P/-proj-a/aaaa.jsonl" <<'LOG'
{"type":"custom-title","customTitle":"sess-a","sessionId":"aaaa"}
{"type":"user","timestamp":"2026-11-03T10:00:01.000Z","isMeta":true,"message":{"role":"user","content":"Another Claude session sent a message:\n<cross-session-message from=\"leader\">새 브랜치로 가라</cross-session-message>"}}
{"type":"user","timestamp":"2026-11-03T10:00:02.000Z","message":{"role":"user","content":"Another Claude session sent a message:\n<teammate-message teammate_id=\"research-03\">새 브랜치를 골랐다</teammate-message>"}}
{"type":"user","timestamp":"2026-11-03T10:00:03.000Z","isMeta":true,"message":{"role":"user","content":"<system-reminder>\n새 브랜치\n</system-reminder>"}}
{"type":"user","timestamp":"2026-11-03T10:00:04.000Z","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /x\n\n새 브랜치를 만든다"}]}}
{"type":"assistant","timestamp":"2026-11-03T10:00:04.500Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_bash","name":"Bash","input":{"command":"grep 새 브랜치"}}]}}
{"type":"user","timestamp":"2026-11-03T10:00:05.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_bash","content":"Your questions have been answered: \"브랜치?\"=\"새 브랜치\""}]}}
{"type":"user","timestamp":"2026-11-03T10:00:07.000Z","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\n<result>새 브랜치</result>\n</task-notification>"}}
{"type":"user","timestamp":"2026-11-03T10:00:08.000Z","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued from a previous conversation. 사용자: 새 브랜치"}}
{"type":"user","timestamp":"2026-11-03T10:00:09.000Z","message":{"role":"user","content":"<bash-stdout>새 브랜치</bash-stdout><bash-stderr></bash-stderr>"}}
{"type":"user","timestamp":"2026-11-03T10:00:10.000Z","message":{"role":"user","content":"<local-command-stdout>새 브랜치</local-command-stdout>"}}
{"type":"api-request-blob","timestamp":"2026-11-03T10:00:11.000Z","message":{"role":"user","content":"새 브랜치로 하자"}}
{"type":"user","timestamp":"2026-11-03T10:00:12.000Z","message":{"role":"user","content":"새 브랜치 끝이 잘린
{"type":"user","timestamp":"2026-11-03T10:00:20.000Z","origin":{"kind":"human"},"message":{"role":"user","content":"새 브랜치로 하자"}}
{"type":"user","timestamp":"2026-11-03T10:00:21.000Z","message":{"role":"user","content":[{"type":"text","text":"이름은 -2, -3\n새 브랜치   번호"}]}}
{"type":"assistant","timestamp":"2026-11-03T10:00:22.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_ask1","name":"AskUserQuestion","input":{"questions":[]}}]}}
{"type":"user","timestamp":"2026-11-03T10:00:23.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ask1","content":"Your questions have been answered: \"브랜치?\"=\"새 브랜치\"."}]}}
{"type":"assistant","timestamp":"2026-11-03T10:00:24.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_ask2","name":"AskUserQuestion","input":{"questions":[]}}]}}
{"type":"user","timestamp":"2026-11-03T10:00:25.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ask2","content":"The user answered: \"이름?\"=\"새 브랜치, -2\"."}]}}
{"type":"user","timestamp":"2026-11-03T10:00:27.000Z","message":{"role":"user","content":"<command-message>wayfinder</command-message>\n<command-name>/wayfinder</command-name>\n<command-args>새 브랜치로 진행</command-args>"}}
{"type":"user","timestamp":"2026-11-03T10:00:28.000Z","message":{"role":"user","content":"<command-name>/compact</command-name>\n<command-args>새 브랜치 결정을 남겨라</command-args>"}}
{"type":"user","timestamp":"2026-11-03T10:00:29.000Z","message":{"role":"user","content":"<bash-input>git switch -c 새 브랜치</bash-input>"}}
{"type":"user","timestamp":"2026-11-03T10:00:30.000Z","message":{"role":"user","content":"<pasted_content id=\"1\">새 브랜치 원문</pasted_content>"}}
LOG
A60=$(printf 'a%.0s' {1..60}) B60=$(printf 'b%.0s' {1..60})
printf '{"type":"user","timestamp":"2026-11-03T10:00:26.000Z","message":{"role":"user","content":"%s새 브랜치%s"}}\n' \
  "${A60}${A60}" "${B60}${B60}" >> "$P/-proj-a/aaaa.jsonl"

# 11-03: the first search by name caught the leader's own log, which quoted the other session's prompt.
cat > "$P/-proj-a/bbbb.jsonl" <<'LOG'
{"type":"custom-title","customTitle":"sess-b","sessionId":"bbbb"}
{"type":"user","timestamp":"2026-11-03T09:00:00.000Z","message":{"role":"user","content":"sess-a의 {\"type\":\"custom-title\",\"customTitle\":\"sess-a\"} 새 브랜치"}}
LOG

cat > "$P/-proj-a/cccc.jsonl" <<'LOG'
{"type":"custom-title","customTitle":"dup"}
{"type":"user","timestamp":"2026-11-03T11:00:02.000Z","message":{"role":"user","content":"중복 답 하나"}}
{"type":"user","timestamp":"2026-11-03T11:00:03.000Z","message":{"role":"user","content":"중복 답 둘"}}
LOG
cat > "$P/-proj-b/dddd.jsonl" <<'LOG'
{"type":"custom-title","customTitle":"dup"}
{"type":"user","timestamp":"2026-11-03T11:00:01.000Z","message":{"role":"user","content":"중복 답 셋"}}
LOG

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
pass() { T_PASS=$((T_PASS+1)); }
flat() { printf '%s' "$1" | tr '\n' '|'; }

# run <args...>: OUT holds stdout, ERR stderr, RC the exit.
run() { OUT=$(HOME="$T" bash "$SRC" "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
has() {  # has <exact line> <label>
  if [ "$RC" -ne 0 ]; then note_fail "$2: exit $RC — stderr: $(flat "$ERR")"
  elif printf '%s\n' "$OUT" | grep -qxF -- "$1"; then pass
  else note_fail "$2: no line '$1' — output: $(flat "$OUT")"; fi
}
lacks() {  # lacks <timestamp> <label>
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then note_fail "$2: the $1 line is printed — output: $(flat "$OUT")"
  else pass; fi
}
shown() {  # shown <timestamp> <label>: a user line at that time is printed
  if printf '%s\n' "$OUT" | grep -q "^$1  user  "; then pass
  else note_fail "$2: no user line at $1 — output: $(flat "$OUT")"; fi
}
is() {  # is <exact stdout> <label>
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$1" ]; then pass
  else note_fail "$2: exit $RC — output: $(flat "$OUT")"; fi
}
refused() {  # refused <exit> <label>: that exit and nothing on stdout a reader could take for a time
  if [ "$RC" -ne "$1" ]; then note_fail "$2: exit $RC, expected $1 — output: $(flat "$OUT")"
  elif [ -n "$OUT" ]; then note_fail "$2: printed on a refusal: $(flat "$OUT")"
  else pass; fi
}

run sess-a "새 브랜치"
has "2026-11-03T10:00:20.000Z  user  새 브랜치로 하자" "a typed message held as a string is found"
has "2026-11-03T10:00:21.000Z  user  이름은 -2, -3 새 브랜치 번호" "a typed text block is found, its newline and space runs folded to one space"
has '2026-11-03T10:00:23.000Z  answer  Your questions have been answered: "브랜치?"="새 브랜치".' "an AskUserQuestion answer is found"
# 11-03: the regex caught one of the two answer forms.
has '2026-11-03T10:00:25.000Z  answer  The user answered: "이름?"="새 브랜치, -2".' "the other answer form is found too"
has "2026-11-03T10:00:26.000Z  user  ${A60}새 브랜치${B60}" "a long message shows 60 characters on each side of the phrase"
# What the user typed through a skill command, a built-in command, a ! command or a paste.
shown 2026-11-03T10:00:27.000Z "a skill command's arguments are the user's"
shown 2026-11-03T10:00:28.000Z "a built-in command's arguments are the user's"
shown 2026-11-03T10:00:29.000Z "a ! command is the user's"
shown 2026-11-03T10:00:30.000Z "a paste is the user's"
lacks 10:00:01 "a cross-session message is not the user's"
lacks 10:00:02 "a teammate message that the log does not flag as meta is not the user's either"
lacks 10:00:03 "a system reminder is not the user's"
lacks 10:00:04 "a skill body the harness injected is not the user's"
lacks 10:00:05 "a Bash result that quotes an answer is not an answer, even in the answer's words"
lacks 10:00:07 "a task notification is not the user's"
lacks 10:00:08 "a compaction summary that quotes the user is not the user's"
lacks 10:00:09 "the output of a ! command is not the user's"
lacks 10:00:10 "the output of a local command is not the user's"
lacks 10:00:11 "a line that is not a user line is not read"
lacks 10:00:12 "a cut-off line is skipped, and the lines after it are still read"
lacks 09:00:00 "a log that only quotes the session's title is not that session's log"
[ "$(printf '%s\n' "$OUT" | wc -l)" -eq 9 ] && pass || note_fail "sess-a prints its nine lines and no other: $(flat "$OUT")"

run sess-b "새 브랜치"
is "2026-11-03T09:00:00.000Z  user  sess-a의 {\"type\":\"custom-title\",\"customTitle\":\"sess-a\"} 새 브랜치" \
  "the log whose own title line names the session is read"

run dup "중복 답"
is "2026-11-03T11:00:01.000Z  user  dddd.jsonl  중복 답 셋
2026-11-03T11:00:02.000Z  user  cccc.jsonl  중복 답 하나
2026-11-03T11:00:03.000Z  user  cccc.jsonl  중복 답 둘" \
  "two logs with one title are both read, each line names its file, the earliest line first"

run nobody "새 브랜치"; refused 2 "a name no log has as its title exits 2"
case "$ERR" in *nobody*) pass ;; *) note_fail "the exit-2 reason names the session: $(flat "$ERR")" ;; esac
run sess-a "없는 문구"; refused 1 "a phrase no line holds exits 1"

run;                  refused 2 "no arguments are refused"
run sess-a;           refused 2 "a missing phrase is refused"
run sess-a x y;       refused 2 "an extra argument is refused"
run "" "새 브랜치";    refused 2 "an empty name is refused"
run sess-a "";        refused 2 "an empty phrase is refused"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'session-answer: %d/%d\n' "$T_PASS" "$T_PASS"; exit 0
else
  printf 'session-answer: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"; exit 1
fi
