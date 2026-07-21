# resolve-gate — 설계 (Resolved QA-readiness 게이트)

**Resolved(=QA to-do) 이슈를 QA가 검토해, 테스트로 삼기 부적합한 것을 `Need Something`(→Handover)로 되돌려보내는 QA-side 진입 게이트.** 통과분은 tc-author 단계로 이어진다. 용어·초점은 [CONTEXT.md](./CONTEXT.md), 구현체는 [`.claude/skills/resolve-gate/`](../../../.claude/skills/resolve-gate/).

근거: resolve 처리 = 그 이슈가 QA 팀의 to-do가 됐다는 뜻. resolve-gate는 이 QA 큐를 검토해, QA가 테스트 플랜을 못 짤 이슈를 개발자에게 되돌린다.

## 확정 결정

- **D1 대상 = Resolved(QA to-do)**.
- **D2 주체 = QA 팀/담당자**.
- **D3 판정 2축**: ① 필요성(QA Scenario 재판정 — 개발자 Not Required도 QA가 뒤집음) ② 작성가능성(test-plannability).
- **D4 되돌림 = `Need Something` 전이**(Resolved→Handover, 실측). QA Not Satisfied(→Confirmed, fix 부적절)·Ask Reconfirmation(→Open, 이슈 재확인)과 구분.
- **D5 tc-author 경계 = 앞단 필터**. resolve-gate가 부적격 반송 → 남은 것을 tc-author가 자체 Select(SQL 재현성 등)로 다시 거름. 중복 아님.
- **D6 단계별 동작**: Select 범위·필드 변경·전이 실행·통과분 처리가 단계(PoC/팀내/자동화)마다 다름(아래 매트릭스).
- **Check-in Fix(Handover→Resolved)는 범위 밖** — 개발자가 머지 후 직접 전이한다. 매뉴얼은 우선 Resolved 후 추후 작성하기도 하므로 미완성이 Resolved를 막지 않는다.

## 판정 2축

**① 필요성 — QA Scenario 재판정 (양방향)**
QA Scenario 필드는 최초 개발자가 작성하고, QA가 Resolved에서 재검토해 바꾸기도 한다. resolve-gate(QA 주체)는 이를 무조건 신뢰하지 않고 필요성을 **양방향으로 재판정**한다.
- **승격 (Not Required/Not Yet → 필요)**: crash·core·data-integrity·회귀 위험이면 개발자가 불필요로 뒀어도 필요로 올린다.
- **하향 (Required → 불필요)**: 테스트 표면이 없으면 필요에서 내린다(예: 26701 — AC가 "빌드 성공"뿐).
- **선행 — resolution 상태 체크**: Won't-do/Duplicate/Deferred는 QA Scenario·severity와 무관하게 테스트 대상이 아니다 → 필요성 판정 **이전에** 스킵(severity만 보면 오승격 위험).
- **필요성 스킵 카테고리**(QA Scenario로 걸러지지 않음): EPIC·build-only AC·internal 미GA 기능.
- **이슈 타입별 필요성 prior**: 이슈 성격이 사전확률을 준다 —
  - **신규 기능**(Improve Function 등): Required 높음 — 새 기능은 새 검증이 필요.
  - **refactoring**: Required 낮음 — 개발자 테스트 또는 기존 regression 통과로 충분(신규 시나리오 불필요).
  - **regression·core fail — 발견 경로가 가른다**: *regression 스위트가 원인*(회귀 테스트가 잡은 실패)이면 **Not Required**(기존 TC가 이미 커버); *회귀 스위트 밖 신규 버그 리포팅*이면 **Required 높음**(신규 TC 추가).
  → crash/core라고 무조건 승격이 아니라, comment·첨부로 "누가·어떻게 발견했나"를 확인한다. **또한 fix가 동작 변화 없는 debug-only assert 추가·내부 리팩터링이면 SQL TC 대상이 아니다** — release 동작이 불변이라 사용자 관측 변화가 없고, debug 빌드 회귀가 assert를 커버한다(예: 26888 — fix가 debug assert 조건 추가뿐 → Not Required).

