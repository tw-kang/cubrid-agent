# 공통 설계 원칙 (cubrid-agent 전역)

모든 에이전트의 설계·구현에 공통 적용되는 원칙. 개별 에이전트 `DESIGN.md`는 이 원칙을 **전제**하고, 각자의 적용 지점만 명시한다. 파이프라인 지도는 [../CONTEXT-MAP.md](../CONTEXT-MAP.md).

## DP1 — 병렬 실행 (동시성·속도)

동시성과 작업 수행 속도 향상을 위해, **순차 의존이 없는 작업 단위는 필요에 따라 병렬로 쪼개 수행한다.** 서브에이전트 fan-out(`parallel`/`pipeline`), 다건 동시 처리를 기본 도구로 삼는다.

에이전트별 병렬화 지점(예):
- **tc-author**: 다건 이슈 동시 처리, 결정성 N회 반복·pre/post-fix 빌드 검증을 병렬로.
- **tc-reviewer**: 4개 렌즈(coverage-expansion·answer-vs-spec·determinism-convention·plan-stability)를 독립 서브에이전트로 병렬(perspective-diverse), 다건 PR 병렬, 백테스트 PR별 병렬.
- **resolve-gate**: Handover 풀의 다건 이슈를 동시 검사.
- **test-runner**: 다건 이슈의 회귀 판정 병렬(qaresu 조회는 read-only라 안전).
- **close-backport**: 다건 동시 처리.

**경합 주의(병렬도 제한)**: 공유 자원을 다투는 단위는 병렬도를 낮춘다.
- **읽기/판정**(Jira·qaresu·corpus 조회, 정적 리뷰)은 적극 병렬.
- **쓰기**(PR 생성·Jira 전이/코멘트 게시)는 GitHub/Jira rate limit을 고려해 레이트 분리.
- **로컬 검증**(CTP 포트·pod·DB 경로)은 인스턴스 유니크성이 확보된 만큼만 병렬(포트/인스턴스명/DB경로 충돌 금지).

구현 수단: Claude Code Workflow의 `parallel()`/`pipeline()`, 또는 서브에이전트 동시 spawn. 산출은 합쳐 판정(fan-out → 수렴).

## DP2 — 사용자 관점 · 블랙박스 테스트

TC·테스트 시나리오는 **내부 구현이 아니라 사용자가 관측하는 동작**을 기준으로 작성·평가한다. **여기서 '사용자'는 DBA·DB engineer(전문가)부터 AP(응용) 개발자(비전문가 포함)까지의 스펙트럼**이다 — 전문가 관점은 SQL·csql·쿼리 플랜(SET TRACE)·시스템 카탈로그(db_class 등)·statdump까지, AP 개발자 관점은 드라이버(JDBC/CCI) 입출력·응용 동작까지가 블랙박스 경계 **안**에 든다. **블랙박스 테스트를 원칙으로 한다** — 이들이 관측 가능한 입력 → 출력·동작(결과·에러·메시지·플랜·카탈로그)으로 검증하고, **csql·표준 유틸로 볼 수 없는 C 내부**(코드 경로·assert·내부 상태·메모리 물리 배치)에는 의존하지 않는다.

**목적**: 회귀 검증에 더해, **DBMS 제품이 필드에서 마주칠 상황을 미리 검출**한다 — AP 개발자(비전문가)가 현장에서 만들 예상외·오사용·엣지 상황까지 TC로 커버한다(coverage-expansion의 negative·경계 케이스와 직결).

에이전트별 적용:
- **tc-author**: TC/시나리오를 사용자 관점 블랙박스로 작성. csql 입력→출력으로 검증하고, 내부 assert·코드 경로·물리값(page id·offset 등)에 의존하는 TC를 지양.
- **tc-reviewer**: 화이트박스 의존(내부 상태·구현 세부 단언)을 지적하고, 사용자 관점 시나리오인지 검토(P15 불변식만 단언·환경의존값 회피와 연결).
- **resolve-gate**: test-plannability를 "**사용자 관점 블랙박스로 테스트 플랜을 짤 수 있나**"로 판정. 동작 변화 없는 debug-only assert·내부 리팩터링은 블랙박스 관측 표면이 없어 SQL TC 대상이 아니다(CBRD-26888 사례).

경계(사용자=DBA·DB engineer·AP 개발자 기준):
- **관점 스펙트럼별 관측 수단**: DBA/DB engineer=플랜·카탈로그·statdump(SQL·shell). AP 개발자=드라이버(CCI/JDBC) 입출력·응용 동작. 비전문가적 오사용·예상외 사용도 필드 상황이라 시나리오에 포함한다(negative·엣지).
- 옵티마이저 **플랜/trace·시스템 카탈로그·statdump**는 DBA·DB engineer의 정상 관측 수단이므로 **블랙박스 안**이다(예외가 아님) — tc-reviewer plan-stability 렌즈가 이를 다룬다.
- 진짜 제외되는 화이트박스는 **csql·표준 유틸로 관측할 수 없는 C 내부**(코드 경로·assert·메모리 물리 배치)다. 이런 것이 이슈 핵심이면 SQL이 아니라 shell·debug 회귀 등 **적합 러너로 라우팅**한다(카테고리 적합성).
- **카테고리별 관측 수단(확장 예정)**: 블랙박스 표면은 테스트 카테고리마다 다르다. 현재 SQL 카테고리(csql 입출력·플랜·카탈로그) 중심이나 **추후 shell·기타 카테고리로 확장**한다 — shell은 서버 프로세스·로그·conf·재시작·OS 상태를 DBA/DB engineer가 관측하므로, **SQL에선 화이트박스인 서버 크래시(예: 26888류)가 shell에선 블랙박스 표면**이 된다. 카테고리 라우팅이 관측 수단을 정한다.
