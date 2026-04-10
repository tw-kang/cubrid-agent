---
name: sql-runone
description: "Executes a single CUBRID SQL testcase (.sql file) through CTP and reports pass/fail with diff analysis. Invoke when the user wants to run one specific SQL test — Korean: 돌려봐, 수행해줘, 실행해봐, SQL tc 한건 확인, SQL 케이스 실행, 패스하는지 확인; English: \"run\", \"execute\", \"sql tc\", \"test this sql\". A CUBRID build URL alongside a .sql file path is a strong execution signal. Also handles sql_by_cci (CCI driver) when user explicitly says 'sqlbycci' or 'sql_by_cci'.

Skip for: reviewing or editing SQL test files, creating new SQL tests, full regression suite runs."
---

# SQL Testcase Runner (CTP Interactive Mode)

Run a single CTP SQL testcase via CTP interactive mode. Supports `sql`, `medium`, `sql_by_cci` categories.

## 0. CTP Installation Check (mandatory first step)

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

If `ctp.sh` or `conf/` is not found, **stop immediately** and display:

> "CTP is not installed. This skill cannot proceed.
> Install: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

## 1. Pre-run Cleanup

```bash
source ~/.cubrid.sh 2>/dev/null
cubrid service stop 2>/dev/null
```

## 2. Install CUBRID (mandatory)

A build URL is required. If not provided, ask:
> "A CUBRID build file URL is required. Please provide the build URL."

```bash
sh ~/cubrid-testtools/CTP/common/script/run_cubrid_install <build_url> 2>&1 | tee /tmp/cubrid_install.log
grep '\[ERROR\]' /tmp/cubrid_install.log
source ~/.cubrid.sh && cubrid_rel
```

Always use this script (installs to `$HOME/CUBRID`, sets up `~/.cubrid.sh`). If `[ERROR]` appears or `cubrid_rel` fails, stop and ask for a correct URL.

## 3. Verify environment

```bash
source ~/.cubrid.sh
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
# Locale library — sql.conf does not auto-build it
[ ! -f $CUBRID/lib/libcubrid_all_locales.so ] && sh $CUBRID/bin/make_locale.sh -t 64bit
```

## 4. Detect category

| Category | Trigger | Conf file | Interactive command |
|----------|---------|-----------|-------------------|
| `sql` | default (path contains `/sql/`) | `sql.conf` | `run <file>` |
| `medium` | path contains `/medium/` | `medium_dev.conf` | `run <file>` |
| `sql_by_cci` | user explicitly says `sqlbycci`/`sql_by_cci` | `sql_by_cci.conf` | `run_cci <file>` |

```bash
CTP_HOME=$HOME/cubrid-testtools/CTP
# Detect from user request and file path
if <user said sqlbycci or sql_by_cci>; then
    CTP_CATEGORY=sql_by_cci; CTP_CONF=$CTP_HOME/conf/sql_by_cci.conf; RUN_CMD=run_cci
elif echo "$SQL_FILE" | grep -q '/medium/'; then
    CTP_CATEGORY=medium; CTP_CONF=$CTP_HOME/conf/medium_dev.conf; RUN_CMD=run
else
    CTP_CATEGORY=sql; CTP_CONF=$CTP_HOME/conf/sql.conf; RUN_CMD=run
fi
```

## 5. Prepare file structure

CTP expects `.sql` in `cases/` with answers in sibling `answers/`. If already in `cases/`, use directly. Otherwise create a temp structure:

```bash
TEMP_DIR=/tmp/sql_runone_$$
mkdir -p $TEMP_DIR/cases $TEMP_DIR/answers
cp "$SQL_FILE" $TEMP_DIR/cases/
SQL_FILE=$TEMP_DIR/cases/$(basename "$SQL_FILE")
# Copy .answer and .queryPlan if provided
```

## 6. Read the SQL file

Read the SQL file before running to understand what it tests. Essential for diagnosing failures.

## 7. Run via CTP interactive mode

```bash
printf "%s %s\nquit\n" "$RUN_CMD" "$SQL_FILE" | \
  timeout 600 $CTP_HOME/bin/ctp.sh $CTP_CATEGORY -c $CTP_CONF --interactive 2>&1 | tee /tmp/sql_runone_output.log
```

Setup (DB creation, config) takes 1-3 minutes before the interactive shell starts.

## 8. Parse result

```bash
RESULT_DIR=$(grep "^Result Root Dir" /tmp/sql_runone_output.log | head -1 | awk -F': ' '{print $2}' | tr -d ' ')
cat $RESULT_DIR/main.info 2>/dev/null        # sql/medium
cat $RESULT_DIR/summary.info 2>/dev/null     # sql_by_cci
```

If no result files exist, check for "No Results!!" or "Failed to connect to database server" in the log.

## 9. Failure analysis (when fail > 0)

Compare actual result against expected answer to identify which query diverged.

### Step A: Find the result and answer files

```bash
# CTP result file (actual output)
RESULT_FILE=$(find $RESULT_DIR -name "*.result" | head -1)
# Answer file (expected output) — derive from SQL file path
ANSWER_FILE=$(echo "$SQL_FILE" | sed 's|/cases/|/answers/|; s|\.sql$|.answer|')
```

### Step B: Diff result vs answer

```bash
diff "$ANSWER_FILE" "$RESULT_FILE"
```

Query result blocks are separated by `===...===` lines, so the diff context reveals which SQL statement diverged.

### Step C: Check server/broker logs and core dumps

```bash
cat $CUBRID/log/server/*.err 2>/dev/null | tail -30
ls $CUBRID/core* /tmp/core* 2>/dev/null
```

Core dump = CUBRID bug. Server error log shows crashes, assertions, or internal errors.

### Step D: Report

```
[FAIL] test_name.sql  (category: sql|medium|sql_by_cci)
  - Total: 1, Fail: 1
  - Failed query: <the SQL statement that diverged>
  - Expected: <answer file content for that query>
  - Actual:   <result file content for that query>
  - Diagnosis: test bug / CUBRID bug / environment issue
```

On success:
```
[PASS] test_name.sql  (category: sql|medium|sql_by_cci)
  - Total: 1, Success: 1, Fail: 0
  - Elapsed: <time>
```

## 10. Cleanup

```bash
[ -n "$TEMP_DIR" ] && rm -rf $TEMP_DIR
```

## Common Issues

- **"No Results!!"** — SQL file path not found. Check absolute path and `cases/` directory.
- **"Failed to connect to database server"** — locale library missing (`make_locale.sh -t 64bit`), port conflict, or disk full.
- **"Cannot connect to a broker"** — broker not running or port 33120 occupied.
- **No answer file** — test ran but needs an answer file for comparison.
- **javac not found** — non-fatal unless testcase uses Java stored procedures.
