# shell writing rules

These *writing rules* say how to write the files of a TC under `shell/`. What a TC checks is in the [*test perspectives*](test-perspectives.md).

## New TC

### Place and files

**Write a scenario that needs no server restart, parameter change, or utility call as a SQL TC in `cubrid-testcases`, not as a shell TC.** A shell TC pays for its own database, server, and cleanup, which a scenario of SQL statements alone does not need. Example: a check that a `SELECT` with `GROUP BY` returns the right rows is a SQL TC; a check that `unloaddb` writes those rows is a shell TC.

**Put the entry script of a TC at `<name>/cases/<name>.sh`, with the same `<name>` for the directory and the script.** CTP runs only the script named after its directory, so a TC under another name never runs and never fails. Example: `shell/_06_issues/_26_2h/cbrd_xxxxx/cases/cbrd_xxxxx.sh`, not `cbrd_xxxxx/cases/test.sh` or `cbrd_xxxxx/cbrd_xxxxx.sh`.

**Put a bug-fix TC under `_06_issues/_<yy>_<1|2>h/` for the half-year in which its issue was created.** The date of the issue picks the directory, not the day you write the TC. Example: a bug issue created on 2025-02-03 gets `shell/_06_issues/_25_1h/cbrd_xxxxx/` even when you write its TC in 2026.

