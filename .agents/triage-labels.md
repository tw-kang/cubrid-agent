# Triage Labels

스킬은 다섯 개의 정규 트리아지 역할로 말한다. 이 파일은 그 역할을 이 repo 트래커(CUBRIDQA Jira)에서 실제로 쓰는 라벨 문자열에 매핑한다. 기본값 유지 — 라벨 문자열은 역할 이름과 동일하다.

| Label in mattpocock/skills | Label in our tracker | 뜻                                   |
| -------------------------- | -------------------- | ------------------------------------ |
| `needs-triage`             | `needs-triage`       | 메인테이너가 이 이슈를 판단해야 함    |
| `needs-info`               | `needs-info`         | 리포터의 추가 정보 대기              |
| `ready-for-agent`          | `ready-for-agent`    | 완전히 명세됨, AFK 에이전트 투입 가능 |
| `ready-for-human`          | `ready-for-human`    | 사람 구현이 필요                     |
| `wontfix`                  | `wontfix`            | 처리하지 않음                        |

스킬이 역할을 언급하면(예: "AFK-ready 트리아지 라벨을 붙여라") 이 표의 오른쪽 라벨 문자열을 쓴다.

## Jira 라벨 적용 주의

이 트래커는 Jira다. `cubrid-jira update <KEY> --label ...`은 라벨 하나를 추가하는 게 아니라 **전체 목록을 교체**한다 — 그래서 트리아지 라벨을 붙이는 일이 기존 라벨을 지우는 일이 될 수 있다. 절차(현재 라벨을 먼저 읽는 방법, 개별 add/remove가 없다는 점)는 [`issue-tracker.md`](./issue-tracker.md)의 "라벨 주의" 절 하나에만 둔다.

오른쪽 열은 실제로 쓰는 라벨 어휘에 맞게 편집하면 된다.
