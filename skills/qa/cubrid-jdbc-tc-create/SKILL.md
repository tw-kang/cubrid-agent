---
name: cubrid-jdbc-tc-create
description: "Use this skill whenever the user wants to create, draft, write, or scaffold a new JDBC testcase (JUnit 4 Java @Test method) for CUBRID CTP. Common requests: \"jdbc tc 만들어줘\", \"jdbc testcase\", \"jdbc tc 초안\", \"create jdbc test\", \"jdbc 테스트케이스 작성\", \"create jdbc tc for CBRD-XXXXX\". NOT for: running existing JDBC tests, reviewing diffs/PRs, CTP configuration, or general Java coding unrelated to CTP test creation."
---

# JDBC Testcase Creator (CTP)

Generate well-formed CUBRID CTP JDBC testcase files (JUnit 4 Java `.java` classes).

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
ls $CTP_HOME/conf/
```

If `ctp.sh` or `conf/` is not found, stop and display:

> "CTP is not installed. This skill cannot proceed.
> Installation methods:
> - Option 1: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> - Option 2: `git clone https://github.com/CUBRID/cubrid-testtools.git` and use `~/cubrid-testtools/CTP` directly
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

## JIRA Issue Context (do this when a CBRD-XXXXX is referenced)

When the request includes a `CBRD-XXXXX` ticket, **invoke the `jira` skill first** to fetch the issue background — title, description, reproduction steps, affected components, and comments — before generating the testcase. This grounds the test in the issue's actual requirements rather than guesswork.

**Already fetched in this conversation?** Reuse the context — do not re-invoke. The fetcher caches issues, but the conversation should not redundantly re-display them.

1. **Normalize the ticket ID** — `jira_search.py` requires the canonical `CBRD-NNNNN` form. Filenames typically use `cbrd_NNNNN`:

   ```bash
   TICKET=$(echo "$RAW_INPUT" | grep -oiE 'cbrd[-_ ]?[0-9]+' | head -1 \
            | tr '[:lower:]' '[:upper:]' \
            | sed -E 's/^CBRD[-_ ]?/CBRD-/')
   ```

2. **Locate the `jira` skill** — search project-scope, user-scope, plugin cache, and any `CLAUDE_PLUGIN_ROOT` install path. Do **not** rely on developer-specific paths:

   ```bash
   JIRA_SCRIPT=""
   for d in \
       "$(pwd)/.claude/skills/jira" \
       "$HOME/.claude/skills/jira" \
       "$HOME/.claude/plugins/skills/jira" \
       "$HOME/skills/jira" \
       "${CLAUDE_PLUGIN_ROOT:-}/skills/jira"
   do
       [ -n "$d" ] && [ -f "$d/scripts/jira_search.py" ] && JIRA_SCRIPT="$d/scripts/jira_search.py" && break
   done
   ```

3. **If the skill is available** — prefer the slash form `/jira CBRD-XXXXX` when the harness exposes it (it honors the upstream `pandoc` prerequisite gate). Otherwise call the bundled script directly. Warn the user when `pandoc` is missing so they know the description/comments will fall back to raw Jira-wiki markup:

   ```bash
   command -v pandoc >/dev/null 2>&1 || \
       echo "WARNING: pandoc not installed — JIRA description/comments will be raw wiki markup (degraded readability)."
   python3 "$JIRA_SCRIPT" "$TICKET"
   ```

   Let the summary, description, and comments drive the testcase scope, expected behavior, and edge cases.

4. **If the skill is missing** — **halt and ask the user**:

   > The `jira` skill is required to fetch CBRD-XXXXX context for accurate testcase generation, but it is not installed. May I install it from this repo (`tw-kang/skills`) now?
   > Suggested: `npx skills add tw-kang/skills -s jira -a claude-code`
   >
   > After install, re-run the discovery step above. If the script is still not found, the install path may differ on this system — please report which directory under `~/.claude/` or the plugin cache contains the new `jira/scripts/jira_search.py`.

   Wait for explicit confirmation. If the user declines, proceed without JIRA context and warn them that issue-specific details may be missing.

5. **No CBRD-XXXXX in the request** — skip this section.

## Directory Path Convention

### Bug fixes (CBRD issue)

```
cubrid-testcases-private/interface/JDBC/test_jdbc/src/com/cubrid/jdbc/test/cbrd/TestCbrdXXXXX.java
```

### Feature-specific tests

```
cubrid-testcases-private/interface/JDBC/test_jdbc/src/com/cubrid/jdbc/test/spec/connection/TestFeatureName.java
cubrid-testcases-private/interface/JDBC/test_jdbc/src/com/cubrid/jdbc/test/spec/statement/TestFeatureName.java
cubrid-testcases-private/interface/JDBC/test_jdbc/src/com/cubrid/jdbc/test/spec/resultset/TestFeatureName.java
```

### General test cases

```
cubrid-testcases-private/interface/JDBC/test_jdbc/src/com/cubrid/jdbc/test/TestCaseNN.java
```

## Class and Method Naming

