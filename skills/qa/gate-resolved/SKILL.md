---
name: gate-resolved
description: "Review a Resolved CBRD issue (a QA to-do) for QA-readiness and bounce back the ones QA can't turn into a test plan, via the 'Need Something' transition (Resolved->Handover). Run by QA. Two axes: (1) necessity — re-judge the QA Scenario field (a developer's 'Not Required' can be overturned by QA); (2) plannability — can a test plan be written from the content. Use whenever someone says \"gate-resolved 돌려줘\", \"Resolved 검토\", \"QA to-do 점검\", \"테스트 플랜 못 짜는 이슈 반려\", \"Need Something 반송\", even without the exact word. Read-oriented: drafts a report + rejection comments; Jira writes (field change, transition) are staged. NOT for: writing testcases (cubrid-*-tc-create), running tests, executing the fix, or the Check-in Fix (Handover->Resolved, which the developer does)."
---

# gate-resolved — Resolved QA-readiness gate

Review **Resolved (= QA to-do) issues** and **bounce back the ones QA can't turn into a test plan** to Handover via the `Need Something` transition. Passing issues continue to the author-testcase stage. Run by **QA**.

Verdict few-shots: [`examples/verdicts.md`](./examples/verdicts.md).

## Scope

**Produces:** a gate report — per issue pass (Start Test candidate) / bounce (Need Something) / skip (not needed), with a rejection-comment draft for the bounces. Jira writes (QA Scenario field change, transition) are **staged** (see matrix).

**Does NOT:** write testcases, run the fix, use CTP/build, or do Check-in Fix (Handover→Resolved — the developer does that).

## Before you start

- cubrid-jira installed + authenticated. Sanity: `cubrid-jira search CBRD-XXXXX`.
- No CTP / CUBRID build needed.
- **Download and read every attachment (required, before you judge).** Many issues carry the repro or intent only in the attachments. Use `cubrid-jira attachment <KEY>` (if not available, interim: take each `.content` URL from `cubrid-jira jql 'key=<KEY>' --fields attachment --output json` and `curl --netrc -o <file>` it — credentials come from `.netrc` (jira.cubrid.org) or `-u $CUBRID_JIRA_USER:$CUBRID_JIRA_PASSWORD`). **Check `.size` before fetching — for anything >5MB (cores and binaries included), skip the curl itself** and record only the metadata plus the reason. Fetch only the rest, read the text/code (.sql/.txt/.log/.sh/.json, etc.) closely, and read images visually with the Read multimodal.

## Two-axis judgment

Each Resolved issue is judged on two axes:

1. **Necessity — QA Scenario re-judgment.** The QA Scenario field (`cf[210565]`) is the developer's draft; QA re-judges it. A developer's **`Not Required` can be overturned** if QA sees a test is needed → treat as needed. Don't blindly skip Not Required.
2. **Plannability — test-plannability.** If needed, can a test plan be written from description + **comments + attachments**? Bug/feature bifurcation (C0~C6), regression/core attached-TC exception.

**Outcome → transition:**
- **needed + plannable** → pass: `Start Test` (→Test, author-testcase stage). Set QA Scenario to Required per stage if re-judged.
- **needed + NOT plannable** → **bounce: `Need Something` (→Handover)** + rejection comment (the missing pieces).
- **not needed (QA agrees)** → skip (not a test target).

## Pipeline

```
Select (stage-scoped) → Necessity → Plannability → Transition + report
```

## 1. Select (stage-scoped)

- **PoC**: `project = CBRD AND cf[210441] = guava AND status = Resolved AND cf[213834] = twkang` (QA assignee = twkang).
- **Team-internal / Automation**: `project = CBRD AND cf[210441] = guava AND status = Resolved`.
- Single issue: `/gate-resolved CBRD-XXXXX`.

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

**C0 (both):** can QA write a test plan from the content? Abstract AC ("must not cause problems", "no perf regression", "various scenarios") is the top bounce reason for features.

**Warnings (report, don't bounce):** C3 Fixed version · C5 QA Scenario · C6 Need Manual · C4 spec reflected. **C6 manual is warning-only** — the manual is often written *after* Resolved, so a missing manual does not bounce the issue.

## 4. Transition + report + rejection draft

- **pass** → `Start Test` (PoC / team-internal: propose; automation: auto-run + trigger author-testcase).
- **bounce** → **sub-task guard first**, then `Need Something`. If the issue is a **sub-task**, check parent + sibling sub-tasks: if a sibling handles TC/scenario authoring, that sibling covers the test → **do not bounce** (skip/pass this one). Bouncing per-individual-sub-task causes **status ping-pong** (dev re-resolves → bounce again). Only bounce when no sibling covers it and it's not plannable: `cubrid-jira transition <KEY> --to "Need Something" --yes` (PoC / team-internal: draft + manual; automation: auto). Rejection comment in Korean, to the developer.

Transition map (measured 2026-07-16): **Need Something→Handover** (bounce), **Start Test→Test** (pass), Assign QA→Resolved (stays put), QA Not Satisfied→Confirmed (fix inadequate, out of scope), Ask Reconfirmation→Open (out of scope).

Rejection comment template (Korean — posted to the developer on the Jira issue):
```
[gate-resolved] 현재 내용으로는 QA가 테스트 플랜을 짤 수 없어 Handover로 되돌립니다 (Need Something).
- 부족: {C0~C2(버그) 또는 C1'~C2'(기능) 중 무엇이 왜 — repro 자기완결/Expected·Actual/추상 AC 등, 구체적으로}
- (필드: Fixed version 등 미기입 — 경고)
@{개발자 assignee} 위 내용을 보완해 주시면 다시 검토하겠습니다.
```
**Avoid false positives:** a repro "typo" can be the intended input for a line-accuracy bug (PoC CBRD-26909) — ask "is this intended?", don't auto-bounce.

## Stage matrix

| | Select scope | QA Scenario change | Transition execution | Passing issues |
|---|---|---|---|---|
| **PoC (Stage 1)** | assignee=twkang | propose only | manual (draft) | bounces only |
| **Team-internal rollout (Stage 2)** | all guava Resolved | propose only (manual) | manual | bounce |
| **Automation (Stage 3)** | all guava Resolved | change directly | auto transition | trigger author-testcase (Start Test) |

## Output

Write the report to `$HOME/.cubrid-agent/reports/gate-resolved/gate-resolved-<date>.md`: query + count; per-issue table (key · summary · kind · necessity · plannability basis · pass/bounce/skip · runner tag · warnings); rejection drafts for the bounces; stats. In PoC / team-internal, transitions and comment posting are done by a human — the skill drafts only.
