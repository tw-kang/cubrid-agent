---
name: cubrid-test-fail-reasoning
description: "Diagnose a batch of CUBRID regression test failures (shell, sql, isolation, jdbc, cci, ha-shell, ha_repl, cdc_repl, unittest) over a given commit range and produce a single report.md table of suspect commits + answer-fix vs bug-report verdicts. Invoke whenever the user supplies (or asks for) a CUBRID test failure analysis with a fail list + branch + commit range — Korean: 실패 분석, 실패 원인 추측, 회귀 원인, 11.x 실패 리포트, 실패 TC bisect, 답지 수정인지 버그인지; English: 'analyze failing CUBRID tests', 'bisect regression', 'fail reason report'. The skill HARD-GATES on three required inputs (fail list path, branch, commit range): if any is missing it refuses with a precise message and stops. Tests are dispatched to the matching `cubrid-*-tc-runone` skill at /home/dev/skills/, build is produced in the configured CI build pod (or via an HTTP tarball URL once that's wired), and reasoning is automated via diff-token extraction + `git log -G` over the range; the LLM only steps in when an automated suspect cannot be found."
---

# CUBRID Test Failure Reasoning

End-to-end pipeline that takes a fail list + branch + commit range, runs the failing testcases, identifies the introducing commit per failure, and writes a single tabulated `report.md`.

## Required inputs (HARD GATE — refuse without all three)

This skill REFUSES to run if any of the following is missing or unparseable:

1. **Failure list path** — a file (typically `fail.txt`) where each failure starts with a TC path line such as `shell/_06_issues/.../foo.sh`, `sql/_xx_yy/foo`, etc.
2. **Branch** — git branch name (e.g. `release/11.3`, `develop`).
3. **Commit range** — `<good_sha>..<bad_sha>` (the bisect window, narrower is faster).

Always run the validator FIRST and abort on non-zero:

```bash
python3 scripts/validate_inputs.py \
  --fail-list "$FAIL_LIST" \
  --branch "$BRANCH" \
  --commit-range "$COMMIT_RANGE"
```

If the script exits non-zero, **print its error verbatim and stop**. Do NOT attempt to guess defaults — refusal is the correct behavior; that's how the user knows what to provide.

## Workflow

Run from the repo root that contains your CUBRID source checkout.

```bash
cd /home/dev/cubrid                                    # CUBRID source root
WORKDIR=$(mktemp -d -t cubrid-fail-reason-XXXX)        # ephemeral run dir
SKILL=/home/dev/skills/cubrid-test-fail-reasoning

# 1) Hard gate
python3 $SKILL/scripts/validate_inputs.py \
  --fail-list "$FAIL_LIST" --branch "$BRANCH" --commit-range "$COMMIT_RANGE"

# 2) Ensure a build is available at /home/dev/CUBRID
python3 $SKILL/scripts/build_cubrid.py \
  --branch "$BRANCH" --commit "${COMMIT_RANGE##*..}" --target /home/dev/CUBRID

# 3) Parse the fail list into structured failures.json
python3 $SKILL/scripts/parse_fail_list.py "$FAIL_LIST" > $WORKDIR/failures.json

# 4) Run each failing TC; capture pass/fail and structured diff
python3 $SKILL/scripts/run_tc.py --failures $WORKDIR/failures.json --out $WORKDIR/runs.json

# 5) Auto-bisect each failure to a suspect commit and emit the report
python3 $SKILL/scripts/generate_report.py \
  --runs $WORKDIR/runs.json \
  --branch "$BRANCH" \
  --commit-range "$COMMIT_RANGE" \
  --out report.md
```

Final artifact: `./report.md` — single markdown table, one row per failing TC.

## Build backend (pluggable)

`scripts/build_cubrid.py` chooses the backend by environment variable so that the deployed skill works both today (kubectl pod) and tomorrow (HTTP URL):

| `CUBRID_BUILD_BACKEND` | Required env | Behavior |
| --- | --- | --- |
| `pod` (default) | `CUBRID_BUILD_POD` (default `cubridci-build-5d85b4566c-g4twr`) | `kubectl exec` into the build pod, sync source + submodules, build with devtoolset-8 + ninja, `tar czf`, `kubectl cp` to local, extract to `--target`. |
| `url` | `CUBRID_BUILD_URL` (https URL of `CUBRID.tar.gz`) | Download via `urllib`, extract to `--target`. |

