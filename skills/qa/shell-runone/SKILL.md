---
name: shell-runone
description: "Executes a named CUBRID shell testcase on the local machine and reports pass/fail. Invoke when the user asks to physically run a specific shell test — Korean: 돌려봐, 수행해줘, 실행해봐, 패스하는지 확인, 동작하는지 확인; English: \"run\", \"execute\", \"shell tc\". A CUBRID build URL in the request is a strong execution signal — always invoke this skill when a build URL appears alongside a test name or .sh path. Covers: checking if a newly written test works, verifying a test passes, and diagnosing a failing shell tc by actually running it.\n\nSkip for: reviewing or editing test code, creating new tests, adding to exclusion lists, full regression suites, CUBRID command questions without a specific test to run."
---

# Shell Testcase Runner (CTP)

Run a single CTP shell testcase on the local machine, report the result, and analyze failures.

## Prerequisites

### CTP Installation Check (mandatory first step)

**Before executing this skill, verify CTP is installed. CTP can exist in two forms:**

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
# Verify shell helpers exist
ls $CTP_HOME/shell/init_path/init.sh
```

If `ctp.sh` or `init.sh` is not found at any of the above paths, **stop immediately** and display:

> "CTP is not installed. This skill cannot proceed.
> Installation methods:
> - Option 1: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> - Option 2: `git clone https://github.com/CUBRID/cubrid-testtools.git` and use `~/cubrid-testtools/CTP` directly
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

**Proceed to the following steps only after CTP installation is confirmed. Use the detected `$CTP_HOME` in all subsequent steps.**

### Other requirements

The local machine must have:
- `cubrid-testtools` repository with CTP shell helpers (`CTP/shell/init_path/init.sh`)
- `cubrid-testcases-private-ex` repository containing the test cases

CUBRID does not need to be pre-installed — the skill handles installation via a build URL.

## Execution Steps

### 1. Request the build URL and install CUBRID

Before anything else, a CUBRID build file URL is required. If the user already provided a URL in their request, use it directly. Otherwise, ask:

> "A CUBRID build file URL is required to run the test. Please provide the build URL."
> (e.g. `http://somewhere/CUBRID-11.3.0.xxxx-Linux.x86_64.sh`)

Once you have the URL, install CUBRID and capture the output for error checking:

```bash
sh ~/cubrid-testtools/CTP/common/script/run_cubrid_install <build_url> 2>&1 | tee /tmp/cubrid_install.log
```

**Important**: The `run_cubrid_install` script does NOT exit with a non-zero code on failure — it prints `[ERROR]` messages but returns 0. Also, it removes the existing `$HOME/CUBRID` directory before attempting download. So you must verify installation by two checks:

```bash
# Check 1: Look for [ERROR] in install output
grep '\[ERROR\]' /tmp/cubrid_install.log

# Check 2: Verify CUBRID binary works
source ~/.cubrid.sh
cubrid --version
```

If either check indicates failure (grep finds `[ERROR]` or `cubrid --version` fails), **stop immediately** and tell the user:

> "Build installation failed. Please verify the build file URL and try again."
> (Show the `[ERROR]` lines from `/tmp/cubrid_install.log` for context)

Do not proceed with test execution if installation fails.

### 2. Identify the test case (after successful installation)

Determine the full path to the `.sh` file. Shell testcases follow this structure:
```
{test_name}/cases/{test_name}.sh
```

If the user gives a partial path, CBRD issue number, or test name, locate the actual file:
```bash
find ~/cubrid-testcases-private-ex/shell -name "<pattern>.sh" -path "*/cases/*"
```

### 3. Read the test script before running

Always read the test script first to understand:
- What it tests (the shebang-top comment explains the purpose)
- What databases it creates
- What services it starts
- Whether it needs special configuration or platform requirements (e.g., `WINDOWS_NOT_SUPPORTED`)

This context is essential for diagnosing failures later.

### 4. Prepare the environment

```bash
source ~/.cubrid.sh
export init_path=$HOME/cubrid-testtools/CTP/shell/init_path
```

Verify the environment is ready:
```bash
cubrid --version    # CUBRID must be accessible
ls $init_path/init.sh  # CTP helpers must exist
```

If either check fails, stop and tell the user what's missing.

### 5. Execute the test

