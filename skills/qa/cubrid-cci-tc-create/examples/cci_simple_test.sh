#!/bin/bash
# CBRD-XXXXX: Verify cci_prepare / cci_execute / cci_fetch for basic SELECT
# Pattern: simple (output comparison with answer file)

. $init_path/init.sh
init test
set -x

create_ccidb
isdbstart=`cubrid server status | grep "Server ccidb " | wc -l`
if [ $isdbstart -ne 1 ]; then
    cubrid server start ccidb
fi

cubrid broker start

xgcc -o test test.c

port=`cubrid broker status -b | grep broker1 | awk '{print $4}'`
output_file=${case_name}.output
./test $port > $output_file

compare_result_between_files "${output_file}" "${case_name}.answer"

if [ $isdbexist -ne 1 ]; then
    cubrid server stop ccidb
    cubrid deletedb ccidb
fi

rm -f test $output_file
finish
