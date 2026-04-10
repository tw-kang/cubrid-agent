---
name: cdc_repl-create
description: Use this skill whenever the user wants to create, draft, write, or scaffold a new CDC replication testcase (.sql) for CUBRID CTP. Common requests: "cdc_repl tc 만들어줘", "cdc replication testcase", "cdc tc 초안", "create cdc repl tc", "draft cdc test", "새 cdc 테스트케이스 작성", "create draft cdc tc for CBRD-XXXXX". NOT for: running existing CDC tests, reviewing diffs/PRs, CTP configuration, or general SQL scripting unrelated to CTP cdc_repl test creation.
---

# CDC Replication Testcase Creator (CTP)

Generate well-formed CUBRID CTP CDC replication testcase files (`.sql`).

## Prerequisites — CTP Installation Check (mandatory first step)

CTP can exist in two forms:

1. **Deployed form**: `$HOME/CTP` (copied from cubrid-testtools)
2. **Git clone form**: `~/cubrid-testtools/CTP` (repository used directly)

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

## What is CDC Replication Testing?

CDC (Change Data Capture) is a mechanism that captures DML changes (INSERT/UPDATE/DELETE) from a source database in real-time and replicates them to a target database. CDC replication tests verify that captured changes are correctly and consistently applied to the target.

### CDC vs. HA Replication — Key Differences

| Aspect | ha_repl | cdc_repl |
|--------|---------|----------|
| Capture mechanism | Log-based replication | CDC change capture |
| Verification | Master/slave row comparison | `CheckDiff.java` (CDC-specific) |
| Helper tool | (none) | `cdc_test_helper` (native C tool) |
| Utility class | (none) | `CdcReplUtils.java` |
| Config file | `conf/ha_repl.conf` | `conf/cdc_repl.conf` |
| Run command | `bin/ctp.sh ha_repl -c conf/ha_repl.conf` | `bin/ctp.sh cdc_repl -c conf/cdc_repl.conf` |
| Results path | `CTP/result/ha_repl/current_runtime_logs/` | `CTP/result/cdc_repl/current_runtime_logs/` |
| PRIMARY KEY | Auto-added if missing | **Mandatory — must be explicit** |
| LOB support | Full | Limited — BLOB/CLOB may not replicate correctly |

### CDC-Specific Components

- **`CheckDiff.java`**: CDC-specific data consistency verifier. Compares source and target data after CDC replication completes. Not present in ha_repl.
- **`CdcReplUtils.java`**: Utility functions specific to CDC operations (e.g., waiting for CDC sync, validating capture state).
- **`cdc_test_helper`**: Native C tool (`cdc_test_helper/cdc_test_helper.c`) for CDC-specific test operations. Build with `cdc_test_helper/build.sh` before running tests.

## Testcase Markers

| Marker | Purpose | Example |
|--------|---------|---------|
| `--test:` | DML/DDL statement executed on the **source** DB; captured by CDC | `--test: INSERT INTO t1 VALUES (1, 'a');` |
| `--check:` | Query run on **both** source and target; results compared by `CheckDiff` | `--check: SELECT * FROM t1 ORDER BY id;` |

**Rules:**
- Every `--test:` block that modifies data must end with `--test: COMMIT;`
- `--check:` queries must produce deterministic results — always use `ORDER BY`
- Do not mix `--test:` and `--check:` on the same logical block without a `COMMIT` between them
- Setup and teardown (`CREATE TABLE`, `DROP TABLE IF EXISTS`) use `--test:` markers

## Directory Path Convention

CDC replication testcases live in the `cubrid-testcases` repository under a path parallel to ha_repl:

### Bug fixes

```
cdc_repl/_13_issues/_{yy}_{1|2}h/cases/cbrd_XXXXX.sql
```

- `{yy}` = two-digit year, `{1|2}h` = first/second half of year
- Multiple tests for same issue: append suffix (`cbrd_27100_insert.sql`, `cbrd_27100_update.sql`)

### New features

```
cdc_repl/_{no}_{release_code}/{feature_group}/cases/cbrd_XXXXX.sql
```

Multiple SQL test files share the same `cases/` directory — do not create per-test subdirectories.

## Testcase File Format

```sql
/**
 * This test case verifies CBRD-XXXXX: CDC replication of <feature>
 *
 * Coverage:
 * 1 - CDC captures INSERT operations
 * 2 - CDC captures UPDATE operations
 * 3 - CDC captures DELETE operations
 * 4 - Verify data consistency via CheckDiff
 */

--test: DROP TABLE IF EXISTS t1;
--test: CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
--test: COMMIT;

--test: INSERT INTO t1 VALUES (1, 'hello');
--test: INSERT INTO t1 VALUES (2, 'world');
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: UPDATE t1 SET val = 'modified' WHERE id = 1;
--test: COMMIT;

--check: SELECT id, val FROM t1 ORDER BY id;

--test: DELETE FROM t1 WHERE id = 2;
--test: COMMIT;

--check: SELECT id, val FROM t1 ORDER BY id;

--test: DROP TABLE IF EXISTS t1;
--test: COMMIT;
```

