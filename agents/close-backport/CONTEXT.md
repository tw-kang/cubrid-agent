# close-backport (Tested → Closed / Backport)

**상태: 설계 전 (grilling 미실시).**

역할: Tested 상태 이슈를 종결(Closed)하거나 백포트로 넘기는 작업을 하는 에이전트.

이 디렉토리에 이 에이전트의 grilling 산출물(용어 `CONTEXT.md`, `DESIGN.md`, `docs/adr/`, `reports/`)을 둔다. 파이프라인 맥락은 [../../CONTEXT-MAP.md](../../CONTEXT-MAP.md), 공유 롤아웃 모델은 [../../docs/staging.md](../../docs/staging.md).

## 설계 전 인계 메모

- **회귀 무결(스위트 전체 영향) 확인은 여기로 이관됨** (test-runner D5). test-runner는 "내 신규 TC가 회귀에서 사는가"만 보고, "내 머지가 다른 TC를 깼는가"는 안 본다 → close 전에 close-backport가 판정해야 한다. 재료는 test-runner와 같은 qaresu `resultstat`의 `fail_scenario` baseline 증가분 중 **내 TC가 아닌 신규 실패**([../test-runner/DESIGN.md](../test-runner/DESIGN.md) close-backport 관계 절, [../test-runner/docs/adr/0010-verdict-source-and-baseline-delta.md](../test-runner/docs/adr/0010-verdict-source-and-baseline-delta.md)).
