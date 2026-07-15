# resolve-gate verdict examples (27-issue PoC, 2026-07-16)

Few-shot for the skill: how each issue kind maps to a verdict, runner tag, and rejection draft. Full source: `agents/resolve-gate/reports/poc-guava-handover.md`.

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
