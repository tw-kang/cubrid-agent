package com.cubrid.jdbc.test;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import org.junit.Assert;
import org.junit.Test;

/**
 * Example: basic DML operations via Statement.
 * Tests INSERT, SELECT, UPDATE, and DELETE against a simple table.
 */
public class TestBasicDml {

    private static final String DRIVER = PropertiesUtil.getValue(
            "jdbc.driverClassName", "jdbc.properties");
    private static final String URL = PropertiesUtil.getValue("jdbc.url",
            "jdbc.properties");
    private static final String USER = PropertiesUtil.getValue("jdbc.username",
            "jdbc.properties");
    private static final String PASS = PropertiesUtil.getValue("jdbc.password",
            "jdbc.properties");

    @Test
    public void testInsertAndSelect() throws SQLException, ClassNotFoundException {
        Class.forName(DRIVER);
        Connection conn = DriverManager.getConnection(URL, USER, PASS);
        try {
            Statement stmt = conn.createStatement();

            // setup
            stmt.execute("DROP TABLE IF EXISTS t_dml");
            stmt.execute("CREATE TABLE t_dml (id INT PRIMARY KEY, name VARCHAR(100))");

            // INSERT
            int rows = stmt.executeUpdate("INSERT INTO t_dml VALUES (1, 'alice')");
            Assert.assertEquals(1, rows);
            rows = stmt.executeUpdate("INSERT INTO t_dml VALUES (2, 'bob')");
            Assert.assertEquals(1, rows);

            // SELECT — verify both rows present
            ResultSet rs = stmt.executeQuery("SELECT COUNT(*) FROM t_dml");
            Assert.assertTrue(rs.next());
            Assert.assertEquals(2, rs.getInt(1));
            rs.close();

            // SELECT — verify specific row
            rs = stmt.executeQuery("SELECT name FROM t_dml WHERE id = 1");
            Assert.assertTrue(rs.next());
            Assert.assertEquals("alice", rs.getString("name"));
            Assert.assertFalse(rs.next());
            rs.close();

            // cleanup
            stmt.execute("DROP TABLE IF EXISTS t_dml");
            stmt.close();
        } finally {
            conn.close();
        }
    }

    @Test
    public void testUpdate() throws SQLException, ClassNotFoundException {
        Class.forName(DRIVER);
        Connection conn = DriverManager.getConnection(URL, USER, PASS);
        try {
            Statement stmt = conn.createStatement();

            // setup
            stmt.execute("DROP TABLE IF EXISTS t_dml");
            stmt.execute("CREATE TABLE t_dml (id INT PRIMARY KEY, name VARCHAR(100))");
            stmt.executeUpdate("INSERT INTO t_dml VALUES (1, 'alice')");

            // UPDATE
            int rows = stmt.executeUpdate("UPDATE t_dml SET name = 'charlie' WHERE id = 1");
            Assert.assertEquals(1, rows);

            // verify
            ResultSet rs = stmt.executeQuery("SELECT name FROM t_dml WHERE id = 1");
            Assert.assertTrue(rs.next());
            Assert.assertEquals("charlie", rs.getString("name"));
            rs.close();

            // cleanup
            stmt.execute("DROP TABLE IF EXISTS t_dml");
            stmt.close();
        } finally {
            conn.close();
        }
    }

    @Test
    public void testDelete() throws SQLException, ClassNotFoundException {
        Class.forName(DRIVER);
        Connection conn = DriverManager.getConnection(URL, USER, PASS);
        try {
            Statement stmt = conn.createStatement();

            // setup
            stmt.execute("DROP TABLE IF EXISTS t_dml");
            stmt.execute("CREATE TABLE t_dml (id INT PRIMARY KEY, name VARCHAR(100))");
            stmt.executeUpdate("INSERT INTO t_dml VALUES (1, 'alice')");
            stmt.executeUpdate("INSERT INTO t_dml VALUES (2, 'bob')");

            // DELETE
            int rows = stmt.executeUpdate("DELETE FROM t_dml WHERE id = 1");
            Assert.assertEquals(1, rows);

            // verify remaining
            ResultSet rs = stmt.executeQuery("SELECT COUNT(*) FROM t_dml");
            Assert.assertTrue(rs.next());
            Assert.assertEquals(1, rs.getInt(1));
            rs.close();

            // verify deleted row is gone
            rs = stmt.executeQuery("SELECT id FROM t_dml WHERE id = 1");
            Assert.assertFalse(rs.next());
            rs.close();

            // cleanup
            stmt.execute("DROP TABLE IF EXISTS t_dml");
            stmt.close();
        } finally {
            conn.close();
        }
    }
}
