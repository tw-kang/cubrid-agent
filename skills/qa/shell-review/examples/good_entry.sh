#!/bin/sh
# Test: Verify backupdb works with small databases
# This is a well-formed entry script example for CTP shell testing

# Initialize CTP environment
. $init_path/init.sh
init test

# Define database name
dbname=test_backup_01

# Create database using CTP helper (not raw cubrid createdb)
cubrid_createdb $dbname

# Create test data
csql -udba $dbname -c "create table t1 (c1 int)"
csql -udba $dbname -c "insert into t1 values (1), (2), (3)"

# Test: Backup database with error handling
if cubrid backupdb $dbname > backup.log 2>&1; then
    # Success path
    write_ok
else
    # Failure path with log
    write_nok backup.log
fi

# Cleanup sequence: stop services before deleting databases
cubrid server stop $dbname
cubrid deletedb $dbname

# Final CTP cleanup
finish
