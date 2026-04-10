#!/bin/bash
# CBRD-99102: Verify failover — slave promotes to master when master process is stopped
# Stops the master cub_master process to simulate failure, then checks that the
# slave node promotes to master state. After resuming the original master,
# verifies failback and data consistency between nodes.
# Requires: 1 master + 1 slave (D_HOST1)

set -x
. $init_path/init.sh
. $init_path/init_ext.sh
init test

curPwd=`pwd`
db_name=hatestdb
host1=`hostname`
host2=`rexec D_HOST1 -c "hostname"`

# --- Setup HA ---
cubrid_ha_create -s D_HOST1
cubrid_ha_start
cubrid broker start

# --- Create table and insert initial data on master ---
csql -udba $db_name@$host1 <<'EOF'
CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
INSERT INTO t1 VALUES (1, 'row_one');
INSERT INTO t1 VALUES (2, 'row_two');
COMMIT;
EOF

wait_replication_done

# --- Simulate master failure: stop cub_master process ---
mpid=`ps ux | grep cub_master | grep -v grep | awk '{print $2}'`

kill -STOP $mpid

# --- Poll slave: wait until slave reports as master ---
rexec D_HOST1 -c "cubrid hb status" \
    -tillcontains "registered_and_to_be_active" -maxattempts 180 -interval 2

rexec D_HOST1 -c "cubrid hb status" \
    -tillcontains "state master" -maxattempts 180 -interval 2 > $curPwd/slave_status.txt

# Verify slave promoted to master
ismasterforslave=`grep "state master" $curPwd/slave_status.txt | grep "$host2" | wc -l`
if [ $ismasterforslave -gt 0 ]; then
    write_ok
else
    write_nok "$curPwd/slave_status.txt"
fi

# --- Resume original master ---
kill -CONT $mpid

# --- Poll: wait for original master to failback ---
cubrid hb status -tillcontains "state master" -maxattempts 180 -interval 2 > $curPwd/master_status.txt 2>&1 || true

# Poll via rexec to check original master returned
rexec D_HOST1 -c "cubrid hb status" \
    -tillcontains "state slave" -maxattempts 180 -interval 2 > $curPwd/slave_after_failback.txt

# Verify original master recovered as master
ismasterrecovery=`cubrid hb status | grep "state master" | grep "$host1" | wc -l`
if [ $ismasterrecovery -ne 0 ]; then
    write_ok
else
    write_nok
fi

# Verify slave returned to slave state
isslaverecovery=`cubrid hb status | grep "state slave" | grep "$host2" | wc -l`
if [ $isslaverecovery -eq 1 ]; then
    write_ok
else
    write_nok
fi

# --- Data consistency check after failback ---
wait_replication_done

mcount=`csql -udba -l -c 'select count(*) from t1' $db_name@$host1 \
    | grep count | awk -F ':' '{print $2}' | tr -d ' '`

cat <<EOF > $curPwd/sql_count.sh
csql -udba -l -c 'select count(*) from t1' $db_name@$host2
EOF
rexec D_HOST1 -f "$curPwd/sql_count.sh" > $curPwd/slave_count.txt
scount=`cat $curPwd/slave_count.txt | grep count | awk -F ':' '{print $2}' | tr -d ' '`

if [ "$mcount" -eq "$scount" ]; then
    write_ok
else
    write_nok "$curPwd/slave_count.txt"
fi

# --- Cleanup ---
cubrid_ha_stop
cubrid_service_stop
cubrid_ha_destroy
rm -f $curPwd/slave_status.txt $curPwd/master_status.txt
rm -f $curPwd/slave_after_failback.txt $curPwd/slave_count.txt $curPwd/sql_count.sh
finish
