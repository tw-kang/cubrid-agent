# Issue tracker: CUBRID Jira (CUBRIDQA)

cubrid-agent 자체 개발의 스펙·PRD는 CUBRID Jira의 **`CUBRIDQA`** 프로젝트에 산다(이슈 키 `CUBRIDQA-XXXX`). **작업 티켓은 이 repo의 GitHub Issues에 산다.** Jira 쪽 생성·조회·수정은 모두 `cubrid-jira` CLI(`~/.local/bin/cubrid-jira`)로 하고, Jira 웹 UI로도 한다(둘 다 유효한 경로).

> 이 트래커는 cubrid-agent **자체를 개발**하는 작업을 담는 곳이다. cubrid-agent의 에이전트들이 **대상으로 삼아 처리**하는 CBRD/CUBRIDQA 이슈(파이프라인 입력)와는 별개다.

관점·내용은 **한글, 사용자 관점**(코드 구현 설명이 아니라 "무엇을 적용해 어떤 동작이 바뀌었다"). PR·커밋 제목의 태깅 규약은 [`AGENTS.md`](../AGENTS.md)의 "변경을 내보낼 때" 절에 있다.

## 티켓 구조 — 기본은 "새로 만들지 않는다"

부모는 **[CUBRIDQA-1425](http://jira.cubrid.org/browse/CUBRIDQA-1425)**("cubrid-agent for qa dev process"). 이 repo의 Jira 티켓은 전부 그 아래로 붙는다. 그 트리가 이미 **31건**이다(2026-07-31: sub-task 18 + 관련 Task 12 + 부모). 티켓이 늘어난 것 자체가 문제이므로 **새로 만드는 경우는 아래 둘뿐**이고, 둘은 서로 다른 트래커에 산다.

| 만드는 것 | 어디에 | 무엇 한 건당 | 어떻게 |
|---|---|---|---|
| **스펙** | Jira sub-task | `/to-spec` 산출물 = **스펙 한 건**. 작업 단위가 아니다 | `create`에 `--parent`가 없다 → 아래 "curl REST 직결은 최후 수단" |
| **작업 티켓** | GitHub Issue | `/to-tickets` 산출물 = **처리할 작업 한 건** | `gh issue create`. 본문에 그 스펙 sub-task의 Jira 키를 링크한다 |

작업 티켓이 GitHub으로 간 근거는 [ADR 0008](adr/0008-branch-model-prs-and-work-tickets.md)에 있다.

**Jira에 새로 남길 그 밖의 모든 것은 기존 티켓에 붙인다.** 만들기 전에 트리를 먼저 읽는다:

```bash
cubrid-jira jql 'key = CUBRIDQA-1425 OR parent = CUBRIDQA-1425 OR issue in linkedIssues(CUBRIDQA-1425) ORDER BY key' \
  --fields summary,issuetype,status --output json
```

- 관련 티켓이 있으면 **코멘트**로 남긴다(`comment --body-file`).
- 그 티켓이 **말하는 내용 자체가 달라졌으면** description을 고친다(`update --description-file` — replace, 아래 참조).
- 어디에 붙일지 애매하면 만들지 말고 **CUBRIDQA-1491**(기여 규범·프로젝트 룰, 상시)에 코멘트한다.

기존 sub-task 18건은 이 규칙보다 먼저 만들어져 작업 단위가 섞여 있다. **재분류하지 않는다** — 새로 만들 때만 이 규칙을 따른다. CUBRIDQA에 이미 있는 Task 12건도 같다 — GitHub으로 옮기지 않고, 새 작업 티켓만 GitHub에 만든다.

## 이슈에 무엇을 남기나 — 열고 30초에 알 수 있게

**이슈는 읽는 사람이 지금 무엇을 알아야 하는지를 담는다. 어떻게 알아냈는지는 담지 않는다.**

설계가 이슈에 사는 것은 결정이다(repo는 제품을, 설계는 Jira가 보관 — CUBRIDQA-1454). 그러니 **분량을 줄이는 게 목표가 아니라 읽는 순서를 주는 게 목표**다. 아래 넷은 실측에서 나온 세 가지 실패를 각각 겨냥한다.

### 1. 자리 — 같은 사실을 두 곳에 두지 않는다

| 자리 | 담는 것 | 담지 않는 것 |
|---|---|---|
| **description** | **지금 참인 것만** — 문제, 결정, 현재 스펙 | 시각이 붙는 것(실측·실행 결과·"…시점 스냅샷"), 정정 이력 |
| **comment** | 시각이 붙는 것 — 실측, 실행 결과, 무엇을 왜 바꿨는지 | 다음에도 참일 결정(그건 description으로 올린다) |
| **repo** (커밋 메시지·`docs/`) | 근거, 측정 원자료, 대안 검토 | — |

description에 날짜가 붙은 절이 생겼다면 그건 코멘트 자리다.

### 2. 리드 — 첫 15줄 안에 셋을 답한다

description 맨 위에 **무엇이 문제인가**(1~2문장) · **지금 상태**(한 줄) · **다음 행동**(한 줄). 그 아래로는 얼마든지 길어도 된다 — 읽는 사람이 접고 내려갈 수 있으면 길이는 비용이 아니다. 리드가 없으면 13개 절을 다 읽어야 상태를 안다.

### 3. 주제당 정본 코멘트 하나 — 새로 달지 말고 그 코멘트를 고친다

같은 주제로 두 번째 코멘트를 달지 않는다. 첫 코멘트가 그 주제의 **정본**이고, 이후는 `comment-update --id <ID>`로 그 본문을 갱신한다. 정본 코멘트는 첫 줄에 그렇게 밝힌다:

```
h3. {anchor:<주제>-이-주제-통합}<주제> — <한 줄 요약> (YYYY-MM-DD, 이 주제 통합)
이 코멘트가 <주제>의 정본이다. 이전에 나뉘어 있던 코멘트는 여기로 합쳤다.
```

갱신은 **replace**이므로 기존 본문을 먼저 읽어 뒤에 이어 붙인다. 쓰기 전에 dry-run 출력의 앞부분이 원본과 바이트 단위로 같은지 확인한다(`comment-list <KEY> --output json | jq -r '.comments[] | select(.id=="<ID>") | .body'`).

### 4. 정정은 덧붙이지 말고 그 자리를 고친다

description이 틀렸으면 **틀린 문장을 고친다**. "정정(날짜)" 절을 아래에 붙이지 않는다 — Jira가 history를 보관하므로 원래 문장은 사라지지 않는다. 무엇을 왜 고쳤는지는 코멘트에 한 줄 남긴다.

### 분량 — 목표가 아니라 신호

**description 6,000자를 넘으면 리드가 있는지 다시 본다.** 2026-08-05 실측(19건, 합 93,181자): 13건이 6,000자 이하로 중앙값 2,004자인데, 넘는 6건이 전체 분량의 **65%** 를 차지한다(최대 15,021자). 즉 길이 자체보다 **몇 건에 몰리는 것**이 신호다. 다시 재려면 — **문자 수로 센다. 한글은 1자가 3바이트라 `wc -c`는 세 배로 부푼다**:

```bash
cubrid-jira jql 'key = CUBRIDQA-1425 OR parent = CUBRIDQA-1425 ORDER BY key' --fields description --output json \
  | jq -r '.issues[] | "\(.key)\t\(.fields.description // "" | length)"'
```

## CLI 버전 — 최소선 2026-07-29, 권장 최신

`cubrid-jira`는 semver를 올리지 않는다(전부 `1.0.0`). 그래서 "최신"은 git HEAD를 뜻한다.

**최소선 = 2026-07-29 머지분.** 그 이전 설치본은 스킬이 지시한 대로 **동작하지 않는다**:

- **인증 읽기**(PR #3) — 없으면 read를 익명 전송해 CUBRIDQA에서 **HTTP 401**. 공개 프로젝트(CBRD)는 익명 read가 되므로 증상이 CUBRIDQA에서만 난다. 401을 보면 **재시도하지 말 것**(반복 실패는 CAPTCHA 잠금).
- **`attachment` 서브커맨드**(PR #2) — 없으면 스킬이 지시한 명령이 `invalid choice`로 실패.

**권장 = 그냥 최신.** 2026-07-30에 아래 두 건이 두 시간 간격으로 머지됐으므로 "07-30 머지분"이라는 표현은 둘을 구분하지 못한다 — 날짜로 고르지 말고 `uv tool upgrade`로 올린다. 없어도 정상 경로는 돌지만, 조용히 틀리는 경우가 남는다:

- **pandoc 읽기 폴백**(PR #4) — 낡은 pandoc에서 이슈 본문이 빈칸이 되는 대신 경고 한 줄 + Jira 마크업 원문으로 나온다. 아래 `search` 경고 참조.
- **읽기·첨부 하드닝**(PR #5) — ① 401이 **첫 시도에서 멈춘다**(그 전에는 관련 이슈마다 재전송해 한 번의 `search`가 여러 번의 인증 실패가 됐다 — CAPTCHA 잠금의 실제 원인이었다) ② 서버가 알려준 크기를 못 믿고 **받은 바이트로** 5MiB 상한을 걸어 초과분이 디스크에 남지 않는다 ③ 첨부 파일명을 basename으로 정리해 경로 탈출을 막고 중복 이름에 `-<id>`를 붙인다 ④ 인증 없이도 공개 이슈 첨부를 받는다.

확인·갱신:

```bash
cubrid-jira attachment --help >/dev/null 2>&1 && echo OK || uv tool upgrade cubrid-jira   # 최소선 확인
uv tool upgrade cubrid-jira                                                              # 권장: 그냥 최신으로
```

최소선 확인에 `attachment`의 존재를 대리 지표로 쓴다 — PR #2와 #3이 30초 차로 머지됐으므로 둘 중 하나만 있는 빌드는 사실상 없다.

**curl REST 직결은 최후 수단**(CLI로 안 되는 것만). 베이스 `http://jira.cubrid.org/rest/api/2`(http — https는 302), `curl --netrc`. 지금 남은 실제 용도는 **sub-task 생성**(`create`에 `--parent`가 없다)뿐이다. 쓰기는 `--yes` 안전판이 없으니 페이로드를 먼저 확인한다.

## 핵심 규약 (`cubrid-jira` CLI)

모든 **쓰기 명령은 기본 dry-run** — 실제 전송하려면 `--yes`가 필수다. 서버 기본값은 `http://jira.cubrid.org`.

- **이슈 생성**: `cubrid-jira create --project CUBRIDQA --type Task --summary "..." [--description-file PATH] [--label ...] [--field "QA Scenario=..."] --yes`
  - 본문(description)은 markdown 파일을 주면 Jira wiki markup으로 변환된다(`--from jira`로 raw 전송 가능). heredoc 대신 파일 경로를 쓴다.
  - 이슈 타입(`--type`)은 프로젝트가 허용하는 값(예: `Task`, `Bug`, `Improvement`) 중 하나.
- **이슈 읽기(단건)**: `cubrid-jira search <KEY>` — 캐시 우선으로 live fetch, markdown을 stdout에 출력. 오프라인은 `--cache-only`.
  - ⚠️ **본문이 빈칸으로 나오면 이슈가 빈 게 아니라 pandoc이 낡은 것이다.** `search`는 description·comment를 `pandoc -f jira`로 렌더한다. `jira` reader가 없는 pandoc(RHEL 8 배포판 2.0.6)에서 **2026-07-29 이전 설치본은 성공 종료 + 빈 본문**을 낸다 — 실제로 이것 때문에 CUBRIDQA-1443의 4664자 본문을 "비어 있다"고 오판한 적이 있다(CUBRIDQA-1473). 2026-07-30 이후 설치본(PR #4)은 `Warning: pandoc cannot convert Jira wiki markup …`을 stderr에 한 번 찍고 **원문을 그대로** 내보낸다. **에이전트가 읽을 때는 버전에 관계없이** pandoc 무관 경로인 `cubrid-jira jql 'key = <KEY>' --fields summary,description,comment,attachment --output json`을 쓴다(CUBRIDQA-1478).
- **이슈 목록/검색**: `cubrid-jira jql "<JQL>" [--output json] [--max N] [--fields ...]`
  - 예: `cubrid-jira jql "project = CUBRIDQA AND status != Closed ORDER BY updated DESC" --output json` — 에이전트/jq 파이프용 raw JSON.
- **첨부 다운로드**: `cubrid-jira attachment <KEY> --output json` — 전부 받고 파일별 매니페스트를 한 줄 JSON으로 출력(`--list`는 메타데이터만). 기본 저장 위치는 `~/.local/share/cubrid-jira/attachments/<KEY>/`(`$CUBRID_JIRA_DIR`가 있으면 그 아래, `--out DIR`로 지정 가능)이고, 각 항목의 `path`가 실제 경로다. 5MiB 초과는 받지 않고 `skipped` 사유만 남긴다 — 코어·바이너리가 디스크에 쌓이지 않는다.
- **댓글**: 추가 `cubrid-jira comment <KEY> --body-file PATH --yes` / 목록 `comment-list` / 수정 `comment-update` / 삭제 `comment-delete`.
- **필드 수정**: `cubrid-jira update <KEY> [--summary "..."] [--description-file PATH] [--field FIELD=VALUE] --yes`
  - `--description-file`은 기존 description을 **replace**한다(history엔 남음). `-`로 stdin 입력 가능.
  - ⚠️ **Closed 이슈는 description이 편집 화면에 없어 `HTTP 400 … "Field 'description' cannot be set. It is not on the appropriate screen, or unknown."`이 난다** — 권한·설정 문제로 읽히지만 원인은 **상태**다. 고쳐야 하면 `transition --to "Reopen Issue"` → `update` → **`Close Issue` 전이로 원래 resolution을 되돌린다**. 되닫는 전이는 `resolution`이 필수인데 CLI는 전이에 필드를 못 실으므로 이 마지막 단계만 REST 직결이다(`POST /rest/api/2/issue/<KEY>/transitions`, 페이로드를 먼저 출력해 확인). **되닫는 전이가 있는지 Reopen 전에는 조회되지 않으니**, 그 상태에 머물러도 되는 이슈에만 한다.
  - `--field`는 커스텀 필드 id(`customfield_210565`) 또는 표시 이름(`"QA Scenario"`) 둘 다 받는다.
- **상태 전이**: `cubrid-jira transition <KEY> --to <이름> --yes` (`--to` 생략 시 가능한 전이 목록 출력).
- **담당자 지정**: `cubrid-jira assign <KEY> --to <username|""> --yes` (`""`는 해제).
- **이슈 링크**: `cubrid-jira link <KEY> --type <Blocks|Cloners|Duplicate|Relates> --to <KEY> --yes`.

## 라벨 주의 (트리아지와 직결)

`cubrid-jira update <KEY> --label ...`는 **라벨 전체 목록을 교체**한다(Jira REST `fields` 시맨틱). 트리아지 라벨 하나를 "추가"하려면 **기존 라벨 + 새 라벨 전부**를 함께 넘겨야 한다. 먼저 `cubrid-jira search <KEY>`(또는 `jql --output json`의 `labels`)로 현재 라벨을 읽고, 원하는 최종 집합을 통째로 `--label`로 전달한다. 개별 add/remove 서브커맨드는 없다.

## 스킬이 "issue tracker에 publish" 하라고 할 때

위 "티켓 구조"를 따른다 — 스펙이면 Jira sub-task, 작업이면 GitHub Issue, **그 밖이면 기존 Jira 티켓에 코멘트**다. 스킬이 "publish"라고 말한다고 해서 무조건 새 이슈가 되는 게 아니다.

## 스킬이 "관련 티켓을 fetch" 하라고 할 때

`cubrid-jira search <KEY>`로 읽는다.

## GitHub을 요청 표면으로 다루는가

**PRs as a request surface: no.** _(GitHub PR은 트리아지 큐가 아니다. 넣고 싶으면 이 플래그를 `yes`로 바꾸고 여기 워크플로를 적는다.)_

**GitHub Issues는 요청 표면이 아니라 작업 티켓 자리다.** `/to-tickets`가 스펙 sub-task에서 만든 작업만 산다. 밖에서 들어온 요청은 여기서 받지 않는다 — 그 자리는 Jira(CUBRIDQA)다.
