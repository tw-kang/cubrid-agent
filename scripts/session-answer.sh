#!/bin/bash
# session-answer.sh — when the user said it: the time of a user's message or AskUserQuestion answer.
#
#   session-answer.sh <session name> <phrase>
#
# Dev-only. Reads every ~/.claude/projects/*/*.jsonl whose custom-title line is <session name> (the
# title /rename gives) and prints each user line that holds <phrase>, the earliest first:
#   <timestamp>  <user|answer>  [<log file>  ]<excerpt>
# The log file column shows only when more than one log has the title.
# Exit 0 = printed. 1 = no line holds the phrase. 2 = bad input or no log has the title.
set -u

[ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] \
  || { echo "usage: session-answer.sh <session name> <phrase>" >&2; exit 2; }

exec python3 -I - "$@" <<'PY'
import glob, json, os, sys

name, phrase = sys.argv[1], sys.argv[2]
root = os.path.expanduser('~/.claude/projects')
# How text the user did not type opens on a user line the harness leaves unflagged; the text of a flagged
# line (isMeta: reminders, skill bodies, most session messages) is never taken as typed. The title match
# keeps out logs that only quote the session; this keeps out lines that only quote the user.
NOT_TYPED = ('Another Claude session sent a message', '<task-notification', '<bash-stdout',
             '<local-command-stdout')

def records(lines):
    for line in lines:
        try:
            yield json.loads(line)
        except ValueError:
            continue

def titled(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        # Only title lines are parsed: the logs run to tens of MB each.
        return any(o.get('type') == 'custom-title' and o.get('customTitle') == name
                   for o in records(l for l in fh if 'custom-title' in l))

def content(o):
    return (o.get('message') or {}).get('content')

def blocks(c):
    return c if isinstance(c, list) else []

def texts(c):
    return [c] if isinstance(c, str) else [b.get('text', '') for b in blocks(c) if b.get('type') == 'text']

logs = sorted(p for p in glob.glob(os.path.join(root, '*', '*.jsonl')) if titled(p))
if not logs:
    print(f'session-answer: no log under {root} has the title {name!r} (a session gets one from /rename)',
          file=sys.stderr)
    sys.exit(2)

hits = []
for path in logs:
    with open(path, encoding='utf-8', errors='replace') as fh:
        recs = list(records(fh))
    asks = {b.get('id') for o in recs if o.get('type') == 'assistant' for b in blocks(content(o))
            if b.get('type') == 'tool_use' and b.get('name') == 'AskUserQuestion'}
    for o in recs:
        if o.get('type') != 'user':
            continue
        found = [('answer', t) for b in blocks(content(o))
                 if b.get('type') == 'tool_result' and b.get('tool_use_id') in asks
                 for t in texts(b.get('content'))]
        if not (o.get('isMeta') or o.get('isCompactSummary')):
            found += [('user', t) for t in texts(content(o)) if not t.startswith(NOT_TYPED)]
        for kind, t in found:
            i = t.find(phrase)
            if i >= 0:
                excerpt = ' '.join(t[max(0, i - 60):i + len(phrase) + 60].split())
                hits.append((o.get('timestamp', ''), kind, os.path.basename(path), excerpt))

if not hits:
    print(f'session-answer: no user line in {", ".join(logs)} holds {phrase!r}', file=sys.stderr)
    sys.exit(1)
for ts, kind, log, excerpt in sorted(hits, key=lambda h: h[0]):
    print('  '.join([ts, kind] + ([log] if len(logs) > 1 else []) + [excerpt]))
PY
