#!/bin/bash
# CBRD-99101: Verify INSERT replication from master to slave with data consistency
# Inserts rows on the master, waits for replication, then compares
# SELECT output between master and slave to confirm identical data.
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

# --- Create table and insert data on master ---
csql -udba $db_name@$host1 <<'EOF'
CREATE TABLE t1 (id INT PRIMARY KEY, val VARCHAR(100));
INSERT INTO t1 VALUES (1, 'alpha');
INSERT INTO t1 VALUES (2, 'beta');
INSERT INTO t1 VALUES (3, 'gamma');
COMMIT;
EOF

# Wait for replication to catch up before reading slave
wait_replication_done

# --- Read from master ---
csql -udba $db_name@$host1 -c "SELECT id, val FROM t1 ORDER BY id;" > $curPwd/master.log 2>&1
format_csql_output $curPwd/master.log

# --- Read from slave via rexec ---
cat <<EOF > $curPwd/sql_slave.sh
csql -udba $db_name@$host2 -c "SELECT id, val FROM t1 ORDER BY id;"
EOF
rexec D_HOST1 -f "$curPwd/sql_slave.sh" > $curPwd/slave.log 2>&1
format_csql_output $curPwd/slave.log

# --- Verify: master and slave output must match ---
compare_result_between_files $curPwd/master.log $curPwd/slave.log

# --- Additional check: row count consistency ---
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
rm -f $curPwd/master.log $curPwd/slave.log $curPwd/slave_count.txt
rm -f $curPwd/sql_slave.sh $curPwd/sql_count.sh
finish
