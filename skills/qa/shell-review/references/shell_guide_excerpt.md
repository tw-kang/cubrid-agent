# CTP Shell Guide Key Points

Extracted from `cubrid-testtools/doc/shell_guide.md`

## 1. Test Case Structure

### Required Directory Layout
```
shell/{category}/{test_name}/cases/{test_name}.sh
```

### For New Features
```
shell/_{no}_{release_code}/cbrd_xxxxx_{feature}/
shell/_{no}_{release_code}/cbrd_xxxxx_{feature}/cases/cbrd_xxxxx_{feature}.sh
```

### For Bug Fixes
```
shell/_06_issues/_{yy}_{1|2}h/cbrd_xxxxx/
shell/_06_issues/_{yy}_{1|2}h/cbrd_xxxxx/cases/cbrd_xxxxx.sh
```

## 2. Required Test Case Template

Every shell test case MUST follow this structure:

```bash
#!/bin/sh
# Description comment
. $init_path/init.sh
init test

dbname=tmpdb
cubrid_createdb $dbname

# Test steps...

# Check the result
if [ condition ]; then
    write_ok
else
    write_nok
fi

cubrid service stop
cubrid deletedb $dbname
finish
```

## 3. Key Conventions

### Initialization (MUST)
- `. $init_path/init.sh` - Sources all helper functions
- `init test` - Initializes test environment
- `init_path` environment variable points to `cubrid-testtools/CTP/shell/init_path`

### Cleanup (MUST)
- `cubrid deletedb` - Checks for core files, fatal errors, backs up logs
- `finish` - Reverts all config files to original status
- Removes temp files: `userver.err.*`, `uclient.err.*`, `client.err.*`, `./lob`
- Stops services: `cubrid service stop`, `pkill cub`
- Releases resources: `release_broker_sharedmemory`, `delete_ini`, `restore_all_conf`

### Result Reporting (MUST)
- `write_ok` - Report test passed
- `write_nok` - Report test failed (can include file: `write_nok result.log`)
- Tests without `write_ok`/`write_nok` are incomplete

## 4. Platform Support

### Macros for Platform-Specific Exclusions
- `WINDOWS_NOT_SUPPORTED` - Skip on Windows
- `LINUX_NOT_SUPPORTED` - Skip on Linux  
- `AIX_NOT_SUPPORTED` - Skip on AIX

Usage:
```bash
#!/bin/sh
WINDOWS_NOT_SUPPORTED
. $init_path/init.sh
init test
...
```

## 5. Configuration Management

### Parameter Change Helpers (USE THESE)
- `change_db_parameter` - Modify cubrid.conf
- `change_broker_parameter` - Modify cubrid_broker.conf
- `change_ha_parameter` - Modify cubrid_ha.conf

### Why Use Helpers
- Changes are automatically tracked and reverted
- No manual config file editing needed
- Ensures clean state between tests

## 6. Process Management

### Safe Process Termination
- Use `xkill` helper instead of raw `kill`
- `xkill cub_server` - Kill by process name
- `xkill $pid` - Kill by PID
- `xkill -f "statdump"` - Kill by full command match

### Orphan Prevention
- Background processes (`&`) must be tracked and cleaned up
- `wait $pid` - Wait for background process to prevent orphan
- `finish` function includes `pkill cub` for cleanup

## 7. Output Stability

### Normalization Helpers
- `format_csql_output` - Removes timing information
- `format_query_plan` - Normalizes query plan output
- `format_path_output` - Normalizes path strings
- `compare_result_between_files` - Compares with answer files

### Why Normalize
- Timestamps, PIDs, paths vary between runs
- Normalization ensures stable test results
- Required for reliable automated testing
