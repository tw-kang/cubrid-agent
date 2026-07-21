# 배포 구조 — 자산 3계층 모델 (Stage 2 · Stage 3 공통)

cubrid-agent를 팀원 머신(Stage 2)과 k8s pod(Stage 3)에 배포하기 쉽게 만드는 구조의 정본. 실행 가이드는 [stage2-setup.md](./stage2-setup.md), 단계 모델은 [staging.md](./staging.md), 부품 스킬 경계 결정은 [ADR 0011](./adr/0011-part-skills-boundary.md). (2026-07-21 grilling으로 확정.)

**원칙 한 줄: 문서는 사람에게, 스크립트는 머신에게, 자격은 Secret에게.**

## 자산 3계층

머신(팀원 로컬이든 pod든)에 도달해야 하는 모든 자산을 전달 방식으로 3계층으로 나눈다:

| Tier | 정의 | 자산 | 전달 |
|---|---|---|---|
| **1. clone이 나른다** | git 버전관리 | cubrid-agent(**자기완결** 오케스트레이터 스킬 3종 `.claude/skills/` — tc-reviewer 연료 포함, hook `.claude/hooks/`+`settings.json`) + **tw-kang/skills**(부품 스킬 9카테고리×2, 별도 repo — ADR 0011). `agents/`·`docs/`는 dev-only 설계 기록(실행에 불필요) | `git clone` |
| **2. 스크립트가 만든다** | 재현 가능한 머신 상태 — **`$HOME` 표준 배치** | `~/cubrid-testcases`(+twkang)·`~/cubrid`·CTP(`~/cubrid-testtools/CTP`), 부품 스킬 심링크, `~/.cubrid-agent/`(env.sh·manifest·reports·worktrees), (옵션) `$HOME/CUBRID` 빌드. **conf 사본 불필요** — CTP 원본 conf가 이미 `scenario=${HOME}/cubrid-testcases/sql`·비기본 포트 | **`./setup.sh`** (멱등·비대화식, 기존 clone 불가침) |
| **3. 사람이 넣는다** | 자격 — repo 금지 | cubrid-jira 자격, gh 인증 | env(표준) 또는 .netrc/`gh auth login` |

## 확정 결정 (grilling 2026-07-21)

| # | 결정 | 내용 |
|---|---|---|
| D1 | 부품 스킬 전달 | **clone+심링크** — setup.sh가 `~/skills`(tw-kang/skills)를 clone/pull하고 필요 스킬만 `~/.claude/skills/`에 심링크. 정본은 skills repo 유지(편입·submodule 기각 — ADR 0011) |
| D2 | setup.sh 범위 | **이슈무관 상태 전부 + 빌드는 `--build <url>` 옵션**. 신뢰 빌드는 이슈 의존이라 setup에 고정 불가 — 이슈별 빌드 교체는 파이프라인(verify)이 담당 |
| D3 | 경로 규약 | **`$HOME` 규약 + 자동탐지** — CUBRID=`$HOME/CUBRID`(소켓 108자 충족), work=repo 상대(절대화는 conf 생성 시), JDK는 javac에서 탐지. 새 환경변수 도입 안 함 |
| D4 | 자격 표준 | **env 표준**(`CUBRID_JIRA_USER/PASSWORD`, `GH_TOKEN`) — cubrid-jira의 에이전트 권장 순서와 일치. Stage 2는 .netrc·`gh auth login` 병행 허용, **Stage 3는 Secret→env만** |
| D5 | Stage 3 이미지 | **setup.sh 컨테이너 재사용 원칙만 확정**(비대화식·멱등·`$HOME` 규약 → `RUN ./setup.sh` 가능). 이미지 선택(cubridci 확장 vs 신규)은 Stage 3 착수 시 — park 유지 |
| D6 | 문서 위치 | 이 문서가 정본, stage2-setup.md는 실행 가이드로 축소, 부품 스킬 경계는 ADR 0011 |
| D7 | **런타임 = `$HOME` 표준** (2026-07-21 추가) | 소스·도구·빌드는 `$HOME` 배치(`~/cubrid-testcases`·`~/cubrid`·CTP·`$HOME/CUBRID`), 실행 산출물(manifest·리포트·worktree)은 **`~/.cubrid-agent/`**. **repo의 `work/`는 PoC 환경격리 유물** — 배포 계약에서 제외. 격리가 필요한 머신(예: `~/cubrid-testcases`가 사람 작업장)은 `CUBRID_TESTCASES` 오버라이드(부품 스킬과 동일 해석 규약) |
| D8 | **스킬 자기완결** (2026-07-21 추가) | 스킬은 `agents/`를 런타임 참조하지 않는다(부자재 최소화 — 간편 배포). tc-reviewer 연료(few-shot bank·관점 카탈로그)는 스킬 `references/`로 이동. `agents/`는 dev-only 설계 기록 |

## 마찰 → 해소 매핑

zoom-out(2026-07-21)에서 식별한 배포 마찰 5개와 처리:

| # | 마찰 | 해소 |
|---|---|---|
| M1 | Tier 2가 문서(복붙 명령)였음 | **setup.sh로 스크립트화** — 같은 스크립트가 팀원 머신과 pod을 프로비저닝 |
| M2 | 부품 스킬 채널 단절("미배포"는 낡은 전제 — tw-kang/skills + `npx skills add` 채널 기존재) | setup.sh가 clone+심링크로 채널 연결 (D1) |
| M3 | 경로 가정 산재(`/home/dev/...`, `work/` 상대경로) | `$HOME` 규약 + 탐지 (D3·D7) — work/ 이중 clone·conf 사본 제거로 배포 부자재 축소 |
| M4 | 신뢰 빌드 수동 pin | Stage 2는 유지(`--build <url>` + 파이프라인 확인). **BUILD_SHA 자동 선정은 Stage 3 이연**(기존 DESIGN 항목) |
| M5 | 자격 이중화(.netrc vs env) | env 표준·netrc 병행, Stage 3에서 env 수렴 (D4) |

## Stage 3 매핑 (park — 방향만)

| Stage 3 요소 | 이 모델에서 |
|---|---|
| 컨테이너 이미지 | Tier 1 clone + `RUN ./setup.sh`(Tier 2 bake). 이미지 베이스 선택은 착수 시 (D5) |
| CUBRID 빌드 | 이미지에 굽지 않음 — build-cache overlay 마운트(ADR 0001). 로컬↔pod 차이는 "빌드 설치 vs 마운트" 한 지점으로 국소화 |
| 자격 | k8s Secret → env(`CUBRID_JIRA_USER/PASSWORD`, `GH_TOKEN`) — D4의 env 표준이 그대로 Secret 주입 형식 |
| 기동 | CronJob → headless 세션(`/resolve-next` 등). dispatcher·fan-out·self-healing은 v1 배포 설계 분류대로 park |
