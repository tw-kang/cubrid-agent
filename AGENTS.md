# cubrid-agent — Agent Instructions

CBRD 이슈 워크플로의 상태 전이를 맡는 에이전트들의 모노레포. 전체 지도·파이프라인·용어는 루트 [`CONTEXT.md`](./CONTEXT.md)를 먼저 읽는다.

이 파일은 여러 CLI 에이전트 도구(Claude Code, Codex, Cursor, Gemini 등)가 공유하는 정본이다. `CLAUDE.md`는 이 파일로의 심링크다.

## 개발 방식 — 이 repo를 고칠 때 지키는 두 가지

clone해서 개발하는 사람도 대개 AI 에이전트로 작업한다. 그래서 방식을 여기 적는다 — 이 파일이 어떤 CLI 도구에서든 가장 먼저 읽히는 정본이기 때문이다.

- **코드로 가능한 것은 최대한 코드로, LLM은 판단에 쓴다.** 기계적으로 결정되는 일(분류·추출·규칙 검사·카운팅·상태 기록)은 `scripts/`·`hooks/`가 하고, 스킬 산문은 판단만 담는다. 새 규칙을 스킬에 적기 전에 **"훅이나 스크립트가 이걸 판정할 수 있나"를 먼저 묻는다** — 할 수 있으면 코드로 옮기고 스킬엔 한 줄만 남긴다. 근거(TC 1건 62분의 원인)와 코드/LLM 경계표는 `.agents/design-principles.md` DP6.
- **변경은 스킬 체인으로 굴린다**: `/grill-with-docs` → `/to-spec` → `/to-tickets` → `/implement`(안에서 `/tdd`) → `/code-review`. 한 세션에 담기는 작은 변경은 `/to-spec`·`/to-tickets`를 건너뛰고 `/implement`로 바로 가도 되지만, **`/implement`는 항상 `/code-review`(Standards+Spec 2축)로 닫는다**. 여러 세션짜리면 `/to-tickets`까지를 **한 컨텍스트 안에서** 끝낸다(중간에 compact하면 spec과 티켓이 다른 사고 위에 얹힌다). 티켓은 CUBRIDQA — 아무 때나 새로 만들지 말고 `CUBRIDQA-1425` 트리(sub-task·related)를 먼저 확인해 관련 티켓에 코멘트/description으로 붙인다(`.agents/issue-tracker.md`). 이 스킬들은 이 repo가 아니라 개인 `~/.claude/skills`에 있다 — 없으면 `/setup-matt-pocock-skills`, 어떤 걸 쓸지 모르면 `/ask-matt`.

## Language policy — 배포 대상은 영문, 미배포는 한글

배포 대상(외부·타 CLI·마켓플레이스로 나가는 것)은 **영문**, 배포 미대상(팀·개발자만 읽는 것)은 **한글**로 쓴다.

- **영문(배포 대상)**: 스킬 `SKILL.md`(`name`·`description`·본문·`references/`·`evals/`), 플러그인 매니페스트(`.claude-plugin/plugin.json`·`marketplace.json`), `hooks/`·`scripts/`, 루트 `README.md`·`CHANGELOG.md`·`LICENSE`·`package.json`.
- **한글(배포 미대상)**: `docs/`(런북·참조), `.agents/`(규범·thin ADR), 이 `AGENTS.md`·`CONTEXT.md`, Jira 티켓(CUBRIDQA) 본문.
- **예외 (기능적 한글 유지)**: 스킬 `description`은 영문으로 쓰되 **한글 트리거 키워드는 유지**한다(팀이 한글로 스킬을 부르므로 트리거 정확도 확보). 예: `… Use when someone says "이 PR 리뷰해줘", "gate-resolved 돌려줘", …`. 같은 이유로 eval의 `prompt`(트리거 입력)와 스킬이 Jira/GitHub에 게시하는 산출물(반송 코멘트·리뷰 초안 등)·few-shot으로 인용한 리뷰어 코멘트 원문도 한글이다 — 감싸는 지시문만 영문. 자세히는 `.agents/design-principles.md` DP3.

## Agent skills

### Issue tracker

cubrid-agent 자체 개발 이슈는 CUBRID Jira의 `CUBRIDQA` 프로젝트에서 `cubrid-jira` CLI(및 Jira 웹 UI)로 추적한다. See `.agents/issue-tracker.md`.

### Triage labels

다섯 개 정규 역할을 라벨명 그대로 쓴다(기본값 유지). Jira 라벨은 전체 교체 시맨틱이라 적용 시 주의. See `.agents/triage-labels.md`.

### Domain docs

다중 컨텍스트 — 루트 `CONTEXT.md`(단일 용어집; 에이전트별 CONTEXT는 Jira로 흡수). See `.agents/domain.md`.
