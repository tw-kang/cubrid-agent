# gate-resolved (Resolved QA-readiness 게이트)

**구현체: [`skills/qa/gate-resolved/`](../../../skills/qa/gate-resolved/) (Stage 2).**

역할: **Resolved(=QA to-do) 이슈를 QA가 검토해, 테스트로 삼기 부적합한 것을 `Need Something`(→Handover)로 되돌려보내는 QA-side 진입 게이트.** 통과분은 author-testcase 단계로 이어진다. author-testcase(생성형)와 달리 산출물을 만들지 않고 **판정(권고)** 을 낸다.

## 초점 — QA to-do의 테스트 준비도 (2축)

resolve 처리 = 그 이슈가 QA 팀 to-do가 됨. gate-resolved는 이 큐를 두 축으로 검토한다:
1. **필요성** — 테스트가 필요한가 (QA Scenario 재판정: 개발자 초안을 QA가 뒤집을 수 있음).
2. **작성 가능성** — 필요하면 내용으로 테스트 플랜을 짤 수 있나 (test-plannability).

못 짜는 이슈는 부족한 점을 찾아 Handover로 반송. 사실상 **author-testcase의 Ground가 성공할 재료가 있는지를 앞단에서 거르는 관문**이다.

## 용어

- **Resolved**: Jira 상태. 개발자가 fix를 머지하고 Check-in Fix로 넘긴 직후 = **QA 팀 to-do**.
- **Check-in Fix**: Handover→Resolved 전이. **개발자가 머지 후 직접 수행**(gate-resolved 범위 밖). 매뉴얼(Need Manual)은 우선 Resolved 후 추후 작성하기도 한다.
- **QA to-do**: Resolved 상태 이슈. gate-resolved 검토 대상.
- **필요성 재판정**: QA Scenario(개발자 초안)를 QA 관점에서 재검토. **Not Required도 QA가 Required로 뒤집을 수 있다** — 필요하면 테스트 대상으로 승격.
- **test-plannability(작성 가능성)**: 내용(description·comment·첨부)만으로 QA가 테스트 플랜을 짤 수 있는가. 버그/기능 이원 판정(C0~C6), regression·core는 첨부된 실패 TC가 곧 repro.
- **Need Something**: Resolved→Handover 되돌림 전이(실측 확정). 테스트 플랜 부족분 반송에 사용. `cubrid-jira transition <KEY> --to "Need Something"`.
- **통과 / 반송**: 필요+가능 → `Start Test`(→Test, author-testcase) / 필요+불가 → `Need Something`(→Handover) / 불필요(QA 동의) → 스킵.
- **완성 정의(실제 쓰기)**: 스킬의 종료 산출물 = 초안이 아니라 실제 Jira 전이·코멘트·필드 쓰기([ADR 0016](../../adr/0016-completion-is-real-write.md)). Stage 2(사람 호출)에서도 적용.
- **targeted / batch**: 사람이 이슈 키를 **나열**한 대상 지정 호출 = targeted(실제 쓰기), 스킬이 **JQL/큐 쿼리**로 집합을 만든 호출 = batch(초안). 개수 무관.
- **가드 강등(guard-downgrade)**: targeted 실제 쓰기 경로에서 오탐 가드(sub-task 형제 커버·26909식 "오타가 의도된 입력"·저신뢰)가 걸리면 게시하지 않고 초안+@질의로 강등.

## 위치

Resolved 상태에서 author-testcase 앞에 선다:

```
Handover ─[Check-in Fix: 개발자]→ Resolved (QA to-do)
Resolved ─[gate-resolved: QA 검토]→ ┬ 통과 ─[Start Test]→ Test (author-testcase)
                                    └ 부적격 ─[Need Something]→ Handover (반송)
```

파이프라인 맥락은 [../../../CONTEXT-MAP.md](../../../CONTEXT-MAP.md), 롤아웃은 [../../staging.md](../../staging.md).