**② 작성 가능성 — test-plannability** ([DP2](../../design-principles.md) 블랙박스)
필요하다고 본 이슈가 내용으로 **사용자 관점 블랙박스** 테스트 플랜을 짤 수 있는가 — 내부 assert·코드 경로가 아니라 입력→관측 동작(결과·에러·메시지)으로. 이슈 성격 이원화(버그 C1/C2 · 기능 C1′/C2′) + C0 종합(추상 AC 감지) + regression/core 첨부TC 예외 + hygiene 경고. 상세는 아래 '검사 기준'.

## 판정 → 전이

- **필요 + 작성가능** → 통과. `Start Test`(→Test)로 tc-author 단계 진행. (필요성 재판정으로 QA Scenario를 Required로 바꿔야 하면 D6 단계에 따라 변경/제안.)
- **필요 + 작성불가** → **반송 전 sub-task 가드** 후 `Need Something`(→Handover) 반송. **이슈가 sub-task면 부모+형제 sub-task를 먼저 확인** — 형제 중 TC/시나리오 작성을 담당하는 sub-task가 있으면 그 형제가 테스트를 커버하므로 **반송하지 않는다**(스킵/통과 처리). **부모 issuetype도 본다**: refactoring 부모는 동작 무변이라 검증 sub-task가 없는 게 정상이고 구성 sub-task는 전부 Not Required(예: 26653 그룹); 성능/기능 부모는 검증 sub-task가 구현 sub-task를 커버(예: EPIC 26177의 검증 sub-task 26421이 구현 26255를 커버). 개별 sub-task만 보고 반송하면 개발자가 다시 Resolved로 올려 **status 왕복(핑퐁)**이 생긴다. 형제에 TC 담당이 없고 작성도 불가일 때만 반송하며, 부족분(repro 자기완결·Expected/Actual·추상 AC 등)을 코멘트로.
- **불필요(QA도 동의)** → 테스트 대상 아님. 스킵(QA Scenario 확정).

## 전이 지도 (실측 — Resolved 이슈 available transitions)

| 전이 | → target | resolve-gate 용도 |
|---|---|---|
| **Need Something** | **Handover** | **되돌림**(테스트 플랜 부족분 보완 요청) |
| Start Test | Test | 통과분 진행(tc-author 단계) |
| Assign QA | Resolved | QA 배정(제자리) |
| QA Not Satisfied | Confirmed | (범위 밖) fix 자체가 부적절 → 재분석 |
| Ask Reconfirmation | Open | (범위 밖) 이슈 재확인 |
| Close / Need Backport | Closed / Backport | (범위 밖) 뒷단 |

되돌림 실행: `cubrid-jira transition <KEY> --to "Need Something" --yes` (쓰기라 --yes 필수).

## 단계별 매트릭스 ([staging.md](../../staging.md) 정합)

| | Select 범위 | QA Scenario 필드 변경 | 전이 실행 | 통과분 |
|---|---|---|---|---|
| **PoC (Stage 1)** | QA assignee=twkang | 제안만 | 수동(초안) | 반송만(통과분은 그대로) |
| **팀내 배포 (Stage 2)** | guava Resolved 전체 | 제안만(수동) | 수동 | 반송(통과분 그대로) |
| **자동화 (Stage 3)** | guava Resolved 전체 | 직접 변경(cubrid-jira update) | 자동 전이 | tc-author 트리거(Start Test) |

## 검사 기준 (작성가능성 축)

이슈 성격에 따라 차단 기준을 **이원 적용**한다. issuetype으로 분기: **Correct Error=버그**, 그 외(Improve Function·Sub-task·Development Subject·Internal Management 등)=**기능**.

**차단(pass/fail 핵심) — test-plannability**

