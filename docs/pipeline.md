# 파이프라인 지도 · 에이전트 로스터

cubrid-agent는 CBRD 이슈 워크플로의 각 상태 전이를 맡는 에이전트들의 모노레포다(모노레포 근거는 **CUBRIDQA-1425**). 이 문서는 파이프라인 지도와 에이전트 로스터(한 줄 역할)를 담는다. 용어는 [`GLOSSARY.md`](../GLOSSARY.md)에 있다.

**에이전트·스킬의 상세 설계는 여기 없다.** repo=제품, 설계=Jira(CUBRIDQA-1454)에 따라 각 에이전트의 DESIGN·설계 ADR·상세 CONTEXT는 대응 CUBRIDQA 티켓으로 옮겼다(= design-to-Jira backfill). 로스터의 티켓 링크를 따라간다.

## 파이프라인 지도 (CBRD 이슈 상태)

```
# Dev 팀 (우리 범위 밖): Open → Confirmed → Analysis → Develop → Handover
Handover ─[Check-in Fix: 개발자]→ Resolved (QA to-do)
Resolved ─[gate-resolved: QA 검토]→ ┬ 통과 ─[Start Test]→ Test (author-testcase)
                                    └ 부적격 ─[Need Something]→ Handover (반송)
Test     ─[test-runner: Verify]→ Tested
Tested   ─[close-backport: Close / Need Backport]→ Closed / Backport
```

각 에이전트는 앞 상태/산출물을 입력으로, 다음 상태로의 전이를 출력으로 한다. 조인 키는 **이슈 키**(`CBRD-XXXXX` / TC 파일명 `cbrd_xxxxx`). 공식 상태·전이·운영 규칙은 사람용 런북 [`dev-process.md`](./dev-process.md) 참조.

**review-testcase는 상태 전이가 아니라 PR 수명주기에 붙는 횡단 에이전트**다. author-testcase(또는 사람)가 낸 sql TC PR이 머지되기 전 구간에서 첫 리뷰어로 붙는다:

```
author-testcase ─Draft PR─► [review-testcase 심사 ─► 사람 approve·merge] ─► test-runner
사람 작성 PR ────────────►┘
```

## 에이전트 로스터 (한 줄 역할 + 설계 티켓)

| 에이전트 | 전이 | 역할 (한 줄) | 설계 |
|---|---|---|---|
| **gate-resolved** | Resolved 검토 | Resolved(=QA to-do)를 ①필요성 ②작성 가능성 2축으로 검토해 부적격을 `Need Something`(→Handover)로 반송하는 QA-side 진입 게이트 (판정형) | [CUBRIDQA-1440](https://jira.cubrid.org/browse/CUBRIDQA-1440) |
| **author-testcase** | Resolved→Test (`Start Test`) | 이슈 fix에 대한 CTP SQL 테스트케이스를 작성·검증하고 Draft PR까지 내는 생성형 | [CUBRIDQA-1429](https://jira.cubrid.org/browse/CUBRIDQA-1429) |
| **review-testcase** | (횡단) PR open→merge | sql TC PR의 첫 리뷰어. 3층(컨벤션/도메인 관점/실행)으로 심사해 권고 판정 + 리뷰 초안을 낸다 (평가형) | [CUBRIDQA-1441](https://jira.cubrid.org/browse/CUBRIDQA-1441) |
| **test-runner** | Test→Tested (`Verify`) | 머지된 신규 TC가 야간 회귀에서 연속 2일 안정 PASS하는지 baseline 델타로 판독해 승격을 권고하는 판독형 | [CUBRIDQA-1444](https://jira.cubrid.org/browse/CUBRIDQA-1444) |
| **close-backport** | Tested→Closed / Backport (`Close` / `Need Backport`) | 종결 또는 백포트. 스위트 전체 회귀 무결(내 머지가 다른 TC를 깼는가)까지 확인 | 설계 전 — 부모 [CUBRIDQA-1425](https://jira.cubrid.org/browse/CUBRIDQA-1425) |

스킬 이름 = 에이전트 이름. 구현체는 배포분이면 `skills/qa/<name>/`, 아직 배포하지 않는 것이면 `skills/in-progress/<name>/`.
