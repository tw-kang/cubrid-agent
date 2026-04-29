---
name: cubrid-ha_shell-tc-runone
description: "Executes a single CUBRID HA shell testcase (.sh using make_ha.sh) on configured HA infrastructure and reports pass/fail. Requires master + slave nodes. Invoke when the user asks to run a specific HA shell test — Korean: ha shell tc 돌려봐, ha shell 테스트 실행; English: \"run ha shell test\". NOT for: creating tests (use cubrid-ha_shell-tc-create), regular shell tests (use cubrid-shell-tc-runone), running full regression."
---

# HA Shell Testcase Runner (CTP)

Run a single CTP HA shell testcase on configured HA infrastructure and report pass/fail.

> **These tests CANNOT run on a single local machine.** They require a master + slave node pair configured in HA.properties.

## Infrastructure Requirements

- Master node (local) + slave node (remote) with SSH access configured in `HA.properties`
- `$CTP_HOME/shell/init_path/make_ha.sh` must exist (HA helper scripts)
- CUBRID must be installed on both nodes (via build URL or pre-installed)
- DB name is always `hatestdb` — never changed

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

# Verify HA helpers exist
ls $CTP_HOME/shell/init_path/make_ha.sh
```

If `make_ha.sh` is not found, **stop** and display:
> "CTP HA helpers not found. HA shell tests require `make_ha.sh` in `CTP/shell/init_path/`. Install: `git clone https://github.com/CUBRID/cubrid-testtools.git`"

## Execution Steps

### 1. Verify HA infrastructure config

```bash
# Check for HA.properties (CTP reads slave SSH info from here)
find $CTP_HOME -name "HA.properties" 2>/dev/null
# Or check shell_template.conf for HA node settings
ls $CTP_HOME/conf/shell_template.conf 2>/dev/null
```

If no HA node configuration is found, **stop** and explain:
> "HA infrastructure is not configured. Ensure `HA.properties` exists with slave SSH credentials (host, user, password). HA shell tests cannot run without a configured slave node."

### 2. Identify the test file

HA shell testcases live in `cubrid-testcases-private/HA/shell/`:

```bash
find ~/cubrid-testcases-private/HA/shell -name "<pattern>.sh" -path "*/cases/*" 2>/dev/null
```

Read the `.sh` file to understand its setup/verify/cleanup phases before running.

### 3. Prepare temp conf

```bash
cat > /tmp/ha_shell_runone.conf << 'EOF'
scenario=<path_to_cases_dir>
test_category=shell
EOF
# Append HA-specific settings from shell_template.conf if present
grep -E "^(ha_|slave_|master_)" $CTP_HOME/conf/shell_template.conf >> /tmp/ha_shell_runone.conf 2>/dev/null
```

Replace `<path_to_cases_dir>` with the parent `cases/` directory of the `.sh` file.

### 4. Run via CTP

```bash
timeout 1200 $CTP_HOME/bin/ctp.sh shell -c /tmp/ha_shell_runone.conf 2>&1 | tee /tmp/ha_shell_runone.log
```

Timeout is 1200s — HA setup (`setup_ha_environment`) creates `hatestdb` on both nodes and starts heartbeat.

### 5. Check results

```bash
# Result file is in the cases/ directory
cat <path_to_cases_dir>/<testname>.result 2>/dev/null
```

Result lines: `<testname>-1 : OK` (pass) or `<testname>-1 : NOK` (fail).

Also scan the CTP log:
```bash
grep -E "OK|NOK|PASS|FAIL" /tmp/ha_shell_runone.log | tail -20
```

### 6. Failure analysis (when NOK)

HA shell failures typically occur in one of three phases: setup, test logic, or verify.

```bash
# Check execution output for errors
grep -E "ERROR|FAILED|write_nok|exit 1" /tmp/ha_shell_runone.log

# Check CUBRID server logs on master
ls -la $CUBRID/log/server/*.err 2>/dev/null
cat $CUBRID/log/server/*.err 2>/dev/null | tail -30

# Check HA heartbeat status
cubrid hb status 2>/dev/null
```

For slave-side failures, check:
```bash
# HA heartbeat and replication logs are on the slave node
# Use run_on_slave to inspect (not raw ssh):
# run_on_slave -c "cat \$CUBRID/log/server/*.err"
# run_on_slave -c "cubrid hb status"
```

Identify:
1. Which phase failed (setup / test / verify / cleanup)
2. Whether `setup_ha_environment` succeeded (both nodes running in HA mode)
3. Whether `wait_for_slave` timed out before the verify step
4. Whether the result mismatch was master vs slave data difference

## Output Format

**On success:**
```
[PASS] <testcase_name>
  - Result: <testname>-1 : OK
  - Summary: <what the HA behavior was verified>
```

**On failure:**
```
[FAIL] <testcase_name>
  - Result: <testname>-1 : NOK
  - Failed at: <phase — setup/test/verify/cleanup>
  - Root cause: <diagnosis>
  - Key logs: <relevant error lines>
  - Suggestion: <what to fix>
```

## Common Issues

- **`HA.properties` missing or slave not reachable**: `setup_ha_environment` will fail early — check SSH connectivity to the slave node and that `HA.properties` has correct credentials.
- **`make_ha.sh` not found**: CTP HA helpers must be present in `$CTP_HOME/shell/init_path/` — reinstall CTP from cubrid-testtools.
- **`setup_ha_environment` hangs**: Heartbeat startup on the slave timed out — check if CUBRID service is already running on the slave and clean up manually.
- **`wait_for_slave` timeout**: Replication did not complete in time — network latency or slave node overload; check slave CUBRID logs via `run_on_slave`.
- **Master/slave data mismatch at verify step**: A `wait_for_slave` call may be missing before the comparison — review the `.sh` file for missing sync waits.
