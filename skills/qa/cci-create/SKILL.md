---
name: cci-create
description: Use this skill whenever the user wants to create, draft, write, or scaffold a new CCI testcase for CUBRID CTP. This is the right skill any time someone needs a new CCI (C Client Interface) test script and C source file. Common requests: "cci tc 만들어줘", "cci 테스트케이스 작성", "create cci testcase", "draft cci test for CBRD-XXXXX", "새 cci 테스트케이스". NOT for: cci_compatibility tests (use cci-compatibility-create), JDBC tests (use jdbc-create), regular shell tests (use shell-create).
---

# CCI Testcase Creator (CTP)

Generate well-formed CUBRID CTP CCI testcase scripts (shell + C source + answer file).

## What is a CCI Test?

CCI (C Client Interface) tests verify CUBRID's C-language client driver (`libcascci`). Each test consists of:
- A **shell script** (`.sh`) — sets up DB, compiles C code, runs the binary, checks output
- A **C source file** (`test.c`) — contains the actual CCI API calls
- An **answer file** (`.answer`) — expected output for `compare_result_between_files` (simple tests only)

## Quick Start

1. Gather context: JIRA issue ID (if bug fix), CCI API(s) being tested, expected behavior.
2. Choose test pattern: **simple** (output comparison) or **issue** (explicit pass/fail check).
3. Determine directory path.
4. Generate shell script + test.c (+ answer file if simple pattern).
5. Output the directory path and file contents.

## Directory Path Convention

CCI testcases live in **`cubrid-testcases-private/interface/CCI/shell/_20_cci/`**.

### Category subdirectories
```
_01_simple/        — basic CCI API sanity tests
_02_adv/           — advanced CCI scenarios
_03_func/          — functional tests
_04_db/            — database-level CCI tests
_05_set/           — SET type tests
_06_bind/          — bind parameter tests
_07_query/         — query execution tests
_09_datetime/      — datetime type tests
_10_bigint/        — bigint type tests
_11_other/         — miscellaneous
_12_issue/         — bug fix tests (BTS issues)
_13_enhancement/   — enhancement tests
_14_1h_issue/      — recent 1-hour issue tests
_14_ENUM/          — ENUM type tests
_15_Cursor/        — cursor tests
_28_features_841/  — features from CUBRID 8.4.1
_28_features_844/  — features from CUBRID 8.4.4
```

### Path structure
```
_20_cci/<category>/<test_name>/cases/<test_name>.sh
_20_cci/<category>/<test_name>/cases/test.c
_20_cci/<category>/<test_name>/cases/<test_name>.answer   # simple pattern only
```

### Bug fixes (issue tests)
```
_20_cci/_12_issue/<bug_id>/cases/<bug_id>.sh
_20_cci/_12_issue/<bug_id>/cases/test.c
```
Use `cbrd_XXXXX` or `bug_bts_XXXXX` naming for CUBRID issues.

## Two Test Patterns

### Pattern 1: Simple (output comparison)

Use when the test produces deterministic text output that can be compared against an answer file.

```bash
#!/bin/bash
. $init_path/init.sh
init test
set -x

# create_ccidb: creates 'ccidb' DB with standard schema, starts server and broker
create_ccidb
isdbstart=`cubrid server status | grep "Server ccidb " | wc -l`
if [ $isdbstart -ne 1 ]; then
    cubrid server start ccidb
fi

cubrid broker start

# compile C source
xgcc -o test test.c

# run test
port=`cubrid broker status -b | grep broker1 | awk '{print $4}'`
output_file=${case_name}.output
./test $port > $output_file

compare_result_between_files "${output_file}" "${case_name}.answer"

if [ $isdbexist -ne 1 ]; then
    cubrid server stop ccidb
    cubrid deletedb ccidb
fi

finish
```

### Pattern 2: Issue/explicit check

Use when verifying a specific bug fix or behavior — check output for a keyword or condition.

```bash
#!/bin/bash
. $init_path/init.sh
init test
set -x

db=testdb
cubrid_createdb --db-volume-size=20m $db
cubrid server start $db

gcc -o test test.c -I${CUBRID}/include -L${CUBRID}/lib -lcascci

cubrid broker start
port=`get_broker_port_from_shell_config`
./test $port $db > result.log 2>&1

if grep "EXPECTED_OUTPUT" result.log; then
    write_ok
else
    write_nok
fi

cubrid server stop $db
cubrid deletedb $db
rm -rf $db test
finish
```

## test.c Structure

