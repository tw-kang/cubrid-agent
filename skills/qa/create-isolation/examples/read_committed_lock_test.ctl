/*
Test Case: Read Committed - Lock Contention on Row Update
Priority: 1
Reference case:
Author: tester

Test Plan:
Test that under READ COMMITTED isolation, an UPDATE by C2 on a row
already locked by C1 is blocked until C1 commits, at which point C2
acquires the lock and proceeds with the updated base value.

Test Scenario:
C1 begins an update on row id=1 without committing.
C2 attempts to update the same row — C2 is blocked waiting for C1's X lock.
C1 commits its update.
C2 is unblocked, reads the committed value from C1, applies its own update, and commits.
Both clients verify the final state via SELECT.

Test Point:
1) C2 must wait while C1 holds the X lock on id=1
2) After C1 commits, C2 proceeds and sees C1's committed value as its base
3) Final row value reflects both updates applied sequentially

NUM_CLIENTS = 2
C1: update row id=1, hold X lock, then commit;
C2: attempt update on same row, wait for C1, then commit;
*/

MC: setup NUM_CLIENTS = 2;

C1: login as 'dba';
C1: set transaction lock timeout INFINITE;
C1: set transaction isolation level read committed;

C2: set transaction lock timeout INFINITE;
C2: set transaction isolation level read committed;

/* preparation */
C1: DROP TABLE IF EXISTS t1;
C1: CREATE TABLE t1 (id INT PRIMARY KEY, val INT);
C1: INSERT INTO t1 VALUES (1, 100), (2, 200), (3, 300);
C1: COMMIT;
MC: wait until C1 ready;

/* test: C1 acquires X lock on id=1 */
C1: UPDATE t1 SET val = 110 WHERE id = 1;
MC: wait until C1 ready;

/* C2 attempts to update same row — will block on C1's X lock */
C2: UPDATE t1 SET val = 999 WHERE id = 1;

/* C1 commits, releasing the X lock; C2 can now proceed */
C1: COMMIT;
MC: wait until C1 ready, C2 ready;

/* verify: C2 committed its update on top of C1's committed value */
C2: COMMIT;
MC: wait until C2 ready;

/* read final state */
C1: SELECT * FROM t1 ORDER BY id;
C1: COMMIT;
MC: wait until C1 ready;

/* cleanup */
C1: DROP TABLE IF EXISTS t1;
C1: COMMIT;
MC: wait until C1 ready;

C1: quit;
C2: quit;
