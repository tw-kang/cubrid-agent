# 0010 — test-runner 판정 원천은 qaresu DB, 판정은 baseline 델타

- 상태: 수락 (2026-07-15)
- 맥락: test-runner grilling + qaresu 실측/dry-run
- 관련: [DESIGN.md](../../DESIGN.md) D4/D7, [ADR 0007](../../../../adr/0007-rollout-stages.md)(롤아웃 단계)

## 맥락

test-runner는 Test→Tested를 판정하려면 "머지 후 회귀 결과"를 읽어야 한다. 후보 원천은 두 가지였다: 공식 리포트 홈 **qahome.cubrid.org**(웹)와 실행 엔진 **CircleCI**. 또한 "신규 TC가 PASS했나"를 어떻게 판정할지도 정해야 했다.

grilling 중 두 사실이 드러났다:
1. **CircleCI는 머지 *전* 검증**(PR 게이트), **qahome은 머지 *후* regression 탐지**(사용자 정정). test-runner의 관심사는 후자다.
2. qahome 웹은 curl 파싱이 막혀 있고(root 200 / index 404 / JS·인증), 백엔드가 CUBRID DB **`qaresu`**(`192.168.1.86:33080`)임을 사내 도구(`cubrid_scheduler`, `qahome_utils`)에서 확인 — 그리고 그 DB가 실제로 도달·조회 가능했다.

## 결정

### (a) 판정 진실 원천 = qaresu DB 직접 쿼리 (웹 아님)

test-runner는 qahome 웹을 스크래핑하지 않고 **qaresu DB를 JDBC/CCI로 직접 쿼리**한다. 회귀 run summary는 `resultstat` 테이블(testcat·testtype·treepath·total_scenario·success_scenario·fail_scenario·stat_date·qaresultpath), 야간 빌드 이력은 `cubrid_build`(treepath 조인)에서 읽는다.

- 브로커 포트(33080)라 `csql`(cub_master 1523, 닫힘)이 아닌 **JDBC/CCI 경로** 필수.
- 개별 TC 성패는 sql의 경우 `resultstat`에 없다(개수만) — 필요 시 `qaresultpath` 결과 파일(접근 방법 추후 설계).

### (b) sql 판정 = baseline 델타 (fail=0 아님)

dry-run 실측: **sql testcat은 상시 `fail_scenario=1`**(알려진 baseline 실패)이라 "그린(fail=0)이면 PASS"가 성립하지 않는다. 따라서 판정을 **baseline 델타**로 한다:

> 내 TC 편입 run의 `fail_scenario`가 편입 직전 baseline run과 **같으면(신규 실패 0) 안정 PASS**. 델타>0일 때만 `qaresultpath` 결과 파일에서 내 TC 개별 확인.

편입은 시간 기준(`stat_date > merged_at`), 관측 창은 연속 2일(야간 1일 1회 × 2 run).

## 대안

- **qahome 웹 파싱**: 리포트 홈을 직접 스크래핑. 인증·JS 렌더로 취약하고, DB가 더 구조적. 기각.
- **CircleCI 결과**: 머지 전(PR) 결과라 "머지 후 회귀 안정성"의 증거가 아님. 범위 밖.
- **fail_scenario=0 판정**: sql 상시 baseline 때문에 무효(dry-run 반증).
- **항상 qaresultpath 개별 확인**: 정확하나 파일 접근이 PoC 전제가 되어(접근 미설계) 막힘. 델타>0일 때만으로 축소.

## 결과

- **좋음**: 구조화된 DB 쿼리로 판정이 견고·재현 가능. sql 상시 baseline을 흡수해 PoC에서 파일 접근 없이 1차 판정 가능. dry-run으로 판정 SQL 실증.
- **비용/리스크**: (1) `resultstat` 스키마·값 관례(testcat 명명, treepath 형식)에 의존 — 스키마 변경에 취약. (2) baseline 오염 — 야간 1 run에 여러 TC 머지가 몰리면 델타가 내 TC 단독이 아님(“신규 실패 0”이면 무해 보장은 되나, 델타>0 귀속은 qaresultpath에 의존). (3) qaresultpath 접근이 미설계라 델타>0 케이스는 PoC에서 사람 에스컬레이션.
- qaresu 접근 인증·DB 위치는 운영 비밀 — 리포트/커밋에 자격증명 남기지 않는다.
