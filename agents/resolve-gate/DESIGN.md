# resolve-gate — 설계 v1 + PoC 검증 (cubrid-agent)

**상태: 설계 v1 + PoC 검증 + Stage 2 게이트 스킬 구현 (2026-07-16).**

Handover→Resolved("Accept the fix") 전이 앞의 **평가형 게이트**. **실행 주체는 개발자** — 자기 fix를 Resolved로 올리기 전 **QA-readiness(테스트 플랜 작성 가능성)** 를 스스로 점검하는 self-check다. accept/보완을 판정한다. 용어·초점은 [CONTEXT.md](./CONTEXT.md).

## 범위 (PoC)

- **한다**: Handover 이슈의 description·comment·첨부를 읽고 "이 내용으로 QA가 테스트 플랜을 짤 수 있는가"를 판정 → 읽기전용 게이트 리포트.
- **안 한다**: Jira 전이·코멘트 쓰기(사람이), fix 실행 검증(repro 재실행), 로컬 CTP, TC 작성.

## 확정 결정 (2026-07 grilling)

- **D1 초점 = test-plannability**: 이슈 내용만으로 테스트 플랜을 작성 가능한지가 중점. **fix가 실제로 동작하는지(실행검증)는 범위 밖**(추후 옵션).
- **D2 출력 = 읽기전용 게이트 리포트/권고**: accept/보완 + 사유. resolve-gate는 **판정만** 하고 Jira 전이는 하지 않음. **check-in-fix(Handover→Resolved 전이) 주체는 미확정**(개발자/QA — 2026-07-17 결정 예정) — 게이트를 **돌리는** self-check 실행 주체가 개발자인 것과는 별개다. (S4: Jira 쓰기=Stage 3)
- **D3 검사 2계층**: **차단**=test-plannability(C0~C2), **경고**=핸드오버 hygiene(C3/C5/C6). (근거: dry-run에서 실제 Handover 3건 모두 Fixed version·QA Scenario 미기입 — 이를 차단하면 전부 탈락하므로 경고로.)
- **D4 로컬 CTP 불요**: fix를 실행하지 않으므로 tc-author보다 가벼운 read-only 에이전트.

## 검사 기준

이슈 성격에 따라 차단 기준을 **이원 적용**한다(PoC 발견 — 개선점 1). 파이프라인 첫 단계에서 issuetype으로 분기: **Correct Error=버그**, 그 외(Improve Function·Sub-task·Development Subject·Internal Management 등)=**기능**. 버그 기준을 기능 이슈에 적용하면 pool의 85%(PoC 23/27)를 오판한다.

**차단(pass/fail 핵심) — test-plannability**

_버그 이슈_
- **C1 Repro 존재·자기완결**: 재현 절차/스크립트가 있고, 빠진 스키마·데이터·오타 없이 그대로 실행 가능. **regression·core 리포팅 예외**: core나 regression fail을 유발한 TC가 이슈에 **첨부**돼 있으면 그 TC가 곧 repro이므로 별도 reproduction step이 없어도 C1 충족. 이런 이슈는 재현 정보·첨부 TC가 **comment에 있는 경우가 많아 description뿐 아니라 comment·첨부까지 확인**한다.
- **C2 Expected/Actual 명시**: fix 후 기대 동작 + fix 전 버그 동작. (regression/core는 "그 TC가 fail/core → fix 후 pass"가 곧 Expected/Actual.)

_기능 이슈_ (버그 repro 개념이 없어 재해석)
- **C1′ Spec 구체성**: Specification Changes가 입출력·오류조건·예시로 구체적인가.
- **C2′ AC 검증가능성**: Acceptance Criteria가 QA가 케이스를 도출할 만큼 관측 가능·구체적인가.

- **C0 종합**(성격 무관): description만으로 QA가 테스트 플랜을 짤 수 있는가(dev-process p17 취지). **추상 AC 감지를 명시 항목으로** 포함 — "문제 발생 안 함"·"성능 저하 없어야"·"다양한 시나리오로 확인" 같은 추상 AC는 기능 이슈 NOT-READY의 주사유(개선점 3).

