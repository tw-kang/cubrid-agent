# 배포 구조 — 자산 3계층 모델

cubrid-agent를 팀원 머신과 k8s pod에 배포하는 구조의 정본. 실행 가이드는 [setup.md](./setup.md), 롤아웃 단계는 CUBRIDQA-1425(이 repo가 관리하지 않는다), 부품 스킬 흡수·플러그인 재패키징은 [ADR 0001](../.agents/adr/0001-repackage-as-plugin.md), 이중 채널 배포는 [ADR 0002](../.agents/adr/0002-dual-channel-distribution.md).

**원칙 한 줄: 문서는 사람에게, 스크립트는 머신에게, 자격은 Secret에게.**

## 자산 3계층

머신(팀원 로컬이든 pod든)에 도달해야 하는 모든 자산을 전달 방식으로 3계층으로 나눈다:

| Tier | 정의 | 자산 | 전달 |
|---|---|---|---|
| **1. clone이 나른다** | git 버전관리 | cubrid-agent 루트 플러그인 — **자기완결** 스킬 22종(연료 포함, 별도 repo 없음 — ADR 0001) + hook `hooks/`+`scripts/` + 매니페스트 `.claude-plugin/`. **파일은 22종이 다 오지만 로드는 `skills/qa/`의 6종**(setup 1 + 파이프라인 5 = `plugin.json` 등재분)이고, `skills/in-progress/`의 부품 16종은 `npx skills add` 채널 전용이다([ADR 0006](../.agents/adr/0006-shipped-vs-in-progress-skill-trees.md)). `docs/`는 dev-only — 실행에 불필요 | `git clone` 또는 `claude plugin install` |
| **2. 스크립트가 만든다** | 재현 가능한 머신 상태 — **`$HOME` 표준 배치** | 테스트케이스 clone(+`fork` 리모트, 경로는 D7의 오버라이드 규약)·`~/cubrid`·CTP(`~/cubrid-testtools/CTP`), `~/.cubrid-agent/`(env.sh·manifest·reports·worktrees), (옵션) `$HOME/CUBRID` 빌드. **conf 사본은 setup이 만들지 않는다** — CTP 원본 conf가 이미 비기본 포트이고, `scenario=`는 `verify-run.sh`가 매 실행 run 디렉토리 사본에 덮어 쓴다 | **`/cubrid-agent:setup-cubrid-agent`** (= `skills/qa/setup-cubrid-agent/scripts/setup.sh`, 멱등·비대화식, 기존 clone 불가침 — [ADR 0003](../.agents/adr/0003-setup-entrypoint-skill.md)) |
| **3. 사람이 넣는다** | 자격 — repo 금지 | cubrid-jira 자격, gh 인증 | env(표준) 또는 .netrc/`gh auth login` |

## 확정 결정

| # | 결정 | 내용 |
|---|---|---|
| D1 | 부품 스킬 전달 | **repo에 내장** — 흡수(ADR 0001)로 스킬 22종이 포함되고, 배포분 6종(setup 1 + 파이프라인 5)은 `skills/qa/`, 부품 16종은 `skills/in-progress/`에 나뉜다(ADR 0006). clone/플러그인 설치가 곧 **파일** 전달 — 별도 clone·심링크 불필요. 단 **로드**는 `skills/qa/`의 6종만이며 부품 16종은 `npx skills add`로 깔아야 스킬로 뜬다 |
| D2 | setup.sh 범위 | **이슈무관 상태 전부 + 빌드는 `--build <url>` 옵션**. 신뢰 빌드는 이슈 의존이라 setup에 고정 불가 — 이슈별 빌드 교체는 파이프라인(verify)이 담당 |
| D3 | 경로 규약 | **`$HOME` 규약 + 자동탐지** — CUBRID=`$HOME/CUBRID`(소켓 108자 충족), JDK는 javac에서 탐지. 새 환경변수 도입 안 함 |
| D4 | 자격 표준 | **env 표준**(`CUBRID_JIRA_USER/PASSWORD`, `GH_TOKEN`) — cubrid-jira의 에이전트 권장 순서와 일치. 팀원 머신은 .netrc·`gh auth login` 병행 허용, **pod는 Secret→env만** |
| D5 | 컨테이너 이미지 | **setup 스크립트 재사용 원칙만 확정**(비대화식·멱등·`$HOME` 규약·CWD 비의존 → `RUN skills/qa/setup-cubrid-agent/scripts/setup.sh` 가능). 이미지 선택(cubridci 확장 vs 신규)은 미확정 — CUBRIDQA-1425 |
| D6 | 문서 위치 | 이 문서가 배포 정본, setup.md는 실행 가이드, 재패키징·채널 결정은 ADR 0001·0002 |
| D7 | **런타임 = `$HOME` 표준** | 소스·도구·빌드는 `$HOME` 배치(`~/cubrid-testcases`·`~/cubrid`·CTP·`$HOME/CUBRID`), 실행 산출물(manifest·리포트·worktree)은 **`~/.cubrid-agent/`**. 실행 하나가 남기는 나머지도 전부 **run 디렉토리 `~/.cubrid-agent/<KEY>/`**(manifest와 같은 자리)에 두고, 홈이나 cwd에 쓰거나 새 디렉토리를 만들지 않는다 — 컨테이너에선 홈이 곧 이미지 레이어라 잔여 파일이 그대로 굳는다(setup.md §7). `CUBRID_TESTCASES` 오버라이드로 clone 자체를 바꿀 수 있다(부품 스킬과 동일 해석 규약). 다만 `~/cubrid-testcases`가 사람 작업장이라서 격리가 필요한 경우라면 **별도 clone을 만들 필요가 없다** — author-testcase가 `prepare-tc-workspace.sh`로 판정해 worktree(`~/.cubrid-agent/worktrees/`)로 격리한다. review-testcase도 같은 스크립트를 `--pr N`으로 불러 PR을 detached worktree로 받는다(브랜치 안 만들고 clone 안 건드림) |
| D8 | **스킬 자기완결** | 스킬·hook은 `docs/`를 런타임 참조하지 않는다(배포 부자재 최소화). review-testcase 연료(few-shot bank·관점 카탈로그)는 스킬 `references/`에 내장. `docs/`는 dev-only |

## pod 배포 매핑 (방향만 — 미확정)

| pod 요소 | 이 모델에서 |
|---|---|
| 컨테이너 이미지 | Tier 1 clone + `RUN skills/qa/setup-cubrid-agent/scripts/setup.sh`(Tier 2 bake). 이미지 베이스 선택은 착수 시 (D5) |
| CUBRID 빌드 | 이미지에 굽지 않음 — build-cache overlay 마운트(CUBRIDQA-1429). 로컬↔pod 차이는 "빌드 설치 vs 마운트" 한 지점으로 국소화. BUILD_SHA 자동 pin은 미확정(CUBRIDQA-1425) |
| 자격 | k8s Secret → env(`CUBRID_JIRA_USER/PASSWORD`, `GH_TOKEN`) — D4의 env 표준이 그대로 Secret 주입 형식 |
| 기동 | CronJob → headless 세션(`/cubrid-agent:author-testcase` 등). dispatcher·fan-out·self-healing은 park(staging.md) |
