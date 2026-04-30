---
name: cubrid-test-fail-reasoning
description: "Diagnose a batch of CUBRID regression test failures (shell, sql, isolation, jdbc, cci, ha_shell, ha_repl, cdc_repl, unittest) over a given commit range and produce a single report.md with suspect commits and answer-fix vs bug-report verdicts. Invoke whenever the user supplies (or asks for) a CUBRID test-failure analysis with a fail list + branch + commit range — Korean: 실패 분석, 실패 원인 추측, 회귀 원인, 11.x 실패 리포트, 실패 TC bisect, 답지 수정인지 버그인지; English: 'analyze failing CUBRID tests', 'bisect regression', 'fail reason report'. Requires all three inputs; refuses precisely if any is missing."
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

## Prerequisites

Set these environment variables before invoking the skill (the scripts refuse with a precise message if any required value is missing):

| Variable | Required for | Meaning |
| --- | --- | --- |
| `CUBRID_SRC` | every run | absolute path to the CUBRID source checkout (workdir for `git log -G`) |
| `CUBRID_INSTALL` | every run | where the built CUBRID will land (default: `./CUBRID`) |
| `CTP_HOME` | shell-style TCs | path to the `cubrid-testtools/CTP` checkout |
| `CUBRID_TC_ROOT` *or* `CUBRID_TC_ROOT_<CATEGORY>` | running TCs | testcase repo root(s); per-category override wins |
| `CUBRID_BUILD_BACKEND` | optional | `pod` (default) or `url` |
| `CUBRID_BUILD_POD` | `backend=pod` | pod name for `kubectl exec`; **no built-in default** |
| `CUBRID_BUILD_URL` | `backend=url` | https URL of a `CUBRID.tar.gz` artifact |

If `CUBRID_BUILD_BACKEND=pod` is selected and `kubectl` is missing on PATH, **halt and ask the user** before installing kubectl — or suggest switching to the portable `url` backend (`CUBRID_BUILD_BACKEND=url` + `CUBRID_BUILD_URL=<https://.../CUBRID.tar.gz>`). Never install kubectl without explicit user consent.

## Workflow

```bash
cd "${CUBRID_SRC:?set CUBRID_SRC to the CUBRID source checkout}"
WORKDIR=$(mktemp -d -t cubrid-fail-reason-XXXX)
SKILL=<this skill's base directory>             # provided when invoked

# 1) Hard gate
python3 "$SKILL/scripts/validate_inputs.py" \
  --fail-list "$FAIL_LIST" --branch "$BRANCH" --commit-range "$COMMIT_RANGE"

# 2) Ensure a build is available at $CUBRID_INSTALL (default: ./CUBRID)
python3 "$SKILL/scripts/build_cubrid.py" \
  --branch "$BRANCH" --commit "${COMMIT_RANGE##*..}" \
  --target "${CUBRID_INSTALL:-$PWD/CUBRID}"

# 3) Parse the fail list into structured failures.json
python3 "$SKILL/scripts/parse_fail_list.py" "$FAIL_LIST" > "$WORKDIR/failures.json"

# 4) Run each failing TC; capture pass/fail and structured diff
python3 "$SKILL/scripts/run_tc.py" --failures "$WORKDIR/failures.json" --out "$WORKDIR/runs.json"

# 5) Auto-bisect each failure to a suspect commit and emit the report
python3 "$SKILL/scripts/generate_report.py" \
  --runs "$WORKDIR/runs.json" \
  --branch "$BRANCH" \
  --commit-range "$COMMIT_RANGE" \
  --out report.md
```

Final artifact: `./report.md` — single markdown table, one row per failing TC.

## Build backend (pluggable)

`scripts/build_cubrid.py` chooses the backend by environment variable. The `url` backend is the portable / deployment-friendly path; `pod` is intended for environments with a CUBRID CI cluster.

| `CUBRID_BUILD_BACKEND` | Required env | Behavior |
| --- | --- | --- |
| `pod` (default) | `CUBRID_BUILD_POD` (no default — must be set) | `kubectl exec` into the build pod, sync source + submodules, build with devtoolset-8 + ninja, `tar czf`, `kubectl cp` to local, extract to `--target`. |
| `url` | `CUBRID_BUILD_URL` (https URL of `CUBRID.tar.gz`) | Download via `urllib`, extract to `--target`. |

The script is idempotent — if `<target>/bin/cubrid_rel` already reports a version string whose short SHA matches the requested commit, it skips the build. Pass `--force` to override.

## Test runner routing

Each row in `failures.json` carries a `runone_skill` selected by the leading directory of the TC path. Skill names are resolved by Claude's `available_skills` registry — the script does NOT rely on a hard-coded skill location.

| TC path prefix | Routes to | Script handler |
| --- | --- | --- |
| `shell/` | `cubrid-shell-tc-runone` | shell |
| `ha_shell/` | `cubrid-ha_shell-tc-runone` | shell |
| `ha_repl/` | `cubrid-ha_repl-tc-runone` | shell |
| `cdc_repl/` | `cubrid-cdc_repl-tc-runone` | shell |
| `isolation/` | `cubrid-isolation-tc-runone` | shell |
| `sql/` | `cubrid-sql-tc-runone` | csql-driven |
| `jdbc/` | `cubrid-jdbc-tc-runone` | sub-skill |
| `cci/` | `cubrid-cci-tc-runone` | sub-skill |
| `unittest/` | `cubrid-unittest-tc-runone` | sub-skill |

