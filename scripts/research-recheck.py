#!/usr/bin/env python3
"""Re-run the repro blocks of a research result and compare their output.

Dev-only (outside SHIPPED_PATHS). A research ticket is resolved only when this exits 0 for its
result file; a session that re-counts by hand, or with a checker written for the occasion, has
passed wrong numbers before.

usage: research-recheck.py <result.md> [--twice] [ID ...]

Layout: the result file `<name>.md` cites its numbers as `[ID]` tags; the blocks live beside it in
`<name>.repro.md` as

    #### [ID] free title
    ```sh
    commands
    ```
    ```expected
    exact stdout
    ```
    ```independent
    commands that reach the same number without the research script
    ```

The `independent` fence is optional per block. Every line it prints must be a line of the expected, so
it may confirm one number of a longer block. At least five blocks (every block, when there are fewer)
must carry one: a research script that is consistently wrong passes its own expected, and only a
second path to the number catches it.

`[ENV]` runs first wherever it sits, and alone: the variables it defines and the directory it ends
in are the environment of every other block. Without it, blocks run in the repro file's directory.

Exit 1 when any of these holds; 2 on a usage error:
  - a block has no expected, an empty expected, or output that differs from it
  - an independent fence prints nothing, or a line that is not a line of its block's expected, or
    repeats its block's sh fence
  - fewer blocks carry an independent fence than the floor above
  - the result cites an ID no block defines, or a block is never cited
  - a block reads a moving ref (`origin/...`, bare `HEAD`) in its sh or independent fence
  - the result has a tag the grammar cannot parse (`[` + uppercase + ... `]` that is not `[ID]`)
  - with --twice, a block's two runs differ
  - IDs were given, so blocks were skipped: a partial run never passes
"""
import os
import re
import subprocess
import sys

BLOCK_RE = re.compile(r'^#### \[([A-Z][A-Z0-9]*)\][^\n]*\n(.*?)(?=^#### \[|\Z)', re.M | re.S)
SH_RE = re.compile(r'```sh\n(.*?)```', re.S)
EXPECTED_RE = re.compile(r'```expected\n(.*?)```', re.S)
INDEPENDENT_RE = re.compile(r'```independent\n(.*?)```', re.S)
SHOW_CHARS = 3000
INDEPENDENT_NEEDED = 5


def say(line):
    print(line, flush=True)


def parse_blocks(text):
    out = []
    for bid, body in BLOCK_RE.findall(text):
        sh = SH_RE.search(body)
        exp = EXPECTED_RE.search(body)
        ind = INDEPENDENT_RE.search(body)
        out.append((bid, sh.group(1) if sh else None, exp.group(1).rstrip('\n') if exp else None,
                    ind.group(1) if ind else None))
    return out


TAG_RE = re.compile(r'\[([A-Z][^\]\n]*)\]')
ID_RE = re.compile(r'[A-Z][A-Z0-9]*$')
JIRA_KEY_RE = re.compile(r'[A-Z]+-[0-9x]+$')
MOVING_REF_RE = re.compile(r'origin/|\bHEAD\b')


def scan_tags(result):
    """-> (cited IDs, unparsed tags). Tags live in prose: a `[A-Z]` inside a code span or fence is a
    regex, `[Text](url)` is a link, and `[CBRD-1234]` is an issue key quoted from a commit subject."""
    prose = re.sub(r'```.*?```', '', result, flags=re.S)
    prose = re.sub(r'`[^`\n]*`', '', prose)
    prose = re.sub(r'\[[^\]\n]*\]\([^)\n]*\)', '', prose)
    cited, unparsed = set(), []
    for tag in TAG_RE.findall(prose):
        if ID_RE.match(tag):
            cited.add(tag)
        elif not JIRA_KEY_RE.match(tag) and tag not in unparsed:
            unparsed.append(tag)
    return cited, unparsed


def run_env(code, cwd):
    # Capture only what ENV created, plus where it ended: `declare -p` of everything re-sources
    # read-only shell variables and fails.
    script = (
        '__pre=$(compgen -v)\n' + code + '\n'
        'printf "\\n__RECHECK_ENV__\\n"\n'
        'declare -p $(LC_ALL=C comm -13 <(printf "%s\\n" "$__pre" | LC_ALL=C sort) <(compgen -v | LC_ALL=C sort) | grep -v "^__") 2>/dev/null\n'
        'printf "__RECHECK_PWD__%s\\n" "$PWD"\n'
    )
    r = subprocess.run(['bash', '-ec', script], capture_output=True, text=True, cwd=cwd)
    if r.returncode or '__RECHECK_ENV__' not in r.stdout:
        return None, None, r
    _, _, tail = r.stdout.partition('__RECHECK_ENV__\n')
    decls, _, pwd = tail.rpartition('__RECHECK_PWD__')
    return decls, pwd.strip(), r


def run_block(code, decls, cwd):
    r = subprocess.run(['bash', '-c', decls + '\n' + code], capture_output=True, text=True, cwd=cwd)
    return r.stdout.rstrip('\n'), r.stderr.strip()