The script is idempotent — if `<target>/bin/cubrid_rel` already reports a version string whose short SHA matches the requested commit, it skips the build. Pass `--force` to override.

## Test runner routing

Each row in `failures.json` carries `runone_skill` selected by the leading directory of the TC path. The names mirror the existing skills under `/home/dev/skills/`:

| TC path prefix | Routes to | Script handler |
| --- | --- | --- |
| `shell/` | `cubrid-shell-tc-runone` | shell |
| `ha_shell/` or `ha-shell/` | `cubrid-ha-shell-tc-runone` | shell |
| `ha_repl/` | `cubrid-ha_repl-tc-runone` | shell |
| `cdc_repl/` | `cubrid-cdc_repl-tc-runone` | shell |
| `isolation/` | `cubrid-isolation-tc-runone` | shell |
| `sql/` | `cubrid-sql-tc-runone` | csql-driven |
| `jdbc/` | `cubrid-jdbc-tc-runone` | sub-skill |
| `cci/` | `cubrid-cci-tc-runone` | sub-skill |
| `unittest/` | `cubrid-unittest-tc-runone` | sub-skill |

`run_tc.py` natively executes shell-style TCs (`.sh`) by replicating the relevant runone steps in code (source `~/.cubrid.sh`, set `CTP_HOME` + `init_path`, clean stale CUBRID processes, `cd cases/`, `timeout 300 sh <tc>`, parse `<tc>.result`). For non-shell TCs, the script emits `status=DELEGATE` and the matching runone skill must be invoked by the calling agent — read the relevant skill at `/home/dev/skills/cubrid-<category>-tc-runone/SKILL.md` only when this happens.

## Reasoning method (automated)

For each `NOK` TC, `generate_report.py`:

1. Extracts the **smallest unique token** from the actual-vs-expected diff. Heuristics in priority order:
   - format suffixes attached to `sql hash text` (e.g. `;bind_var_cnt=N`, `;remote={...}`)
   - new key-value pairs that appear only on the actual side (`?193="..."`)
   - numeric byte deltas in `QM_QUERY_*` lines (categorized as "byte counter shift" — points to plan cache hash text or storage size changes)
   - sha1 / XASL_ID changes (downstream of hash text — never the root token; the script intentionally skips them and instead bisects the upstream hash text token of any sibling failure in the same group)
2. Runs `git log --oneline <range> -G '<token>' -- src/` to find the introducing commit. Limits to `src/parser`, `src/query`, `src/optimizer` first; widens to all `src/` if no hit.
3. Groups failures whose tokens collide → emits one common root-cause line per group, then per-row entry for traceability.
4. Triages the verdict:
   - format / identifier / cache-key / hash text / sha1 / byte counter shifts → **answer-fix** (intentional output evolution; update test answer files)
   - crashes, wrong query results, lock/deadlock changes, performance regressions → **bug-report** (raise a JIRA, link the suspect commit)

When automatic bisect returns no commit (token too generic, or root cause is in a non-`src/` file), the row is marked `action=investigate` with the diff snippet preserved so the orchestrating agent can step in for manual reasoning.

## Report shape

`report.md` columns (in order):

```
| # | Test Case | Category | Symptom | Diff token | Suspect commit | Verdict | Notes |
```

Plus a header section with branch, commit range, total count, and a "Root-cause groups" subsection that collapses TCs sharing a token into one diagnosis line. Keep all tables in a single file so reviewers can ack everything in one scroll.

## Failure modes the gate prevents

- User passes only the fail list → refused: "missing branch, commit-range".
- User passes a commit range without `..` → refused: "commit-range must be 'good..bad'".
- Fail list path doesn't exist → refused before any kubectl call.
- Pod backend selected but no `kubectl` available → script aborts before touching network.

These checks live in `scripts/validate_inputs.py` and `scripts/build_cubrid.py`.

## When NOT to use this skill

- A single TC failure with a known cause → use `cubrid-<category>-tc-runone` directly.
- No commit range provided and the user does not want to provide one → respond that the input is required; do not use this skill.
- Build pipeline questions, environment setup, packaging — out of scope.

## References

- `references/fail_list_format.md` — exact format of fail.txt and what each column means
- `references/reasoning_steps.md` — long-form explanation of the bisect-by-token heuristic, with worked examples
- `references/pod_build.md` — how the build backend works, env knobs, and how to swap to URL-based delivery later