`run_tc.py` natively executes shell-style TCs (`.sh`) by replicating the relevant runone steps in code (source `~/.cubrid.sh`, set `CTP_HOME` + `init_path`, clean stale CUBRID processes, `cd cases/`, `timeout 300 sh <tc>`, parse `<tc>.result`). For non-shell TCs, the script emits `status=DELEGATE` and the matching runone skill must be invoked by the calling agent.

## JIRA Issue Context (per-failure enrichment)

For each TC whose path encodes a `cbrd_XXXXX` / `cbrd-XXXXX` / `CBRDXXXXX` token (e.g. `shell/_06_issues/_25_2h/cbrd_27100/cases/cbrd_27100.sh`), **invoke the `jira` skill** to fetch the CBRD-XXXXX issue background — original symptom, expected behavior, affected components, comments — and feed that context into the `answer-fix` vs `bug-report` verdict. Issue intent is the single most reliable signal for distinguishing intentional output evolution (answer-fix) from a true regression (bug-report).

**Already fetched in this conversation?** Reuse the context — do not re-invoke. The fetcher caches issues, but the conversation should not redundantly re-display them.

1. **Locate the `jira` skill** — search project-scope, user-scope, plugin cache, and any `CLAUDE_PLUGIN_ROOT` install path. Do **not** rely on developer-specific paths:

   ```bash
   JIRA_SCRIPT=""
   for d in \
       "$(pwd)/.claude/skills/jira" \
       "$HOME/.claude/skills/jira" \
       "$HOME/.claude/plugins/skills/jira" \
       "$HOME/skills/jira" \
       "${CLAUDE_PLUGIN_ROOT:-}/skills/jira"
   do
       [ -n "$d" ] && [ -f "$d/scripts/jira_search.py" ] && JIRA_SCRIPT="$d/scripts/jira_search.py" && break
   done
   ```

2. **If available** — extract every `cbrd[NNNNN]` token from the TC paths in the fail list (handles `cbrd_NNNNN`, `cbrd-NNNNN`, `CBRDNNNNN`, mixed case), dedupe, normalize to `CBRD-NNNNN`, and fetch each one. Warn when `pandoc` is missing so the caller knows the description/comments will fall back to raw Jira-wiki markup:

   ```bash
   command -v pandoc >/dev/null 2>&1 || \
       echo "WARNING: pandoc not installed — JIRA description/comments will be raw wiki markup (degraded readability)."

   grep -oiE 'cbrd[-_]?[0-9]+' "$FAIL_LIST" \
     | tr '[:lower:]' '[:upper:]' \
     | sed -E 's/^CBRD[-_]?/CBRD-/' \
     | sort -u \
     | while read -r cbrd; do python3 "$JIRA_SCRIPT" "$cbrd"; done
   ```

   The fetcher caches issues so repeats are cheap. Pass the gathered context to the verdict step: a CBRD that says "intentional output format change" supports `answer-fix`; one that says "data corruption" / "crash" / "wrong result" supports `bug-report`.

3. **If missing** — **halt and ask the user**:

   > The `jira` skill is required to enrich each failure's verdict with the issue's stated intent, but it is not installed. May I install it from this repo (`tw-kang/skills`) now?
   > Suggested: `npx skills add tw-kang/skills -s jira -a claude-code`
   >
   > After install, re-run the discovery step above. If the script is still not found, the install path may differ on this system — please report which directory under `~/.claude/` or the plugin cache contains the new `jira/scripts/jira_search.py`.

   Wait for explicit confirmation. If the user declines, proceed without JIRA context and add a `verdict_confidence=low` note for any TC whose verdict was decided without it.

4. **No CBRD-XXXXX in any TC path** — skip this section.

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
   - **Cross-check with JIRA context** (see "JIRA Issue Context (per-failure enrichment)" above): if the CBRD-XXXXX issue describes an intentional behavior change in the suspect commit's release, prefer `answer-fix`; if it describes the failure mode, prefer `bug-report` and reference the issue in the report's `Notes` column.

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
- Pod backend selected but no `kubectl` or no `CUBRID_BUILD_POD` → script aborts with a consent-prompt-friendly message before touching network.

These checks live in `scripts/validate_inputs.py` and `scripts/build_cubrid.py`.

## When NOT to use this skill

- A single TC failure with a known cause → use `cubrid-<category>-tc-runone` directly.
- No commit range provided and the user does not want to provide one → respond that the input is required; do not use this skill.
- Build pipeline questions, environment setup, packaging — out of scope.

## References

- `references/fail_list_format.md` — exact format of fail.txt and what each column means
- `references/reasoning_steps.md` — long-form explanation of the bisect-by-token heuristic, with worked examples
- `references/pod_build.md` — how the build backend works, env knobs, and how to swap to URL-based delivery later
