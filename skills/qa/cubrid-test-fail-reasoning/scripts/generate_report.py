#!/usr/bin/env python3
"""Generate report.md by mining each TC's diff for the introducing commit.

Heuristics (priority order, first match wins):

  1. New `;<name>=<value>` suffix that appears only on the actual side of a
     `sql hash text =` line (e.g. `;bind_var_cnt=2`, `;remote={...}`).
     This is the most reliable signal because the parser writes such suffixes
     into a single string that flows into both plandump output and SHA1Compute.

  2. New `?<digits>="..."` host-var locale fingerprints (`?193="en_US"`).

  3. New `,<flag>=<value>` query-cache or session attributes.

  4. Numeric byte-counter shifts in `QM_QUERY_*` lines — the script does NOT
     try to bisect these directly (the byte delta itself isn't a stable token);
     it groups them with sibling failures that share an upstream hash text
     change.

  5. sha1 / XASL_ID changes — explicitly skipped as a primary token because
     they are downstream of (1)/(2)/(3). The report records them as the
     visible symptom but bisects via the upstream group token.

For each candidate token we run:
    git log --oneline <commit-range> -G '<token>' -- <subtree>
limited first to src/parser src/query src/optimizer (where hash text is built)
then widening to src/ if no hit.

Failures whose tokens collide are grouped — the report has a "Root-cause
groups" section with one diagnosis per group, then a per-row table for full
traceability.
"""
from __future__ import annotations
import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict


# ---- token extraction ----------------------------------------------------

# `<` introduces the actual line in `diff` output.  We look for what the
# expected (`>` or `|`) side does NOT have.
SUFFIX_KV_RE = re.compile(r";([a-z_]+=[^\s ;)]+)")
HOST_VAR_RE = re.compile(r"\?(\d+=\"[^\"]*\")")
QM_BYTES_RE = re.compile(r"QM_QUERY_\w+\s+\d+\s*X\s*(\d+)\+")
SHA1_RE = re.compile(r"sha1\s*=\s*\{\s*[0-9a-f ]+\}")

# Tokens the fail.txt annotation may name explicitly. Side-by-side diff
# truncates long lines so the actual hash text suffix may be invisible in
# `failing_diffs`; the human annotation (e.g. "sql hash text에 'bind_var_cnt'
# 이 추가 됨") is often the most reliable token source.
ANNOT_QUOTED_RE = re.compile(r"['\"`]([A-Za-z_][\w.-]{2,})['\"`]")
ANNOT_KEYWORD_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]{3,})\b")
ANNOT_HINT_KEYWORDS = {
    "추가": "suffix", "바뀜": "sha1_or_byte", "변경": "sha1_or_byte",
    "added": "suffix", "changed": "sha1_or_byte",
}
ANNOT_BLOCKLIST = {  # generic words that should not become a token
    "unknown", "verified", "history", "Analysis", "verify",
    "원인", "불명", "값이", "값", "추가", "바뀜", "변경",
    "song", "Won", "ryong",
}


def extract_token_from_annotation(annotation: str) -> tuple[str, str]:
    if not annotation:
        return "", ""
    # 1) Quoted identifier — most precise
    for m in ANNOT_QUOTED_RE.finditer(annotation):
        cand = m.group(1)
        if cand not in ANNOT_BLOCKLIST:
            return cand, "annotation_quoted"
    # 2) Pick a recognizable upper-case identifier (e.g. QM_QUERY_DROP_ALL_PLANS,
    #    XASL_ID, SQL_ID) — these don't get truncated and bisect cleanly
    for m in ANNOT_KEYWORD_RE.finditer(annotation):
        cand = m.group(1)
        if cand in ANNOT_BLOCKLIST:
            continue
        if cand.isupper() and len(cand) >= 6:
            return cand, "annotation_uppercase"
    return "", ""


