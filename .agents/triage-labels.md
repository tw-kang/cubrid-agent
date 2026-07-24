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

이 트래커는 Jira다. 라벨은 `cubrid-jira update <KEY> --label ... --yes`로 붙이는데, `--label`은 **라벨 전체 목록을 교체**한다. 트리아지 라벨 하나만 추가하려 해도 **기존 라벨 전부 + 새 라벨**을 함께 넘겨야 한다(안 그러면 기존 라벨이 지워진다). 먼저 `cubrid-jira search <KEY>`로 현재 라벨을 읽고 최종 집합을 통째로 전달할 것. 자세한 규약은 `issue-tracker.md` 참조.

오른쪽 열은 실제로 쓰는 라벨 어휘에 맞게 편집하면 된다.
