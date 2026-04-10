#!/bin/bash
# CBRD-XXXXX: Verify cci_prepare / cci_execute / cci_fetch for basic SELECT
# Pattern: simple (output comparison with answer file)
# DB: ccidb (created by create_ccidb)

. $init_path/init.sh
init test
set -x

# create_ccidb: creates 'ccidb' with standard schema, starts server
create_ccidb
isdbstart=`cubrid server status | grep "Server ccidb " | wc -l`
if [ $isdbstart -ne 1 ]; then
    cubrid server start ccidb
fi

cubrid broker start

# compile C source (xgcc handles -I/-L automatically)
xgcc -o test test.c

# run test and capture output
port=`cubrid broker status -b | grep broker1 | awk '{print $4}'`
output_file=${case_name}.output
./test $port > $output_file

# compare against expected answer file
compare_result_between_files "${output_file}" "${case_name}.answer"

# cleanup: only delete ccidb if this test created it
if [ $isdbexist -ne 1 ]; then
    cubrid server stop ccidb
    cubrid deletedb ccidb
fi

rm -f test $output_file
finish
