---
name: sql-runone
description: "Executes a single CUBRID SQL testcase (.sql file) through CTP and reports pass/fail with diff analysis. Invoke when the user wants to run one specific SQL test — Korean: 돌려봐, 수행해줘, 실행해봐, SQL tc 한건 확인, SQL 케이스 실행, 패스하는지 확인; English: \"run\", \"execute\", \"sql tc\", \"test this sql\". A CUBRID build URL alongside a .sql file path is a strong execution signal. Covers: verifying a newly written SQL test works, checking if a specific SQL tc passes, diagnosing a failing SQL tc by actually running it. Also handles sql_by_cci (CCI driver) when user explicitly says 'sqlbycci' or 'sql_by_cci'.

Skip for: reviewing or editing SQL test files, creating new SQL tests, full regression suite runs, CUBRID command questions without a specific .sql file to run."
---

# SQL Testcase Runner (CTP Interactive Mode)

Run a single CTP SQL testcase on the local machine using CTP interactive mode, compare against the answer file if available, and analyze failures.

Supports three CTP categories: `sql`, `medium`, `sql_by_cci`.

## Prerequisites

- `cubrid-testtools` repository at `~/cubrid-testtools/CTP`
- `JAVA_HOME` must be set (CTP requires Java)
- CUBRID is installed via build URL as part of this skill — do not skip this step even if CUBRID appears to already be installed

## Execution Steps

### 1. Request the build URL and install CUBRID

**This step is mandatory and must not be skipped.** Before running anything, a CUBRID build file URL is required. If the user already provided a URL, use it directly. Otherwise ask:

> "테스트를 수행하려면 CUBRID 빌드 파일 링크가 필요합니다. 빌드 URL을 알려주세요."
> (예: `http://somewhere/CUBRID-11.3.0.xxxx-Linux.x86_64.sh`)

Once you have the URL, use the CTP install script — it handles download, license acceptance, and installation to `$HOME/CUBRID` automatically:

```bash
sh ~/cubrid-testtools/CTP/common/script/run_cubrid_install <build_url> 2>&1 | tee /tmp/cubrid_install.log
```

**Important**: The install script does NOT exit with a non-zero code on failure — it prints `[ERROR]` but returns 0. Verify installation with two checks:

```bash
# Check 1: errors in install output
grep '\[ERROR\]' /tmp/cubrid_install.log

# Check 2: source env and verify installed version
source ~/.cubrid.sh && cubrid_rel
```

`run_cubrid_install` installs CUBRID to `$HOME/CUBRID` and sets up `~/.cubrid.sh`. After sourcing it, `$CUBRID` points to `$HOME/CUBRID`.

If either check fails, stop immediately and tell the user:

> "빌드 파일 설치에 실패했습니다. 올바른 빌드 파일 링크를 확인 후 다시 제시해 주세요."
> (show the `[ERROR]` lines from `/tmp/cubrid_install.log`)

Do not proceed if installation fails.

### 2. Verify the environment

```bash
source ~/.cubrid.sh
echo "JAVA_HOME=$JAVA_HOME"
ls $HOME/cubrid-testtools/CTP/bin/ctp.sh
```

If `JAVA_HOME` is not set, try:
```bash
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
```

Check the locale library — CTP requires it for DB creation but `sql.conf` does not auto-build it:
```bash
if [ ! -f $CUBRID/lib/libcubrid_all_locales.so ]; then
    sh $CUBRID/bin/make_locale.sh -t 64bit
fi
```

### 3. Identify the SQL file and detect the test category

Determine the absolute path to the `.sql` file:
```bash
SQL_FILE=$(readlink -f /path/to/test.sql)
```

**CTP supports three categories for SQL-based tests:**

