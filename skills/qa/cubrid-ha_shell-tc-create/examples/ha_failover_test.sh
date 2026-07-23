#!/bin/bash
# CBRD-XXXXX: Verify failover — slave promotes to master when master's cub_server is stopped
# Sends SIGSTOP to cub_server to simulate isolation, waits for slave to be promoted,
# then resumes master and verifies data consistency between nodes.
# Requires: 1 master + 1 slave

. $init_path/init.sh
. $init_path/make_ha.sh
init test
set -x

# Setup HA: creates hatestdb on both nodes, configures HA, starts heartbeat
setup_ha_environment

# --- Setup: insert initial data on master ---
csql -udba $dbname -c "
CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
INSERT INTO t1 VALUES (1, 'initial');
COMMIT;
"

wait_for_slave

# Verify initial replication is working
csql -udba $dbname@$masterHostName -c "SELECT COUNT(*) FROM t1;" > before_failover_master.log
run_on_slave -c "csql -udba $dbname -c \"SELECT COUNT(*) FROM t1;\"" > before_failover_slave.log
format_csql_output before_failover_master.log
format_csql_output before_failover_slave.log
compare_result_between_files before_failover_master.log before_failover_slave.log

# --- Failover: stop master's cub_server (simulate isolation) ---
kill -19 $(pgrep -u $USER cub_server)

# Wait for slave to be promoted to master
wait_for_slave_active > slave_status.log
if grep -q "current HA running mode is active" slave_status.log; then
    write_ok
else
    write_nok
fi

# --- Verify slave is now acting as master ---
run_on_slave -c "cubrid hb status" > hb_status.log
if grep -q "state master" hb_status.log; then
    write_ok
else
    write_nok
fi

# --- Restore master: resume cub_server ---
kill -18 $(pgrep -u $USER cub_server)

# Wait for master to re-sync as slave
wait_for_active > master_recover.log
if grep -q "current HA running mode is" master_recover.log; then
    write_ok
else
    write_nok
fi

# --- Verify data consistency after failover recovery ---
wait_for_slave_failover

csql -udba $dbname@$masterHostName -c "SELECT * FROM t1 ORDER BY id;" > final_master.log
run_on_slave -c "csql -udba $dbname -c \"SELECT * FROM t1 ORDER BY id;\"" > final_slave.log
format_csql_output final_master.log
format_csql_output final_slave.log
compare_result_between_files final_master.log final_slave.log

# --- Cleanup ---
revert_ha_environment
finish
