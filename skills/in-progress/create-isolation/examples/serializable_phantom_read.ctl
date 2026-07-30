/*
Test Case: Serializable - Phantom Read Prevention
Priority: 1
Reference case:
Author: tester

Test Plan:
Test that under SERIALIZABLE isolation, a transaction that performs
a range scan does not see newly inserted rows (phantoms) committed by
a concurrent transaction during the same transaction scope.

Test Scenario:
C1 opens a transaction and reads all rows where val > 0 (initial snapshot).
C2 inserts a new row with val=50 and commits.
C1 re-reads the same range — under SERIALIZABLE, C1 must not see the new row.
C1 commits its read-only transaction.
A final read by C1 in a new transaction confirms the inserted row is now visible.

Test Point:
1) C1's second range scan within the same SERIALIZABLE transaction returns
   the same rows as the first scan (no phantom row from C2)
2) After C1 commits and starts a new transaction, C2's inserted row is visible

NUM_CLIENTS = 2
C1: performs repeated range scans within a SERIALIZABLE transaction;
C2: inserts a new row and commits while C1's transaction is active;
*/

MC: setup NUM_CLIENTS = 2;

C1: login as 'dba';
C1: set transaction lock timeout INFINITE;
C1: set transaction isolation level serializable;

C2: set transaction lock timeout INFINITE;
C2: set transaction isolation level serializable;

/* preparation */
C1: DROP TABLE IF EXISTS t1;
C1: CREATE TABLE t1 (id INT PRIMARY KEY, val INT);
C1: INSERT INTO t1 VALUES (1, 10), (2, 20), (3, 30);
C1: COMMIT;
MC: wait until C1 ready;

/* test: C1 performs initial range scan — establishes snapshot */
C1: SELECT * FROM t1 WHERE val > 0 ORDER BY id;
MC: wait until C1 ready;

/* C2 inserts a new row and commits — this is the "phantom" row */
C2: INSERT INTO t1 VALUES (4, 50);
C2: COMMIT;
MC: wait until C2 ready;

/* C1 re-reads the same range within the same transaction
   Under SERIALIZABLE, result must be identical to the first scan (no phantom) */
C1: SELECT * FROM t1 WHERE val > 0 ORDER BY id;
C1: COMMIT;
MC: wait until C1 ready;

/* C1 starts a new transaction — C2's committed row is now visible */
C1: SELECT * FROM t1 WHERE val > 0 ORDER BY id;
C1: COMMIT;
MC: wait until C1 ready;

/* cleanup */
C1: DROP TABLE IF EXISTS t1;
C1: COMMIT;
MC: wait until C1 ready;

C1: quit;
C2: quit;
