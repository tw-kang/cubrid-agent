# cubrid-agent — Agent Instructions

CBRD 이슈 워크플로의 상태 전이를 맡는 에이전트들의 모노레포. 전체 지도·파이프라인·용어는 루트 [`CONTEXT-MAP.md`](./CONTEXT-MAP.md)를 먼저 읽는다.

이 파일은 여러 CLI 에이전트 도구(Claude Code, Codex, Cursor, Gemini 등)가 공유하는 정본이다. `CLAUDE.md`는 이 파일로의 심링크다.

## Language policy — 배포 대상은 영문, 미배포는 한글

배포 대상(외부·타 CLI·마켓플레이스로 나가는 것)은 **영문**, 배포 미대상(팀·개발자만 읽는 것)은 **한글**로 쓴다.

- **영문(배포 대상)**: 스킬 `SKILL.md`(`name`·`description`·본문·`references/`·`evals/`), 플러그인 매니페스트(`.claude-plugin/plugin.json`·`marketplace.json`), `hooks/`·`scripts/`, 루트 `README.md`·`CHANGELOG.md`·`LICENSE`·`package.json`.
- **한글(배포 미대상)**: `docs/`(ADR·설계·staging·deployment), 이 `AGENTS.md`·`CONTEXT-MAP.md`, Jira 티켓(CUBRIDQA) 본문.
- **예외 (기능적 한글 유지)**: 스킬 `description`은 영문으로 쓰되 **한글 트리거 키워드는 유지**한다(팀이 한글로 스킬을 부르므로 트리거 정확도 확보). 예: `… Use when someone says "이 PR 리뷰해줘", "gate-resolved 돌려줘", …`. 같은 이유로 eval의 `prompt`(트리거 입력)와 스킬이 Jira/GitHub에 게시하는 산출물(반송 코멘트·리뷰 초안 등)·few-shot으로 인용한 리뷰어 코멘트 원문도 한글이다 — 감싸는 지시문만 영문. 자세히는 `docs/design-principles.md` DP3.

## Agent skills

### Issue tracker

cubrid-agent 자체 개발 이슈는 CUBRID Jira의 `CUBRIDQA` 프로젝트에서 `cubrid-jira` CLI(및 Jira 웹 UI)로 추적한다. See `docs/agents/issue-tracker.md`.

### Triage labels

다섯 개 정규 역할을 라벨명 그대로 쓴다(기본값 유지). Jira 라벨은 전체 교체 시맨틱이라 적용 시 주의. See `docs/agents/triage-labels.md`.

### Domain docs

다중 컨텍스트 — 루트 `CONTEXT-MAP.md` + 에이전트별 `docs/agents/<name>/CONTEXT.md`. See `docs/agents/domain.md`.
