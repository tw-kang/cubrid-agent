# Context Map — cubrid-agent

cubrid-agent는 CBRD 이슈 워크플로의 각 상태 전이를 맡는 에이전트들의 모노레포. 모노레포 결정 근거는 [ADR 0008](./docs/adr/0008-monorepo-agents.md).

**디렉토리 성격 3분법** ([ADR 0012](./docs/adr/0012-doc-tree-by-nature.md)): 루트 = 지도(이 파일)·진입점(`setup.sh`) / **루트 플러그인 = 실행 계약**(`.claude-plugin/`·`skills/qa/`·`hooks/`·`scripts/` — 배포되는 전부, docs/ 참조 없음; 재패키징 [ADR 0014](./docs/adr/0014-repackage-as-plugin.md)) / **`docs/` = 문서 전부** — 평면은 **현행 유효한 전역 규범·참조만**, `guides/`=실행 가이드, `adr/`=결정 기록, `agents/`=에이전트별 설계 기록(dev-only). **문서는 항상 최신만 — 과거 이력은 git commit이 보존**(역사화된 문서는 삭제). 각 에이전트는 `docs/agents/<name>/` 아래 자기 `CONTEXT.md`·`DESIGN.md`·`docs/adr/`·`reports/`(gitignore, dev 로컬)를 가지며, **스킬 이름 = 에이전트 이름**이다.

## Contexts (에이전트)

