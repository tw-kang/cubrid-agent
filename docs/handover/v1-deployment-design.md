# CUBRID TC 자동화 에이전트 서비스 — 설계 핸드오버 (v1)

> 외부 AI 도구로 작성된 설계 논의 정리본. jira-resolve-agent의 재료로 보존. 분류는 [../staging.md](../staging.md) 참조.
> 상태: 설계 논의 정리본 (실행 전). 아래 "열린 결정 변수"가 확정되면 매니페스트 수준으로 구체화 가능.

---

## 1. 목적 및 개요

야간 스케줄 배치로 동작하는 **무인 에이전트 서비스**. 매일 새벽 1시(KST) CUBRID JIRA에 REST API로 쿼리를 보내 `Resolved` 상태 이슈를 가져오고, 각 이슈에 대해: (1) TC 작성 (2) PR 생성 (3) 이슈 상태를 `Resolved` → `Test`로 전이. 외부 노출 없음(클러스터 내부 전용).

**볼륨 전망:** 초기 하루 수십 건 → 개발팀이 에이전틱 개발을 도입하면 수백 건. 이 볼륨 증가가 설계를 두 단계로 가른다.

## 2. 인프라 전제 (이미 확정된 것)
- 빌드는 에이전트가 만들지 않는다. repo에 PR이 머지될 때마다 CI가 빌드 생성. "build stage"는 이미 기존 CI에 존재.
- 빌드 아티팩트는 GlusterFS로 모든 노드에 공유되고, 에이전트 파드는 overlay mount로 붙어 사용.
- overlay(read-only lower + 파드별 upper) 구조라 아티팩트 오염 위험 없음(단 §7 런타임 경합은 별개).
- 결과: 파이프라인은 빌드를 만들지 않고 GlusterFS 경로에서 올바른 아티팩트를 고르기만 하면 됨(사실상 1스테이지 fan-out).

## 3. 핵심 패턴 판정
- 이건 큐가 아니라 **스케줄 배치 팬아웃**. 새벽 1시에 "그날 resolved 집합"이라는 유한·확정 목록을 처리하고 끝. KEDA/competing-consumers 부적합. 프리미티브 = **CronJob**(`timeZone: Asia/Seoul`, `schedule: 0 1 * * *`; timeZone 없으면 UTC라 `0 16 * * *`), `concurrencyPolicy: Forbid`, `activeDeadlineSeconds`/`startingDeadlineSeconds`/history limit.
- **Argo는 지금 안 씀** — 스테이지 하나(fan-out), 이슈 독립(팬인 없음). CronJob + Indexed Job이 정확. Argo로 옮길 시점: per-issue 재시도·상태추적·부분 재실행·조건분기가 아플 때. Indexed Job도 `backoffLimitPerIndex`(1.29+), `maxFailedIndexes`로 꽤 멀리 감.

## 4. 단계별 진화
- **단계 1 — 단일 파드**: CronJob → Job 1개 → 파드가 JIRA 쿼리 → 순차 루프. 하루 수십 건이면 순차로 충분. 병렬화는 순차가 시간 안에 안 끝나는 게 실측될 때.
- **단계 2 — dispatcher 패턴**: CronJob → dispatcher가 JIRA 한 번 쿼리 → 목록 확정 → Indexed Job(`completions=N`,`parallelism=K`)으로 팬아웃. 워커는 재조회 안 함(claim 경쟁 없음). Indexed Job은 실행 시점 `completions`(N)를 알아야 하므로 launcher Job이 N을 정해 apply하는 2-스텝.

## 5. 수백 단위 리팩터링
- (a) 신뢰 빌드를 이슈에서 분리 — 같은 브랜치 resolved 이슈는 같은 신뢰 빌드; 새로 빌드 말고 CI 산출물 재사용. 빌드 스테이지 = "신뢰 아티팩트 fetch".
- (b) 아티팩트 결정적 pin — 커밋 SHA/빌드 ID로 경로 고정.
- (c) 병렬성(K)과 제출 레이트 분리 — 검증은 컴퓨트 바운드로 넓게, PR/전이는 외부 API라 별개. GitHub secondary rate limit, JIRA 전이 한도. `parallelism`=동시 CUBRID 인스턴스+LLM 예산, 외부 제출은 독립 큐.
- (d) 진짜 병목 = 아침의 수백 PR 리뷰. 자동 게이트(hook 하드 게이트)가 사람 도달 PR을 거르는 필터로 load-bearing.

## 6. 멱등성·신뢰성
- 상태전이를 완료 마커로(맨 마지막, PR 성공 후). 중간에 죽으면 `Resolved`로 남아 다음 날 재시도 → 부분 실패 자가 치유.
- 결정적 브랜치/PR 이름(`tc/{issue-key}`), 재시도 시 존재 확인해 중복 방지. TC 경로도 이슈 키로 결정적.
- 순서 = 안전장치: (빌드·검증 →) PR → 상태전이. 커밋 포인트는 상태 전이 하나.
- self-healing에 에스컬레이션 필수: max-attempts 초과 → 사람 큐. 재시도 카운터 + DLQ 상당물.

## 7. GlusterFS/overlay/런타임 경합
- overlay는 파일 레이어 오염만 막고 런타임 자원 경합은 못 막음. 한 노드에 CUBRID 여럿이면 포트·공유메모리·서버이름·DB볼륨 충돌 → 파드마다 포트/인스턴스명/데이터경로 유니크. 진짜 병렬 천장은 여기(노드당 동시 인스턴스 수).
- GlusterFS는 아티팩트 read/공유엔 좋지만 DB 데이터 볼륨으론 피함(fsync·small write 지연). 검증용 DB 볼륨은 로컬 디스크(emptyDir/local PV), Gluster는 읽기 전용 아티팩트 공유만.

## 8. 무인 운영 관측
- CronJob은 실패해도 기본 알림 없음. Job 실패 알림(kube-state-metrics), 실행 요약(N/M/실패 이슈 키)을 Slack 등, 작업당 토큰·비용 메트릭.

## 9. 야간 배치 vs 상시 드레인
- 수백 건이면 야간 창이 빡빡. 상시 드레인하면 병렬성·API 레이트 완만(competing-consumers 회귀). 다만 정착된 end-of-day 브랜치를 한 번 빌드하는 게 오라클 신뢰성에 유리 → 야간 유지, 창이 안 맞으면 꺼내볼 카드.

## 10. 열린 결정 변수
1. PR 하드 데드라인 2. 하룻밤 대상 브랜치 수 3. 노드당 동시 CUBRID 인스턴스 상한 → 셋이 `parallelism` 결정. 4. dispatcher의 "이슈 → 아티팩트 경로" 해소 규칙(빌드 ID/커밋 SHA 명명).
