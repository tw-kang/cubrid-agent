# jira-resolve-agent — PoC 설계

Resolved 처리된 CBRD 이슈를 읽어 CTP SQL 테스트케이스를 작성·검증·리뷰하고 upstream Draft PR까지 제출하는 agent bot. 용어는 [CONTEXT.md](./CONTEXT.md), 주요 결정 근거는 [docs/adr/](./docs/adr/)를 따른다.

**추적 이슈**: [CUBRIDQA-1429](http://jira.cubrid.org/browse/CUBRIDQA-1429) — PoC 진행 현황을 이슈 description에 지속 반영한다. 원문은 `agents/tc-author/docs/jira/CUBRIDQA-1429-description.jira`에서 관리하고, 갱신은 `cubrid-jira update CUBRIDQA-1429 --description-file agents/tc-author/docs/jira/CUBRIDQA-1429-description.jira --yes`로 수행한다 (CUBRIDQA 프로젝트는 익명 읽기 불가 — 이 파일이 사실상의 사본이다).

**롤아웃 단계**: 이 문서는 Stage 1(PoC) 설계다. Stage 2(팀내 수동 트리거)·Stage 3(무인 자동 서비스) 분류와 외부 핸드오버 문서 정리는 [staging.md](../../docs/staging.md), 근거는 [ADR 0007](../../docs/adr/0007-rollout-stages.md).

## 범위 (PoC)

- **대상 카테고리**: SQL만 (`cubrid-testcases/sql`). shell/medium/CCI 등은 PoC 이후.
- **실행 형태**: Claude Code 프로젝트. 이 디렉토리에서 사람이 세션을 열고 기동 커맨드 한 번으로 전체 파이프라인 실행. headless/cron/webhook 배포는 PoC 이후.
- **Jira는 읽기 전용**. PR 링크·처리 결과는 리포트에만 기록.

## 확정 결정 (grilling 세션)

| # | 결정 사항 | 내용 |
|---|---|---|
| Q1 | 실행 형태 | Claude Code 프로젝트 (오케스트레이터 지침 + 기동 스킬 + 서브에이전트 lane) |
| Q2 | 선정 기준 | QA Scenario ∈ {`Required`, `Not Yet`} ∩ Reproduction 존재 (ADR 0002 — tc_triage 대조 후 Not Yet 포함으로 개정) |
| Q3 | 검증 단위 | sqlmedium pod에서 CTP interactive 단건 실행 (ADR 0001) |
| Q4 | 검증 빌드 | 엔진 `a569a3ee`. 피드백 루프는 debug 빌드 `50f89208...`, Submit 직전 최종 재검증과 `.answer` 확정은 release 빌드 `d67bdd75...` (R1, ADR 0005) |
| Q5 | PR 대상 | upstream Draft PR: `CUBRID/cubrid-testcases:develop` ← `tw-kang:tc/cbrd-XXXXX` (ADR 0003) |
| Q6 | 루프 규칙 | 리뷰 통과 후에도 개선·재검증 1회 강제(최소 2회차), 최대 5회차, 미통과 시 스킵+리포트 |
| Q7 | 처리 범위 | run당 기본 1건(대기열 선두), 인자로 N건 또는 이슈 키 지정 |
| Q8 | 브랜치/커밋 | 브랜치 `tc/cbrd-XXXXX`, 커밋 `[CBRD-XXXXX] <영문 요약>` |
| Q9 | Jira 쓰기 | PoC는 읽기 전용 (comment/transition은 PoC 이후) |

### 리스크 grilling(2차)로 확정된 결정

| # | 결정 사항 | 내용 |
|---|---|---|
| R1 | `.answer` 기준 빌드 | 운영 CI가 release 빌드로 TC를 돌리므로(`build.sh` 기본 mode=release), 루프는 debug로 돌되 **Submit 직전 release 빌드로 최종 재검증하고 `.answer`는 release 출력으로 확정**. 두 빌드 출력이 다르면 리뷰에 보고 (ADR 0005) |
| R2 | throwaway 커밋 | 해소 — `50f89208`/`d67bdd75`는 a569 대비 `.circleci/config.yml`만 변경(각 1~3줄). 엔진 SQL 동작 동일 |
| R3 | SQL 재현성 기준 | "fix 후 빌드에서 `.answer`가 매회 일치"로 정의. 확률적 재현(race) 버그도 대상 — 검출력은 별도 속성으로 리뷰에서 평가 (ADR 0004) |
| R4 | pod 수명 | run마다 봇 전용 pod를 생성하고 종료 시 삭제. 기존 공용 sqlmedium pod는 불가침 |

### tc_triage.md 대조(3차)로 개정된 결정

과거 수동 triage(`~/workspace/jira/tc_triage.md`)와 파이프라인 판정을 대조한 결과, 내용 판단은 전건 일치했으나 QA Scenario=Required 게이트가 최적 후보(CBRD-25913, Not Yet)를 본문 판독 없이 탈락시키고 있었다.

| # | 결정 사항 | 내용 |
|---|---|---|
| T1 | Select 필터 개정 | QA Scenario는 **Not Required만 제외** (Required + Not Yet 포함, ADR 0002 개정). **PoC 1호 = CBRD-25913**(결정적 syntax error 재현, resolved 2025-07-23으로 최고령), **2호 = CBRD-26799** |

### 로컬 전환 (4차) — 구현 착수 시 결정

PoC 검증을 pod 대신 **로컬 CTP 실행**으로 수행하기로 결정(ADR 0006). Q3/Q4의 pod 접근은 **배포 단계로 이연**된다(pod·build-cache 마운트는 그때 사용).

| # | 결정 사항 | 내용 |
|---|---|---|
| L1 | 검증 환경 | 로컬 CTP 단건 실행 (ADR 0006). Q3의 pod interactive를 PoC 범위에서 대체 |
| L2 | 검증 빌드 확보 | `run_cubrid_install <release-url>`로 **`/home/dev/CUBRID` 표준 설치**(사내 빌드서버 `192.168.1.91:8080`). 격리(HOME override) 설치는 소켓 경로 108자 한계로 폐기; jdbc 정리로 위치 확보 (ADR 0006) |
| L3 | 검증 빌드 | release `11.5.0.2300-04192d6` (두 fix 포함). Q4의 pod SHA(a569 계열)를 로컬 URL 빌드로 대체. debug는 진단 시에만 |
| L4 | 작업 위치 | repo clone은 `work/`에 격리(`cubrid`, `cubrid-testcases`, `cubrid-testtools`). CUBRID 설치본은 소켓 한계상 짧은 경로 `/home/dev/CUBRID`. scenario는 PoC conf에서 `work/cubrid-testcases/sql`로 지정 → 사용자 `~/cubrid-testcases` 불가침 유지 |
| L5 | 포트/JDK | CTP sql.conf가 비기본 포트(1822/33120) 사용 → 호스트 무충돌. Java SP 컴파일에 JDK 필요 → `JAVA_HOME`=javac 있는 JDK(예: `/usr/lib/jvm/java-1.8.0-openjdk-…`, jre 하위 아님). (jdbc 인스턴스는 사용자 승인 하 정리됨) |

### 설계 기본값 (인터뷰 없이 확정한 것 — 이견 시 조정)

- **작업 공간 격리**: `~/cubrid-testcases`는 사용자의 수동 작업 공간(현재 다른 브랜치 작업 중)이므로 봇은 절대 건드리지 않는다. 봇 전용 clone을 `work/cubrid-testcases`에 두고 origin(CUBRID)/twkang(tw-kang) 리모트로 운용.
- **TC 경로**: `sql/_36_guava/cbrd_XXXXX/{cases,answers}/` — origin/develop에 확립된 guava 컨벤션 (스킬 문서의 `_13_issues` 경로 대신 corpus 우선).
- **TC 배치**: 루프 중에는 push 없이 `work/cubrid-testcases`의 `cases/`에 직접 두고 로컬 CTP로 검증 (ADR 0006). 배포 단계에선 `kubectl cp` 주입 (ADR 0001).
- **Review lane 분리**: 리뷰는 작성자와 분리된 fresh-context 서브에이전트가 수행 (OMC self-approve 금지 원칙).
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
   - **SQL 재현성**: 재현·관측이 csql SQL문만으로 가능하고, **fix 후 빌드에서 출력이 매회 일치**하는가(R3). 프로세스 조작·설정 파일 수정·외부 유틸 관측이 필요하면 스킵+사유 기록. 버그 발생이 확률적(race)이어도 fix 후 출력이 결정적이면 적격 — 재발 검출력은 리뷰에서 평가.
   - **중복**: `tc/cbrd-XXXXX` 브랜치/PR 존재, 또는 testcases repo에 `cbrd_xxxxx` TC 기존재 시 스킵.
3. 통과분을 resolved 오래된 순 대기열로 만들고, run 인자(기본 1건)만큼 처리.

### 2. Ground — 코드 사실 대조

이슈 내용이 단일진실원천이되, 작성 근거를 코드로 보강한다.

- `~/cubrid`(fetch 후 origin/develop 기준)에서 `git log --grep=CBRD-XXXXX`로 fix 커밋/PR을 찾고 merge diff를 읽는다. 필요시 `gh pr view`로 PR 본문·리뷰 보강.
- `work/cubrid-testcases`에서 관련 기존 TC·history를 검색해 유사 TC 스타일과 중복 여부를 파악.
- 산출: 재현 시나리오, fix 후 기대 동작, 커버할 케이스 목록 (Author 입력).

### 3. Author — TC 작성

- `work/cubrid-testcases`를 origin/develop 최신으로 갱신 후 `tc/cbrd-XXXXX` 브랜치 생성 (재시도 시 기존 브랜치에서 계속).
- `~/skills/cubrid-sql-tc-create` 스킬 규칙으로 `.sql` 작성: 헤더 블록(`/** CBRD-XXXXX ... Coverage: */`), `evaluate 'Case N: ...'` 섹션, DROP-before-CREATE, 마지막 cleanup.
- `.answer`는 손으로 쓰지 않는다 — Verify가 생성한 `.result`를 승격.

**로컬 검증에서 확인한 작성 주의 (CBRD-25913 경험):**
- **파일 독립성 필수**: 머지 후 CI/regression은 DB를 한 번 만들고 그 안에서 전체 SQL TC를 연속 실행한다(테스트마다 DB 생성 아님). 따라서 각 `.sql`이 공유 DB·세션을 오염시키지 않아야 한다 — 모든 `CREATE TABLE` 앞에 `DROP TABLE IF EXISTS`, cleanup에서 만든 것 되돌리기, `prepare` 했으면 cleanup에서 `deallocate prepare <name>`.
- **server-message는 반사적으로 쓰지 않는다**: `--+ server-message on`은 (1) PL/CSQL의 `DBMS_OUTPUT` 출력, (2) `System.xml errorMessage=false`일 때 에러 코드 뒤 **메시지 텍스트**를 붙인다. corpus 사용의 98%가 `_05_plcsql`이고, plain SQL 에러 TC는 대개 `Error:-NNN` 코드만 검증한다(off). 에러 코드만으로 회귀가 잡히면 off가 관례. 메시지 문구까지 고정하려면 on(단 문구 변경에 취약).
- **비결정 출력 회피**: `EXECUTE ... USING {컬렉션}`의 결과는 `[Ljava.lang.Integer;@<hash>`로 렌더되어 매회 달라진다. 컬렉션 값을 결과로 반환하는 케이스는 answer에 부적합 — 스칼라 결과나 에러로 검증.

### 4. Verify — 로컬 CTP 검증 (ADR 0006)

전제: PoC 전용 CUBRID가 `/home/dev/CUBRID`에 설치돼 있다(release `11.5.0.2300-04192d6`, 두 fix 포함). CTP는 sql.conf에서 비기본 포트(1822/33120)를 써 호스트와 충돌하지 않는다. env:
```
export HOME=/home/dev; source /home/dev/.cubrid.sh          # CUBRID=/home/dev/CUBRID
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-…          # JDK(javac 포함), jre 아님 — Java SP 컴파일용
export CTP_HOME=<abs>/work/cubrid-testtools/CTP
```
PoC용 conf `work/sql.poc.conf` = CTP `sql.conf`의 `scenario`를 `work/cubrid-testcases/sql`로 덮어쓴 사본(사용자 `~/cubrid-testcases` 불가침).

**answer 생성 (핵심 — 비자명)**: CTP 인터랙티브 `run`은 MODE_RESULT라 **`.answer`가 없는 케이스를 스킵**한다(실행조차 안 함 → Total:1 / Success:0 / Fail:0). 새 TC의 answer는 *빈-answer 트릭*으로 만든다:
1. 빈 `answers/cbrd_XXXXX.answer`를 만든다 → 케이스가 실행된다.
2. 실행: `printf "run <sql-abs>\nquit\n" | timeout 900 $CTP_HOME/bin/ctp.sh sql -c work/sql.poc.conf --interactive`
   → 결과가 `$CTP_HOME/sql/result/<날짜>/schedule_…/sql/cbrd_XXXXX.result`에 저장된다(빈 answer 대비 Fail:1).
3. 그 `.result`를 읽어 의도 부합(에러코드·행수·메시지) 확인 후 `answers/cbrd_XXXXX.answer`로 승격(cp).
4. 재실행 → `Success:1`이면 확정.

**결정성 실측**: 승격 후 최소 2회 더 실행해 매회 `Success:1`인지 확인(= 출력이 answer와 매회 일치, 비교는 개행 무시). 비결정 토큰이 있으면 해당 케이스를 제거/수정하도록 Author 피드백. **알려진 함정**: `EXECUTE … USING {컬렉션}`의 결과가 `[Ljava.lang.Integer;@<hash>`처럼 Java 객체 해시로 렌더되어 매회 달라진다 → 컬렉션 값을 결과로 반환하는 케이스는 피한다(스칼라/에러로 검증).

**fail→pass 회귀 계약 (PoC부터, ADR 0007)**: 승격·결정성 확인만으로는 "버그를 실제로 잡는지"가 증명되지 않는다. fix **이전** 빌드(fix commit의 부모 또는 그 직전 빌드서버 산출물)를 설치해 같은 TC를 돌려 **FAIL**함을 실측한다 — fix 후 PASS와 합쳐 fail→pass를 증명. 결정적 버그는 명확히 FAIL, race 버그는 반복 실행 best-effort로 FAIL을 관측하고 한계를 리뷰·PR에 명시. pre-fix 빌드를 못 구하면 이슈 Repro/Expected로 pre-fix 동작을 근거화하고 그 사실을 리포트에 남긴다.

`.answer`는 release 빌드(=CI mode) 출력으로 확정된다. debug 진단이 필요하면 같은 버전 `-debug.sh`를 추가 설치해 병행 확인한다(ADR 0006). CCI 교차 검증(`run_cci`/`.answer_cci`)과 게이트의 hook 강제는 Stage 2부터 적용한다(ADR 0007). 배포 단계에서는 이 절차를 pod 내부 실행으로 이식한다(ADR 0001).

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
  - 제목: 영어, `[CBRD-XXXXX]` 헤더.
  - 본문: 한글·사용자 관점, cubrid PR 템플릿 형식(jira 링크 + Purpose/Implementation/Remarks). Remarks에 검증 증거(BUILD_SHA, pod, 루프 횟수, 결과 요약) 명시.

### 8. 리포트

`reports/CBRD-XXXXX.md`: 선정 근거(필드 값·repro 위치), Ground 요약(fix PR/커밋), 루프 회차별 이력(검증 결과·리뷰 지적·반영 내용), 최종 PR 링크 또는 스킵 사유.

## 프로젝트 구조 (구현 시)

```
jira-resolve-agent/
├── CLAUDE.md                     # 오케스트레이터 지침: 파이프라인 규칙·게이트·금지사항
├── CONTEXT.md                    # 도메인 용어 (완료)
├── DESIGN.md                     # 이 문서
├── docs/adr/                     # 결정 기록 (0001~0006 완료)
├── docs/jira/                    # CUBRIDQA-1429 description 사본 (지속 갱신)
├── .claude/skills/
│   └── resolve-next/SKILL.md     # 기동 커맨드: /resolve-next [N | CBRD-XXXXX]
├── work/                         # 봇 전용 (gitignore) — 준비 완료
│   ├── cubrid/                   #   엔진 clone (Ground: fix diff)
│   ├── cubrid-testcases/         #   TC clone (origin=CUBRID, twkang=fork)
│   ├── cubrid-testtools/         #   CTP
│   └── sql.poc.conf              #   scenario→work/cubrid-testcases 로 덮어쓴 CTP conf
└── reports/                      # run 리포트 (커밋 여부는 구현 시 결정)

# CUBRID 검증 빌드: /home/dev/CUBRID (release 11.5.0.2300-04192d6, 소켓 경로 한계로 짧은 경로 필수)
```

역할 분담: 메인 세션 = 오케스트레이터(Select·Ground·Verify·Submit 및 루프 제어), Author = `cubrid-sql-tc-create` 스킬 지침을 따르는 실행 lane, Review = 분리된 서브에이전트 lane.

## 후보 판정 현황 (2026-07-06 전수 판독 + tc_triage.md 대조)

Required+Not Yet 8건의 본문·댓글 판독 결과 (과거 수동 triage `~/workspace/jira/tc_triage.md`와 내용 판단 전건 일치 확인):

| 이슈 | repro | SQL 재현성 | 처분 |
|---|---|---|---|
| CBRD-25913 (Not Yet) | 있음 (q-1~q-6 순수 SQL, 기대값=syntax error) | 적격 — 결정적, 검출력 100% | **PoC 1호 대상** |
| CBRD-26799 | 있음 (완전한 csql 스크립트+기대값) | 적격 (race — fix 후 결정성 기준) | **PoC 2호 대상** |
| CBRD-26797 | 있음 | 적격 (동일 버그) | 26799에 통합 |
| CBRD-25741 | 있음 | 부적격 — 관측이 `cubrid plandump` 유틸 필요 | 스킵 (plan cache 관측을 SQL로 대체 가능해지면 재검토) |
| CBRD-26213 | 있음 | 부적격 — ulimit·conf 수정·서버 재시작·로그 검사 | 스킵 (shell 카테고리 후보) |
| CBRD-26739 | 있음 (검증 절차) | 부적격 — broker/OS 조작 | 스킵 (shell 카테고리 후보) |
| CBRD-26255 | 없음 | 부적격 | 스킵 |
| CBRD-26701 | 없음 | 부적격 | 스킵 |

## 리스크 / 유의점 (2차 grilling 후 잔여분)

- **검출력 한계**: CBRD-26799 TC는 재발을 확률적(~6%/회)으로만 잡는다. Author는 반복 rebuild·데이터 패턴 조정 등으로 검출력 증폭을 시도하고, 리뷰는 검출력을 평가 항목으로 삼으며, 한계는 PR Remarks에 명시한다 (ADR 0004).
- **대기열 소진**: 25913·26799 처리 후 현 필터로는 대상이 없다. Select 조건 확장(다른 planned version, 다른 QA Assignee 등)은 사용자와 재논의 사항.
- **로컬 검증 env 재현성**: 검증은 `work/cubrid-rel`의 격리 설치본 + `HOME`/`CTP_HOME`/`JAVA_HOME`/scenario 심링크 env에 의존한다. 이 env 구성은 `/resolve-next` 스킬이 매 run 시작 시 멱등하게 재수립해야 한다(스킬 구현 항목).
- **debug/release 차이**: 로컬은 release 단일로 진행하므로, 이슈 재현이 debug assertion에 의존하는 경우에만 `-debug.sh`를 추가 설치한다. `.answer`는 항상 release로 확정.

## PoC 이후로 미룬 것

배포 형태(headless/cron/webhook), **pod·build-cache 마운트 검증(ADR 0001 — 로컬 대신 배포 단계)**, SQL 외 카테고리(shell 후보: CBRD-26213, 26739), Jira 쓰기(코멘트·전이), BUILD_SHA 자동 선정(최신 develop 추적), 다건 병렬 처리, Select 조건 확장.