Run the test from its `cases/` directory — this is important because some tests use relative paths for helper scripts or answer files.

```bash
cd /path/to/test_name/cases/
sh test_name.sh 2>&1 | tee /tmp/shell_runone_output.log
```

Use `tee` to capture full output while still showing progress. Set a reasonable timeout (default 300 seconds) to avoid hanging on stuck tests:

```bash
cd /path/to/test_name/cases/
timeout 300 sh test_name.sh 2>&1 | tee /tmp/shell_runone_output.log
EXIT_CODE=$?
```

If the exit code is 124 (timeout), report that the test timed out.

### 6. Check the result

After execution, check the result file:
```bash
cat /path/to/test_name/cases/test_name.result
```

The result file contains lines like:
- `test_name-1 : OK` — test passed
- `test_name-1 : NOK` — test failed

Report each result line to the user.

### 7. Failure analysis (when NOK)

When a test fails, perform a systematic investigation. The goal is to give the user an actionable diagnosis, not just "it failed."

#### Step A: Check the execution output

Review the captured output (`/tmp/shell_runone_output.log`) for:
- Error messages from CUBRID utilities (`cubrid server start`, `cubrid createdb`, etc.)
- csql errors (syntax errors, runtime errors)
- Shell errors (command not found, permission denied)
- Assertion failures (the condition that led to `write_nok`)

#### Step B: Check CUBRID server error logs

```bash
ls -la $CUBRID/log/server/*.err 2>/dev/null
cat $CUBRID/log/server/*.err 2>/dev/null
```

Server error logs often contain the root cause: crashes, assertion failures, or internal errors.

#### Step C: Check broker logs if relevant

```bash
ls -la $CUBRID/log/broker/*.err 2>/dev/null
```

#### Step D: Check for core dumps

```bash
ls -la /path/to/test_name/cases/core* 2>/dev/null
ls -la $CUBRID/core* 2>/dev/null
```

If a core dump exists, it indicates a server crash — this is significant information.

#### Step E: Compare actual vs expected output

If the test uses `compare_result_between_files` or file-based comparison, look for:
- The answer file (`.answer`) — what was expected
- The result/log file — what actually happened
- Run `diff` between them to show the exact differences

```bash
diff expected_file actual_file
```

#### Step F: Synthesize the diagnosis

Present the failure analysis in this structure:

1. **Result**: PASS or FAIL (with the exact result line)
2. **What the test does**: Brief summary from the script's header comment
3. **Where it failed**: Which phase (setup/test/verify/cleanup) and which specific command or check
4. **Root cause**: What went wrong and why, based on the log evidence
5. **Relevant logs**: Key error messages (quote the actual log lines)
6. **Suggestion**: What to fix — is it a test script bug, a CUBRID bug, or an environment issue?

### 8. Cleanup verification

After the test finishes (pass or fail), verify cleanup was thorough:

```bash
# Check for leftover databases
cubrid server status 2>/dev/null
# Check for orphan processes  
ps -ef | grep cub_ | grep -v grep
```

If leftover processes or databases exist, warn the user and offer to clean them up.

## Handling Common Issues

### Test hangs or takes too long
If the test exceeds the timeout, kill it and check:
- Is there an unbounded loop in the script?
- Is the server stuck? Check `$CUBRID/log/server/*.err`
- Is it waiting for a lock? Check `cubrid lockdb`

### Environment not set up
If `$CUBRID` or `$init_path` is not set, guide the user:
```bash
source ~/.cubrid.sh
export init_path=$HOME/cubrid-testtools/CTP/shell/init_path
```

### Permission issues
If the script can't execute, check permissions:
```bash
chmod +x test_name.sh
```

### Answer file missing
If the test uses answer-based comparison and the `.answer` file doesn't exist, the test needs to be run in answer mode first:
```bash
# Edit the script temporarily: change "init test" to "init answer"
# Or tell the user this is expected for a first run
```

## Output Format

Always present results clearly:

**On success:**
```
[PASS] test_name
  - Result: test_name-1 : OK
  - Summary: <what the test verified>
```

**On failure:**
```
[FAIL] test_name
  - Result: test_name-1 : NOK
  - Summary: <what the test verified>
  - Failed at: <phase and command>
  - Root cause: <diagnosis>
  - Key logs:
    <relevant error lines>
  - Suggestion: <what to fix>
```
