# CTP Helper Functions Reference

From `cubrid-testtools/CTP/shell/init_path/init.sh`

## Lifecycle

| Function | Purpose |
|----------|---------|
| `init test` | Initialize test environment (must be first call after sourcing init.sh) |
| `init answer` | Answer-creation mode (generates .answer files instead of comparing) |
| `finish` | Cleanup: stop services, restore configs, remove temp files |

`finish` internally calls: `cubrid service stop` → `pkill cub` → `release_broker_sharedmemory` → `delete_ini` → `restore_all_conf`

## Database Operations

| Function | Purpose |
|----------|---------|
| `cubrid_createdb [-r] <dbname> [options]` | Create DB with CTP compatibility (charset handling, env setup) |
| `cubrid deletedb <dbname>` | Delete DB with core/fatal error checking and backup |

Always use `cubrid_createdb` over raw `cubrid createdb` — it handles locale parameter compatibility across CUBRID versions.

## Configuration

| Function | Purpose |
|----------|---------|
| `change_db_parameter "key=value"` | Modify cubrid.conf (auto-reverted by `finish`) |
| `change_broker_parameter "key=value"` | Modify cubrid_broker.conf (auto-reverted by `finish`) |
| `change_ha_parameter "key=value"` | Modify cubrid_ha.conf (auto-reverted by `finish`) |
| `restore_all_conf` | Restore all configs (called automatically by `finish`) |

Examples:
```bash
change_db_parameter "java_stored_procedure=yes"
change_db_parameter "log_max_archives=1"
change_broker_parameter "SQL_LOG=ON"
change_broker_parameter "MAX_NUM_APPL_SERVER=5"
change_ha_parameter "ha_enable_sql_logging=true"
```

## Result Handling

| Function | Purpose |
|----------|---------|
| `write_ok` | Report test passed |
| `write_nok [file or message]` | Report test failed (attach log file or message as evidence) |
| `compare_result_between_files <answer> <result>` | Compare two files, auto-calls write_ok/write_nok |
| `make_answer_or_compare_result` | Create answer files or compare results depending on mode |

## Output Normalization

| Function | What it removes/normalizes |
|----------|---------------------------|
| `format_csql_output <file>` | Execution time (`0.006435 sec`), CAS info lines |
| `format_query_plan <file>` | Query plan volatile content |
| `format_path_output <file>` | Absolute path strings → normalized |
| `diff_ignore_lineno <f1> <f2>` | Line number differences |

Use these before `diff` or `compare_result_between_files` to avoid flaky test results.

## Process Management

| Function | Purpose |
|----------|---------|
| `xkill <pattern>` | Safe, user-scoped process kill (cross-platform) |
| `xkill -f "string"` | Kill by full command match |
| `xkill -9 <pattern>` | Force kill (last resort) |
| `xkill_pid <pid>` | Kill specific PID |
| `release_broker_sharedmemory` | Release broker shared memory |

Always prefer `xkill` over raw `kill -9` or `pkill`.

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
| `do_make_locale [force] [debug\|release] [locale]` | Cross-platform make_locale |
| `delete_make_locale` | Revert make_locale results |
| `do_make_tz [new\|extend] [release] [nocheck]` | Cross-platform make_tz |
| `revert_tz` | Revert make_tz results |

## Platform Exclusion Macros

Place before sourcing init.sh:
```bash
#!/bin/sh
WINDOWS_NOT_SUPPORTED
. $init_path/init.sh
init test
```

Available macros: `WINDOWS_NOT_SUPPORTED`, `LINUX_NOT_SUPPORTED`, `AIX_NOT_SUPPORTED`
