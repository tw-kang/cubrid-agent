# 용어집 — cubrid-agent

CBRD 이슈 워크플로의 상태 전이를 맡는 에이전트들이 함께 쓰는 용어. 파이프라인 지도와 에이전트 로스터는 [`docs/pipeline.md`](./docs/pipeline.md)에 있다.

## 파이프라인 상태·전이 (에이전트 간 조인 어휘)

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
| **신뢰 빌드** | oracle(기대 결과) 생성·검증의 기준이 되는, **대상 이슈의 fix가 포함된** CUBRID 빌드. fix 미포함 빌드의 검증 결과는 false signal |

## 공유 Jira 커스텀 필드

| 용어 | 뜻 |
|---|---|
| **Planned Version** | 이슈가 편입되기로 계획된 릴리스 필드. Fix Version(이미 편입된 릴리스)과 다르다. 파이프라인 Select 공통 축 |
| **QA Assignee** | 이슈의 QA 검증 담당자 필드. 개발 담당자(assignee)와 다르다 |
| **QA Scenario** | TC(시나리오) 작성 필요 여부의 공식 판단 필드. 값: `Required`/`Not Required`/`Not Yet`. 개발자가 초안을 쓰고 gate-resolved(QA)가 재판정한다 |

## 횡단 개념 (여러 에이전트 공통)

| 용어 | 뜻 |
|---|---|
| **판정형 vs 생성형** | gate-resolved·test-runner은 산출물을 만들지 않고 **판정(권고)** 을 낸다(판독형 포함). author-testcase는 **산출물(TC·PR)을 생성**한다. review-testcase는 **평가(권고)** |
| **횡단 에이전트** | Jira 상태 전이가 아니라 PR 수명주기(open→review→merge)에 붙는 에이전트(review-testcase). 대상은 작성자 무관(사람 PR + 봇 PR) 전체 sql TC PR |
| **완성 정의(실제 쓰기)** | 스킬의 종료 산출물 = 초안이 아니라 **실제 Jira 전이·코멘트·필드 쓰기**. 사람이 호출하는 지금도 적용(설계는 Jira) |
| **targeted / batch** | 사람이 이슈 키를 **나열**한 대상 지정 호출 = targeted(실제 쓰기), 스킬이 **JQL/큐 쿼리**로 만든 집합 호출 = batch(초안). 개수 무관 |
| **롤아웃 단계** | 이 repo는 결과물만 담는다. 단계와 진행은 로컬 지도가 관리하고, 지금 배포된 것이 어느 단계인지는 `CHANGELOG.md`만 적는다 |
| **배포면(shipped surface)** | 사용자 세션 동작을 바꾸는 파일 집합. 여기를 바꾼 커밋은 자리를 선언하고, 다음 릴리스가 그만큼 버전을 올린다. 밖(docs·규범·테스트·in-progress)만 바뀌면 버전은 그대로다 |
| **자리(digit)** | 버전 번호의 세 칸 `major`·`minor`·`patch` 중 하나. 배포면을 바꾼 사람이 변경 시점에 고른다 |
| **헤드 키** | 목표 하나를 담는 Jira 이슈(Jira 헤드)의 키. Draft PR이 다는 자리표시자 헤더다. 목록은 `.github/head-keys.txt` |
| **로컬 티켓** | 결정 하나 또는 작업 하나를 담는 `.scratch/` 아래 markdown 파일. Jira sub-task(PR 하나)와 다른 단계다 |

## 제품·저장소 형태 (CUBRIDQA-1454 어휘)

| 용어 | 뜻 |
|---|---|
| **design-to-Jira backfill** | 에이전트·스킬 설계 문서(DESIGN·설계 ADR·상세 CONTEXT 등)를 대응 CUBRIDQA 티켓 본문으로 옮기고 repo에서 삭제하는 것. "내용손실없이"는 백필 + git 이력이 보장 |
