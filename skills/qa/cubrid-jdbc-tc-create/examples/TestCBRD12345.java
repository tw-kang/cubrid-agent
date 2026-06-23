package cubrid.jdbc.driver;

import java.sql.SQLException;
import java.sql.Types;

import org.junit.After;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;

import cubrid.jdbc.ConnectionProvider;
import cubrid.jdbc.SqlUtil;
import cubrid.jdbc.SqlUtil.Arg;

/**
 * Driver-pattern JDBC testcase — the DEFAULT for a CBRD bug / regression.
 *
 * On disk:  src/cubrid/jdbc/driver/TestCBRD12345.java   (package == directory)
 * Class name starts with "Test" so Ant batchtest discovers it (Test-prefixed
 * class files), and CTP's JdbcLocalTest runs every @Test method.
 *
 * Standard JUnit 4 shape: @Before opens the connection via ConnectionProvider
 * (CTP rewrites jdbc.properties with the live broker port at runtime, so never
 * hardcode a URL), each test<N>() is one scenario, @After always cleans up and
 * closes — even when a @Test throws.
 */
public class TestCBRD12345 {

    private static final String TABLE = "t1";
    CUBRIDConnection conn;                       // same package — no import needed

    @Before
    public void before() throws SQLException {
        conn = ConnectionProvider.getConnection();
    }

    @Test
    public void test1() throws SQLException {
        SqlUtil.createTable(conn, TABLE, "a int primary key", "b varchar(100)");
        SqlUtil.insertRow(conn, TABLE,
                new Arg("a", Types.INTEGER, "1"),
                new Arg("b", Types.VARCHAR, "hello"));
        Assert.assertEquals(1, SqlUtil.getCount(conn, TABLE, null));
    }

    @Test(expected = SQLException.class)         // expected exception is an annotation, not try/catch
    public void test2() throws SQLException {
        SqlUtil.createTable(conn, TABLE, "a int primary key");
        SqlUtil.insertRow(conn, TABLE, new Arg("a", Types.INTEGER, "1"));
        SqlUtil.insertRow(conn, TABLE, new Arg("a", Types.INTEGER, "1"));   // duplicate PK -> SQLException
    }

    @After
    public void after() throws SQLException {
        SqlUtil.dropTable(conn, TABLE);
        conn.close();
    }
}
