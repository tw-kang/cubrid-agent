---
name: create-ha-shell
description: "Create, draft, or scaffold a new CUBRID CTP HA shell testcase (.sh) from scratch — an HA replication test for a CBRD bug fix or feature. Use this whenever someone says \"ha shell tc 만들어줘\", \"ha shell tc 초안 작성해줘\", \"create ha shell tc\", \"draft HA shell test\", \"새 ha 테스트케이스\", \"HA shell 테스트케이스 작성\", or \"create draft ha shell tc for CBRD-XXXXX\", even if they don't say \"testcase\". They usually give a CBRD number, the HA behavior to test, and sometimes a target release dir. NOT for: regular shell tests (use create-shell), ha_repl SQL-format tests (use create-ha-repl), reviewing/debugging existing tests, running tests, or CTP configuration."
---

# HA Shell Testcase Creator (CTP)

Generate a CUBRID CTP HA shell testcase that passes review on the first try. A good HA testcase is one self-contained `#!/bin/bash` script that drives a 1-master/1-slave cluster through **setup → action on master → wait for replication → verify slave → revert**, which CTP runs, collects, and regression-tracks.

## Scope

**Produces:** the entry `.sh` (owns the full HA lifecycle), correct directory paths under `$TC/HA/shell/`, replication/failover/config-change logic against `hatestdb`.

**Does NOT produce:** answer files (CTP generates these in `init answer` mode — never hand-write them), CTP framework changes, CI config. Route regular shell tests to `create-shell`, ha_repl SQL-format tests to `create-ha-repl`.

## Before you start

