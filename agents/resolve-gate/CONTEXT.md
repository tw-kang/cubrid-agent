# resolve-gate (Handover → Resolved)

**상태: 설계 v1 + guava Handover pool 27건 전수 PoC 검증 (2026-07-16). 구현 전.**

역할: 개발자가 Handover한 fix를, QA가 Resolved로 받기("Accept the fix") 전에 심사하는 **평가형 게이트** 에이전트. tc-author(생성형)와 달리 산출물을 만들지 않고 **판정(권고)** 을 낸다.

## 초점 — QA-readiness(테스트 플랜 작성 가능성)

fix를 실행해 검증하는 게 아니라, **"이 Handover 이슈가, 첨부 내용으로 QA가 repro 재현 및 테스트 작성이 가능할 만큼 준비됐는가"** — 특히 **description(필수)** 이 그 재료로 충분한가 — 를 심사한다. 부족하면 accept 대신 "무엇이 빠졌는지" **반려 권고**. 사실상 **tc-author의 Ground가 성공할 재료가 있는지를 미리 거르는 관문**이다.

## 용어

- **Handover**: Jira 상태. 개발자가 fix를 머지·인계한 직후, QA가 받기 전.
- **Accept the fix**: Handover→Resolved 전이(=Check-in Fix). 반대편은 반려(ask recommendation / Resolve without fix = Bug Invalid). **dev→QA 핸드오프 지점**이라 이 시점 QA는 미배정(assignee=개발자, QA 배정은 다음 "Assign QA/Start Test") → resolve-gate 반려 @멘션 대상 = **개발자(현 assignee)**.
- **test-plannability(테스트 플랜 작성 가능성)**: 이슈 내용(특히 description)만으로 QA가 테스트 플랜/케이스를 짤 수 있는가. 게이트의 **차단 기준**. **이슈 성격별 이원 판정**(PoC 발견): 버그 이슈는 repro 자기완결+Expected/Actual로, 기능 이슈는 Spec 구체성+AC 검증가능성으로. 버그 기준을 기능 이슈에 적용하면 대다수 오판(PoC 23/27).
- **핸드오버 hygiene**: Fixed version·Need Manual·QA Scenario 등 dev-process p18 필드 충족. 게이트의 **경고**(차단 아님).
- **gate report**: 이슈별 `READY`(accept 권고) / `NOT-READY`(reject + gap 체크리스트). 읽기전용 — 사람이 Jira 전이.

## 위치

파이프라인상 tc-author 앞: `Handover ─[resolve-gate: Accept the fix]→ Resolved ─[tc-author: Start Test]→ Test`. resolve-gate의 `READY`가 곧 tc-author Select의 입력 품질을 보장한다. 파이프라인 맥락은 [../../CONTEXT-MAP.md](../../CONTEXT-MAP.md), 롤아웃은 [../../docs/staging.md](../../docs/staging.md).
