---
name: ha-shell-create
description: Use this skill whenever the user wants to create, draft, write, or scaffold a new HA shell testcase (.sh) for CUBRID CTP HA replication testing. This is the right skill any time someone needs a new HA test script produced from scratch for a CBRD issue involving high availability, replication, failover, or master/slave behavior. Common requests: "ha shell tc 만들어줘", "ha-shell testcase 작성해줘", "ha shell tc 초안", "HA shell test 작성", "create ha shell tc", "draft HA shell test for CBRD-XXXXX". Users typically mention a CBRD issue number, HA scenario (replication lag, failover, log check), and the number of nodes required. NOT for: regular (non-HA) shell tests, SQL/MEDIUM/JDBC testcases, CTP configuration, or debugging existing HA tests.
---

# HA Shell Testcase Creator (CTP)

Generate well-formed CUBRID CTP HA shell testcase scripts for replication and high-availability testing.

## Prerequisites — CTP Installation Check (mandatory first step)

**Before executing this skill, verify CTP is installed and HA helpers exist:**

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
ls $CTP_HOME/shell/init_path/init.sh
ls $CTP_HOME/shell/init_path/init_ext.sh
```

If `init_ext.sh` is not found, **stop immediately** and display:

> "CTP HA helpers (init_ext.sh) are not installed. This skill cannot proceed.
> Installation methods:
> - Option 1: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> - Option 2: `git clone https://github.com/CUBRID/cubrid-testtools.git` and use `~/cubrid-testtools/CTP` directly"

**Proceed only after both `init.sh` and `init_ext.sh` are confirmed.**

## Quick Start

1. Gather context: JIRA issue ID, HA scenario (replication, failover, log check), number of nodes needed.
2. Determine directory path under `shell_ext/HA/`.
3. Generate the script following the HA lifecycle contract and conventions below.
4. Output the directory path and file content.

## How HA Shell Tests Differ from Regular Shell Tests

| Aspect | Regular Shell Test | HA Shell Test |
|--------|-------------------|---------------|
| Shebang | `#!/bin/sh` (default) | `#!/bin/bash` (ALWAYS — HA tests use bash features) |
| Init source | `. $init_path/init.sh` only | `. $init_path/init.sh` AND `. $init_path/init_ext.sh` |
| DB creation | `cubrid_createdb $dbname` | `cubrid_ha_create -s D_HOST1` |
| DB name | any name | **always `hatestdb`** (CTP HA convention) |
| Remote exec | N/A | `rexec D_HOST1 -c "cmd"` |
| Polling | bounded sleep loop | `rexec D_HOST1 -tillcontains "text" -maxattempts N -interval N` |
| Cleanup | `cubrid server stop` + `cubrid deletedb` | `cubrid_ha_stop` + `cubrid_service_stop` + `cubrid_ha_destroy` |
| Directory | `shell/_06_issues/...` | `shell_ext/HA/...` |

## Directory Path Convention

HA testcases live under the `shell_ext/HA/` tree of `cubrid-testcases-private`:

### Single test per bug
```
shell_ext/HA/<bug_id>/cases/<bug_id>.sh
```

Examples:
- `shell_ext/HA/bug_bts_10344/cases/bug_bts_10344.sh`
- `shell_ext/HA/cbrd_12345/cases/cbrd_12345.sh`

### Multiple tests for same bug
```
shell_ext/HA/<bug_id>/<bug_id>_1/cases/<bug_id>_1.sh
shell_ext/HA/<bug_id>/<bug_id>_2/cases/<bug_id>_2.sh
```

### CBRD issue tests
```
shell_ext/HA/cbrd_XXXXX/cases/cbrd_XXXXX.sh
```

The directory name and script filename must match: `test_name/cases/test_name.sh`.

## HA Infrastructure Requirements

State in a comment block at the top how many nodes the test needs:

- **1 master + 1 slave**: `cubrid_ha_create -s D_HOST1`
- **1 master + 2 slaves**: `cubrid_ha_create -s D_HOST1,D_HOST2`
- **1 master + 2 slaves + 1 replica**: `cubrid_ha_create -s D_HOST1,D_HOST2 -r D_HOST3`

