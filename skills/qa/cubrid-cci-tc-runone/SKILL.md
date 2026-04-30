---
name: cubrid-cci-tc-runone
description: "Executes a single CUBRID CCI testcase on the local machine and reports pass/fail. Invoke when the user asks to run a specific CCI test — Korean: cci tc 돌려봐, cci 테스트 실행, cci tc 수행; English: \"run cci test\", \"execute cci tc\". A CUBRID build URL with a CCI test path is a strong signal. NOT for: creating new CCI tests (use cubrid-cci-tc-create), running full CCI regression suites."
---

# CCI Testcase Runner (CTP)

Run a single CTP CCI testcase on the local machine, report the result, and analyze failures.

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
ls $CTP_HOME/shell/init_path/init.sh
```

If `ctp.sh` or `init.sh` is not found, **stop immediately** and display:

> "CTP is not installed. This skill cannot proceed.
> Install: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

The `cubrid-testcases-private` repository containing test cases must also be present.

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

## 1. Install CUBRID

A build URL is required. If not provided, ask:
> "A CUBRID build file URL is required. Please provide the build URL."

```bash
sh ~/cubrid-testtools/CTP/common/script/run_cubrid_install <build_url> 2>&1 | tee /tmp/cubrid_install.log
grep '\[ERROR\]' /tmp/cubrid_install.log
source ~/.cubrid.sh && cubrid --version
```

`run_cubrid_install` does NOT exit non-zero on failure — always check for `[ERROR]` in the log and verify `cubrid --version` works. If either fails, stop and ask the user for a correct URL.

## 2. Identify the test case

CCI testcases live in:
```
cubrid-testcases-private/interface/CCI/shell/_20_cci/<category>/<test_name>/cases/
```

If the user gives a partial name or CBRD issue number, locate the file:
```bash
find ~/cubrid-testcases-private/interface/CCI -name "<pattern>.sh" -path "*/cases/*"
```

## 3. Read the test files before running

Always read both the `.sh` script and `test.c` before running:
- The shell script header explains what is being tested
- `test.c` shows the CCI API calls being exercised
- The `.answer` file (if present) shows expected output

This context is essential for diagnosing failures.

## 4. Prepare the environment

```bash
source ~/.cubrid.sh
export init_path=$CTP_HOME/shell/init_path
cubrid --version        # CUBRID must be accessible
ls $init_path/init.sh  # CTP helpers must exist
```

## 5. Execute the test

Run from the `cases/` directory — some tests use relative paths for helper scripts or answer files.

```bash
cd /path/to/test_name/cases/
timeout 300 bash test_name.sh 2>&1 | tee /tmp/cci_runone_output.log
EXIT_CODE=$?
```

If exit code is 124, the test timed out — report this immediately.

## 6. Check the result

```bash
cat /path/to/test_name/cases/test_name.result
```

Result lines look like:
- `test_name-1 : OK` — passed
- `test_name-1 : NOK` — failed

## 7. Failure analysis (when NOK)

### Step A: Check for compile errors

CCI tests compile C code — check for `gcc`/`xgcc` failures first:
```bash
grep -i "error:" /tmp/cci_runone_output.log | head -20
```

If compilation failed, verify the CCI header exists:
```bash
ls ${CUBRID}/include/cas_cci.h
```

### Step B: Check execution output

Review `/tmp/cci_runone_output.log` for:
- `cci_connect failed`, `cci_prepare failed`, `cci_execute failed`
- Output mismatch lines (when using `compare_result_between_files`)
- `write_nok` trigger — what condition caused it

### Step C: Check CUBRID server and broker logs

```bash
cat $CUBRID/log/server/*.err 2>/dev/null | tail -30
ls -la $CUBRID/log/broker/*.err 2>/dev/null
```

### Step D: Check for core dumps

```bash
ls -la /path/to/test_name/cases/core* 2>/dev/null
ls -la $CUBRID/core* 2>/dev/null
```

A core dump indicates a server or client crash — significant information.

### Step E: Compare actual vs expected (simple pattern tests)

```bash
diff /path/to/test_name/cases/test_name.answer \
     /path/to/test_name/cases/test_name.output
```

### Step F: Synthesize the diagnosis

1. **Result**: PASS or FAIL
2. **What the test does**: from the script header
3. **Pattern**: simple (xgcc + answer comparison) or issue (explicit gcc + write_ok/write_nok)
4. **Where it failed**: compile / connect / execute / compare
5. **Root cause**: based on log evidence
6. **Suggestion**: test bug, CUBRID bug, or environment issue

## 8. Cleanup verification

```bash
cubrid server status 2>/dev/null
ps -ef | grep cub_ | grep -v grep
```

Warn the user if leftover processes or databases remain.

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
  - Failed at: <compile|connect|execute|compare>
  - Root cause: <diagnosis>
  - Key logs:
    <relevant error lines>
  - Suggestion: <what to fix>
```

## Common Issues

- **Compile error: `cas_cci.h` not found** — `${CUBRID}/include/cas_cci.h` is missing; verify CUBRID installation with `cubrid --version` and check `$CUBRID` is set.
- **`cci_connect failed`** — broker not running; run `cubrid broker start` and confirm port with `cubrid broker status -b`.
- **Answer file mismatch** — output diverges from `.answer`; use `diff` to pinpoint the exact line, then check if it is a test script bug or a CUBRID regression.
- **Test hangs / timeout** — check for an unbounded loop in `test.c` or a stuck server; inspect `$CUBRID/log/server/*.err` and run `cubrid lockdb <dbname>`.
- **Core dump present** — indicates a crash in the CCI driver or CUBRID server; report the core location and the last lines of the server error log for further triage.
