/**
 * This test case verifies CBRD-XXXXX: CDC replication of basic DML operations
 *
 * Coverage:
 * 1 - CDC captures single-row INSERT
 * 2 - CDC captures multi-row INSERT
 * 3 - CDC captures UPDATE on a single row
 * 4 - CDC captures UPDATE on multiple rows
 * 5 - CDC captures DELETE on a single row
 * 6 - CDC captures DELETE on all rows
 * 7 - Verify empty table state is consistent after full DELETE
 */

--test: DROP TABLE IF EXISTS t1;
--test: CREATE TABLE t1 (id INT PRIMARY KEY, name VARCHAR(100), score INT);
--test: COMMIT;

-- Coverage 1: Single-row INSERT
--test: INSERT INTO t1 VALUES (1, 'alice', 90);
--test: COMMIT;

--check: SELECT id, name, score FROM t1 ORDER BY id;

-- Coverage 2: Multi-row INSERT
--test: INSERT INTO t1 VALUES (2, 'bob', 75);
--test: INSERT INTO t1 VALUES (3, 'carol', 85);
--test: INSERT INTO t1 VALUES (4, 'dave', 60);
--test: COMMIT;

--check: SELECT id, name, score FROM t1 ORDER BY id;

-- Coverage 3: UPDATE single row
--test: UPDATE t1 SET score = 95 WHERE id = 1;
--test: COMMIT;

--check: SELECT id, name, score FROM t1 WHERE id = 1 ORDER BY id;

-- Coverage 4: UPDATE multiple rows
--test: UPDATE t1 SET score = score + 5 WHERE score < 80;
--test: COMMIT;

--check: SELECT id, name, score FROM t1 ORDER BY id;

-- Coverage 5: DELETE single row
--test: DELETE FROM t1 WHERE id = 4;
--test: COMMIT;

--check: SELECT id, name, score FROM t1 ORDER BY id;

-- Coverage 6: DELETE multiple rows
--test: DELETE FROM t1 WHERE score < 85;
--test: COMMIT;

--check: SELECT id, name, score FROM t1 ORDER BY id;

-- Coverage 7: DELETE all rows — verify empty state is replicated
--test: DELETE FROM t1;
--test: COMMIT;

--check: SELECT COUNT(*) FROM t1;

--test: DROP TABLE IF EXISTS t1;
--test: COMMIT;
