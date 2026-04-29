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
- On miss, calls the CUBRID JIRA REST API over plain HTTP (`http://jira.cubrid.org/rest/api/2/issue`), formats the issue + 1 level of related issues to markdown via **pandoc**, writes to cache, and prints stdout.

Cache directory resolution (first match wins): `--dir` flag → `$CUBRID_JIRA_DIR` → `~/.local/share/cubrid-jira/issues/`.

## Prerequisites

- **Python ≥ 3.10** (stdlib only — no pip packages).
- **`pandoc` (required)** — converts Jira wiki markup to clean markdown. Without it, descriptions/comments are unreadable.

## Steps

1. **Verify `pandoc` is installed.** Run `command -v pandoc`.

   - If `pandoc` is found → proceed to step 2.
   - If `pandoc` is **missing**, **halt and ask the user**:
     > `pandoc` is required for this skill to convert Jira wiki markup to readable markdown. May I install it now? (Suggested command for this system: `<detected-install-command>`)

     Detect the right command via `command -v` in this order and show the first match:
     - `dnf` → `sudo dnf install -y pandoc`
     - `apt-get` → `sudo apt-get install -y pandoc`
     - `pacman` → `sudo pacman -S --noconfirm pandoc`
     - `brew` → `brew install pandoc`
     - none of the above → tell the user to install pandoc manually from https://pandoc.org/installing.html.

     **Wait for explicit user confirmation** before running the install. If the user declines, stop and tell them the skill cannot continue without `pandoc`.

2. Resolve the bundled script path: `<SKILL_DIR>/scripts/jira_search.py`, where `<SKILL_DIR>` is this skill's base directory (provided to you when the skill is invoked).

3. Run via Bash:

   ```
   python3 <SKILL_DIR>/scripts/jira_search.py TICKET_ID
   ```

4. Present the stdout to the user as-is. It is readable markdown with metadata, description, comments, and related-issue links.

5. If the command exits non-zero:
   - Confirm Python ≥ 3.10 with `python3 --version`.
   - Otherwise the JIRA instance may be unreachable; surface the stderr message to the user.

## Optional flags

- `--force` — ignore the cache and re-fetch.
- `--no-recurse` — only fetch the requested issue (skip related issues).
- `--dir DIR` — override the cache directory for this call.
