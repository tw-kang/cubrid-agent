# Rollout 단계 (staging)

에이전트 롤아웃을 **PoC / Stage 2 / Stage 3** 3단계로 나눈다. 결정 근거는 [ADR 0007](./adr/0007-rollout-stages.md), 용어 지도는 [CONTEXT-MAP.md](../CONTEXT-MAP.md).

## 3단계 모델

| 단계 | 형태 | 트리거 | 검증 환경 | Jira | 상태 |
|---|---|---|---|---|---|
| **Stage 1 — PoC** | 로컬 Claude Code 세션 | 사람이 세션에서 수동, 게이트마다 확인 | 로컬 CTP (`$HOME/CUBRID`) | 읽기 전용 | author-testcase 완료 (PR #3041·#3049) |
| **Stage 2 — 팀내 수동 트리거** | 로컬 세션 **팀 공유**(스킬+setup.sh+hook) | 팀원이 각자 로컬에서 기동 커맨드 | 로컬 CTP | 쓰기: targeted=실제, batch=초안 (ADR 0016) | 1순위 3종 패키징 완료 |
| **Stage 3 — 무인 자동 서비스** | k8s CronJob → (Indexed) Job | 야간 스케줄 자동 | pod + build-cache overlay (ADR 0001) | 쓰기(전이+코멘트) | **park** |

핵심: Stage 2는 "배포"가 아니라 PoC 로컬 흐름을 **팀이 재현하도록 패키징**한 것. 인프라(k8s·GlusterFS·CronJob)는 전부 Stage 3. Stage 2가 더하는 것은 **품질 게이트의 강제화**(hook)와 **CCI 교차**, 그리고 **팀 셋업 자동화**(setup.sh + [guides/stage2-setup.md](./guides/stage2-setup.md))다.

**에이전트 배포 우선순위**: ① **gate-resolved · author-testcase · review-testcase** — QA to-do(Resolved) 진입부터 TC PR 머지까지 커버, 팀이 바로 쓸 3종 → ② **test-runner** — 머지 후 qaresu 회귀 판독 → ③ **close-backport** — 종결/백포트. test-runner는 판독형이라 PR 머지 후에야 동작하고, close-backport는 종결 단계라 뒤로 둔다.

## Stage 2 구성 (현행)

- **기동 스킬 3종** `skills/qa/{gate-resolved,author-testcase,review-testcase}/` — 스킬명 = 에이전트명. 팀과 git으로 공유. 자기완결(스킬은 docs/를 참조하지 않는다 — deployment.md D8).
- **팀 셋업** — `install` → `/setup-cubrid-agent` → 자격 주입(repo 개발자는 `skills/qa/setup-cubrid-agent/scripts/setup.sh` 직접 실행). 가이드 [guides/stage2-setup.md](./guides/stage2-setup.md).
- **하드 게이트 = hook** ([hooks/](../hooks/)) — 결정성·fail→pass·리뷰 PASS·CCI·컨벤션 린트가 run manifest로 확인되지 않으면 TC PR 제출 차단.
- **CCI 교차 검증** — `run_cci`로 재실행, 기본 sql(JDBC) 출력과 다르면 `.answer_cci`.
- **Jira 쓰기 (완성 정의 = 실제 쓰기, [ADR 0016](./adr/0016-completion-is-real-write.md))** — 사람이 키를 **나열**한 targeted 호출은 전이·코멘트·필드를 실제로 쓴다. **JQL/큐 배치 호출은 초안** 유지, 오탐 가드가 걸리면 초안+@질의로 강등. 무인 트리거/cron 자동 호출은 여전히 Stage 3(호출 축).
- **멱등성** — 결정적 브랜치/PR 이름(`tc/cbrd-XXXXX`), 기존 존재 시 스킵.

## 단계 결정 (grilling 확정)

| # | 결정 | 값 |
|---|---|---|
| S1 | Stage 2 실행 형태 | 로컬 세션 팀 공유 (k8s Job 아님) |
| S2 | fail→pass 실측 회귀 계약 | PoC부터 |
| S3 | CCI 교차 검증 | Stage 2부터 |
| S4 | Jira 쓰기 | **완성=실제 쓰기, Stage 2부터** (targeted=실제/batch=초안, 가드 강등 — [ADR 0016](./adr/0016-completion-is-real-write.md)). 무인 자동 호출·batch 무인 쓰기는 Stage 3 |
| S5 | 하드 게이트 hook 강제 | Stage 2부터 |

기본값: 결정성 반복 **N=3**; SQLancer 오라클 park.

**결정성 실행 방식 (2026-07-22 확정)**: N회는 **한 CTP 세션에서 `run <case>`×N**으로 돌린다(개별 ctp.sh N회 아님). 실측상 세션 setup(~85s: JVM+DB 생성+서버)이 비용을 지배하고 세션 내 추가 run은 ~1.5s라, N=3가 N=1과 사실상 동가(결정성블록 ~255s→~88s). 게다가 같은-DB 반복이라 regression(전 TC가 공유 DB 연속 실행)에 더 충실하고 cleanup 누락(비-self-contained TC)까지 잡는다. verify 전체는 6→3세션(생성/confirm+determinism/CCI).

## Stage 3 park 목록

CronJob 야간 배치·Argo 판단·dispatcher/Indexed Job fan-out·BUILD_SHA 자동 pin·rate-limit 분리·self-healing 재시도/에스컬레이션·overlay 런타임 경합 관리·무인 관측·야간배치 vs 상시드레인·SQLancer 오라클. (pod 검증은 ADR 0001, 이미지 방향은 deployment.md D5.)

**[ADR 0016로 이동]** "상태전이=완료마커" 쓰기 자체는 Stage 2로 내려왔다(targeted 실제 쓰기). Stage 3에 남는 것은 그 쓰기를 **무인으로** 돌리는 부분(트리거/cron 호출 + batch 무인 쓰기 + self-healing 루프)이다.

## 잔여 작업

- **CBRD-25913 fail→pass 소급 실측**: PR #3041은 제출됐으나 pre-fix FAIL 실측 전 — fix 이전 빌드로 확인(결정적이라 명확히 FAIL 예상).
- **CBRD-26799 fail→pass**: race라 pre-fix FAIL도 확률적 — 로컬 미재현, CI/저사양 환경 몫(한계는 PR에 명시됨).
- PR #3041·#3049 리뷰·머지 → test-runner 판정 시연.
