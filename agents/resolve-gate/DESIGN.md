# resolve-gate — 설계 v1 (cubrid-agent)

Handover→Resolved("Accept the fix") 전이를 맡는 **평가형 게이트**. 개발자가 인계한 fix를 QA가 받기 전, **QA-readiness(테스트 플랜 작성 가능성)** 를 심사해 accept/reject를 권고한다. 용어·초점은 [CONTEXT.md](./CONTEXT.md).

## 범위 (PoC)

- **한다**: Handover 이슈를 읽고 "이 내용(특히 description)으로 QA가 테스트 플랜을 짤 수 있는가"를 판정 → 읽기전용 게이트 리포트.
- **안 한다**: Jira 전이·코멘트 쓰기(사람이), fix 실행 검증(repro 재실행), 로컬 CTP, TC 작성.

## 확정 결정 (2026-07 grilling)

- **D1 초점 = test-plannability**: 이슈 내용만으로 테스트 플랜을 작성 가능한지가 중점. **fix가 실제로 동작하는지(실행검증)는 범위 밖**(추후 옵션).
- **D2 출력 = 읽기전용 게이트 리포트/권고**: accept/reject + 사유. Jira 전이는 사람이 수행(S4: Jira 쓰기=Stage 3).
- **D3 검사 2계층**: **차단**=test-plannability(C0~C2), **경고**=핸드오버 hygiene(C3/C5/C6). (근거: dry-run에서 실제 Handover 3건 모두 Fixed version·QA Scenario 미기입 — 이를 차단하면 전부 탈락하므로 경고로.)
- **D4 로컬 CTP 불요**: fix를 실행하지 않으므로 tc-author보다 가벼운 read-only 에이전트.

## 검사 기준

**차단(pass/fail 핵심) — test-plannability**
- **C1 Repro 존재·자기완결**: 재현 절차/스크립트가 있고, 빠진 스키마·데이터·오타 없이 그대로 실행 가능.
- **C2 Expected/Actual 명시**: fix 후 기대 동작 + fix 전 버그 동작.
- **C0 종합**: description만으로 QA가 테스트 플랜을 짤 수 있는가(dev-process p17 취지).

**경고(리포트에 표시) — 핸드오버 hygiene(p18)**
- **C3 Fixed version**(Planned 대비 머지 version) · **C5 QA Scenario**(Required/Not Required+사유) · **C6 Need Manual**(필요 시 CUBRIDMAN 링크) · **C4 변경 스펙/설정 반영**.

## 파이프라인

1. **Select** — `planned=guava & status=Handover` 풀 조회(cubrid-jira jql). QA Assignee 미설정이라 쓰지 않고, 카테고리 무관(readiness는 SQL 제한 불필요).
2. **검사** — 각 이슈의 description·comment·fields를 읽어 C0~C6 판정. merge diff(cubrid repo)는 스펙 변경 이해·description 대조에 참고.
3. **Gate report + 반려 코멘트** — 이슈별 `READY`(accept 권고) / `NOT-READY`. NOT-READY 시 **반려 Jira 코멘트**를 산출:
   - ⓐ "Resolved로 상태변경 불가" 명시
   - ⓑ **내용 gap** — repro 자기완결·expected/actual 등(C0~C2)
   - ⓒ **필드 gap** — Fixed version·QA Scenario·Need Manual 중 미기입(C3~C6)
   - ⓓ **assignee(개발자) @멘션** — 확인·보완 요청
   게시 주체: **PoC=사람이 검토·게시(봇은 @멘션 포함 완성 초안까지), 이후=봇 자동게시**(오탐으로 실제 개발자를 잘못 호출하는 리스크를 PoC에서 차단하는 단계적 접근).

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

## tc-author와의 관계

resolve-gate의 `READY` = tc-author Select의 입력 품질 보장. tc-author의 Ground(이슈→TC 재료 추출)가 성공할 조건을 resolve-gate가 앞단에서 판정한다. 두 에이전트의 조인 키는 이슈 키(`CBRD-XXXXX`).

## 열린 질문 결정 (2026-07)

- **Select 필터** → **`planned=guava & status=Handover` 전체**(카테고리 무관 — readiness 검사는 SQL 제한 불필요). QA Assignee는 이 시점 미설정이라 쓰지 않음.
- **hygiene(C3/C5/C6)** → **경고 유지**(차단 안 함). 실제 Handover가 대개 미기입이라 차단하면 전부 탈락.
- **반려 산출물** → NOT-READY 시 반려 Jira 코멘트(Resolved 불가 + 내용/필드 gap + **개발자 @멘션**) 산출. **게시 주체: PoC=사람이 게시(봇은 완성 초안), 이후=봇 자동게시**(단계적 — PoC는 오탐으로 실제 개발자 오호출 방지).
- **fix 실행검증** → **범위 밖 유지**(후속 옵션). repro 재실행(fixed 빌드)은 tc-author 로컬검증 인프라를 재사용해 CBRD-27052처럼 "fix가 실제론 미해결"인 케이스를 잡는 향후 확장.

## 남은 리스크

- **판정 주관성**: test-plannability는 정성 판단 → fresh-context 리뷰/근거 패킷으로 보강(tc-author Review 방식 차용).
- **hygiene 승격 시점**: 조직이 p18 필드를 Handover에서 실제로 강제하면 경고→차단 재검토.

## PoC 이후로 미룬 것

Jira 자동 전이·코멘트(Stage 3), fix 실행검증, 하드 게이트 hook(Stage 2 resolve-next류 오케스트레이션), 무인 스케줄.