- [gate-resolved](./docs/agents/gate-resolved/) — **Resolved 검토 (QA-side 게이트)**: Resolved(=QA to-do) 이슈를 QA가 ①필요성 ②작성가능성 2축으로 검토 → 테스트 플랜 불가 이슈를 **Need Something(→Handover) 반송**, 통과분은 author-testcase로. Check-in Fix(Handover→Resolved)는 개발자 몫(범위 밖). (Stage 2 스킬: [`skills/qa/gate-resolved/`](./skills/qa/gate-resolved/))
- [author-testcase](./docs/agents/author-testcase/) — **Resolved→Test** ("Start Test"): 이슈 fix에 대한 CTP 테스트케이스 산출물 생성. (Stage 2 스킬: [`skills/qa/author-testcase/`](./skills/qa/author-testcase/); Draft PR #3041·#3049 리뷰 대기)
- [review-testcase](./docs/agents/review-testcase/) — **PR 리뷰 (횡단)**: cubrid-testcases의 sql TC PR(사람·봇 무관)을 3층(컨벤션/마이닝된 도메인 관점/실행)으로 심사 → 권고 판정 + 리뷰 초안. 상태 전이가 아니라 PR 머지 구간의 리뷰어 병목을 줄이는 첫 리뷰어. (Stage 2 스킬: [`skills/qa/review-testcase/`](./skills/qa/review-testcase/))
- [test-runner](./docs/agents/test-runner/) — **Test→Tested** ("Verify"): 머지된 신규 TC가 야간 회귀(qaresu DB)에서 **연속 2일 안정 PASS** 하는지를 baseline 델타로 판독 → Tested 승격 권고. 회귀는 직접 안 돌리고 결과만 읽는 판독형. (설계 v1)
- [close-backport](./docs/agents/close-backport/) — **Tested→Closed / Backport** ("Close" / "Need Backport"): 종결 또는 백포트. (설계 전)

## 파이프라인 (CBRD 이슈 상태 — 공식 워크플로)

```
# Dev 팀 (우리 범위 밖): Open → Confirmed → Analysis → Develop → Handover
Handover ─[Check-in Fix: 개발자]→ Resolved (QA to-do)
Resolved ─[gate-resolved: QA 검토]→ ┬ 통과 ─[author-testcase: Start Test]→ Test
                                    └ 부적격 ─[Need Something]→ Handover (반송)
Test     ─[test-runner: Verify]→ Tested
Tested   ─[close-backport: Close / Need Backport]→ Closed / Backport
```

각 에이전트는 앞 상태/산출물을 입력으로, 다음 상태로의 전이를 출력으로 한다. 이슈 키(`cbrd_xxxxx`)가 에이전트 간 조인 키. 공식 상태·전이·운영 규칙(Description/Handover/Merge/Backport)은 [docs/dev-process-v2.4.md](./docs/dev-process-v2.4.md).

예외적으로 **review-testcase는 상태 전이가 아니라 PR 수명주기에 붙는 횡단 에이전트**다: author-testcase(또는 사람)가 낸 TC PR이 머지되기 전 구간(`PR open ─[review-testcase 심사]→ 사람 approve·merge`)에서 첫 리뷰어 역할을 한다.

## 공유 (시스템 전역)

- [docs/design-principles.md](./docs/design-principles.md) — 전 에이전트 공통 설계 원칙(DP1 병렬 실행; **DP2 사용자 관점·블랙박스 테스트** — TC·시나리오는 내부 구현이 아닌 관측 동작 기준. '사용자'=DBA·DB engineer(전문가)~AP 개발자(비전문가) 스펙트럼이라 플랜·카탈로그·statdump·드라이버 입출력은 블랙박스 안, C 내부는 제외. 목적에 **필드에서 마주칠 상황 미리 검출** 포함. 관측 수단은 카테고리별(SQL→shell·CCI/JDBC 등 확장 예정)).
- [docs/staging.md](./docs/staging.md) — 롤아웃 3단계 모델(PoC / Stage 2 팀 수동 트리거 / Stage 3 무인 자동), 전 에이전트 공통.
- [docs/deployment.md](./docs/deployment.md) — **배포 구조 정본**: 자산 3계층(clone이 나른다/스크립트가 만든다/사람이 넣는다), 확정 결정 D1~D8, Stage 3 매핑. 원칙: *문서는 사람에게, 스크립트는 머신에게, 자격은 Secret에게*. Tier 2 자동화 = 루트 `setup.sh`(멱등). 부품 스킬 흡수·플러그인 재패키징은 [ADR 0014](./docs/adr/0014-repackage-as-plugin.md), 이중 채널 배포는 [ADR 0015](./docs/adr/0015-dual-channel-distribution.md).
- [docs/guides/stage2-setup.md](./docs/guides/stage2-setup.md) — Stage 2 팀 셋업 실행 가이드: `git clone` → `./setup.sh` → 자격 주입 → 기동. 함정 체크리스트 포함.
- [docs/adr/](./docs/adr/) — 시스템 전역 ADR.
- [docs/dev-process-v2.4.md](./docs/dev-process-v2.4.md) — 공식 dev 프로세스(상태·전이·운영 규칙) 참조.
- 공유 자산(코드 아님): `cubrid-jira` CLI, `~/skills`, 소스 repo(cubrid, cubrid-testcases, cubrid-testtools 등), 사내 빌드서버, 로컬/pod 검증 환경.

## ADR 번호 규칙

ADR 번호는 **전역 유일 단일 시퀀스**. 생성 순서로 매기되 범위에 따라 위치가 갈린다:
- `0001`~`0006`·`0009` = author-testcase 전용 → `docs/agents/author-testcase/docs/adr/`
- `0007`(롤아웃 단계)·`0008`(모노레포)·`0012`(문서 트리 성격 3분법)·`0013`(jira 첨부 읽기)·`0014`(플러그인 재패키징)·`0015`(이중 채널 배포) = 시스템 전역 → `docs/adr/`
- `0010`(판정 원천·baseline 델타) = test-runner 전용 → `docs/agents/test-runner/docs/adr/`
- 이후: 전역 결정은 `docs/adr/`, 에이전트 전용은 `docs/agents/<name>/docs/adr/`. **새 번호를 매기기 전 전 시퀀스(전역+에이전트)를 확인한다.**

## 용어

각 에이전트는 자기 `CONTEXT.md`에 자기 용어를 두고, **여러 에이전트가 공유하는 용어는 이 맵으로 승격한다**. 승격분:

| 용어 | 뜻 |
|---|---|
| **Planned Version** | 이슈가 편입되기로 계획된 릴리스를 담는 Jira 커스텀 필드(`cf[210441]`). Fix Version(이미 편입된 릴리스)과 다르다. 파이프라인 Select 공통 축(현재 값 guava) |
| **QA Assignee** | 이슈의 QA 검증 담당자 Jira 커스텀 필드(`cf[213834]`). 개발 담당자(assignee)와 다르다 |
| **QA Scenario** | TC(시나리오) 작성 필요 여부의 공식 판단 Jira 커스텀 필드(`cf[210565]`). 값: `Required`/`Not Required`/`Not Yet`. 개발자가 초안을 쓰고 gate-resolved(QA)가 재판정한다 |
| **신뢰 빌드** | oracle(`.answer`) 생성·검증의 기준이 되는, **대상 이슈의 fix가 포함된** CUBRID 빌드. 위치 규약 `$HOME/CUBRID`(deployment.md D7). fix 미포함 빌드의 검증 결과는 false signal |
