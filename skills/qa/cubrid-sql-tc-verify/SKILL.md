---
name: cubrid-sql-tc-verify
description: "Run one CUBRID CTP SQL testcase on this machine, judge pass/fail, and on failure diagnose the root cause from the result diff. Use whenever someone wants to physically run a specific SQL test and know whether it passes and why — Korean: \"돌려봐\", \"수행해줘\", \"실행해봐\", \"SQL tc 한건 확인\", \"패스하는지 확인\", \"검증해줘\", \"실패 원인 알려줘\"; English: \"run\", \"execute\", \"verify\", \"sql tc\", \"check if it passes\". A CUBRID build URL alongside a .sql path is a strong signal — invoke this skill. Also handles sql_by_cci when the user says 'sqlbycci'/'sql_by_cci'. NOT for: reviewing/editing SQL test code, creating new tests, or full regression suites."
---

# SQL Testcase Verifier (CTP)

Run a single CTP SQL testcase, report PASS/FAIL, and — when it fails — diagnose *why* from the result diff the run leaves behind. "Verify" means all three: **run → judge → diagnose**, not just execute.

## Scope

**Does:** install a given CUBRID build, locate and run one `.sql` testcase through CTP interactive mode (`sql`, `medium`, or `sql_by_cci`), compare its result against the `.answer`, and on FAIL trace the divergence to a root cause with a fix recommendation.

**Does NOT:** edit/review SQL test code, create tests, run full suites, or bisect a batch of failures across commits.

## Before you start

- **CTP installed.** Resolve `$CTP_HOME` (env → `~/CTP` → `~/cubrid-testtools/CTP`). Sanity check: `ls $CTP_HOME/bin/ctp.sh $CTP_HOME/conf/`. If absent, stop and tell the user to install it (`git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`).
- **Testcase repo.** Resolve its root without a hardcoded home path: use `$CUBRID_TESTCASES` if set, else discover the `cubrid-testcases` checkout from the current dir (`git rev-parse --show-toplevel` or search upward), else ask the user. Call it `$TC` below.
- **Build URL.** A CUBRID build URL is required to install the binary under test. If not given, ask for it.
- **JIRA context (optional).** If a `CBRD-XXXXX` is referenced, run `cubrid-jira search CBRD-XXXXX` first to ground the work (reuse if already fetched). If the CLI isn't installed, skip — but installing `cubrid-jira` improves accuracy.
- Test guide: `sql_guide.md` — https://github.com/CUBRID/cubrid-testtools/blob/develop/doc/sql_guide.md (or `$CTP_HOME/../doc/sql_guide.md` if CTP is checked out locally).

## Run

Work from a scratch dir so logs and temp structures never collide: `work=$(mktemp -d)`.

1. **Install CUBRID** and verify it really worked — `run_cubrid_install` can return 0 even on failure, so trust the binary, not the exit code:
   ```bash
   sh "$CTP_HOME/common/script/run_cubrid_install" <build_url> 2>&1 | tee "$work/install.log"
   grep '\[ERROR\]' "$work/install.log" && { echo "install failed"; }   # stop & show these lines if present
   source ~/.cubrid.sh && cubrid_rel                                     # must print a version
   ```
2. **Build the locale library** — `sql.conf` does not auto-build it, and a missing one fails DB startup:
   ```bash
   # JAVA_HOME must be a JDK (needs javac — CTP compiles Java SP classes at DB setup); `which java` may resolve to a JRE
   export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
   [ -x "$JAVA_HOME/bin/javac" ] || JAVA_HOME=$(dirname "$JAVA_HOME")   # jre/bin/java → up to the JDK root
   [ ! -f $CUBRID/lib/libcubrid_all_locales.so ] && sh $CUBRID/bin/make_locale.sh -t 64bit
   ```
3. **Detect the category** from the user request and file path — picks the conf and run command:

   | Category | Trigger | Conf | Run cmd |
   |----------|---------|------|---------|
   | `sql` | default | `sql.conf` | `run <file>` |
   | `medium` | path contains `/medium/` | `medium_dev.conf` | `run <file>` |
   | `sql_by_cci` | user says `sqlbycci`/`sql_by_cci` | `sql_by_cci.conf` | `run_cci <file>` |

4. **Read the SQL file first** — know what it tests so a failing query is diagnosable.
5. **Prepare structure.** CTP expects the `.sql` in a `cases/` dir with answers in a sibling `answers/`. If already there, use in place; otherwise stage under `$work`:
   ```bash
   mkdir -p "$work/cases" "$work/answers"; cp "$SQL_FILE" "$work/cases/"   # also copy .answer/.queryPlan if given
   ```
