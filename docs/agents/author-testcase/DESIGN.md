# author-testcase — 설계 (cubrid-agent)

Resolved 처리된 CBRD 이슈를 읽어 CTP SQL 테스트케이스를 작성·검증·리뷰하고 upstream Draft PR까지 제출하는 agent. 용어는 [CONTEXT.md](./CONTEXT.md), 주요 결정 근거는 [docs/adr/](./docs/adr/), 구현체는 [`skills/qa/author-testcase/`](../../../skills/qa/author-testcase/)(기동 `/author-testcase [N | CBRD-XXXXX]`).

**추적 이슈**: [CUBRIDQA-1429](http://jira.cubrid.org/browse/CUBRIDQA-1429) — 진행 현황·스펙의 **단일 정본은 이 이슈 description**이다(로컬 사본을 repo에 두지 않는다). CUBRIDQA는 익명 읽기가 막혀 있어 인증으로 읽는다: `curl --netrc "http://jira.cubrid.org/rest/api/2/issue/CUBRIDQA-1429?fields=description"`. 갱신은 임시 파일(raw Jira wiki markup)에 써서 `cubrid-jira update CUBRIDQA-1429 --description-file <tmp> --from jira --yes`로 올리고 그 파일은 커밋하지 않는다(`--from jira`는 EL8 pandoc 2.0.6이 jira writer(≥2.9)를 미지원해 필수).

**롤아웃**: 현재 Stage 2(팀내 수동 트리거). 단계 모델은 [staging.md](../../staging.md), 근거는 [ADR 0007](../../adr/0007-rollout-stages.md).

## 범위

- **대상 카테고리**: SQL만 (`cubrid-testcases/sql`). shell/medium/CCI 등은 이후.
- **실행 형태**: Claude Code 스킬(`/author-testcase`) — 사람이 세션에서 기동. headless/cron은 Stage 3.
- **Jira는 읽기 전용**. PR 링크·처리 결과는 리포트에만 기록.

## 확정 결정

| # | 결정 사항 | 내용 |
|---|---|---|
| Q1 | 실행 형태 | 오케스트레이터 스킬 + 부품 스킬(create/verify) 위임 + 분리 리뷰 lane |
| Q2 | 선정 기준 | QA Scenario는 **Not Required만 제외**(Required + Not Yet 포함) ∩ Reproduction 존재 ∩ SQL 재현성 (ADR 0002) |
| Q3 | 검증 단위 | 로컬 CTP interactive 단건 실행 (ADR 0006). pod·build-cache 검증은 Stage 3 (ADR 0001 — run마다 봇 전용 pod 생성/삭제, 공용 pod 불가침) |
| Q4 | 검증 빌드 | **신뢰 빌드**(대상 이슈 fix 포함 release, `$HOME/CUBRID`). `.answer`는 release(=CI mode) 출력으로 확정, debug는 진단 시에만 (ADR 0005) |
| Q5 | PR 대상 | upstream Draft PR: `CUBRID/cubrid-testcases:develop` ← `tw-kang:tc/cbrd-XXXXX` (ADR 0003) |
| Q6 | 루프 규칙 | 리뷰 통과 후에도 개선·재검증 1회 강제(최소 2회차), 최대 5회차, 미통과 시 스킵+리포트 |
| Q7 | 처리 범위 | run당 기본 1건(대기열 선두), 인자로 N건 또는 이슈 키 지정 |
| Q8 | 브랜치/커밋 | 브랜치 `tc/cbrd-XXXXX`, 커밋 `[CBRD-XXXXX] <영문 요약>` |
| Q9 | Jira 쓰기 | Stage 2까지 읽기 전용 (comment/transition은 Stage 3) |
| R3 | SQL 재현성 기준 | "fix 후 빌드에서 `.answer`가 매회 일치". 확률적 재현(race) 버그도 대상 — 검출력은 별도 속성으로 리뷰에서 평가 (ADR 0004) |

### 검증 환경 — 로컬 CTP, $HOME 표준

환경 배치는 전역 배포 계약 [deployment.md](../../deployment.md) **D7($HOME 런타임 표준)**을 따른다: 신뢰 빌드 `$HOME/CUBRID`(소켓 108자 한계상 짧은 경로), testcases `$TC`(=`$CUBRID_TESTCASES` 오버라이드, 기본 `~/cubrid-testcases`), CTP `$CTP_HOME`(기본 `~/cubrid-testtools/CTP`), env `~/.cubrid-agent/env.sh`(JDK `JAVA_HOME` 포함 — setup 스크립트(`/setup-cubrid-agent`) 생성). CTP 원본 conf가 이미 `${HOME}/cubrid-testcases/sql`·비기본 포트(1822/33120)라 **conf 사본 불필요**.

### 설계 기본값 (이견 시 조정)

- **작업 공간 규약**: 봇은 `$TC`(origin/twkang 리모트)에서 **`tc/cbrd-XXXXX` 브랜치로만** 작업한다 — 사람이 체크아웃한 브랜치에는 커밋하지 않는다. 격리가 필요한 머신은 `CUBRID_TESTCASES`로 별도 clone 지정(deployment.md D7).
- **TC 경로**: `sql/_36_guava/cbrd_XXXXX/{cases,answers}/` — origin/develop에 확립된 guava 컨벤션(corpus 우선).
- **TC 배치**: 루프 중에는 push 없이 `$TC`의 `cases/`에 직접 두고 로컬 CTP로 검증 (ADR 0006). Stage 3에선 `kubectl cp` 주입 (ADR 0001).
- **Review lane 분리**: 리뷰는 작성자와 분리된 fresh-context 서브에이전트가 수행 (self-approve 금지).
- **멱등성**: fork/upstream에 `tc/cbrd-XXXXX` 브랜치 또는 PR이 이미 있으면 처리된 이슈로 간주하고 대기열에서 제외. GitHub이 진실 원천, 로컬 state 파일은 캐시일 뿐.
- **Jira 본문 읽기 경로**: `cubrid-jira jql --output json --fields 'summary,description,comment,...'`만 사용. `search` 서브커맨드의 markdown은 본문이 비는 문제가 있어 정본으로 쓰지 않는다.

## 파이프라인

```
Select ─► Ground ─► ┌── Author ──► Verify ──► Review ──┐ ─► Submit ─► 리포트
                    └───────── 피드백 루프 (2~5회차) ◄──┘
```

### 1. Select — 대상 이슈 선정

1. JQL로 후보 조회 (익명, 인증 불필요):
   ```
   project = CBRD AND cf[213834] = twkang AND cf[210441] = guava
     AND status = Resolved AND cf[210565] in ("Required", "Not Yet")
   ORDER BY resolved ASC
   ```
   (`cf[213834]`=QA Assignee, `cf[210441]`=Planned Version, `cf[210565]`=QA Scenario)
2. 각 후보의 `description`, `comment` 전문을 jql json으로 읽고 판정:
   - **Reproduction 존재**: 문제를 재현하는 구체적 SQL/절차가 본문·댓글에 있는가.
   - **SQL 재현성**: 재현·관측이 SQL문만으로(JDBC/CCI 드라이버로 실행) 가능하고, **fix 후 빌드에서 출력이 매회 일치**하는가(R3). 프로세스 조작·설정 파일 수정·외부 유틸 관측이 필요하면 스킵+사유 기록. 버그 발생이 확률적(race)이어도 fix 후 출력이 결정적이면 적격 — 재발 검출력은 리뷰에서 평가.
   - **중복**: `tc/cbrd-XXXXX` 브랜치/PR 존재, 또는 testcases repo에 `cbrd_xxxxx` TC 기존재 시 스킵.
3. 통과분을 resolved 오래된 순 대기열로 만들고, run 인자(기본 1건)만큼 처리. 처리가능 대기열이 비면 보고하고 중단 — Select 조건 확장은 사용자 결정.

### 2. Ground — 코드 사실 대조

이슈 내용이 단일진실원천이되, 작성 근거를 코드로 보강한다.

- `~/cubrid`(fetch 후 origin/develop 기준)에서 `git log --grep=CBRD-XXXXX`로 fix 커밋/PR을 찾고 merge diff를 읽는다. 필요시 `gh pr view`로 PR 본문·리뷰 보강.
- `$TC`에서 관련 기존 TC·history를 검색해 유사 TC 스타일과 중복 여부를 파악. **커버리지 검색은 cbrd 번호가 아니라 이슈 repro(테이블/쿼리 패턴·기능 영역) 기준으로** — 같은 repro가 이미 다른 이름으로 있을 수 있다. 있으면 중복 대신 차별화(ADR 0009).
- 산출: 재현 시나리오, fix 후 기대 동작, 커버할 케이스 목록 (Author 입력).

### 3. Author — TC 작성

- `$TC`를 origin/develop 최신으로 갱신 후 `tc/cbrd-XXXXX` 브랜치 생성 (재시도 시 기존 브랜치에서 계속).
- `cubrid-sql-tc-create` 스킬 규칙으로 `.sql` 작성: 헤더 블록(`/** CBRD-XXXXX ... Coverage: */`), `evaluate 'Case N: ...'` 섹션, DROP-before-CREATE, 마지막 cleanup.
- `.answer`는 손으로 쓰지 않는다 — Verify가 생성한 `.result`를 승격.

**작성 규칙 (실측으로 확립):**
- **파일 독립성 필수**: 머지 후 CI/regression은 DB를 한 번 만들고 그 안에서 전체 SQL TC를 연속 실행한다. 각 `.sql`이 공유 DB·세션을 오염시키지 않아야 한다 — 모든 `CREATE TABLE` 앞에 `DROP TABLE IF EXISTS`, cleanup에서 만든 것 되돌리기, `prepare` 했으면 `deallocate prepare`.
- **server-message는 반사적으로 쓰지 않는다**: plain SQL 에러 TC는 `Error:-NNN` 코드만 검증(off)이 관례. `--+ server-message on`은 PL/CSQL `DBMS_OUTPUT` 또는 메시지 문구 고정이 필요할 때만(문구 변경에 취약).
- **비결정 출력 회피**: `EXECUTE ... USING {컬렉션}` 결과는 `[Ljava.lang.Integer;@<hash>`로 매회 달라진다 — 스칼라 결과나 에러로 검증.
- **fix 코드 경로를 실제로 타게 하라** (ADR 0009): 결정적 PASS여도 무관 경로를 돌면 무의미. 데이터 크기로 경로를 유도한다(예: 병렬 인덱스 빌드는 `parallelism`≥2 + heap≥`parallel_sort_page_threshold`(2048)일 때만). Verify의 경로 게이트로 확인.
- **기대값은 `.answer`에만**: 주석에도, SQL 판정(`CASE 'OK'/'NOK'`)으로도 두지 않는다. 라벨은 `evaluate 'Case N'` 디렉티브(answer echo).
- **언어**: `.sql` 주석·커밋 메시지는 영문(PR 본문만 한글).

### 4. Verify — 로컬 CTP 검증 (ADR 0006)

전제: **신뢰 빌드**가 `$HOME/CUBRID`에 설치돼 있다. CTP는 **원본 `sql.conf` 그대로** 사용(`$TC`가 비기본이면 사본에 scenario만 덮음). env는 `source ~/.cubrid-agent/env.sh`.

**answer 생성 (핵심 — 비자명)**: CTP 인터랙티브 `run`은 MODE_RESULT라 **`.answer`가 없는 케이스를 스킵**한다(실행조차 안 함 → Total:1 / Success:0 / Fail:0). 새 TC의 answer는 *빈-answer 트릭*으로 만든다:
1. 빈 `answers/cbrd_XXXXX.answer`를 만든다 → 케이스가 실행된다.
2. 실행: `printf "run <sql-abs>\nquit\n" | timeout 900 $CTP_HOME/bin/ctp.sh sql -c $CTP_HOME/conf/sql.conf --interactive`
   → 결과가 `$CTP_HOME/sql/result/<날짜>/schedule_…/sql/cbrd_XXXXX.result`에 저장된다(빈 answer 대비 Fail:1).
3. 그 `.result`를 읽어 의도 부합(에러코드·행수·메시지) 확인 후 `answers/cbrd_XXXXX.answer`로 승격(cp).
4. 재실행 → `Success:1`이면 확정.

**결정성 실측**: 승격 후 최소 2회 더 실행해 매회 `Success:1`인지 확인(N=3). 비결정 토큰이 있으면 해당 케이스를 제거/수정하도록 Author 피드백.

**경로 커버리지 게이트 (ADR 0009)**: 결정성 PASS만으론 부족 — TC가 **fix 코드 경로를 실제로 탔는지** plan/trace(`;plan detail`, `.queryPlan`, `SET TRACE ON`)로 확인한다. config가 경로를 바꿀 수 있다(`test_mode=yes`는 `parallel_sort_page_threshold`를 0으로 강제).

**fail→pass 회귀 계약 (ADR 0007)**: 승격·결정성만으로는 "버그를 실제로 잡는지" 증명이 안 된다. fix **이전** 빌드를 설치해 같은 TC가 **FAIL**함을 실측한다. 결정적 버그는 명확히 FAIL, race 버그는 반복 실행 best-effort + 한계를 리뷰·PR에 명시. **함정(ADR 0009)**: `taskset` ≤2코어는 `system_core_count`(affinity-aware)로 병렬 자체가 disable — **≥4코어**로. pre-fix 빌드를 못 구하면 이슈 Repro/Expected로 근거화하고 리포트에 남긴다.

**CCI 교차 검증**: 같은 `.sql`을 `run_cci`로 재실행, 기본 sql(JDBC) 출력과 다르면 `.answer_cci`. 게이트(결정성·fail→pass·리뷰·CCI·린트)는 hook이 run manifest로 강제한다(`hooks/`).

### 5. Review — 분리 lane 품질 평가

fresh-context 리뷰 서브에이전트에 이슈 본문, fix diff 요약, `.sql`/`.answer`, 검증 로그를 주고 평가:

- 스킬 self-review 체크리스트 (헤더, evaluate 넘버링, cleanup, server-message 페어, 경로 규칙).
- **회귀 가치**: 이 TC가 fix 이전 엔진이라면 실패했을 것인가 (fix 검증력).
- **커버리지**: 이슈의 재현 시나리오와 fix 영향 범위를 충분히 덮는가.
- `.answer` 타당성: 기대값이 이슈가 말하는 "fix 후 동작"과 일치하는가.
- 산출: PASS 또는 수정 요구 목록 (Author 피드백).

### 6. 피드백 루프

- 1회차: Author→Verify→Review.
- 리뷰 결과와 무관하게 피드백 반영 개선→재검증→재리뷰를 1회 이상 수행 (통과했어도 리뷰 코멘트 반영분 1회).
- 2회차 이후 3게이트(작성 완성도·검증 pass·리뷰 PASS) 모두 통과 시 Submit.
- 5회차 미통과: 브랜치는 로컬 보존, 스킵 사유·진단을 리포트에 기록, 다음 이슈로.

### 7. Submit — 커밋·push·PR

- 커밋: `[CBRD-XXXXX] Add SQL testcase for <영문 요약>` + Claude trailer.
- push: `twkang` 리모트(tw-kang/cubrid-testcases)에 `tc/cbrd-XXXXX`.
- PR: `gh pr create --repo CUBRID/cubrid-testcases --base develop --head tw-kang:tc/cbrd-XXXXX --draft`
  - 제목: 영어, `[CBRD-XXXXX]` 헤더. 본문: 한글·사용자 관점, cubrid PR 템플릿 형식(jira 링크 + Purpose/Implementation/Remarks). Remarks에 검증 증거(빌드, 루프 횟수, 결과 요약) 명시.

### 8. 리포트

`~/.cubrid-agent/reports/author-testcase/CBRD-XXXXX.md`: 선정 근거(필드 값·repro 위치), Ground 요약(fix PR/커밋), 루프 회차별 이력(검증 결과·리뷰 지적·반영 내용), 최종 PR 링크 또는 스킵 사유.

## 프로젝트 구조

repo 구조·에이전트 배치의 정본은 [CONTEXT-MAP.md](../../../CONTEXT-MAP.md)(ADR 0008·0012), 배포 자산 계층·런타임 배치($HOME 표준)의 정본은 [deployment.md](../../deployment.md) — 여기 중복하지 않는다.

역할 분담: 메인 세션 = 오케스트레이터(Select·Ground·Verify·Submit 및 루프 제어), Author = `cubrid-sql-tc-create` 스킬 지침을 따르는 실행 lane, Review = 분리된 서브에이전트 lane.

## 후보 판정 현황 (현 필터 기준)

| 이슈 | repro | SQL 재현성 | 처분 |
|---|---|---|---|
| CBRD-25913 (Not Yet) | 있음 (순수 SQL, 기대값=syntax error) | 적격 — 결정적 | 완료 (Draft PR #3041) |
| CBRD-26799 | 있음 (완전한 csql 스크립트+기대값) | 적격 (race — fix 후 결정성 기준) | 완료 (Draft PR #3049) |
| CBRD-26797 | 있음 | 적격 (동일 버그) | 26799에 통합 |
| CBRD-25741 | 있음 | 부적격 — 관측이 `cubrid plandump` 유틸 필요 | 스킵 (plan cache 관측을 SQL로 대체 가능해지면 재검토) |
| CBRD-26213 | 있음 | 부적격 — ulimit·conf 수정·서버 재시작·로그 검사 | 스킵 (shell 카테고리 후보) |
| CBRD-26739 | 있음 (검증 절차) | 부적격 — broker/OS 조작 | 스킵 (shell 카테고리 후보) |
| CBRD-26255 | 없음 | 부적격 | 스킵 |
| CBRD-26701 | 없음 | 부적격 | 스킵 |

→ **처리가능 대기열 0**: 라이브 end-to-end Run은 Select 조건 확장(사용자 결정) 후 가능.

## 리스크 / 유의점

- **검출력 한계**: CBRD-26799 TC는 재발을 확률적으로만 잡는다. Author는 반복 rebuild·데이터 패턴 조정으로 검출력 증폭을 시도하고, 리뷰는 검출력을 평가 항목으로 삼으며, 한계는 PR Remarks에 명시한다 (ADR 0004).
- **대기열 소진**: 현 필터로는 대상이 없다. Select 조건 확장(다른 planned version, 다른 QA Assignee 등)은 사용자와 재논의 사항.
- **로컬 검증 env 재현성**: env는 setup 스크립트(`/setup-cubrid-agent`)가 멱등 수립(`~/.cubrid-agent/env.sh`)하고 `/author-testcase`가 매 run 시작 시 전제를 확인한다.
- **debug/release 차이**: 로컬은 release 단일로 진행하므로, 이슈 재현이 debug assertion에 의존하는 경우에만 `-debug.sh`를 추가 설치한다. `.answer`는 항상 release로 확정.

## 미룬 것 (backlog)

pod·build-cache 마운트 검증(ADR 0001, Stage 3), headless/cron 배포, SQL 외 카테고리(shell 후보: CBRD-26213, 26739), Jira 쓰기(코멘트·`Start Test` 전이), BUILD_SHA 자동 선정, 다건 병렬 처리, Select 조건 확장, fail→pass 소급 실측(CBRD-25913).
