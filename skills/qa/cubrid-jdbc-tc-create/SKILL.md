---
name: cubrid-jdbc-tc-create
description: "Create, draft, or scaffold a new CUBRID CTP JDBC testcase (JUnit 4 Java @Test method) from scratch — for a CBRD bug fix or feature. Use this whenever someone says \"jdbc tc 만들어줘\", \"jdbc tc 초안 작성해줘\", \"jdbc 테스트케이스 작성\", \"create jdbc test\", \"draft jdbc testcase\", or \"create jdbc tc for CBRD-XXXXX\", even if they don't say the word \"testcase\". They usually give a CBRD number, the behavior to test, and sometimes a target package. NOT for: running/reviewing existing JDBC tests, CTP configuration, general Java unrelated to CTP, or shell/SQL/CCI/HA testcases (use the matching cubrid-*-tc-* skill)."
---

# JDBC Testcase Creator (CTP)

Generate a CUBRID CTP JDBC testcase that passes review on the first try. A good testcase is one self-contained JUnit 4 `.java` class whose `@Test` methods CTP's `JdbcLocalTest` runner discovers, executes, and regression-tracks.

## Scope

**Produces:** the test class (one or more `@Test` methods owning their own setup/teardown), the correct package + directory, descriptive `test*` method names.

**Does NOT produce:** `jdbc.properties` / `conf/jdbc.conf` (CTP fills these at runtime), CTP framework changes, CI config, or shell/SQL/CCI/HA tests (route those to the matching `cubrid-*-tc-*` skill).

## Before you start

- **CTP must be installed.** Expect it at `$CTP_HOME`, `~/CTP`, or `~/cubrid-testtools/CTP`. Sanity check: `ls $CTP_HOME/bin/ctp.sh`. If absent, stop and tell the user to install it (`git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`).
- **JIRA context (optional).** If a `CBRD-XXXXX` is referenced, run `cubrid-jira search CBRD-XXXXX` first to ground the work (reuse if already fetched). If the CLI isn't installed, skip — but installing cubrid-jira improves accuracy.

## Directory convention

The package path is how CTP locates and categorizes a test; the package declaration and on-disk directory **must match**, and the class name must equal the filename.

```
# Root: cubrid-testcases-private/interface/JDBC/test_jdbc/src/com/cubrid/jdbc/test/
# Bug fix:   .../cbrd/TestCbrdXXXXX.java          pkg com.cubrid.jdbc.test.cbrd
# Feature:   .../spec/{connection|statement|resultset}/TestFeatureName.java
# General:   .../TestCaseNN.java                  pkg com.cubrid.jdbc.test
```

Class names: bug fix `TestCbrd27100`, feature `TestConnectionFeature` / `TestStatementFeature` / `TestResultSetFeature`, general `TestCase01`.

## Lifecycle contract

Each `@Test` method owns its full lifecycle. Missing a step fails review.

```java
package com.cubrid.jdbc.test;   // MUST match the on-disk directory

import java.sql.*;
import org.junit.Assert;
import org.junit.Test;

public class TestCbrdXXXXX {
    // Never hardcode connection params — CTP populates jdbc.properties at runtime.
    private static final String DRIVER = PropertiesUtil.getValue("jdbc.driverClassName", "jdbc.properties");
    private static final String URL  = PropertiesUtil.getValue("jdbc.url", "jdbc.properties");
    private static final String USER = PropertiesUtil.getValue("jdbc.username", "jdbc.properties");
    private static final String PASS = PropertiesUtil.getValue("jdbc.password", "jdbc.properties");

    @Test  // name MUST contain "test" — the runner matches by substring
    public void testFeatureName() throws SQLException, ClassNotFoundException {
        Class.forName(DRIVER);
        Connection conn = DriverManager.getConnection(URL, USER, PASS);
        try {
            Statement stmt = conn.createStatement();
            stmt.execute("DROP TABLE IF EXISTS t1");          // re-runnable
            stmt.execute("CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100))");
            stmt.execute("INSERT INTO t1 VALUES (1, 'hello')");

            ResultSet rs = stmt.executeQuery("SELECT val FROM t1 WHERE id = 1");
            Assert.assertTrue(rs.next());
            Assert.assertEquals("hello", rs.getString("val"));

            rs.close();
            stmt.execute("DROP TABLE IF EXISTS t1");          // cleanup
            stmt.close();
        } finally {
            conn.close();                                     // always reached
        }
    }
}
```

