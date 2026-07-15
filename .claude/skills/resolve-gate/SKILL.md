---
name: resolve-gate
description: "Gate a CBRD Handover issue for QA-readiness before it moves to Resolved (\"Accept the fix\") — run by the developer as a self-check on their own fix. Judges whether the issue's content (description + comments + attachments) lets QA write a test plan (test-plannability), then emits READY / NOT-READY plus a self-remediation checklist. Use whenever someone says \"resolve-gate 돌려줘\", \"handover 판정해줘\", \"내 이슈 Resolved로 올려도 되나\", \"QA readiness 심사\", \"Handover pool 게이트\", \"resolve gate\", even without the exact word. Read-only: it drafts a checklist and a report; the developer fixes gaps and does the Jira transition. NOT for: writing testcases (cubrid-*-tc-create), running tests, executing the fix, or performing Jira status transitions itself."
---

# resolve-gate — QA-readiness gate (Handover → Resolved)

**Run by the developer** on their own fix before moving it to Resolved — a self-check that the issue's content lets QA write a test plan (chiefly the **description**, plus **comments and attachments**). This is the gate in front of tc-author: a `READY` verdict means tc-author's Ground will have material to work with.

**Read-only.** You produce a gate report + a self-remediation checklist (what to fix before Resolved). The developer reviews, fixes the gaps, and does the Jira transition. Do **not** write to Jira or run the fix.

Design rationale and the 27-issue PoC that validated these criteria: `agents/resolve-gate/DESIGN.md` and `agents/resolve-gate/reports/poc-guava-handover.md`.

## Scope

**Produces:** a gate report — per issue `READY` (accept-recommended, with a suitable-runner tag) or `NOT-READY` (reject-recommended, with a rejection-comment draft).

**Does NOT:** write to Jira (drafts only), transition status, run the fix / repro, use local CTP or a CUBRID build, or write testcases.

## Before you start

- **cubrid-jira CLI installed + authenticated** (netrc). Sanity check: `cubrid-jira search CBRD-27052`. If it errors, stop and tell the user to authenticate.
- **No CTP / CUBRID build needed** — fix execution is out of scope (verifying that the fix actually works is a future option, not this gate).
- cubrid-jira usage notes worth remembering: batch read with `--output json`; `assignee.name` (login, e.g. `vimkim`) not `displayName`; `comment-list` truncates bodies (use a library GET for full comment text if needed).

## Pipeline

```
Select (batch read) → Classify (bug vs feature) → Judge (C0~C6) → Gate report + rejection drafts
```

## 1. Select — batch read the pool

**Primary use** — the developer runs it on their own issue, the fix they're about to move to Resolved: `/resolve-gate CBRD-XXXXX`. Fetch its body, comments, and attachments:

```
cubrid-jira search CBRD-XXXXX
# or, for structured fields incl. comments/attachments:
cubrid-jira jql "project = CBRD AND key = CBRD-XXXXX" \
  --fields summary,issuetype,description,comment,attachment,fixVersions,customfield_210565 --output json
```

**Secondary use (QA/admin batch)** — scan the whole pool in one call:

```
cubrid-jira jql "project = CBRD AND cf[210441] = guava AND status = Handover ORDER BY updated DESC" \
  --fields summary,issuetype,description,comment,attachment,fixVersions,customfield_210565,assignee --output json
```

- `cf[210441]` = Planned Version (guava), `cf[210565]` = QA Scenario.
- **Read comments and attachments, not just the description** — regression/core issues carry their repro info and the failing/core-triggering testcase there (see C1). `comment-list` truncates bodies; use a library GET for full comment text if a comment looks load-bearing.

## 2. Classify — bug vs feature (critical; the PoC's key finding)

Split by `issuetype` **before** judging:

- **Correct Error** → **bug**
- everything else (Improve Function / Sub-task / Development Subject / Internal Management …) → **feature**

