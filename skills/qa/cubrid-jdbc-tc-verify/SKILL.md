---
name: cubrid-jdbc-tc-verify
description: "Run one CUBRID JDBC testcase (a JUnit 4 Java class) on this machine, judge PASS/FAIL, and on failure diagnose the root cause. Use whenever someone wants to physically run a specific JDBC test and know whether it passes and why — Korean: \"jdbc tc 돌려봐\", \"jdbc 테스트 실행\", \"jdbc tc 수행\", \"패스하는지 확인\", \"검증해줘\", \"실패 원인 알려줘\"; English: \"run jdbc test\", \"execute jdbc tc\", \"verify\", \"check if it passes\". A CUBRID build URL alongside a JDBC test path is a strong signal — invoke this skill. NOT for: creating new JDBC tests (use cubrid-jdbc-tc-create) or running full JDBC regression suites."
---

# JDBC Testcase Verifier (CTP)

Run a single CUBRID JDBC testcase (JUnit 4 class), report PASS/FAIL, and — when it fails — diagnose *why* from the stack trace and server logs. "Verify" means all three: **run → judge → diagnose**, not just execute.

## Scope

**Does:** install a given CUBRID build, locate and run one JDBC `Test*.java` class, read its JUnit result, and on FAIL trace the failure to a root cause with a fix recommendation.

**Does NOT:** edit/review test code, create tests, run full suites, or bisect a batch of failures across commits.

## Before you start

- **CTP installed.** Resolve `$CTP_HOME` (env → `~/CTP` → `~/cubrid-testtools/CTP`). Sanity check: `ls $CTP_HOME/bin/ctp.sh $CTP_HOME/conf/`. If absent, stop and tell the user to install it (`git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`). The testcase repo (`cubrid-testcases-private`) must also be present; CUBRID itself need not be pre-installed.
- **Build URL.** A CUBRID build URL is required to install the binary under test. If not given, ask for it.
- **JIRA context (optional).** If a `CBRD-XXXXX` is referenced, run `cubrid-jira search CBRD-XXXXX` first to ground the work (reuse if already fetched). If the CLI isn't installed, skip — but installing `cubrid-jira` improves accuracy.

## Run

Work from a scratch dir so logs never collide: `work=$(mktemp -d)`.

1. **Install CUBRID** and verify it really worked — `run_cubrid_install` returns 0 even on failure, so trust the binary, not the exit code:
   ```bash
   sh "$CTP_HOME/common/script/run_cubrid_install" <build_url> 2>&1 | tee "$work/install.log"
   grep '\[ERROR\]' "$work/install.log" && { echo "install failed"; }   # stop & show these lines if present
   source ~/.cubrid.sh && cubrid --version                               # must print a version
   ```
2. **Locate the test class** — JDBC tests live under `~/cubrid-testcases-private/interface/JDBC/test_jdbc/src/com/cubrid/jdbc/test/` (`cbrd/TestCbrdXXXXX.java` for bug fixes; `spec/{connection,statement,resultset}/` for features). From a partial name or CBRD number: `find ~/cubrid-testcases-private/interface/JDBC -name '*.java' | grep -i '<pattern>'`.
3. **Read the Java class first** — know its `@Test` methods, the SQL it exercises, and its assertions. This is what makes a failure diagnosable.
4. **Start the service**, then execute via the CTP jdbc runner with a per-class conf:
   ```bash
   source ~/.cubrid.sh; export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
   cubrid service start
   printf 'scenario=%s\ntest_category=jdbc\ntestcase_include=%s\n' \
     "$HOME/cubrid-testcases-private/interface/JDBC/test_jdbc" "<fully.qualified.ClassName>" > "$work/runone.conf"
   "$CTP_HOME/bin/ctp.sh" jdbc -c "$work/runone.conf" 2>&1 | tee "$work/run.log"
   ```
   CTP matches test methods by the substring `test` — a method without it runs zero tests.

## Verdict

Read the JUnit tally from the run log and report it verbatim:
```bash
grep -E 'Tests run|FAIL|ERROR|Exception' "$work/run.log" | tail -20
```
`Tests run: N, Failures: 0, Errors: 0` → PASS. Any `Failures` (assertion) or `Errors` (exception), a timeout, or a crash → FAIL; proceed to Failure analysis. After the verdict, check for leftovers (`cubrid server status`) and offer cleanup.

## Failure analysis

On FAIL, gather evidence then classify — don't guess:

1. **Java stack trace** (`$work/run.log`) — `grep -A20 'FAIL\|ERROR\|Exception'`. `AssertionError` = expected vs actual mismatch; `SQLException` = DB/driver error (note the error code); `ClassNotFoundException`/`Connection refused` = env, not a real failure.
2. **Server / broker logs** — `cat $CUBRID/log/server/*.err`, `ls $CUBRID/log/broker/*.err`.
3. **Core dumps** — `ls $CUBRID/core*` → a core means a server crash.
4. **Connection** — confirm the broker is up and the conf's host/port/db match: `cubrid server status && cubrid broker status -b`.

**Classify the failure (test-fix vs bug-report).** This is the decision the user actually needs — is the test wrong, or is CUBRID wrong?
- **test-fix** (the test's expectation is stale): the `AssertionError` reflects an *intentional* output/format change, or the test hard-codes an env detail (port, db name) that drifted. The product behaves correctly; the test needs updating.
- **bug-report** (CUBRID regressed): a crash/core, a wrong query result, an unexpected `SQLException`, or a driver fault. Raise it with the evidence.
- **Cross-check with JIRA** when available: if the CBRD issue describes an *intentional* change for this release, prefer test-fix; if it describes this very failure mode, prefer bug-report and cite the issue.

## Output format

**Pass:**
```
[PASS] TestClassName
  - Result: Tests run: N, Failures: 0, Errors: 0
  - Summary: <what the test verified>
```
**Fail:**
```
[FAIL] TestClassName
  - Result: Tests run: N, Failures: F, Errors: E
  - Summary: <what the test verified>
  - Failed method: <testMethodName>
  - Root cause: <AssertionError | SQLException | crash | env>
  - Verdict: test-fix | bug-report  (<one-line justification>)
  - Key trace: <quoted stack-trace lines>
  - Suggestion: <fix the test | file a CUBRID bug | fix env>
```

## Common pitfalls

- **`Connection refused` / `Cannot connect to a broker`** → service not started; `cubrid service start`, verify with `cubrid broker status -b`.
- **`ClassNotFoundException: cubrid.jdbc.driver.CUBRIDDriver`** → JDBC jar not on classpath; check `test_jdbc/lib/` holds `CUBRID-JDBC-*.jar`.
- **Zero tests run** → the method name lacks the substring `test`; CTP finds tests by substring match.
- **Env unset** → `source ~/.cubrid.sh`; ensure `JAVA_HOME` points at a real JDK.
