# ADR 0009 — PoC 2호(CBRD-26799)에서 얻은 파이프라인 보강

- 상태: 채택 (2026-07)
- 범위: author-testcase. 스킬 `cubrid-sql-tc-create`/`cubrid-sql-tc-verify`에 동시 반영.
- 관련: [0004](0004-probabilistic-repro-accepted.md)(확률적 repro), [0006](0006-local-verification-for-poc.md)(로컬 검증), [../../../adr/0007-rollout-stages.md](../../../../adr/0007-rollout-stages.md)(fail→pass).

## 배경

PoC 2호(병렬 인덱스 빌드 row loss, race)에서 파이프라인의 빈틈이 드러났다. 결정적 PoC 1호에선 안 보이던 문제들이다:
- 초기에 버그 트리거를 오인(`WITH ONLINE PARALLEL`=online loader_task 경로 ≠ 버그)해 수백 회 헛빌드.
- 이슈 원본 repro(700K)가 이미 corpus에 다른 이름(`_03_iss_700000`/`_08_..._with_null`)으로 존재하는 걸 늦게(리뷰 중) 발견.
- 700K는 기본 config에서 **serial**이라 fix 경로(병렬 정렬)를 안 타는데도 결정적으로 PASS — "조용히 통과하는 무의미 TC" 위험.
- race가 이 머신에서 미재현. 2코어 taskset 재현 시도는 병렬을 꺼버려 무효.
- 주석·커밋 언어, 기대값 위치(주석/SQL 판정 vs `.answer`)에서 시행착오.

## 결정

1. **커버리지 검색은 "번호"가 아니라 "동작" 기준** (Select/Ground). `tc/cbrd-XXXXX`·`cbrd_xxxxx` 존재 확인만으론 부족하다. 이슈의 repro(테이블/쿼리 패턴, 기능 영역)로 corpus를 grep한다. 이미 다른 이름으로 존재하면 **중복 대신 차별화**(다른 변형, 또는 표준 suite에서 경로를 타는 자급형).

2. **경로 커버리지 게이트** (Verify). 결정적 PASS는 필요조건일 뿐. TC가 **fix 코드 경로를 실제로 타는지** plan/trace로 확인한다. 데이터 크기로 경로를 유도한다 — 예: offline 병렬 인덱스 빌드(`btree_sort_get_next_parallel`)는 평범한 `CREATE INDEX`가 `parallelism`≥2(기본4) **및** heap 페이지 ≥ `parallel_sort_page_threshold`(기본2048)일 때만 진입(`WITH ONLINE PARALLEL`은 딴 경로). config가 경로를 바꿀 수 있음(`test_mode=yes`→threshold 0). 700K는 serial, ~2.1M은 병렬.

3. **fail→pass race 방법론 보강** ([0007] 보강). pre-fix 빌드는 빌드서버(`192.168.1.91:8080`)에서 **fix 직전 커밋(feature 도입 이후)** 산출물로 확보. race는 빠른 다중코어 환경에서 미재현될 수 있어 반복+한계 명시(best-effort). **함정**: `taskset`으로 ≤2코어에 묶으면 `system_core_count`(affinity-aware)가 2가 되어 병렬 자체가 disable된다 → few-core 재현은 **≥4코어**.

4. **작성 규약 확정**. `.sql` 주석·커밋 메시지는 **영문**(PR 본문만 한글, 사용자 관점). 기대값은 **`.answer`에만** 둔다 — 주석에도, SQL 판정(`CASE 'OK'/'NOK'`)으로도 두지 않는다(CTP는 raw 결과 vs `.answer` diff로 판정). 시나리오 라벨은 `evaluate 'Case N: ...'` 디렉티브(answer에 echo).

## 결과

- 스킬 반영: create(중복검색·경로트리거·판정위치·언어 + 체크리스트), verify(경로 커버리지·config 영향·fail→pass 함정 섹션).
- DESIGN 파이프라인의 Ground(커버리지)·Verify(경로 게이트·affinity)·Author(경로 유도·언어)에 포인터.
- 남은 한계: race의 로컬 fail→pass 실측은 여전히 환경 의존(Stage 2+/CI 몫).
