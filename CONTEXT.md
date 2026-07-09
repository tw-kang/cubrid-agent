# jira-resolve-agent

Resolved 처리된 CBRD 이슈를 읽어 CTP SQL 테스트케이스를 작성·검증하고 PR까지 제출하는 agent bot의 컨텍스트. PoC 범위는 SQL 카테고리 단일 파이프라인이다.

## Language

### 파이프라인 단계

**Select**:
Jira에서 TC 작성 대상 이슈를 골라내는 첫 단계. QA Scenario가 Not Required가 아니고(Required 또는 Not Yet), Reproduction과 SQL 재현성이 있는 Resolved 이슈만 통과시킨다.
_Avoid_: 수집, 크롤링, triage

**Ground**:
선정된 이슈를 코드 사실(PR merge diff, 기존 TC)과 대조해 작성 근거를 확보하는 단계.
_Avoid_: 분석, 조사

**Author**:
`cubrid-sql-tc-create` 스킬로 `.sql` 테스트케이스를 작성하는 단계.
_Avoid_: 생성, 구현

**Verify**:
sqlmedium pod 안에서 CTP로 테스트케이스를 실제 수행해 pass/fail을 판정하는 단계.
_Avoid_: 테스트, 실행

**Review**:
Verify 결과와 TC 품질을 작성자와 분리된 lane에서 평가하는 단계.
_Avoid_: 검사, QA

**Submit**:
통과한 TC를 fork(tw-kang)에 push하고 upstream(CUBRID)에 Draft PR을 여는 마지막 단계.
_Avoid_: 배포, 머지

**피드백 루프**:
Author↔Verify↔Review를 도는 반복. 1회차를 전부 통과해도 리뷰 피드백을 반영한 개선·재검증을 1회 강제하며(따라서 최소 2회차), 5회차까지 미통과면 스킵한다.

**Run**:
봇의 1회 기동. 기본으로 대기열 선두 1건을 end-to-end 처리하며, 인자로 건수나 특정 이슈 키를 지정할 수 있다.

**대기열**:
Select를 통과한 이슈들의 처리 순서. resolved 처리가 오래된 순.
_Avoid_: 백로그

**스킵**:
SQL로 재현할 수 없거나 피드백 루프 한도(5회) 안에 통과하지 못한 이슈를, 사유를 리포트에 남기고 건너뛰는 처분.
_Avoid_: 실패, 폐기

**이슈 브랜치**:
한 이슈의 TC 작업만 담는 브랜치. 이름은 `tc/cbrd-xxxxx`.

**리포트**:
Run이 이슈별로 남기는 처리 기록 — 선정 근거, 루프 이력, 검증 결과, PR 링크 또는 스킵 사유.

### Jira 개념

**Planned Version**:
이슈가 편입되기로 계획된 릴리스를 담는 Jira 커스텀 필드(`cf[210441]`). Fix Version(이미 편입된 릴리스)과 다르다.
_Avoid_: fixVersion, Target Version

**QA Assignee**:
이슈의 QA 검증 담당자를 담는 Jira 커스텀 필드(`cf[213834]`). 개발 담당자(assignee)와 다르다.

**QA Scenario**:
TC(시나리오) 작성 필요 여부에 대한 조직의 공식 판단을 담는 Jira 커스텀 필드(`cf[210565]`). 값: `Required` / `Not Required` / `Not Yet`.

**Scenario Required**:
QA Scenario=Required인 이슈. TC를 만들어야 한다는 공식 신호. Not Yet(판단 보류)인 이슈도 Select 대상이며, 이때 봇의 TC 초안은 판단 재료 역할을 한다. Not Required만 제외된다.

**Reproduction**:
이슈의 description 또는 comment에 담긴, 문제를 재현하는 구체적 절차(SQL, 설정, 순서). Select의 두 번째 필요조건 — 자동 TC 작성 가능성의 전제.
_Avoid_: repro step(문서에서는 한글 용어 사용), 재현 경로

**SQL 재현성**:
이슈의 재현과 증상 관측이 csql SQL문만으로 가능하고, fix 후 빌드에서 출력이 매회 일치하는 성질. Select의 세 번째 게이트. 버그 발생이 확률적이어도 fix 후 출력이 결정적이면 충족.
_Avoid_: 재현 가능성(Reproduction과 혼동 금지)

**검출력**:
TC가 버그 재발 시 실제로 실패할 확률. SQL 재현성과 별개 속성으로, 리뷰의 평가 항목이다.
_Avoid_: 커버리지

### 검증 개념

**sqlmedium pod**:
build-cache의 CUBRID 빌드를 overlay 마운트하고 CTP를 내장한 k8s pod — TC 검증의 실행 환경. 봇은 run마다 전용 pod를 생성하고 종료 시 삭제하며, 기존 공용 pod는 건드리지 않는다.
_Avoid_: 테스트 컨테이너, CI pod

**BUILD_SHA**:
sqlmedium pod가 build-cache에서 마운트할 CUBRID 빌드를 지정하는 식별자(커밋 SHA).

**Answer file**:
TC의 기대 출력 기준선(`.answer`). CTP 실행 결과에서 승격해 만들며, 손으로 쓰지 않는다.
