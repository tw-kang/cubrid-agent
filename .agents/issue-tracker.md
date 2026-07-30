# Issue tracker: CUBRID Jira (CUBRIDQA)

cubrid-agent 자체 개발 작업의 이슈·PRD는 CUBRID Jira의 **`CUBRIDQA`** 프로젝트에 산다(이슈 키 `CUBRIDQA-XXXX`). 생성·조회·수정을 모두 `cubrid-jira` CLI(`~/.local/bin/cubrid-jira`)로 하고, Jira 웹 UI로도 한다(둘 다 유효한 경로).

> 이 트래커는 cubrid-agent **자체를 개발**하는 작업을 담는 곳이다. cubrid-agent의 에이전트들이 **대상으로 삼아 처리**하는 CBRD/CUBRIDQA 이슈(파이프라인 입력)와는 별개다.

관점·내용은 **한글, 사용자 관점**(코드 구현 설명이 아니라 "무엇을 적용해 어떤 동작이 바뀌었다"). 커밋·PR도 `[CUBRIDQA-XXXX]`로 태깅한다.

## CLI 최소 버전 — 2026-07-29 머지분 이상

`cubrid-jira`는 semver를 올리지 않는다(전부 `1.0.0`). 그래서 "최신"은 git HEAD를 뜻하고, 필요한 최소선은 **2026-07-29 머지분**이다. 그 이전 설치본에는 두 가지가 없다:

- **인증 읽기**(PR #3) — 없으면 read를 익명 전송해 CUBRIDQA에서 **HTTP 401**. 공개 프로젝트(CBRD)는 익명 read가 되므로 증상이 CUBRIDQA에서만 난다. 401을 보면 **재시도하지 말 것**(반복 실패는 CAPTCHA 잠금).
- **`attachment` 서브커맨드**(PR #2) — 없으면 스킬이 지시한 명령이 `invalid choice`로 실패.

확인·갱신:

```bash
cubrid-jira attachment --help >/dev/null 2>&1 && echo OK || uv tool upgrade cubrid-jira
```

`attachment`의 존재를 대리 지표로 쓴다 — PR #2와 #3이 30초 차로 머지됐으므로 둘 중 하나만 있는 빌드는 사실상 없다.

**curl REST 직결은 최후 수단**(CLI로 안 되는 것만). 베이스 `http://jira.cubrid.org/rest/api/2`(http — https는 302), `curl --netrc`. 지금 남은 실제 용도는 **sub-task 생성**(`create`에 `--parent`가 없다)뿐이다. 쓰기는 `--yes` 안전판이 없으니 페이로드를 먼저 확인한다.

## 핵심 규약 (`cubrid-jira` CLI)

모든 **쓰기 명령은 기본 dry-run** — 실제 전송하려면 `--yes`가 필수다. 서버 기본값은 `http://jira.cubrid.org`.

- **이슈 생성**: `cubrid-jira create --project CUBRIDQA --type Task --summary "..." [--description-file PATH] [--label ...] [--field "QA Scenario=..."] --yes`
  - 본문(description)은 markdown 파일을 주면 Jira wiki markup으로 변환된다(`--from jira`로 raw 전송 가능). heredoc 대신 파일 경로를 쓴다.
  - 이슈 타입(`--type`)은 프로젝트가 허용하는 값(예: `Task`, `Bug`, `Improvement`) 중 하나.
- **이슈 읽기(단건)**: `cubrid-jira search <KEY>` — 캐시 우선으로 live fetch, markdown을 stdout에 출력. 오프라인은 `--cache-only`.
  - ⚠️ **본문이 빈칸으로 나오면 이슈가 빈 게 아니라 pandoc이 낡은 것이다.** `search`는 description·comment를 `pandoc -f jira`로 렌더하고 cubrid-jira가 그 실패를 검사하지 않아, `jira` reader가 없는 pandoc(RHEL 8 배포판 2.0.6)에서는 **성공 종료 + 빈 본문**이 된다. 확실히 읽어야 하면 pandoc 무관 경로인 `cubrid-jira jql 'key = <KEY>' --fields summary,description,comment,attachment --output json`으로 원문(Jira 마크업)을 직접 본다 — 실제로 이것 때문에 CUBRIDQA-1443의 4664자 본문을 "비어 있다"고 오판한 적이 있다(CUBRIDQA-1473).
- **이슈 목록/검색**: `cubrid-jira jql "<JQL>" [--output json] [--max N] [--fields ...]`
  - 예: `cubrid-jira jql "project = CUBRIDQA AND status != Closed ORDER BY updated DESC" --output json` — 에이전트/jq 파이프용 raw JSON.
- **댓글**: 추가 `cubrid-jira comment <KEY> --body-file PATH --yes` / 목록 `comment-list` / 수정 `comment-update` / 삭제 `comment-delete`.
- **필드 수정**: `cubrid-jira update <KEY> [--summary "..."] [--description-file PATH] [--field FIELD=VALUE] --yes`
  - `--description-file`은 기존 description을 **replace**한다(history엔 남음). `-`로 stdin 입력 가능.
  - `--field`는 커스텀 필드 id(`customfield_210565`) 또는 표시 이름(`"QA Scenario"`) 둘 다 받는다.
- **상태 전이**: `cubrid-jira transition <KEY> --to <이름> --yes` (`--to` 생략 시 가능한 전이 목록 출력).
- **담당자 지정**: `cubrid-jira assign <KEY> --to <username|""> --yes` (`""`는 해제).
- **이슈 링크**: `cubrid-jira link <KEY> --type <Blocks|Cloners|Duplicate|Relates> --to <KEY> --yes`.

## 라벨 주의 (트리아지와 직결)

`cubrid-jira update <KEY> --label ...`는 **라벨 전체 목록을 교체**한다(Jira REST `fields` 시맨틱). 트리아지 라벨 하나를 "추가"하려면 **기존 라벨 + 새 라벨 전부**를 함께 넘겨야 한다. 먼저 `cubrid-jira search <KEY>`(또는 `jql --output json`의 `labels`)로 현재 라벨을 읽고, 원하는 최종 집합을 통째로 `--label`로 전달한다. 개별 add/remove 서브커맨드는 없다.

## 스킬이 "issue tracker에 publish" 하라고 할 때

`cubrid-jira create --project CUBRIDQA ...`로 새 Jira 이슈를 만든다(또는 웹에서 생성).

## 스킬이 "관련 티켓을 fetch" 하라고 할 때

`cubrid-jira search <KEY>`로 읽는다.

## PR을 요청 표면으로 다루는가

**PRs as a request surface: no.** _(cubrid-agent의 이슈는 Jira에서만 다룬다. GitHub PR을 트리아지 큐에 넣고 싶으면 이 플래그를 `yes`로 바꾸고 여기 워크플로를 적는다.)_
