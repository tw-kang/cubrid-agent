---
name: cubrid-sql-tc-create
description: "Use this skill whenever the user wants to create, draft, write, or scaffold a new SQL testcase (.sql + .answer) for CUBRID CTP. This is the right skill any time someone needs a new SQL test produced from scratch for a CBRD issue — bug fix or new feature. Common requests: \"sql tc 만들어줘\", \"sql tc 초안 작성해줘\", \"create sql tc\", \"draft sql test\", \"새 sql testcase\", \"sql 테스트케이스 작성\", \"create draft sql tc for CBRD-XXXXX\". NOT for: running existing SQL tests, reviewing diffs/PRs, CTP configuration, or general SQL scripting unrelated to CTP test creation."
---

# SQL Testcase Creator (CTP)

Generate well-formed CUBRID CTP SQL testcase files (`.sql` + `.answer`).

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

If `ctp.sh` or `conf/` is not found at any of the above paths, **stop immediately** and display:

> "CTP is not installed. This skill cannot proceed.
> Installation methods:
> - Option 1: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> - Option 2: `git clone https://github.com/CUBRID/cubrid-testtools.git` and use `~/cubrid-testtools/CTP` directly
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

## JIRA Issue Context (do this when a CBRD-XXXXX is referenced)

When the request includes a `CBRD-XXXXX` ticket, **invoke the `jira` skill first** to fetch the issue background — title, description, reproduction steps, affected components, and comments — before generating the testcase. This grounds the test in the issue's actual requirements rather than guesswork.

**Already fetched in this conversation?** Reuse the context — do not re-invoke. The fetcher caches issues, but the conversation should not redundantly re-display them.

1. **Normalize the ticket ID** — `jira_search.py` requires the canonical `CBRD-NNNNN` form. Filenames typically use `cbrd_NNNNN`:

   ```bash
   TICKET=$(echo "$RAW_INPUT" | grep -oiE 'cbrd[-_ ]?[0-9]+' | head -1 \
            | tr '[:lower:]' '[:upper:]' \
            | sed -E 's/^CBRD[-_ ]?/CBRD-/')
   ```

2. **Locate the `jira` skill** — search project-scope, user-scope, plugin cache, and any `CLAUDE_PLUGIN_ROOT` install path. Do **not** rely on developer-specific paths:

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

3. **If the skill is available** — prefer the slash form `/jira CBRD-XXXXX` when the harness exposes it (it honors the upstream `pandoc` prerequisite gate). Otherwise call the bundled script directly. Warn the user when `pandoc` is missing so they know the description/comments will fall back to raw Jira-wiki markup:

   ```bash
   command -v pandoc >/dev/null 2>&1 || \
       echo "WARNING: pandoc not installed — JIRA description/comments will be raw wiki markup (degraded readability)."
   python3 "$JIRA_SCRIPT" "$TICKET"
   ```

   Let the summary, description, and comments drive the testcase scope, expected behavior, and edge cases.

4. **If the skill is missing** — **halt and ask the user**:

   > The `jira` skill is required to fetch CBRD-XXXXX context for accurate testcase generation, but it is not installed. May I install it from this repo (`tw-kang/skills`) now?
   > Suggested: `npx skills add tw-kang/skills -s jira -a claude-code`
   >
   > After install, re-run the discovery step above. If the script is still not found, the install path may differ on this system — please report which directory under `~/.claude/` or the plugin cache contains the new `jira/scripts/jira_search.py`.

   Wait for explicit confirmation. If the user declines, proceed without JIRA context and warn them that issue-specific details may be missing.

5. **No CBRD-XXXXX in the request** — skip this section.

## Directory Path Convention

### Bug fixes

```
sql/_13_issues/_{yy}_{1|2}h/cases/cbrd_XXXXX.sql
sql/_13_issues/_{yy}_{1|2}h/answers/cbrd_XXXXX.answer
```

- `{yy}` = two-digit year, `{1|2}h` = first/second half of year
- Multiple tests for same issue: append suffix (`cbrd_27100_select.sql`, `cbrd_27100_update.sql`)

### New features

```
sql/_{no}_{release_code}/{feature_group}/cases/cbrd_XXXXX.sql
sql/_{no}_{release_code}/{feature_group}/answers/cbrd_XXXXX.answer
```

