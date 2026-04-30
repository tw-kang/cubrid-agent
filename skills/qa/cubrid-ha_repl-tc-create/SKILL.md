---
name: cubrid-ha_repl-tc-create
description: "Use this skill whenever the user wants to create, draft, write, or scaffold a new HA replication testcase (.sql) for CUBRID CTP ha_repl module. This is the right skill any time someone needs a new ha_repl test produced from scratch for a CBRD issue — bug fix or new feature. Common requests: \"ha_repl tc 만들어줘\", \"ha replication testcase\", \"ha_repl tc 초안\", \"ha_repl tc 초안 작성해줘\", \"create ha_repl tc\", \"draft ha replication test\", \"새 ha_repl testcase\", \"ha replication 테스트케이스 작성\", \"create draft ha_repl tc for CBRD-XXXXX\". NOT for: running existing ha_repl tests, reviewing diffs/PRs, CTP configuration, or general SQL scripting unrelated to CTP test creation."
---

# HA Replication Testcase Creator (CTP)

Generate well-formed CUBRID CTP HA replication testcase files (`.sql` with `--test:` / `--check:` markers).

## Prerequisites — CTP Installation Check (mandatory first step)

```bash
# Detect CTP_HOME: $CTP_HOME env var → $HOME/CTP → ~/cubrid-testtools/CTP (in order)
if [ -n "$CTP_HOME" ] && [ -f "$CTP_HOME/bin/ctp.sh" ]; then
    echo "CTP found: $CTP_HOME"
elif [ -f "$HOME/CTP/bin/ctp.sh" ]; then
    export CTP_HOME=$HOME/CTP
elif [ -f "$HOME/cubrid-testtools/CTP/bin/ctp.sh" ]; then
    export CTP_HOME=$HOME/cubrid-testtools/CTP
else
    echo "CTP not found"; exit 1
fi
# Verify conf directory exists
ls $CTP_HOME/conf/
```

If `ctp.sh` or `conf/` is not found, stop and display:

> "CTP is not installed. This skill cannot proceed.
> Installation methods:
> - Option 1: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> - Option 2: `git clone https://github.com/CUBRID/cubrid-testtools.git` and use `~/cubrid-testtools/CTP` directly
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

Use the detected `$CTP_HOME` in all subsequent steps.

## JIRA Issue Context (do this when a CBRD-XXXXX is referenced)

When the request includes a `CBRD-XXXXX` ticket, **invoke the `jira` skill first** to fetch the issue background — title, description, reproduction steps, affected components, and comments — before generating the testcase. This grounds the test in the issue's actual requirements rather than guesswork.

1. **Check that the `jira` skill is available** — search common install locations for its bundled fetcher script:

   ```bash
   JIRA_SCRIPT=""
   for d in "$(pwd)/.claude/skills/jira" "$HOME/.claude/skills/jira" "$HOME/skills/jira" "/home/dev/skills/jira"; do
       [ -f "$d/scripts/jira_search.py" ] && JIRA_SCRIPT="$d/scripts/jira_search.py" && break
   done
   ```

2. **If available** — invoke the skill (e.g. `/jira CBRD-XXXXX`) or run the bundled script and read the output before proceeding:

   ```bash
   python3 "$JIRA_SCRIPT" CBRD-XXXXX
   ```

   Use the summary, description, and comments to drive the testcase scope, expected behavior, and edge cases.

3. **If missing** — **halt and ask the user**:

   > The `jira` skill is required to fetch CBRD-XXXXX context for accurate testcase generation, but it is not installed. May I install it from this repo (`tw-kang/skills`) now?
   > Suggested: `npx skills add tw-kang/skills -s jira -a claude-code`

   Wait for explicit confirmation. If the user declines, proceed without JIRA context and warn them that issue-specific details may be missing.

4. **No CBRD-XXXXX in the request** — skip this section.

## HA Replication Concepts

HA replication tests verify that data written on the **master** is correctly replicated to the **slave**. `--test:` statements run on master only; `--check:` statements run on both and results are compared. Any discrepancy is a replication failure.

Key invariant: after every `--test: COMMIT;`, subsequent `--check:` queries must return identical result sets on master and slave. The `migrate/Convert.java` transformer auto-adds primary keys to tables that lack them.

## Marker Reference

| Marker | Executed on | Purpose |
|--------|-------------|---------|
| `--test:` | Master only | DML/DDL/COMMIT to drive state changes |
| `--check:` | Master **and** Slave | SELECT (or other read) to verify consistency |

