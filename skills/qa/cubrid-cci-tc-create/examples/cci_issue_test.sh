#!/bin/bash
# CBRD-XXXXX: Verify cci_connect_with_url query_timeout option disconnects on timeout
# Pattern: issue (explicit write_ok / write_nok)

. $init_path/init.sh
init test
set -x

db=testdb_cbrd
cubrid_createdb --db-volume-size=20m $db
cubrid server start $db

gcc -o test test.c -I${CUBRID}/include -L${CUBRID}/lib -lcascci

cubrid broker start
port=`get_broker_port_from_shell_config`

./test $port $db 10 > result.log 2>&1

if grep "query time out" result.log; then
    write_ok
else
    write_nok
fi

cubrid server stop $db
cubrid deletedb $db
rm -rf $db test result.log
finish
