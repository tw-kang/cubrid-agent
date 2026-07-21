# resolve-gate verdict examples

Few-shot for the skill: how each issue kind maps to a verdict, runner tag, and remediation draft.

> **실행 주체 = QA, 대상 = Resolved(QA to-do).** 아래 "NOT-READY"는 QA가 `Need Something`(→Handover)로 되돌리는 **반송**이며, 초안은 개발자에게 보낼 부족분 코멘트다(개발자 assignee @멘션). "READY"는 통과 → `Start Test`(→Test, tc-author).
> **regression/core 예외:** core나 regression fail을 유발한 TC가 이슈에 첨부돼 있으면 그 TC가 repro이므로 별도 repro step 없이 통과. description뿐 아니라 comment·첨부까지 확인한다(CBRD-27052 참조).

## READY (accept-recommended + runner tag)

### CBRD-25531 (bug) — READY · runner: SQL
완전한 SQL repro(drop/create/insert/set opt/query1~6) + Expected/Actual(query plan). SQL TC 최적.

### CBRD-26859 (bug) — READY (경계) · runner: CCI
C1 자기완결(synonym + CCI 스키마 조회) + C2 명확(owner 포함/누락). 단 SQL로 관측 불가 → CCI/JDBC 러너로 라우팅.

### CBRD-26612 (feature) — READY · runner: SQL
AC 매우 구체 — SQL 예시 다수, NULL/비DBA/미존재 처리 명시. 기능 이슈지만 C1′(Spec 구체성)·C2′(AC 검증가능성) 충족.

### CBRD-26663 (feature) — READY (경계) · runner: perftool
AC 절반이 성능(CPU%)이라 SQL TC 부적합 → perftool. 단 "결과 동일·회귀"는 검증 가능하므로 READY.

## NOT-READY (reject-recommended + rejection draft)

### CBRD-27052 (bug) — repro 없음
```
[resolve-gate] 현재 내용으로는 QA가 재현·검증 절차를 짤 수 없어 Resolved로 받기 어렵습니다.
- 내용: core 파일과 스택트레이스만 있고, 재현 절차(어떤 부하/종료 순서에서 lock_uninit_resource assert가 나는지)가 없습니다. QA가 이 crash를 유발할 시나리오를 만들 수 없습니다.
- 필드: Fixed version 미기입.
@byungwook.kim 재현 절차(또는 최소 유발 조건)를 description에 보강해 주시면 다시 검토하겠습니다.
```
→ **regression/core 예외**: 이런 이슈는 comment·첨부를 반드시 확인한다 — core 유발 TC가 첨부돼 있었다면 그 TC=repro로 READY가 된다. 27052는 스택트레이스만 있고 첨부 실패 TC가 없어 NOT-READY.

### CBRD-26909 (bug) — repro 오타 (확인형 반려, 오탐 회피)
```
[resolve-gate] Expected/Actual은 명확하나 재현 스키마가 그대로 실행되지 않아 현 상태로는 받기 어렵습니다.
- 내용: cubann-12.schema에서 [tbl2]를 만들지 않고 [tb2]를 ALTER(오타), [pk_tbl_id']에 불필요한 따옴표가 있어 로드가 중단됩니다. 이 이슈가 "line 정보 부정확"을 다루므로 오타가 의도된 테스트 입력인지 확인이 필요합니다.
- 필드: Fixed version 미기입.
@ctshim 의도된 오타라면 그 취지를, 실수라면 정정본을 알려주시면 바로 진행하겠습니다.
```
→ 오타를 자동 reject하지 않고 "의도된 입력인지 확인"으로 되묻는 게 핵심(line-부정확 버그에선 오타가 테스트 포인트일 수 있음).

### CBRD-27028 (feature) — AC 섹션 부재
```
[resolve-gate] 현 description으로는 검증 시나리오를 도출하기 어려워 Resolved 보류합니다.
- 내용: Acceptance Criteria가 없고 code reference(assert 위치)만 있어, QA가 어떤 입력에서 무엇이 정상/실패인지 판단할 기준이 없습니다.
- 필드: Fixed version 미기입, QA Scenario=Not Required.
@vimkim 관측 가능한 수용 기준(정상 동작 조건 + 실패 조건)을 한 줄이라도 추가해 주세요.
```

### CBRD-25779 (feature) — 추상 AC
```
[resolve-gate] 수용 기준이 추상적이라 검증 케이스를 만들 수 없어 보류합니다.
- 내용: AC "pgbuf_unfix/set_dirty 동작 중 문제가 발생하지 않아야"는 어떤 입력·상태에서 무엇을 확인하는지가 없습니다. 리팩터링 회귀를 드러낼 구체 시나리오(예: 특정 쿼리/temp 사용 경로)를 제시해 주세요.
- 필드: Fixed version 미기입, QA Scenario=Not Yet.
@youngjinj 위 시나리오를 보강해 주시면 다시 검토하겠습니다.
```
→ "문제 발생 안 함"·"성능 저하 없어야"·"다양한 시나리오로 확인" 같은 **추상 AC**가 기능 이슈 NOT-READY의 주 사유.

## sub-task 가드 — 형제가 테스트 담당 (반송 아님)

### CBRD-26255 (sub-task, Connection Pool 재설계) — 반송 취소
부모 **CBRD-26177 [EPIC]**(동시성/성능, connection·worker) 아래 형제 sub-task **26421(검증 케이스들 추가)**·26523(HA 테스트케이스)이 이 EPIC의 테스트를 담당한다. 구현 sub-task 26255를 개별 반송하면 개발자가 다시 Resolved로 올려 **핑퐁** → **반송하지 않고 스킵**(테스트는 26421이 커버). → **반송 결정 전 부모+형제 sub-task를 확인하라**(TC/검증 담당 형제가 있으면 구현 sub-task는 반송 X).

### CBRD-26701 (sub-task, worker pool 변경) — 스킵(refactoring 부모)
부모 **CBRD-26653 [리팩토링] Thread manager refactoring**의 7 sub-task는 전부 내부 리팩토링이고 검증 담당 sub-task가 없다. refactoring은 동작 무변 → 기존 regression 통과로 충분(신규 TC 불필요) → 26701 등 전부 Not Required. 26177(성능, 검증 sub-task 26421 有)과 대조 — **부모 issuetype + 검증 sub-task 유무가 판정을 가른다**(성능/기능 부모=검증 형제가 커버, refactoring 부모=전부 Not Required).

