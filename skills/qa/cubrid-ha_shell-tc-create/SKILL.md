---
name: cubrid-ha_shell-tc-create
description: "Use this skill whenever the user wants to create, draft, write, or scaffold a new HA shell testcase (.sh) for CUBRID CTP. This is the right skill any time someone needs a new HA replication test script produced from scratch for a CBRD issue. Common requests: \"ha shell tc 만들어줘\", \"ha shell tc 초안 작성해줘\", \"create ha shell tc\", \"draft HA shell test\", \"새 ha 테스트케이스\", \"HA shell 테스트케이스 작성\", \"create draft ha shell tc for CBRD-XXXXX\". NOT for: regular shell tests (use cubrid-shell-tc-create), ha_repl SQL-format tests (use cubrid-ha_repl-tc-create), debugging existing HA tests, or CTP configuration."
---

# HA Shell Testcase Creator (CTP)

Generate well-formed CUBRID CTP HA shell testcase scripts for high-availability replication testing.

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
# Verify HA helpers exist
ls $CTP_HOME/shell/init_path/make_ha.sh
ls $CTP_HOME/shell/init_path/ha_common.sh
```

If `make_ha.sh` is not found, stop and display:

> "CTP HA helpers not found. HA shell tests require make_ha.sh in CTP/shell/init_path/.
> Installation: `git clone https://github.com/CUBRID/cubrid-testtools.git`"

## JIRA Issue Context (do this when a CBRD-XXXXX is referenced)

When the request includes a `CBRD-XXXXX` ticket, **invoke the `jira` skill first** to fetch the issue background — title, description, reproduction steps, affected components, and comments — before generating the testcase. This grounds the test in the issue's actual requirements rather than guesswork.

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

   Use the summary, description, and comments to drive the testcase scope, expected behavior, and edge cases.

3. **If missing** — **halt and ask the user**:

   > The `jira` skill is required to fetch CBRD-XXXXX context for accurate testcase generation, but it is not installed. May I install it from this repo (`tw-kang/skills`) now?
   > Suggested: `npx skills add tw-kang/skills -s jira -a claude-code`

   Wait for explicit confirmation. If the user declines, proceed without JIRA context and warn them that issue-specific details may be missing.

4. **No CBRD-XXXXX in the request** — skip this section.

## HA Shell vs Regular Shell Tests

| Aspect | Regular Shell | HA Shell |
|--------|--------------|----------|
| Shebang | `#!/bin/sh` | `#!/bin/bash` (always) |
| Helper files | `. $init_path/init.sh` | `. $init_path/init.sh` + `. $init_path/make_ha.sh` |
| DB setup | `cubrid_createdb $dbname` | `setup_ha_environment` |
| DB name | Any name | Always `hatestdb` (set by make_ha.sh) |
| Remote exec | Not needed | `run_on_slave -c "cmd"` |
| Cleanup | `cubrid deletedb $dbname` | `revert_ha_environment` |
| Testcases dir | `shell/` in cubrid-testcases | `HA/shell/` in cubrid-testcases-private |

## Directory Path Convention

HA shell testcases live in **`cubrid-testcases-private/HA/shell/`** (not `cubrid-testcases`).

### Bug fixes
```
HA/shell/_12_bts_issue/<bug_id>/cases/<bug_id>.sh
HA/shell/_16_bts_issue/<bug_id>/cases/<bug_id>.sh
```
Use `cbrd_XXXXX` naming for CBRD issues.

### New features (use the appropriate release directory)
```
HA/shell/_31_cherry/<feature_name>/cases/<feature_name>.sh
HA/shell/_36_damson/<feature_name>/cases/<feature_name>.sh
HA/shell/_37_elderberry/<feature_name>/cases/<feature_name>.sh
HA/shell/_38_fig/<feature_name>/cases/<feature_name>.sh
HA/shell/_39_fig_cake/<feature_name>/cases/<feature_name>.sh
```

Multiple tests for the same issue:
```
HA/shell/_12_bts_issue/cbrd_XXXXX/cbrd_XXXXX_1/cases/cbrd_XXXXX_1.sh
HA/shell/_12_bts_issue/cbrd_XXXXX/cbrd_XXXXX_2/cases/cbrd_XXXXX_2.sh
```

