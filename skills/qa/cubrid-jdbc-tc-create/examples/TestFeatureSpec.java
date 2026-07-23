package com.cubrid.jdbc.test.spec.statement;

import org.junit.Assert;
import org.junit.Test;

import com.cubrid.jdbc.test.spec.GeneralTestCase;

/**
 * Spec-pattern JDBC testcase — for a JDBC spec / feature (not a single bug).
 *
 * On disk:  src/com/cubrid/jdbc/test/spec/<category>/Test<Feature>.java
 *           <category> in { connection, statement, resultset, metadata, transaction }
 *
 * Extends GeneralTestCase: the base owns the lifecycle — its @Before opens the
 * connection(s) via ConnectionProvider and its @After closes them — so this
 * class only declares @Test methods and uses conn() plus the inherited static
 * helpers (createTable, dropTable, insertRow, getCount, queryAsList, executeSql).
 */
public class TestFeatureSpec extends GeneralTestCase {

    @Test
    public void test1() throws Exception {
        dropTable(conn(), "t1");                                  // re-runnable
        createTable(conn(), "t1", "a int primary key", "b varchar(100)");
        insertRow(conn(), "t1", "a, b", 1, "hello");             // columns string + value varargs
        Assert.assertEquals(1, getCount(conn(), "t1", null));
        dropTable(conn(), "t1");
    }
}
