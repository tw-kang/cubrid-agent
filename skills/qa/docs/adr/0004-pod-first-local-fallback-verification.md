# 0004 — Verify authored testcases pod-first, local-fallback

Date: 2026-06-23
Status: accepted

Scope: the `cubrid-shell-tc-create` skill.

## Context

A generated testcase that is never run is a guess. The skill should leave behind evidence that the test actually executes and gives the right verdict (passes on a fixed build, reproduces on a broken one). Two verification environments are available, with opposite cost/confidence profiles:

- A **k8s test-shell pod** with a real CUBRID build runs the test through CTP exactly as CI does — ground-truth `OK`/`NOK`, real coredumps, real regression behavior. But a pod is not always reachable, and bringing one up (clone CTP, install a build via `run_cubrid_install`, inject the TC, set up localhost ssh, run `ctp.sh shell`) costs minutes.
- **Local checks** (`bash -n`, `xgcc` compile of any `.c`, optional local CTP run) are instant and always available, but cannot confirm runtime pass/fail.

This was exercised end-to-end on CBRD-26745: the pod path produced a clean fixed-vs-pre-fix `OK`/`NOK` pair that local checks alone could never have shown.

## Decision

Verification is **pod-first, local-fallback**: attempt the real pod run first; if no pod is reachable, fall back to local checks. Crucially, "no pod" is a normal, expected outcome — not a failure — so the skill must always satisfy at least the local path. When reporting, state which path ran, the build(s) tested, and the verdict with evidence; if only local checks ran, say so explicitly rather than implying a green run.

## Consequences

- The strongest available evidence is produced when a pod exists, without making pod access a hard prerequisite that would block the skill in headless/offline contexts.
- Authors must be honest about confidence level: local-only verification proves well-formedness and compilation, not behavior.
- Cost: the skill carries a `references/verification_protocol.md` describing both paths; the pod path has real setup steps to follow.
- Revisit trigger: if a always-on local CTP+CUBRID becomes standard in the skill's runtime, the local path can be upgraded from "syntax+compile" to "always run", narrowing the gap with the pod.
