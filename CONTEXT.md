# CONTEXT — cubrid-agent

cubrid-agent는 CBRD 이슈 워크플로의 각 상태 전이를 맡는 에이전트들의 모노레포다(모노레포 근거는 **CUBRIDQA-1425**). 이 파일은 저장소의 단일 **오리엔테이션 + 공유 용어집**이다 — 파이프라인 지도, 에이전트 로스터(한 줄 역할), 저장소 배치, 그리고 여러 에이전트가 공유하는 용어만 담는다.

**에이전트·스킬의 상세 설계는 여기 없다.** [ADR 0005](.agents/adr/0005-repo-is-product-design-lives-in-jira.md)(repo=제품, 설계=Jira)에 따라 각 에이전트의 DESIGN·설계 ADR·상세 CONTEXT는 대응 CUBRIDQA 티켓으로 옮겼다(= design-to-Jira backfill). 로스터의 티켓 링크를 따라간다.

## 파이프라인 지도 (CBRD 이슈 상태)

```
# Dev 팀 (우리 범위 밖): Open → Confirmed → Analysis → Develop → Handover
Handover ─[Check-in Fix: 개발자]→ Resolved (QA to-do)
Resolved ─[gate-resolved: QA 검토]→ ┬ 통과 ─[Start Test]→ Test (author-testcase)
                                    └ 부적격 ─[Need Something]→ Handover (반송)
Test     ─[test-runner: Verify]→ Tested
Tested   ─[close-backport: Close / Need Backport]→ Closed / Backport
```

각 에이전트는 앞 상태/산출물을 입력으로, 다음 상태로의 전이를 출력으로 한다. 조인 키는 **이슈 키**(`CBRD-XXXXX` / TC 파일명 `cbrd_xxxxx`). 공식 상태·전이·운영 규칙은 사람용 런북 [`docs/`](docs/)의 dev-process 참조.

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

스킬 이름 = 에이전트 이름. 구현체는 배포분이면 `skills/qa/<name>/`, 아직 배포하지 않는 것이면 `skills/in-progress/<name>/`([ADR 0006](.agents/adr/0006-shipped-vs-in-progress-skill-trees.md)).

## 저장소 배치

[ADR 0005](.agents/adr/0005-repo-is-product-design-lives-in-jira.md)에 따라 문서를 "배포되는가·누가 읽는가"로 나눈다.

- **루트 플러그인 = 제품(배포되는 전부):** `.claude-plugin/` · `skills/qa/` · `hooks/` · `scripts/`. 저장소의 존재 이유. **`skills/qa/`는 `plugin.json` 등재분과 정확히 일치**하고, 아직 배포하지 않는 스킬은 `skills/in-progress/`에서 개발한다 — 완성되면 이동+등재로 승격한다([ADR 0006](.agents/adr/0006-shipped-vs-in-progress-skill-trees.md)).
- **`.agents/` = 에이전트용 규범(횡단) + thin ADR:**
  - 규범: `design-principles.md`(DP1 병렬 실행, **DP2 사용자 관점·블랙박스 테스트**, DP3 언어 정책), `issue-tracker.md`, `triage-labels.md`, `domain.md`.
  - **thin ADR set** (`.agents/adr/`): "제품·저장소가 왜 이 모양인가"만 담는다 — ship-as-plugin, dual-channel 배포, setup-entrypoint 스킬, 개인 식별자 제거, 이 doc-strategy(repo=제품·설계=Jira), 배포분/개발 중 2트리. `.agents/adr/`로 옮기며 **0001–0005로 재번호**했고, 옛 전역 단일 시퀀스 규칙은 폐기됐다.
- **`docs/` = 사람용 런북/참조:** 설치(setup), 배포 구조(deployment), 공식 dev-process. 외부 기여자는 제품 + 이 문서로 충분하다.
- **루트 `CONTEXT.md`(이 파일):** 단일 용어집 + 파이프라인 지도. (구 `CONTEXT-MAP.md` + 에이전트별 `docs/agents/*/CONTEXT.md` ×5를 흡수·대체.)
- **Jira(CUBRIDQA):** 에이전트·스킬 설계(DESIGN, 방법론 ADR, staging, hook-gates 설계). 역사는 git commit이 보존한다.

공유 자산(코드 아님): `cubrid-jira` CLI, `~/skills`, 소스 repo(cubrid, cubrid-testcases, cubrid-testtools 등), 사내 빌드서버, 로컬/pod 검증 환경.

## 용어

### 파이프라인 상태·전이 (에이전트 간 조인 어휘)

