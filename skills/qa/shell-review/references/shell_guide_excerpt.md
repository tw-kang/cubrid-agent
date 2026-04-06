# CTP Shell Guide Key Points

From `cubrid-testtools/doc/shell_guide.md`

## Directory Layout

```
shell/{category}/{test_name}/cases/{test_name}.sh
```

New features: `shell/_{no}_{release_code}/cbrd_xxxxx_{feature}/cases/cbrd_xxxxx_{feature}.sh`
Bug fixes: `shell/_06_issues/_{yy}_{1|2}h/cbrd_xxxxx/cases/cbrd_xxxxx.sh`

## Required Template

```bash
#!/bin/sh
# CBRD-XXXXX: Brief description of what this test verifies
. $init_path/init.sh
init test

dbname=tmpdb
cubrid_createdb $dbname

# Test steps...

if [ condition ]; then
    write_ok
else
    write_nok
fi

cubrid service stop
cubrid deletedb $dbname
finish
```

## Lifecycle Contract

1. `. $init_path/init.sh` — source helpers
2. `init test` — initialize environment
3. `write_ok` / `write_nok` — report result
4. `finish` — cleanup (restores configs, stops services, removes temp files)

## Platform Exclusion Macros

Place before init.sh sourcing:
```bash
WINDOWS_NOT_SUPPORTED
LINUX_NOT_SUPPORTED
AIX_NOT_SUPPORTED
```

## Configuration Management

Use helpers (`change_db_parameter`, `change_broker_parameter`, `change_ha_parameter`) instead of direct file edits. Changes are auto-tracked and reverted by `finish`.

## Process Management

- Use `xkill` over raw `kill` — user-scoped, cross-platform
- Track background processes (`&`) with `wait $pid`
- `finish` includes `pkill cub` as safety net

## Output Stability

Normalize volatile content before comparison:
- `format_csql_output` — strips timing
- `format_query_plan` — normalizes plans
- `format_path_output` — normalizes paths
- `compare_result_between_files` — handles version compatibility
