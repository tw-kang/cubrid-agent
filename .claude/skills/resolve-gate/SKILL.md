---
name: resolve-gate
description: "Review a Resolved CBRD issue (a QA to-do) for QA-readiness and bounce back the ones QA can't turn into a test plan, via the 'Need Something' transition (Resolved->Handover). Run by QA. Two axes: (1) necessity — re-judge the QA Scenario field (a developer's 'Not Required' can be overturned by QA); (2) plannability — can a test plan be written from the content. Use whenever someone says \"resolve-gate 돌려줘\", \"Resolved 검토\", \"QA to-do 점검\", \"테스트 플랜 못 짜는 이슈 반려\", \"Need Something 반송\", even without the exact word. Read-oriented: drafts a report + rejection comments; Jira writes (field change, transition) are staged. NOT for: writing testcases (cubrid-*-tc-create), running tests, executing the fix, or the Check-in Fix (Handover->Resolved, which the developer does)."
---

# resolve-gate — Resolved QA-readiness gate

Review **Resolved (= QA to-do) issues** and **bounce back the ones QA can't turn into a test plan** to Handover via the `Need Something` transition. Passing issues continue to the tc-author stage. Run by **QA**.

Verdict few-shots: [`examples/verdicts.md`](./examples/verdicts.md).

## Scope

**Produces:** a gate report — per issue 통과(Start Test candidate) / 반송(Need Something) / 스킵(not needed), with a rejection-comment draft for 반송. Jira writes (QA Scenario field change, transition) are **staged** (see matrix).

**Does NOT:** write testcases, run the fix, use CTP/build, or do Check-in Fix (Handover→Resolved — the developer does that).

## Before you start

- cubrid-jira installed + authenticated. Sanity: `cubrid-jira search CBRD-XXXXX`.
- No CTP / CUBRID build needed.
- **첨부 전부 다운로드+읽기(필수, 판정 전).** 재현·의도가 첨부에만 있는 이슈가 많다. `cubrid-jira attachment <KEY>`(미탑재 시 interim: `cubrid-jira jql 'key=<KEY>' --fields attachment --output json`의 각 `.content` URL을 `curl --netrc -o <file>` — 자격은 `.netrc`(jira.cubrid.org) 또는 `-u $CUBRID_JIRA_USER:$CUBRID_JIRA_PASSWORD`). 읽기: 텍스트·코드(.sql/.txt/.log/.sh/.json 등) 정독 + 이미지 Read 멀티모달로 시각 판독 + 코어·바이너리·>5MB는 미정독 사유만 기록.

## Two-axis judgment

Each Resolved issue is judged on two axes:

1. **Necessity — QA Scenario re-judgment.** The QA Scenario field (`cf[210565]`) is the developer's draft; QA re-judges it. A developer's **`Not Required` can be overturned** if QA sees a test is needed → treat as needed. Don't blindly skip Not Required.
2. **Plannability — test-plannability.** If needed, can a test plan be written from description + **comments + attachments**? Bug/feature bifurcation (C0~C6), regression/core attached-TC exception.

**Outcome → transition:**
- **needed + plannable** → 통과: `Start Test` (→Test, tc-author stage). Set QA Scenario to Required per stage if re-judged.
- **needed + NOT plannable** → **반송: `Need Something` (→Handover)** + rejection comment (the missing pieces).
- **not needed (QA agrees)** → skip (not a test target).

## Pipeline

```
Select (stage-scoped) → Necessity → Plannability → Transition + report
```

## 1. Select (stage-scoped)

- **PoC**: `project = CBRD AND cf[210441] = guava AND status = Resolved AND cf[213834] = twkang` (QA assignee = twkang).
- **팀내/자동화**: `project = CBRD AND cf[210441] = guava AND status = Resolved`.
- Single issue: `/resolve-gate CBRD-XXXXX`.

Batch read: `--fields summary,issuetype,description,comment,attachment,fixVersions,customfield_210565,assignee,parent,subtasks --output json`. `cf[210441]`=Planned Version(guava), `cf[210565]`=QA Scenario, `cf[213834]`=QA Assignee. **Read comments; download + read every attachment's content per Before-you-start** (not just filenames — the "runnable repro TC attached" plannability call needs the actual file), and **parent/subtasks** (sub-task bounce guard, step 4).

## 2. Necessity — QA Scenario re-judgment (bidirectional)