**경고(리포트에 표시) — 핸드오버 hygiene(p18)**
- **C3 Fixed version**(Planned 대비 머지 version) · **C5 QA Scenario**(Required/Not Required+사유) · **C6 Need Manual**(필요 시 CUBRIDMAN 링크) · **C4 변경 스펙/설정 반영**.
- _C3 노이즈 완화_(개선점 5): Handover 시점엔 머지 version이 원래 미확정이라 거의 전건 미기입(PoC 25/27) → 경고가 무의미해진다. Handover 단계에선 C3 경고를 낮은 우선순위로 두고 다음 단계(Resolved 이후)에서 본다.

## 파이프라인

1. **Select** — 실행 주체가 개발자이므로 주 용법은 **자기 이슈 지정**(Resolved로 올리려는 `CBRD-XXXXX`). pool 전체 조회(`planned=guava & status=Handover` 배치 read: `--fields summary,issuetype,description,comment,attachment,fixVersions,customfield_210565,assignee --output json`)는 QA·관리자용 부차 용법. **issuetype으로 버그/기능 분기**(검사 기준 이원 적용). **QA Scenario=Not Required**는 TC 미대상이라 판정하되 "TC 미대상" 태그만 달고 차단하지 않는다(개선점 4, PoC: Not Required 6건).
2. **검사** — 각 이슈의 description·comment·**첨부(첨부 TC)**·fields를 읽어 C0~C6 판정. **regression/core 이슈는 첨부된 실패 TC를 repro로 인정**(C1 예외). merge diff(cubrid repo)는 스펙 변경 이해·대조에 참고.
3. **Gate report + 반려 코멘트** — 이슈별 `READY`(accept 권고) / `NOT-READY`. **READY에는 적합 러너 태그(SQL/shell/CCI/perftool)를 함께 단다**(개선점 2) — READY라도 CCI/JDBC·성능·statdump·내부저장 관측은 SQL TC 부적합이므로, 다운스트림(tc-author=SQL 전용)이 헛집기 않게 미리 라우팅한다. NOT-READY 시 **반려 Jira 코멘트**를 산출:
   - ⓐ "Resolved로 상태변경 불가" 명시
   - ⓑ **내용 gap** — repro 자기완결·expected/actual 등(C0~C2)
   - ⓒ **필드 gap** — Fixed version·QA Scenario·Need Manual 중 미기입(C3~C6)
   - ⓓ **보완 항목** — 개발자 본인이 Resolved로 올리기 전 고칠 gap. 실행 주체가 개발자라 외부 @멘션 호출이 아닌 **self 보완 체크리스트**다(다른 개발자 이슈를 점검하는 경우에만 @멘션).
   게시 주체: **개발자 본인** — self-check 결과를 보고 이슈를 보완한다. (보완 후 **Resolved 전이=check-in-fix 주체는 미확정**, 2026-07-17 결정 예정.) Jira 코멘트 게시는 재량(QA 소통·기록용). 자동 게시·전이는 Stage 3.

## 재료

- **cubrid-jira**: 이슈 description·comment·필드(Fixed version/QA Scenario 등). 단일진실원천.
- **cubrid repo**: fix merge diff/PR(스펙 변경 이해, description 대조용 참고).
- **gh**: PR 머지 여부 확인(선택).
- 로컬 CTP·CUBRID **불요**.

## dry-run 근거 (2026-07, 실제 Handover 3건)

| 이슈 | C0~C2 | 판정 |
|---|---|---|
| CBRD-27056 (CAS numeric) | 자기완결 SELECT repro + Expected/Actual 명시 | **READY** (+ Fixed ver·QA Scenario 미기입 경고) |
| CBRD-27052 (core 회귀) | **repro 없음**(스택트레이스만) | **NOT-READY** — 반려: 재현 절차 부재 |
| CBRD-26909 (loaddb) | repro 있으나 **오타로 미실행** | **NOT-READY** — 반려: repro 자기완결 X |

→ 기준이 실제 판정을 정확히 냄. tc-author가 그 재료로 TC를 못 짜는 케이스를 미리 거른다.

## PoC 전수 검증 (2026-07-16, guava Handover 27건)

dry-run 3건을 넘어 pool 전체 27건에 기준을 적용. 상세·반려 초안·판정표는 [reports/poc-guava-handover.md](./reports/poc-guava-handover.md)(gitignore).