### Minimal CCI test.c
```c
#include <stdio.h>
#include "cas_cci.h"

int main(int argc, char *argv[])
{
    int port = atoi(argv[1]);
    int conn, req, res, col_count;
    T_CCI_ERROR error;
    T_CCI_COL_INFO *res_col_info;
    T_CCI_SQLX_CMD cmd_type;

    conn = cci_connect("127.0.0.1", port, "ccidb", "public", "");
    if (conn < 0) {
        fprintf(stderr, "cci_connect failed\n");
        return 1;
    }

    req = cci_prepare(conn, "SELECT 1+1", 0, &error);
    if (req < 0) {
        fprintf(stderr, "cci_prepare failed: %s\n", error.err_msg);
        cci_disconnect(conn, &error);
        return 1;
    }

    res = cci_execute(req, 0, 0, &error);
    if (res < 0) {
        fprintf(stderr, "cci_execute failed: %s\n", error.err_msg);
        cci_close_req_handle(req);
        cci_disconnect(conn, &error);
        return 1;
    }

    cci_cursor(req, 1, CCI_CURSOR_FIRST, &error);
    cci_fetch(req, &error);

    char *val;
    int ind;
    cci_get_data(req, 1, CCI_A_TYPE_STR, &val, &ind);
    printf("%s\n", val);

    cci_close_req_handle(req);
    cci_disconnect(conn, &error);
    return 0;
}
```

### Key CCI APIs
| API | Purpose |
|-----|---------|
| `cci_connect(host, port, db, user, pw)` | Connect to CUBRID broker |
| `cci_connect_with_url(url, user, pw)` | Connect via URL with options |
| `cci_prepare(conn, sql, flags, &error)` | Prepare a SQL statement |
| `cci_execute(req, flags, max_col, &error)` | Execute prepared statement |
| `cci_cursor(req, offset, origin, &error)` | Move result cursor |
| `cci_fetch(req, &error)` | Fetch current row |
| `cci_get_data(req, col_no, type, &val, &ind)` | Get column value |
| `cci_get_result_info(req, &cmd_type, &col_count)` | Get result metadata |
| `cci_close_req_handle(req)` | Close request handle |
| `cci_disconnect(conn, &error)` | Disconnect |
| `cci_bind_param(req, idx, a_type, val, u_type, flag)` | Bind parameter |

### CCI data types
| Constant | C type | Description |
|----------|--------|-------------|
| `CCI_A_TYPE_STR` | `char *` | String |
| `CCI_A_TYPE_INT` | `int` | Integer |
| `CCI_A_TYPE_BIGINT` | `int64_t` | Big integer |
| `CCI_A_TYPE_DOUBLE` | `double` | Double |
| `CCI_A_TYPE_DATE` | `T_CCI_DATE` | Date |

## Compilation

### `xgcc` (simple tests using `create_ccidb`)
`xgcc` is a CTP wrapper that handles include/lib paths automatically:
```bash
xgcc -o test test.c
```

### Manual `gcc` (issue tests with custom DB)
```bash
gcc -o test test.c -I${CUBRID}/include -L${CUBRID}/lib -lcascci
```
For 32-bit CUBRID, add `-m32`. For thread-safe builds, add `-lpthread`.

## Helper Functions Reference

| Function/Var | Purpose |
|-------------|---------|
| `create_ccidb` | Create standard 'ccidb' DB with schema and start server |
| `cubrid_createdb [opts] $db` | Create a custom DB |
| `get_broker_port_from_shell_config` | Get broker port from CTP config (issue tests) |
| `cubrid broker status -b \| grep broker1 \| awk '{print $4}'` | Get broker port (simple tests) |
| `compare_result_between_files file1 file2` | Compare output to answer; writes ok/nok automatically |
| `write_ok` / `write_nok` | Record pass/fail result |
| `$case_name` | Current test case name (auto-set by CTP) |
| `$isdbexist` | 1 if ccidb already existed before test, 0 if created by test |
| `finish` | Finalize test (must be last call) |

## Writing Rules

1. **Always `#!/bin/bash`** — not `#!/bin/sh`
2. **Source order**: `. $init_path/init.sh` → `init test` → `set -x`
3. **Simple pattern**: use `create_ccidb` + `xgcc` + `compare_result_between_files`
4. **Issue pattern**: use `cubrid_createdb` + explicit `gcc` + `write_ok`/`write_nok`
5. **Always clean up**: stop server, `cubrid deletedb`, `rm test` before `finish`
6. **No hardcoded ports**: use `get_broker_port_from_shell_config` or grep broker status
7. **No hardcoded CUBRID paths**: use `${CUBRID}/include`, `${CUBRID}/lib`
8. **`finish` must be last call** — always

## Generation Process

1. **Clarify**: JIRA issue ID, CCI API(s) being tested, what pass/fail looks like.
2. **Choose pattern**: simple (deterministic output) or issue (keyword check).
3. **Draft**: shell script + test.c (+ answer file if simple).
4. **Self-review**:
   - `#!/bin/bash`?
   - `. $init_path/init.sh` and `init test` before anything else?
   - DB cleanup before `finish`?
   - `finish` is last call?
   - No hardcoded paths or ports?
5. **Present**: show directory path and all file contents.

## Examples

- `@examples/cci_simple_test.sh` + `@examples/cci_simple_test.c` + `@examples/cci_simple_test.answer` — output comparison pattern
- `@examples/cci_issue_test.sh` + `@examples/cci_issue_test.c` — explicit pass/fail check pattern

## References

- `~/cubrid-testcases-private/interface/CCI/shell/_20_cci/` — existing CCI testcases
- `~/cubrid-testtools/CTP/shell/init_path/init.sh` — CTP core helpers
- CUBRID CCI API header: `${CUBRID}/include/cas_cci.h`
