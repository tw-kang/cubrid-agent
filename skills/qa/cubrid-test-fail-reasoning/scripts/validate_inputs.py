#!/usr/bin/env python3
"""Hard input gate for cubrid-test-fail-reasoning.

Refuses to proceed unless --fail-list, --branch, and --commit-range are all
present and parseable. Emits a precise message naming the missing/invalid input
so the caller knows exactly what to provide.

Exit codes:
  0 — all three inputs are valid
  2 — missing or invalid input (caller must abort)
"""
from __future__ import annotations
import argparse
import os
import re
import sys


BRANCH_RE = re.compile(r"^[\w./_+-]{1,200}$")
SHA_RE = re.compile(r"^[0-9a-f]{4,40}$", re.IGNORECASE)


def fail(msg: str) -> None:
    sys.stderr.write(f"[cubrid-test-fail-reasoning] REFUSED: {msg}\n")
    sys.exit(2)


def main() -> None:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--fail-list", default=None, help="path to fail.txt-style file")
    ap.add_argument("--branch", default=None, help="git branch (e.g. release/11.3)")
    ap.add_argument("--commit-range", default=None, help="<good_sha>..<bad_sha>")
    args = ap.parse_args()

    missing = [n for n, v in [
        ("--fail-list", args.fail_list),
        ("--branch", args.branch),
        ("--commit-range", args.commit_range),
    ] if not v]
    if missing:
        fail(
            "missing required input(s): " + ", ".join(missing) +
            ". Provide all three: --fail-list <path> --branch <name> "
            "--commit-range <good_sha>..<bad_sha>"
        )

    if not os.path.isfile(args.fail_list):
        fail(f"fail-list path does not exist or is not a file: {args.fail_list}")
    if os.path.getsize(args.fail_list) == 0:
        fail(f"fail-list is empty: {args.fail_list}")

    if not BRANCH_RE.match(args.branch):
        fail(f"invalid branch name: {args.branch!r}")

    if ".." not in args.commit_range:
        fail(
            f"commit-range must be in 'good..bad' form, got {args.commit_range!r}"
        )
    parts = args.commit_range.split("..")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        fail(f"commit-range malformed (need exactly one '..'): {args.commit_range!r}")
    for p in parts:
        if not SHA_RE.match(p):
            fail(f"commit-range endpoint is not a hex sha: {p!r}")

    print(
        f"[cubrid-test-fail-reasoning] inputs OK: fail-list={args.fail_list} "
        f"branch={args.branch} commit-range={args.commit_range}"
    )


if __name__ == "__main__":
    main()