| 용어 | 뜻 |
|---|---|
| **이슈 키** | `CBRD-XXXXX`. 에이전트 간 조인 키이자 TC 파일명 규약(`cbrd_xxxxx`) |
| **Resolved** | 개발자가 fix를 머지하고 Check-in Fix로 넘긴 직후의 Jira 상태 = **QA 팀 to-do**. gate-resolved의 검토 대상 |
| **Check-in Fix** | Handover→Resolved 전이. **개발자가 직접 수행**(우리 범위 밖). Need Manual은 우선 Resolved 후 추후 작성하기도 함 |
| **Need Something** | Resolved→Handover 되돌림 전이. gate-resolved가 테스트 플랜 부족분을 반송할 때 사용 |
| **Start Test** | Resolved→Test 전이. gate-resolved 통과분이 author-testcase로 넘어가는 경계 |
| **Verify** | Test→Tested 공식 전이(test-runner). 되돌림은 Stop Test(→Resolved). ※ author-testcase **내부 단계명** "Verify"(CTP 실행)와 이름이 겹치니 문맥 주의 |
| **Tested** | Verify 통과 상태. close-backport의 대상 |
| **Close / Need Backport** | Tested→Closed / Backport 전이. close-backport |
| **신뢰 빌드** | oracle(`.answer`) 생성·검증의 기준이 되는, **대상 이슈의 fix가 포함된** CUBRID 빌드. 위치 규약 `$HOME/CUBRID`. fix 미포함 빌드의 검증 결과는 false signal |

### 공유 Jira 커스텀 필드

| 용어 | 뜻 |
|---|---|
| **Planned Version** | 이슈가 편입되기로 계획된 릴리스 필드(`cf[210441]`). Fix Version(이미 편입된 릴리스)과 다르다. 파이프라인 Select 공통 축 |
| **QA Assignee** | 이슈의 QA 검증 담당자 필드(`cf[213834]`). 개발 담당자(assignee)와 다르다 |
| **QA Scenario** | TC(시나리오) 작성 필요 여부의 공식 판단 필드(`cf[210565]`). 값: `Required`/`Not Required`/`Not Yet`. 개발자가 초안을 쓰고 gate-resolved(QA)가 재판정한다 |

### 횡단 개념 (여러 에이전트 공통)

| 용어 | 뜻 |
|---|---|
| **판정형 vs 생성형** | gate-resolved·test-runner은 산출물을 만들지 않고 **판정(권고)** 을 낸다(판독형 포함). author-testcase는 **산출물(TC·PR)을 생성**한다. review-testcase는 **평가(권고)** |
| **횡단 에이전트** | Jira 상태 전이가 아니라 PR 수명주기(open→review→merge)에 붙는 에이전트(review-testcase). 대상은 작성자 무관(사람 PR + 봇 PR) 전체 sql TC PR |
| **완성 정의(실제 쓰기)** | 스킬의 종료 산출물 = 초안이 아니라 **실제 Jira 전이·코멘트·필드 쓰기**. 사람이 호출하는 지금도 적용(설계는 Jira) |
| **targeted / batch** | 사람이 이슈 키를 **나열**한 대상 지정 호출 = targeted(실제 쓰기), 스킬이 **JQL/큐 쿼리**로 만든 집합 호출 = batch(초안). 개수 무관 |
| **롤아웃 단계** | 이 repo는 결과물만 담는다. 단계와 그 이력은 CUBRIDQA-1425가 관리하고, 지금 배포된 것이 어느 단계인지는 `CHANGELOG.md`만 적는다 |
| **배포면(shipped surface)** | 사용자 세션 동작을 바꾸는 파일 집합. 여기가 바뀌면 버전 범프가 필수이고, 밖(docs·규범·테스트·in-progress)이 바뀌면 범프 없이 develop에 쌓인다. 경로 목록 정본은 버저닝 ADR |

### 제품·저장소 형태 결정 (ADR 0005 어휘)

| 용어 | 뜻 |
|---|---|
| **product-shape ADR** | repo에 남기는 thin ADR. "제품·저장소가 왜 이 모양인가"(ship-as-plugin·dual-channel·setup-entrypoint·doc-strategy)만 담고, 에이전트·스킬 설계는 담지 않는다(그건 Jira). 위치 `.agents/adr/` |
| **design-to-Jira backfill** | 에이전트·스킬 설계 문서(DESIGN·설계 ADR·상세 CONTEXT 등)를 대응 CUBRIDQA 티켓 본문으로 옮기고 repo에서 삭제하는 것. "내용손실없이"는 백필 + git 이력이 보장 |
