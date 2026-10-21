# cubrid-agent — Agent Instructions

CBRD 이슈 워크플로의 상태 전이를 맡는 에이전트들의 모노레포. 용어는 루트 [`GLOSSARY.md`](./GLOSSARY.md)를, 파이프라인 지도와 에이전트 로스터는 [`docs/pipeline.md`](./docs/pipeline.md)를 먼저 읽는다.

이 파일은 여러 CLI 에이전트 도구(Claude Code, Codex, Cursor, Gemini 등)가 공유하는 정본이다. `CLAUDE.md`는 이 파일로의 심링크다.

## 저장소 배치

문서를 "배포되는가·누가 읽는가"로 나눈다.

- **루트 플러그인 = 제품(배포되는 전부):** `.claude-plugin/plugin.json` · `skills/qa/` · `hooks/` · `scripts/`의 훅 스크립트. 저장소의 존재 이유. `scripts/`의 나머지는 개발 도구이고 배포면 밖이다. 배포면 경로 목록의 정본은 `scripts/release.sh`의 `SHIPPED_PATHS`다. **스킬은 전부 이 repo에 있다** — 외부 skills repo도 심링크 설치도 없다. **`skills/qa/`는 `plugin.json` 등재분과 정확히 일치**하고, 아직 배포하지 않는 스킬은 `skills/in-progress/`에서 개발한다 — 완성되면 이동+등재로 승격한다.
- **`docs/agents/` = 에이전트용 규범(횡단):** `design-principles.md`(DP1 병렬 실행, **DP2 사용자 관점·블랙박스 테스트**, DP3 언어 정책), `issue-tracker.md`, `triage-labels.md`, `domain.md`.
- **`docs/` = 사람용 런북/참조:** 설치(setup), 배포 구조(deployment), 공식 dev-process, 파이프라인 지도·에이전트 로스터(pipeline). 외부 기여자는 제품 + 이 파일 + `GLOSSARY.md` + `docs/pipeline.md`로 충분하다.
- **루트 `GLOSSARY.md`:** 단일 용어집.
- **Jira(CUBRIDQA):** 에이전트·스킬 설계(DESIGN, 방법론 ADR, staging, hook-gates 설계)와 결정의 이유. 역사는 git commit이 보존한다. 그래서 repo에서 뺀 문서는 지운다 — 아카이브 디렉토리에 두지 않는다.

공유 자산(코드 아님): `cubrid-jira` CLI, 소스 repo(cubrid, cubrid-testcases, cubrid-testtools 등), 사내 빌드서버, 로컬/pod 검증 환경.

## 개발 방식 — 이 repo를 고칠 때 지키는 두 가지

clone해서 개발하는 사람도 대개 AI 에이전트로 작업한다. 그래서 방식을 여기 적는다 — 이 파일이 어떤 CLI 도구에서든 가장 먼저 읽히는 정본이기 때문이다.

