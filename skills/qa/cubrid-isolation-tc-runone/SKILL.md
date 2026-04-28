---
name: cubrid-isolation-tc-runone
description: "Executes a single CUBRID isolation testcase (.ctl) via CTP and reports pass/fail. Invoke when the user asks to run a specific isolation test — Korean: isolation tc 돌려봐, 격리 테스트 실행; English: \"run isolation test\", \"execute isolation tc\". NOT for: creating new isolation tests (use cubrid-isolation-tc-create), running full isolation regression."
---

# Isolation Testcase Runner (CTP)

Run a single CTP isolation testcase (`.ctl`) on the local machine and report pass/fail.

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
```

If `ctp.sh` is not found, stop and display:

> "CTP is not installed. This skill cannot proceed.
> Install: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

## Execution Steps

### 1. Install CUBRID

A build URL is required. If not provided, ask:

> "A CUBRID build file URL is required. Please provide the build URL."

```bash
sh ~/cubrid-testtools/CTP/common/script/run_cubrid_install <build_url> 2>&1 | tee /tmp/cubrid_install.log
grep '\[ERROR\]' /tmp/cubrid_install.log
source ~/.cubrid.sh
cubrid --version
```

If either check fails, stop and show the `[ERROR]` lines from the install log.

### 2. Identify the .ctl file

Isolation testcases live under `~/cubrid-testcases/isolation/`. Locate the file:

```bash
find ~/cubrid-testcases/isolation -name "<pattern>.ctl"
```

Read the `.ctl` file before running to understand the concurrent scenario, the clients involved, and what the test verifies. This context is essential for diagnosing failures.

### 3. Prepare the environment

```bash
source ~/.cubrid.sh
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
```

### 4. Create a temporary CTP config

Point the config at the **directory** containing the `.ctl` file, not the file itself:

```bash
cat > /tmp/isolation_runone.conf << 'EOF'
scenario=<path_to_ctl_file_directory>
test_category=isolation
feedback_type=file
EOF
```

### 5. Run via CTP

```bash
timeout 600 $CTP_HOME/bin/ctp.sh isolation -c /tmp/isolation_runone.conf 2>&1 | tee /tmp/isolation_runone_output.log
```

### 6. Check the result

Parse CTP output for pass/fail counts:

```bash
grep -E 'PASS|FAIL|success|fail' /tmp/isolation_runone_output.log | tail -20
```

Also check for a generated `.result` file alongside the `.ctl`:

```bash
cat <path_to_ctl_file_directory>/<test_name>.result
```

### 7. Failure analysis (when FAIL)

**Compare result vs expected output:**

```bash
diff <test_name>.answer <test_name>.result
```

The `.answer` file contains the expected output from the concurrent scenario. Any difference indicates a behavioral regression.

**Check CUBRID server logs for deadlocks, lock timeouts, or crashes:**

```bash
cat $CUBRID/log/server/*.err 2>/dev/null | tail -50
```

**Check for core dumps:**

```bash
ls -la core* 2>/dev/null
ls -la $CUBRID/core* 2>/dev/null
```

### 8. Cleanup

```bash
cubrid server status 2>/dev/null
ps -ef | grep cub_ | grep -v grep
```

Warn the user if leftover server processes or databases remain after the test.

## Output Format

**On success:**
```
[PASS] <test_name>.ctl
  - Result: <pass count from CTP output>
  - Summary: <what concurrent scenario was verified>
```

**On failure:**
```
[FAIL] <test_name>.ctl
  - Result: <fail count from CTP output>
  - Diff (answer vs result):
    <relevant diff lines>
  - Server logs: <key error lines>
  - Crash: <yes/no — core dump found?>
  - Root cause: <diagnosis>
  - Suggestion: <what to investigate>
```

## Common Issues

- **Test hangs on lock contention**: Isolation tests use concurrent connections that may wait on each other indefinitely. The 600-second `timeout` will terminate a hung test — check `cubrid lockdb` and server logs for the blocking transaction.
- **CUBRID server not running**: Isolation tests require a running CUBRID instance (unlike unittests). Verify with `cubrid server status` and start if needed.
- **JAVA_HOME not set**: CTP is Java-based — if `java` is not on PATH or `JAVA_HOME` is wrong, CTP will fail to start. Set `JAVA_HOME` explicitly before running.
- **`.answer` file missing**: The test has never produced a reference output. Run the test once in answer-generation mode or check if the `.answer` file exists in the testcases repo.
- **Multiple `.ctl` files in the directory**: Setting `scenario=` to a directory runs all `.ctl` files in it. If only one specific test should run, move it to a temp directory or check CTP docs for single-file targeting.
