package com.cubrid.jdbc.test;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import org.junit.Assert;
import org.junit.Test;

/**
 * Example: PreparedStatement usage including parameter binding and batch execution.
 */
public class TestPreparedStatement {

    private static final String DRIVER = PropertiesUtil.getValue(
            "jdbc.driverClassName", "jdbc.properties");
    private static final String URL = PropertiesUtil.getValue("jdbc.url",
            "jdbc.properties");
    private static final String USER = PropertiesUtil.getValue("jdbc.username",
            "jdbc.properties");
    private static final String PASS = PropertiesUtil.getValue("jdbc.password",
            "jdbc.properties");

    @Test
    public void testPreparedInsertAndSelect() throws SQLException, ClassNotFoundException {
        Class.forName(DRIVER);
        Connection conn = DriverManager.getConnection(URL, USER, PASS);
        try {
            Statement stmt = conn.createStatement();
            stmt.execute("DROP TABLE IF EXISTS t_ps");
            stmt.execute("CREATE TABLE t_ps (id INT PRIMARY KEY, val VARCHAR(100), score INT)");
            stmt.close();

            // INSERT with parameter binding
            PreparedStatement pstmt = conn.prepareStatement(
                    "INSERT INTO t_ps VALUES (?, ?, ?)");
            pstmt.setInt(1, 1);
            pstmt.setString(2, "hello");
            pstmt.setInt(3, 100);
            int rows = pstmt.executeUpdate();
            Assert.assertEquals(1, rows);

            pstmt.setInt(1, 2);
            pstmt.setString(2, "world");
            pstmt.setInt(3, 200);
            rows = pstmt.executeUpdate();
            Assert.assertEquals(1, rows);
            pstmt.close();

            // SELECT with parameter binding
            pstmt = conn.prepareStatement(
                    "SELECT val, score FROM t_ps WHERE id = ?");
            pstmt.setInt(1, 1);
            ResultSet rs = pstmt.executeQuery();
            Assert.assertTrue(rs.next());
            Assert.assertEquals("hello", rs.getString("val"));
            Assert.assertEquals(100, rs.getInt("score"));
            Assert.assertFalse(rs.next());
            rs.close();
            pstmt.close();

            // cleanup
            stmt = conn.createStatement();
            stmt.execute("DROP TABLE IF EXISTS t_ps");
            stmt.close();
        } finally {
            conn.close();
        }
    }

    @Test
    public void testPreparedStatementBatch() throws SQLException, ClassNotFoundException {
        Class.forName(DRIVER);
        Connection conn = DriverManager.getConnection(URL, USER, PASS);
        try {
            Statement stmt = conn.createStatement();
            stmt.execute("DROP TABLE IF EXISTS t_ps");
            stmt.execute("CREATE TABLE t_ps (id INT PRIMARY KEY, val VARCHAR(100), score INT)");
            stmt.close();

            // batch INSERT
            PreparedStatement pstmt = conn.prepareStatement(
                    "INSERT INTO t_ps VALUES (?, ?, ?)");
            for (int i = 1; i <= 5; i++) {
                pstmt.setInt(1, i);
                pstmt.setString(2, "item" + i);
                pstmt.setInt(3, i * 10);
                pstmt.addBatch();
            }
            int[] results = pstmt.executeBatch();
            Assert.assertEquals(5, results.length);
            for (int r : results) {
                Assert.assertEquals(1, r);
            }
            pstmt.close();

            // verify row count
            stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery("SELECT COUNT(*) FROM t_ps");
            Assert.assertTrue(rs.next());
            Assert.assertEquals(5, rs.getInt(1));
            rs.close();

            // cleanup
            stmt.execute("DROP TABLE IF EXISTS t_ps");
            stmt.close();
        } finally {
            conn.close();
        }
    }

    @Test
    public void testPreparedUpdate() throws SQLException, ClassNotFoundException {
        Class.forName(DRIVER);
        Connection conn = DriverManager.getConnection(URL, USER, PASS);
        try {
            Statement stmt = conn.createStatement();
            stmt.execute("DROP TABLE IF EXISTS t_ps");
            stmt.execute("CREATE TABLE t_ps (id INT PRIMARY KEY, val VARCHAR(100), score INT)");
            stmt.executeUpdate("INSERT INTO t_ps VALUES (1, 'original', 50)");
            stmt.close();

            // UPDATE via PreparedStatement
            PreparedStatement pstmt = conn.prepareStatement(
                    "UPDATE t_ps SET val = ?, score = ? WHERE id = ?");
            pstmt.setString(1, "updated");
            pstmt.setInt(2, 99);
            pstmt.setInt(3, 1);
            int rows = pstmt.executeUpdate();
            Assert.assertEquals(1, rows);
            pstmt.close();

            // verify
            stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery("SELECT val, score FROM t_ps WHERE id = 1");
            Assert.assertTrue(rs.next());
            Assert.assertEquals("updated", rs.getString("val"));
            Assert.assertEquals(99, rs.getInt("score"));
            rs.close();

            // cleanup
            stmt.execute("DROP TABLE IF EXISTS t_ps");
            stmt.close();
        } finally {
            conn.close();
        }
    }
}
