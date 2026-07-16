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

TC·테스트 시나리오는 **내부 구현이 아니라 사용자가 관측하는 동작**을 기준으로 작성·평가한다. **여기서 '사용자'는 DBA 수준의 DBMS 전문가**다 — SQL·csql·쿼리 플랜(SET TRACE)·시스템 카탈로그(db_class 등)·statdump처럼 DBA가 쓰는 관측 수단이 블랙박스 경계 **안**에 든다(앱 최종사용자 기준보다 넓다). **블랙박스 테스트를 원칙으로 한다** — DBA가 관측 가능한 입력 → 출력·동작(결과·에러·메시지·플랜·카탈로그)으로 검증하고, **DBA가 csql·표준 유틸로 볼 수 없는 C 내부**(코드 경로·assert·내부 상태·메모리 물리 배치)에는 의존하지 않는다.

에이전트별 적용:
- **tc-author**: TC/시나리오를 사용자 관점 블랙박스로 작성. csql 입력→출력으로 검증하고, 내부 assert·코드 경로·물리값(page id·offset 등)에 의존하는 TC를 지양.
- **tc-reviewer**: 화이트박스 의존(내부 상태·구현 세부 단언)을 지적하고, 사용자 관점 시나리오인지 검토(P15 불변식만 단언·환경의존값 회피와 연결).
- **resolve-gate**: test-plannability를 "**사용자 관점 블랙박스로 테스트 플랜을 짤 수 있나**"로 판정. 동작 변화 없는 debug-only assert·내부 리팩터링은 블랙박스 관측 표면이 없어 SQL TC 대상이 아니다(CBRD-26888 사례).

경계(사용자=DBA 기준):
- 옵티마이저 **플랜/trace·시스템 카탈로그·statdump**는 DBA의 정상 관측 수단이므로 **블랙박스 안**이다(예외가 아님) — tc-reviewer plan-stability 렌즈가 이를 다룬다.
- 진짜 제외되는 화이트박스는 **DBA가 관측할 수 없는 C 내부**(코드 경로·assert·메모리 물리 배치)다. 이런 것이 이슈 핵심이면 SQL이 아니라 shell·debug 회귀 등 **적합 러너로 라우팅**한다(카테고리 적합성). 동작 변화 없는 debug-only assert는 SQL TC 대상이 아니다(CBRD-26888).
