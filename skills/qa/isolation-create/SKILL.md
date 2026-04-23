---
name: isolation-create
description: "Use this skill whenever the user wants to create, draft, write, or scaffold a new isolation testcase (.ctl) for CUBRID CTP. This is the right skill any time someone needs a new isolation test produced from scratch for a CBRD issue — bug fix or new feature. Common requests: \"isolation tc 만들어줘\", \"isolation tc 초안 작성해줘\", \"create isolation tc\", \"draft isolation test\", \"새 isolation testcase\", \"isolation testcase 작성\", \"create draft isolation tc for CBRD-XXXXX\". NOT for: running existing isolation tests, reviewing diffs/PRs, CTP configuration, or SQL/shell testcase creation."
---

# Isolation Testcase Creator (CTP)

Generate well-formed CUBRID CTP isolation testcase files (`.ctl` format) for concurrent transaction testing.

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
# Verify isolation module exists
ls $CTP_HOME/isolation/
```

If `ctp.sh` is not found, stop and display:

> "CTP is not installed. This skill cannot proceed.
> Installation methods:
> - Option 1: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> - Option 2: `git clone https://github.com/CUBRID/cubrid-testtools.git` and use `~/cubrid-testtools/CTP` directly
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

Use the detected `$CTP_HOME` in all subsequent steps.

## Directory Path Convention

Testcases live under `~/cubrid-testcases/isolation/`.

### Isolation level directories

```
_01_ReadCommitted/     - Tests where all clients use READ COMMITTED
_02_RepeatableRead/    - Tests where all clients use REPEATABLE READ
_04_RepeatableRead_ReadCommitted/  - C1=REPEATABLE READ, C2=READ COMMITTED
_05_ReadCommitted_RepeatableRead/  - C1=READ COMMITTED, C2=REPEATABLE READ
_06_features/          - Feature-specific isolation tests (new features)
```

Choose the directory matching the isolation levels used. For mixed levels, match C1 level first, C2 level second.

### Bug fixes

```
isolation/_01_ReadCommitted/<area>/<test_name>/<test_name>_01.ctl
```

Example:
```
isolation/_01_ReadCommitted/update/update_conflict/update_conflict_01.ctl
```

### New features

```
isolation/_06_features/<feature_name>/<test_name>/<test_name>_01.ctl
```

Example:
```
isolation/_06_features/mvcc_insert/mvcc_insert_visibility/mvcc_insert_visibility_01.ctl
```

### Numbering

When multiple `.ctl` files test the same scenario variant, number sequentially: `_01.ctl`, `_02.ctl`, etc.

## .ctl File Format

Every `.ctl` file has two sections: a comment header block and the test body.

### Header block

```
/*
Test Case: <Short descriptive title>
Priority: 1
Reference case:
Author: <your name>

Test Plan:
<1-3 sentences describing what concurrency behavior is being verified>

Test Scenario:
<Step-by-step narrative: who does what and when, C1 and C2 actions>

Test Point:
1) <What C1 should or should not experience (block/succeed/see data)>
2) <What C2 should or should not experience>

NUM_CLIENTS = 2
C1: <One-line role of C1>;
C2: <One-line role of C2>;
*/
```

- `Priority: 1` is standard; use `2` only for edge cases
- `Reference case:` can be left blank or reference a related CBRD issue
- `NUM_CLIENTS` in the header comment is documentation only; the actual setup is `MC: setup NUM_CLIENTS = N;`

### Test body structure

```
MC: setup NUM_CLIENTS = 2;

C1: login as 'dba';
C1: set transaction lock timeout INFINITE;
C1: set transaction isolation level read committed;

C2: set transaction lock timeout INFINITE;
C2: set transaction isolation level read committed;

/* preparation */
C1: DROP TABLE IF EXISTS t1;
C1: CREATE TABLE t1 (...);
C1: COMMIT;
MC: wait until C1 ready;

/* test body */
...

/* cleanup */
C1: DROP TABLE IF EXISTS t1;
C1: COMMIT;
MC: wait until C1 ready;

C1: quit;
C2: quit;
```

## Command Reference

### MC (Main Controller) commands

| Command | Purpose |
|---|---|
| `MC: setup NUM_CLIENTS = N;` | Set number of concurrent client connections (always first) |
| `MC: wait until C1 ready;` | Block until C1 finishes its current statement and is idle |
| `MC: wait until C2 ready;` | Block until C2 finishes its current statement and is idle |
| `MC: wait until C1 ready, C2 ready;` | Wait for multiple clients simultaneously |

`MC: wait until Cx ready;` is a synchronization barrier. Use after every logical phase.

### Client (C1, C2, ...) commands