- **READY 19 / NOT-READY 8** (READY 중 경계 10 = "test-plannable하나 SQL 밖 관측" 또는 "AC 얇음").
- 이슈 성격: **버그 4 · 기능 23** → dry-run이 전부 버그라 놓쳤던 편향을 발견(개선점 1: 이원화).
- **버그 4건**: 원안 C1/C2로 2 READY(25531·26859) / 2 NOT-READY(27052·26909) 정확 판정.
- **기능 23건**: C1′/C2′(AC 검증가능성)로만 판정 가능(원안 C1/C2면 전건 오판) → 17 READY / 6 NOT-READY.
- **NOT-READY 8건 사유**: repro/AC 부재·추상 5(27052·27028·25779·25632·26125), repro 오타 1(26909 — 자동 reject 아닌 개발자 확인형 반려로 오탐 회피, 개선점 6), 내부계약·관측불가 2(27006·27029).
- 6개 설계 개선점을 위 검사 기준·파이프라인에 반영(1 이원화·2 러너태그·3 추상AC·4 Not Required·5 C3완화·6 확인형 반려).

## tc-author와의 관계

resolve-gate의 `READY` = tc-author Select의 입력 품질 보장. tc-author의 Ground(이슈→TC 재료 추출)가 성공할 조건을 resolve-gate가 앞단에서 판정한다. 두 에이전트의 조인 키는 이슈 키(`CBRD-XXXXX`).

## 열린 질문 결정 (2026-07)

- **Select 필터** → **`planned=guava & status=Handover` 전체**(카테고리 무관 — readiness 검사는 SQL 제한 불필요). QA Assignee는 이 시점 미설정이라 쓰지 않음.
- **hygiene(C3/C5/C6)** → **경고 유지**(차단 안 함). 실제 Handover가 대개 미기입이라 차단하면 전부 탈락.
- **반려 산출물** → NOT-READY 시 **개발자 본인 보완 체크리스트**(Resolved 불가 사유 + 내용/필드 gap) 산출. 실행 주체가 개발자라 self-check — 개발자가 보고 보완 후 Resolved로 올린다. Jira 게시는 재량, 자동화는 Stage 3.
- **fix 실행검증** → **범위 밖 유지**(후속 옵션). repro 재실행(fixed 빌드)은 tc-author 로컬검증 인프라를 재사용해 CBRD-27052처럼 "fix가 실제론 미해결"인 케이스를 잡는 향후 확장.
- **check-in-fix 전이 주체** → **미확정**(2026-07-17 결정 예정). resolve-gate를 돌리는 self-check 실행은 개발자로 확정됐으나, 게이트 통과 후 Handover→Resolved 전이(check-in-fix)를 누가 하는지(개발자/QA)는 아직 정해지지 않음. resolve-gate는 읽기전용이라 전이 자체는 범위 밖(판정만) — 주체가 정해지면 D2·SKILL에 반영.

## 남은 리스크

- **판정 주관성**: test-plannability는 정성 판단 → fresh-context 리뷰/근거 패킷으로 보강(tc-author Review 방식 차용).
- **hygiene 승격 시점**: 조직이 p18 필드를 Handover에서 실제로 강제하면 경고→차단 재검토.

## 구현 (Stage 2 게이트 스킬)

오케스트레이션을 [`.claude/skills/resolve-gate/`](../../.claude/skills/resolve-gate/)로 스킬화(팀 git 공유, Stage 2). 이 에이전트의 첫 구현 산출물.
- **SKILL.md**: Select(cubrid-jira 배치 read) → 성격 분류(버그/기능) → C0~C6 판정 → gate report + 반려 초안. 검사 기준·이원화·러너 태그·반려 템플릿·오탐 회피(확인형 반려)를 실행 지침으로 임베드.
- **examples/verdicts.md**: 27건 PoC 판정 few-shot(READY+러너 태그, NOT-READY 반려 초안 4종).
- 읽기전용이라 hook 하드게이트 불요, 셋업은 cubrid-jira 인증뿐(로컬 CTP·빌드 없음) → tc-author보다 가벼운 Stage 2.
- **검증**: JQL 배치 read가 실 pool에 동작(27건) 확인. 판정 로직은 PoC(fork)에서 검증됨.
- **남은 것**: 팀 셋업 문서(cubrid-jira 인증 가이드), 자동 게시·전이(Stage 3).

## PoC 이후로 미룬 것

Jira 자동 전이·코멘트(Stage 3), fix 실행검증, 하드 게이트 hook(Stage 2 resolve-next류 오케스트레이션), 무인 스케줄.
