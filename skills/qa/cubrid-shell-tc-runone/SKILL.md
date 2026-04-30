---
name: cubrid-shell-tc-runone
description: "Executes a named CUBRID shell testcase on the local machine and reports pass/fail. Invoke when the user asks to physically run a specific shell test — Korean: 돌려봐, 수행해줘, 실행해봐, 패스하는지 확인, 동작하는지 확인; English: \"run\", \"execute\", \"shell tc\". A CUBRID build URL in the request is a strong execution signal — always invoke this skill when a build URL appears alongside a test name or .sh path. Covers: checking if a newly written test works, verifying a test passes, and diagnosing a failing shell tc by actually running it.\n\nSkip for: reviewing or editing test code, creating new tests, adding to exclusion lists, full regression suites, CUBRID command questions without a specific test to run."
---

# Shell Testcase Runner (CTP)

Run a single CTP shell testcase on the local machine, report the result, and analyze failures.

## Prerequisites

### CTP Installation Check (mandatory first step)

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

If `ctp.sh` or `init.sh` is not found, **stop immediately** and display:

> "CTP is not installed. This skill cannot proceed.
> Install: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

The `cubrid-testcases-private-ex` repository containing test cases must also be present. CUBRID itself does not need to be pre-installed.

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

### 1. Request the build URL and install CUBRID

A build URL is required. If not provided, ask:
> "A CUBRID build file URL is required. Please provide the build URL."

Install CUBRID and capture output for error checking:

```bash
sh ~/cubrid-testtools/CTP/common/script/run_cubrid_install <build_url> 2>&1 | tee /tmp/cubrid_install.log
```

**Important**: `run_cubrid_install` always returns 0 even on failure (prints `[ERROR]` instead) and removes `$HOME/CUBRID` before downloading. Verify by two checks:

```bash
# Check 1: Look for [ERROR] in install output
grep '\[ERROR\]' /tmp/cubrid_install.log

# Check 2: Verify CUBRID binary works
source ~/.cubrid.sh
cubrid --version
```

If either check fails, **stop** and show the `[ERROR]` lines from `/tmp/cubrid_install.log`. Ask the user to verify the URL.

### 2. Identify the test case

Determine the full path to the `.sh` file. Shell testcases follow this structure:
```
{test_name}/cases/{test_name}.sh
```

If the user gives a partial path, CBRD issue number, or test name, locate the actual file:
```bash
find ~/cubrid-testcases-private-ex/shell -name "<pattern>.sh" -path "*/cases/*"
```

### 3. Read the test script before running

Read the script to understand what it tests, what databases/services it uses, and any special requirements (e.g., `WINDOWS_NOT_SUPPORTED`). This context is essential for diagnosing failures.

### 4. Prepare the environment

```bash
source ~/.cubrid.sh
export init_path=$HOME/cubrid-testtools/CTP/shell/init_path
```

Verify both `cubrid --version` and `ls $init_path/init.sh` succeed. If either fails, stop and report what is missing.

### 5. Execute the test

Run from the `cases/` directory (tests use relative paths for helpers/answer files). Use timeout of 300s:

```bash
cd /path/to/test_name/cases/
timeout 300 sh test_name.sh 2>&1 | tee /tmp/shell_runone_output.log
EXIT_CODE=$?
```

Exit code 124 means timeout.

### 6. Check the result
```bash
cat /path/to/test_name/cases/test_name.result
```

Result lines: `test_name-1 : OK` (pass) or `test_name-1 : NOK` (fail). Report each line.

### 7. Failure analysis (when NOK)

Perform a systematic investigation to give the user an actionable diagnosis.

#### Step A: Check the execution output

Review `/tmp/shell_runone_output.log` for CUBRID utility errors, csql errors, shell errors, or assertion failures (`write_nok`).

#### Step B: Check CUBRID server error logs

```bash
cat $CUBRID/log/server/*.err 2>/dev/null
```

#### Step C: Check broker logs if relevant

```bash
ls -la $CUBRID/log/broker/*.err 2>/dev/null
```

#### Step D: Check for core dumps

```bash
ls -la /path/to/test_name/cases/core* 2>/dev/null
ls -la $CUBRID/core* 2>/dev/null
```

A core dump indicates a server crash.

#### Step E: Compare actual vs expected output

If the test uses file-based comparison, `diff` the `.answer` file against the result file.

```bash
diff expected_file actual_file
```

#### Step F: Synthesize the diagnosis

Present the failure analysis:

1. **Result**: PASS or FAIL (with the exact result line)
2. **What the test does**: Brief summary from the script's header comment
3. **Where it failed**: Which phase (setup/test/verify/cleanup) and which specific command or check
4. **Root cause**: What went wrong and why, based on the log evidence
5. **Relevant logs**: Key error messages (quote the actual log lines)
6. **Suggestion**: What to fix — is it a test script bug, a CUBRID bug, or an environment issue?

### 8. Cleanup verification

After the test finishes, check for leftovers:

```bash
cubrid server status 2>/dev/null
ps -ef | grep cub_ | grep -v grep
```

If leftover processes or databases exist, warn the user and offer cleanup.

## Handling Common Issues

- **Test hangs**: Check for unbounded loops, stuck server (`$CUBRID/log/server/*.err`), or lock waits (`cubrid lockdb`).
- **Environment not set**: Run `source ~/.cubrid.sh` and `export init_path=$HOME/cubrid-testtools/CTP/shell/init_path`.
- **Permission denied**: `chmod +x test_name.sh`
- **Answer file missing**: The test needs answer mode first (change `init test` to `init answer` in the script).

## Output Format

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
