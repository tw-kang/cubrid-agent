---
name: cubrid-cdc_repl-tc-runone
description: "Executes a single CUBRID CDC replication testcase (.sql with --test:/--check: markers) via CTP and reports pass/fail. Requires configured CDC infrastructure (source + target nodes). Invoke when the user asks to run a specific cdc_repl test — Korean: cdc_repl tc 돌려봐, cdc 테스트 실행; English: \"run cdc_repl test\". NOT for: creating tests (use cubrid-cdc_repl-tc-create), running full regression."
---

# CDC Replication Testcase Runner (CTP)

Run a single CTP cdc_repl testcase on configured CDC infrastructure and report pass/fail.

> **These tests CANNOT run on a single local machine.** They require a CDC-enabled source + target cluster with `cdc_test_helper` built on both nodes.

## Infrastructure Requirements

- Source node and target node configured in `$CTP_HOME/conf/cdc_repl.conf`
- `cdc_test_helper` built on infrastructure nodes via `cdc_test_helper/build.sh`
- CUBRID build URL: required so CTP installs CUBRID on both nodes
- All tables in test must have explicit PRIMARY KEY (CDC tracks rows by PK)

## Prerequisites — CTP Installation Check

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
> "CTP is not installed. Install: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`"

## JIRA Issue Context (do this when the test corresponds to a CBRD-XXXXX)

If the test path or user's request mentions `CBRD-XXXXX` (e.g. `cbrd_27100.sh`, `TestCbrd27100.java`), **invoke the `jira` skill first** to fetch the issue background — original symptom, expected behavior, affected components, comments — before running and diagnosing the test. This dramatically improves failure analysis: actual behavior can then be compared against the issue's stated expected behavior.

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

   Use the summary, description, and comments to inform pass/fail interpretation and root-cause diagnosis.

3. **If missing** — **halt and ask the user**:

   > The `jira` skill is required to fetch CBRD-XXXXX context for accurate failure diagnosis, but it is not installed. May I install it from this repo (`tw-kang/skills`) now?
   > Suggested: `npx skills add tw-kang/skills -s jira -a claude-code`

   Wait for explicit confirmation. If the user declines, proceed without JIRA context and warn them that issue-specific details may be missing.

4. **No CBRD-XXXXX in the test path or request** — skip this section.

## Execution Steps

### 1. Verify CDC infrastructure config

```bash
ls $CTP_HOME/conf/cdc_repl.conf
grep -E "ssh\.(host|user|password)" $CTP_HOME/conf/cdc_repl.conf
grep "cubrid_download_url" $CTP_HOME/conf/cdc_repl.conf
```

If `cdc_repl.conf` is missing or SSH credentials are absent, **stop** and explain:
> "CDC infrastructure is not configured. Edit `$CTP_HOME/conf/cdc_repl.conf` and set source/target SSH credentials and `cubrid_download_url`."

If `cubrid_download_url` is not set and the user has not provided a build URL, ask:
> "A CUBRID build URL is required. Please provide the build URL."

### 2. Identify the test file

Locate the `.sql` file in `cubrid-testcases/cdc_repl/`:

```bash
find ~/cubrid-testcases -path "*/cdc_repl/*/cases/*.sql" -name "<pattern>.sql" 2>/dev/null
```

Read the test file to understand its `--test:` and `--check:` markers. Confirm all tables have PRIMARY KEY — CDC cannot track rows without one.

### 3. Prepare temp conf

```bash
cp $CTP_HOME/conf/cdc_repl.conf /tmp/cdc_repl_runone.conf

# Set scenario to the cases/ directory containing the test
sed -i "s|^scenario=.*|scenario=<path_to_cases_dir>|" /tmp/cdc_repl_runone.conf

# Set build URL if provided by user
sed -i "s|^cubrid_download_url=.*|cubrid_download_url=<build_url>|" /tmp/cdc_repl_runone.conf
```

Replace `<path_to_cases_dir>` with the parent `cases/` directory of the `.sql` file.
Replace `<build_url>` with the user-provided URL.

### 4. Run via CTP

```bash
timeout 1200 $CTP_HOME/bin/ctp.sh cdc_repl -c /tmp/cdc_repl_runone.conf 2>&1 | tee /tmp/cdc_repl_runone.log
```

Timeout is 1200s — CDC tests require remote CUBRID install and CDC daemon startup.

### 5. Check results

```bash
ls -lt $CTP_HOME/result/cdc_repl/current_runtime_logs/
cat $CTP_HOME/result/cdc_repl/current_runtime_logs/*.log 2>/dev/null | tail -50
```

Look for `PASS` / `FAIL` summary lines. CDC verification is performed by `CheckDiff.java` which compares source and target data after replication.

### 6. Failure analysis (when FAIL)

For cdc_repl, failure means `CheckDiff.java` found a data discrepancy between source and target.

```bash
# Find the test execution log
find $CTP_HOME/result/cdc_repl/current_runtime_logs/ -name "*.log" | xargs grep -l "FAIL" 2>/dev/null

# Look for CheckDiff output
grep -A10 "CheckDiff\|FAIL\|differ\|mismatch" /tmp/cdc_repl_runone.log
```

Identify:
1. Which `--check:` query triggered the diff
2. Source result vs target result shown by CheckDiff
3. Whether `cdc_test_helper` reported an error during CDC capture
4. Whether the table had a PRIMARY KEY (required for CDC tracking)

## Output Format

**On success:**
```
[PASS] <testcase_name>
  - CheckDiff found no discrepancies between source and target
  - Summary: <what the test verified>
```

**On failure:**
```
[FAIL] <testcase_name>
  - Failed at --check: <query>
  - CheckDiff output: <diff lines>
  - Root cause: <diagnosis>
  - Suggestion: <what to fix>
```

## Common Issues

- **`cdc_repl.conf` missing or incomplete**: Stop and ask user to configure SSH credentials and build URL before proceeding.
- **Table missing PRIMARY KEY**: CDC cannot track rows without a PK — the test `.sql` must declare `PRIMARY KEY` on every table explicitly.
- **`cdc_test_helper` not built**: CDC requires the native helper built via `cdc_test_helper/build.sh` on the infrastructure nodes — run build before retrying.
- **Build URL wrong or unreachable**: CTP prints `[ERROR]` during install phase — check `/tmp/cdc_repl_runone.log` for `[ERROR]` lines.
- **LOB column replication failure**: BLOB/CLOB may not replicate correctly via CDC — check whether the failing `--check:` involves LOB columns.