### Header block

Always start with `/** ... */` comment:
- First line: `This test case verifies CBRD-XXXXX: <title>`
- `Coverage:` section listing numbered scenarios

### Setup and cleanup

- `--test: DROP TABLE IF EXISTS` before every `--test: CREATE TABLE` (re-runnable)
- Always include `--test: COMMIT;` after DDL and after each DML batch
- Setup at top, cleanup at bottom
- Keep table and column names simple (`t1`, `col1`)

## File Format Rules

### PRIMARY KEY is mandatory

CDC tracks rows by primary key. A table without a PRIMARY KEY cannot be reliably replicated:

```sql
-- CORRECT
--test: CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));

-- WRONG — CDC cannot track rows without a primary key
--test: CREATE TABLE t1 (val VARCHAR(100));
```

### LOB (BLOB/CLOB) limitations

BLOB and CLOB columns may not replicate correctly via CDC. Either:
- Avoid LOB columns unless the test explicitly targets LOB CDC behavior
- If testing LOB behavior, add a comment noting the known limitation

### Composite primary keys

Allowed, but prefer single-column integer primary keys for clarity:

```sql
--test: CREATE TABLE t1 (id1 INT, id2 INT, val VARCHAR(100), PRIMARY KEY (id1, id2));
```

### CHECK queries must be deterministic

Always include `ORDER BY` in `--check:` queries. Results are compared between source and target — non-deterministic ordering will cause false failures:

```sql
-- CORRECT
--check: SELECT id, val FROM t1 ORDER BY id;

-- WRONG — row order may differ between source and target
--check: SELECT id, val FROM t1;
```

## Writing Rules

- Keep tests focused on one feature or behavior per file
- 3–8 `--check:` blocks per file is typical
- Each distinct DML operation type (INSERT/UPDATE/DELETE) should have its own `--check:`
- Use simple, predictable data values for easy diff inspection
- Test edge cases: empty result after DELETE, multiple rows updated, NULL values
- Do NOT test LOB columns unless explicitly required by the issue
- Do NOT use `AUTO_INCREMENT` columns alone as primary key if you need to predict inserted IDs — use explicit values

### NULL handling

```sql
--test: INSERT INTO t1 VALUES (3, NULL);
--test: COMMIT;
--check: SELECT id, val FROM t1 WHERE val IS NULL ORDER BY id;
```

### Multi-table scenarios

When testing joins or cross-table consistency, create all tables before any data inserts:

```sql
--test: DROP TABLE IF EXISTS t2;
--test: DROP TABLE IF EXISTS t1;
--test: CREATE TABLE t1 (id INT PRIMARY KEY, name VARCHAR(50));
--test: CREATE TABLE t2 (id INT PRIMARY KEY, t1_id INT, score INT);
--test: COMMIT;
```

## Infrastructure Requirements

CDC replication tests require a live CDC-enabled CUBRID environment:
- Source DB node with CDC enabled
- Target DB node configured to consume CDC events
- `cdc_test_helper` built (`cdc_test_helper/build.sh`) and accessible
- Config: `conf/cdc_repl.conf` pointing to source/target nodes

**These tests cannot be run locally without a full CDC replication environment.** When generating a testcase without access to such an environment, create the `.sql` file and note that execution requires a configured CDC cluster.

## Generation Process

1. **Clarify the test target**: JIRA issue ID, behavior under test (INSERT/UPDATE/DELETE/DDL/mixed), test type (bug fix / new feature).
2. **Determine the directory path**: current date (year + half) for bug fixes, or release code for new features.
3. **Draft the `.sql` file**: header → setup (DROP IF EXISTS + CREATE TABLE with PRIMARY KEY + COMMIT) → test blocks (--test: DML + COMMIT) → check blocks (--check: SELECT ORDER BY) → cleanup.
4. **Self-review checklist**:
   - Header present with CBRD issue ID and Coverage section?
   - Every table has an explicit PRIMARY KEY?
   - Every DML batch ends with `--test: COMMIT;`?
   - Every `--check:` query has `ORDER BY`?
   - `DROP TABLE IF EXISTS` before every `CREATE TABLE`?
   - No LOB columns unless explicitly required?
   - Cleanup at the bottom?
5. **Present the output**: show file path and contents.

## Examples

- `@examples/basic_dml_capture.sql` — INSERT/UPDATE/DELETE CDC capture with consistency checks
- `@examples/schema_change_capture.sql` — DDL changes captured by CDC
