---
name: resolve-gate
description: "Gate CBRD Handover issues for QA-readiness before they move to Resolved (\"Accept the fix\"). Judges whether each issue's content lets QA write a test plan (test-plannability), then emits READY / NOT-READY plus a rejection-comment draft. Use whenever someone says \"resolve-gate 돌려줘\", \"handover 판정해줘\", \"QA readiness 심사\", \"Handover pool 게이트\", \"resolve gate\", \"이 이슈 Resolved로 받아도 되나\", even without the exact word. Read-only: it drafts comments and a report; a human posts and does the Jira transition. NOT for: writing testcases (cubrid-*-tc-create), running tests, executing the fix, or performing Jira status transitions itself."
---

# resolve-gate — QA-readiness gate (Handover → Resolved)

Judge whether a Handover issue is ready for QA to accept the fix — i.e. whether its content (chiefly the **description**) lets QA write a test plan. This is the gate in front of tc-author: a `READY` verdict means tc-author's Ground will have material to work with.

**Read-only.** You produce a gate report + rejection-comment drafts. A human reviews, posts comments, and does the Jira transition. Do **not** write to Jira or run the fix.

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

Default target is the whole guava Handover pool. One batch call fetches every issue's body + fields:

```
cubrid-jira jql "project = CBRD AND cf[210441] = guava AND status = Handover ORDER BY updated DESC" \
  --fields summary,issuetype,description,fixVersions,customfield_210565,assignee --output json
```

- `cf[210441]` = Planned Version (guava), `cf[210565]` = QA Scenario.
- Single issue: `/resolve-gate CBRD-XXXXX` → add `AND key = CBRD-XXXXX` (or `cubrid-jira search CBRD-XXXXX`).
- QA Assignee is unset at Handover, so don't filter by it. Category-agnostic: readiness doesn't need an SQL-only filter.

## 2. Classify — bug vs feature (critical; the PoC's key finding)

Split by `issuetype` **before** judging:

- **Correct Error** → **bug**
- everything else (Improve Function / Sub-task / Development Subject / Internal Management …) → **feature**

Why this matters: the blocking criteria are bug-shaped (repro + Expected/Actual). Applying them to feature issues misjudged ~85% (23/27) of the real pool. The original dry-run happened to be all bugs, which hid the bias.

## 3. Judge — blocking criteria (test-plannability)

Blocking = decides READY/NOT-READY. Apply the set that matches the issue kind:

| Kind | Blocking criteria |
|---|---|
| **Bug** | **C1 Repro self-contained** — repro steps/script present and runnable as-is (no missing schema/data, no typos). **C2 Expected/Actual** — post-fix expected behavior + pre-fix bug behavior stated. |
| **Feature** | **C1′ Spec concreteness** — Specification Changes are concrete (I/O, error conditions, examples). **C2′ AC verifiability** — Acceptance Criteria are observable and specific enough for QA to derive cases. |

**C0 (both kinds):** can QA write a test plan from the description alone? Include **abstract-AC detection** as an explicit fail signal — "must not cause problems", "no performance regression", "verify with various scenarios" are the top NOT-READY reason for feature issues.

Warnings (report, don't block) — handover hygiene: **C3 Fixed version · C5 QA Scenario · C6 Need Manual · C4 spec/config reflected.** C3 is noisy — at Handover the merge version is often undecided (PoC: 25/27 blank), so keep C3 low-priority and revisit it after Resolved.

**QA Scenario = Not Required:** judge but tag "TC 미대상"; don't block (a test plan isn't going to be written anyway).

## 4. Gate report + rejection drafts

**READY** → attach a suitable-runner tag: `SQL` / `shell` / `CCI` / `perftool`. A `READY` issue can still be observable only outside SQL (CCI/JDBC, performance, statdump, internal storage) — tag it so downstream tc-author (SQL-only) doesn't pick it up in vain.

**NOT-READY** → draft a rejection comment (Korean, user-facing perspective — describe the gap, not code). Template:

```
[resolve-gate] {현재 내용으로는 QA가 검증 시나리오를 짤 수 없어 Resolved로 받기 어렵습니다.}
- 내용: {C0~C2 (버그) 또는 C1'~C2' (기능) 중 무엇이 왜 부족한지 — repro 자기완결/Expected·Actual/추상 AC 등, 구체적으로}
- 필드: {Fixed version·QA Scenario 등 미기입 항목 (경고)}
@{fields.assignee.name} {확인·보완 부탁드립니다. 의도된 것이면 알려주시면 그대로 진행하겠습니다.}
```

**Avoid false positives:** this is a **confirmation request, not an auto-reject**. A repro "typo" can be the intended test input for a line-accuracy bug (PoC: CBRD-26909) — always phrase rejection as "@mention + please confirm", never a hard reject.

## Output

Write the gate report to `agents/resolve-gate/reports/resolve-gate-<date>.md` (gitignore). Sections: query + count; per-issue verdict table (key · summary · kind · C-criteria basis · READY/NOT-READY · runner tag · hygiene warnings); rejection drafts for NOT-READY; stats (READY/NOT-READY ratio). Rejection drafts stay in the report — **do not post them** (PoC). Report to the user which issues are NOT-READY and hand them the drafts.

## Staging

- **PoC (now):** human posts comments and does transitions; the bot drafts only.
- **Later:** auto-post rejection comments, then automated transition (Stage 3). The gradual rollout mirrors tc-author — draft first so a false positive never pings a real developer.