| Command | Purpose |
|---|---|
| `Cx: login as 'dba';` | Authenticate as DBA (required at start, or after switching users) |
| `Cx: login as '<user>';` | Authenticate as a specific DB user |
| `Cx: set transaction lock timeout INFINITE;` | Wait forever for locks (prevents spurious timeouts in tests) |
| `Cx: set transaction lock timeout <ms>;` | Set explicit lock timeout in milliseconds |
| `Cx: set transaction isolation level read committed;` | Set isolation level |
| `Cx: set transaction isolation level repeatable read;` | Set isolation level |
| `Cx: set transaction isolation level serializable;` | Set isolation level |
| `Cx: <any SQL>;` | Execute any CUBRID SQL statement |
| `Cx: COMMIT;` | Commit the current transaction |
| `Cx: ROLLBACK;` | Rollback the current transaction |
| `Cx: quit;` | End the client session (required at end) |

### Inline comments

Use `/* comment */` on its own line to label phases and improve readability. These are ignored by the test runner.

## Isolation Level Combinations

| Scenario | Directory | C1 isolation | C2 isolation |
|---|---|---|---|
| Both READ COMMITTED | `_01_ReadCommitted/` | `read committed` | `read committed` |
| Both REPEATABLE READ | `_02_RepeatableRead/` | `repeatable read` | `repeatable read` |
| C1=RR, C2=RC | `_04_RepeatableRead_ReadCommitted/` | `repeatable read` | `read committed` |
| C1=RC, C2=RR | `_05_ReadCommitted_RepeatableRead/` | `read committed` | `repeatable read` |
| SERIALIZABLE | `_06_features/` | `serializable` | `serializable` |

## Writing Rules

1. **Always end with `C1: quit;` and `C2: quit;`** — sessions must be explicitly closed.
2. **Always sync with `MC: wait until Cx ready;`** after every logical phase boundary. Without this, commands from different clients may interleave unpredictably.
3. **Set lock timeout before any DML** — use `INFINITE` to avoid flaky timeouts unless the test specifically verifies timeout behavior.
4. **Set isolation level per client** — each client sets its own isolation level; do not assume defaults.
5. **Use `C1: login as 'dba';`** at the top for setup/DDL, even if C2 uses a different role.
6. **`DROP TABLE IF EXISTS` before `CREATE TABLE`** — ensures the test is re-runnable.
7. **Cleanup at end** — drop tables and any users/objects created during preparation.
8. **Label phases with comments** — use `/* preparation */`, `/* test body */`, `/* cleanup */` to separate phases.
9. **One statement per line** — do not combine multiple SQL statements on one `Cx:` line.
10. **COMMIT after preparation** — always commit DDL and setup DML before the concurrent test phase begins.

## Common Patterns

### Pattern 1: Lock contention (one writer blocks another)

```
C1: UPDATE t1 SET val = 1 WHERE id = 1;
C2: UPDATE t1 SET val = 2 WHERE id = 1;
MC: wait until C1 ready;
C1: COMMIT;
MC: wait until C1 ready, C2 ready;
C2: COMMIT;
MC: wait until C2 ready;
```

### Pattern 2: Read visibility (dirty read prevention)

```
C1: INSERT INTO t1 VALUES (1, 'uncommitted');
C2: SELECT * FROM t1;
MC: wait until C2 ready;
C1: COMMIT;
MC: wait until C1 ready;
C2: SELECT * FROM t1;
MC: wait until C2 ready;
```

### Pattern 3: Phantom read test (SERIALIZABLE prevents phantoms)

```
C1: SELECT * FROM t1 WHERE val > 0;
C2: INSERT INTO t1 VALUES (99, 'phantom');
C2: COMMIT;
MC: wait until C2 ready;
C1: SELECT * FROM t1 WHERE val > 0;
C1: COMMIT;
MC: wait until C1 ready;
```

### Pattern 4: User privilege / ownership change

```
C1: login as 'dba';
C1: ALTER TABLE t1 OWNER TO some_user;
C1: COMMIT;
MC: wait until C1 ready;
C2: login as 'some_user';
C2: SELECT * FROM t1;
MC: wait until C2 ready;
```

## Generation Process — Self-Review Checklist

- Header complete (Test Case, Priority, Test Plan, Test Scenario, Test Point, NUM_CLIENTS)?
- Every phase followed by `MC: wait until Cx ready;`?
- All clients quit (`C1: quit;`, `C2: quit;`)?
- Cleanup present (`DROP TABLE IF EXISTS` + `COMMIT`)?
- Lock timeout set per client?
- Isolation level set per client?

## Examples

- `@examples/read_committed_lock_test.ctl` — lock contention between two transactions under READ COMMITTED
- `@examples/serializable_phantom_read.ctl` — phantom read prevention under SERIALIZABLE isolation
