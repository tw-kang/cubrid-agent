---
name: cubrid-sql-tc-create
description: "Create, draft, or scaffold a new CUBRID CTP SQL testcase (.sql + .answer) from scratch — for a CBRD bug fix or feature. Use this whenever someone says \"sql tc 만들어줘\", \"sql tc 초안 작성해줘\", \"create sql tc\", \"draft sql test\", \"새 sql testcase\", \"sql 테스트케이스 작성\", or \"create draft sql tc for CBRD-XXXXX\", even if they don't say the word \"testcase\". They usually give a CBRD number, the behavior to test, and sometimes a target release dir. NOT for: running existing SQL tests, reviewing diffs/PRs, CTP configuration, or SQL scripting unrelated to CTP test creation."
---

# SQL Testcase Creator (CTP)

Generate a CUBRID CTP SQL testcase that passes review on the first try. A good testcase is a self-contained `.sql` (setup → scenarios → cleanup) plus a matching `.answer` that CTP diffs to decide pass/fail — and the `.answer` is **generated**, never hand-written.

## Scope

**Produces:** the `.sql` file (owns its own setup and cleanup), an optional empty `.queryPlan` sidecar for optimizer tests, and correct directory paths under `cases/` + `answers/`.

**Does NOT produce:** the `.answer` file (CTP generates it by running the `.sql` — see Lifecycle contract), CTP framework changes, CI config, or shell/JDBC/CCI/HA tests (route those to the matching `cubrid-*-tc-create` skill).

## Before you start

- **CTP must be installed.** Expect it at `$CTP_HOME`, `~/CTP`, or `~/cubrid-testtools/CTP`. Sanity check: `ls $CTP_HOME/bin/ctp.sh`. If absent, stop and tell the user to install it (`git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`).
- **Testcase repo.** Resolve its root without a hardcoded home path: use `$CUBRID_TESTCASES` if set, else discover the `cubrid-testcases` checkout from the current dir (`git rev-parse --show-toplevel` or search upward), else ask the user. Call it `$TC` below.
- **JIRA context (optional).** If a `CBRD-XXXXX` is referenced, run `cubrid-jira search CBRD-XXXXX` first to ground the work (reuse if already fetched). If the CLI isn't installed, skip — but installing cubrid-jira improves accuracy.

## Directory convention

The path is how CTP locates and categorizes a test. The `.sql` and its `.answer` share basename, split across sibling `cases/` and `answers/` dirs.

```
# Bug fix:  $TC/sql/_13_issues/_{yy}_{1|2}h/cases/cbrd_XXXXX.sql
#                                            answers/cbrd_XXXXX.answer
# Feature:  $TC/sql/_{no}_{release_code}/{feature_group}/cases/cbrd_XXXXX.sql
#                                                        answers/cbrd_XXXXX.answer
# Medium:   $TC/medium/...
```

`{yy}` = 2-digit year, `{1|2}h` = first/second half of year. Multiple tests for one issue get a suffix (`cbrd_27100_select.sql`, `cbrd_27100_update.sql`). All SQL files share one `cases/`+`answers/` pair — never make per-test subdirectories.

## Lifecycle contract

The `.answer` is the expected output and **must come from CTP**, not your keyboard — hand-written answers drift from real engine output and fail diffs.

1. Write the `.sql` into `cases/`.
2. Run it through CTP via the `cubrid-sql-tc-verify` skill (needs a build URL — use one given, else ask). This produces a `.result` next to the `.sql`.
3. Promote it: `cp cases/cbrd_XXXXX.result answers/cbrd_XXXXX.answer`.
4. Read the `.answer` and confirm it matches intent — DDL/DML show affected row count; SELECT shows headers + rows; errors show `Error:-NNN\n<message>`; each statement's output is split by `===...===` lines.

No build URL / no CUBRID env? Drop an empty `.answer` and tell the user to fill it later with `cubrid-sql-tc-verify`.

## Essential helpers (use these, not raw SQL prose)

These directives are how CTP and reviewers read your intent. Skipping them changes what gets compared.

| Use | For | Why |
|---|---|---|
| `evaluate 'Case N: ...'` | label each scenario | sole section marker CTP echoes into the answer; number sequentially |
| `--+ server-message on` / `off` | negative tests asserting `-NNN` errors | makes error text part of the diff; always pair on/off |
| `DROP TABLE IF EXISTS t` before `CREATE` | every table | keeps the test re-runnable |
| empty `cbrd_XXXXX.queryPlan` sidecar | optimizer/plan tests | tells CTP to capture and diff the query plan |
| `cubrid-sql-tc-verify` | generating `.answer` | only sanctioned source of expected output |

## Writing rules

- **`evaluate 'Case N: description'`** before each scenario; this is the *only* section marker — do not add `-- === ...` style comment banners.
- **Pair `server-message on/off`.** Enable only when asserting error messages; skip when checking result sets.
- **`DROP TABLE IF EXISTS` before every `CREATE TABLE`**, setup at top, cleanup at bottom. Keep setup minimal with simple names (`tbl1`, `col1`).
- **Simple, distinct data values** so answer diffs read cleanly; explicit column lists in `INSERT` when it aids readability.
- **3–10 `evaluate` sections** per file is typical; one `evaluate` label per error case.
- **No hardcoded paths.** SQL stays path-free; if a step needs scratch space use `work=$(mktemp -d)` or cwd, never `/tmp`/`/home`.

## House idioms (quick recipes)

These match what the corpus and reviewers expect. See `@examples/` for full files.

- **Header block** — start every file with `/** This test case verifies CBRD-XXXXX: <title> */` followed by a numbered `Coverage:` list.
- **Query-plan test** — drop an empty `cbrd_XXXXX.queryPlan` beside the `.sql`; CTP then captures the optimizer plan into the answer.
- **Parameter change (rare)** — `SET SYSTEM PARAMETERS 'k=v';` then restore the original value at the end of the test.
- **`holdcas` (rare)** — wrap transaction-sensitive scenarios in `--+ holdcas on;` … `--+ holdcas off;`.

## Verify before claiming done

After authoring, prove the testcase actually runs — don't just eyeball it.

1. **Run it (ground truth):** push the `.sql` through `cubrid-sql-tc-verify` with a real build, generate the `.result`, promote it to `.answer`, and confirm the answer reflects intended behavior (right error codes, right row counts).
2. **No-build fallback** (a clean, expected path): leave the `.answer` empty and hand off to the user with `cubrid-sql-tc-verify` instructions.

## Self-review checklist

- Header block present with CBRD number and `Coverage:`?
- `evaluate 'Case N: ...'` on every scenario, numbered, no `-- ===` banners?
- `DROP TABLE IF EXISTS` before each `CREATE TABLE`? Cleanup at bottom?
- `server-message on/off` paired (only for error tests)?
- `.queryPlan` sidecar present for optimizer tests?
- `.answer` generated via `cubrid-sql-tc-verify` (not hand-written), or left empty with a handoff note?
- Dir/basename correct? Right `_{yy}_{1|2}h` bucket, shared `cases/`+`answers/`?

## Examples & references

- `@examples/bug_fix_error_cases.sql` — negative test with `server-message on/off`.
- `@examples/bug_fix_select.sql` — basic SELECT result verification.
- `@examples/feature_query_plan.sql` — optimizer test with a `.queryPlan` sidecar.
- Test guide: `sql_guide.md` — https://github.com/CUBRID/cubrid-testtools/blob/develop/doc/sql_guide.md (or `$CTP_HOME/../doc/sql_guide.md` if CTP is checked out locally).