| Category | Trigger | Conf file | DB name |
|----------|---------|-----------|---------|
| `sql` | 기본 (path에 `/sql/`) | `$CTP_HOME/conf/sql.conf` | `basic_qa` |
| `medium` | path에 `/medium/` | `$CTP_HOME/conf/medium_dev.conf` | `medium_qa` |
| `sql_by_cci` | 사용자가 명시적으로 `sqlbycci` 또는 `sql_by_cci` 언급 | `$CTP_HOME/conf/sql_by_cci.conf` | `basic_qa` |

`sql_by_cci`는 JDBC 대신 CCI(C Client Interface)로 실행하는 방식으로, 사용자가 명시적으로 요청할 때만 사용한다.

Detect category:
```bash
CTP_HOME=$HOME/cubrid-testtools/CTP

# sql_by_cci: only when user explicitly says "sqlbycci" or "sql_by_cci"
# (check the user's original request, not the file path)
if <user said sqlbycci or sql_by_cci>; then
    CTP_CATEGORY=sql_by_cci
    CTP_CONF=$CTP_HOME/conf/sql_by_cci.conf
elif echo "$SQL_FILE" | grep -q '/medium/'; then
    CTP_CATEGORY=medium
    CTP_CONF=$CTP_HOME/conf/medium_dev.conf
else
    CTP_CATEGORY=sql
    CTP_CONF=$CTP_HOME/conf/sql.conf
fi
```

If the path is ambiguous or the file is outside the standard testcases directory, ask the user which category to use.

### 4. Prepare the file structure

CTP expects testcases in a `cases/` directory, with answers in a sibling `answers/` directory:
```
test_suite/
├── cases/
│   └── test.sql
└── answers/
    └── test.answer      (optional — needed for pass/fail comparison)
└── queryPlan/
    └── test.queryPlan   (optional — enables query plan comparison)
```

CTP derives the answer path by replacing `cases` → `answers` and `.sql` → `.answer`. The `.queryPlan` file is derived similarly.

**If the `.sql` file is already inside a `cases/` directory** → use it directly.

**If it is a standalone file (not in a `cases/` directory)** → create a temporary structure:

```bash
TEMP_DIR=/tmp/sql_runone_$$
mkdir -p $TEMP_DIR/cases $TEMP_DIR/answers $TEMP_DIR/queryPlan
cp "$SQL_FILE" $TEMP_DIR/cases/
BASENAME=$(basename "$SQL_FILE" .sql)
SQL_FILE=$TEMP_DIR/cases/${BASENAME}.sql

# Copy optional files if the user provided them
[ -f /path/to/test.answer ]    && cp /path/to/test.answer    $TEMP_DIR/answers/${BASENAME}.answer
[ -f /path/to/test.queryPlan ] && cp /path/to/test.queryPlan $TEMP_DIR/queryPlan/${BASENAME}.queryPlan
```

### 5. Read the SQL file before running

Always read the SQL file first to understand what it tests — what tables it creates, what queries it runs, and what the expected behavior is. This context is essential for diagnosing failures.

### 6. Run via CTP interactive mode

CTP interactive mode handles full setup automatically (CUBRID config, DB creation) then enters an interactive shell where `run` and `quit` are available.

Always pass the `-c` conf flag — it specifies the category-specific configuration:

```bash
printf "run %s\nquit\n" "$SQL_FILE" | \
  timeout 600 $CTP_HOME/bin/ctp.sh $CTP_CATEGORY -c $CTP_CONF --interactive 2>&1 | tee /tmp/sql_runone_output.log
EXIT_CODE=$?
[ $EXIT_CODE -eq 124 ] && echo "TIMEOUT: test exceeded 10 minutes"
```

**Category-specific commands:**

