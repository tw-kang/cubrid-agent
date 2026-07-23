/**
 * This test case verifies CBRD-XXXXX: HA replication of INSERT/UPDATE/DELETE operations
 *
 * Coverage:
 * 1 - Replicate INSERT operations from master to slave
 * 2 - Verify data consistency after UPDATE
 * 3 - Verify data consistency after DELETE
 * 4 - Verify empty table state after full DELETE
 */

--test: DROP TABLE IF EXISTS t1;
--test: CREATE TABLE t1 (id INT PRIMARY KEY, name VARCHAR(100), score INT);
--test: INSERT INTO t1 VALUES (1, 'alice', 90);
--test: INSERT INTO t1 VALUES (2, 'bob', 75);
--test: INSERT INTO t1 VALUES (3, 'carol', 85);
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: INSERT INTO t1 VALUES (4, 'dave', 60);
--test: INSERT INTO t1 VALUES (5, 'eve', 95);
--test: COMMIT;

--check: SELECT COUNT(*) FROM t1;
--check: SELECT * FROM t1 ORDER BY id;

--test: UPDATE t1 SET score = 80 WHERE id = 2;
--test: COMMIT;

--check: SELECT * FROM t1 WHERE id = 2;
--check: SELECT * FROM t1 ORDER BY id;

--test: UPDATE t1 SET score = score + 5 WHERE score < 80;
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: DELETE FROM t1 WHERE id = 3;
--test: COMMIT;

--check: SELECT COUNT(*) FROM t1;
--check: SELECT * FROM t1 ORDER BY id;

--test: DELETE FROM t1 WHERE score < 70;
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: DELETE FROM t1;
--test: COMMIT;

--check: SELECT COUNT(*) FROM t1;

--test: DROP TABLE IF EXISTS t1;
--test: COMMIT;
