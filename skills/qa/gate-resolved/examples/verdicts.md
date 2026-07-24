# gate-resolved verdict examples

Few-shot for the skill: how each issue kind maps to a verdict, runner tag, and remediation draft.

> **Actor = QA, target = Resolved (QA to-do).** The "NOT-READY" cases below are **returns**, where QA sends the issue back via `Need Something` (→Handover); the draft is the missing-info comment to send to the developer (@mention the developer assignee). "READY" means it passes → `Start Test` (→Test, author-testcase).
> **regression/core exception:** If a TC that triggered the core dump or regression failure is attached to the issue, that TC *is* the repro, so it passes without a separate repro step. Check not only the description but also the comments and attachments (see CBRD-27052).

## READY (accept-recommended + runner tag)

### CBRD-25531 (bug) — READY · runner: SQL
Complete SQL repro (drop/create/insert/set opt/query1~6) + Expected/Actual (query plan). Ideal for an SQL TC.

### CBRD-26859 (bug) — READY (borderline) · runner: CCI
C1 self-contained (synonym + CCI schema lookup) + C2 clear (owner present/missing). But it can't be observed through SQL → route to the CCI/JDBC runner.

### CBRD-26612 (feature) — READY · runner: SQL
Very concrete AC — many SQL examples, with NULL / non-DBA / non-existent handling spelled out. A feature issue, but it satisfies C1′ (Spec concreteness) and C2′ (AC verifiability).

### CBRD-26663 (feature) — READY (borderline) · runner: perftool
Half the AC is performance (CPU%), so an SQL TC is a poor fit → perftool. But "same results / no regression" is verifiable, so READY.

## NOT-READY (reject-recommended + rejection draft)

### CBRD-27052 (bug) — no repro
```
[gate-resolved] 현재 내용으로는 QA가 재현·검증 절차를 짤 수 없어 Resolved로 받기 어렵습니다.
- 내용: core 파일과 스택트레이스만 있고, 재현 절차(어떤 부하/종료 순서에서 lock_uninit_resource assert가 나는지)가 없습니다. QA가 이 crash를 유발할 시나리오를 만들 수 없습니다.
- 필드: Fixed version 미기입.
@byungwook.kim 재현 절차(또는 최소 유발 조건)를 description에 보강해 주시면 다시 검토하겠습니다.
```
→ **regression/core exception**: for issues like this, always check the comments and attachments — if a TC that triggered the core dump had been attached, that TC = repro and it would become READY. 27052 has only a stack trace and no attached failing TC, so it is NOT-READY.

### CBRD-26909 (bug) — repro typo (clarifying rejection, avoids a false positive)
```
[gate-resolved] Expected/Actual은 명확하나 재현 스키마가 그대로 실행되지 않아 현 상태로는 받기 어렵습니다.
- 내용: cubann-12.schema에서 [tbl2]를 만들지 않고 [tb2]를 ALTER(오타), [pk_tbl_id']에 불필요한 따옴표가 있어 로드가 중단됩니다. 이 이슈가 "line 정보 부정확"을 다루므로 오타가 의도된 테스트 입력인지 확인이 필요합니다.
- 필드: Fixed version 미기입.
@ctshim 의도된 오타라면 그 취지를, 실수라면 정정본을 알려주시면 바로 진행하겠습니다.
```
→ The key is to not auto-reject the typo but to ask back whether it is an intended input (in a line-inaccuracy bug, the typo may itself be the test point).

### CBRD-27028 (feature) — no AC section
```
[gate-resolved] 현 description으로는 검증 시나리오를 도출하기 어려워 Resolved 보류합니다.
- 내용: Acceptance Criteria가 없고 code reference(assert 위치)만 있어, QA가 어떤 입력에서 무엇이 정상/실패인지 판단할 기준이 없습니다.
- 필드: Fixed version 미기입, QA Scenario=Not Required.
@vimkim 관측 가능한 수용 기준(정상 동작 조건 + 실패 조건)을 한 줄이라도 추가해 주세요.
```

### CBRD-25779 (feature) — abstract AC
```
[gate-resolved] 수용 기준이 추상적이라 검증 케이스를 만들 수 없어 보류합니다.
- 내용: AC "pgbuf_unfix/set_dirty 동작 중 문제가 발생하지 않아야"는 어떤 입력·상태에서 무엇을 확인하는지가 없습니다. 리팩터링 회귀를 드러낼 구체 시나리오(예: 특정 쿼리/temp 사용 경로)를 제시해 주세요.
- 필드: Fixed version 미기입, QA Scenario=Not Yet.
@youngjinj 위 시나리오를 보강해 주시면 다시 검토하겠습니다.
```
→ **Abstract AC** such as "must not cause problems", "must not degrade performance", or "verify with various scenarios" is the main reason a feature issue is NOT-READY.

## sub-task guard — a sibling owns the testing (not a return)

### CBRD-26255 (sub-task, Connection Pool redesign) — return cancelled
Under the parent **CBRD-26177 [EPIC]** (concurrency/performance, connection·worker), the sibling sub-tasks **26421 (adds the verification cases)** and 26523 (HA testcases) own the testing for this EPIC. Returning the implementation sub-task 26255 on its own would just have the developer push it back to Resolved — a **ping-pong** → **don't return it, skip it** (26421 covers the testing). → **Before deciding to return, check the parent and sibling sub-tasks** (if a sibling owns the TC/verification, do not return the implementation sub-task).

### CBRD-26701 (sub-task, worker pool change) — skip (refactoring parent)
Under the parent **CBRD-26653 [리팩토링] Thread manager refactoring**, all 7 sub-tasks are internal refactoring and there is no sub-task responsible for verification. Refactoring is behavior-preserving → passing the existing regression is enough (no new TC needed) → 26701 and the rest are all Not Required. Contrast with 26177 (performance, which *does* have verification sub-task 26421) — **the parent's issuetype plus whether a verification sub-task exists is what decides the verdict** (a performance/feature parent = a sibling covers verification; a refactoring parent = all Not Required).

