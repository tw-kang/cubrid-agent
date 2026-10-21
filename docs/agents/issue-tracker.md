# Issue tracker: Jira 헤드 + 로컬 markdown

cubrid-agent 자체 개발의 일을 세 단계로 추적한다. 이 트래커는 cubrid-agent의 에이전트가 처리 대상으로 삼는 CBRD/CUBRIDQA 이슈(파이프라인 입력)와 별개다.

이 문서에서 **리더**는 지도와 배정을 맡는 세션이다. SendMessage로 부르는 이름은 `leader`다. **작업 세션**은 리더가 배정한 결정 티켓이나 스펙을 처리하는 세션이다.

## 세 단계

| 단계 | 자리 | 하나가 담는 것 | 만드는 쪽 |
|---|---|---|---|
| **Jira 헤드** | CUBRIDQA Task. 키 목록은 `.github/head-keys.txt` | 목표 하나 | 리더 |
| **Jira sub-task** | 헤드 아래 sub-task | PR 하나 | 작업 세션, "머지 준비" 때 |
| **로컬 티켓** | `.scratch/` 아래 markdown 파일 | 결정 하나 또는 작업 하나 | 리더(지도), `/to-tickets`(스펙) |

- 모든 repo에 같게 적용한다. tc repo의 PR도 같은 헤드와 sub-task를 쓴다.
- **GitHub Issues는 쓰지 않는다.** tc repo는 Issues가 꺼져 있다. 이 repo는 공개라서 비공개 tc repo의 내용을 적을 수 없다.
- **Jira에는 결정의 기록만 남긴다.** 진행 이력 코멘트를 쌓지 않는다. 진행은 로컬 지도와 스펙이 관리한다.
- **PRs as a request surface: no.** 밖에서 온 요청의 자리는 [`triage-labels.md`](./triage-labels.md)에 있다.

## 로컬 트래커 — `.scratch/`

