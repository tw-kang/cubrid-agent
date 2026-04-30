---
name: cubrid-ha_repl-tc-runone
description: "Executes a single CUBRID HA replication testcase (.sql with --test:/--check: markers) via CTP and reports pass/fail. Requires configured HA infrastructure (master + slave nodes). Invoke when the user asks to run a specific ha_repl test — Korean: ha_repl tc 돌려봐, ha replication 테스트 실행; English: \"run ha_repl test\". NOT for: creating tests (use cubrid-ha_repl-tc-create), running full regression."
---

# HA Replication Testcase Runner (CTP)

Run a single CTP ha_repl testcase on configured HA infrastructure and report pass/fail.

> **These tests CANNOT run on a single local machine.** They require a 3-node setup (controller, master, slave).

## Infrastructure Requirements

- Master node: SSH host/user/password configured in `$CTP_HOME/conf/ha_repl.conf`
- Slave node: SSH host/user/password configured in `$CTP_HOME/conf/ha_repl.conf`
- CUBRID build URL: required so CTP installs CUBRID on both nodes
- Config keys: `env.instance1.master.ssh.host/user/password`, `env.instance1.slave.ssh.host/user/password`

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

### 1. Verify HA infrastructure config

```bash
ls $CTP_HOME/conf/ha_repl.conf
grep -E "env.instance1.(master|slave).ssh.(host|user|password)" $CTP_HOME/conf/ha_repl.conf
grep "cubrid_download_url" $CTP_HOME/conf/ha_repl.conf
```

If `ha_repl.conf` is missing or any required key is absent, **stop** and explain:
> "HA infrastructure is not configured. Edit `$CTP_HOME/conf/ha_repl.conf` and set master/slave SSH credentials and `cubrid_download_url`."

If `cubrid_download_url` is not set and the user has not provided a build URL, ask:
> "A CUBRID build URL is required. Please provide the build URL."

### 2. Identify the test file

Locate the `.sql` file (in `cubrid-testcases/ha_repl/` or `cubrid-testcases-private/ha_repl/`):

```bash
find ~/cubrid-testcases ~/cubrid-testcases-private -path "*/ha_repl/*/cases/*.sql" -name "<pattern>.sql" 2>/dev/null
```

Read the test file to understand its `--test:` and `--check:` markers before running.

### 3. Prepare temp conf

```bash
cp $CTP_HOME/conf/ha_repl.conf /tmp/ha_repl_runone.conf

# Set scenario to the cases/ directory containing the test
sed -i "s|^scenario=.*|scenario=<path_to_cases_dir>|" /tmp/ha_repl_runone.conf

# Set build URL if provided by user
sed -i "s|^cubrid_download_url=.*|cubrid_download_url=<build_url>|" /tmp/ha_repl_runone.conf
```

Replace `<path_to_cases_dir>` with the parent `cases/` directory of the `.sql` file.
Replace `<build_url>` with the user-provided URL.

### 4. Run via CTP

```bash
timeout 1200 $CTP_HOME/bin/ctp.sh ha_repl -c /tmp/ha_repl_runone.conf 2>&1 | tee /tmp/ha_repl_runone.log
```

Timeout is 1200s — HA tests take longer because CTP installs CUBRID on remote nodes.

### 5. Check results

```bash
ls -lt $CTP_HOME/result/ha_repl/current_runtime_logs/
cat $CTP_HOME/result/ha_repl/current_runtime_logs/*.log 2>/dev/null | tail -50
```

Look for `PASS` / `FAIL` summary lines in the log output.

### 6. Failure analysis (when FAIL)

For ha_repl, failure means master and slave returned different result sets at a `--check:` point.

```bash
# Find the test execution log
find $CTP_HOME/result/ha_repl/current_runtime_logs/ -name "*.log" | xargs grep -l "FAIL" 2>/dev/null

# Look for check-point comparison output
grep -A5 "FAIL\|mismatch\|differ" /tmp/ha_repl_runone.log
```

Identify:
1. Which `--check:` query failed
2. Master result vs slave result at that point
3. Whether slave had a replication lag (data not yet replicated before check ran)
4. Any CUBRID error on master or slave node

## Output Format

**On success:**
```
[PASS] <testcase_name>
  - All --check: points matched between master and slave
  - Summary: <what the test verified>
```

**On failure:**
```
[FAIL] <testcase_name>
  - Failed at --check: <query>
  - Master result: <rows>
  - Slave result: <rows>
  - Root cause: <diagnosis>
  - Suggestion: <what to fix>
```

## Common Issues

- **`ha_repl.conf` missing or incomplete**: Stop and ask user to configure SSH credentials and build URL before proceeding.
- **Build URL wrong or unreachable**: CTP prints `[ERROR]` during install phase — check `/tmp/ha_repl_runone.log` for `[ERROR]` lines.
- **Slave replication lag at `--check:`**: Ensure `--test: COMMIT;` precedes every `--check:` block in the `.sql` file.
- **Timeout (exit 124)**: HA setup involves remote CUBRID install; increase timeout or check network connectivity to slave node.
- **Table has no PRIMARY KEY**: CTP auto-adds one via `migrate/Convert.java`, but explicit PKs are safer — review the `.sql` file.