- **코드로 가능한 것은 최대한 코드로, LLM은 판단에 쓴다.** 기계적으로 결정되는 일(분류·추출·규칙 검사·카운팅·상태 기록)은 `scripts/`·`hooks/`가 하고, 스킬 산문은 판단만 담는다. 새 규칙을 스킬에 적기 전에 **"훅이나 스크립트가 이걸 판정할 수 있나"를 먼저 묻는다** — 할 수 있으면 코드로 옮기고 스킬엔 한 줄만 남긴다. 근거(TC 1건 62분의 원인)와 코드/LLM 경계표는 `docs/agents/design-principles.md` DP6.
- **한 번만, 짧게, 한 가지로만 읽히게.** 두 갈래로 읽히는 규칙은 실제로 틀린 쪽으로 읽혔고(CUBRIDQA-1486, 반년 디렉토리), 복붙된 규칙은 다르게 낡았다(첨부 문단 12곳 중 PDF 주의가 3곳에만 닿음). 같은 사실은 한 곳에 두고 두 번째 자리엔 링크만 두며, 독자의 행동을 바꾸지 않는 문장은 지운다. 근거는 `docs/agents/design-principles.md` DP7. **스킬 본문을 줄일 때는 `scripts/rule-inventory.sh <ref> <SKILL.md>`로 규칙 손실 0을 확인한다** — bold·backtick·헤딩 인벤토리를 diff하므로, 근거를 걷어냈는지 규칙을 지웠는지가 눈이 아니라 목록으로 갈린다. 매 턴 로드되는 것은 `SKILL.md`뿐이니 세부는 `references/`로 옮기고 **본문에서 반드시 링크한다**(링크 없는 참조는 삭제와 같다 — invariant가 잡는다).
- **변경은 스킬 체인으로 굴린다**: 지도(`/wayfinder`) → `/to-spec` → `/to-tickets` → `/implement-spec`(작은 일은 `/implement`) → `/code-review`.
  - 지도는 결정만 담는다. 실행은 스펙과 그 티켓으로 한다.
  - **`/implement`는 항상 `/code-review`(Standards+Spec 2축)로 닫는다.** 안에서 `/tdd`를 쓴다.
  - 여러 세션짜리면 `/to-tickets`까지를 **한 컨텍스트 안에서** 끝낸다(중간에 compact하면 spec과 티켓이 다른 사고 위에 얹힌다).
  - 티켓의 자리, 배정, claim, 결과 기록, PR 흐름은 `docs/agents/issue-tracker.md`에 있다.
  - **`/retro`는 세 경우에만 세션을 닫기 전에 부른다**: 같은 작업을 다시 했을 때, 보고와 실물이 어긋났을 때, 사용자가 정정했을 때.
  - 이 스킬들은 이 repo가 아니라 `mattpocock-skills` 플러그인에서 온다 — 없으면 `claude plugin install mattpocock-skills@claude-plugins-official`, 어떤 걸 쓸지 모르면 `/ask-matt`.

## 변경을 내보낼 때 — 흐름과 형식

흐름은 이 repo가 정했다. 형식은 CUBRID 사내 규칙이라 취향이 아니다.

### 흐름 — 브랜치 · PR · 머지 · 릴리스

- **브랜치**: `main`은 릴리스, `develop`은 개발이다.
- **PR은 배포면을 바꿀 때만 낸다.** 배포면은 `scripts/release.sh`의 `SHIPPED_PATHS`다. 그 밖의 변경(문서, 개발 도구)은 `develop`에 직접 커밋한다. tc repo에는 언제나 PR로 낸다.
- **PR 하나 = Jira sub-task 하나.** Draft로 열고, 헤더는 헤드 키다. 사람의 "머지 준비" 지시를 기다린다. 머지 준비, 머지 뒤, Reopen의 순서는 `docs/agents/issue-tracker.md`의 "PR 흐름" 절에 있다.
- **커밋 제목에 이슈 키를 붙이지 않는다.** 키는 PR 제목에만 붙는다.
- **배포면은 릴리스 PR(`develop`→`main`)로만 사용자에게 나간다.**
- **배포면을 바꾼 커밋은 같은 커밋에서 `CHANGELOG.md`의 `[Unreleased]` 절에 항목 하나를 넣는다.** 항목은 자리 태그로 시작한다 — `- (major)`·`- (minor)`·`- (patch)` 중 하나다. push 전에 `scripts/release.sh check`로 확인한다.
  - 자리의 뜻은 `CHANGELOG.md`의 Version note가 정본이다. 경계는 manifest 호환이다.
  - 게이트를 더 세게 걸었다 → minor. manifest에 필드를 더했다 → minor. 옛 run 디렉토리를 더 못 읽는다 → major.
  - major에 유예 기간을 두지 않는다. 대신 그 항목에 팀원이 무엇을 바꿔야 하는지 적는다.
