/**
 * This test case verifies CBRD-XXXXX: CDC replication of DDL schema changes
 *
 * Coverage:
 * 1 - CDC captures CREATE TABLE and initial INSERT
 * 2 - CDC captures ALTER TABLE ADD COLUMN
 * 3 - CDC captures data after column addition
 * 4 - CDC captures ALTER TABLE DROP COLUMN
 * 5 - CDC captures data after column removal
 * 6 - CDC captures RENAME TABLE (if supported)
 * 7 - CDC captures DROP TABLE
 */

-- Coverage 1: CREATE TABLE and initial data
--test: DROP TABLE IF EXISTS t1;
--test: CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
--test: COMMIT;

--test: INSERT INTO t1 VALUES (1, 'initial');
--test: INSERT INTO t1 VALUES (2, 'data');
--test: COMMIT;

--check: SELECT id, val FROM t1 ORDER BY id;

-- Coverage 2: ALTER TABLE ADD COLUMN
--test: ALTER TABLE t1 ADD COLUMN extra INT DEFAULT 0;
--test: COMMIT;

--check: SELECT id, val, extra FROM t1 ORDER BY id;

-- Coverage 3: Data insert after schema change
--test: INSERT INTO t1 VALUES (3, 'after_alter', 42);
--test: UPDATE t1 SET extra = 10 WHERE id = 1;
--test: COMMIT;

--check: SELECT id, val, extra FROM t1 ORDER BY id;

-- Coverage 4: ALTER TABLE DROP COLUMN
--test: ALTER TABLE t1 DROP COLUMN extra;
--test: COMMIT;

--check: SELECT id, val FROM t1 ORDER BY id;

-- Coverage 5: Data consistency after column removal
--test: INSERT INTO t1 VALUES (4, 'post_drop');
--test: UPDATE t1 SET val = 'modified' WHERE id = 2;
--test: COMMIT;

--check: SELECT id, val FROM t1 ORDER BY id;

-- Coverage 6: RENAME TABLE
--test: RENAME TABLE t1 TO t1_renamed;
--test: COMMIT;

--check: SELECT id, val FROM t1_renamed ORDER BY id;

-- Coverage 7: DROP TABLE — verify replication of table removal
--test: DROP TABLE IF EXISTS t1_renamed;
--test: COMMIT;
