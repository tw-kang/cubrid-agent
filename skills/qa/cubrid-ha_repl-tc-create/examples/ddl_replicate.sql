/**
 * This test case verifies CBRD-XXXXX: HA replication of DDL operations
 *
 * Coverage:
 * 1 - Replicate CREATE TABLE and initial data to slave
 * 2 - Replicate ALTER TABLE ADD COLUMN and verify new column on slave
 * 3 - Replicate CREATE INDEX and verify index-driven query results
 * 4 - Replicate ALTER TABLE DROP COLUMN and verify schema on slave
 * 5 - Replicate DROP TABLE and verify table is gone on slave
 */

--test: DROP TABLE IF EXISTS t1;
--test: CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
--test: INSERT INTO t1 VALUES (1, 'alpha');
--test: INSERT INTO t1 VALUES (2, 'beta');
--test: INSERT INTO t1 VALUES (3, 'gamma');
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: ALTER TABLE t1 ADD COLUMN extra INT DEFAULT 0;
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: UPDATE t1 SET extra = id * 10;
--test: COMMIT;

--check: SELECT id, val, extra FROM t1 ORDER BY id;

--test: CREATE INDEX idx_t1_val ON t1 (val);
--test: COMMIT;

--check: SELECT * FROM t1 WHERE val = 'beta' ORDER BY id;

--test: INSERT INTO t1 VALUES (4, 'delta', 40);
--test: INSERT INTO t1 VALUES (5, 'epsilon', 50);
--test: COMMIT;

--check: SELECT COUNT(*) FROM t1;
--check: SELECT * FROM t1 ORDER BY id;

--test: DROP INDEX idx_t1_val ON t1;
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: ALTER TABLE t1 DROP COLUMN extra;
--test: COMMIT;

--check: SELECT * FROM t1 ORDER BY id;

--test: DROP TABLE IF EXISTS t1;
--test: COMMIT;

--check: SELECT COUNT(*) FROM db_class WHERE class_name = 't1';
