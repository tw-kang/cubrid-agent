# CTP Helper Functions Reference

Extracted from `cubrid-testtools/CTP/shell/init_path/init.sh`

## Lifecycle Functions

### `init [test|answer]`
Initializes the test environment.
- `init test` - Test mode: writes results to result files
- `init answer` - Answer mode: creates answer files for new tests

### `finish`
Cleans up the test environment.
```bash
function finish {
    rm -f userver.err.* uclient.err.* client.err.*
    rm -rf ./lob
    cubrid service stop
    pkill cub >/dev/null 2>&1
    release_broker_sharedmemory
    delete_ini
    restore_all_conf
    echo "[INFO] TEST STOP (`date`)"
}
```

**Must be called at end of every test case.**

## Database Operations

### `cubrid_createdb [options] <dbname>`
Creates a database with CTP compatibility.
```bash
cubrid_createdb -r $dbname
cubrid_createdb -r $dbname --db-volume-size=20M --log-volume-size=20M
```

**Why use instead of `cubrid createdb`:**
- Handles charset compatibility for legacy builds
- Sets up proper environment
- Ensures consistent behavior across CUBRID versions

### `cubrid_deletedb <dbname>`
Deletes a database with cleanup checks.
```bash
cubrid deletedb $dbname
```

**Features:**
- Checks for core files and fatal errors
- Backs up db volumes, core files, logs
- Safer than raw `cubrid deletedb`

## Configuration Helpers

### `change_db_parameter <parameter=value>`
Modifies cubrid.conf parameters.
```bash
change_db_parameter "java_stored_procedure=yes"
change_db_parameter "test_mode=yes"
```

### `change_broker_parameter <parameter=value>`
Modifies cubrid_broker.conf parameters.
```bash
change_broker_parameter "SQL_LOG=ON"
change_broker_parameter "SLOW_LOG=ON"
```

### `change_ha_parameter <parameter=value>`
Modifies cubrid_ha.conf parameters.
```bash
change_ha_parameter "ha_enable_sql_logging=true"
```

### Restoration Functions
- `delete_ini` - Restores cubrid.conf from .org backup
- `restore_broker_conf` - Restores broker config
- `restore_ha_conf` - Restores HA config
- `restore_all_conf` - Restores all configs

**Note:** `finish` automatically calls `restore_all_conf`.

## Result Handling

### `write_ok`
Reports test success.
```bash
write_ok
```

### `write_nok [file|message]`
Reports test failure.
```bash
write_nok                    # Basic failure
write_nok "timeout occurred" # With message
write_nok result.log         # Include file contents
```

### `compare_result_between_files <answer> <result>`
Compares result with expected answer.
```bash
compare_result_between_files result.answer result.log
```

**Features:**
- Automatically calls `write_ok` or `write_nok` based on comparison
- Handles version compatibility
- Normalizes output for comparison

## Output Normalization

### `format_csql_output <file>`
Removes timing information from csql output.
```bash
format_csql_output result.log
```

Removes:
- Execution time lines
- CAS info lines
- Other volatile timing data

### `format_query_plan <file>`
Normalizes query plan output.
```bash
format_query_plan result.log
```

### `format_path_output <file>`
Normalizes path strings in output.
```bash
format_path_output result.log
```

### `make_answer_or_compare_result`
Creates answer files or compares results.
```bash
make_answer_or_compare_result
```

## Process Management

### `xkill [options] <pattern>`
Safe cross-platform process termination.
```bash
xkill cub_server           # Kill by process name
xkill $pid                 # Kill by PID
xkill -f "statdump"        # Kill by full command
xkill -9 cub_server        # Force kill (last resort)
```

**Why use instead of `kill`:**
- Cross-platform support (Linux, AIX, Windows)
- User-scoped (only kills user's processes)
- Safer pattern matching

### `xkill_pid <pid>`
Kill specific PID.
```bash
xkill_pid $server_pid
```

### `release_broker_sharedmemory`
Releases broker shared memory.
```bash
release_broker_sharedmemory
```

## Utility Functions

### `get_os`
Returns operating system.
```bash
OS=`get_os`  # Returns: Linux, AIX, Windows_NT
```

### `get_broker_port_from_shell_config`
Gets broker port from shell_config.xml.
```bash
broker_port=`get_broker_port_from_shell_config`
```

### `get_cubrid_port_id`
Returns CUBRID port ID from config.
```bash
port=`get_cubrid_port_id`
```

### `count_time`
Logs test execution time.
```bash
count_time
```

## SQL Execution

### `exec_sql <dbname> <sql>`
Executes SQL via csql.
```bash
exec_sql $dbname "select * from t1"
```

### `test_exec_sql <dbname> <sql> <expected>`
Tests SQL execution with expected result.
```bash
test_exec_sql $dbname "select 1" "1"
```

### `test_exec_command <command> <expected>`
Tests command execution.
```bash
test_exec_command "cubrid server status" "Server $db"
```

## File Operations

### `diff_ignore_lineno <file1> <file2>`
Diff that ignores line numbers.
```bash
diff_ignore_lineno result.answer result.log
```

### `get_best_compat_file <base> <server_ver> <driver_ver>`
Selects best compatibility file.
```bash
answer_file=`get_best_compat_file result $srv_ver $drv_ver`
```

## Locale/Timezone

### `do_make_locale`
Cross-platform locale building.
```bash
do_make_locale $charset
```

### `delete_make_locale`
Reverts locale changes.
```bash
delete_make_locale
```

### `do_make_tz`
Cross-platform timezone building.
```bash
do_make_tz
```

### `revert_tz`
Reverts timezone changes.
```bash
revert_tz
```

## Compilation

### `xgcc [options] <source>`
Cross-platform GCC wrapper.
```bash
xgcc -o test test.c $CFLAGS $LDFLAGS
```

Supports Linux, AIX, and Windows.

## Version Management

### `version_convert_to_number <version>`
Converts version string to numeric value.
```bash
ver_num=`version_convert_to_number "10.2.1"`
```

### `parse_build_version`
Parses CUBRID build version.
```bash
parse_build_version
```

## Environment

### `setENVParam <var=value>`
Sets environment parameter.
```bash
setENVParam "LANG=en_US"
```

### `recoverENVParam`
Recovers environment parameters.
```bash
recoverENVParam
```

### `unsetENVParam <var>`
Unsets environment parameter.
```bash
unsetENVParam "LANG"
```

## Key Points

1. **Always use `cubrid_createdb`** instead of raw `cubrid createdb`
2. **Always use `xkill`** instead of raw `kill` or `kill -9`
3. **Always call `finish`** at end of test
4. **Always use `write_ok`/`write_nok`** for test results
5. **Use config helpers** (`change_db_parameter`, etc.) instead of direct file edits
6. **Normalize output** with `format_csql_output` before comparison
