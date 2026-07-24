# 공통 설계 원칙 (cubrid-agent 전역)

모든 에이전트의 설계·구현에 공통 적용되는 원칙. 개별 에이전트 `DESIGN.md`는 이 원칙을 **전제**하고, 각자의 적용 지점만 명시한다. 파이프라인 지도는 [../CONTEXT-MAP.md](../CONTEXT-MAP.md).

## DP1 — 병렬 실행 (동시성·속도)

동시성과 작업 수행 속도 향상을 위해, **순차 의존이 없는 작업 단위는 필요에 따라 병렬로 쪼개 수행한다.** 서브에이전트 fan-out(`parallel`/`pipeline`), 다건 동시 처리를 기본 도구로 삼는다.

에이전트별 병렬화 지점(예):
- **author-testcase**: 다건 이슈 동시 처리, 결정성 N회 반복·pre/post-fix 빌드 검증을 병렬로.
- **review-testcase**: 4개 렌즈(coverage-expansion·answer-vs-spec·determinism-convention·plan-stability)를 독립 서브에이전트로 병렬(perspective-diverse), 다건 PR 병렬, 백테스트 PR별 병렬.
- **gate-resolved**: Handover 풀의 다건 이슈를 동시 검사.
- **test-runner**: 다건 이슈의 회귀 판정 병렬(qaresu 조회는 read-only라 안전).
- **close-backport**: 다건 동시 처리.

**경합 주의(병렬도 제한)**: 공유 자원을 다투는 단위는 병렬도를 낮춘다.
- **읽기/판정**(Jira·qaresu·corpus 조회, 정적 리뷰)은 적극 병렬.
- **쓰기**(PR 생성·Jira 전이/코멘트 게시)는 GitHub/Jira rate limit을 고려해 레이트 분리.
- **로컬 검증**(CTP 포트·pod·DB 경로)은 인스턴스 유니크성이 확보된 만큼만 병렬(포트/인스턴스명/DB경로 충돌 금지).

구현 수단: Claude Code Workflow의 `parallel()`/`pipeline()`, 또는 서브에이전트 동시 spawn. 산출은 합쳐 판정(fan-out → 수렴).

## DP2 — 사용자 관점 · 블랙박스 테스트

TC·테스트 시나리오는 **내부 구현이 아니라 사용자가 관측하는 동작**을 기준으로 작성·평가한다. **여기서 '사용자'는 DBA·DB engineer(전문가)부터 AP(응용) 개발자(비전문가 포함)까지의 스펙트럼**이다 — 전문가 관점은 SQL·csql·쿼리 플랜(SET TRACE)·시스템 카탈로그(db_class 등)·statdump까지, AP 개발자 관점은 드라이버(JDBC/CCI) 입출력·응용 동작까지가 블랙박스 경계 **안**에 든다. **블랙박스 테스트를 원칙으로 한다** — 이들이 관측 가능한 입력 → 출력·동작(결과·에러·메시지·플랜·카탈로그)으로 검증하고, **SQL(JDBC/CCI 드라이버)·표준 유틸로 볼 수 없는 C 내부**(코드 경로·assert·내부 상태·메모리 물리 배치)에는 의존하지 않는다.

**목적**: 회귀 검증에 더해, **DBMS 제품이 필드에서 마주칠 상황을 미리 검출**한다 — AP 개발자(비전문가)가 현장에서 만들 예상외·오사용·엣지 상황까지 TC로 커버한다(coverage-expansion의 negative·경계 케이스와 직결).

에이전트별 적용:
- **author-testcase**: TC/시나리오를 사용자 관점 블랙박스로 작성. SQL(JDBC 드라이버) 입력→출력으로 검증하고, 내부 assert·코드 경로·물리값(page id·offset 등)에 의존하는 TC를 지양.
- **review-testcase**: 화이트박스 의존(내부 상태·구현 세부 단언)을 지적하고, 사용자 관점 시나리오인지 검토(P15 불변식만 단언·환경의존값 회피와 연결).
- **gate-resolved**: test-plannability를 "**사용자 관점 블랙박스로 테스트 플랜을 짤 수 있나**"로 판정. 동작 변화 없는 debug-only assert·내부 리팩터링은 블랙박스 관측 표면이 없어 SQL TC 대상이 아니다(CBRD-26888 사례).

경계(사용자=DBA·DB engineer·AP 개발자 기준):
- **관점 스펙트럼별 관측 수단**: DBA/DB engineer=플랜·카탈로그·statdump(SQL·shell). AP 개발자=드라이버(CCI/JDBC) 입출력·응용 동작. 비전문가적 오사용·예상외 사용도 필드 상황이라 시나리오에 포함한다(negative·엣지).
- 옵티마이저 **플랜/trace·시스템 카탈로그·statdump**는 DBA·DB engineer의 정상 관측 수단이므로 **블랙박스 안**이다(예외가 아님) — review-testcase plan-stability 렌즈가 이를 다룬다.
- 진짜 제외되는 화이트박스는 **SQL(드라이버)·표준 유틸로 관측할 수 없는 C 내부**(코드 경로·assert·메모리 물리 배치)다. 이런 것이 이슈 핵심이면 SQL이 아니라 shell·debug 회귀 등 **적합 러너로 라우팅**한다(카테고리 적합성).
- **카테고리별 관측 수단(확장 예정)**: 블랙박스 표면은 테스트 카테고리마다 다르다. 현재 SQL 카테고리(JDBC/CCI 드라이버 입출력·플랜·카탈로그) 중심이나 **추후 shell·기타 카테고리로 확장**한다 — shell은 서버 프로세스·로그·conf·재시작·OS 상태를 DBA/DB engineer가 관측하므로, **SQL에선 화이트박스인 서버 크래시(예: 26888류)가 shell에선 블랙박스 표면**이 된다. 카테고리 라우팅이 관측 수단을 정한다.