def extract_token(annotation: str, diff_blocks: list[str]) -> tuple[str, str]:
    """Return (token, kind). kind labels:
       suffix, hostvar, sha1, byte_shift, annotation_quoted, annotation_uppercase, ''"""
    # First try the annotation — it survives diff truncation
    tok, kind = extract_token_from_annotation(annotation)
    if tok:
        return tok, kind

    has_sha1 = False
    has_qm = False
    for block in diff_blocks:
        actual_lines = []
        expected_lines = []
        for line in block.splitlines():
            if line.startswith("<"):
                actual_lines.append(line[1:])
            elif line.startswith(">"):
                expected_lines.append(line[1:])
            else:
                # diff side-by-side ('|' separator); split on first occurrence
                if " | " in line or "\t|\t" in line:
                    sep_idx = max(line.find(" | "), line.find("\t|\t"))
                    if sep_idx > 0:
                        actual_lines.append(line[:sep_idx])
                        expected_lines.append(line[sep_idx + 3:])
        actual_text = "\n".join(actual_lines)
        expected_text = "\n".join(expected_lines)

        # 1. ;name=value suffixes
        for m in SUFFIX_KV_RE.finditer(actual_text):
            cand = m.group(1).split("=")[0]
            cand_full = f";{cand}="
            if cand_full not in expected_text:
                return cand_full, "suffix"

        # 2. ?N="..." host var locale fingerprints
        for m in HOST_VAR_RE.finditer(actual_text):
            cand = "?" + m.group(1)
            if cand not in expected_text:
                key = re.match(r"\?(\d+)", cand).group(0)
                return f'?{key[1:]}="', "hostvar"

        # 3. Categories for fallback grouping
        if SHA1_RE.search(actual_text):
            has_sha1 = True
        if QM_BYTES_RE.search(actual_text):
            has_qm = True

    if has_sha1:
        return "", "sha1"
    if has_qm:
        return "", "byte_shift"
    return "", ""


# ---- bisect over the commit range ---------------------------------------

GIT_SUBTREES_NARROW = ["src/parser", "src/query", "src/optimizer"]
GIT_SUBTREES_WIDE = ["src"]


def git_bisect_token(token: str, commit_range: str, repo: str) -> str:
    if not token:
        return ""
    for subtrees in (GIT_SUBTREES_NARROW, GIT_SUBTREES_WIDE):
        try:
            cmd = ["git", "-C", repo, "log", "--oneline", commit_range,
                   "-G", token, "--"] + subtrees
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
        except Exception:
            return ""
        line = out.strip().splitlines()[0] if out.strip() else ""
        if line:
            return line
    return ""


# ---- verdict heuristic ---------------------------------------------------

ANSWER_FIX_KEYWORDS = (
    "hash text", "XASL_ID", "sha1", "QM_QUERY_", "bind_var_cnt", "remote=",
    "answer", "format", "plan cache",
)
BUG_KEYWORDS = (
    "core dump", "crash", "wrong result", "값이 틀림", "잘못된", "deadlock",
    "hang", "leak", "성능", "regression",
)


def verdict_for(symptom: str, kind: str) -> str:
    s = (symptom or "").lower()
    if any(k in s for k in (k.lower() for k in BUG_KEYWORDS)):
        return "bug-report"
    if kind in ("suffix", "hostvar", "sha1", "byte_shift"):
        return "answer-fix"
    if any(k in s for k in (k.lower() for k in ANSWER_FIX_KEYWORDS)):
        return "answer-fix"
    return "investigate"


def symptom_from_annotation(annotation: str) -> str:
    """Pull the human-noted reason out of fail.txt's annotation block."""
    if not annotation:
        return ""
    for line in annotation.splitlines():
        if any(t in line for t in ("원인 ", "unknown", "바뀜", "추가", "원인:", "[unknown]")):
            return line.strip()
    return annotation.splitlines()[0].strip()