Node placeholders (replaced at runtime by CTP framework):
- `D_HOST1` — first slave node
- `D_HOST2` — second slave node
- `D_HOST3` — third node (additional slave or replica)

## HA Lifecycle Contract

Every HA entry script must follow this exact sequence. Missing any step will fail review.

```bash
#!/bin/bash
# CBRD-XXXXX: Brief description of what this HA test verifies
# Tests: <HA behavior being tested>
# Requires: 1 master + 1 slave (D_HOST1)

set -x
. $init_path/init.sh
. $init_path/init_ext.sh
init test

curPwd=`pwd`
db_name=hatestdb
host1=`hostname`
host2=`rexec D_HOST1 -c "hostname"`

# --- Setup HA ---
cubrid_ha_create -s D_HOST1
cubrid_ha_start
cubrid broker start

# --- Test ---
# (test logic here)

# --- Verify ---
if [ condition ]; then
    write_ok
else
    write_nok
fi

# --- Cleanup ---
cubrid_ha_stop
cubrid_service_stop
cubrid_ha_destroy
finish
```

### Phase details

**1. Shebang + summary comment**
- Always `#!/bin/bash` — HA tests use bash features (`[[ ]]`, process substitution, etc.)
- Comment block immediately after shebang: issue ID, what the test verifies, node requirements
- `set -x` for debugging output (placed after shebang, before or after sourcing init files)

**2. Source and init**
- `. $init_path/init.sh` — loads CTP helper functions
- `. $init_path/init_ext.sh` — loads HA-specific helpers (REQUIRED — this is what separates HA tests)
- `init test` — initializes the test environment

**3. Host and environment variables**
- Always capture hostnames at the top: `host1=\`hostname\`` and `host2=\`rexec D_HOST1 -c "hostname"\``
- `curPwd=\`pwd\`` for referencing local files passed to remote commands
- `db_name=hatestdb` — always use this exact name

**4. HA Setup (strict order)**
1. `cubrid_ha_create -s D_HOST1` — creates the HA DB on master + slaves
2. `cubrid_ha_start` — starts HA cluster (master + slaves)
3. `cubrid broker start` — start broker after HA is up

**5. Test logic**
- Use `wait_replication_done` before comparing master/slave data
- Remote commands via `rexec`, never raw `ssh`
- Upload files to remote via `r_upload`
- Poll remote state with `-tillcontains`/`-maxattempts`/`-interval`
- Keep SQL inline via heredocs

**6. Verify**
- `write_ok` / `write_nok` for each check point
- Or `compare_result_between_files <answer> <result>`

**7. Cleanup (strict order)**
1. `cubrid_ha_stop` — stop HA cluster
2. `cubrid_service_stop` — stop CUBRID service on local node
3. `cubrid_ha_destroy` — destroy DB and clean up on all nodes
4. Remove temp files
5. `finish` — must be last call

## HA Helper Functions Reference

### Infrastructure lifecycle

| Helper | Purpose |
|--------|---------|
| `cubrid_ha_create -s D_HOST1` | Create HA DB on local (master) + D_HOST1 (slave) |
| `cubrid_ha_create -s D_HOST1,D_HOST2` | Create with two slaves |
| `cubrid_ha_create -s D_HOST1,D_HOST2 -r D_HOST3` | Create with two slaves + one replica |
| `cubrid_ha_start` | Start HA cluster (master + all slaves) |
| `cubrid_ha_stop` | Stop HA cluster |
| `cubrid_service_stop` | Stop CUBRID service on local node |
| `cubrid_ha_destroy` | Destroy HA DB and clean up on all nodes |

### Remote execution

| Helper | Purpose |
|--------|---------|
| `rexec D_HOST1 -c "cmd"` | Execute command on remote host |
| `rexec D_HOST1 -f script.sh` | Execute local script file on remote host |
| `rexec D_HOST1 -c "cmd" -tillcontains "text" -maxattempts 180 -interval 2` | Poll until output contains text |
| `r_upload D_HOST1 -from <local> -to <remote>` | Upload local file to remote host |

