#!/usr/bin/env python3
"""Parse a fail.txt-style failure list into structured JSON.

Format expectation (one block per failing TC):

    shell/_06_issues/_17_1h/cbrd_20145_1/cases/cbrd_20145_1.sh
    [0]
    [history]  [AI Analysis]  [verify]
    2  N  Y  22h:1m  Won-ryong song  verified  [unknown] 원인 불명: ...
        25
    shell/_06_issues/_12_2h/bug_bts_8662/cases/bug_bts_8662.sh
    ...

The "header" line of each block is a TC path that:
  - starts with a category prefix (shell/, sql/, jdbc/, cci/, isolation/,
    ha_repl/, cdc_repl/, ha_shell/, unittest/)
  - ends in .sh / .sql / .test / no extension (jdbc class names)

All non-header lines until the next header are the annotation, which we
preserve verbatim because it carries the human-noted symptom (e.g. "원인 불명:
sql hash text에 'bind_var_cnt'이 추가 됨").

Output JSON shape:
{
  "failures": [
    {
      "tc_path":      "shell/_06_issues/.../foo.sh",
      "category":     "shell",
      "runone_skill": "cubrid-shell-tc-runone",
      "annotation":   "[history]  [AI Analysis]  [verify]\\n..."
    },
    ...
  ]
}
"""
from __future__ import annotations
import json
import re
import sys
from typing import Iterable


CATEGORY_TO_RUNONE: dict[str, str] = {
    "shell":     "cubrid-shell-tc-runone",
    "sql":       "cubrid-sql-tc-runone",
    "ha_shell":  "cubrid-ha_shell-tc-runone",
    "ha_repl":   "cubrid-ha_repl-tc-runone",
    "cdc_repl":  "cubrid-cdc_repl-tc-runone",
    "isolation": "cubrid-isolation-tc-runone",
    "jdbc":      "cubrid-jdbc-tc-runone",
    "cci":       "cubrid-cci-tc-runone",
    "unittest":  "cubrid-unittest-tc-runone",
}

CATEGORY_PREFIXES = "|".join(re.escape(c) for c in CATEGORY_TO_RUNONE)
HEADER_RE = re.compile(rf"^({CATEGORY_PREFIXES})/[^\s]+$")


def parse(lines: Iterable[str]) -> list[dict]:
    failures: list[dict] = []
    current: dict | None = None
    annot: list[str] = []

    def flush() -> None:
        if current is not None:
            current["annotation"] = "\n".join(annot).strip()
            failures.append(current)

    for raw in lines:
        line = raw.rstrip("\n")
        m = HEADER_RE.match(line.strip())
        if m:
            flush()
            cat = m.group(1)
            current = {
                "tc_path": line.strip(),
                "category": cat,
                "runone_skill": CATEGORY_TO_RUNONE[cat],
            }
            annot = []
        else:
            if current is not None and line.strip():
                annot.append(line)
    flush()
    return failures


def main() -> None:
    if len(sys.argv) < 2:
        sys.stderr.write("usage: parse_fail_list.py <fail-list-path>\n")
        sys.exit(2)
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        failures = parse(f)
    json.dump({"failures": failures}, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