QA re-judges necessity in **both directions** (PoC: 6/17 flipped):
- **Promote (Not Required / Not Yet → needed)**: crash / core / data-integrity / regression risk → needed even if the developer set Not Required. Set QA Scenario to Required per stage (propose vs write).
- **Demote (Required → not needed)**: no test surface (e.g. build-only AC) → drop from needed. (PoC: CBRD-26701, AC = "build succeeds".)
- **Precheck — resolution status**: Won't-do / Duplicate / Deferred → not a test target regardless of QA Scenario or severity; skip **before** necessity. (PoC: 26957 Won't-do — would be mis-promoted on severity alone.)
- **Necessity skip categories** (not caught by the QA Scenario field): EPIC, build-only AC, internal not-yet-GA feature.
- **Issue-type prior** (user rule): issue nature gives a prior —
  - **new feature** (Improve Function): Required likely (new feature = new verification).
  - **refactoring**: Required unlikely (developer test or existing regression suffices; no new scenario).
  - **regression/core fail — the discovery path decides**: caused by the *regression suite* (a regression test caught it) → **Not Required** (existing TC already covers); a *new bug report* outside the suite → **Required likely** (new TC).
  → So crash/core is not an automatic promote — check comments/attachments for who/how it was found. **Also: if the fix has no behavior change (debug-only assert addition, internal refactoring), it is not an SQL-TC target** — release behavior is unchanged (no user-observable diff) and debug regression covers the assert. (CBRD-26888 re-check: promoted in PoC as "core", but Not Required on review — the fix only adds a debug assert condition, release unchanged.)

## 3. Plannability — test-plannability (C0~C6)

Bifurcate by `issuetype`: **Correct Error=bug**, else=feature.

| Kind | Blocking criteria |
|---|---|
| **Bug** | **C1 Repro self-contained** (runnable as-is). *Regression/core exception:* if a **runnable repro TC is attached** (often via a comment), that TC *is* the repro — no separate step. **Decision line = a *runnable* repro TC exists**; an analysis doc or stack trace alone is not enough (PoC: 26888/24838 pass vs 26965 bounce). **C2 Expected/Actual** (post-fix + pre-fix). *Probabilistic/timing repro:* pass if a **positive assertion is verifiable** (always-succeeds after fix), bounce if the assertion is **negative + nondeterministic** (e.g. a race crash) — request a deterministic repro (PoC: 26799 pass vs 26965 bounce). |
| **Feature** | **C1′ Spec concreteness** (I/O, error conditions, examples). **C2′ AC verifiability** (observable, specific enough to derive cases). |

**C0 (both):** can QA write a test plan from the content? Abstract AC ("must not cause problems", "no perf regression", "various scenarios") is the top 반송 reason for features.

**Warnings (report, don't bounce):** C3 Fixed version · C5 QA Scenario · C6 Need Manual · C4 spec reflected. **C6 manual is warning-only** — the manual is often written *after* Resolved, so a missing manual does not bounce the issue.

## 4. Transition + report + rejection draft

- **통과** → `Start Test` (PoC/팀내: propose; 자동화: auto-run + trigger tc-author).
- **반송** → **sub-task guard first**, then `Need Something`. If the issue is a **sub-task**, check parent + sibling sub-tasks: if a sibling handles TC/scenario authoring, that sibling covers the test → **do not bounce** (skip/pass this one). Bouncing per-individual-sub-task causes **status ping-pong** (dev re-resolves → bounce again). Only bounce when no sibling covers it and it's not plannable: `cubrid-jira transition <KEY> --to "Need Something" --yes` (PoC/팀내: draft + manual; 자동화: auto). Rejection comment in Korean, to the developer.

Transition map (2026-07-16 실측): **Need Something→Handover** (반송), **Start Test→Test** (통과), Assign QA→Resolved(제자리), QA Not Satisfied→Confirmed(fix 부적절, 범위 밖), Ask Reconfirmation→Open(범위 밖).

반송 코멘트 템플릿:
```
[resolve-gate] 현재 내용으로는 QA가 테스트 플랜을 짤 수 없어 Handover로 되돌립니다 (Need Something).
- 부족: {C0~C2(버그) 또는 C1'~C2'(기능) 중 무엇이 왜 — repro 자기완결/Expected·Actual/추상 AC 등, 구체적으로}
- (필드: Fixed version 등 미기입 — 경고)
@{개발자 assignee} 위 내용을 보완해 주시면 다시 검토하겠습니다.
```
**Avoid false positives:** a repro "typo" can be the intended input for a line-accuracy bug (PoC CBRD-26909) — ask "is this intended?", don't auto-bounce.

## Stage matrix

| | Select 범위 | QA Scenario 변경 | 전이 실행 | 통과분 |
|---|---|---|---|---|
| **PoC (Stage 1)** | assignee=twkang | 제안만 | 수동(초안) | 반송만 |
| **팀내 배포 (Stage 2)** | guava Resolved 전체 | 제안만(수동) | 수동 | 반송 |
| **자동화 (Stage 3)** | guava Resolved 전체 | 직접 변경 | 자동 전이 | tc-author 트리거(Start Test) |

## Output

Write the report to `$HOME/.cubrid-agent/reports/resolve-gate/resolve-gate-<date>.md`: query + count; per-issue table (key · summary · kind · necessity · plannability basis · 통과/반송/스킵 · runner tag · warnings); rejection drafts for 반송; stats. In PoC/팀내, transitions and comment posting are done by a human — the skill drafts only.
