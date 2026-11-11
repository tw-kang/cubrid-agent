#!/bin/bash
# resolve-ticket.sh — close a local tracker ticket (docs/agents/issue-tracker.md, Resolve 2).
#
#   resolve-ticket.sh <ticket file> <session name>
#
# Dev-only. Refuses while
#   - a line of the last round starts with `- [ ]`: the last round runs from the last `## 재오픈` heading
#     on, or is the whole file; a quoted `> - [ ]` does not count,
#   - no line but a heading in the last `## Answer` section names /code-review, or
#   - a `## 재오픈` section comes after the last Answer.
# Otherwise writes `resolved (<session name>, <date>)` into the Status line, keeping a chain behind
# ` · 이전: ` when the value holds 재오픈, and prints that line.
# Exit 0 = resolved. 1 = refused, each reason listed. 2 = bad input or no Status line.
set -u

[ $# -eq 2 ] && [ -n "$2" ] || { echo "usage: resolve-ticket.sh <ticket file> <session name>" >&2; exit 2; }
[ -f "$1" ] || { echo "resolve-ticket: no ticket file $1" >&2; exit 2; }

exec python3 -I - "$@" "$(date '+%Y-%m-%d %H:%M')" <<'PY'
import os, re, sys

path, session, now = sys.argv[1:4]
lines = open(path, encoding='utf-8').read().split('\n')
status = next(((i, m[1], m[2]) for i, l in enumerate(lines)
               if (m := re.match(r'(\*\*Status:\*\* |Status: )(.*)', l))), None)
if not status:
    print(f'resolve-ticket: {path} has no "Status:" or "**Status:**" line', file=sys.stderr)
    sys.exit(2)

heads = [i for i, l in enumerate(lines) if l.startswith('## ')]
answers = [i for i in heads if lines[i].startswith('## Answer')]
reopens = [i for i in heads if lines[i].startswith('## 재오픈')]
start = reopens[-1] if reopens else 0
problems = [f'{i}: {l}' for i, l in enumerate(lines[start:], start + 1) if re.match(r'- \[ \]', l)]
if not answers:
    problems.append('no "## Answer" section')
elif reopens and reopens[-1] > answers[-1]:
    problems.append(f'{reopens[-1] + 1}: {lines[reopens[-1]]} — no Answer after it')
else:
    a = answers[-1]
    end = next((i for i in heads if i > a), len(lines))
    if not any('/code-review' in l and not l.startswith('#') for l in lines[a + 1:end]):
        problems.append(f'{a + 1}: {lines[a]} — names no /code-review run')
if problems:
    print('refused: ' + path, *problems, sep='\n  ')
    sys.exit(1)

i, head, value = status
lines[i] = f'{head}resolved ({session}, {now})' + (f' · 이전: {value}' if '재오픈' in value else '')
# .scratch/ is not in git: a write cut short would lose the ticket.
with open(path + '.tmp', 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(lines))
os.replace(path + '.tmp', path)
print(lines[i])
PY
