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
