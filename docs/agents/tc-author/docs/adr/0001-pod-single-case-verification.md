---
status: PoC 범위에서 ADR 0006(로컬 검증)으로 supersede. 배포 단계에는 유효.
---

# 검증은 sqlmedium pod에서 CTP interactive 단건 실행으로 수행한다

> 적용 범위: **배포 단계(Stage 3)**. PoC/Stage 2 검증은 로컬 CTP(ADR 0006).

기존 `cubrid-sql-tc-verify` 스킬은 빌드 URL을 받아 **로컬 머신에** CUBRID를 설치해 실행하는 설계이고, sqlmedium pod의 entrypoint는 **전체 suite 실행**(수 시간)을 상정한다. 이 봇은 둘 다 따르지 않는다: TC 파일을 `kubectl cp`로 pod에 주입하고, pod 안에서 CTP interactive 모드(`run <file>`)로 **해당 TC만** 실행한다(회당 수 분). 피드백 루프를 이슈당 최대 5회 도는 설계에서 회당 검증 비용이 지배 변수이고, 새 SQL TC는 독립 파일이라 다른 TC를 깨뜨릴 수 없으므로 suite 실행의 이득이 없기 때문이다. verify 스킬의 run→judge→diagnose 절차는 pod 내부 실행으로 이식해 재사용한다.

## Considered Options

- 로컬 설치 후 검증(verify 스킬 원형) — 이 머신에 빌드 설치를 반복해야 하고, 운영 검증 환경(pod)과 어긋난다.
- `/entrypoint.sh test` 전체 suite — 운영과 동일 경로지만 회당 수 시간이라 루프 5회가 비현실적.
- pod에 이슈 브랜치를 clone(BRANCH_TESTCASES 변경) — 매 루프마다 push가 강제되어 WIP 커밋이 양산된다. `kubectl cp` 주입으로 회피.
