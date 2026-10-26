#!/bin/bash
# Behavioural test for research-recheck.py — the "exit 0 before resolve" check a research ticket needs.
#
# Dev-only, run by check-invariants.sh. Offline: every case is a throwaway result/repro pair in a temp
# directory. Only the CLI seam is observed: exit code and stdout.
set -u

RECHECK=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/research-recheck.py
[ -f "$RECHECK" ] || { echo "test-research-recheck: script not found at $RECHECK" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "test-research-recheck: python3 not found" >&2; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }
flat() { printf '%s' "$1" | tr '\n' '|'; }

# blk <ID> <sh> [expected [independent]]  -> one repro block on stdout; an empty 3rd arg is an empty
# expected. Without a 4th arg the block gets an independent fence that prints the expected with printf, so
# cases about other rules meet the independent floor and never repeat their sh; an empty 4th arg leaves the
# fence out.
blk() {
  printf '#### [%s]\n\n```sh\n%s\n```\n' "$1" "$2"
  [ $# -ge 3 ] && printf '\n```expected\n%s\n```\n' "$3"
  [ $# -eq 3 ] && printf '\n```independent\nprintf '"'"'%%s\\n'"'"' %q\n```\n' "$3"
  [ -n "${4-}" ] && printf '\n```independent\n%s\n```\n' "$4"
  printf '\n'
}

N=0; D=
fixture() {  # fixture <result body> <repro body>  -> D holds r.md and r.repro.md
  N=$((N+1)); D="$T/$N"; mkdir -p "$D"
  printf '%s\n' "$1" > "$D/r.md"
  printf '%s\n' "$2" > "$D/r.repro.md"
}

expect() {  # expect <want-exit> <pattern|""> <label> -- <args...>
  local want=$1 pat=$2 label=$3 out rc; shift 4
  out=$(python3 "$RECHECK" "$@" 2>&1); rc=$?
  if [ "$rc" -ne "$want" ]; then note_fail "$label: exit $rc, expected $want — output: $(flat "$out")"; return; fi
  if [ -n "$pat" ] && ! printf '%s\n' "$out" | grep -qE "$pat"; then
    note_fail "$label: no line matching /$pat/ — output: $(flat "$out")"; return
  fi
  T_PASS=$((T_PASS+1))
}

fixture '값은 3이다 [A].' "$(blk A "printf '3\n'" '3')"
expect 0 '^\[A\] PASS' "a block whose output equals its expected passes" -- "$D/r.md"

fixture '값은 3이다 [A].' "$(blk A "printf '4\n'" '3')"
expect 1 '^\[A\] FAIL' "output that differs from expected fails" -- "$D/r.md"

# The research script and the expected agree on 43; a command that skips the script counts 42.
fixture '값은 43이다 [A].' "$(blk A "printf '43\n'" '43' "printf '42\n'")"
expect 1 '^\[A\] FAIL' "an independent fence that disagrees with expected fails though the sh output matches" -- "$D/r.md"

fixture '[A]' "$(blk A "printf 'pop 882\ncases 17627\n'" $'pop 882\ncases 17627' "echo 'cases 17627'")"
expect 0 '^\[A\] PASS' "an independent fence may confirm one line of a longer expected" -- "$D/r.md"

fixture '[A]' "$(blk A 'echo 3' '3' 'true')"
expect 1 '^\[A\] FAIL' "an independent fence that prints nothing fails — nothing was confirmed" -- "$D/r.md"

fixture '[A]' "$(blk A 'echo 3' '3' 'echo  3')"
expect 1 'COPIED SH.*\[A\]' "an independent fence that repeats the sh fence fails — it is not a second path" -- "$D/r.md"

fixture '[A] [B] [C] [D] [E] [F]' "$(for i in A B C D; do blk $i 'echo 1' '1'; done; blk E 'echo 1' '1' ''; blk F 'echo 1' '1' '')"
expect 1 '^TOO FEW INDEPENDENT' "four independent fences among six blocks fail — five are needed" -- "$D/r.md"

fixture '[A] [B] [C] [D] [E] [F]' "$(for i in A B C D E; do blk $i 'echo 1' '1'; done; blk F 'echo 1' '1' '')"
expect 0 '^INDEPENDENT: \[A\] \[B\] \[C\] \[D\] \[E\] \(5 of 5' "five independent fences among six blocks pass" -- "$D/r.md"

fixture '[A]' "$(blk A 'echo 1' '1'; blk A 'echo 1' '1')"
expect 0 '^INDEPENDENT: \[A\] \(1 of 1 needed' "an ID defined twice counts once toward the floor" -- "$D/r.md"

fixture '[A] [B]' "$(blk A 'echo 1' '1'; blk B 'echo 1' '1' '')"
expect 1 '^TOO FEW INDEPENDENT.*1 of 2' "a result with fewer than five blocks needs a fence in every block" -- "$D/r.md"

fixture '[A]' "$(blk A 'echo 3' '3' ': origin/develop; echo 3')"
expect 1 'UNPINNED.*\[A\].*origin/' "an independent fence that names origin/... fails" -- "$D/r.md"

fixture '값은 3이다 [A].' "$(blk A "printf '3\n'")"
expect 1 '^\[A\] NOEXP' "a block without expected fails — nothing was compared" -- "$D/r.md"

fixture '값은 3이다 [A].' "$(blk A "printf '3\n'" '')"
expect 1 '^\[A\] NOEXP' "an empty expected fails the same way" -- "$D/r.md"

fixture '값은 3이다 [A].' $'#### [A] no code\n\n```expected\n3\n```\n'
expect 1 '^\[A\] NOSH' "a block heading without a sh fence fails" -- "$D/r.md"

fixture '값은 3이다 [A], 4는 [B].' "$(blk A "printf '3\n'" '3')"
expect 1 'UNDEFINED.*\[B\]' "a cited ID no block defines fails" -- "$D/r.md"

fixture '값은 3이다 [A].' "$(blk A "printf '3\n'" '3'; blk B "printf '4\n'" '4')"
expect 1 'UNUSED.*\[B\]' "a defined block the result never cites fails" -- "$D/r.md"

fixture '값은 3이다 [A].' "$(blk ENV 'X=3'; blk A 'printf "$X\n"' '3')"
expect 0 '^\[A\] PASS' "ENV is neither cited nor counted as unused" -- "$D/r.md"

fixture '[A]' "$(blk A "echo origin/develop" 'origin/develop')"
expect 1 'UNPINNED.*\[A\].*origin/' "a block that names origin/... fails even when its output matches" -- "$D/r.md"

fixture '[A]' "$(blk A "echo HEAD" 'HEAD')"
expect 1 'UNPINNED.*\[A\].*HEAD' "a block that names bare HEAD fails" -- "$D/r.md"

fixture '[A]' "$(blk A "echo HEADER" 'HEADER')"
expect 0 '^\[A\] PASS' "HEAD inside another word is not a ref" -- "$D/r.md"

fixture '[A]' "$(printf 'The pin replaces origin/develop as of HEAD today.\n\n'; blk A "echo 0acb2f08" '0acb2f08')"
expect 0 '^\[A\] PASS' "prose outside the sh fence may mention a moving ref" -- "$D/r.md"

fixture '값은 3이다 [N 1].' "$(blk A "printf '3\n'" '3')"
expect 1 'UNPARSED.*\[N 1\]' "a tag the grammar cannot read fails instead of being skipped" -- "$D/r.md"

fixture '[A] 커밋 [CBRD-27247]와 [CUBRIDQA-xxxx]는 이슈 키다.' "$(blk A "printf '3\n'" '3')"
expect 0 '^\[A\] PASS' "a Jira key in prose is not a tag" -- "$D/r.md"

fixture $'[A] 정규식 `[A-Z]`와\n```\n[N 1]\n```\n안의 것은 태그가 아니다.' "$(blk A "printf '3\n'" '3')"
expect 0 '^\[A\] PASS' "brackets inside code spans and fences are not tags" -- "$D/r.md"

fixture '[A] 규칙은 [AGENTS.md](../AGENTS.md)와 [Rulebook shape](../issues/04.md)에 있다.' "$(blk A "printf '3\n'" '3')"
expect 0 '^\[A\] PASS' "a markdown link label is not a tag" -- "$D/r.md"

# A counter file makes the first run print 1 and the second 2: without --twice the block passes.
COUNTER='n=$(( $(cat cnt 2>/dev/null || echo 0) + 1 )); echo $n > cnt; echo $n'
fixture '[A]' "$(blk A "$COUNTER" '1')"
expect 0 '^\[A\] PASS' "one run of a stateful block passes" -- "$D/r.md"
rm -f "$D/cnt"
expect 1 '^\[A\] NONDET' "--twice fails a block whose second run differs" -- "$D/r.md" --twice

fixture '[A]' "$(blk ENV 'X=7; W=$(mktemp -d); mkdir "$W/sub"; cd "$W/sub"'; blk A 'echo "$X ${PWD##*/}"' '7 sub')"
expect 0 '^\[A\] PASS' "a block sees ENV's variables and runs where ENV ended" -- "$D/r.md"

fixture '[A]' "$(blk A 'ls r.repro.md' 'r.repro.md')"
expect 0 '^\[A\] PASS' "without ENV a block runs in the repro file's directory" -- "$D/r.md"

fixture '[A]' "$(blk A 'echo "$X"' '7'; blk ENV 'X=7')"
expect 0 '^\[A\] PASS' "ENV runs first even when it is not the first block" -- "$D/r.md"

fixture '[A]' "$(blk ENV 'false'; blk A 'echo 1' '1')"
expect 1 '^\[ENV\] FAIL' "an ENV that fails stops the run as a failure" -- "$D/r.md"

fixture '[A] [B]' "$(blk A 'echo 1' '1'; blk B 'echo 2' '2')"
expect 1 '^\[B\] SKIP' "running a subset of IDs skips the rest and never exits 0" -- "$D/r.md" A

fixture '[A]' "$(blk A 'echo 1' '1')"
rm "$D/r.repro.md"
expect 2 'repro' "a result without its repro file is a usage error" -- "$D/r.md"
expect 2 '' "no arguments is a usage error" --

if [ "$T_FAIL" -eq 0 ]; then
  printf 'research-recheck: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'research-recheck: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
