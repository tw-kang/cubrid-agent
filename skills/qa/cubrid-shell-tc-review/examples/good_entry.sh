#!/bin/sh
# CBRD-12345: Verify backupdb works with small databases
# Creates a single-table DB, inserts rows, runs backupdb, and checks the result.

. $init_path/init.sh
init test

dbname=test_backup_01
cubrid_createdb $dbname

# Start server with error handling
cubrid server start $dbname
if [ $? -ne 0 ]; then
    write_nok "Failed to start server"
    cubrid deletedb $dbname
    finish
fi

# Inline SQL via heredoc (do not split into external query files)
csql -udba $dbname <<'EOF'
CREATE TABLE t1 (id INT, name VARCHAR(50));
INSERT INTO t1 VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');
EOF

# Test: Backup database
if cubrid backupdb $dbname > backup.log 2>&1; then
    write_ok
else
    write_nok backup.log
fi

# Cleanup: stop services before deleting databases
cubrid server stop $dbname
cubrid deletedb $dbname
rm -f backup.log
finish