Multiple SQL test files share the same `cases/` and `answers/` directories — do not create per-test subdirectories.

## SQL File Format

```sql
/**
 * This test case verifies CBRD-XXXXX: Brief one-line title
 *
 * Coverage:
 * 1 - Scenario one description
 * 2 - Scenario two description
 */

--+ server-message on

DROP TABLE IF EXISTS tbl_name;
CREATE TABLE tbl_name (col1 INT, col2 VARCHAR(100));
INSERT INTO tbl_name VALUES (1, 'hello'), (2, 'world');

evaluate 'Case 1: description of what this tests';
SELECT col1, col2 FROM tbl_name WHERE col1 = 1;

evaluate 'Case 2: description of expected error';
SELECT col1 / 0 FROM tbl_name;

DROP TABLE IF EXISTS tbl_name;

--+ server-message off
```

### Header block

Always start with `/** ... */` comment:
- First line: `This test case verifies CBRD-XXXXX: <title>`
- `Coverage:` section listing numbered scenarios

### `evaluate` statements

Use `evaluate 'Case N: description'` before each test scenario. Number sequentially. This is the sole section marker — do NOT add `-- ===` style comment headers.

### `--+ server-message on/off`

Enable when testing error messages (negative tests expecting `-NNN` errors). Always pair on/off. Skip when the test only checks result sets.

### Setup and cleanup

- `DROP TABLE IF EXISTS` before every `CREATE TABLE` (re-runnable)
- Setup at top, cleanup at bottom
- Keep setup minimal, use simple names (`tbl1`, `col1`)

### Query plan tests

When verifying optimizer decisions, create an empty `.queryPlan` file alongside the `.sql`:
```
cases/cbrd_XXXXX.sql
cases/cbrd_XXXXX.queryPlan   ← empty file
answers/cbrd_XXXXX.answer
```

## Writing Rules

- Use explicit column lists in `INSERT` when it aids readability
- Keep test SQL focused — avoid unrelated complexity
- Prefer simple data values for easy answer diffs
- 3–10 `evaluate` sections per file is typical
- Each error case should have its own `evaluate` label

### Parameter changes (rare)
```sql
SET SYSTEM PARAMETERS 'param_name=value';
-- ... test ...
SET SYSTEM PARAMETERS 'param_name=original_value';
```

### `holdcas` directive (rare)
```sql
--+ holdcas on;
-- ... transaction-sensitive test ...
--+ holdcas off;
```

## Answer File Generation

Do NOT write `.answer` files manually. Use the `cubrid-sql-tc-runone` skill to generate them.

### Procedure

1. Place the `.sql` file in the `cases/` directory.
2. Invoke the `cubrid-sql-tc-runone` skill to run the `.sql` file through CTP.
   - A build URL is required — use one already provided by the user, or ask for it.
3. After CTP execution, a `.result` file is generated in the `cases/` directory.
4. Copy the `.result` file to the `answers/` directory with the `.answer` extension:

```bash
BASENAME=cbrd_XXXXX
cp sql/_13_issues/_26_1h/cases/${BASENAME}.result \
   sql/_13_issues/_26_1h/answers/${BASENAME}.answer
```

5. Review the `.answer` file contents to confirm they match expected results.
   - DDL/DML: affected row count (`0` or integer)
   - SELECT: column headers + data rows
   - Errors: `Error:-NNN\n<error message>`
   - Each SQL statement output is separated by `===...===` lines

If no build URL is available or CUBRID environment is not set up, create an empty `.answer` file and instruct the user to complete it later using `cubrid-sql-tc-runone`.

## Self-Review Checklist

Before presenting output, verify:
- Header block present with CBRD number and coverage?
- `evaluate` labels on each scenario?
- `DROP TABLE IF EXISTS` before every `CREATE TABLE`?
- `server-message on/off` paired correctly?
- `.queryPlan` file needed?

## Examples

- `@examples/bug_fix_error_cases.sql` — negative test with server-message
- `@examples/bug_fix_select.sql` — basic SELECT result verification
- `@examples/feature_query_plan.sql` — test with queryPlan for optimizer verification
