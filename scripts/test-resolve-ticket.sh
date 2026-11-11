#!/bin/bash
# Behavioural test for resolve-ticket.sh — a ticket closes only when its boxes are ticked and its last
# Answer names /code-review, and the Status line then carries the time `date` gave.
#
# Dev-only, run by check-invariants.sh. Offline: every ticket is a temp file.
set -u

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/resolve-ticket.sh
[ -f "$SRC" ] || { echo "test-resolve-ticket: script not found at $SRC" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
pass() { T_PASS=$((T_PASS+1)); }
flat() { printf '%s' "$1" | tr '\n' '|'; }

# ticket <name>: stdin becomes the ticket file $T/<name>.md; TICKET holds its path.
ticket() { TICKET="$T/$1.md"; cat > "$TICKET"; cp "$TICKET" "$TICKET.orig"; }
# run <args...>: OUT holds stdout, ERR stderr, RC the exit.
run() { OUT=$(bash "$SRC" "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
refused() {  # refused <exit> <label>: that exit, and the ticket is byte-for-byte unchanged
  if [ "$RC" -ne "$1" ]; then note_fail "$2: exit $RC, want $1 — stdout: $(flat "$OUT") stderr: $(flat "$ERR")"
  elif [ -n "${TICKET:-}" ] && [ -f "$TICKET.orig" ] && ! cmp -s "$TICKET" "$TICKET.orig"; then
    note_fail "$2: the ticket changed on a refusal"
  else pass; fi
}
says() {  # says <text> <label>: stdout or stderr holds the text
  if printf '%s\n%s\n' "$OUT" "$ERR" | grep -qF -- "$1"; then pass
  else note_fail "$2: no '$1' — stdout: $(flat "$OUT") stderr: $(flat "$ERR")"; fi
}

ticket boxes <<'MD'
# 01: x

**Status:** claimed (s1, 2026-11-11 10:00)

- [x] done
- [ ] not done yet

## Answer

- /code-review: Standards and Spec ran.
MD
run "$TICKET" s1; refused 1 "an unticked box at the start of a line refuses the close"
says '6: - [ ] not done yet' "the refusal names the unticked line with its number"

# resolved <want line with @ for the time> <label>: exit 0, the Status line is <want> with a time `date`
# gave during the run, it is printed, and no other line changed.
resolved() {
  local got time rest
  if [ "$RC" -ne 0 ]; then note_fail "$2: exit $RC — stdout: $(flat "$OUT") stderr: $(flat "$ERR")"; return; fi
  got=$(grep -m1 -E '^(\*\*Status:\*\*|Status:) ' "$TICKET")
  time=$(printf '%s' "$got" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' | head -1)
  if [ "${1//@/$time}" != "$got" ]; then note_fail "$2: Status line is '$got', want '$1'"
  elif [[ "$time" < "$BEFORE" || "$time" > "$AFTER" ]]; then note_fail "$2: time $time is outside the run ($BEFORE–$AFTER)"
  elif ! printf '%s\n' "$OUT" | grep -qxF -- "$got"; then note_fail "$2: the new Status line is not printed — stdout: $(flat "$OUT")"
  elif ! diff <(grep -v -E '^(\*\*Status:\*\*|Status:) ' "$TICKET") <(grep -v -E '^(\*\*Status:\*\*|Status:) ' "$TICKET.orig") >/dev/null; then
    note_fail "$2: a line other than Status changed"
  else pass; fi
}
timed() { BEFORE=$(date '+%Y-%m-%d %H:%M'); run "$@"; AFTER=$(date '+%Y-%m-%d %H:%M'); }

ticket map <<'MD'
# 03: map ticket

Type: task
Status: claimed (v2-03, 2026-11-11 10:00)
Blocked by: —

> **What to build:** the absorbed ticket, kept as history.
>
> - [ ] a box inside a quote is history, not a task

## Answer

- `/code-review` ran: Standards 0, Spec 0.

## Comments

- [x] note
MD
timed "$TICKET" v2-03
resolved 'Status: resolved (v2-03, @)' "a quoted box does not count; a plain Status line is overwritten"

REOPENED='claimed (s2, 2026-11-11 10:00) · 이전: ready-for-agent — 재오픈 (2026-11-10 20:13 · leader — 질문) · 이전: resolved (s0, 2026-11-04 17:15)'
ticket reopened <<MD
# 02: spec ticket

**Status:** $REOPENED

- [x] first round

## Answer

- first round, reviewed before /code-review existed.

## 재오픈 (2026-11-10, leader — 질문)

1. do the new thing.

## Answer (재오픈분 — 2026-11-11, s2)

- \`/code-review\`: Standards 1 fixed, Spec 0.

## Comments
MD
timed "$TICKET" s2
resolved "**Status:** resolved (s2, @) · 이전: $REOPENED" "a reopened ticket keeps its chain: the new value goes first"

# S3 04: resolved before /code-review ran. The first-round Answer named the review; the reopen's did not.
ticket last-answer-unreviewed <<'MD'
**Status:** claimed (s3, 2026-11-11 10:00) · 이전: ready-for-agent — 재오픈 (2026-11-10 20:13 · leader — x)

## Answer

- `/code-review`: Standards 0, Spec 0.

## 재오픈 (2026-11-10, leader — x)

1. more work.

## Answer (재오픈분 — 2026-11-11, s3)

- done; review comes later.
MD
run "$TICKET" s3; refused 1 "the last Answer, not an earlier one, has to name /code-review"
says '/code-review' "the refusal says /code-review is missing"

# The 1-03 ticket on 11-11: the 11-04 Answer named /code-review, the 11-10 reopen came after it, and its
# own Answer was not written yet. The last Answer in the file is then the previous round's.
ticket reopen-unanswered <<'MD'
**Status:** claimed (s4, 2026-11-11 10:00) · 이전: ready-for-agent — 재오픈 (2026-11-10 20:13 · leader — y)

## Answer (재오픈분 — 2026-11-04, s0)

- `/code-review`: Standards 0, Spec 0.

## 재오픈 (2026-11-10, leader — y)

1. more work.

## Comments
MD
run "$TICKET" s4; refused 1 "a reopen with no Answer after it is not answered by the previous round's Answer"
says '## 재오픈 (2026-11-10, leader — y)' "the refusal names the unanswered reopen"

ticket no-answer <<'MD'
Status: claimed (s5, 2026-11-11 10:00)

- [x] done

## Comments

- `/code-review` will run.
MD
run "$TICKET" s5; refused 1 "no Answer at all refuses, even when Comments name /code-review"
says 'no "## Answer" section' "the refusal says there is no Answer, not a crash's exit 1"

ticket review-in-comments <<'MD'
Status: claimed (s6, 2026-11-11 10:00)

## Answer

- done.

## Comments

- `/code-review` ran after the Answer.
MD
run "$TICKET" s6; refused 1 "/code-review under a later heading is not in the Answer"

# Resolve 1 keeps an earlier round's boxes as they are, so only the last round's boxes can refuse. The S1
# deploy-tool ticket keeps an unticked box from its 10-28 round; its last round is 11-03.
ticket old-round-box <<'MD'
**Status:** claimed (s9, 2026-11-11 10:00) · 이전: ready-for-agent — 재오픈 (2026-11-03 17:37 · leader — z)

## 재오픈 (2026-10-28, leader — w)

- [ ] after the merge: a follow-up another session does.

## Answer (재오픈분 — 2026-10-28, s0)

- `/code-review`: Standards 0, Spec 0.

## 재오픈 (2026-11-03, leader — z)

- [x] the new round's box

## Answer (재오픈분 — 2026-11-11, s9)

- `/code-review`: Standards 0, Spec 0.
MD
timed "$TICKET" s9
resolved "**Status:** resolved (s9, @) · 이전: claimed (s9, 2026-11-11 10:00) · 이전: ready-for-agent — 재오픈 (2026-11-03 17:37 · leader — z)" \
  "an unticked box in an earlier round does not refuse the last round"

ticket last-round-box <<'MD'
**Status:** claimed (s10, 2026-11-11 10:00) · 이전: ready-for-agent — 재오픈 (2026-11-03 17:37 · leader — z)

## Answer

- `/code-review`: Standards 0, Spec 0.

## 재오픈 (2026-11-03, leader — z)

- [ ] the new round's box

## Answer (재오픈분 — 2026-11-11, s10)

- `/code-review`: Standards 0, Spec 0.
MD
run "$TICKET" s10; refused 1 "an unticked box in the last round refuses"
says '9: - [ ] the new round'"'"'s box' "the refusal names the last round's box with its number"

# The 1-03 Answer draft on 11-11 had the review only as a heading, before the review ran; S3 04's Answer
# had the heading "### \`/code-review\`와 순서".
ticket review-heading-only <<'MD'
Status: claimed (s11, 2026-11-11 10:00)

## Answer

### `/code-review`

- PLACEHOLDER
MD
run "$TICKET" s11; refused 1 "/code-review only in a heading is no record of a review"

ticket no-status <<'MD'
# 07: no status line

## Answer

- `/code-review` ran.
MD
run "$TICKET" s7; refused 2 "a ticket with no Status line exits 2"
says 'Status' "the exit-2 reason names the missing Status line"

TICKET=""
run "$T/absent.md" s8; refused 2 "a missing ticket file exits 2"
run;                   refused 2 "no arguments are refused"
run "$T/map.md";       refused 2 "a missing session name is refused"
run "$T/map.md" "";    refused 2 "an empty session name is refused"
run "$T/map.md" a b;   refused 2 "an extra argument is refused"

if [ "$T_FAIL" -eq 0 ]; then
  printf 'resolve-ticket: %d/%d\n' "$T_PASS" "$T_PASS"; exit 0
else
  printf 'resolve-ticket: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"; exit 1
fi