## HA Lifecycle Contract

Every HA shell testcase must follow this exact sequence:

```bash
#!/bin/bash
# CBRD-XXXXX: Brief description of what this HA test verifies
# HA config: 1 master + 1 slave
# Tests: <HA behavior being verified>

. $init_path/init.sh
. $init_path/make_ha.sh
init test
set -x

# --- Setup HA (creates hatestdb on both nodes, configures HA, starts heartbeat) ---
setup_ha_environment

# --- Test phase ---
# (test logic here)

# --- Verify phase ---
if [ condition ]; then
    write_ok
else
    write_nok
fi

# --- Cleanup ---
revert_ha_environment
finish
```

### Phase details

**Shebang + summary**: Always `#!/bin/bash` (HA helpers require bash). Comment block: issue ID, what the test verifies, HA config.

**Source and init**:
- `. $init_path/init.sh` — CTP core helpers (write_ok, write_nok, format_csql_output, finish)
- `. $init_path/make_ha.sh` — HA helpers (reads HA.properties, defines run_on_slave, sources make_ha_upper.sh)
- `init test` — initializes CTP test logging; `set -x` — enables debug output

**`setup_ha_environment`**: Creates `hatestdb` on master AND slave, modifies and uploads `cubrid.conf`/`cubrid_ha.conf`/`cubrid_broker.conf`, starts heartbeat on both nodes, waits for active mode, auto-sets `masterHostName`/`slaveHostName`.

**Test logic**: Execute DML on master, use `wait_for_slave` before comparing, use `run_on_slave -c "..."` for all remote execution (never raw ssh).

**Cleanup**: `revert_ha_environment` destroys hatestdb on both nodes and reverts all config files. `finish` must be the last call.

## HA Helper Functions Reference

### Setup and Teardown
| Function | Source | Purpose |
|----------|--------|---------|
| `setup_ha_environment` | make_ha_upper.sh | Create DB on both nodes, configure HA, start heartbeat |
| `revert_ha_environment` | make_ha_upper.sh | Destroy DB on both nodes, revert config files |

### Remote Execution (aliases in make_ha.sh)
| Alias | Purpose |
|-------|---------|
| `run_on_slave -c "cmd"` | Execute shell command on slave node |
| `run_on_slave -initfile $init_path/ha_common.sh -c "func_name arg"` | Execute with ha_common.sh functions available |
| `run_upload_on_slave -from <local> -to <remote>` | Upload file to slave |
| `run_download_on_slave -from <remote> -to <local>` | Download file from slave |

### HA Service Control
| Function | Source | Purpose |
|----------|--------|---------|
| `stop_slave_hb` | make_ha_upper.sh | Stop heartbeat on slave (`cubrid hb stop`) |
| `start_slave_hb` | make_ha_upper.sh | Start heartbeat on slave (`cubrid hb start`) |
| `stop_slave_service` | make_ha_upper.sh | Stop CUBRID service on slave (`cubrid service stop`) |
| `stop_ha_master` | make_ha_upper.sh | Stop HA master node |

### Wait/Polling
| Function | Source | Purpose |
|----------|--------|---------|
| `wait_for_slave` | make_ha_upper.sh | Wait for DML replication to slave (creates/drops a sentinel table) |
| `wait_for_slave_failover` | make_ha_upper.sh | Wait for replication after failover (slave→master direction) |
| `wait_for_active` | ha_common.sh | Wait for master to reach active HA mode |
| `wait_for_slave_active` | ha_common.sh | Wait for slave to become active (new master after failover) |

### Config Modification (auto-reverted by `revert_ha_environment`)
| Function | Purpose |
|----------|---------|
| `modify_cubrid_conf $CUBRID/conf/cubrid.conf` | Modify cubrid.conf and upload to slave |
| `modify_cubrid_ha $CUBRID/conf/cubrid_ha.conf` | Modify cubrid_ha.conf and upload to slave |
| `modify_cubrid_broker_conf $CUBRID/conf/cubrid_broker.conf` | Modify broker config |

