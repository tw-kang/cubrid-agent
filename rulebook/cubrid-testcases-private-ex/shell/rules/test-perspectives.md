# shell test perspectives

These *test perspectives* say what a TC under `shell/` checks. How to write the files of the TC is in the [*writing rules*](writing-rules.md).

## Scenarios to cover

**Cover every scenario and acceptance criterion of the issue, and write in the TC PR why you leave any of them out.** A scenario that no TC runs is a regression that nobody catches. Example: the issue lists eight acceptance criteria and the eighth needs a second host, so the PR says `A/C 8 is not covered: it needs a second host`.

**Add scenarios with invalid inputs and boundary values next to the valid ones.** A regression often shows only at an edge of the input range. Example: for an option that accepts 1 to 100, the TC also runs 0, 1, 100, 101, and `abc`.

**When the feature works in client-server mode and in standalone mode, run the scenario in both.** The two modes run different engine code. Example: the TC runs the same `unloaddb` check with `-C` while the server runs and with `-S` after the server stops.

**Run a privilege or ownership scenario as a user outside the DBA group as well as `dba`.** `dba` passes every authorization check, so it never takes the path that refuses. Example: the TC creates `u1` outside the DBA group, grants it `SELECT` on `t`, and checks that `u1` can select from `t` and cannot update it.

## Evidence in a verdict

**Put evidence that the TC reached the *bug path* into a *verdict*.** A TC that checks only the final result can pass without running the bug path at all. Examples:
- A TC for a refused duplicate backup checks that the second `backupdb` printed `Backup is already running`, not only that the database restores.
- A TC that kills an operation first checks that the operation is still running, for example in `cubrid tranlist`, and only then kills it.