_버그 이슈_
- **C1 Repro 존재·자기완결**: 재현 절차/스크립트가 있고, 빠진 스키마·데이터·오타 없이 그대로 실행 가능. **regression·core 리포팅 예외**: core나 regression fail을 유발한 TC가 이슈에 **첨부**돼 있으면 그 TC가 곧 repro이므로 별도 reproduction step이 없어도 C1 충족. **판정선 = "실행 가능한 repro TC"의 유무** — analysis 문서·스택트레이스만으론 불충족(예: 26888·24838 자기완결 repro 첨부→통과 / 26965 실행 TC 없는 타이밍 레이스→반송). 재현 정보·첨부 TC가 **comment에 있는 경우가 많아 comment·첨부까지 확인**한다.
- **C2 Expected/Actual 명시**: fix 후 기대 동작 + fix 전 버그 동작. (regression/core는 "그 TC가 fail → fix 후 pass"가 곧 Expected/Actual.)
- **확률적·타이밍 repro**: 재현이 확률적이어도 **양성 단언이 검증 가능하면 통과**(fix 후 항상 성공함을 단언), **음성 단언 + 비결정이면 반송**(레이스 crash 재현이 불확정 → 결정적 재현 수단 요청). 예: 26799(병렬 row 유실이지만 양성 검증)=통과 / 26965(타이밍 crash)=반송.

_기능 이슈_ (버그 repro 개념이 없어 재해석)
- **C1′ Spec 구체성**: Specification Changes가 입출력·오류조건·예시로 구체적인가.
- **C2′ AC 검증가능성**: Acceptance Criteria가 QA가 케이스를 도출할 만큼 관측 가능·구체적인가.

- **C0 종합**(성격 무관): description만으로 QA가 테스트 플랜을 짤 수 있는가. **추상 AC 감지를 명시 항목으로** — "문제 발생 안 함"·"성능 저하 없어야"·"다양한 시나리오로 확인" 같은 추상 AC는 기능 이슈 반송의 주사유.

**경고(리포트에 표시) — 핸드오버 hygiene**
- **C3 Fixed version · C5 QA Scenario · C6 Need Manual · C4 변경 스펙/설정 반영**. C3는 노이즈가 커(대개 미기입) 낮은 우선순위. **C6 매뉴얼**: 매뉴얼 미완성은 Need Something 반송 사유가 아니다(경고만).

## 파이프라인

```
Select ─► 필요성 판정 ─► 작성가능성 판정 ─► 전이 + 리포트
```

1. **Select** — 단계별 범위(위 매트릭스). cubrid-jira 배치 read: `--fields summary,issuetype,description,comment,attachment,fixVersions,customfield_210565,assignee,parent,subtasks --output json`. **sub-task면 부모·형제 관계도 확보**(반송 가드용).
2. **필요성 판정** — QA Scenario를 QA 관점에서 재검토(개발자 초안 무관). 불필요(QA 동의)면 스킵.
3. **작성가능성 판정** — C0~C6(성격 이원화, regression/core 예외). merge diff(cubrid repo)는 스펙 변경 대조 참고.
4. **전이 + 리포트** — 필요+가능→Start Test(단계별 실행), 필요+불가→Need Something 반송(부족분 코멘트 초안), 불필요→스킵. 리포트는 `~/.cubrid-agent/reports/resolve-gate/`.

## tc-author와의 관계

**앞단 필터.** resolve-gate 통과분(필요+가능)이 tc-author 입력. resolve-gate가 부적격을 먼저 Need Something으로 반송해 tc-author 큐 품질을 올린다. tc-author는 자체 Select(SQL 재현성 등)로 다시 거른다(중복 아님, 각자 다른 기준). 조인 키는 이슈 키(`CBRD-XXXXX`).

## 남은 것 / 미룬 것

- **자동화(Stage 3)**: QA Scenario 필드 직접 변경·자동 전이·tc-author 트리거.