# ---- main ----------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", required=True)
    ap.add_argument("--branch", required=True)
    ap.add_argument("--commit-range", required=True)
    ap.add_argument("--out", default="report.md")
    ap.add_argument("--repo", default=".",
                    help="git repo to bisect in (default: cwd)")
    args = ap.parse_args()

    runs = json.load(open(args.runs, encoding="utf-8"))["runs"]

    rows = []
    for r in runs:
        symptom = symptom_from_annotation(r.get("annotation", ""))
        token, kind = extract_token(r.get("annotation", ""), r.get("failing_diffs", []))
        suspect = git_bisect_token(token, args.commit_range, args.repo) if token else ""
        rows.append({
            "tc": r["tc_path"],
            "category": r.get("category", ""),
            "status": r.get("status", ""),
            "symptom": symptom,
            "token": token,
            "kind": kind,
            "suspect": suspect,
            "verdict": verdict_for(symptom, kind),
        })

    # Group by token (within same kind) so we can summarize root causes
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for row in rows:
        groups[(row["kind"], row["token"])].append(row)

    # Co-failures within the same commit window typically share one root
    # cause. If any row got a clean suspect, propagate it to rows whose
    # bisect was empty (e.g. tokens like XASL_ID / sha1 / QM_QUERY_* that
    # don't textually change in commits but reflect downstream effects).
    # The propagation is marked "(inferred)" so reviewers know it wasn't a
    # direct git-log hit.
    suspect_pool = [r["suspect"] for r in rows if r["suspect"]]
    if suspect_pool:
        # Pick the most-frequent suspect as the inferred root cause
        from collections import Counter
        inferred = Counter(suspect_pool).most_common(1)[0][0]
        for row in rows:
            if not row["suspect"]:
                row["suspect"] = inferred + "  (inferred — no direct git-log hit)"

    # Write the report
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("# CUBRID Test Failure Reasoning Report\n\n")
        f.write(f"- Branch: `{args.branch}`\n")
        f.write(f"- Commit range: `{args.commit_range}`\n")
        f.write(f"- Total TCs analyzed: {len(rows)}\n")
        nok = sum(1 for r in rows if r["status"] == "NOK")
        ok = sum(1 for r in rows if r["status"] == "OK")
        delegated = sum(1 for r in rows if r["status"] == "DELEGATE")
        notfound = sum(1 for r in rows if r["status"] == "NOT_FOUND")
        f.write(f"- Status counts: NOK={nok} OK={ok} DELEGATE={delegated} NOT_FOUND={notfound}\n\n")

        # Root-cause groups
        f.write("## Root-cause groups\n\n")
        non_trivial = [(k, v) for k, v in groups.items() if k[1] or k[0] in ("sha1", "byte_shift")]
        if not non_trivial:
            f.write("_No structured tokens extracted; see per-row table below._\n\n")
        else:
            for (kind, token), members in non_trivial:
                head = token if token else f"<{kind}>"
                suspect = next((m["suspect"] for m in members if m["suspect"]), "")
                f.write(f"### `{head}` ({kind}, {len(members)} TC)\n\n")
                if suspect:
                    f.write(f"- Suspect commit: `{suspect}`\n")
                f.write(f"- Members:\n")
                for m in members:
                    f.write(f"  - `{m['tc']}`\n")
                f.write("\n")

        # Per-row table
        f.write("## Per-test details\n\n")
        f.write("| # | Test Case | Category | Status | Symptom | Token | Kind | Suspect commit | Verdict |\n")
        f.write("|---|-----------|----------|--------|---------|-------|------|----------------|---------|\n")
        for i, r in enumerate(rows, 1):
            sym = (r["symptom"] or "").replace("|", "\\|")[:160]
            tok = (r["token"] or "")[:40]
            f.write(
                f"| {i} | `{r['tc']}` | {r['category']} | {r['status']} | "
                f"{sym} | `{tok}` | {r['kind']} | {r['suspect']} | {r['verdict']} |\n"
            )

    print(f"[generate_report] wrote {args.out}")


if __name__ == "__main__":
    main()
