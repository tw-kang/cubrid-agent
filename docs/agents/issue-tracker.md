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
- **GitHub Issues는 쓰지 않는다.** tc repo는 Issues가 꺼져 있다. 이 repo는 공개라서 비공개 tc repo의 내용을 적을 수 없다. 예외는 룰북(TC 작성 규칙 문서)에 적는 비공개 repo의 케이스 경로 하나다. 정본은 `.scratch/v2/issues/04-rulebook-shape.md`의 D2·D10이다.
- **Jira에는 결정의 기록만 남긴다.** 진행 이력 코멘트를 쌓지 않는다. 진행은 로컬 지도와 스펙이 관리한다.
- **PRs as a request surface: no.** 밖에서 온 요청의 자리는 [`triage-labels.md`](./triage-labels.md)에 있다.

## 로컬 트래커 — `.scratch/`

- `.scratch/`는 gitignore 대상이다. 다른 repo의 세션은 이 repo의 `.scratch/`를 절대 경로로 읽는다.
- 지도와 그 결정 티켓은 아래 [Wayfinding operations](#wayfinding-operations--v2-지도-로컬) 절을 따른다.
- **스펙**: 한 구간의 결정이 끝나면 리더가 `/to-spec`으로 `.scratch/v2-<묶음>/spec.md`를 만든다. 이어서 `/to-tickets`로 같은 디렉토리에 `issues/NN-<slug>.md`를 만든다.
- 스펙 하나는 통합 브랜치 하나, Draft PR 하나로 간다. 작업 세션이 `/implement-spec`으로 처리한다.
- 티켓 하나에 파일 하나다. 번호는 `01`부터 매긴다.
- `Status:` 줄의 형식은 둘이다. 지도 티켓은 평문 `Status: open`이다. `/to-tickets`가 만든 스펙 티켓은 굵은 글씨 `**Status:** ready-for-agent`다.
  - claim과 resolve는 그 줄의 형식을 그대로 두고 값만 바꾼다. 값은 아래 Wayfinding operations 절의 Claim·Resolve 항목을 따른다.
  - 스펙 티켓을 resolve할 때는 완료 조건의 `- [ ]`도 `- [x]`로 바꾼다.
- 대화와 제안은 파일 끝의 `## Comments` 아래에 덧붙인다.
- 스킬이 "issue tracker에 publish"하라고 하면 위 자리에 파일을 쓴다. Jira에는 올리지 않는다.
- 스킬이 "관련 티켓을 fetch"하라고 하면 받은 경로나 번호의 파일을 읽는다. Jira 키를 받으면 아래 [`search`](#핵심-규약-cubrid-jira-cli) 항목의 에이전트용 읽기 명령을 쓴다.

## Wayfinding operations — v2 지도 (로컬)

`/wayfinder`가 이 절을 읽는다. v2의 지도와 티켓은 Jira나 GitHub이 아니라 이 repo의 gitignore된 로컬 파일이다. 결정의 근거는 `.scratch/v2/issues/01-structure-charting.md`에 있다.

- **지도**: `.scratch/v2/map.md`. `/wayfinder 02`처럼 번호만 받으면 이 지도의 티켓 `02`다. 지도는 결정 티켓만 담는다(wayfinder 기본값 "plan, don't do"). 실행은 스펙으로 한다.
- **티켓**: `.scratch/v2/issues/NN-<slug>.md`. 머리 줄은 `Type:`(`research` / `prototype` / `grilling` / `task`), `Status:`, `Blocked by:`다. 그 티켓에만 해당하는 지시는 티켓 본문에 있다. grilling 티켓은 `grilling`과 `domain-modeling`을, research 티켓은 `research`를 부른다.
  - grilling에서 이름·배치·관례를 정하는 질문은 추천하기 전에 `research`로 표준과 널리 쓰이는 예를 조사한다. 04에서 조사 없이 추천해 라운드가 2~3개 더 들었다. 자리·사본·흐름을 정하는 질문은 선택지보다 먼저 목록(산출물, 사본, 읽는 쪽, 쓰는 쪽)을 보인다. 05에서 목록 없이 물어 같은 질문을 세 번 했다.
- **Frontier**: `Status: open`이고 `Blocked by`의 티켓이 모두 `resolved`인 티켓이다. 순서는 지도의 순서표가 정한다.
- **리더**: 리더는 구현과 티켓 처리를 하지 않는다. 리더가 직접 쓰는 것은 `.scratch/` 아래의 지도, 티켓, 스펙뿐이다. repo가 추적하는 파일의 변경은 급해도 티켓으로 만들어, 그 파일을 맡은 작업 세션에 넘긴다.
- **배정**: 리더가 지도의 순서표에서 세션을 배정한다. 배정받지 않은 티켓은 claim하지 않는다.
- **Claim**: 일을 시작하기 전에 `Status:` 줄을 `claimed (<세션 이름>, <YYYY-MM-DD HH:MM>)`로 바꾸고 저장한다. 세션 이름은 맡은 티켓 번호를 따른다(예: `v2-03`).
  - 시각과 수치는 손으로 치지 않는다. 티켓 줄의 시각은 그 줄을 적는 셸 명령(`sed -i`, heredoc) 안의 `$(date '+%Y-%m-%d %H:%M')`가 넣는다. 보고의 시각과 수치는 명령의 출력 줄(그 티켓 줄, 검사 출력)을 그대로 붙인다. `v2-sql-medium-rulebook` 01은 15:01을 15:20으로 적었다. 지적을 받은 뒤에도 같은 일이 한 번 더 생겼다.
  - 재오픈된 티켓(`Status:` 값에 `재오픈`이 있다)은 값을 덮지 않고 앞에 잇는다. 새 값을 앞에 쓴다. 지금 값은 ` · 이전: `으로 뒤에 잇는다. 예: `**Status:** claimed (v2-structure, 2026-10-23 20:12) · 이전: ready-for-agent — 재오픈 (…) · 이전: resolved`. resolve도 같다.
  - 상태를 셀 때는 `Status:` 줄을 ` · 이전:` 앞까지만 읽는다. 줄 전체를 grep하면 "이전: resolved"가 걸린다.
- **Resolve**:
  1. 티켓 끝에 `## Answer`를 적는다. 재오픈된 티켓은 `## Answer (재오픈분 — <YYYY-MM-DD>, <세션 이름>)` 절에 따로 적는다. 기존 `## Answer`와 1차분의 체크박스는 고치지 않는다. 재오픈 절의 체크박스만 `- [x]`로 바꾼다.
     - Answer의 초안을 쓴 뒤에 `/code-review`를 돌린다. PR이 있으면 PR 본문의 초안도 먼저 쓴다. Spec 축에는 그 초안들을 함께 넘긴다. 초안의 동작 문장을 보는 판단 규칙은 [`CODING_STANDARDS.md`](../../CODING_STANDARDS.md)에 둔다. `v2-shell-rulebook` 01 재오픈분에서는 `/code-review`가 Answer보다 먼저 돌았다. 그래서 Answer의 "`/`로 시작하는 링크도 위반이다"가 거짓인 채 리더에게 갔다(`7ea10c5`).
  2. `Status: resolved`로 바꾼다.
  3. 리더에게 SendMessage로 알린다. 보고에는 아래 세 항목이 반드시 있다. 길이 제한은 없다.
     - **실물**: 그 일에 해당하는 머지 SHA, PR 번호나 링크, 결과 파일 경로
     - **닫은 티켓**: 티켓 경로
     - **지도에 영향을 주는 사실**: 순서표, 막힘 관계, 다음 티켓에 영향을 주는 것. 없으면 "없음"이라고 적는다.
  - **`map.md`는 고치지 않는다.** Decisions so far와 순서표는 리더가 실물(커밋, PR, 파일)과 대조한 뒤 고친다. wayfinder 기본 절차의 "지도에 context pointer 추가"를 이 알림이 대신한다.
- **재오픈**: 닫힌 티켓의 후속 일은 리더가 새 티켓 대신 그 티켓을 다시 연다. 판단 기준은 리더 몫이다(지도 Notes "리더 운용"의 "후속 일은 새 티켓보다 재오픈"). 리더가 새 요구를 적는 절을 이 문서는 **재오픈 절**이라 부른다. 그 이름은 `## 재오픈 (날짜, 누가 — 이유)`다. 다른 티켓을 흡수한 재오픈이면 이름이 `## 재오픈분 — <주제>`이고, `## 흡수한 NN` 절은 원문 이력이다. 작업 세션은 재오픈 절의 할 일만 한다. Claim과 Resolve는 위 절차대로 한다.
- **Research 결과**: `.scratch/v2/research/<name>.md`에 쓴다. 브랜치를 만들거나 push하지 않는다. 이 repo는 공개이고 tc repo 일부는 비공개이기 때문이다.
  - 다음 티켓이 쓰는 수치마다 그 수치를 다시 내는 명령을 붙인다. 명령은 옆 파일 `<name>.repro.md`의 `#### [ID]` 블록(`sh` + `expected`)에 둔다. 결과 파일은 수치 옆에 `[ID]`를 적는다. 결과 파일의 첫 절(리드)이 재현 파일을 가리킨다. 블록 형식의 정본은 `scripts/research-recheck.py`의 머리 주석이다.
  - resolve 전에 `scripts/research-recheck.py <결과 파일>`이 exit 0인지 본다. 명령, `INDEPENDENT` 줄, `SUMMARY` 줄을 `## Answer`에 적는다. 손으로 다시 세거나 그때 짠 검사기로 대신하지 않는다. 02에서 그런 검사기 다섯 중 둘이 틀린 채 통과했다.
  - resolve하는 세션은 블록 5개 이상에서 주장 하나씩을 결과를 낸 스크립트 없이 다시 낸다(예: `git show <고정 SHA>:<경로> | wc -l`, `grep -c`). 블록이 5개보다 적으면 모든 블록에서 한다. 그 명령은 그 블록의 `independent` fence에 둔다. recheck가 fence를 가진 블록의 수와 fence의 출력을 검사한다. 결과를 낸 스크립트가 일관되게 틀리면 그 출력으로 채운 expected도 같이 틀린다. 10에서 줄 수가 1씩 많은 결함이 37블록 PASS를 두 번 받았다.
  - 개수를 내는 명령은 센 항목(ID나 경로)도 함께 찍는다. 항목이 많으면 표본을 찍는다. 개수만 찍으면 잘못 잡은 항목이 보이지 않는다.
- **위치 주장**: 파일의 행 번호나 위치를 말하는 주장은 그 행을 `grep -n`이나 `sed -n`으로 찍은 출력과 함께 둔다. 이 규칙은 research 결과와, 다음 티켓이 입력으로 쓰는 티켓의 `## Answer`에 모두 건다. `v2-sql-medium-rulebook` 01에서 서브에이전트가 "29~30행, 데이터를 만드는 줄 옆"이라 적은 주석은 실제로 29~31행, 데이터 문장 위의 별도 줄이었다. 그 글이 사용자 선택지의 추천안이 되었다.
- **서브에이전트**: research를 서브에이전트에 나눠 맡길 때 아래를 지킨다.
  - 지시문에 넣는다 — 오래 걸리는 명령은 foreground로 돌린다. 도구 상한(한 번에 10분)을 넘기면 나눠 돌린다. background 명령을 기다리며 턴을 끝내지 않는다.
  - 서브에이전트를 띄운 작업 세션은 "기다린다"는 idle 알림을 끝으로 믿지 않는다. 알림을 받으면 그 명령이 쓴 출력 파일을 직접 본다. 02에서 두 번 생겼다. 한 번은 13시간 넘게 멈췄다.
  - 병렬 서브에이전트에게는 각자 다른 중간 파일 디렉토리를 준다. 같은 scratchpad 루트를 주면 서로 덮는다(03 재오픈분, 에이전트 6개).
  - 서브에이전트가 SendMessage로 부르는 `team-lead`는 그 서브에이전트를 띄운 작업 세션이다. 리더가 아니다. 리더에게 보고하는 쪽은 작업 세션뿐이다. 10의 작업 세션은 `team-lead`를 리더로 읽었다. 그래서 리더에게 보낸 보고 두 건에 "서브에이전트가 리더에게 보고했다"고 잘못 적었다.
  - 지시문에 ID(규칙 ID, 표의 행 ID)를 넘길 때는 그 ID를 정의한 파일과 행을 함께 넘긴다. 이 줄은 research 밖의 서브에이전트(구현, 리뷰)에도 건다. `v2-sql-medium-rulebook` 06의 작업 세션은 구현 서브에이전트에 "U-1720-2 = gha-ci가 그 브랜치에서 돌림"이라고 보냈다. 02 표의 정의는 `commit-to-tc-pr-branch`였다.
- **새로 드러난 결정**: 작업 세션은 티켓 파일을 만들지 않는다. 새 결정이나 조사가 필요하면 리더에게 SendMessage로 제안한다. 같은 내용을 맡은 티켓의 `## Comments`에도 적는다. 새 티켓을 만들지 기존 티켓을 재오픈할지는 리더가 판단한다.
- **스펙을 맡은 작업 세션**: `/implement-spec`으로 `.scratch/v2-<묶음>/spec.md`를 처리할 때도 위 Claim·Resolve·알림 규칙을 스펙 단위로 따른다. 보고는 Resolve 3의 세 항목으로 한다. 티켓이 리더에게 값을 넘기라고 하면 그때도 알린다.
  - 스펙 티켓의 `## Answer`가 기대는 검사 스크립트는 `.scratch/v2-<묶음>/tools/`에 둔다. Answer에는 그 경로와 실행 명령을 적는다. 세션 scratchpad(`/tmp/…`)의 경로는 Answer에 적지 않는다. scratchpad는 세션 하나의 `/tmp` 아래 디렉토리다. `/tmp`가 지워지면 Answer의 재현 명령도 사라진다. `v2-sql-medium-rulebook`의 스크립트는 scratchpad에서 판이 갈렸다. 리더가 옛 판 `both.sh`를 돌려 거짓 MISSING을 보았다. 옮긴 뒤의 보기는 `.scratch/v2-sql-medium-rulebook/tools/`다.
- **`/retro` 제안**: 맡은 티켓의 `## Comments`에 적는다. 티켓으로 만들지는 리더가 판단한다. retro를 요청하는 조건은 [`AGENTS.md`](../../AGENTS.md)의 `/retro` 줄에 있다.
  - **닫기 전 알림**: resolve 뒤 세션을 닫기 전에 리더에게 SendMessage로 알린다. 알림에는 retro 제안의 수와 자리를 적는다. 제안이 없으면 retro 없이 닫는다고 적는다. resolve 직후에 닫으면 이 내용을 Resolve 3의 알림에 함께 적는다. 10에서 이 알림이 없어 사용자가 "리더에게 보고부터하라"고 다시 지시했다.
  - 제안마다 두 가지를 한 줄씩 적는다.
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
      ```
   3. sub-task를 In Progress로 바꾼다. 리뷰를 받는 동안 sub-task는 In Progress다. 이미 In Progress이면 그대로 둔다.
      ```bash
      cubrid-jira transition <키> --to "Start Progress" --yes
      cubrid-jira jql 'key = <키>' --fields parent,assignee,status --output json   # 부모, 담당자, In Progress를 확인한다
      ```
   4. PR 헤더를 sub-task 키로 바꾼다. PR 본문 첫 줄의 Jira 링크도 같은 키로 바꾼다.
   5. PR을 Ready로 바꾼다. `validate`가 통과하는지 본다.
   6. 여기서 멈춘다. 사람에게 Ready PR과 sub-task 키를 알린다. 머지하지 않는다.
3. **사람이 "머지"를 지시하면**:
   1. squash 커밋 본문을 파일로 적는다. 첫 줄은 PR 헤더의 키(sub-task 키)로 만든 Jira 링크(`http://jira.cubrid.org/browse/<키>`)다. 그다음은 마지막 커밋까지 반영한 최종 변경의 영문 요약이다. 리뷰 수정, 되돌린 단계, 후속 정정 같은 브랜치 이력은 뺀다. trailer 줄(`Co-Authored-By:` 같은 끝 줄)은 끝에 한 번만 둔다. 이 형식은 [공식 프로세스의 Merge(p20)](../dev-process.md#핵심-운영-규칙)를 따른다.
   2. 기본 본문(PR의 커밋 메시지를 이은 것)으로 머지하지 않는다. 1의 파일을 `gh pr merge --squash --body-file <파일>`로 주어 squash 머지한다. PR #21의 squash 커밋 `ea39d2b`는 기본 본문으로 머지됐다. 그 본문은 커밋 메시지 18개를 이은 246줄이다. trailer 줄도 18번 되풀이된다.
   3. sub-task를 Resolved로 바꾼다(`transition <키> --to "Resolve Issue" --yes`). 이 전이는 resolution을 따로 받지 않고 `Fixed`를 남긴다(CUBRIDQA-1684·1690, 10-28). readback으로 status `Resolved`, resolution `Fixed`를 본다. 다른 값이면 멈추고 리더에게 알린다.
   - 작업 세션은 Close하지 않는다. 리더가 정한 점검 시점에 리더가 헤드 아래 sub-task를 읽고, Resolved인 것을 한꺼번에 Close한다. 그 시점은 지도 순서표의 "1차 끝 점검" 행에 있다.
4. **추이를 보고 고칠 것이 생기면**: 같은 sub-task를 Reopen한다(`transition <키> --to "Reopen Issue" --yes`). 새 sub-task는 만들지 않는다. 후속 PR은 처음부터 그 sub-task 키를 PR 헤더로 연다. "머지 준비"에서는 2의 1(sub-task 만들기)과 2(담당자)를 건너뛴다. 머지 지시가 오면 3처럼 머지하고 다시 Resolved로 바꾼다.

**squash 제목 설정이 `COMMIT_OR_PR_TITLE`인 repo의 PR**(설정은 `gh api repos/<owner>/<repo> --jq .squash_merge_commit_title`로 읽는다): 이 설정은 커밋이 하나뿐인 PR을 그 커밋의 제목으로 머지한다. 그래서 PR에 커밋을 둘 이상 둔다. 그러면 squash 제목은 "머지 준비"에서 sub-task 키로 바꾼 PR 제목이 된다. sub-task는 다른 PR처럼 "머지 준비"에서 만든다. 그래서 커밋할 때는 sub-task 키가 없다. 커밋 제목은 헤드 키로 시작한다.

**후속 커밋을 PR에 더할 때**(어느 단계든): 그 커밋이 바꾼 사실을 같은 PR의 세 자리에서 다시 읽는다 — PR의 diff(`CHANGELOG.md` 항목 포함), PR 본문, 앞 커밋의 메시지. diff와 PR 본문은 그 자리에서 고친다. 앞 커밋의 메시지는 고치지 못한다(force-push 금지). 그래서 새 커밋의 메시지에 무엇이 더는 참이 아닌지 적는다.

PR을 리뷰하는 사람은 지난번에 본 뒤의 변경을 새 커밋의 diff와 메시지로 읽는다. 새 메시지가 바뀐 사실을 말하지 않으면, 리뷰하는 사람은 이미 읽은 앞 메시지를 참이라고 여긴다. PR #20의 후속 커밋이 수치 하나를 뺐을 때 CHANGELOG 항목과 앞 커밋 메시지가 거짓으로 남았다. 그래서 티켓 하나와 리더 왕복 한 번이 더 들었다.

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
