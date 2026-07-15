# Rollout 단계와 핸드오버 문서 분류

두 외부 핸드오버 문서(v1 배포 설계, v2 TC 작성 웹검증판)를 재료로, 각 항목을 **PoC / Stage 2 / Stage 3**로 나눈 정리본. Stage 2(팀내 수동 트리거)를 이번 설계 대상으로 하고, Stage 3(무인 자동 서비스)은 park한다. 결정 근거는 [ADR 0007](./adr/0007-rollout-stages.md), 용어 지도는 [CONTEXT-MAP.md](../CONTEXT-MAP.md).

## 3단계 모델

| 단계 | 형태 | 트리거 | 검증 환경 | Jira | 상태 |
|---|---|---|---|---|---|
| **Stage 1 — PoC** | 로컬 Claude Code 세션 | 사람이 세션에서 수동, 게이트마다 확인 | 로컬 CTP (`/home/dev/CUBRID`) | 읽기 전용 | tc-author 1·2호 완료 (CBRD-25913·26799) |
| **Stage 2 — 팀내 수동 트리거** | 로컬 세션 **팀 공유**(스킬+셋업+hook) | 팀원이 각자 로컬에서 기동 커맨드 | 로컬 CTP | 읽기 전용 | 이번 설계 대상 |
| **Stage 3 — 무인 자동 서비스** | k8s CronJob → (Indexed) Job | 야간 스케줄 자동 | pod + build-cache overlay (ADR 0001) | 쓰기(전이+코멘트) | **park** |

핵심: Stage 2는 "배포"가 아니라 PoC 로컬 흐름을 **팀이 재현하도록 패키징**한 것. 인프라(k8s·GlusterFS·CronJob)는 전부 Stage 3. Stage 2가 더하는 것은 **품질 게이트의 강제화**(hook)와 **CCI 교차**, 그리고 **팀 셋업 문서/스킬**이다.

## Stage 2 설계 (팀내 수동 트리거)

> 상세 구현 스펙(오케스트레이터·manifest·hook·셋업·CCI): [stage2-design.md](./stage2-design.md). 아래는 요약.

목표: PoC에서 검증된 파이프라인을, 팀원이 **자기 로컬에서 커맨드 하나로** 돌리고 Draft PR까지 내되, 필수 게이트는 우회 불가하게 만든다. 형태 결정: **얇은 오케스트레이터**(`resolve-next`가 Select/Ground/Review/loop/Submit, Author/Verify는 기존 create/verify 스킬 호출).

구성:
- **기동 스킬** `.claude/skills/resolve-next/` — `/resolve-next [N | CBRD-XXXXX]`. Select→Ground→Author→Verify→Review→(loop)→Submit 오케스트레이션. 팀과 git으로 공유(버전관리).
- **팀 셋업 문서** — 로컬 CTP·CUBRID 설치(짧은 경로, JDK), 빌드서버 URL 규칙, `cubrid-jira`/`gh` 인증. PoC에서 규명한 함정(소켓 108자, JRE≠JDK, empty-answer)을 셋업 가이드로.
- **하드 게이트 = hook** — 스킬/CLAUDE.md는 '요청'이라 우회 가능하므로, 필수 게이트는 hook으로 강제:
  - fail→pass 미확인 TC의 Submit 차단
  - 결정성 반복(N회) 미통과 차단
  - 컨벤션 린트(헤더/evaluate/경로/answer-not-handwritten)
- **CCI 교차 검증** — 공식 9단계 step 6(`run_cci`) 추가, csql과 결과가 다르면 `.answer_cci` 생성.
- **Jira 읽기 전용 유지** — 전이·코멘트는 Stage 3. Stage 2는 사람이 PR 검토 후 수동 전이.
- **멱등성** — 결정적 브랜치/PR 이름(`tc/cbrd-XXXXX`), 기존 브랜치/PR 존재 시 스킵(PoC와 동일).

Stage 2에서 **하지 않는 것**: k8s Job/pod 검증, dispatcher, 병렬 fan-out, 자동 스케줄, Jira 쓰기, self-healing 재시도/에스컬레이션 — 전부 Stage 3.

## v1(배포 설계) 문서 항목 분류

| 항목 | 단계 | 비고 |
|---|---|---|
| CronJob 야간 배치(timeZone/concurrencyPolicy/deadline) §3 | Stage 3 | 무인 스케줄의 본체 |
| Argo Workflows 도입 판단 §3 | Stage 3+ | per-issue 재시도·DAG 필요해질 때만 |
| 단일 파드 순차 루프 §4.1 / dispatcher+Indexed Job §4.2 | Stage 3 | fan-out·claim 없는 분배 |
| 신뢰 빌드 = CI 산출물 재사용 §5a | PoC (부분) | 이미 빌드서버 산출물 재사용 중 |
| 아티팩트 커밋 SHA/빌드 ID pin §5b | Stage 2~3 | PoC는 빌드 URL로 수동 pin; 다건이면 규칙화 |
| 병렬성 K vs 제출 레이트 분리, GitHub/JIRA rate limit §5c | Stage 3 | 다건 동시 제출 시 |
| 수백 PR 리뷰 병목 §5d | Stage 3 | 단, '자동 게이트가 사람 도달 PR을 거른다'=우리 hook(Stage 2) |
| 상태전이=완료마커, self-healing §6 | Stage 3 | 무인 재시도 루프 전제 |
| 결정적 브랜치/PR 이름, 순서 안전장치 §6 | PoC | 이미 적용 |
| self-healing 재시도 카운터 + 사람 큐 에스컬레이션 §6 | Stage 3 | 무인 운영 필수 |
| overlay 런타임 경합(포트/인스턴스명/DB경로 유니크), DB볼륨=로컬디스크 §7 | Stage 3 | pod 검증 시. 로컬 CTP는 이미 비기본 포트 |
| 무인 관측(실패알림/실행요약/비용 메트릭) §8 | Stage 3 | 1시에 아무도 안 봄 전제 |
| 야간배치 vs 상시드레인 §9 | Stage 3 | 창이 빡빡해질 때 카드 |
| 열린 결정변수 4개 §10 | Stage 3 | parallelism 값 결정용 |