- `.scratch/`는 gitignore 대상이다. 다른 repo의 세션은 이 repo의 `.scratch/`를 절대 경로로 읽는다.
- 지도와 그 결정 티켓은 아래 [Wayfinding operations](#wayfinding-operations--v2-지도-로컬) 절을 따른다.
- **스펙**: 한 구간의 결정이 끝나면 리더가 `/to-spec`으로 `.scratch/v2-<묶음>/spec.md`를 만든다. 이어서 `/to-tickets`로 같은 디렉토리에 `issues/NN-<slug>.md`를 만든다.
- 스펙 하나는 통합 브랜치 하나, Draft PR 하나로 간다. 작업 세션이 `/implement-spec`으로 처리한다.
- 티켓 하나에 파일 하나다. 번호는 `01`부터 매긴다.
- `Status:` 줄은 처음 값(`open` 또는 `ready-for-agent`) → `claimed (...)` → `resolved`로 바뀐다.
- 대화와 제안은 파일 끝의 `## Comments` 아래에 덧붙인다.
- 스킬이 "issue tracker에 publish"하라고 하면 위 자리에 파일을 쓴다. Jira에는 올리지 않는다.
- 스킬이 "관련 티켓을 fetch"하라고 하면 받은 경로나 번호의 파일을 읽는다. Jira 키를 받으면 아래 [`search`](#핵심-규약-cubrid-jira-cli) 항목의 에이전트용 읽기 명령을 쓴다.

## Wayfinding operations — v2 지도 (로컬)

`/wayfinder`가 이 절을 읽는다. v2의 지도와 티켓은 Jira나 GitHub이 아니라 이 repo의 gitignore된 로컬 파일이다. 결정의 근거는 `.scratch/v2/issues/01-structure-charting.md`에 있다.

- **지도**: `.scratch/v2/map.md`. `/wayfinder 02`처럼 번호만 받으면 이 지도의 티켓 `02`다. 지도는 결정 티켓만 담는다(wayfinder 기본값 "plan, don't do"). 실행은 스펙으로 한다.
- **티켓**: `.scratch/v2/issues/NN-<slug>.md`. 머리 줄은 `Type:`(`research` / `prototype` / `grilling` / `task`), `Status:`, `Blocked by:`다. 그 티켓에만 해당하는 지시는 티켓 본문에 있다. grilling 티켓은 `grilling`과 `domain-modeling`을, research 티켓은 `research`를 부른다.
- **Frontier**: `Status: open`이고 `Blocked by`의 티켓이 모두 `resolved`인 티켓이다. 순서는 지도의 순서표가 정한다.
- **리더**: 리더는 구현과 티켓 처리를 하지 않는다. 리더가 직접 쓰는 것은 `.scratch/` 아래의 지도, 티켓, 스펙뿐이다. repo가 추적하는 파일의 변경은 급해도 티켓으로 만들어, 그 파일을 맡은 작업 세션에 넘긴다.
- **배정**: 리더가 지도의 순서표에서 세션을 배정한다. 배정받지 않은 티켓은 claim하지 않는다.
- **Claim**: 일을 시작하기 전에 `Status:` 줄을 `claimed (<세션 이름>, <YYYY-MM-DD HH:MM>)`로 바꾸고 저장한다. 세션 이름은 맡은 티켓 번호를 따른다(예: `v2-03`).
- **Resolve**:
  1. 티켓 끝에 `## Answer`를 적는다.
  2. `Status: resolved`로 바꾼다.
  3. 리더에게 SendMessage로 알린다. 보고에는 아래 세 항목이 반드시 있다. 길이 제한은 없다.
     - **실물**: 그 일에 해당하는 머지 SHA, PR 번호나 링크, 결과 파일 경로
     - **닫은 티켓**: 티켓 경로
     - **지도에 영향을 주는 사실**: 순서표, 막힘 관계, 다음 티켓에 영향을 주는 것. 없으면 "없음"이라고 적는다.
  - **`map.md`는 고치지 않는다.** Decisions so far와 순서표는 리더가 실물(커밋, PR, 파일)과 대조한 뒤 고친다. wayfinder 기본 절차의 "지도에 context pointer 추가"를 이 알림이 대신한다.
- **Research 결과**: `.scratch/v2/research/<name>.md`에 쓴다. 브랜치를 만들거나 push하지 않는다. 이 repo는 공개이고 tc repo 일부는 비공개이기 때문이다.
- **새로 드러난 결정**: `.scratch/v2/issues/`에 다음 번호로 `Status: open` 티켓을 만든다. 그다음 리더에게 알린다. 순서표에 올리는 일은 리더가 한다.
- **스펙을 맡은 작업 세션**: `/implement-spec`으로 `.scratch/v2-<묶음>/spec.md`를 처리할 때도 위 Claim·Resolve·알림 규칙을 스펙 단위로 따른다. 보고는 Resolve 3의 세 항목으로 한다. 티켓이 리더에게 값을 넘기라고 하면 그때도 알린다.
- **`/retro` 제안**: 맡은 티켓의 `## Comments`에 적는다. 티켓으로 만들지는 리더가 판단한다. 제안마다 두 가지를 한 줄씩 적는다.
  - **결과**: 그 문제가 일어나면 무엇이 생기는가
  - **재발**: 어떤 조건에서 다시 생기는가
  - 등급은 결과로 정하고, 재발로 조정한다.
    - **높음**: 되돌릴 수 없는 일이 사람의 확인 없이 일어난다. 또는 검사가 틀린 채 통과한다.
    - **중간**: 재작업이나 조율 지연이 생기고, 같은 조건이 되면 다시 생긴다.
    - **낮음**: 손작업이나 확인이 한 번 더 든다. 또는 드문 조건에서만 생긴다.

## PR 흐름

**PR 헤더**는 PR 제목 맨 앞의 `[CUBRIDQA-<n>]`이다. **브랜치 이름**은 `cubridqa-<헤드 키 번호>-<내용>`이다. 브랜치 이름, PR 헤더, Ready PR의 헤드 키는 `validate`가 검사한다(`scripts/check-pr-push.sh`). 이 절은 기계가 판정하지 못하는 순서만 적는다.

이 흐름과 브랜치 이름은 릴리스 PR을 뺀 모든 PR에 적용한다. 스펙 밖에서 배포면을 바꾸는 PR도 같다. 어떤 PR도 아래 3의 "머지" 지시 전에는 머지하지 않는다. "머지 준비" 지시는 머지 지시가 아니다.

1. **열 때**: Draft PR로 연다. PR 헤더는 헤드 키다. `/implement-spec`이 끝나도 Draft로 둔다. Ready는 2의 "머지 준비" 안에서만 바꾼다.
2. **사람이 "머지 준비"를 지시하면** 아래를 순서대로 한다.
   1. sub-task를 만든다. `create`에는 `--parent`가 없으므로 Task로 만든 뒤 헤드 아래로 옮긴다. description은 PR 본문처럼 한글, 사용자 관점으로 쓴다.
      ```bash
      cubrid-jira create --project CUBRIDQA --type Task --summary "<PR 제목에서 PR 헤더를 뺀 것>" --description-file <파일> --yes
      cubrid-jira convert-to-subtask <새 키> --to <헤드 키> --yes
      ```
   2. 담당자를 바로잡는다. 새 sub-task의 담당자는 기본값으로 다른 사람이 된다. 계정은 `$CUBRID_JIRA_USER`에서 읽는다(비어 있으면 `source ~/.cubrid-agent/env.sh`). 사람 이름을 박지 않는다.
      ```bash
      cubrid-jira assign <새 키> --to "$CUBRID_JIRA_USER" --yes
      cubrid-jira jql 'key = <새 키>' --fields parent,assignee,status --output json   # 부모와 담당자를 확인한다
      ```
   3. PR 헤더를 sub-task 키로 바꾼다. PR 본문 첫 줄의 Jira 링크도 같은 키로 바꾼다.
   4. PR을 Ready로 바꾼다. `validate`가 통과하는지 본다.
   5. 여기서 멈춘다. 사람에게 Ready PR과 sub-task 키를 알린다. 머지하지 않는다.
3. **사람이 "머지"를 지시하면**:
   1. squash 머지한다.
   2. sub-task를 Closed/Fixed로 바꾼다(`transition <키> --to "Close Issue" --yes`). readback으로 resolution이 `Fixed`인지 본다.
4. **추이를 보고 고칠 것이 생기면**: 같은 sub-task를 Reopen한다(`transition <키> --to "Reopen Issue" --yes`). 새 sub-task는 만들지 않는다. 후속 PR은 처음부터 그 sub-task 키를 PR 헤더로 연다. 주의 — 다시 닫는 전이가 `resolution`을 요구하면 아래 `update` 항목의 Closed 이슈 주의를 따른다. 머지 지시가 오면 3처럼 머지하고 다시 닫는다.

## Jira에 무엇을 남기나 — 열고 30초에 알 수 있게

**이슈는 읽는 사람이 지금 무엇을 알아야 하는지를 담는다. 어떻게 알아냈는지는 담지 않는다.** 글은 한글, 사용자 관점이다.

설계는 이슈에 산다(repo는 제품을, 설계는 Jira가 보관 — CUBRIDQA-1454). 그러니 분량을 줄이는 게 목표가 아니다. 읽는 순서를 주는 게 목표다. 아래 넷은 실측에서 나온 세 가지 실패를 각각 겨냥한다.

### 1. 자리 — 같은 사실을 두 곳에 두지 않는다

| 자리 | 담는 것 | 담지 않는 것 |
|---|---|---|
| **description** | **지금 참인 것만** — 문제, 결정, 현재 스펙 | 시각이 붙는 것(실측·실행 결과·"…시점 스냅샷"), 정정 이력 |
| **comment** | 결정의 기록 — 무엇을 왜 바꿨는지 | 진행 이력, 실측, 실행 결과(로컬 티켓과 PR 본문의 자리) |
| **repo** (커밋 메시지·`docs/`) | 근거, 측정 원자료, 대안 검토 | — |

description에 날짜가 붙은 절이 생겼다면 그건 코멘트 자리다.

### 2. 리드 — 첫 15줄 안에 셋을 답한다

description 맨 위에 **무엇이 문제인가**(1~2문장) · **지금 상태**(한 줄) · **다음 행동**(한 줄)을 둔다. 그 아래로는 얼마든지 길어도 된다. 읽는 사람이 접고 내려갈 수 있으면 길이는 비용이 아니다. 리드가 없으면 13개 절을 다 읽어야 상태를 안다.

### 3. 주제당 정본 코멘트 하나 — 새로 달지 말고 그 코멘트를 고친다

같은 주제로 두 번째 코멘트를 달지 않는다. 첫 코멘트가 그 주제의 **정본**이고, 이후는 `comment-update --id <ID>`로 그 본문을 갱신한다. 정본 코멘트는 첫 줄에 그렇게 밝힌다:

```
h3. {anchor:<주제>-이-주제-통합}<주제> — <한 줄 요약> (YYYY-MM-DD, 이 주제 통합)
이 코멘트가 <주제>의 정본이다. 이전에 나뉘어 있던 코멘트는 여기로 합쳤다.
```

갱신은 **replace**이므로 기존 본문을 먼저 읽어 뒤에 이어 붙인다. 쓰기 전에 dry-run 출력의 앞부분이 원본과 바이트 단위로 같은지 확인한다(`comment-list <KEY> --output json | jq -r '.comments[] | select(.id=="<ID>") | .body'`).

### 4. 정정은 덧붙이지 말고 그 자리를 고친다

description이 틀렸으면 **틀린 문장을 고친다**. "정정(날짜)" 절을 아래에 붙이지 않는다. Jira가 history를 보관하므로 원래 문장은 사라지지 않는다. 무엇을 왜 고쳤는지는 코멘트에 한 줄 남긴다.

### 분량 — 목표가 아니라 신호

**description이 6,000자를 넘으면 리드가 있는지 다시 본다.** 2026-08-05 실측(19건, 합 93,181자): 13건이 6,000자 이하로 중앙값 2,004자였다. 넘는 6건이 전체 분량의 **65%** 를 차지했다(최대 15,021자). 길이 자체보다 **몇 건에 몰리는 것**이 신호다. 다시 잴 때는 **문자 수로 센다. 한글은 1자가 3바이트라 `wc -c`는 세 배로 부푼다**:

```bash
cubrid-jira jql 'key = <헤드 키> OR parent = <헤드 키> ORDER BY key' --fields description --output json \
  | jq -r '.issues[] | "\(.key)\t\(.fields.description // "" | length)"'
```

## CLI 버전 — 최소선 2026-07-29, 권장 최신

`cubrid-jira`는 semver를 올리지 않는다(전부 `1.0.0`). 그래서 "최신"은 git HEAD를 뜻한다.

**최소선 = 2026-07-29 머지분.** 그 이전 설치본은 스킬이 지시한 대로 **동작하지 않는다**:

- **인증 읽기**(PR #3) — 없으면 read를 익명 전송해 CUBRIDQA에서 **HTTP 401**이 난다. 공개 프로젝트(CBRD)는 익명 read가 되므로 증상이 CUBRIDQA에서만 난다. 401을 보면 **재시도하지 말 것**(반복 실패는 CAPTCHA 잠금).
- **`attachment` 서브커맨드**(PR #2) — 없으면 스킬이 지시한 명령이 `invalid choice`로 실패한다.

**권장 = 그냥 최신.** 2026-07-30에 아래 두 건이 두 시간 간격으로 머지됐다. 그래서 "07-30 머지분"이라는 표현은 둘을 구분하지 못한다 — 날짜로 고르지 말고 `uv tool upgrade`로 올린다. 없어도 정상 경로는 돌지만, 조용히 틀리는 경우가 남는다:

- **pandoc 읽기 폴백**(PR #4) — 낡은 pandoc에서 이슈 본문이 빈칸이 되는 대신 경고 한 줄 + Jira 마크업 원문으로 나온다. 아래 `search` 경고 참조.
- **읽기·첨부 하드닝**(PR #5) — ① 401이 **첫 시도에서 멈춘다**(그 전에는 관련 이슈마다 재전송해 한 번의 `search`가 여러 번의 인증 실패가 됐다 — CAPTCHA 잠금의 실제 원인이었다) ② 서버가 알려준 크기를 못 믿고 **받은 바이트로** 5MiB 상한을 걸어 초과분이 디스크에 남지 않는다 ③ 첨부 파일명을 basename으로 정리해 경로 탈출을 막고 중복 이름에 `-<id>`를 붙인다 ④ 인증 없이도 공개 이슈 첨부를 받는다.

확인·갱신:

```bash
cubrid-jira attachment --help >/dev/null 2>&1 && echo OK || uv tool upgrade cubrid-jira   # 최소선 확인
uv tool upgrade cubrid-jira                                                              # 권장: 그냥 최신으로
```

최소선 확인에 `attachment`의 존재를 대리 지표로 쓴다. PR #2와 #3이 30초 차로 머지됐으므로 둘 중 하나만 있는 빌드는 사실상 없다.

**curl REST 직결은 최후 수단**(CLI로 안 되는 것만). 베이스는 `http://jira.cubrid.org/rest/api/2`(http — https는 302)이고 `curl --netrc`로 부른다. 지금 남은 실제 용도는 Closed 이슈를 되닫는 전이뿐이다(아래 `update` 항목). 쓰기는 `--yes` 안전판이 없으니 페이로드를 먼저 확인한다.

## 핵심 규약 (`cubrid-jira` CLI)

Jira 쪽 생성·조회·수정은 `cubrid-jira` CLI(`~/.local/bin/cubrid-jira`)로 한다. Jira 웹 UI도 유효한 경로다.

모든 **쓰기 명령은 기본 dry-run**이다. 실제 전송하려면 `--yes`가 필수다. 서버 기본값은 `http://jira.cubrid.org`.

- **이슈 생성**: `cubrid-jira create --project CUBRIDQA --type Task --summary "..." [--description-file PATH] [--label ...] [--field "QA Scenario=..."] --yes`
  - 본문(description)은 markdown 파일을 주면 Jira wiki markup으로 변환된다. wiki 표기를 그대로 올리려면 `--from jira`를 쓴다(markdown 변환이 escape를 넣는다). heredoc 대신 파일 경로를 쓴다.
  - 이슈 타입(`--type`)은 프로젝트가 허용하는 값(예: `Task`, `Bug`, `Improvement`) 중 하나.
- **sub-task로 옮기기**: `cubrid-jira convert-to-subtask <KEY> --to <부모> --yes`. 반대는 `convert-to-issue`, 부모 바꾸기는 `reparent`다.
- **이슈 읽기(단건)**: `cubrid-jira search <KEY>` — 캐시 우선으로 live fetch, markdown을 stdout에 출력. 오프라인은 `--cache-only`.
  - ⚠️ **본문이 빈칸으로 나오면 이슈가 빈 게 아니라 pandoc이 낡은 것이다.** `search`는 description·comment를 `pandoc -f jira`로 렌더한다. `jira` reader가 없는 pandoc(RHEL 8 배포판 2.0.6)에서 **2026-07-29 이전 설치본은 성공 종료 + 빈 본문**을 낸다 — 실제로 이것 때문에 CUBRIDQA-1443의 4664자 본문을 "비어 있다"고 오판한 적이 있다(CUBRIDQA-1473). 2026-07-30 이후 설치본(PR #4)은 `Warning: pandoc cannot convert Jira wiki markup …`을 stderr에 한 번 찍고 **원문을 그대로** 내보낸다. **에이전트가 읽을 때는 버전에 관계없이** pandoc 무관 경로인 `cubrid-jira jql 'key = <KEY>' --fields summary,description,comment,attachment --output json`을 쓴다(CUBRIDQA-1478).
- **이슈 목록/검색**: `cubrid-jira jql "<JQL>" [--output json] [--max N] [--fields ...]`
  - 예: `cubrid-jira jql "project = CUBRIDQA AND status != Closed ORDER BY updated DESC" --output json` — 에이전트/jq 파이프용 raw JSON.
  - 쓴 뒤에는 이 명령으로 다시 읽어 결과를 확인한다(readback).
- **첨부 다운로드**: `cubrid-jira attachment <KEY> --output json` — 전부 받고 파일별 매니페스트를 한 줄 JSON으로 출력(`--list`는 메타데이터만). 기본 저장 위치는 `~/.local/share/cubrid-jira/attachments/<KEY>/`(`$CUBRID_JIRA_DIR`가 있으면 그 아래, `--out DIR`로 지정 가능)이고, 각 항목의 `path`가 실제 경로다. 5MiB 초과는 받지 않고 `skipped` 사유만 남긴다 — 코어·바이너리가 디스크에 쌓이지 않는다.
- **댓글**: 추가 `cubrid-jira comment <KEY> --body-file PATH --yes` / 목록 `comment-list` / 수정 `comment-update` / 삭제 `comment-delete`.
- **필드 수정**: `cubrid-jira update <KEY> [--summary "..."] [--description-file PATH] [--field FIELD=VALUE] --yes`
  - `--description-file`은 기존 description을 **replace**한다(history엔 남음). `-`로 stdin 입력 가능.
  - ⚠️ **Closed 이슈는 description이 편집 화면에 없어 `HTTP 400 … "Field 'description' cannot be set. It is not on the appropriate screen, or unknown."`이 난다** — 권한·설정 문제로 읽히지만 원인은 **상태**다. 고쳐야 하면 `transition --to "Reopen Issue"` → `update` → **`Close Issue` 전이로 원래 resolution을 되돌린다**. 되닫는 전이는 `resolution`이 필수인데 CLI는 전이에 필드를 못 실으므로 이 마지막 단계만 REST 직결이다(`POST /rest/api/2/issue/<KEY>/transitions`, 페이로드를 먼저 출력해 확인). **되닫는 전이가 있는지 Reopen 전에는 조회되지 않으니**, 그 상태에 머물러도 되는 이슈에만 한다.
  - `--field`는 커스텀 필드 id(`customfield_210565`) 또는 표시 이름(`"QA Scenario"`) 둘 다 받는다.
- **상태 전이**: `cubrid-jira transition <KEY> --to <이름> --yes` (`--to` 생략 시 가능한 전이 목록 출력).
- **담당자 지정**: `cubrid-jira assign <KEY> --to <username|""> --yes` (`""`는 해제).
- **이슈 링크**: `cubrid-jira link <KEY> --type <Blocks|Cloners|Duplicate|Relates> --to <KEY> --yes`.

## 라벨 주의

`cubrid-jira update <KEY> --label ...`는 **라벨 전체 목록을 교체**한다(Jira REST `fields` 시맨틱). 라벨 하나를 "추가"하려면 **기존 라벨 + 새 라벨 전부**를 함께 넘겨야 한다. 먼저 `cubrid-jira search <KEY>`(또는 `jql --output json`의 `labels`)로 현재 라벨을 읽고, 원하는 최종 집합을 통째로 `--label`로 전달한다. 개별 add/remove 서브커맨드는 없다.
