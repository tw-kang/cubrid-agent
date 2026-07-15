# resolve-gate (Handover → Resolved)

**상태: 설계 v1 + PoC 검증 + Stage 2 게이트 스킬 구현 (2026-07-16). 구현체 `.claude/skills/resolve-gate/`.**

역할: **개발자가 자기 fix를 Resolved로 올리기 전**("Accept the fix") 스스로 QA-readiness를 점검하는 **평가형 게이트** 에이전트 — **실행 주체는 개발자**다. tc-author(생성형)와 달리 산출물을 만들지 않고 **판정(권고)** 을 낸다.

## 초점 — QA-readiness(테스트 플랜 작성 가능성)

fix를 실행해 검증하는 게 아니라, **"이 이슈를 Resolved로 올려도 되는가 — QA가 repro 재현·테스트 작성이 가능할 만큼 준비됐는가"** 를 개발자가 스스로 점검한다. **description(필수)** 과 **comment·첨부**(regression/core 리포팅은 재현 정보·실패 TC가 comment/첨부에 있다)를 함께 본다. 부족하면 "무엇을 보완해야 Resolved로 올릴 수 있는지" **self 피드백**. 사실상 **tc-author의 Ground가 성공할 재료를 개발자가 미리 갖추게 하는 관문**이다.

## 용어

- **Handover**: Jira 상태. 개발자가 fix를 머지·인계한 직후, QA가 받기 전.
- **Accept the fix**: Handover→Resolved 전이(=Check-in Fix). 반대편은 반려(ask recommendation / Resolve without fix = Bug Invalid). **dev→QA 핸드오프 지점**이라 이 시점 assignee=개발자. **resolve-gate 실행 주체 = 개발자 자신** — 자기 fix를 Resolved로 올리기 전 self-check이므로, NOT-READY는 개발자 본인이 보완할 체크리스트다(외부 @멘션 호출이 아님).
- **test-plannability(테스트 플랜 작성 가능성)**: 이슈 내용(특히 description)만으로 QA가 테스트 플랜/케이스를 짤 수 있는가. 게이트의 **차단 기준**. **이슈 성격별 이원 판정**(PoC 발견): 버그 이슈는 repro 자기완결+Expected/Actual로, 기능 이슈는 Spec 구체성+AC 검증가능성으로. 버그 기준을 기능 이슈에 적용하면 대다수 오판(PoC 23/27).
- **핸드오버 hygiene**: Fixed version·Need Manual·QA Scenario 등 dev-process p18 필드 충족. 게이트의 **경고**(차단 아님).
- **gate report**: 이슈별 `READY`(accept 권고) / `NOT-READY`(reject + gap 체크리스트). 읽기전용 — 사람이 Jira 전이.

## 위치

파이프라인상 tc-author 앞: `Handover ─[resolve-gate: Accept the fix]→ Resolved ─[tc-author: Start Test]→ Test`. resolve-gate의 `READY`가 곧 tc-author Select의 입력 품질을 보장한다. 파이프라인 맥락은 [../../CONTEXT-MAP.md](../../CONTEXT-MAP.md), 롤아웃은 [../../docs/staging.md](../../docs/staging.md).