Why this matters: the blocking criteria are bug-shaped (repro + Expected/Actual). Applying them to feature issues misjudged ~85% (23/27) of the real pool. The original dry-run happened to be all bugs, which hid the bias.

## 3. Judge — blocking criteria (test-plannability)

Blocking = decides READY/NOT-READY. Apply the set that matches the issue kind:

| Kind | Blocking criteria |
|---|---|
| **Bug** | **C1 Repro self-contained** — repro steps/script present and runnable as-is (no missing schema/data, no typos). **Regression/core exception:** if the testcase that triggered the core / regression fail is **attached** to the issue (often referenced in a comment), that TC *is* the repro — no separate reproduction step needed. Check comments + attachments, not just the description. **C2 Expected/Actual** — post-fix expected + pre-fix bug behavior; for regression/core, "that attached TC fails now → passes after the fix" is the Expected/Actual. |
| **Feature** | **C1′ Spec concreteness** — Specification Changes are concrete (I/O, error conditions, examples). **C2′ AC verifiability** — Acceptance Criteria are observable and specific enough for QA to derive cases. |

**C0 (both kinds):** can QA write a test plan from the description alone? Include **abstract-AC detection** as an explicit fail signal — "must not cause problems", "no performance regression", "verify with various scenarios" are the top NOT-READY reason for feature issues.

Warnings (report, don't block) — handover hygiene: **C3 Fixed version · C5 QA Scenario · C6 Need Manual · C4 spec/config reflected.** C3 is noisy — at Handover the merge version is often undecided (PoC: 25/27 blank), so keep C3 low-priority and revisit it after Resolved.

**QA Scenario = Not Required:** judge but tag "TC 미대상"; don't block (a test plan isn't going to be written anyway).

## 4. Gate report + rejection drafts

**READY** → attach a suitable-runner tag: `SQL` / `shell` / `CCI` / `perftool`. A `READY` issue can still be observable only outside SQL (CCI/JDBC, performance, statdump, internal storage) — tag it so downstream tc-author (SQL-only) doesn't pick it up in vain.

**NOT-READY** → produce a **self-remediation checklist**: what the developer must fix before moving the issue to Resolved (Korean, user-facing perspective — describe the gap, not code). The developer runs this on their own issue, so it's a self-check, not a call to someone else. Template:

```
[resolve-gate] 이 이슈는 Resolved로 올리기 전에 보완이 필요합니다 (QA가 검증 시나리오를 짤 수 있도록).
- 내용: {C0~C2 (버그) 또는 C1'~C2' (기능) 중 무엇이 왜 부족한지 — repro 자기완결/Expected·Actual/추상 AC 등, 구체적으로}
- 필드: {Fixed version·QA Scenario 등 미기입 항목 (경고)}
```

(다른 개발자의 이슈를 점검하는 경우에만 `@{fields.assignee.name}`으로 확인 요청을 붙인다.)

**Avoid false positives:** treat a repro "typo" as a **question, not a defect** — for a line-accuracy bug it can be the intended test input (PoC: CBRD-26909). Flag it for the developer to confirm, don't auto-fail.

## Output

Write the gate report to `agents/resolve-gate/reports/resolve-gate-<date>.md` (gitignore). Sections: query + count; per-issue verdict table (key · summary · kind · C-criteria basis · READY/NOT-READY · runner tag · hygiene warnings); self-remediation checklist for each NOT-READY; stats (READY/NOT-READY ratio). Checklists stay in the report — **do not auto-post to Jira** (PoC). The developer reads the checklist, fixes the gaps, then moves the issue to Resolved.

## Staging

- **PoC (now):** the developer reads the checklist, fixes gaps, and does the transition; the skill drafts only (no Jira write).
- **Later:** optional auto-post of the checklist to the issue, then automated transition (Stage 3). Draft-first rollout mirrors tc-author, so a false positive never lands on the issue prematurely.
