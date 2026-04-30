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

## JIRA Issue Context (do this when the test corresponds to a CBRD-XXXXX)

If the test path or user's request mentions a `cbrd_NNNNN` or `CBRD-NNNNN` (e.g. `cbrd_27100.sh`, `TestCbrd27100.java`), **invoke the `jira` skill first** to fetch the issue background — original symptom, expected behavior, affected components, comments — before running and diagnosing the test. This dramatically improves failure analysis: actual behavior can then be compared against the issue's stated expected behavior.

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

   Let the summary, description, and comments inform pass/fail interpretation and root-cause diagnosis.

4. **If the skill is missing** — **halt and ask the user**:

   > The `jira` skill is required to fetch CBRD-XXXXX context for accurate failure diagnosis, but it is not installed. May I install it from this repo (`tw-kang/skills`) now?
   > Suggested: `npx skills add tw-kang/skills -s jira -a claude-code`
   >
   > After install, re-run the discovery step above. If the script is still not found, the install path may differ on this system — please report which directory under `~/.claude/` or the plugin cache contains the new `jira/scripts/jira_search.py`.

   Wait for explicit confirmation. If the user declines, proceed without JIRA context and warn them that issue-specific details may be missing.

5. **No CBRD-XXXXX in the test path or request** — skip this section.

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