### Why each part matters (not just ritual)

- **`PropertiesUtil`, not literal URLs** — CTP injects host/port/charset per environment; a hardcoded URL only passes on one machine.
- **`finally { conn.close(); }`** — the connection must close even when an assertion throws, or the next test inherits a leaked session.
- **Method name contains "test"** — `JdbcLocalTest` finds methods by substring, not by `@Test` alone; a `verifyX` method silently never runs.
- **`throws SQLException, ClassNotFoundException`** — required wherever `Class.forName` / JDBC calls appear; don't swallow them in a generic try/catch.

## Essential helpers (use these, not raw equivalents)

| Use | Instead of | Why |
|---|---|---|
| `PropertiesUtil.getValue(k, "jdbc.properties")` | literal JDBC URL / user / pass | environment-portable; CTP fills the file at runtime |
| `@Ignore` above `@Test` | a commented-out method or `// skip` | JUnit reports it as skipped instead of silently dropping coverage |
| `Assert.assertEquals(expected, actual)` | `if (a != b) fail()` | precise diff on mismatch in the CTP report |
| try `{ bad-op; Assert.assertTrue(false); } catch (SQLException e) { Assert.assertTrue(true); }` | no assertion in catch | proves the *expected* exception actually fired |

Common asserts: `assertEquals` / `assertNotEquals` (values), `assertTrue` / `assertFalse` (conditions), `assertNull` / `assertNotNull` (references).

## Writing rules (principles, not ritual)

- **Self-contained methods** — each `@Test` does its own `DROP TABLE IF EXISTS` → `CREATE` → act → assert → `DROP`. Don't share state via `@Before`/`@After`; a method must pass when run alone.
- **Close in reverse order** — `ResultSet` → `Statement` → `Connection`, with the `Connection` close in `finally`.
- **Minimal, diffable data** — create only the tables/rows the case needs; use simple values (`1`, `'hello'`) so a mismatch is obvious.
- **Expected exceptions are assertions** — use the catch-block pattern above; never let a "should throw" path fall through silently.
- **No hardcoded paths or URLs** — route any scratch file through `Files.createTempFile(...)` or cwd, never `/tmp`/`/home`.
- **`@Ignore` for disabled tests** — annotate, with a one-line reason (e.g. blocked on CBRD-XXXXX); don't comment out the body.

## House idioms (quick recipes)

- **Parameter binding:** `PreparedStatement ps = conn.prepareStatement("... WHERE id = ?"); ps.setInt(1, 1);` — see `@examples/TestPreparedStatement.java`.
- **Batch:** `ps.addBatch()` in a loop, then `ps.executeBatch()`; assert the returned `int[]` length/contents.
- **Scrollable / read-only ResultSet:** `conn.createStatement(ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY)`; assert `rs.updateX` throws.
- **Reading values:** prefer column-name getters (`rs.getString("val")`) over index getters so a column-order change doesn't silently pass.

## Verify before claiming done

After authoring, prove the testcase actually compiles and runs — don't just eyeball it.

1. **Pod-first:** if a k8s test-shell pod is reachable, run it there for real (install a build, inject the class under the right package dir, run via `ctp.sh`, read the CTP report for pass/fail). This is ground truth.
2. **Local fallback** (no pod is a clean, expected path): `work=$(mktemp -d)` and `javac -cp "<junit+cubrid-jdbc jars>" -d "$work" TestCbrdXXXXX.java` to confirm it compiles; eyeball the assertions against the JIRA reproduction.

## Self-review checklist

- Package declaration == on-disk directory? Class name == filename? Correct bucket (`cbrd` / `spec/*` / general)?
- Every `@Test` self-contained (`DROP IF EXISTS` → act → assert → `DROP`), passes run alone?
- Resources closed in reverse order, `conn.close()` in `finally`?
- All method names contain "test"? `throws SQLException, ClassNotFoundException` where needed?
- Connection params via `PropertiesUtil` — no literal URLs/paths?
- Expected-exception paths assert in the catch block? `@Ignore` (not a comment) on disabled tests?
- Compiles (`javac`), and verified pod-first when a pod is available?

## Examples & references

- `@examples/TestBasicDml.java` — INSERT / SELECT / UPDATE / DELETE via `Statement`.
- `@examples/TestPreparedStatement.java` — `PreparedStatement` parameter binding and batch.
