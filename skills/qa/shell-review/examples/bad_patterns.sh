#!/bin/sh
# Bad Patterns Example
# This file demonstrates common anti-patterns that should be avoided
# Each section shows a BAD pattern followed by the GOOD alternative
#
# IMPORTANT: This is for educational purposes - DO NOT USE THESE BAD PATTERNS

# =============================================================================
# PATTERN 1: Unbounded Loop (BAD)
# =============================================================================

# BAD: Can hang indefinitely
wait_for_condition_bad() {
    while true; do
        if check_condition; then
            break
        fi
        sleep 1
    done
}

# GOOD: Bounded wait with timeout
wait_for_condition_good() {
    max_wait=30
    waited=0
    while [ $waited -lt $max_wait ]; do
        if check_condition; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "Timeout waiting for condition"
    return 1
}

# =============================================================================
# PATTERN 2: Unjustified Long Sleep (BAD)
# =============================================================================

# BAD: Arbitrary long sleep with no justification
test_with_long_sleep_bad() {
    cubrid server start $db
    sleep 30  # BAD: Why 30 seconds? What are we waiting for?
    # ... test logic ...
}

# GOOD: Polling with condition check
test_with_polling_good() {
    cubrid server start $db
    
    # GOOD: Poll for specific condition with timeout
    max_wait=30
    waited=0
    while [ $waited -lt $max_wait ]; do
        if cubrid server status | grep -q "$db"; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    if [ $waited -ge $max_wait ]; then
        write_nok "Server failed to start within ${max_wait}s"
        return 1
    fi
    # ... test logic ...
}

# =============================================================================
# PATTERN 3: Orphan Process Risk (BAD)
# =============================================================================

# BAD: Background process without tracking or cleanup
test_with_orphan_risk_bad() {
    cubrid server start $db &
    # Server is running in background but PID is not tracked
    # If test fails or is interrupted, server keeps running (orphan)
    sleep 5
    # ... test logic ...
}

# GOOD: Track PID and cleanup properly
test_with_process_tracking_good() {
    cubrid server start $db &
    server_pid=$!
    
    # GOOD: Bounded wait for process
    max_wait=30
    waited=0
    while [ $waited -lt $max_wait ]; do
        if kill -0 $server_pid 2>/dev/null; then
            # Process exists, check if ready
            if cubrid server status | grep -q "$db"; then
                break
            fi
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    # ... test logic ...
    
    # GOOD: Cleanup with proper wait
    cubrid server stop $db
    wait $server_pid 2>/dev/null  # Reap the process
}

# =============================================================================
# PATTERN 4: Broad Process Kill (BAD)
# =============================================================================

# BAD: Unconditional force kill - may kill wrong processes
cleanup_bad() {
    kill -9 $(pgrep cub_server)  # BAD: Kills ALL cub_server processes!
    pkill -9 cub  # BAD: Even broader - kills anything matching 'cub'
}

# GOOD: Use xkill helper for targeted termination
cleanup_good() {
    # GOOD: Try graceful stop first
    cubrid server stop $db
    sleep 2
    
    # GOOD: Use xkill with specific process name if needed
    if pgrep -x cub_server > /dev/null; then
        xkill cub_server  # Only kills user's cub_server processes
    fi
    
    # GOOD: Or use xkill with specific PID
    if kill -0 $server_pid 2>/dev/null; then
        xkill $server_pid
    fi
    
    # GOOD: Wait for process to actually terminate
    wait $server_pid 2>/dev/null
}

# =============================================================================
# PATTERN 5: Missing Error Handling (BAD)
# =============================================================================

# BAD: Commands that fail silently
test_no_error_check_bad() {
    cubrid_createdb $db
    cubrid server start $db  # If this fails, test continues anyway
    csql -udba $db -c "select 1"  # If server not running, this fails
    # ... continues even if previous commands failed ...
    write_ok
}

# GOOD: Check exit codes and handle failures
test_with_error_check_good() {
    cubrid_createdb $db || {
        write_nok "Failed to create database"
        return 1
    }
    
    cubrid server start $db || {
        write_nok "Failed to start server"
        cubrid deletedb $db
        return 1
    }
    
    if ! csql -udba $db -c "select 1" > result.log 2>&1; then
        write_nok result.log
        cubrid server stop $db
        cubrid deletedb $db
        return 1
    fi
    
    write_ok
    cubrid server stop $db
    cubrid deletedb $db
}

# =============================================================================
# PATTERN 6: Syntax Errors (BAD)
# =============================================================================

# BAD: Missing spaces in [ ] tests
syntax_bad() {
    var="test"
    # WRONG: Spaces required around = inside [ ]
    if [ "$var"="value" ]; then  # This is actually [ "test=value" ] which is always true
        echo "wrong"
    fi
}

# GOOD: Proper spacing
syntax_good() {
    var="test"
    # CORRECT: Spaces around operators
    if [ "$var" = "value" ]; then
        echo "correct"
    fi
}

# BAD: Unquoted variables (word splitting risk)
unquoted_bad() {
    files="file1 file2"
    rm $files  # Expands to: rm file1 file2 - OK here
    # But if files="file with spaces": rm file with spaces - WRONG!
}

# GOOD: Quoted variables
unquoted_good() {
    files="file1 file2"
    rm "$files"  # Treats as single argument
    # Or: rm $files (if you want word splitting)
}

# BAD: Arrays in POSIX sh (not supported)
array_bad() {
    # This is bash-only, fails in /bin/sh
    arr=(1 2 3)
    echo ${arr[0]}
}

# GOOD: Use string manipulation or case statement
array_good() {
    # For simple iteration, use case or multiple variables
    val1=1
    val2=2
    val3=3
    # Or use string with word splitting
    vals="1 2 3"
    for v in $vals; do
        echo $v
    done
}

# =============================================================================
# PATTERN 7: Using Raw Commands Instead of Helpers (BAD)
# =============================================================================

# BAD: Using raw cubrid commands
database_ops_bad() {
    cubrid createdb $db  # BAD: Bypasses CTP compatibility layer
    cubrid deletedb $db  # BAD: No core/fatal error checking
}

# GOOD: Using CTP helpers
database_ops_good() {
    cubrid_createdb $db  # GOOD: CTP wrapper with compatibility handling
    cubrid deletedb $db  # GOOD: Includes core/fatal error checking
}

# BAD: Direct kill commands
process_ops_bad() {
    kill -9 $(pgrep -f cub_server)  # BAD: Broad, unscoped kill
}

# GOOD: Using xkill helper
process_ops_good() {
    xkill cub_server  # GOOD: User-scoped, safe pattern matching
}

# BAD: Direct config file edits
config_bad() {
    echo "java_stored_procedure=yes" >> $CUBRID/conf/cubrid.conf
    # Config change not tracked - won't be reverted!
}

# GOOD: Using config helpers
config_good() {
    change_db_parameter "java_stored_procedure=yes"  # GOOD: Auto-reverted by finish
}
