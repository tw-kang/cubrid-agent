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
| **헤드 키** | 목표 하나를 담는 Jira 이슈(Jira 헤드)의 키. PR 헤더의 자리표시자로도 쓴다. 언제 달고 언제 바꾸는지는 [`docs/agents/issue-tracker.md`](./docs/agents/issue-tracker.md)의 PR 흐름에 있다 |
| **로컬 티켓** | 결정 하나 또는 작업 하나를 담는 `.scratch/` 아래 markdown 파일. Jira sub-task와 다른 단계다 |
| **재현 파일** | research 결과 `<name>.md` 옆의 `<name>.repro.md`. 결과의 `[ID]` 태그마다 그 수치를 다시 내는 블록(`sh`·`expected`, 일부는 `independent`)을 담는다. `scripts/research-recheck.py`가 읽고, 형식의 정본은 그 머리 주석이다 |

## 제품·저장소 형태 (CUBRIDQA-1454 어휘)

| 용어 | 뜻 |
|---|---|
| **design-to-Jira backfill** | 에이전트·스킬 설계 문서(DESIGN·설계 ADR·상세 CONTEXT 등)를 대응 CUBRIDQA 티켓 본문으로 옮기고 repo에서 삭제하는 것. "내용손실없이"는 백필 + git 이력이 보장 |

## 룰북 (CUBRIDQA-1663 어휘)

tc repo 개발자가 읽는 영문 용어 표는 정본의 루트 `AGENTS.md`에 있다. 같은 용어는 두 표에서 같은 뜻이다. 한쪽을 고치면 다른 쪽도 고친다.

| 용어 | 뜻 |
|---|---|
| **룰북(rulebook)** | tc repo에서 TC를 어떻게 쓰는지 알려 주는 파일 묶음이다. 루트 `AGENTS.md`, `<카테고리>/AGENTS.md`, `<카테고리>/rules/`의 두 파일이다 |
| **정본(canonical copy)** | 룰북의 원본이다. `cubrid-agent`의 `rulebook/<tc repo 이름>/`에 tc repo와 같은 경로로 둔다. QA는 정본만 고친다 |
| **배포본(deployed copy)** | tc repo에 들어간 정본의 사본이다. 개발자와 개발자의 에이전트가 읽는다 |
| **test perspectives(테스트 관점)** | 룰북의 B 갈래다. TC가 무엇을 확인하나를 담는다. 파일은 `<카테고리>/rules/test-perspectives.md`다 |
| **writing rules(작성 규칙)** | 룰북의 C 갈래다. TC 파일을 어떻게 쓰나를 담는다. 파일은 `<카테고리>/rules/writing-rules.md`다 |
| **OK/NOK 판정(verdict)** | TC가 `write_ok`나 `write_nok`를 한 번 부르는 것이다. 위 **판정형 vs 생성형**의 판정(에이전트가 내는 권고)과 다른 뜻이다 |
| **답지(answer file)** | TC가 실행 결과를 비교하는 기대 출력 파일이다(`.answer`) |
| **격리(quarantine)** | 원인을 못 찾은 흔들리는 TC를 `_25_unstable` 아래 같은 상대 경로로 옮기는 것이다 |
| **제외(exclusion)** | TC를 excluded list에 더하는 것이다 |
| **대기 상한(wait limit)** | `wait_until`에 주는 timeout이다 |
| **담당자 확인 목록(owner checklist)** | tc repo 룰북 PR 본문에서 카테고리 담당자가 확인할 항목의 목록이다. 설문과 다르게 정한 것과 확인이 필요한 것을 담는다 |
| **CI 파드(CI pod)** | 엔진 repo(`CUBRID/cubrid`)의 CI가 TC를 돌리는 pod다 |
| **VM 정기 회귀(VM daily)** | 공용 VM에서 도는 정기 회귀다 |
| **제외 목록(excluded list)** | 어떤 회귀도 돌리지 않는 TC 경로를 적은 파일이다. `shell/config/daily_regression_test_excluded_list_linux.conf`다 |
