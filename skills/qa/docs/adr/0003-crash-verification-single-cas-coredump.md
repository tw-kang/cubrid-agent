# 0003 — Crash testcases use single-CAS + coredump baseline/delta + CAS-PID stability

Date: 2026-06-23
Status: accepted

Scope: the `cubrid-shell-tc-create` skill (crash / CAS-reuse regressions).

## Context

A class of CUBRID bugs crashes a CAS (broker worker) process rather than returning a wrong answer — e.g. CBRD-26745, where one CAS reused across two databases coredumped in `db_close_session_local()`. Writing a reliable regression test for "the server did not crash" is subtle:

- The default broker pre-forks several CAS (`MIN_NUM_APPL_SERVER=5`), so connections spread across processes and a reuse-specific crash may never hit the same CAS twice — the bug hides.
- "No crash" is not directly observable from query output; it must be inferred from coredump files and process liveness.
- Coredump counts are environment-sensitive: pre-existing cores create false positives.

The corpus already encodes the building blocks: 75 testcases force a single CAS, 208 do coredump detection, and CAS-PID before/after comparison is an established idiom.

## Decision

For crash / CAS-reuse repros, the skill prescribes a three-signal verification:

1. **Force a single CAS** — `change_broker_parameter MIN_NUM_APPL_SERVER=1` and `MAX_NUM_APPL_SERVER=1`, then `cubrid broker restart` — so one deterministic process handles every cycle.
2. **Coredump baseline → delta** — count `core.*` / `*coredump*` under `$CUBRID` and `./` before and after the workload; assert no new cores.
3. **CAS-PID stability** — capture the `broker1_cub_cas` PID before and after; assert it is unchanged.

Pass requires all three (plus the client/workload succeeding). This was validated on CBRD-26745: PASS on fixed builds, NOK (matching coredump stack) on pre-fix builds.

## Consequences

- Deterministic, reproducible crash detection that a single run can trust.
- Cost — fidelity tradeoff: forcing one CAS removes the concurrency some bugs need. A bug that only manifests with many CAS under load will not reproduce under this recipe; such cases need a different (load/concurrency) harness and should say so.
- Coredump counting must use a baseline (or clean cores first), or unrelated pre-existing cores cause false failures.
- Revisit trigger: a crash bug that requires concurrency, or a platform where cores land outside `$CUBRID`/cwd, needs the recipe extended.