### Key Variables (set automatically)
| Variable | Value |
|----------|-------|
| `masterHostName` | Local hostname (master node) — set by `setup_ha_environment` |
| `slaveHostName` | Remote slave hostname — set by `setup_ha_environment` |
| `dbname` | `hatestdb` (always, set by make_ha.sh) |
| `currentPath` | Working directory at script start (set by make_ha.sh) |

## Common HA Test Patterns

### Replication verification
```bash
# 1. Create table and insert data on master
csql -udba $dbname -c "
CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
INSERT INTO t1 VALUES (1, 'data');
COMMIT;
"

# 2. Wait for replication to complete
wait_for_slave

# 3. Compare master vs slave data
csql -udba $dbname@$masterHostName -c "SELECT * FROM t1 ORDER BY id;" > master.log
run_on_slave -c "csql -udba $dbname -c \"SELECT * FROM t1 ORDER BY id;\"" > slave.log

format_csql_output master.log
format_csql_output slave.log
compare_result_between_files master.log slave.log
```

### Failover test (kill master, slave becomes new master)
```bash
# Stop master heartbeat (simulate failure)
kill -19 $(pgrep -u $USER cub_server)

# Wait for slave to be promoted
wait_for_slave_active > slave_status.log
if grep -q "current HA running mode is active" slave_status.log; then
    write_ok
else
    write_nok
fi

# Restore master
kill -18 $(pgrep -u $USER cub_server)
```

### Config change test
```bash
# Modify config before setup (setup_ha_environment applies the changes)
echo "ha_ping_hosts=127.0.0.1" >> $CUBRID/conf/cubrid_ha.conf
setup_ha_environment
# ... test ...
revert_ha_environment  # automatically reverts cubrid_ha.conf
```

### Running ha_common.sh functions on slave
```bash
# To use functions defined in ha_common.sh on slave, use -initfile:
run_on_slave -initfile $init_path/ha_common.sh -c "cleanup $dbname"
```

## Writing Rules

1. **`#!/bin/bash`** — always bash, never `#!/bin/sh`
2. **Source order**: `init.sh` first, then `make_ha.sh`
3. **`dbname=hatestdb`** — never use a different DB name; it's set by make_ha.sh
4. **`setup_ha_environment` before any DB operations** — never call `cubrid createdb` manually
5. **`revert_ha_environment` before `finish`** — never skip cleanup
6. **`run_on_slave` for remote commands** — never raw ssh; credentials come from HA.properties
7. **`wait_for_slave` before comparing** — always wait for replication before reading slave
8. **No hardcoded hostnames or IPs** — use `$masterHostName`, `$slaveHostName`
9. **No hardcoded absolute paths** — use `$CUBRID`, `$currentPath`, `$init_path`
10. **Bounded loops** — never `while true`; use `for ((i=0; i<N; i++))` with a limit

## Generation Checklist

- `#!/bin/bash`?
- Both `init.sh` AND `make_ha.sh` sourced?
- `setup_ha_environment` called before DB ops?
- `wait_for_slave` before master/slave comparison?
- `run_on_slave` (not ssh) for remote commands?
- `$masterHostName`/`$slaveHostName` (not hardcoded)?
- `revert_ha_environment` before `finish`?

## Examples

- `@examples/ha_replication_verify.sh` — INSERT/UPDATE/DELETE replication with master/slave comparison
- `@examples/ha_failover_test.sh` — Failover scenario: kill master, verify slave promotion

## References

- `~/cubrid-testtools/CTP/shell/init_path/make_ha.sh` — HA entry: reads HA.properties, defines run_on_slave aliases, sources make_ha_upper.sh
- `~/cubrid-testtools/CTP/shell/init_path/make_ha_upper.sh` — setup_ha_environment, revert_ha_environment, wait_for_slave, failover helpers
- `~/cubrid-testtools/CTP/shell/init_path/ha_common.sh` — cleanup, wait_for_active, wait_for_slave_active
- `~/cubrid-testtools/CTP/shell/init_path/init.sh` — CTP core helpers: write_ok, write_nok, format_csql_output, finish
- `~/cubrid-testcases-private/HA/shell/` — Existing HA shell testcases for reference