**Put a feature TC under a feature group of its release directory `_<no>_<release_code>/`.** Neither kind of new TC starts under `_25_unstable`, which holds only TCs in *quarantine* ([Changing an existing TC](#changing-an-existing-tc)). Example: a feature TC goes under a group such as `shell/_40_guava/cbrd_xxxxx_<feature>/`.

**Put the scenarios of one issue in one TC that prepares the database once, and split them into `cbrd_xxxxx_<keyword>` TCs only under one of the three conditions that follow.** One TC sets up once and keeps the checks of one issue side by side, while each split costs another database and server. The three conditions are: the scenarios need different settings, such as another parameter value or a server restart; one TC cannot stay well below the TC timeout ([Environment](#environment)); or one TC cannot show which scenario failed. Example: `cbrd_xxxxx_archives_off` and `cbrd_xxxxx_default`, because one scenario needs `log_max_archives=0` and a restart and the other runs with the defaults.

**Put the SQL of a TC in heredocs inside the script, and keep only bulk data and Java or C source in separate files.** One TC never mixes heredocs with an external `.sql` file. SQL in a separate file hides which statements a step ran, so a reader misses a setup step that failed. Example: `csql -u dba $db <<'EOF'` … `EOF` creates the users, not `csql -u dba $db -i create_user.sql`.

**Commit the C source of a client program in `cases/` and compile it with `xgcc` when the TC runs.** `xgcc` adds the include and library paths of the CUBRID build under test, so the program talks to the build that the TC tests. Example: `xgcc -o cbrd_xxxxx cbrd_xxxxx.c`, with `cbrd_xxxxx.c` committed and the binary left out.

### Script

**Make line 1 of the script `#!/bin/bash`, and start a *description block* on line 2 that names the issue key and says what the TC checks.** CTP runs the script with `sh`, which is bash in POSIX mode on the CI image, so this line gives a person who runs `./<name>.sh` by hand the same shell; a shebang below line 1 is a plain comment. The reviewer and the next person who changes the TC read from the block which issue the TC reproduces and what each scenario checks. Example:
```bash
#!/bin/bash
:<<'DESCRIPTION'
Issue: CBRD-xxxxx
Test: a second backupdb is refused while the first one runs.
DESCRIPTION
```

**Source `$init_path/init.sh` and then call `init test` before the logic of the TC.** Without them the CTP functions are undefined or the *verdicts* miss the result file of this run, and CTP reports the empty `.result` file as a failure. Example: `. $init_path/init.sh` and `init test` on the two lines after the description block, and `cubrid_createdb` after them.

**Write a new TC for Linux only, without a Windows branch, `WINDOWS_NOT_SUPPORTED`, `cygpath`, or a `_WIN` *answer file*.** Windows tests of shell TCs have stopped ([Operational facts](../AGENTS.md#operational-facts)), so Windows code in a new TC never runs. Example: the TC has no `if [ "$OS" = "Windows_NT" ]` branch and no `cbrd_xxxxx.answer_WIN`.

**Quote the delimiter of every heredoc, as in `<<'EOF'`, and leave it unquoted only when the body needs a shell variable expanded.** With an unquoted delimiter the shell expands `$` and backticks in the body, so `SELECT '$100'` reaches csql as `SELECT '00'`. The description block follows this rule too. Example: `csql -u dba $db <<'EOF'` for fixed SQL and `:<<'DESCRIPTION'` for the block; `<<EOF` only for a body that uses `$db` or another variable.

**Give each scenario of a TC its own object names and settings.** A table or a setting that one scenario leaves behind changes the result of the next. Example: scenario 1 uses table `t1` and scenario 2 uses `t2`, not both `t`.

**Write a TC for the engine of its own branch, without checks on the build version, and write it again in each branch you backport it to.** Shell TCs do not test compatibility across versions. Example: the TC for 11.4 goes to the 11.4 branch of this repo in its own PR, instead of an `if` on the major version in the develop TC.

**Put a command substitution into a variable before you test it with `[ ]`, and quote the variable with a default value inside the test.** An empty or multi-word value breaks the test with `[: too many arguments`, which counts as false and can send the TC down its OK branch. Example: `size=$(du -k test.log 2>/dev/null | cut -f1)` and then `[ "${size:-0}" -eq 0 ]`, not `[ $(du test.log | cut -f1) -eq 0 ]`.

**Write `set -x` with an ASCII hyphen.** An en dash, as in `set –x`, turns on no trace and sets `$1` to `–x` instead. Example: `set -x` typed in the editor, not pasted from a document that turned the hyphen into a dash.

**Remove unused code, unused files, and repeated steps before the PR.** A reviewer reads every line of a TC as part of what it tests, and a dead line sends them looking for a check that is not there. Example: drop a `result_file=…` line, which `init test` already sets, and a `for` loop that runs once.

**Put a multi-step sequence that the TC needs more than once into a shell function, and call that function each time.** One definition keeps the copies from drifting apart, and the reviewer reads the steps once. Example: the TC runs a query with `csql`, greps the result, and calls `write_ok` or `write_nok` for four cases, so it defines `check_pass` once and calls it four times.

### Environment

**Write the TC to pass in both the *CI pod* and *VM daily*, within the limits that [Operational facts](../AGENTS.md#operational-facts) lists for each.** A TC that passes in only one of them fails in the other or ends up in quarantine. A TC fits both only when it relies on nothing that one of them alone has: root or a normal user, `LANG`, `LC_ALL`, or `SHELL` in the environment, a CPU count, a file system, or a tool or database outside CUBRID and CTP. Example: the TC creates its own database instead of using `demodb`, which the CI image lacks, and sets `LANG` itself when its output depends on it; a TC that needs 3 GB of memory or 1,000 threads goes to `shell_heavy`.

**Base each verdict on a result that is the same for root and for a normal user, and leave out checks that a file permission refuses access.** Root passes every file permission check, and the two environments differ in whether they run as root ([Operational facts](../AGENTS.md#operational-facts)). Example: a check that `backupdb` fails on a `chmod 000` directory passes in VM daily and fails in the CI pod, where root writes there anyway.

**Keep the run time of one TC well below the TC timeout of the CI pod ([Operational facts](../AGENTS.md#operational-facts)), on a debug build as well.** A debug build runs slower than a release build, and a TC near the limit when it runs alone goes over it in a full run. Example: a stress loop of 1200 seconds becomes 300 seconds, and a TC that runs 900 seconds alone splits its scenarios into two TCs.

**Read the port of a CUBRID server or broker from its configuration at run time, and choose any other port the TC needs by checking at run time that it is free.** On a shared VM each user's CUBRID listens on its own ports, and another user's process can hold any fixed port. Example: `port=$(get_cubrid_port_id)` for the server and `port=$(get_broker_port_from_shell_config)` for the broker, not `8001` written into the script.

**Use `localhost` when the TC needs no particular address, and when it needs a numeric address, get one IPv4 address in one fixed way.** `hostname -I` lists every address of the host, and on a dual-stack host the first one can be IPv6. Example: `host_ip=localhost` for a DBLink to a database on the same machine, and `127.0.0.1` where a command needs a numeric address.

**Leave the CUBRID install, the home directory, and other repository checkouts in place.** The TCs of one run share the install, so a TC that moves or deletes part of it breaks every TC after it. Example: `mv $CUBRID`, `rm -rf $CUBRID`, and a library copied into `$CUBRID/lib` stay out of a TC.

**Call no `ctp.sh` inside a TC.** Example: a TC that needs the steps of another TC copies them into its own script instead of running `ctp.sh` on that TC.

**Create temporary files and work directories in the `cases/` directory where the script runs, and remove them at cleanup.** `/tmp` is shared by every user of a VM, and `TMPDIR` is set in neither environment, so the TC uses neither `/tmp` nor `$TMPDIR`. Example: `mkdir -p bk_dir` and `cubrid backupdb -D ./bk_dir $db`, not `/tmp/bk_dir`.

**Write paths with `$CUBRID`, `$init_path`, or a path relative to the `cases/` directory, not as absolute paths such as `/home/…` or `/opt/…`.** The CI checkout lies outside `/home`, and the CUBRID install lies elsewhere on each machine. Example: `$CUBRID/bin/cub_admin` and `./bk2_dir`, not `/home/user1/CUBRID/bin/cub_admin`.

**Create a database with `cubrid_createdb`, and change a setting in `cubrid.conf`, `cubrid_broker.conf`, or `cubrid_ha.conf` either with `change_db_parameter`, `change_broker_parameter`, or `change_ha_parameter`, or by editing the file after you back it up and restoring the backup at cleanup.** `cubrid_createdb` adds the locale argument that `cubrid createdb` needs, and `finish` restores only the files that the helpers changed, so a direct edit without its own backup can leave its setting for every TC after it. Change each file in one way only: the first helper call backs up the file as it is then, so after a direct edit `finish` restores the edited file and the setting stays. Both rules hold in a helper script and in a script inside an archive as well. Example: `change_db_parameter "java_stored_procedure=yes"`, or `cp $CUBRID/conf/cubrid.conf cubrid.conf.bak` before `echo "java_stored_procedure=yes" >> $CUBRID/conf/cubrid.conf` and `mv cubrid.conf.bak $CUBRID/conf/cubrid.conf` before `finish`.

**Create the database at the smallest size, `--db-volume-size=20M --log-volume-size=20M`, unless the TC tests a large or the default size.** A database of the default size, 512 MB of data volume and 512 MB of log volume, takes about 1 GB of disk and longer to create, and 20 MB is the smallest log volume that `cubrid createdb` accepts. Example: `cubrid_createdb --db-volume-size=20M --log-volume-size=20M $db`, and `cubrid_createdb $db` only in a TC that checks the default size.

**Build a locale with `do_make_locale` or a timezone with `do_make_tz`, and undo it in the same TC with `delete_make_locale` or `revert_tz`.** The build replaces a library of the CUBRID install, so without the undo every TC after it runs with that locale or timezone. Example: `do_make_tz new` after `init test`, and `revert_tz` before `finish`.

**Run `java` and `javac` with the `CLASSPATH` that `init test` sets, without `-cp` or a new `export CLASSPATH`.** That `CLASSPATH` holds the JDBC driver of the build under test and the CTP helper jar, and `-cp` replaces it. Example: `javac Test.java` and then `java Test $port $db`, not `java -cp . Test $port $db`.

**Start only the services the TC uses.** A broker or a manager that nothing uses holds ports and memory and can fail to start for a reason unrelated to the issue. Example: a TC that runs only `csql` starts the server with `cubrid server start $db`, not every service with `cubrid service start`.

### Waiting and processes

**Wait for a state with `wait_until` and a *wait limit*, not with a fixed `sleep` or a loop without a limit.** A fixed sleep is too short on a slow machine and wasted on a fast one, and a loop without a limit hangs until the TC timeout. Example:
```bash
wait_until 60 eval 'cubrid tranlist $db 2>/dev/null | grep -qw csql' || write_nok "csql never showed in tranlist"
```

**Set the wait limit to a whole number of seconds well above the normal time.** `wait_until` counts the limit in whole seconds, and a large limit costs time only when something is already wrong. Example: `wait_until 60 …` for a step that takes about 5 seconds, not `wait_until 6 …` or `wait_until 0.5 …`.

**Wrap a condition that has a pipeline or `$(...)` in `eval '...'`.** `eval` runs the whole condition again at each try. Example: `wait_until 60 eval '[ "$(grep -c ok out.log)" -ge 2 ]'`, not `wait_until 60 [ "$(grep -c ok out.log)" -ge 2 ]`, which counts once and then tests the same number at each try.

**Use a fixed `sleep` only when the passing of time is itself the condition or when the TC paces its load, and give each such `sleep` a comment that says why.** Without the comment, a reviewer cannot tell a sleep that the TC needs from one that waits for a state and belongs in `wait_until`. Example: `sleep 6  # the query timeout is 5 s: wait past it`; a `sleep 1` right after `cubrid server start` waits for a state and needs `wait_until` instead.

**Save the PID of each background command with `pid=$!` right after it, and end that process with `wait $pid` or `xkill_pid $pid` before the TC ends.** An orphan process keeps a database or a port, and the next TC fails on it. Example: `cubrid backupdb -D ./bk1 $db > bk1.log 2>&1 < /dev/null &`, then `bk1_pid=$!`, and later `wait $bk1_pid`.

**Stop a process with a `cubrid` command, `xkill`, or `xkill_pid`, and only a process that the TC started.** `pkill` and `kill -9 $(pgrep …)` also end processes that the TC did not start, including those of other users on a shared VM. `xkill` stops every process of your user whose PID or command name contains its argument, so it is exact only for an argument that matches no other process; `xkill_pid` stops exactly the PID it gets. Example: `cubrid server stop $db` for the server and `xkill_pid $bk1_pid` for a background `backupdb`, not `pkill cub`, and not `xkill $bk1_pid`, which also stops PID 1234 when `$bk1_pid` is 234.

**Give `/dev/null` as stdin to each command that can ask for confirmation, such as `backupdb` and `deletedb`, or use its option that skips the prompt.** Under CTP the prompt waits for input that never comes and the TC hangs until the TC timeout, while the same TC run from a terminal shows no problem. Example: `cubrid backupdb -D ./bk2 $db < /dev/null`.

**Set `auto_restart_server=no` in a TC that kills the server or sends it a signal, unless automatic restart is what the TC tests.** The master restarts a killed server, and the restarted server can crash again and leave a core file that does not come from the bug of the issue. Example: `change_db_parameter "auto_restart_server=no"` before `cubrid server start $db`, and the kill after it.

**Take a baseline, such as a start time or a log position, before the action it measures, and assume no second or minute boundary between two steps.** A baseline taken after the action misses what the action did, and the clock can cross a second or a minute between any two steps. Example: `start_ts=$(date +%s)` before the `CREATE TABLE` and `INSERT` that a CDC check extracts, not after the `CREATE TABLE`; the TC reads every new server `.err` file, not only the latest one.

### Verdicts

**Make every path of the script reach `write_ok` or `write_nok`.** A path that writes no verdict skips its check in silence, and a run that writes none leaves an empty `.result` file, which CTP reports without a cause. Example: an `if` that checks a result calls `write_ok` in its `then` branch and `write_nok out.log` in its `else` branch.

**End an *abort path*, a path that stops the TC after a failed step, with `write_nok`, the cleanup, `finish`, and `exit 1`.** `finish` restores the settings for the next TC but does not stop the script, so an abort path without `exit` runs on into the checks. CTP reads no exit code ([Operational facts](../AGENTS.md#operational-facts)), so the `1` is for a person who runs the script by hand. Example: `cubrid server start $db || { write_nok "server start failed"; cubrid deletedb $db; finish; exit 1; }`.

**Put no `exit` at the normal end of the script.** The script ends after `finish` anyway, and CTP reads no exit code ([Operational facts](../AGENTS.md#operational-facts)). Example: the script ends with `finish`, not with `finish` and then `exit 0`.

**Pass `write_nok` the log file or a message that shows why the check failed.** `write_nok <file>` copies the file into the `.result` file, so the CI result shows the cause without a rerun. Example: `write_nok result.log` or `write_nok "scenario 2: expected 3 rows, got $cnt"`, not a bare `write_nok`.

**Write a grep that gives a verdict so it matches only the line it checks, in the log of this database and this TC.** The csql output repeats the query and its column headers, and a short pattern also matches inside longer words and numbers. Anchors (`^`, `$`), `-w`, and an escaped `.` fit the pattern to the line. Example: `grep -qE "^[[:space:]]*'PASS'[[:space:]]*$" result.log`, not `grep -q PASS result.log`, which also matches `DECODE(…, 'PASS', 'FAIL')` in the repeated query; `grep -w 4321`, so that PID `14321` does not match.

**Compare a count with `-eq`, and use a range only for a count that a restart, a retry, or timing can change, with the reason in a comment.** A range lets through counts that the engine should never produce, so its lower bound must be a value that the bug breaks. Example: `[ "$cnt" -eq 2 ]` for the rows of a query; `[ "$cnt" -ge 1 ]  # the client retries, so it connects 1 to 3 times` for a retried connection.

### Answer files

**Make each answer file from the output of a run of the TC and commit it in `cases/`.** `init answer` does not make one: it writes no file that `compare_result_between_files` reads. Example: run the TC once, read `result.log` after the normalizing step, and save it as `cases/cbrd_xxxxx.answer`.

**Check a result of a line or two with `grep` instead of an answer file.** Example: a check that one row came back greps for that row.

**Keep one answer file for outputs that are the same.** Copies of one output must all change when the output changes. Example: when `cbrd_xxxxx_01.answer` to `cbrd_xxxxx_08.answer` would hold the same lines, the TC keeps one `cbrd_xxxxx.answer` and compares each output with it.

**Normalize the output with `format_csql_output`, `format_query_plan`, or `format_path_output`, and then compare it with `compare_result_between_files`.** `compare_result_between_files` writes the verdict itself, and without the normalizing step the run times and paths in the output differ on every run. What to mask beyond these functions is in the [test perspectives](test-perspectives.md#what-a-shell-tc-cannot-check). Example: `format_csql_output result.log` and then `compare_result_between_files cbrd_xxxxx.answer result.log`, not `diff cbrd_xxxxx.answer result.log && write_ok`, which writes nothing when the files differ.

**Keep the output of any bug other than the one the TC tests out of an answer file by changing the scenario to avoid that bug, for example by masking the output or taking another path.** An answer file that holds a bug's output passes only while the bug stays, and the fix of that bug turns it into a NOK. Example: mask with `sed` a plan line that an open optimizer bug changes.

**When the scenario cannot avoid a bug other than the one the TC tests, file an issue for it, write its key and the words `known wrong result` in the description block, keep the output in the answer file, and update the answer file when that issue is closed.** The key in the block tells the reviewer why the answer file holds a wrong line and tells the next person when to update it. Example: the plan line that the open optimizer bug changes is what the TC checks, so the block says `Known wrong result: CBRD-yyyyy` and the answer file keeps the line.

### Cleanup

**Keep each TC atomic, so that it affects neither the TC before it nor the TC after it, and restore the state it started from as soon as it ends.** The rules of this section and the cleanup rules in [Environment](#environment) and [Waiting and processes](#waiting-and-processes) are how a TC does it. Example: a TC that creates its database, changes a parameter with `change_db_parameter`, and starts a background `csql` ends with that process waited for, the database deleted, the parameter restored by `finish`, and its files removed, so the next TC starts from the same state as this one did.

**Run `cubrid deletedb` at the end of each TC on every database it created, through the `cubrid` command that `init test` puts first on `PATH`, not through `cub_admin`.** That `cubrid` is a CTP wrapper: before it deletes the database, it writes a NOK for new core files and `FATAL ERROR`, so it catches a crash of the TC wherever it happened. A TC that tests `cub_admin` itself is the exception. Example: `cubrid deletedb $db` after `cubrid server stop $db`, and `cub_admin deletedb $db` only in a TC of `cub_admin`.

**Put `export SKIP_CHECK_FATAL_ERROR=TRUE` after `init test` in a TC whose scenario writes `FATAL ERROR` on purpose, such as a reproduced crash.** It turns off only the `FATAL ERROR` count of `cubrid deletedb`: a core file left behind is still a NOK and brings the `FATAL ERROR` NOK back with it. Example: a TC that checks `LOG FATAL ERROR: logpb_restore` after a failed restore sets it right after `init test`.

**Remove a leftover database directory before you create the database.** A run that ended early can leave the database behind. Example: `rm -rf $db; mkdir $db` before `cubrid_createdb`.

**At the end of the TC, stop the server, run `cubrid deletedb`, remove the files, and call `finish`, in that order.** `cubrid deletedb` before `cubrid server stop` fails and leaves the database for the next run. Example: `cubrid server stop $db; cubrid deletedb $db; rm -f *.log; finish`.

**Remove the files the TC created with `rm -f` after its last check.** `rm` without `-f` prints an error when a glob matches nothing, and a log removed before the check takes the evidence of a NOK with it. Example: `rm -f *.log *_temp_diff listdrv` before `finish`.

**Leave committed files and the `.result` file unchanged while the TC runs.** A committed file edited in place changes the next run. Example: the TC copies a template to a new file before it runs `sed -i`, instead of editing the committed template.

## Changing an existing TC

**Bring a TC you change in line with the [New TC](#new-tc) section and the rules below, and leave a TC that you have no other reason to change as it is.** Changes made only for the *rulebook* touch many passing TCs at once, while a TC under change gets a review that can check these rules too. Example: a PR that fixes the wait in `cbrd_xxxxx.sh` also quotes its heredoc delimiters, and no PR quotes the delimiters of fifty TCs that need nothing else.

A change of an answer file follows two rules of other sections: the PR says which lines changed and why ([shell/AGENTS.md](../AGENTS.md#the-pr)), and an answer file that keeps a known wrong answer is updated once its issue is closed ([Answer files](#answer-files)).

**Keep every verdict of an existing TC when you change it.** A change that drops a verdict to make the TC pass hides the regression that the verdict caught. A verdict leaves only with the engine feature it checks, and the PR then says so. Example: the fix rewrites the setup of `cbrd_xxxxx.sh` and keeps its two verdicts, so the `.result` file still has `cbrd_xxxxx-1` and `cbrd_xxxxx-2`.

**Find the cause of an unstable TC before you change it, and when the fix raises a wait limit, write in the PR the build, the longest time you measured, and why the old limit fell short.** A larger limit or a longer sleep without a measured value hides the cause and moves the failure to the next slow run. When the cause stays unknown, the next rule moves the TC into quarantine. Example: the PR says `wait limit 60 -> 180: debug build 1a2b3c4 took up to 95 s in 20 runs in the CI pod`.

**Move an existing TC that fails only sometimes, for a cause you have not found, to the same relative path under `_25_unstable`, and add its old path and the measured reason to `_25_unstable/readme.txt`.** The CI pod skips `_25_unstable` and VM daily keeps running it ([Operational facts](../AGENTS.md#operational-facts)); after 5 passes in a row there, the TC moves back. Example: `git mv shell/_38_fig/cbrd_xxxxx shell/_25_unstable/_38_fig/cbrd_xxxxx`, and the readme line `scenario/shell/_38_fig/cbrd_xxxxx (fails 3 of 20 runs: the restart takes up to 70 s)`.

**Add a TC that fails on every run because of an open engine issue or a platform limit to the *excluded list*, with a `#<issue key>` comment line above its path.** The excluded list stops the TC in both environments ([Operational facts](../AGENTS.md#operational-facts)), and the key says when it can come back. Example:
```
#CBRD-xxxxx: the server crashes in recovery until the fix
shell/_06_issues/_25_1h/cbrd_xxxxx
```

**Remove the path and its comment line from the excluded list when the issue is closed.** A TC left on the list after the fix catches no regression. Example: once CBRD-xxxxx is closed, a PR deletes both lines of the example above.