**Prove in a verdict that the two operations of a concurrency TC overlapped.** Operations that ran one after the other pass without testing the concurrency bug, so the TC polls until the first operation reaches a known state before it starts the second, as the [writing rules](writing-rules.md#new-tc) say for any wait. Example: the TC starts the first `backupdb` with `--sleep-msecs`, waits with `wait_until` until `ps` shows it, starts the second, and then checks both that the second was refused and that the first was still running.

**Check that each setup step succeeded before the main check.** When creating a user or a database, starting a server, or loading data fails, the main check can still pass by chance and report a feature that the TC never tested. Example: the TC creates user `u1` and checks with a query on `db_user` that `u1` exists before it checks how `ps` shows the password of `u1`; if `u1` is missing, the TC takes the *abort path* of the [writing rules](writing-rules.md#new-tc).

**Next to each error scenario, add a positive control: a scenario that goes through the same check and must succeed.** Without it, a check that also refuses valid input, or never runs, passes every error scenario. Example: the TC checks that `loaddb` refuses an object file for a class that does not exist, and that the same command loads the file once the class exists.

**Check a refused operation by its expected error code or message, not by the word `ERROR`.** Some messages carry no `ERROR`, and a check on `ERROR` passes when the operation fails for another reason. Example: `loaddb` with an unknown user prints `User "u9" is invalid.`, so the TC greps that message.

**Check the result of a utility with a query on the data after it ran, not with its exit code or success message.** A utility that reports success and loses data is the worst failure for a user. Example: after `restoredb`, the TC checks that `select count(*) from t` returns 200000 and compares sample rows with the *answer file*; good data for this includes an empty table, an all-`NULL` column, a LOB column, a string of the maximum length, and a partitioned table.

**After you change a parameter or a driver property, check that the new value took effect and that a verdict shows the difference it makes.** A TC that still passes when the engine ignores the value misses the regression, and some server parameters take effect only after a restart. Example: the TC sets the JDBC property `logFile=jdbc.log` and checks that `jdbc.log` exists and is not empty, not only that the queries ran.

**Compare string and binary values themselves, not their length or row count.** A count or a length misses a value whose bytes are wrong, such as a string that carries bytes of the next column. Example: the TC checks that `select decode(c, 'a' || CHR(0) || 'b', 'PASS', 'FAIL') from t` returns `'PASS'`; other values worth this check are multibyte strings and the empty string against `NULL`.

**When the issue is a crash that leaves a core file, check for core files and the server `.err` file right after the reproduction steps, and right after that check, delete those core files.** The TC then judges the crash it reproduces where it happens, and the `cubrid deletedb` that ends every TC ([writing rules](writing-rules.md#new-tc)) does not report the same core files again; a crash that also writes `FATAL ERROR` needs the setting in [writing rules](writing-rules.md#cleanup). Example: right after the query that crashed the server, the TC looks for new `core.*` files, greps the server `.err` file for the error that the issue names, calls `write_nok` with what it found, and removes those `core.*` files and no others.

## What a shell TC cannot check

Shell TCs run on shared machines that CTP drives without a terminal. The checks below give results that depend on the machine or never finish there, and each rule says what to do instead.

**Judge a shell TC by states only, and put a check on elapsed time or resource usage in `shell_perf`.** Other loads on the *CI pod* and in *VM daily* change a measured time or size from run to run, while a state (a row, a message, a file, a process) stays the same. Example: the TC checks that the query returns its 100 rows; a check that it ran within 2 seconds or used less than 1 GB of memory goes to `shell_perf`.

**Mask or extract the values that change from run to run before you compare output, and leave a value unmasked when it is what the TC checks.** PIDs, ports, host names, timestamps, absolute paths, and version strings differ on every machine and run; how to call the normalizing functions is in the [writing rules](writing-rules.md#new-tc). Example: the TC runs `sed -i 's/pid [0-9][0-9]*/pid ?/' out.log` before the comparison, so `pid 12345` and `pid 678` compare equal.

**Fold the cost and cardinality digits of a query plan before you compare it, unless those numbers are what the TC checks.** `format_query_plan` replaces each digit with `?` but keeps the number of digits, so a change of the cost model alone breaks the answer file. Example: after `format_query_plan`, the TC runs `sed -i 's/??*/?/g' plan.log`, so a cost of 150 and a cost of 1500 compare equal.

**Give each multi-row SELECT that you compare with an answer file an `ORDER BY` on a unique key, and sort other output that has no fixed order before you compare it.** Rows of a SELECT without `ORDER BY` and lines that a parallel run logs come in any order. Example: `select owner_name, class_name from db_class order by owner_name, class_name;`, and `sort px.log > px.sorted` for the log of a parallel query.

**Point a DBLink TC under `shell/` at a second CUBRID database, and test DBLink to Oracle, MySQL, or MariaDB outside `shell/`.** Neither the CI pod nor VM daily has an Oracle, MySQL, or MariaDB server, so a TC that needs one fails in both. Example: the TC creates `db2` on the same machine and names it in `CREATE SERVER`.

**Test only what runs without interactive input.** The [writing rules](writing-rules.md#new-tc) say why a prompt hangs a TC under CTP and how to give `/dev/null` to a command that may prompt. Example: a check of what `csql` does with a statement typed at its prompt is not a shell TC, and a check of the same statement through `csql -c` is.

## Model TCs

**Copy what a model TC does well, and write each point listed under "Differs" the way the [writing rules](writing-rules.md#new-tc) say.** The listed points break a writing rule, and a copy would carry the break into a new TC. Example: copy the positive control of `cbrd_26719`, and open its *description block* with a quoted delimiter such as `:<<'END'`, not `:<< END`.

- `shell/_40_guava/cbrd_26374/cbrd_26374_unknown/cases/cbrd_26374_unknown.sh`: its description block lists the seven checks, and each scenario that expects a failure checks the exact error message, such as `Class dba.v1 does not exist.`
  Differs: lines 2 and 210 open a heredoc with an unquoted delimiter though the body has no `$`.
- `shell/_40_guava/cbrd_26719/cases/cbrd_26719.sh`: it first checks a positive control (alone, with the worker pool free, the query runs a parallel probe), and its verdicts prove that the serial fallback under contention really happened.
  Differs: line 3 opens a heredoc with an unquoted delimiter though the body has no `$`; lines 78, 192, 208, 217, 222, 230, 237, and 245 call `write_nok` with no argument.
- `shell/_37_elderberry/cbrd_23842_cdc/bug/cbrd_27026/cases/cbrd_27026.sh`: in 78 lines it holds a positive control and the bug scenario, and its description block states the result expected before and after the fix.
  Differs: line 37 waits with `sleep 1` and no reason comment; line 63 ends an abort path with `exit 0`, not `exit 1`; line 70 puts a command substitution straight into `[ ]`; the TC tests a bug fix but sits in the feature group `_37_elderberry/`, and a TC like it goes to the [half-year directory](writing-rules.md#new-tc) of its issue, here `shell/_06_issues/_26_2h/cbrd_27026/`.

## Bad TCs

Each TC below shows the defect named next to it.

- `shell/_38_fig/cbrd_24404/_02_utility/cases/_02_utility.sh`: it appends to and edits the shared `$CUBRID/conf/cubrid_hosts.conf` with `echo >>` and `sed -i`, and it folds seven checks into one verdict with a bare `write_nok` (lines 52 to 55), so a NOK does not say which check failed.
- `shell/_25_unstable/_06_issues/_23_1h/apis_955/cases/apis_955.sh`: its check cannot fail, because `test.c` reads the wrong argument and expects 0 rows on every build; one run also takes 664 seconds with 4,000 CAS processes and 2,000 threads.
- `shell/_39_fig_cake/cbrd_25858/cases/cbrd_25858.sh`: `pkill cub` (line 45) ends every process whose name contains `cub`, not only its own, and lines 43 and 54 delete every `core.*` file under `$CUBRID`, so the `cubrid deletedb` at the end cannot see a crash of the TC.