## v2(TC 작성) 문서 항목 분류

| 항목 | 단계 | 비고 |
|---|---|---|
| 정찰(Recon) 먼저 §0 | PoC | 원칙, 전 단계 |
| CTP 실행 계약(empty-answer 9단계, 구조·네이밍, Asia/Seoul, exclusions) §3 | PoC | 이미 스킬에 반영 |
| oracle = 실행 산출물 §4.1 | PoC | 핵심 원칙 |
| **fail→pass 회귀 계약 §4.2** | **PoC (이번 채택)** | fix 이전 빌드에서 실제 FAIL 확인 |
| 결정성 N회 게이트 §4.3 | PoC | 현재 수행 중; N=3 기본으로 형식화 |
| 격리·자기완결 §4.4 | PoC | deallocate/DROP/SET 복원 등 이미 반영 |
| harness(ctp) 계약 준수 §4.5 | PoC | |
| TC 작성 렌즈(입력공간/상태/견고성/E2E) §5 | PoC | 작성 관점 |
| SQLancer 오라클(TLP/NoREC/PQS/DQE/CERT) §5 | Stage 3+ park | 신규 논리버그 탐색용; resolved 이슈 회귀 TC엔 범위 밖(옵티마이저 fix 시 선택적) |
| 리뷰 2층×2트랙, fresh-context 리뷰, 근거 패킷 §6 | PoC | 분리 lane·리포트로 이미 적용 |
| **CCI 교차(run_cci/.answer_cci) §3·§6** | **Stage 2 (이번 채택)** | csql과 다르면 .answer_cci |
| Claude Code 운영: CLAUDE.md/plan/evidence/fresh-review §7 | PoC | |
| 스킬 배치(.claude/skills) §7.5 | Stage 2 | 팀 공유 패키징 |
| **hook 하드 게이트 §7.6** | **Stage 2 (이번 채택)** | fail→pass/결정성 미통과 제출 차단 |

## grilling 확정 (2026-07-09)

| # | 결정 | 값 |
|---|---|---|
| S1 | Stage 2 실행 형태 | 로컬 세션 팀 공유 (k8s Job 아님) |
| S2 | fail→pass 실측 회귀 계약 | PoC부터 |
| S3 | CCI 교차 검증 | Stage 2부터 |
| S4 | Jira 쓰기 | Stage 2까지 읽기 전용 (쓰기=Stage 3) |
| S5 | 하드 게이트 hook 강제 | Stage 2부터 |

기본값(질문 없이 확정, 이견 시 조정): 결정성 반복 **N=3**; SQLancer 오라클 park; 모든 k8s/CronJob/dispatcher/GlusterFS/rate-limit/self-healing/관측/야간배치 = Stage 3 park.

## PoC 마무리 판정 (2026-07)

tc-author PoC를 두 축으로 검증 완료 → Stage 2 진행.
- **결정적 케이스** CBRD-25913 (EXECUTE…USING 서브쿼리 거부): Draft PR #3041.
- **race 케이스** CBRD-26799 (병렬 인덱스 빌드 행유실, 자급 2.1M): Draft PR #3049.
- 파이프라인(Select→Ground→Author→Verify→Review→loop→Submit)이 로컬 end-to-end 동작 확인: 답지 자동생성(empty-answer)·결정성 N=3·경로 커버리지·독립 리뷰·Draft PR까지.
- 두 PoC 교훈을 스킬(create/verify)·에이전트(DESIGN + ADR 0009)에 반영 완료.
- **graduation**: 결정적·race 두 유형을 파이프라인이 처리함을 확인 → Stage 2(팀 수동 트리거) 설계 착수.
- Stage 2로 이월된 열린 항목: fail→pass 실측(26799 race=CI/저사양 몫, 25913 소급), PR 리뷰·머지·머지 후 regression 1~2일 확인.

## PoC 잔여 작업 (S2 채택의 소급 영향)
- **CBRD-25913**: 이미 제출(PR #3041)됐으나 fail→pass 실측은 안 함 → fix 이전 빌드로 소급 확인 필요(결정적이라 명확히 FAIL 예상).
- **CBRD-26799(2호)**: fail→pass를 처음부터 적용. 단 race라 pre-fix FAIL도 확률적 → 반복 실행 best-effort + 한계 명시.