## DP3 — 언어 정책 (배포 대상 영문 · 미배포 한글)

재패키징([ADR 0014](./adr/0014-repackage-as-plugin.md))으로 이 repo가 외부로 나가는 플러그인·스킬이 되면서, 무엇을 영문/한글로 쓸지 규약을 고정한다. **배포 대상(외부·타 CLI·마켓플레이스로 나가는 것)은 영문, 배포 미대상(팀·개발자만 읽는 것)은 한글.**

- **영문(배포 대상)**: 스킬 `SKILL.md`(`name`·`description`·본문·`references/`·`evals/`), 플러그인 매니페스트(`.claude-plugin/`), `hooks/`·`scripts/`, 루트 `README`·`CHANGELOG`·`LICENSE`·`package.json`.
- **한글(배포 미대상)**: `docs/`(ADR·설계·staging·deployment·guides), `AGENTS.md`·`CONTEXT-MAP.md`, Jira(CUBRIDQA) 티켓 본문.
- **예외 (기능적 한글은 유지 — 지시문만 영문)**: 스킬 `description`은 영문 본문이되 **한글 트리거 키워드는 유지**한다 — 팀이 한글로 스킬을 부르므로 트리거 정확도를 확보하기 위함. 예: `… Use whenever someone says "이 PR 리뷰해줘", "gate-resolved 돌려줘", …`. 같은 논리로 아래 세 가지도 한글을 유지하고, 이를 **감싸는 지시문·설명만** 영문으로 쓴다:
  - **eval `prompt`** — 스킬 호출을 흉내 내는 트리거 입력이라 한글 유지(같은 파일의 `expected_output`·`assertions`는 영문).
  - **스킬이 게시하는 산출물 템플릿** — 반송 코멘트·PR 본문·리뷰 초안 등 Jira/GitHub로 나가는 한글 결과물('Jira(CUBRIDQA) 티켓 본문=한글' 규칙의 연장; 영문화하면 한국 개발자에게 영어로 게시하는 동작 변경이 됨).
  - **few-shot으로 인용한 실제 리뷰어 코멘트 원문** — 인용 데이터라 번역하면 인용이 조작된다(원문이 영어면 영어로 둔다).

크로스-CLI 정본(다른 에이전트 도구도 읽는 형태)은 `AGENTS.md`의 "Language policy" 절 — 이 DP는 그 정책을 설계 원칙으로 성문화한 것이다.

## DP4 — 완성 정의: 실제 쓰기 (호출 의도 게이팅)

스킬의 종료 산출물(완성)은 **초안이 아니라 실제 쓰기**다 — Jira 전이·코멘트·필드, GitHub PR 리뷰 코멘트 게시, Draft PR→ready PR. 결정 근거·supersede 범위는 [ADR 0016](./adr/0016-completion-is-real-write.md).

실제 쓰기는 **호출 의도**로 게이팅한다:
- **targeted**(사람이 이슈/PR 키를 나열) → 실제 쓰기. **batch**(스킬이 JQL/큐 쿼리로 집합 생성) → 초안. 개수 무관(JQL 1건도 batch, 나열 3건도 targeted). 판단 기준 = "사람이 특정 이슈/PR에 책임을 졌는가".
- **가드 강등** — targeted여도 오탐 가드(sub-task 형제 커버·의도된 입력 의심·저신뢰)가 걸리면 게시하지 않고 초안+@질의로 강등.
- **감사** — 실제 게시물에 봇 서명, 리포트에 실행된 전이/코멘트의 키·id·시각 기록.

에이전트별 적용:
- **gate-resolved**: 반송(Need Something)·통과(Start Test) 전이 + 반려 코멘트 + QA Scenario 필드를 targeted에서 실제 쓰기.
- **review-testcase**: PR 리뷰 코멘트 게시(`/review-testcase PR-NNNN`=targeted). 승인/머지는 사람.
- **author-testcase**: targeted=ready PR / batch=Draft PR. 머지는 사람, Start Test는 미소유(gate-resolved 소유).

경계:
- **호출 축과 분리** — Stage 2(사람 호출)에서도 완성=실제 쓰기다. 무인 서비스(트리거/cron·self-healing)는 별개 축이라 Stage 3([ADR 0007](./adr/0007-rollout-stages.md)).
- **Stage 3 batch 쓰기**는 이 DP 범위 밖(ADR 0016 Deferred).
- **DP1과 정합** — batch=초안이라 대량 쓰기 storm이 없고, targeted 소량만 실제 쓰기(쓰기 rate 분리 원칙 유지).
