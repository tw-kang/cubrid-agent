#!/usr/bin/env python3
"""
jira_search.py — cache-first lookup of a CUBRID JIRA issue, fetch on miss.

Stdlib-only (urllib, json, argparse, subprocess, pathlib, re). No third-party
Python dependencies. `pandoc` is used for Jira-wiki -> markdown conversion when
available; falls back to raw text if missing.

Usage:
    python3 jira_search.py CBRD-12345
    python3 jira_search.py http://jira.cubrid.org/browse/CBRD-12345
    python3 jira_search.py CBRD-12345 --force        # bypass cache
    python3 jira_search.py CBRD-12345 --no-recurse   # don't walk related
    python3 jira_search.py CBRD-12345 --dir /tmp/x   # override cache dir

Cache directory resolution (first match wins):
    1. --dir flag
    2. $CUBRID_JIRA_DIR env var
    3. ~/.local/share/cubrid-jira/issues/

Adapted from https://github.com/vimkim/cubrid-jira-fetcher (consolidates
search + fetcher into a single stdlib-only script for skill bundling).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

JIRA_BASE = "http://jira.cubrid.org"
REST_API = f"{JIRA_BASE}/rest/api/2/issue"
DEFAULT_DIR = Path.home() / ".local" / "share" / "cubrid-jira" / "issues"


def parse_issue_key(arg: str) -> str:
    m = re.search(r"([A-Z]+-\d+)", arg)
    if m:
        return m.group(1)
    raise ValueError(f"Cannot parse issue key from: {arg!r}")


def fetch_issue(key: str) -> dict:
    url = f"{REST_API}/{key}?expand=renderedFields"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"  [HTTP {e.code}] Failed to fetch {key}: {e.reason}", file=sys.stderr)
        return {}
    except Exception as e:
        print(f"  [Error] Failed to fetch {key}: {e}", file=sys.stderr)
        return {}


def extract_related_keys(data: dict) -> list:
    related = []
    fields = data.get("fields", {})
    parent = fields.get("parent")
    if parent:
        related.append(("parent", parent["key"]))
    for sub in fields.get("subtasks", []):
        related.append(("subtask", sub["key"]))
    for link in fields.get("issuelinks", []):
        link_type = link["type"]["name"]
        if "inwardIssue" in link:
            related.append((f"{link_type} (inward)", link["inwardIssue"]["key"]))
        if "outwardIssue" in link:
            related.append((f"{link_type} (outward)", link["outwardIssue"]["key"]))
    return related


def jira_to_markdown(text: str) -> str:
    try:
        result = subprocess.run(
            ["pandoc", "-f", "jira", "-t", "markdown", "--wrap=none"],
            input=text,
            capture_output=True,
            text=True,
            timeout=10,
        )
        return result.stdout.strip()
    except Exception:
        return text


def format_issue_markdown(data: dict) -> str:
    if not data:
        return "(no data)"
    key = data.get("key", "?")
    fields = data.get("fields", {})

    lines = []
    summary = fields.get("summary", "(no summary)")
    lines.append(f"# [{key}] {summary}")
    lines.append(f"\n<{JIRA_BASE}/browse/{key}>")

    lines.append("\n## Metadata\n")
    lines.append("| Field | Value |")
    lines.append("|---|---|")
    lines.append(f"| Status | {fields.get('status', {}).get('name', '?')} |")
    lines.append(f"| Priority | {fields.get('priority', {}).get('name', '?')} |")
    lines.append(f"| Type | {fields.get('issuetype', {}).get('name', '?')} |")
    lines.append(f"| Assignee | {(fields.get('assignee') or {}).get('displayName', 'Unassigned')} |")
    lines.append(f"| Reporter | {(fields.get('reporter') or {}).get('displayName', '?')} |")
    lines.append(f"| Resolution | {(fields.get('resolution') or {}).get('name', 'Unresolved')} |")

    components = [c["name"] for c in fields.get("components", [])]
    if components:
        lines.append(f"| Components | {', '.join(components)} |")

    fix_versions = [v["name"] for v in fields.get("fixVersions", [])]
    if fix_versions:
        lines.append(f"| Fix Version | {', '.join(fix_versions)} |")

    target_versions = [v["name"] for v in fields.get("customfield_210441", []) or []]
    if target_versions:
        lines.append(f"| Target Version | {', '.join(target_versions)} |")

    lines.append(f"| Created | {(fields.get('created') or '')[:10]} |")
    lines.append(f"| Updated | {(fields.get('updated') or '')[:10]} |")

    desc = fields.get("description") or ""
    if desc:
        lines.append("\n## Description\n")
        lines.append(jira_to_markdown(desc))

    comments = fields.get("comment", {}).get("comments", [])
    if comments:
        lines.append(f"\n## Comments ({len(comments)} total)\n")
        for c in comments:
            author = (c.get("author") or {}).get("displayName", "?")
            date = (c.get("created") or "")[:10]
            body = jira_to_markdown(c.get("body") or "")
            lines.append(f"### {author} — {date}\n")
            lines.append(body)
            lines.append("")

    related = extract_related_keys(data)
    if related:
        lines.append("\n## Related Issues\n")
        for rel, rkey in related:
            lines.append(f"- **{rel}**: [{rkey}]({JIRA_BASE}/browse/{rkey})")

    return "\n".join(lines)


def issue_path(key: str, out_dir: Path) -> Path:
    return out_dir / f"{key}.md"


def save_issue(data: dict, out_dir: Path) -> Path:
    key = data.get("key", "UNKNOWN")
    path = issue_path(key, out_dir)
    path.write_text(format_issue_markdown(data), encoding="utf-8")
    return path


def fetch_recursive(key, max_depth, visited, out_dir, force=False, current_depth=0):
    if key in visited or current_depth > max_depth:
        return
    visited.add(key)

    path = issue_path(key, out_dir)
    if not force and path.exists():
        print(f"Skipping {key} (already exists: {path})", file=sys.stderr)
        if current_depth < max_depth:
            data = fetch_issue(key)
            if data:
                for _rel, rkey in extract_related_keys(data):
                    fetch_recursive(rkey, max_depth, visited, out_dir, force, current_depth + 1)
        return

    print(f"Fetching {key} (depth {current_depth})...", file=sys.stderr)
    data = fetch_issue(key)
    if not data:
        return
    save_issue(data, out_dir)
    print(f"  Saved -> {path}", file=sys.stderr)

    if current_depth < max_depth:
        for _rel, rkey in extract_related_keys(data):
            fetch_recursive(rkey, max_depth, visited, out_dir, force, current_depth + 1)


def resolve_dir(cli_dir):
    if cli_dir:
        return Path(cli_dir)
    env = os.environ.get("CUBRID_JIRA_DIR")
    if env:
        return Path(env)
    return DEFAULT_DIR


def find_cached(key: str, directory: Path) -> list:
    if not directory.exists():
        return []
    return sorted(directory.glob(f"{key}*.md"))


def main():
    parser = argparse.ArgumentParser(
        description="Cache-first lookup of a CUBRID JIRA issue; fetch from web on miss."
    )
    parser.add_argument("issue", help="Issue key (e.g. CBRD-12345) or full browse URL")
    parser.add_argument("-d", "--dir", default=None, metavar="DIR",
                        help=f"Cache directory (default: $CUBRID_JIRA_DIR or {DEFAULT_DIR})")
    parser.add_argument("--no-recurse", action="store_true",
                        help="On cache miss, only fetch the requested issue (skip related)")
    parser.add_argument("--force", action="store_true",
                        help="Ignore the cache and re-fetch from JIRA")
    args = parser.parse_args()

    try:
        key = parse_issue_key(args.issue)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    out_dir = resolve_dir(args.dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if not args.force:
        cached = find_cached(key, out_dir)
        if cached:
            print(f"# Found cached: {cached[0].name}", file=sys.stderr)
            print(cached[0].read_text(encoding="utf-8"))
            return

    print(f"# Fetching {key} from jira.cubrid.org ...", file=sys.stderr)
    max_depth = 0 if args.no_recurse else 1
    visited = set()
    fetch_recursive(key, max_depth, visited, out_dir)

    cached = find_cached(key, out_dir)
    if cached:
        print(cached[0].read_text(encoding="utf-8"))
    else:
        print(f"Error: Failed to fetch {key}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