- **릴리스는 `scripts/release.sh`가 낸다.** 범프·태그·GitHub Release를 손으로 만들지 마라. 모드는 셋이다 — `check`(상태 검사), `next`(다음 버전 계산), `run --trigger <1|2|3>`(릴리스 실행). 트리거가 충족되면 사람을 기다리지 말고 실행한다.
  - 트리거 1: 팀원이 기다리는 결함 수정은 바로 릴리스한다.
  - 트리거 2: 기능이 완결되면 그 자리에서 릴리스한다.
  - 트리거 3: 그 밖에는 쌓는다. 단 `[Unreleased]`에 7일 넘게 두지 않는다.
- **브랜치 이름(`cubridqa-<헤드 키 번호>-<내용>`), PR 헤더, 배포면 직접 커밋은 `validate`가 검사한다** — `scripts/check-pr-push.sh`. 헤드 키 목록은 `.github/head-keys.txt`다.
- **`develop`에는 squash 머지만 들어간다 — GitHub 설정(linear history, rebase 머지 끔)이 강제한다.** `develop`의 관리자 우회는 릴리스 범프의 직접 push 때문에 둔다. 설정을 바꾸면 `gh api`로 다시 읽어 값을 확인한다.
- **경고 — 범프는 반드시 `develop`에 먼저 올라간다.** 기존 설치본의 마켓플레이스 clone은 `develop`만 받은 shallow clone이다. `main`에만 올라간 범프는 그들에게 도착하지 않고, 오류도 나지 않는다.
- **릴리스는 PR 규칙, 브랜치 규칙, PR 헤더 규칙의 예외다.** 범프 커밋은 배포면을 바꾸지만 `develop`에 직접 push된다. PR 제목은 `Release vX.Y.Z`이고 커밋 제목은 `Release vX.Y.Z (trigger N)`이다. 셋 다 `release.sh`가 한다.

버저닝·릴리스를 왜 이렇게 정했는지는 CUBRIDQA-1508에 있다.

### 형식 — PR · 커밋 · Jira

- **PR 본문 형식**: [`.github/PULL_REQUEST_TEMPLATE.md`](./.github/PULL_REQUEST_TEMPLATE.md) — 이 repo로 PR을 올리면 자동으로 채워지고, 절별로 무엇을 쓰는지도 그 파일 안에 있다(`CUBRID/cubrid`의 같은 파일과 동일한 형식). 내용은 **한글·사용자 관점**이다 — "무엇을 적용해서 어떤 동작이 바뀌었다"이고 **코드 구현 설명이 아니다**.
- **`/pr`은 이 템플릿 안에서만 쓴다.** `/pr`의 전후 증거는 Implementation에, 되돌릴 수 있는지 판단(Door, Blast Radius)은 Remarks에 넣는다. 절은 템플릿의 셋(Purpose, Implementation, Remarks)뿐이다.
- **PR 제목**: 항상 **영어**, `[CUBRIDQA-XXXX]`로 시작(엔진 repo는 `[CBRD-XXXXX]`). 예외는 릴리스 PR 하나다 — 위 흐름 절을 보라.
- **엔진 repo 커밋**은 `[CBRD-XXXXX]`로 태깅한다.
- **`CUBRID/cubrid-testcases`에는 PR 템플릿이 없다.** TC PR 본문은 사람이 짜지 않는다 — `author-testcase`의 Submit 절이 부르는 `render-pr-body.sh`가 manifest와 `.sql`에서 만든다.
- **head→base**: 이 repo는 같은 repo의 브랜치 → `develop`이다. CUBRID repo는 `$FORK:<branch>` → `CUBRID/<repo>:develop`이다. `$FORK`는 `$CUBRID_GH_FORK` 또는 `gh api user --jq .login`으로 **런타임에 구한다 — 사람 이름을 박지 않는다.** 예외는 둘이다. 배포처(`tw-kang/cubrid-agent` — 매니페스트의 owner·author, 설치 명령)는 팀이 함께 쓰는 자원이라 그대로 둔다. 인용의 출처 표기(`few-shot-bank.md`의 `PR1844 / tw-kang` 등)도 그대로 둔다 — 이름만 골라 지우면 인용이 조작된다.
- **Jira 쓰기**는 `cubrid-jira`로 하고 **`--yes`가 없으면 dry-run**이다. `--description-file`은 기존 description을 **replace**한다(history엔 남는다). 쓰기 전에 dry-run 출력과 로컬 파일을 대조하라 — CLI가 한글과 인라인 마크업 사이에 공백을 넣는다.
- **CBRD 이슈 description은 권고이지 강제가 아니다.** 공식 템플릿은 존재하지 않는다(10년치 CBRD에 정의한 티켓 0건). 관례만 있다 — 버그는 `Repro`·`Expected Result`·`Actual Result`·`Test Build`, 그 외는 `Description`·`Implementation`·`Specification Changes`·`Acceptance Criteria`·`Definition of Done`. 채택률이 41~76%라 강제하면 CBRD 자신보다 엄격해진다. CBRD가 실제로 요구하는 것은 절 구조가 아니라 **description만 읽고 무엇이 바뀌었는지 이해되는 자립성**이다(`docs/dev-process.md` p17). 참고: 일부 이슈의 `{anchor:...}` 절은 템플릿이 아니라 **AI 도구가 남긴 흔적**이니 따라 쓰지 마라.

