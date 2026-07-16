# resolve-gate (Resolved QA-readiness 게이트)

**상태: v2 재정의 + PoC 검증 (2026-07-16, twkang assignee 17건). Resolved(QA to-do) 대상, Need Something(→Handover) 반송. 구현체 `.claude/skills/resolve-gate/`.**

역할: **Resolved(=QA to-do) 이슈를 QA가 검토해, 테스트로 삼기 부적합한 것을 `Need Something`(→Handover)로 되돌려보내는 QA-side 진입 게이트.** 통과분은 tc-author 단계로 이어진다. tc-author(생성형)와 달리 산출물을 만들지 않고 **판정(권고)** 을 낸다.

## 초점 — QA to-do의 테스트 준비도 (2축)

resolve 처리 = 그 이슈가 QA 팀 to-do가 됨. resolve-gate는 이 큐를 두 축으로 검토한다:
1. **필요성** — 테스트가 필요한가 (QA Scenario 재판정: 개발자 초안을 QA가 뒤집을 수 있음).
2. **작성 가능성** — 필요하면 내용으로 테스트 플랜을 짤 수 있나 (test-plannability).

못 짜는 이슈는 부족한 점을 찾아 Handover로 반송. 사실상 **tc-author의 Ground가 성공할 재료가 있는지를 앞단에서 거르는 관문**이다.

## 용어

- **Resolved**: Jira 상태. 개발자가 fix를 머지하고 Check-in Fix로 넘긴 직후 = **QA 팀 to-do**.
- **Check-in Fix**: Handover→Resolved 전이. **개발자가 머지 후 직접 수행**(resolve-gate 범위 밖). 매뉴얼(Need Manual)은 우선 Resolved 후 추후 작성하기도 한다.
- **QA to-do**: Resolved 상태 이슈. resolve-gate 검토 대상.
- **필요성 재판정**: QA Scenario(개발자 초안)를 QA 관점에서 재검토. **Not Required도 QA가 Required로 뒤집을 수 있다** — 필요하면 테스트 대상으로 승격.
- **test-plannability(작성 가능성)**: 내용(description·comment·첨부)만으로 QA가 테스트 플랜을 짤 수 있는가. 버그/기능 이원 판정(C0~C6), regression·core는 첨부된 실패 TC가 곧 repro.
- **Need Something**: Resolved→Handover 되돌림 전이(실측 확정). 테스트 플랜 부족분 반송에 사용. `cubrid-jira transition <KEY> --to "Need Something"`.
- **통과 / 반송**: 필요+가능 → `Start Test`(→Test, tc-author) / 필요+불가 → `Need Something`(→Handover) / 불필요(QA 동의) → 스킵.

## 위치

Resolved 상태에서 tc-author 앞에 선다:

```
Handover ─[Check-in Fix: 개발자]→ Resolved (QA to-do)
Resolved ─[resolve-gate: QA 검토]→ ┬ 통과 ─[Start Test]→ Test (tc-author)
                                    └ 부적격 ─[Need Something]→ Handover (반송)
```

전이(Check-in Fix)를 맡던 v1과 달리, v2는 **Resolved 상태의 QA to-do를 검토**하고 부적격을 반송한다. 파이프라인 맥락은 [../../CONTEXT-MAP.md](../../CONTEXT-MAP.md), 롤아웃은 [../../docs/staging.md](../../docs/staging.md).
