#!/usr/bin/env python3
"""Run each failing TC and capture pass/fail + structured diff.

For shell-style TCs (.sh — covers shell, ha_shell, ha_repl, cdc_repl,
isolation), this script replicates the lifecycle documented in the
`cubrid-shell-tc-runone` skill so that no LLM dispatch is needed: source
~/.cubrid.sh, set CTP_HOME and init_path, clean stale CUBRID processes,
cd into <test>/cases/, run `timeout 300 sh <tc>`, then read the emitted
.result file.

For non-shell TCs (sql, jdbc, cci, unittest), the script emits status=DELEGATE
together with the right runone skill name. The orchestrating agent should then
invoke the matching `cubrid-<category>-tc-runone` skill (resolved via Claude's
available_skills registry) and run that TC by hand.

Test-root resolution per category:
  $CUBRID_TC_ROOT_<CATEGORY>   (e.g. CUBRID_TC_ROOT_SHELL)
  $CUBRID_TC_ROOT              (shared fallback for all categories)
If neither is set for a category, that TC is skipped with status=NO_TEST_ROOT.

CTP location: $CTP_HOME (no built-in default — set it explicitly).

Output JSON shape:
{
  "runs": [
    {
      "tc_path":      "...",
      "category":     "shell",
      "runone_skill": "cubrid-shell-tc-runone",
      "annotation":   "...",
      "status":       "OK"|"NOK"|"NOT_FOUND"|"DELEGATE"|"NO_TEST_ROOT",
      "full_path":    "/abs/path/to/.sh",
      "result_lines": [...first 200 lines of <tc>.result...],
      "failing_diffs":[ "...failed-block...", ... ],
      "duration_s":   12.3
    },
    ...
  ]
}
"""
from __future__ import annotations
import argparse
import json
import os
import re
import subprocess
import sys
import time


SHELL_LIKE = {"shell", "ha_shell", "ha-shell", "ha_repl", "cdc_repl", "isolation"}

# No bundled defaults — TC-root location is environment-specific.
# Resolution: $CUBRID_TC_ROOT_<CATEGORY>  ->  $CUBRID_TC_ROOT  ->  None.

RESULT_LINE_RE = re.compile(r"^[a-z0-9_]+-\d+ : (OK|NOK)\s*$")


def log(msg: str) -> None:
    print(f"[run_tc] {msg}", flush=True)


def find_test_root(category: str) -> str | None:
    key = f"CUBRID_TC_ROOT_{category.upper().replace('-', '_')}"
    return os.environ.get(key) or os.environ.get("CUBRID_TC_ROOT")


def cleanup_stale_cubrid() -> None:
    """`cubrid service stop` doesn't kill orphans whose binary was overwritten;
    pkill the broker/cas/master patterns afterward to fully reset shared mem."""
    subprocess.run(
        ["bash", "-lc", "source ~/.cubrid.sh 2>/dev/null; cubrid service stop || true"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["pkill", "-f", "cub_master|cub_broker|cub_cas|query_editor"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def parse_result_file(text: str) -> tuple[list[str], list[str]]:
    """Return (per-step lines, failing diff blocks)."""
    lines = text.splitlines()
    failing: list[str] = []
    block: list[str] = []
    in_block = False
    for line in lines:
        if "failed" in line and ("diff" in line or "compare" in line):
            if in_block and block:
                failing.append("\n".join(block))
            in_block = True
            block = [line]
            continue
        if in_block:
            if RESULT_LINE_RE.match(line):
                failing.append("\n".join(block))
                in_block = False
                block = []
            else:
                block.append(line)
    if in_block and block:
        failing.append("\n".join(block))
    return lines, failing


def run_shell_tc(tc_path: str, test_root: str, timeout: int = 300) -> dict:
    full = os.path.join(test_root, tc_path)
    if not os.path.isfile(full):
        return {"status": "NOT_FOUND", "full_path": full}

    cases_dir = os.path.dirname(full)
    name = os.path.basename(full).rsplit(".", 1)[0]

    cleanup_stale_cubrid()

    ctp_home = os.environ.get("CTP_HOME")
    if not ctp_home:
        return {"status": "NOK", "full_path": full,
                "result_lines": ["<CTP_HOME is not set; cannot run shell TC>"],
                "failing_diffs": [],
                "duration_s": 0.0}
    init_path = f"{ctp_home}/shell/init_path"
    cmd = (
        f"source ~/.cubrid.sh && "
        f"export CTP_HOME='{ctp_home}' && "
        f"export init_path='{init_path}' && "
        f"cd '{cases_dir}' && "
        f"timeout {timeout} sh '{os.path.basename(full)}' >/tmp/run_tc.out 2>&1; "
        f"echo EXIT=$? >>/tmp/run_tc.out"
    )
    t0 = time.time()
    subprocess.run(["bash", "-lc", cmd],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    duration = round(time.time() - t0, 2)

    cleanup_stale_cubrid()  # be a good neighbor for the next TC

    result_file = os.path.join(cases_dir, f"{name}.result")
    if not os.path.isfile(result_file):
        return {"status": "NOK", "full_path": full,
                "result_lines": ["<no .result file produced>"],
                "failing_diffs": [],
                "duration_s": duration}

    with open(result_file, encoding="utf-8", errors="replace") as f:
        text = f.read()

    lines, failing = parse_result_file(text)
    has_nok = any(l.endswith(": NOK") for l in lines)

    return {
        "status": "NOK" if has_nok else "OK",
        "full_path": full,
        "result_lines": lines[:200],
        "failing_diffs": failing[:5],
        "duration_s": duration,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--failures", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()

    with open(args.failures, encoding="utf-8") as f:
        failures = json.load(f)["failures"]

    runs = []
    for i, fail in enumerate(failures, 1):
        cat = fail["category"]
        log(f"[{i}/{len(failures)}] {cat:<10} {fail['tc_path']}")
        root = find_test_root(cat)
        if not root or not os.path.isdir(root):
            runs.append({**fail, "status": "NO_TEST_ROOT"})
            continue
        if cat in SHELL_LIKE and fail["tc_path"].endswith(".sh"):
            r = run_shell_tc(fail["tc_path"], root, timeout=args.timeout)
        else:
            r = {"status": "DELEGATE",
                 "delegate_hint": (
                     f"invoke the `{fail['runone_skill']}` skill"
                 )}
        runs.append({**fail, **r})

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"runs": runs}, f, ensure_ascii=False, indent=2)
    log(f"wrote {args.out}  (total={len(runs)})")


if __name__ == "__main__":
    main()
