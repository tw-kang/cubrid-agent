<http://jira.cubrid.org/browse/CUBRIDQA-XXXX>

### Purpose

N/A

### Implementation

N/A

### Remarks

N/A

<!--
CUBRID PR 규칙 (CUBRID/cubrid 의 .github/PULL_REQUEST_TEMPLATE.md 와 같은 형식)

- 제목: 영어, `[CUBRIDQA-XXXX]` 로 시작.
- 본문: 한글, **사용자 관점**. "무엇을 적용해서 어떤 동작이 바뀌었다" 이고 코드 구현 설명이 아니다.
  - Purpose        배경과 문제 — 무엇이 잘못되어 있었나, 왜 고치나.
  - Implementation 적용한 것과 그로 인한 동작 변화. 파일·함수 나열이 아니라 바뀐 동작.
  - Remarks        쓰는 사람이 알아야 할 것 — 사용 가이드, 주의, 남은 한계.
- head→base: `<your-fork>:<branch>` → `CUBRID/cubrid-agent:develop`.
- 위 Jira 링크의 `XXXX` 를 실제 티켓 번호로 바꾼다. 티켓은 새로 만들기 전에 CUBRIDQA-1425 트리를
  먼저 확인한다(관련 티켓이 있으면 거기에 코멘트/description 으로 붙인다).
- 커밋 메시지도 `[CUBRIDQA-XXXX]` 로 태깅한다.

머지 전 확인: `bash scripts/check-invariants.sh` 가 통과해야 한다.
자세한 규범은 저장소의 `AGENTS.md` 를 읽어라.
-->