def confirms(ind_out, exp):
    return bool(ind_out) and set(ind_out.splitlines()) <= set(exp.splitlines())


def main(argv):
    twice = '--twice' in argv
    args = [a for a in argv if a != '--twice']
    if not args:
        say(__doc__.strip())
        return 2
    result_path, only = args[0], set(args[1:])
    repro_path = re.sub(r'\.md$', '', result_path) + '.repro.md'
    if not os.path.isfile(result_path):
        say(f'no such result file: {result_path}')
        return 2
    if not os.path.isfile(repro_path):
        say(f'no repro file beside the result: {repro_path}')
        return 2
    repro = open(repro_path, encoding='utf-8').read()
    result = open(result_path, encoding='utf-8').read()
    blocks = sorted(parse_blocks(repro), key=lambda b: b[0] != 'ENV')
    cwd = os.path.dirname(os.path.abspath(repro_path))

    defined = {bid for bid, _, _, _ in blocks}
    cited, unparsed = scan_tags(result)
    undefined = sorted(cited - defined)
    unused = sorted(defined - cited - {'ENV'})
    unpinned = [(bid, m.group(0)) for bid, code, _, ind in blocks
                if (m := MOVING_REF_RE.search(f'{code or ""}\n{ind or ""}'))]
    independent = list(dict.fromkeys(bid for bid, _, _, ind in blocks if bid != 'ENV' and ind))
    copied = [bid for bid, code, _, ind in blocks if ind and code and ind.split() == code.split()]
    needed = min(INDEPENDENT_NEEDED, len(defined - {'ENV'}))
    too_few = len(independent) < needed
    tags = ' '.join(f'[{i}]' for i in independent) or 'none'
    say(f'{"TOO FEW INDEPENDENT" if too_few else "INDEPENDENT"}: {tags} ({len(independent)} of {needed} needed)')
    if copied: say('COPIED SH INTO INDEPENDENT: ' + ' '.join(f'[{i}]' for i in copied))
    if undefined: say('UNDEFINED IDS: ' + ' '.join(f'[{i}]' for i in undefined))
    if unused: say('UNUSED BLOCKS: ' + ' '.join(f'[{i}]' for i in unused))
    if unparsed: say('UNPARSED TAGS: ' + ' '.join(f'[{t}]' for t in unparsed))
    for bid, ref in unpinned: say(f'UNPINNED REF: [{bid}] reads {ref}')

    decls = ''
    stats = {'pass': 0, 'fail': 0, 'noexp': 0, 'nondet': 0, 'skip': 0}
    for bid, code, exp, ind in blocks:
        if bid == 'ENV':
            if code is None:
                say('[ENV] NOSH'); stats['fail'] += 1
                continue
            decls, cwd, r = run_env(code, cwd)
            if decls is None:
                say('[ENV] FAIL'); stats['fail'] += 1
                say('--- stdout:\n' + r.stdout[-SHOW_CHARS:])
                if r.stderr.strip(): say('--- stderr:\n' + r.stderr.strip()[-SHOW_CHARS:])
                break
            say('[ENV] OK')
            continue
        if only and bid not in only:
            say(f'[{bid}] SKIP'); stats['skip'] += 1
            continue
        if code is None:
            say(f'[{bid}] NOSH'); stats['fail'] += 1
            continue
        runs = [run_block(code, decls, cwd) for _ in range(2 if twice else 1)]
        out, err = runs[0]
        second_out = runs[1][0] if twice else out
        ind_out, ind_err = run_block(ind, decls, cwd) if ind else (None, '')
        if second_out != out:
            status = 'NONDET'
        elif not exp:
            status = 'NOEXP'
        elif out == exp and (ind_out is None or confirms(ind_out, exp)):
            status = 'PASS'
        else:
            status = 'FAIL'
        stats[status.lower()] += 1
        say(f'[{bid}] {status}')
        if status != 'PASS':
            say('--- got:\n' + out[:SHOW_CHARS])
            if err: say('--- stderr:\n' + err[:SHOW_CHARS])
            if ind_out is not None: say('--- independent got:\n' + ind_out[:SHOW_CHARS])
            if ind_err: say('--- independent stderr:\n' + ind_err[:SHOW_CHARS])
            if exp: say('--- expected:\n' + exp[:SHOW_CHARS])
            if status == 'NONDET': say('--- second run:\n' + second_out[:SHOW_CHARS])

    static = len(undefined) + len(unused) + len(unparsed) + len(unpinned) + len(copied) + too_few
    bad = stats['fail'] + stats['noexp'] + stats['nondet'] + stats['skip'] + static
    say('SUMMARY blocks {}: pass {pass} fail {fail} noexp {noexp} nondet {nondet} skip {skip}'
        .format(len(blocks), **stats)
        + f' | undefined {len(undefined)} unused {len(unused)} unparsed {len(unparsed)}'
        + f' unpinned {len(unpinned)} independent {len(independent)}/{needed} -> exit {1 if bad else 0}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