Rules:
- Every `--test:` line contains exactly **one** SQL statement (no semicolons at line end except the statement terminator).
- Every `--check:` line contains exactly **one** SELECT (or equivalent read) statement.
- `--test: COMMIT;` must appear after every batch of DML before the next `--check:` block — the slave only sees committed data.
- Do **not** mix `--test:` and `--check:` on the same statement.

## Directory Path Convention

### Bug fixes

```
ha_repl/_13_issues/_{yy}_{1|2}h/cases/cbrd_XXXXX.sql
```

- `{yy}` = two-digit year (e.g. `26` for 2026)
- `{1|2}h` = first half (Jan–Jun) or second half (Jul–Dec)
- Multiple tests for same issue: append suffix (`cbrd_27100_insert.sql`, `cbrd_27100_ddl.sql`)

### New features

```
ha_repl/_{no}_{release_code}/{feature_group}/cases/cbrd_XXXXX.sql
```

Multiple SQL test files share the same `cases/` directory — do not create per-test subdirectories.

## SQL File Format

```sql
/**
 * This test case verifies CBRD-XXXXX: Brief one-line title
 *
 * Coverage:
 * 1 - Scenario one description
 * 2 - Scenario two description
 */

--test: DROP TABLE IF EXISTS t1;
--test: CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
--test: INSERT INTO t1 VALUES (1, 'hello'), (2, 'world');
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: UPDATE t1 SET val = 'updated' WHERE id = 1;
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: DROP TABLE IF EXISTS t1;
--test: COMMIT;
```

### Header block

Always start with `/** ... */` comment:
- First line: `This test case verifies CBRD-XXXXX: <title>`
- `Coverage:` section listing numbered scenarios

### Setup and cleanup

- `--test: DROP TABLE IF EXISTS tbl;` before every `--test: CREATE TABLE tbl ...;` (re-runnable)
- Always end with `--test: DROP TABLE IF EXISTS tbl;` + `--test: COMMIT;` for cleanup
- Keep setup minimal; use simple names (`t1`, `t2`, `col1`)
- Provide an explicit `PRIMARY KEY` on every table (CTP auto-adds one if missing, but explicit is clearer)

### Commit discipline

Place `--test: COMMIT;` after every logical batch of DML:
- After INSERT / UPDATE / DELETE batches, before `--check:` queries
- After DDL (CREATE / ALTER / DROP) when followed by DML in the same test
- At end of cleanup block

### DDL replication

DDL statements are also replicated. Test with `--test:` and verify schema state with a `--check:` query (e.g. `SELECT COUNT(*) FROM t1`).

## Writing Rules

- Use `--check:` only for **read** statements (SELECT, SHOW, etc.) — never for DML
- Keep `--check:` queries deterministic: use `ORDER BY` on SELECT results
- One statement per `--test:` or `--check:` line
- 3–8 `--check:` verification points per file is typical
- Avoid unrelated SQL complexity — keep test SQL focused on the feature under test
- Prefer simple data values for easy result comparison

## Infrastructure Requirements

Requires a **3-node setup** (controller, master, slave) that cannot be run locally. Config: `$CTP_HOME/conf/ha_repl.conf` (set master/slave SSH host, user, password). Run: `bin/ctp.sh ha_repl -c conf/ha_repl.conf`. Results: `$CTP_HOME/result/ha_repl/current_runtime_logs/`.

> ha_repl testcases do NOT have `.answer` files. Pass/fail is determined by result-set equality between master and slave at each `--check:` point.

## Generation Process — Self-Review Checklist

- Header `/** ... */` present with CBRD number and Coverage list?
- Every DML batch followed by `--test: COMMIT;` before `--check:`?
- Every table has a PRIMARY KEY?
- All `--check:` SELECTs use `ORDER BY`?
- Cleanup (`DROP TABLE IF EXISTS` + `COMMIT`) at the end?
- No statements mixing `--test:` and `--check:` on the same line?

## Relationship to SQL Testcases

ha_repl testcases use the same `/** ... */` header format as SQL testcases but prefix every line with `--test:` / `--check:` instead of bare SQL + `evaluate` markers. They do **not** use `evaluate`, `--+ server-message on/off`, or `.answer` files. They live under `ha_repl/` instead of `sql/`.

## Examples

- `@examples/basic_insert_replicate.sql` — INSERT/UPDATE/DELETE replication with consistency checks
- `@examples/ddl_replicate.sql` — DDL (CREATE TABLE, ALTER TABLE, DROP TABLE) replication
