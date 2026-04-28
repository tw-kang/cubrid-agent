---
name: cubrid-jdbc-tc-runone
description: "Executes a single CUBRID JDBC testcase (JUnit Java class) and reports pass/fail. Invoke when the user asks to run a specific JDBC test — Korean: jdbc tc 돌려봐, jdbc 테스트 실행, jdbc tc 수행; English: \"run jdbc test\", \"execute jdbc tc\". A CUBRID build URL with a JDBC test path is a strong signal. NOT for: creating new JDBC tests (use cubrid-jdbc-tc-create), running full JDBC regression suites."
---

# JDBC Testcase Runner (CTP)

Run a single CUBRID JDBC testcase (JUnit 4 class) on the local machine, report the result, and analyze failures.

## 0. CTP Installation Check (mandatory first step)

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
ls $CTP_HOME/conf/
```

If `ctp.sh` or `conf/` is not found, **stop immediately** and display:

> "CTP is not installed. This skill cannot proceed.
> Install: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

The `cubrid-testcases-private` repository must also be present.

## 1. Install CUBRID

A build URL is required. If not provided, ask:
> "A CUBRID build file URL is required. Please provide the build URL."

```bash
sh ~/cubrid-testtools/CTP/common/script/run_cubrid_install <build_url> 2>&1 | tee /tmp/cubrid_install.log
grep '\[ERROR\]' /tmp/cubrid_install.log
source ~/.cubrid.sh && cubrid --version
```

`run_cubrid_install` does NOT exit non-zero on failure — always check for `[ERROR]` in the log and verify `cubrid --version` works. If either fails, stop and ask the user for a correct URL.

## 2. Identify the test class

JDBC testcases live in:
```
cubrid-testcases-private/interface/JDBC/test_jdbc/src/com/cubrid/jdbc/test/
```

Common subdirectories:
- `cbrd/TestCbrdXXXXX.java` — bug fix tests
- `spec/connection/`, `spec/statement/`, `spec/resultset/` — feature tests

If the user gives a partial name or CBRD number, locate the file:
```bash
find ~/cubrid-testcases-private/interface/JDBC -name "*.java" | grep -i "<pattern>"
```

## 3. Read the Java test file before running

Always read the test class before running to understand:
- Which `@Test` methods it contains
- What SQL operations it exercises
- What assertions it makes

This context is essential for diagnosing failures.

## 4. Prepare the environment

```bash
source ~/.cubrid.sh
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
cubrid service start
cubrid --version
java -version
```

Verify CUBRID service is running before proceeding.

## 5. Execute via CTP jdbc runner

Create a temp conf file pointing to the specific test class, then run via CTP:

```bash
# Derive the fully-qualified class name from the file path
# e.g. com.cubrid.jdbc.test.cbrd.TestCbrd27100

cat > /tmp/jdbc_runone.conf << EOF
scenario=$HOME/cubrid-testcases-private/interface/JDBC/test_jdbc
test_category=jdbc
testcase_include=<fully.qualified.ClassName>
EOF

$CTP_HOME/bin/ctp.sh jdbc -c /tmp/jdbc_runone.conf 2>&1 | tee /tmp/jdbc_runone_output.log
```

**Alternative — compile and run directly** (when CTP jdbc runner is unavailable):

```bash
TC_ROOT=$HOME/cubrid-testcases-private/interface/JDBC/test_jdbc
CLASSPATH=$TC_ROOT/lib/*:$TC_ROOT/target/classes
javac -cp $CLASSPATH -d $TC_ROOT/target/classes \
  $TC_ROOT/src/com/cubrid/jdbc/test/<path>/TestXXXXX.java
# Create jdbc.properties manually (CTP does this automatically from conf)
cat > $TC_ROOT/jdbc.properties << EOF
jdbc.driverClassName=cubrid.jdbc.driver.CUBRIDDriver
jdbc.url=jdbc:cubrid:localhost:33000:demodb:::
jdbc.username=public
jdbc.password=
EOF
java -cp $CLASSPATH org.junit.runner.JUnitCore com.cubrid.jdbc.test.<package>.TestXXXXX
```

Adjust `33000` and `demodb` to match the running broker port and database.

## 6. Check the result

Scan the output log for pass/fail indicators:

```bash
grep -E "OK|FAIL|Tests run|ERROR" /tmp/jdbc_runone_output.log | tail -20
```

CTP output contains lines like:
- `Tests run: 1, Failures: 0, Errors: 0` — passed
- `Tests run: 1, Failures: 1, Errors: 0` — assertion failed
- `Tests run: 1, Failures: 0, Errors: 1` — exception thrown

## 7. Failure analysis (when fail/error > 0)

### Step A: Read the Java stack trace

```bash
grep -A 20 "FAIL\|ERROR\|Exception" /tmp/jdbc_runone_output.log | head -60
```

Key patterns:
- `AssertionError` — assertion failed; compare expected vs actual values in the trace
- `SQLException` — database or driver error; check the SQL error code and message
- `ClassNotFoundException` — CUBRID JDBC driver jar not on classpath
- `Connection refused` — CUBRID broker not running or wrong port

### Step B: Check CUBRID server and broker logs

```bash
cat $CUBRID/log/server/*.err 2>/dev/null | tail -30
ls -la $CUBRID/log/broker/*.err 2>/dev/null
```

### Step C: Verify connection properties

When running manually, confirm `jdbc.properties` points to a running database and the broker port is correct: `cubrid server status && cubrid broker status -b`.

### Step E: Synthesize the diagnosis

1. **Result**: PASS or FAIL
2. **What the test does**: from reading the Java class
3. **Failed method**: which `@Test` method failed
4. **Root cause**: `AssertionError` (logic mismatch) / `SQLException` (DB error) / env issue
5. **Relevant trace lines**: the actual assertion or exception
6. **Suggestion**: test bug, CUBRID bug, or environment issue

## 8. Cleanup

```bash
rm -f /tmp/jdbc_runone.conf /tmp/jdbc_runone_output.log
```

## Output Format

**On success:**
```
[PASS] TestClassName
  - Tests run: 1, Failures: 0, Errors: 0
  - Summary: <what the test verified>
```

**On failure:**
```
[FAIL] TestClassName
  - Tests run: 1, Failures: 1, Errors: 0
  - Failed method: <testMethodName>
  - Root cause: <AssertionError|SQLException|other>
  - Key trace:
    <relevant stack trace lines>
  - Suggestion: <what to fix>
```

## Common Issues

- **`Connection refused` / `Cannot connect to a broker`** — CUBRID service not started; run `cubrid service start` and verify with `cubrid broker status -b`.
- **`ClassNotFoundException: cubrid.jdbc.driver.CUBRIDDriver`** — CUBRID JDBC jar not on classpath; check `$TC_ROOT/lib/` contains `CUBRID-JDBC-*.jar`.
- **`jdbc.properties` not found** — running manually without CTP; create the properties file manually with the correct host, port, and database name.
- **`AssertionError` with unexpected value** — the actual CUBRID output differs from what the test expects; use the stack trace to find which `Assert` line failed, then check if it is a test bug or a CUBRID regression.
- **Method not found / zero tests run** — test method name does not contain "test"; CTP finds test methods by substring match — rename to `testXxx`.
