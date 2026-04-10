#!/bin/bash
# CBRD-XXXXX: Verify DML replication from master to slave
# Inserts, updates, and deletes rows on master, waits for replication,
# then compares SELECT output between master and slave to confirm data consistency.
# Requires: 1 master + 1 slave

. $init_path/init.sh
. $init_path/make_ha.sh
init test
set -x

# Setup HA: creates hatestdb on both nodes, configures HA, starts heartbeat
# After this call: masterHostName, slaveHostName, dbname=hatestdb are all set
setup_ha_environment

# --- Case 1: INSERT replication ---
csql -udba $dbname -c "
CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
INSERT INTO t1 VALUES (1, 'alpha');
INSERT INTO t1 VALUES (2, 'beta');
INSERT INTO t1 VALUES (3, 'gamma');
COMMIT;
"

wait_for_slave

csql -udba $dbname@$masterHostName -c "SELECT * FROM t1 ORDER BY id;" > master_insert.log
run_on_slave -c "csql -udba $dbname -c \"SELECT * FROM t1 ORDER BY id;\"" > slave_insert.log

format_csql_output master_insert.log
format_csql_output slave_insert.log
compare_result_between_files master_insert.log slave_insert.log

# --- Case 2: UPDATE replication ---
csql -udba $dbname -c "
UPDATE t1 SET val = 'updated' WHERE id = 1;
COMMIT;
"

wait_for_slave

csql -udba $dbname@$masterHostName -c "SELECT * FROM t1 ORDER BY id;" > master_update.log
run_on_slave -c "csql -udba $dbname -c \"SELECT * FROM t1 ORDER BY id;\"" > slave_update.log

format_csql_output master_update.log
format_csql_output slave_update.log
compare_result_between_files master_update.log slave_update.log

# --- Case 3: DELETE replication ---
csql -udba $dbname -c "
DELETE FROM t1 WHERE id = 3;
COMMIT;
"

wait_for_slave

csql -udba $dbname@$masterHostName -c "SELECT COUNT(*) FROM t1;" > master_delete.log
run_on_slave -c "csql -udba $dbname -c \"SELECT COUNT(*) FROM t1;\"" > slave_delete.log

format_csql_output master_delete.log
format_csql_output slave_delete.log
compare_result_between_files master_delete.log slave_delete.log

# --- Cleanup ---
revert_ha_environment
finish