### Replication helpers

| Helper | Purpose |
|--------|---------|
| `wait_replication_done` | Wait until replication is fully caught up |

### Standard CTP helpers (also available in HA tests)

| Helper | Purpose |
|--------|---------|
| `write_ok` | Record test passed |
| `write_nok [file\|message]` | Record test failed |
| `compare_result_between_files <answer> <result>` | Diff two files, auto-calls write_ok/write_nok |
| `format_csql_output <file>` | Strip timing/CAS info from csql output |
| `change_db_parameter "key=value"` | Change cubrid.conf, auto-reverted by finish |
| `change_broker_parameter "key=value"` | Change broker conf, auto-reverted by finish |
| `get_broker_port_from_shell_config` | Get broker port from runtime config |

## Writing Rules

### Bash not sh
- Always `#!/bin/bash` — never `#!/bin/sh` for HA tests
- bash features are expected and used (process substitution, `[[ ]]`, `let`, etc.)

### Database name
- Always use `hatestdb` — this is a hard CTP HA convention, not a suggestion
- Variable: `db_name=hatestdb` (or `db_name="hatestdb"`)

### init_ext.sh is mandatory
- Never omit `. $init_path/init_ext.sh` — without it all `cubrid_ha_*` and `rexec` helpers are undefined
- Source order: `init.sh` first, then `init_ext.sh`

### Remote commands via rexec
- Never use raw `ssh host cmd` — always `rexec D_HOST1 -c "cmd"`
- Never hardcode hostnames — use `D_HOST1`, `D_HOST2` placeholders
- For multi-line remote scripts, write to a local `.sh` file and use `rexec D_HOST1 -f script.sh`

### Replication synchronization
- Always call `wait_replication_done` before reading slave data for comparison
- Never assume replication is instant — a missing `wait_replication_done` causes flaky tests

### Polling over sleep
- Use `-tillcontains "text" -maxattempts N -interval N` for HA state checks
- Avoid `sleep` for waiting on HA state transitions
- `sleep` is acceptable only for fixed delays (e.g., giving a Java process time to insert rows)

### Cleanup ordering
HA cleanup must follow this exact sequence to avoid leaving orphan processes or DB files:
1. `cubrid_ha_stop`
2. `cubrid_service_stop`
3. `cubrid_ha_destroy`
4. Remove temp files (`.log`, `.class`, `.sh` scripts)
5. `finish`

### No hardcoded paths
- Never use `/home/...`, `/opt/...`
- Use `$CUBRID`, `$curPwd` (captured via `pwd`), `$init_path`, or relative paths
- Temp files go to `$curPwd` (current test dir), not `/tmp`

### Inline SQL
- Keep SQL in heredocs inside the shell script — never in separate `.sql` files
- Use single-quoted delimiter to prevent variable expansion: `<<'EOF'`

### Error handling
- Check exit codes for critical operations: `cubrid_ha_start`, `cubrid broker start`, `csql`
- Every code path must reach `finish`

## Common HA Test Patterns

### Pattern 1: Replication verify (INSERT master → check slave)

```bash
# Insert on master
csql -udba $db_name@$host1 <<'EOF'
CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
INSERT INTO t1 VALUES (1, 'master_data');
COMMIT;
EOF

wait_replication_done

# Read from master
csql -udba $db_name@$host1 -c "SELECT * FROM t1 ORDER BY id;" > master.log 2>&1
format_csql_output master.log

# Read from slave via rexec
cat <<EOF > sql.sh
csql -udba $db_name@$host2 -c "SELECT * FROM t1 ORDER BY id;"
EOF
rexec D_HOST1 -f "sql.sh" > slave.log 2>&1
format_csql_output slave.log

compare_result_between_files master.log slave.log
```

### Pattern 2: Failover (kill/stop master process, slave becomes master)

