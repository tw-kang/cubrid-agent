# test-runner (Test → Tested)

**상태: 설계 v1 — 스킬 미구현.**

역할: 머지된 TC가 **머지 후 야간 회귀에서 안정적으로 도는가**를 판정해 이슈를 Tested로 넘길지 권고하는 **판독형 게이트** 에이전트. author-testcase(생성형)와 달리 TC를 만들지 않고, gate-resolved(판정형)처럼 **판정(권고)** 을 낸다. 회귀 자체는 이미 있는 인프라(엔진 CircleCI·사내 야간 스케줄러)가 돌리므로, test-runner는 **그 결과를 읽어 판정**한다.

## 초점 — 머지 후 회귀 안정성 (신규 TC 자체)

"내가 낸 신규 TC가 develop 머지 후 야간 회귀에 편입되어 **연속 2일 안정 PASS** 하는가"만 본다. 스위트 전체가 깨졌는지(다른 TC 영향, 회귀 무결)는 **보지 않는다** — 그건 close-backport의 몫(D5). Verify의 본질을 "새 TC가 회귀에서 사는가"로 좁힌 것.

## 용어

- **Verify**: Test→Tested 공식 전이. 되돌림은 Stop Test(→Resolved). dev-process v2.4.
- **qahome / qaresu**: qahome.cubrid.org = QA 리포트 홈(웹은 파싱 막힘). 그 백엔드 = **CUBRID DB `qaresu`**(`192.168.1.86:33080`) — test-runner의 판정 진실 원천, JDBC/CCI로 직접 쿼리(ADR 0010).
- **resultstat**: qaresu의 회귀 **run summary** 테이블. testcat(sql/medium/…)·testtype(release/debug)·treepath(엔진 build_id)·total_scenario·success_scenario·**fail_scenario(개수)**·stat_date·qaresultpath. sql은 개별 TC 이름이 없고 개수만 → 개별은 qaresultpath 결과 파일에.
- **baseline 델타 판정**: sql 회귀는 **상시 baseline 실패**(~1건)를 가져 `fail=0`이 성립 안 함(dry-run 실측). 그래서 "내 TC 편입 run의 fail_scenario가 편입 직전 baseline과 같은가(= 신규 실패 0)"로 판정한다. 델타>0일 때만 qaresultpath로 개별 확인(ADR 0010).
- **편입(시간 기준)**: 내 TC가 회귀 run에 들었는지를 "TC PR develop 머지 시각 이후 stat_date의 sql run"으로 판정. resultstat이 testcases 버전을 기록하지 않아 시간이 유일 견고 키(D9).
- **관측 창**: 연속 2일(= 야간 1일 1회 × 2 run) 안정 PASS = 승격 조건(D6).
- **VERIFIED / NOT-VERIFIED**: 판정 권고. 2 run 델타 0 = VERIFIED(Tested 권고), 델타>0 or FAIL = NOT-VERIFIED(사람 확인 에스컬레이션). Jira 전이는 사람.
- **진단**: FAIL 원인(TC 문제 vs fix 미해결) 규명. **PoC 보류**, Stage 2=builder/tester, Stage 3=glusterfs 빌드 bisect로 실패 유발 커밋 탐색(D1, 방법은 Stage 3 인터뷰).

## 위치

author-testcase Submit·머지 뒤의 회귀 구간에 선다:

```
author-testcase ─Draft PR─► [review-testcase·사람 리뷰 ─► 머지] ─► [test-runner: Verify] ─► Tested ─► close-backport
```

CircleCI는 **머지 전** 검증(PR 게이트, test-runner 범위 밖), qahome은 **머지 후** regression 탐지 — test-runner는 후자만 읽는다(D3). 조인 키는 이슈 키(`CBRD-XXXXX`)와 TC 파일명(`cbrd_xxxxx`). 파이프라인 맥락은 [../../../CONTEXT-MAP.md](../../../CONTEXT-MAP.md), 롤아웃은 [../../staging.md](../../staging.md).
