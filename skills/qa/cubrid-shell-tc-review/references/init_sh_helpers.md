# CTP Helper Functions Reference

From `cubrid-testtools/CTP/shell/init_path/init.sh`

## Lifecycle

| Function | Purpose |
|----------|---------|
| `init test` | Initialize test environment (must be first call) |
| `init answer` | Answer-creation mode |
| `finish` | Cleanup: stop services, restore configs, remove temp files |

`finish` calls: `cubrid service stop` → `pkill cub` → `release_broker_sharedmemory` → `delete_ini` → `restore_all_conf`

## Database Operations

| Function | Purpose |
|----------|---------|
| `cubrid_createdb [-r] <dbname> [options]` | Create DB with CTP compatibility (charset handling, env setup) |
| `cubrid deletedb <dbname>` | Delete DB with core/fatal error checking |

Always use `cubrid_createdb` over raw `cubrid createdb`.

## Configuration

| Function | Purpose |
|----------|---------|
| `change_db_parameter "key=value"` | Modify cubrid.conf (auto-reverted by `finish`) |
| `change_broker_parameter "key=value"` | Modify cubrid_broker.conf |
| `change_ha_parameter "key=value"` | Modify cubrid_ha.conf |
| `restore_all_conf` | Restore all configs (called by `finish`) |

## Result Handling

| Function | Purpose |
|----------|---------|
| `write_ok` | Report test passed |
| `write_nok [file or message]` | Report test failed |
| `compare_result_between_files <answer> <result>` | Compare and auto-call write_ok/write_nok |
| `make_answer_or_compare_result` | Create answer files or compare results |

## Output Normalization

| Function | What it removes/normalizes |
|----------|---------------------------|
| `format_csql_output <file>` | Execution time, CAS info lines |
| `format_query_plan <file>` | Query plan volatile content |
| `format_path_output <file>` | Absolute path strings |
| `diff_ignore_lineno <f1> <f2>` | Line number differences |

Use these before `diff` or `compare_result_between_files` to avoid flaky results.

## Process Management

| Function | Purpose |
|----------|---------|
| `xkill <pattern>` | Safe, user-scoped process kill (cross-platform) |
| `xkill -f "string"` | Kill by full command match |
| `xkill -9 <pattern>` | Force kill (last resort) |
| `xkill_pid <pid>` | Kill specific PID |
| `release_broker_sharedmemory` | Release broker shared memory |

Always prefer `xkill` over raw `kill -9`.

## SQL Execution

| Function | Purpose |
|----------|---------|
| `exec_sql <dbname> <sql>` | Execute SQL via csql |
| `test_exec_sql <dbname> <sql> <expected>` | Execute and assert result |
| `test_exec_command <cmd> <expected>` | Execute command and assert output |

## Utility

| Function | Purpose |
|----------|---------|
| `get_os` | Returns: Linux, AIX, Windows_NT |
| `get_broker_port_from_shell_config` | Broker port from shell_config.xml |
| `get_cubrid_port_id` | CUBRID port from config |
| `xgcc [options] <source>` | Cross-platform GCC wrapper |