```bash
# Stop master heartbeat to trigger failover
mpid=`ps ux | grep cub_master | grep -v grep | awk '{print $2}'`
kill -STOP $mpid

# Poll slave until it reports as master
rexec D_HOST1 -c "cubrid hb status" \
    -tillcontains "state master" -maxattempts 180 -interval 2 > slave_status.txt

ismasterforslave=`grep "state master" slave_status.txt | grep "$host2" | wc -l`
if [ $ismasterforslave -gt 0 ]; then
    write_ok
else
    write_nok
fi

# Resume master
kill -CONT $mpid
```

### Pattern 3: HA log check (grep error/warning in HA logs)

```bash
cat <<EOF > check_log.sh
grep "target message" $CUBRID/log/${host2}_master.err
EOF

rexec D_HOST1 -f "check_log.sh" \
    -tillcontains "target message" -maxattempts 180 -interval 2 > ha_log_check.txt

if [ `grep "target message" ha_log_check.txt | wc -l` -ne 0 ]; then
    write_ok
else
    write_nok
fi
```

### Pattern 4: Row count consistency after failover/recovery

```bash
wait_replication_done

mcount=`csql -udba -l -c 'select count(*) from t1' $db_name@localhost \
    | grep count | awk -F ':' '{print $2}' | tr -d ' '`

cat <<EOF > sql_count.sh
csql -udba -l -c 'select count(*) from t1' $db_name@localhost
EOF
rexec D_HOST1 -f "sql_count.sh" > slave_count.txt
scount=`cat slave_count.txt | grep count | awk -F ':' '{print $2}' | tr -d ' '`

if [ $mcount -eq $scount ]; then
    write_ok
else
    write_nok
fi
```

## Generation Process

When the user requests an HA testcase, follow this process:

1. **Clarify the test target**: Ask for the JIRA issue ID (CBRD-XXXXX or bug_bts_XXXXX), the HA scenario (replication, failover, log check, multi-slave), and the number of nodes required if not provided.

2. **Determine the directory path**: Always under `shell_ext/HA/`, using `bug_bts_XXXXX` or `cbrd_XXXXX` naming.

3. **Generate the script**: Follow the HA lifecycle contract strictly. Include:
   - `#!/bin/bash` shebang (never sh)
   - Shebang-top comment: issue ID, scenario, node requirements
   - `set -x` for debug output
   - Both `init.sh` and `init_ext.sh` sourced
   - `init test` call
   - `curPwd`, `db_name=hatestdb`, `host1`, `host2` variables
   - All lifecycle phases (ha_create → ha_start → broker start → test → verify → ha_stop → ha_destroy → finish)
   - `wait_replication_done` before any master/slave data comparison
   - `rexec` for all remote commands (never ssh)
   - `-tillcontains` polling for HA state checks (not sleep loops)
   - Cleanup in strict order

4. **Review your own output**: Before presenting, check:
   - `#!/bin/bash` present?
   - Both `init.sh` and `init_ext.sh` sourced?
   - `init test` called?
   - `db_name=hatestdb`?
   - `host1` and `host2` captured?
   - `cubrid_ha_create` → `cubrid_ha_start` → `cubrid broker start` order?
   - `wait_replication_done` before slave data reads?
   - `rexec` used for all remote commands?
   - `write_ok`/`write_nok` for each assertion?
   - Cleanup: `cubrid_ha_stop` → `cubrid_service_stop` → `cubrid_ha_destroy` → temp file cleanup → `finish`?
   - No hardcoded paths?

5. **Present the output**: Show the full directory path and script content. Briefly explain the test strategy (what HA behavior is exercised and how it is verified).

## Examples

See `@examples/` for complete working examples:
- `@examples/ha_replication_verify.sh` — INSERT replication master→slave with data consistency check
- `@examples/ha_failover_test.sh` — failover scenario: kill master process, verify slave promotes, verify data consistency

## References

- `cubrid-testtools/CTP/shell/init_path/init_ext.sh` — HA helpers source (reference only)
- `cubrid-testtools/CTP/shell/init_path/init.sh` — CTP helpers source (reference only)
- `cubrid-testcases-private/shell_ext/HA/` — existing HA testcase examples
