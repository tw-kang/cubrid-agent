---
name: jira
description: Look up CUBRID JIRA issue context. Use when a CBRD-XXXXX ticket is mentioned or when the user asks about a JIRA issue.
argument-hint: <CBRD-XXXXX>
---

Look up CUBRID JIRA issue context.

Given a JIRA ticket ID (e.g., CBRD-25123), fetch the issue details from the CUBRID JIRA REST API and present a comprehensive summary. The argument is the ticket ID.

If no ticket ID is provided, ask for one.

$ARGUMENTS

## How it works

This skill bundles a stdlib-only Python fetcher at `scripts/jira_search.py` (vendored from https://github.com/vimkim/cubrid-jira-fetcher). The script:

- Parses a JIRA key from a bare ID (`CBRD-25123`) or browse URL.
- Looks up `<key>*.md` in a cache directory first; prints it on hit (no network).
- On miss, calls the CUBRID JIRA REST API over plain HTTP (`http://jira.cubrid.org/rest/api/2/issue`), formats the issue + 1 level of related issues to markdown, writes to cache, and prints stdout.

Cache directory resolution (first match wins): `--dir` flag → `$CUBRID_JIRA_DIR` → `~/.local/share/cubrid-jira/issues/`.

## Steps

1. Resolve the bundled script path: `<SKILL_DIR>/scripts/jira_search.py`, where `<SKILL_DIR>` is this skill's base directory (provided to you when the skill is invoked).

2. Run via Bash:

   ```
   python3 <SKILL_DIR>/scripts/jira_search.py TICKET_ID
   ```

3. Present the stdout to the user as-is. It is readable markdown with metadata, description, comments, and related-issue links.

4. If the command exits non-zero:
   - Re-run with `python3 --version` to confirm Python ≥ 3.10 is available.
   - If `pandoc` is missing, the script still runs but Jira wiki markup will not be converted to clean markdown — install pandoc for best output (`sudo dnf install pandoc` / `sudo apt install pandoc` / `brew install pandoc`).
   - Otherwise the JIRA instance may be unreachable; surface the stderr message to the user.

## Optional flags

- `--force` — ignore the cache and re-fetch.
- `--no-recurse` — only fetch the requested issue (skip related issues).
- `--dir DIR` — override the cache directory for this call.