| Test type | Class name | Package |
|-----------|-----------|---------|
| CBRD issue bug fix | `TestCbrd27100` | `com.cubrid.jdbc.test.cbrd` |
| Connection feature | `TestConnectionFeature` | `com.cubrid.jdbc.test.spec.connection` |
| Statement feature | `TestStatementFeature` | `com.cubrid.jdbc.test.spec.statement` |
| ResultSet feature | `TestResultSetFeature` | `com.cubrid.jdbc.test.spec.resultset` |
| General | `TestCase01` | `com.cubrid.jdbc.test` |

- Method names **must contain "test"** (CTP runner finds test methods by name substring match)
- Use descriptive names: `testInsertAndSelect`, `testPreparedStatementBatch`, `testScrollableResultSet`

## JDBC Test Structure

```java
package com.cubrid.jdbc.test;                    // adjust to target package

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import org.junit.Assert;
import org.junit.Ignore;
import org.junit.Test;

public class TestCbrdXXXXX {

    private static final String DRIVER = PropertiesUtil.getValue(
            "jdbc.driverClassName", "jdbc.properties");
    private static final String URL = PropertiesUtil.getValue("jdbc.url",
            "jdbc.properties");
    private static final String USER = PropertiesUtil.getValue("jdbc.username",
            "jdbc.properties");
    private static final String PASS = PropertiesUtil.getValue("jdbc.password",
            "jdbc.properties");

    @Test
    public void testFeatureName() throws SQLException, ClassNotFoundException {
        Class.forName(DRIVER);
        Connection conn = DriverManager.getConnection(URL, USER, PASS);
        try {
            Statement stmt = conn.createStatement();
            stmt.execute("DROP TABLE IF EXISTS t1");
            stmt.execute("CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100))");
            stmt.execute("INSERT INTO t1 VALUES (1, 'hello')");

            ResultSet rs = stmt.executeQuery("SELECT * FROM t1 WHERE id = 1");
            Assert.assertTrue(rs.next());
            Assert.assertEquals(1, rs.getInt("id"));
            Assert.assertEquals("hello", rs.getString("val"));
            rs.close();

            stmt.execute("DROP TABLE IF EXISTS t1");
            stmt.close();
        } finally {
            conn.close();
        }
    }

    @Ignore   // temporarily skip this test
    @Test
    public void testIgnoredCase() throws SQLException, ClassNotFoundException {
        // disabled until CBRD-XXXXX is resolved
    }
}
```

## PropertiesUtil — Connection Setup

**Never hardcode connection URLs.** Use `PropertiesUtil` as shown in the template above. `jdbc.properties` is populated at test runtime by CTP from `conf/jdbc.conf`.

## JUnit Assert Reference

| Assert method | Use when |
|---------------|----------|
| `Assert.assertEquals(expected, actual)` | Values must be equal (int, String, long, double…) |
| `Assert.assertNotEquals(unexpected, actual)` | Values must differ |
| `Assert.assertTrue(condition)` | Boolean condition must be true |
| `Assert.assertFalse(condition)` | Boolean condition must be false |
| `Assert.assertNull(object)` | Reference must be null |
| `Assert.assertNotNull(object)` | Reference must not be null |
| `Assert.assertTrue(false)` inside catch | Fail the test explicitly (unexpected code path reached) |
| `Assert.assertTrue(true)` inside catch | Pass when expected exception is caught |

For expected exceptions:

```java
try {
    rs.updateString("col", "val");   // should throw on READ_ONLY ResultSet
    Assert.assertTrue(false);        // must not reach here
} catch (SQLException e) {
    Assert.assertTrue(true);         // expected
}
```

## Writing Rules

1. **Always close resources**: Close `ResultSet`, `Statement`, and `Connection` in reverse order of creation.
2. **Use try-finally**: Wrap the body in `try { ... } finally { conn.close(); }` to guarantee connection cleanup even on assertion failure.
3. **DROP TABLE IF EXISTS before CREATE TABLE**: Makes the test re-runnable.
4. **Cleanup at end**: Drop test tables at the end of each test method (not in `@After`), so each `@Test` is self-contained.
5. **No hardcoded URLs**: Use `PropertiesUtil` for all connection parameters.
6. **Minimal setup**: Create only the tables and rows needed for the specific test.
7. **Simple data values**: Use simple, easily-diffable values (`1`, `'hello'`, `'abc'`).
8. **@Ignore for disabled tests**: Add `@Ignore` above `@Test` (not just a comment) to skip a test properly.
9. **throws declaration**: Declare `throws SQLException, ClassNotFoundException` on test methods that call `Class.forName`.
10. **Method name must contain "test"**: CTP's `JdbcLocalTest` runner identifies test methods by substring "test".

## Self-Review Checklist

Before presenting output, verify:
- `DROP TABLE IF EXISTS` before `CREATE TABLE`?
- Resources closed in `finally`?
- No hardcoded URLs?
- Method name contains "test"?
- `@Ignore` above `@Test` (not standalone)?
- Package matches directory?

## Examples

- `@examples/TestBasicDml.java` — INSERT / SELECT / UPDATE / DELETE via `Statement`
- `@examples/TestPreparedStatement.java` — `PreparedStatement` with parameter binding and batch