```bash
# sql
printf "run %s\nquit\n" "$SQL_FILE" | \
  timeout 600 $CTP_HOME/bin/ctp.sh sql -c $CTP_HOME/conf/sql.conf --interactive 2>&1 | tee /tmp/sql_runone_output.log

# medium
printf "run %s\nquit\n" "$SQL_FILE" | \
  timeout 600 $CTP_HOME/bin/ctp.sh medium -c $CTP_HOME/conf/medium_dev.conf --interactive 2>&1 | tee /tmp/sql_runone_output.log

# sql_by_cci (uses run_cci command inside interactive shell, not run)
printf "run_cci %s\nquit\n" "$SQL_FILE" | \
  timeout 600 $CTP_HOME/bin/ctp.sh sql_by_cci -c $CTP_HOME/conf/sql_by_cci.conf --interactive 2>&1 | tee /tmp/sql_runone_output.log
```

Note: Setup (DB creation, CUBRID config) runs before the interactive shell starts — this normally takes 1–3 minutes.

### 7. Find the result directory and parse the outcome

The result directory is printed in the log:
```bash
RESULT_DIR=$(grep "^Result Root Dir" /tmp/sql_runone_output.log | head -1 | awk -F': ' '{print $2}' | tr -d ' ')
```

Read the summary:
```bash
cat $RESULT_DIR/main.info
FAIL=$(grep 'fail:'    $RESULT_DIR/main.info | awk -F: '{print $2}')
SUCC=$(grep 'success:' $RESULT_DIR/main.info | awk -F: '{print $2}')
TOTAL=$(grep 'total:'  $RESULT_DIR/main.info | awk -F: '{print $2}')
```

If `main.info` is missing, check the log for "No Results!!" — this usually means the SQL file was not found or the path was incorrect.

### 8. Failure analysis (when fail > 0)

When a test fails, investigate systematically. The goal is an actionable diagnosis.

#### Step A: Check execution output
```bash
grep -i "error\|fail\|exception\|nok" /tmp/sql_runone_output.log | head -30
```

#### Step B: Find and read diff output

CTP saves diffs between actual and expected output in the result directory:
```bash
find $RESULT_DIR -name "*.diff" 2>/dev/null | head -5
find $RESULT_DIR -name "*.diff" -exec cat {} \;
```

Also check the query result files:
```bash
ls $RESULT_DIR/query_result/ 2>/dev/null
```

#### Step C: Check CUBRID server logs
```bash
cat $CUBRID/log/server/*.err 2>/dev/null | tail -50
```

#### Step D: Check for core dumps
```bash
ls -la $CUBRID/core* 2>/dev/null
```

#### Step E: Synthesize the diagnosis

1. **Result**: PASS or FAIL (with counts from main.info)
2. **What the test does**: Brief summary from reading the SQL file
3. **Where it failed**: Which query diverged (from diff)
4. **Root cause**: Actual vs expected (show the diff)
5. **Relevant logs**: Key error messages
6. **Suggestion**: Test bug, CUBRID bug, or environment issue

### 9. Cleanup
```bash
# Remove temp structure if created
[ -n "$TEMP_DIR" ] && rm -rf $TEMP_DIR
```

## Output Format

**On success:**
```
[PASS] test_name.sql  (category: sql|medium|sql_by_cci)
  - Total: 1, Success: 1, Fail: 0
  - Elapsed: <time>
  - Result dir: <path>
```

**On failure:**
```
[FAIL] test_name.sql  (category: sql|medium|sql_by_cci)
  - Total: 1, Success: 0, Fail: 1
  - Diff:
    Expected: ...
    Actual:   ...
  - Root cause: <diagnosis>
  - Suggestion: <what to fix>
```

## Common Issues

**"No Results!!" in log** — the SQL file path was not found. Verify the absolute path passed to `run` is correct.

**Test hangs** — timeout kills it after 10 minutes. Check `$CUBRID/log/server/*.err` for deadlocks or hangs.

**No answer file** — CTP records output but cannot compare. The test is neither PASS nor FAIL — it needs an answer file. Tell the user the test ran but comparison was skipped.

**DB already exists error** — CTP normally cleans up before creating the DB. If something went wrong in a previous run, manually drop it:
```bash
source ~/.cubrid.sh
cubrid deletedb basic_qa 2>/dev/null
cubrid deletedb medium_qa 2>/dev/null
```