- **Testcase repo.** Resolve its root without a hardcoded home path: use `$CUBRID_TESTCASES_PRIVATE` if set, else discover the `cubrid-testcases-private` checkout from the current dir (`git rev-parse --show-toplevel` or search upward), else ask the user. Call it `$TC` below.
- **CTP with HA helpers must be installed.** Expect it at `$CTP_HOME`, `~/CTP`, or `~/cubrid-testtools/CTP`. Sanity check: `ls $CTP_HOME/shell/init_path/make_ha.sh`. If absent, stop and tell the user to install it (`git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`). HA tests also need an `HA.properties` with reachable slave-node credentials.
- **JIRA context (optional).** If a `CBRD-XXXXX` is referenced, ground the work in it first: `cubrid-jira jql 'key = CBRD-XXXXX' --fields summary,description,comment,attachment --output json` — raw Jira wiki markup, which reads fine as-is. **Not `cubrid-jira search`**: its markdown goes through pandoc, so an old pandoc without the `jira` reader (the RHEL 8 package is one) silently degrades the body — blank on a CLI older than 2026-07-30, raw Jira markup with a warning after. `jql` never touches pandoc. Repro steps sit in comments as often as in the description. If the CLI isn't installed, skip — but installing `cubrid-jira` improves accuracy. **When you read the issue yourself** (not handed grounded input by `author-testcase`), also download and read every attachment — they often carry the developer's intended cases (a repro `.sh` or the HA nodes' logs) that the description omits. `cubrid-jira attachment <KEY> --output json` fetches them and prints a per-file manifest; it applies the 5 MiB gate itself, so cores and binaries come back `skipped` and never hit the disk — record just their metadata + reason. Read the fetched text/code closely and view images with the Read multimodal. If the subcommand is missing, the CLI is stale — `uv tool upgrade cubrid-jira`.

## Directory convention

The path is how CTP identifies and categorizes a test; the directory name and the script filename **must match** (`test_name/cases/test_name.sh`). HA tests live under `$TC/HA/shell/` (not `cubrid-testcases`).

```
# Bug fix:   HA/shell/_{nn}_bts_issue/cbrd_xxxxx/cases/cbrd_xxxxx.sh
# Feature:   HA/shell/_{nn}_{release_code}/{feature_name}/cases/{feature_name}.sh
```

`{nn}_bts_issue` buckets bug fixes (e.g. `_12_bts_issue`, `_16_bts_issue`); `{nn}_{release_code}` buckets features by release (e.g. `_38_fig`, `_39_fig_cake`). Multiple tests for one issue nest with a suffix: `cbrd_xxxxx/cbrd_xxxxx_1/cases/cbrd_xxxxx_1.sh`.

## Lifecycle contract

Every entry script follows this skeleton. Missing a step fails review.

```bash
#!/bin/bash
# CBRD-XXXXX: one-line statement of what this HA behavior verifies.
# HA config: 1 master + 1 slave. Setup → action → expected replication outcome.

. $init_path/init.sh
. $init_path/make_ha.sh
init test
set -x

# --- Setup (creates hatestdb on both nodes, configures HA, starts heartbeat) ---
setup_ha_environment

# --- Test (act on master) ---
csql -udba $dbname -c "CREATE TABLE t1(id INT PRIMARY KEY); INSERT INTO t1 VALUES(1); COMMIT;"

# --- Verify (wait for replication, then compare) ---
wait_for_slave
if [ <condition> ]; then write_ok; else write_nok; fi

# --- Cleanup ---
revert_ha_environment
finish
```

### Why each phase matters (not just ritual)

- `#!/bin/bash` is mandatory — the HA helpers rely on bash features.
- `. init.sh` loads CTP core (`write_ok`/`write_nok`/`format_csql_output`/`finish`); `. make_ha.sh` reads `HA.properties`, defines `run_on_slave`, and sources the upper helpers. Source `init.sh` **first**. `set -x` gives reviewers a debuggable trace.
- `setup_ha_environment` creates `hatestdb` on master **and** slave, uploads the conf files, starts heartbeat, waits for active mode, and auto-sets `$masterHostName`/`$slaveHostName`. Never `cubrid createdb` by hand.
- `revert_ha_environment` destroys `hatestdb` on both nodes and reverts every conf change; `finish` must be the **last** call. Every exit path (including early `write_nok` returns) must reach them, or the next test inherits a dirty cluster.
- Every code path ends at exactly one of `write_ok` / `write_nok`, then revert, then `finish`.

## Essential helpers (use these, not raw commands)

Raw equivalents fail review because these handle two-node orchestration, replication timing, and auto-revert.

| Use | Instead of | Why |
|---|---|---|
| `setup_ha_environment` / `revert_ha_environment` | `cubrid createdb` + manual conf edits | builds/tears down both nodes; reverts conf automatically |
| `run_on_slave -c "cmd"` | raw `ssh` | credentials from `HA.properties`, cross-host safe |
| `wait_for_slave` / `wait_for_slave_failover` | `sleep` then read | blocks until replication (or failover) actually lands |
| `wait_for_active` / `wait_for_slave_active` | grepping status in a loop | waits for a node to reach active HA mode |
| `modify_cubrid_conf` / `modify_cubrid_ha` / `modify_cubrid_broker_conf` | editing `.conf` | edits + uploads to slave; reverted by `revert_ha_environment` |
| `write_ok` / `write_nok [file]` | echoing PASS/FAIL | CTP result tracking |

`dbname` is always `hatestdb` and `$masterHostName`/`$slaveHostName`/`$currentPath` are set for you by setup. To call `ha_common.sh` functions on the slave: `run_on_slave -initfile $init_path/ha_common.sh -c "func arg"`. Full helper source: the CTP files listed under Examples & references.

## Writing rules (principles, not ritual)

- **Header comment describes the test, not the run that produced it** — the `# CBRD-XXXXX:` line and any comment block state what is verified. Nothing addressed to a later pipeline stage ("the Verify lane MUST check …"), no reporting guidance: reasoning goes in the run report, reviewer constraints in the PR Remarks, and a condition that decides whether the run proved anything in the manifest's `verify.preconditions` (CUBRIDQA-1481). Both a human reviewer and a later skill read it, so keep it **within 20 lines** and compress wording rather than dropping coverage items.
- **Always `#!/bin/bash`**, source `init.sh` before `make_ha.sh`, keep `dbname=hatestdb`.
- **`setup_ha_environment` before any DB op; `revert_ha_environment` before `finish`** — on every exit path, early branches included.
- **`wait_for_slave` before reading the slave** — never compare master vs slave without waiting for replication.
- **Remote work goes through `run_on_slave`**, never raw `ssh`.
- **No hardcoded hostnames/IPs** — use `$masterHostName`/`$slaveHostName`. **No hardcoded paths** — use `$CUBRID`, `$init_path`, `$currentPath`, or `work=$(mktemp -d)` for scratch.
- **Quote variables** (`"$dbname"`), space your tests (`[ "$x" -eq 0 ]`), check exit codes for things that can fail.
- **Bounded loops only** — poll with a counter, never `while true`.

## House idioms (quick recipes)

- **Compare master vs slave:** dump both to logs, normalize, diff.
  ```bash
  csql -udba $dbname@$masterHostName -c "SELECT * FROM t1 ORDER BY id;" > master.log
  run_on_slave -c "csql -udba $dbname -c \"SELECT * FROM t1 ORDER BY id;\"" > slave.log
  format_csql_output master.log; format_csql_output slave.log
  compare_result_between_files master.log slave.log
  ```
- **Simulate master failure (failover):** `kill -19 $(pgrep -u $USER cub_server)` to suspend, then `wait_for_slave_active` and assert `current HA running mode is active`; `kill -18 ...` to resume.
- **Config-change test:** apply the change *before* `setup_ha_environment` (it picks up and uploads the edit); `revert_ha_environment` undoes it.
- **Run ha_common.sh helpers on the slave:** `run_on_slave -initfile $init_path/ha_common.sh -c "cleanup $dbname"`.

## Verify before claiming done

After authoring, prove the testcase actually runs — don't just eyeball it.

1. **Cluster-first:** if a real 1m/1s HA environment (or k8s HA pod pair) is reachable, run it there via `ctp.sh shell` and read `feedback.log` for `OK`/`NOK`. This is ground truth — HA timing bugs only surface against two live nodes.
2. **Local fallback** (no cluster is an expected path): `bash -n` the script to catch syntax errors, and eyeball that every exit path reaches `revert_ha_environment` then `finish`.

## Self-review checklist

- `#!/bin/bash`, `init.sh` then `make_ha.sh`, `init test`, `set -x`?
- `setup_ha_environment` before any DB op? `dbname` left as `hatestdb`?
- `wait_for_slave` before every master/slave comparison?
- Remote commands via `run_on_slave`, no raw `ssh`? No hardcoded hosts/IPs/paths?
- Exactly one `write_ok`/`write_nok` per path, then `revert_ha_environment`, then `finish` last — on every exit path?
- Bounded loops? Dir name == filename, in the right `_{nn}_bts_issue` / release bucket?
- Verified (cluster-first, else `bash -n`)?

## Examples & references

- `@examples/ha_replication_verify.sh` — INSERT/UPDATE/DELETE replication with master/slave comparison.
- `@examples/ha_failover_test.sh` — kill master, verify slave promotion.
- CTP helper source (read for exact signatures): `$CTP_HOME/shell/init_path/make_ha.sh` (run_on_slave, properties), `make_ha_upper.sh` (setup/revert, wait_for_slave, failover), `ha_common.sh` (cleanup, wait_for_active), `init.sh` (write_ok/write_nok/finish). Existing tests: `$TC/HA/shell/`.
- Test guide: `ha_shell_guide.md` — https://github.com/CUBRID/cubrid-testtools/blob/develop/doc/ha_shell_guide.md (or `$CTP_HOME/../doc/ha_shell_guide.md` if CTP is checked out locally).