6. **Execute** via CTP interactive mode with a timeout (DB setup takes 1-3 min before the shell starts):
   ```bash
   printf "%s %s\nquit\n" "$RUN_CMD" "$SQL_FILE" | \
     timeout 600 "$CTP_HOME/bin/ctp.sh" "$CTP_CATEGORY" -c "$CTP_CONF" --interactive 2>&1 | tee "$work/run.log"
   ```

## Verdict

Find the result root and read the count file verbatim:
```bash
RESULT_DIR=$(grep "^Result Root Dir" "$work/run.log" | head -1 | awk -F': ' '{print $2}' | tr -d ' ')
cat "$RESULT_DIR/main.info"     # sql/medium   |   cat "$RESULT_DIR/summary.info"   # sql_by_cci
```
`Fail: 0` → PASS. `Fail > 0`, timeout (exit 124), or a crash → FAIL; proceed to Failure analysis. If no result file exists, look for `No Results!!` or `Failed to connect to database server` in `$work/run.log`. After the verdict, stop leftovers (`cubrid service stop`) and offer cleanup.

## Failure analysis

On FAIL, gather evidence then classify — don't guess:

1. **Diff result vs answer** — query blocks are separated by `===...===` lines, so the diff context reveals which statement diverged:
   ```bash
   RESULT_FILE=$(find "$RESULT_DIR" -name '*.result' | head -1)
   ANSWER_FILE=$(echo "$SQL_FILE" | sed 's|/cases/|/answers/|; s|\.sql$|.answer|')
   diff "$ANSWER_FILE" "$RESULT_FILE"
   ```
2. **Server / broker logs** — `cat $CUBRID/log/server/*.err | tail -30`, `ls $CUBRID/log/broker/*.err`.
3. **Core dumps** — `ls "$RESULT_DIR"/core* $CUBRID/core*` → a core means a server crash.

**Classify the failure (answer-fix vs bug-report).** This is the decision the user actually needs — is the test wrong, or is CUBRID wrong?
- **answer-fix** (the `.answer` baseline is stale): the diff is a *format/identifier* change — plan-text formatting, XASL/SHA1 ids, cache keys, byte-counter shifts. The product behaves correctly; the baseline needs regenerating.
- **bug-report** (CUBRID regressed): a crash/core, a wrong query result, or a lock/deadlock change. Raise it with the evidence.
- **Cross-check with JIRA** when available: if the CBRD issue describes an *intentional* output change for this release, prefer answer-fix; if it describes this very failure mode, prefer bug-report and cite the issue.

## Output format

**Pass:**
```
[PASS] test_name.sql  (category: sql|medium|sql_by_cci)
  - Result: Total 1, Fail 0
  - Summary: <what the test verified>
```
**Fail:**
```
[FAIL] test_name.sql  (category: sql|medium|sql_by_cci)
  - Result: Total 1, Fail 1
  - Failed query: <the SQL statement that diverged>
  - Expected vs Actual: <answer line> | <result line>
  - Root cause: <diagnosis from the evidence>
  - Verdict: answer-fix | bug-report  (<one-line justification>)
  - Suggestion: <regenerate answer file | file a CUBRID bug | fix env>
```

## Common pitfalls

- **"No Results!!"** → SQL file path not found; check the absolute path and the `cases/` dir.
- **"Failed to connect to database server"** → missing locale lib (`make_locale.sh -t 64bit`), port conflict, or disk full.
- **"Cannot connect to a broker"** → broker not running or port 33120 occupied.
- **"socket path is too long (>108)"** → the CUBRID install path is too deep; the Unix socket `$CUBRID/var/CUBRID_SOCK/…` exceeds the OS 108-char limit, so broker/master won't start. Install to a short path (e.g. `~/CUBRID`), not a deeply nested dir.
- **No answer file** → interactive `run` **skips** the case (`Total:1 / Success:0 / Fail:0`) — it does not run. To generate a baseline: seed an empty `answers/<name>.answer`, run it (Fails vs empty and writes the real output to `$CTP_HOME/sql/result/…/sql/<name>.result`), then promote that `.result` to the answer.
- **javac not found** → `JAVA_HOME` points at a JRE, not a JDK (CTP compiles Java SP classes at DB setup). Fix `JAVA_HOME` to a JDK (Run step 2). Truly harmless only when no test uses Java SP.
