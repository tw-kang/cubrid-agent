# Context Map — cubrid-agent

cubrid-agent는 CBRD 이슈 워크플로의 각 상태 전이를 맡는 에이전트들의 모노레포. 각 에이전트는 `agents/<name>/` 아래 자기 `CONTEXT.md`·`DESIGN.md`·`docs/adr/`·`reports/`(grilling 산출물)를 가진다. 모노레포 결정 근거는 [ADR 0008](./docs/adr/0008-monorepo-agents.md).

## Contexts (에이전트)

- [resolve-gate](./agents/resolve-gate/) — **Handover→Resolved** ("Accept the fix"): 개발자 fix를 Resolved로 받기 전 **QA-readiness(테스트 플랜 작성 가능성)** 게이트. (설계 v0)
- [tc-author](./agents/tc-author/) — **Resolved→Test** ("Start Test"): 이슈 fix에 대한 CTP 테스트케이스 산출물 생성. (PoC 진행 중, 1호 완료)
- [tc-reviewer](./agents/tc-reviewer/) — **PR 리뷰 (횡단)**: cubrid-testcases의 sql TC PR(사람·봇 무관)을 3층(컨벤션/마이닝된 도메인 관점/실행)으로 심사 → 권고 판정 + 리뷰 초안. 상태 전이가 아니라 PR 머지 구간의 리뷰어 병목을 줄이는 첫 리뷰어. (설계 v1)
- [test-runner](./agents/test-runner/) — **Test→Tested** ("Verify"): 머지된 신규 TC가 야간 회귀(qaresu DB)에서 **연속 2일 안정 PASS** 하는지를 baseline 델타로 판독 → Tested 승격 권고. 회귀는 직접 안 돌리고 결과만 읽는 판독형. (설계 v1)
- [close-backport](./agents/close-backport/) — **Tested→Closed / Backport** ("Close" / "Need Backport"): 종결 또는 백포트. (설계 전)

## 파이프라인 (CBRD 이슈 상태 — 공식 워크플로)

```
# Dev 팀 (우리 범위 밖): Open → Confirmed → Analysis → Develop → Handover
Handover ─[resolve-gate: Accept the fix]→ Resolved
         ─[tc-author: Start Test]→ Test
         ─[test-runner: Verify]→ Tested
         ─[close-backport: Close / Need Backport]→ Closed / Backport
```

각 에이전트는 앞 상태/산출물을 입력으로, 다음 상태로의 전이를 출력으로 한다. 이슈 키(`cbrd_xxxxx`)가 에이전트 간 조인 키. 공식 상태·전이·운영 규칙(Description/Handover/Merge/Backport)은 [docs/handover/dev-process-v2.4.md](./docs/handover/dev-process-v2.4.md).

예외적으로 **tc-reviewer는 상태 전이가 아니라 PR 수명주기에 붙는 횡단 에이전트**다: tc-author(또는 사람)가 낸 TC PR이 머지되기 전 구간(`PR open ─[tc-reviewer 심사]→ 사람 approve·merge`)에서 첫 리뷰어 역할을 한다.

## 공유 (시스템 전역)

- [docs/design-principles.md](./docs/design-principles.md) — 전 에이전트 공통 설계 원칙(DP1 병렬 실행: 순차 의존 없는 단위는 병렬로 쪼개 수행).
- [docs/staging.md](./docs/staging.md) — 롤아웃 3단계 모델(PoC / Stage 2 팀 수동 트리거 / Stage 3 무인 자동), 전 에이전트 공통.
- [docs/adr/](./docs/adr/) — 시스템 전역 ADR.
- [docs/handover/](./docs/handover/) — 외부 핸드오버 재료(v1 배포 설계, v2 TC 작성).
- 공유 자산(코드 아님): `cubrid-jira` CLI, `~/skills`, 소스 repo(cubrid, cubrid-testcases, cubrid-testtools 등), 사내 빌드서버, 로컬/pod 검증 환경.

## ADR 번호 규칙

ADR 번호는 **전역 유일 단일 시퀀스**. 생성 순서로 매기되 범위에 따라 위치가 갈린다:
- `0001`~`0006` = tc-author PoC에서 나온 tc-author 전용 결정 → `agents/tc-author/docs/adr/`
- `0007`(롤아웃 단계), `0008`(모노레포) = 시스템 전역 → `docs/adr/`
- 이후: 전역 결정은 `docs/adr/`, 에이전트 전용은 `agents/<name>/docs/adr/`.

## 용어

현재 도메인 용어집은 [agents/tc-author/CONTEXT.md](./agents/tc-author/CONTEXT.md)에 있다(PoC에서 정립). 다른 에이전트가 설계되면 각자 `CONTEXT.md`에 자기 용어를 두고, 여러 에이전트가 공유하는 용어는 이 맵으로 승격한다.
