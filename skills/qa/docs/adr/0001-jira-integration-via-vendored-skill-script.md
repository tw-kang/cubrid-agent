# 0001 — Jira integration via vendored skill script, not an MCP server

Date: 2026-06-10
Status: Superseded by [0005](0005-jira-context-via-cubrid-jira-cli-optional-enrichment.md)

> **Superseded (2026-06-23).** The `jira` skill and its vendored script were removed. Jira context is now optional enrichment via the `cubrid-jira` CLI — see [ADR 0005](0005-jira-context-via-cubrid-jira-cli-optional-enrichment.md). The factual findings below (EOL Jira Server, no fitting MCP server) still hold and still argue against an MCP server.

## Context

~20 skills in this repo auto-invoke the `jira` skill for CBRD-XXXXX ticket context. The question arose whether to replace or augment it with an MCP server, or with the external `cubrid-jira` CLI installed via `uv tool install`.

Facts established by direct inspection and primary sources (full evidence in `jira-research/`):

- jira.cubrid.org is **Jira Server 7.7.1** (EOL, plain HTTP). Anonymous read access covers all 6 projects including JQL search (13,370 issues).
- Atlassian's official (Rovo) MCP Server is **Cloud-only** even after its Feb 2026 GA (Atlassian-hosted, Cloud site required); DC support is an open feature request (JRASERVER-78874, still "Gathering Interest" as of June 2026).
- The de-facto standard community server, sooperset/mcp-atlassian, documents a Jira Server/DC **minimum of 8.14**; it does document basic username/password auth, but has no anonymous mode, so 7.7.1 stays outside documented support and would require a real password over plain HTTP.
- No MCP server supports anonymous access. Remaining candidates: b1ff/atlassian-dc-mcp is PAT-only (8.14+), cosmix/jira-mcp was archived in July 2025, leaving only rixbeck/jira-mcp (2 stars, unproven) — credentials in long-lived process env, no dry-run safety, no cache, no defense against Jira Server's 401→CAPTCHA account lockout. (Adversarially re-verified 2026-06-11; see jira-research/04.)
- Anthropic's own guidance (code-execution-with-MCP, Agent Skills posts) favors skill+script over always-loaded MCP tool definitions for context efficiency, and skills work in subagents/headless/CI wherever Bash works.
- AGENTS.md mandates: skills must be self-contained, no `uv tool install`/companion-repo requirements, external CLI functionality must be vendored into `scripts/` (precedent: commit 161b700 deliberately dropped the external CLI dependency).

## Decision

Keep Jira integration as a **Claude Code skill wrapping a vendored, stdlib-only Python script** (`jira/scripts/jira_search.py`, adapted from vimkim/cubrid-jira). Do not run an MCP server. Do not depend on an installed `cubrid-jira` binary.

When new capability is needed (next: anonymous `jql` all-project search; later, possibly writes), **backport it from upstream vimkim/cubrid-jira into the vendored script**, crediting upstream via `Co-Authored-By:`. Writes, if ever adopted, go into a separate opt-in skill and must preserve upstream's contracts: dry-run by default, and exit-immediately-on-401 (CAPTCHA lockout defense).

## Consequences

- Anonymous-read-first keeps the credential surface at zero for the common path; no secrets in MCP config JSON or resident processes against an EOL plain-HTTP server.
- The skill keeps working in subagents, headless runs, and the 20+ consumer skills without per-machine MCP setup, at zero standing context cost.
- Cost accepted: upstream improvements must be manually backported; the vendored script can lag vimkim/cubrid-jira.
- Revisit trigger: if jira.cubrid.org ever migrates to Atlassian Cloud (or a PAT-capable DC version), re-evaluate the official Rovo MCP Server / sooperset/mcp-atlassian; the skill's `/jira CBRD-XXXXX` interface is neutral to such a backend swap.