## Language policy — 배포 대상은 영문, 미배포는 한글

배포 대상(외부·타 CLI·마켓플레이스로 나가는 것)은 **영문**, 배포 미대상(팀·개발자만 읽는 것)은 **한글**로 쓴다.

- **영문(배포 대상)**: 스킬 `SKILL.md`(`name`·`description`·본문·`references/`·`evals/`), 플러그인 매니페스트(`.claude-plugin/plugin.json`·`marketplace.json`), `hooks/`·`scripts/`, 루트 `README.md`·`CHANGELOG.md`·`LICENSE`·`package.json`.
- **한글(배포 미대상)**: `docs/`(런북·참조, `docs/agents/` 규범), 이 `AGENTS.md`·`GLOSSARY.md`, 로컬 트래커(`.scratch/`)의 지도·스펙·티켓, Jira 티켓(CUBRIDQA) 본문.
- **예외 (기능적 한글 유지)**: 스킬 `description`은 영문으로 쓰되 **한글 트리거 키워드는 유지**한다(팀이 한글로 스킬을 부르므로 트리거 정확도 확보). 예: `… Use when someone says "이 PR 리뷰해줘", "gate-resolved 돌려줘", …`. 같은 이유로 eval의 `prompt`(트리거 입력)와 스킬이 Jira/GitHub에 게시하는 산출물(반송 코멘트·리뷰 초안 등)·few-shot으로 인용한 리뷰어 코멘트 원문도 한글이다 — 감싸는 지시문만 영문. **실행 리포트도 같다**: `~/.cubrid-agent/reports/`에 쓰이는 본문은 팀이 읽는 것이라 한글이고(그래서 `render-report.sh`·`select-queue.sh`가 한글 문장을 만든다), 스크립트 자신의 주석과 에이전트에게 찍는 메시지는 영문이다. **이 목록이 정본이다**; 예외가 왜 존재하는지(영문화가 취향이 아니라 동작 변경이 되는 이유)는 `docs/agents/design-principles.md` DP3.

## Agent skills

### Issue tracker

Jira 헤드(목표) → Jira sub-task(PR) → 로컬 markdown 티켓(`.scratch/`)의 세 단계다. GitHub Issues는 쓰지 않는다. See `docs/agents/issue-tracker.md`.

### Triage labels

트리아지 라벨은 쓰지 않는다. See `docs/agents/triage-labels.md`.

### Domain docs

단일 컨텍스트 — 용어집은 루트 `GLOSSARY.md` 하나다. ADR은 만들지 않는다. See `docs/agents/domain.md`.
