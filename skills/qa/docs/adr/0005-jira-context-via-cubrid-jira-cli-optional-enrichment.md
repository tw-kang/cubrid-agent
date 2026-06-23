# 0005 — Jira context via the `cubrid-jira` CLI as optional enrichment

Date: 2026-06-23
Status: accepted
Supersedes: [0001](0001-jira-integration-via-vendored-skill-script.md)

## Context

ADR 0001 kept Jira integration as a dedicated `jira` skill wrapping a vendored, stdlib-only Python script, and had every testcase skill auto-invoke it. In practice this produced two problems:

- **Boilerplate sprawl.** Each of 16 consumer skills carried a near-identical 35–49 line block to locate and call the vendored script — a 5-candidate-path discovery loop, a `pandoc` warning, slash-vs-script branching, ticket-ID normalization, and an install-prompt fallback. This was the single largest source of size-cap violations and cross-skill non-uniformity.
- **A real external tool now exists and is standard here.** `cubrid-jira` (vimkim) is an installed CLI in this environment with `search` (cache-first read), `jql`, and dry-run-default writes. It is already the project-wide standard for Jira reads/writes (see the global agent guidelines), so the vendored copy duplicated a tool the user already runs.

The tension with 0001 is the self-contained rule (AGENTS.md): skills must not *require* an external `uv tool install`. The resolution is to change Jira's **status in the skills**, not just its mechanism.

## Decision

Treat Jira context as **optional enrichment** delivered through the `cubrid-jira` CLI, and delete the `jira` skill.

- Every consumer skill reduces Jira handling to **one optional line**: *"If a `CBRD-XXXXX` is referenced, run `cubrid-jira search CBRD-XXXXX` first to ground the work (reuse if already fetched). If the CLI isn't installed, skip — but installing `cubrid-jira` notably improves accuracy."*
- Because Jira context is no longer required for a skill to function, a skill stays self-contained and deployable without the CLI — so this does **not** violate the self-contained rule. The CLI is an accuracy multiplier, not a runtime dependency.
- The `jira` skill, its vendored `jira_search.py`, the `pandoc` gate, and the path-discovery boilerplate are removed.

## Consequences

- 16 skills shed their largest non-domain block; uniformity and the 200-line cap become easy to hold.
- Jira reads/writes now go through one maintained upstream (`cubrid-jira`) instead of a vendored copy that could lag — 0001's accepted "manual backport" cost disappears.
- Cost accepted: when the CLI is absent, skills run without issue context and say so; accuracy degrades but nothing breaks. Installing `cubrid-jira` is the documented way to restore it.
- The factual findings in 0001 (jira.cubrid.org is EOL Jira Server 7.7.1 over plain HTTP; no MCP server fits) still hold and still argue against an MCP server — `cubrid-jira` remains the right backend.
