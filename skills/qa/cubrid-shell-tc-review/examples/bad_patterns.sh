#!/bin/sh
# Anti-patterns with BAD → GOOD comparisons
# For educational reference — do NOT use BAD patterns

# ── PATTERN 1: Unbounded loop ────────────────────────────────────────
# BAD: while true can hang indefinitely [blocker]
while true; do
    check_condition && break
    sleep 1
done

# GOOD: Bounded wait with timeout
max_wait=30; waited=0
while [ $waited -lt $max_wait ]; do
    check_condition && break
    sleep 1
    waited=$((waited + 1))
done
[ $waited -ge $max_wait ] && write_nok "Timeout"

# ── PATTERN 2: Unjustified long sleep ────────────────────────────────
# BAD: Arbitrary 30s sleep [major]
cubrid server start $db
sleep 30

# GOOD: Poll for server readiness
cubrid server start $db
max_wait=30; waited=0
while [ $waited -lt $max_wait ]; do
    cubrid server status | grep -q "$db" && break
    sleep 1
    waited=$((waited + 1))
done

# ── PATTERN 3: Orphan process ────────────────────────────────────────
# BAD: Background process without tracking [blocker]
some_command &
sleep 5

# GOOD: Track PID and cleanup
some_command &
bg_pid=$!
# ... test logic ...
wait $bg_pid 2>/dev/null

# ── PATTERN 4: Broad process kill ────────────────────────────────────
# BAD: Kills ALL matching processes [major]
kill -9 $(pgrep cub_server)

# GOOD: Use xkill helper (user-scoped, safe)
cubrid server stop $db
xkill cub_server

# ── PATTERN 5: Missing error handling ────────────────────────────────
# BAD: No exit code checks [major]
cubrid_createdb $db
cubrid server start $db
csql -udba $db -c "select 1"
write_ok

# GOOD: Check and handle failures
cubrid_createdb $db || { write_nok "createdb failed"; finish; }
cubrid server start $db || { write_nok "server start failed"; cubrid deletedb $db; finish; }
csql -udba $db -c "select 1" > result.log 2>&1 || { write_nok result.log; cubrid server stop $db; cubrid deletedb $db; finish; }
write_ok

# ── PATTERN 6: Raw commands instead of CTP helpers ───────────────────
# BAD: Bypasses CTP compatibility layer [major]
cubrid createdb $db
echo "java_stored_procedure=yes" >> $CUBRID/conf/cubrid.conf

# GOOD: CTP helpers (auto-tracked, auto-reverted)
cubrid_createdb $db
change_db_parameter "java_stored_procedure=yes"

# ── PATTERN 7: External query files in entry script ──────────────────
# BAD: Reviewer must cross-reference files [blocker]
csql -udba $db -i query.sql

# GOOD: Inline SQL via heredoc
csql -udba $db <<'EOF'
SELECT * FROM t1 WHERE id > 0;
EOF
