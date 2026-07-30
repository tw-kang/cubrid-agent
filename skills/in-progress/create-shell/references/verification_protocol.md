# Verification Protocol

After authoring a testcase, prove it actually runs and gives the right verdict — passing on a fixed build, reproducing on a broken one. Try the pod first (real CTP run = ground truth); fall back to local when no pod is reachable. **No pod is a normal, expected path, not a failure.**

## 1. Pod-first (real CTP run)

If a k8s test-shell pod is reachable (`kubectl get pods` shows a `cubridci-test-shell-*` you can `exec` into, or you can launch one from the deployment manifest):

1. **Get CTP + a build into the pod.** The image ships no CTP — clone it (`git clone --depth 1 -b develop https://github.com/CUBRID/cubrid-testtools.git /home/cubrid-testtools`) and install a CUBRID build from a URL with `cubrid-testtools/CTP/common/script/run_cubrid_install <url>` (installs to `$HOME/CUBRID`, writes `~/.cubrid.sh`).
2. **Inject the testcase.** The pod's testcases tree may lag; `mkdir -p` the parent bucket, then `kubectl cp <local TC dir>` into `.../shell/_06_issues/_{yy}_{Nh}/<name>`.
3. **Enable local ssh** (the CTP runner ssh'es to localhost as root): put a keypair in `/root/.ssh` (not `/home/.ssh` — ssh uses the passwd home), `cat` the pub key into `authorized_keys`, start `sshd`.
4. **Run just this TC.** Copy `CTP/conf/shell_ci.conf` to a custom conf with `scenario=` pointing at the single TC dir and `testcase_update_yn=false` (else it git-resets and wipes the injected TC), then `cd $CTP_HOME && HOME=/home ./bin/ctp.sh shell -c <conf>`.
5. **Read the verdict** in `CTP/result/shell/current_runtime_logs/feedback.log` (`<name>-1 : OK`/`NOK`) and `test_status.data`. The full `set -x` trace in `test_local.log` is the proof the workload actually ran.

To confirm a regression test really *catches* the bug, run it against both a fixed and a pre-fix build and expect `OK` then `NOK` (a clean before/after pair on the same version line is the strongest evidence).

## 2. Local fallback (no pod)

When no pod is reachable, do as much as the environment allows:

- **Syntax:** `bash -n <name>.sh` (and `sh -n` if you kept a `#!/bin/sh` body).
- **Compile:** for any embedded C client, `xgcc -o /tmp/x <name>.c` (or the explicit `gcc -I$CUBRID/include -L$CUBRID/lib -lcascci ... -lpthread`) to catch include/link errors.
- **Helper sanity:** confirm referenced helpers exist in `$CTP_HOME/shell/init_path/init.sh`.
- **Local CTP run** if a local CUBRID + CTP are present: same `ctp.sh shell -c <conf>` flow as the pod, against the installed `$CUBRID`.

Local checks confirm the script is well-formed and compiles, but cannot confirm runtime pass/fail — say so plainly when reporting, rather than implying a green run.

## Reporting

State which path you took (pod or local), the build(s) tested, and the verdict with evidence (the `feedback.log` line, PID/coredump deltas, or the syntax/compile results). If you only did local checks, make that limitation explicit.
