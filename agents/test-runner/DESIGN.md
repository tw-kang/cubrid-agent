# test-runner — 설계 v1 (cubrid-agent)

Test→Tested("Verify") 전이를 맡는 **판독형 게이트**. 머지된 신규 TC가 야간 회귀에서 연속 2일 안정 PASS 하는지를 qaresu DB로 판정해 Tested 승격을 권고한다. 용어·초점·위치는 [CONTEXT.md](./CONTEXT.md), 판정 원천·방식 근거는 [docs/adr/0010-verdict-source-and-baseline-delta.md](./docs/adr/0010-verdict-source-and-baseline-delta.md).

## 범위 (PoC)

- **한다**: status=Test 이면서 TC PR이 머지된 이슈를 골라, 머지 후 sql 회귀 결과(qaresu)를 읽어 baseline 델타로 "연속 2일 안정 PASS"를 판정 → 읽기전용 리포트 + Jira 코멘트 초안.
- **안 한다**: 회귀 직접 실행(인프라가 함), Jira 전이·코멘트 게시(사람이), 실패 원인 진단(보류), 스위트 회귀 무결 확인(close-backport 몫), sql 외 카테고리.

## 확정 결정 (2026-07-15 grilling)

| # | 결정 | 값 |
|---|---|---|
| D1 | 정체 | 판독형 + 실패시 진단. 진단은 PoC 보류 / Stage2 builder·tester / Stage3 glusterfs 빌드 bisect(방법은 Stage3 인터뷰). 진단 결과는 qahome 기록 |
| D2 | PoC 시연 | tc-author PoC PR(#3041/#3049) **머지·회귀 편입 후** 실제 판정. 설계는 지금 완결, 실행 시연만 머지 후 |
| D3 | 진실 원천 | **qahome**(머지 후 regression). CircleCI=머지 전 검증이라 범위 밖 |
| D4 | qahome 읽기 | **qaresu DB 직접 쿼리**(`192.168.1.86:33080`, JDBC/CCI). 웹 스크래핑 아님 (ADR 0010) |
| D5 | 판정 대상 | **신규 TC 안정 PASS만**. 스위트 회귀 무결(다른 TC 영향)은 close-backport로 이관 |
| D6 | 관측 창 | 연속 **2일(2 run)** PASS. 회귀=야간 1일 1회(cubrid_build 실측) |
| D7 | 개별 확정 | resultstat **baseline 델타**: fail_scenario ≤ 편입직전 baseline(신규 실패 0)이면 PASS. 델타>0일 때만 qaresultpath 개별 확인 (dry-run으로 D7 최초안 "fail=0" 반증 후 개정, ADR 0010). qaresultpath 접근 방법은 추후 설계 |
| D8 | Select | JQL(`status=Test ∧ cf[213834]=twkang ∧ cf[210441]=guava`) ∩ **TC PR develop 머지됨** |
| D9 | 편입 판정 | **시간 기준**: TC PR 머지 시각 이후 stat_date의 sql run이 내 TC 포함. 머지 직전 run = baseline |
| D10 | 출력 | 읽기전용 리포트 + Tested 권고·근거를 **Jira 코멘트 초안**(PoC=사람 게시, 이후 자동). 전이는 사람 |
| D11 | FAIL 분기 | NOT-VERIFIED 리포트 + 코멘트 초안(사람 확인). Tested 권고 안 함. 원인 구분은 진단 보류라 안 함 |

## 파이프라인

```
Select ─► Resolve(빌드·baseline) ─► 관측(2 run) ─► Verdict ─► 리포트 + Jira 코멘트 초안
```

1. **Select** — JQL로 `status=Test ∧ QA Assignee=twkang ∧ Planned=guava` 이슈를 뽑고, 각 이슈의 TC PR이 `CUBRID/cubrid-testcases:develop`에 **머지됐는지 gh로 확인**. 미머지는 회귀에 없으니 대기열 보류(D8).
2. **Resolve(빌드·baseline)** — 이슈의 TC PR 머지 시각(`merged_at`)을 기준점으로 잡고, qaresu `resultstat`에서:
   - **baseline run** = 머지 직전 sql release run(`testcat='sql'`, `stat_date < merged_at` 최신)의 `fail_scenario`.
   - **관측 대상 run** = `stat_date > merged_at`인 sql release run들(야간이라 머지 다음날부터, `treepath` build_id로 어느 야간 빌드인지 식별).
3. **관측(2 run)** — 관측 대상 sql run이 2개 쌓일 때까지: 각 run의 `fail_scenario`가 baseline 이하(**신규 실패 0**)이고 `total_scenario`가 편입을 반영(증가)하면 그 run은 PASS. 아직 2 run이 안 쌓였으면 "대기"(다음 야간까지).
4. **Verdict** —
   - **VERIFIED**: 연속 2 run 모두 델타 0 → Tested 승격 권고.
   - **델타>0(신규 실패 의심)**: 그 run의 `qaresultpath` 결과 파일에서 내 TC(`cbrd_xxxxx`)가 실패 목록에 있는지 개별 확인 → 내 TC면 NOT-VERIFIED, 무관하면 baseline 갱신 후 계속. **PoC는 qaresultpath 접근이 추후 설계라 이 경우 사람 에스컬레이션**.
   - **FAIL/불안정**: NOT-VERIFIED(D11).
5. **리포트 + 코멘트 초안** — `reports/CBRD-XXXXX.md`(gitignore): 판정, 근거(baseline·관측 2 run의 build_id·stat_date·fail_scenario·total_scenario), Tested 권고 여부. Jira 코멘트 초안(회귀 2일 PASS 증거 + 권고). **PoC는 사람이 게시**, 이후 자동(D10).

## 재료

- **cubrid-jira**: 이슈 상태·QA Assignee·Planned·description(단일진실원천). JQL로 Select.
- **gh**: TC PR의 develop 머지 여부·`merged_at`.
- **qaresu DB**(`192.168.1.86:33080`, dba, JDBC): `resultstat`(회귀 run summary), `cubrid_build`(야간 빌드 이력, treepath 조인). 판정 진실 원천 (ADR 0010).
- **(추후)** qaresultpath 결과 파일: 델타>0 시 개별 TC 확인. 접근 방법 미설계.
- 로컬 CTP·CUBRID **불요**(회귀를 직접 안 돌림).

## dry-run 근거 (2026-07-15, qaresu 실측)

최근 sql/medium release 회귀(baseline 델타 판정의 실측):

| testcat | 관측 | 판정 함의 |
|---|---|---|
| `sql` | 매일 `fail_scenario=1` (7-14/7-13/7-10), total 17437→38→39 | **상시 baseline 1 존재 → "fail=0" 무효**. baseline 델타로 판정해야(D7 개정 근거) |
| `medium` | 매일 `fail_scenario=0` | 그린 카테고리 — 델타=절대값 |
| `sql_by_cci` | 매일 `fail_scenario=15~17` | baseline이 큰 카테고리 — 델타 필수 |
| `cubrid_build` | got_time 매일 22~23시 | 야간 1일 1회 확정(D6 근거) |
| `is_verified` | 최근 sql 46건 전부 0 | 미사용 필드 — PoC 참고만 |

→ 판정 SQL이 실제 데이터로 도는 것을 확인. sql의 상시 baseline이 "fail=0이면 PASS"를 반증해 D7을 baseline 델타로 개정.

## close-backport와의 관계

test-runner는 **신규 TC 자체**(내 TC가 회귀에서 사는가)만 판정하고, **스위트 회귀 무결**(내 머지가 다른 TC를 깼는가)은 close-backport로 넘긴다(D5). 즉 `fail_scenario`의 baseline **증가분 중 내 TC가 아닌 것**(다른 TC 신규 실패)은 test-runner가 무시하지만, close-backport는 그것까지 본다. 조인 키는 이슈 키.

## 열린 질문

- **qaresultpath 접근**: 델타>0 시 개별 결과 파일 경로(`cubrid/RB-.../function/sql/...`) 접근이 파일시스템 마운트인지 웹인지 — 추후 설계(D7).
- **baseline 오염**: 야간 1 run에 여러 TC 머지가 몰리면 baseline 델타가 내 TC 단독이 아님. "신규 실패 0"이면 최소한 내 TC는 무해하나, 델타>0의 귀속은 qaresultpath 확인에 의존.
- **is_verified 의미**: resultstat 검증 플래그의 실제 용도(누가/언제 1로) 미확인 — test-runner가 채울 자리인지 추후 확인.
- **testcat 정합**: PoC 대상 = `testcat='sql' ∧ testtype='release'`(운영 CI mode)로 고정. debug run은 참고만.

## PoC 이후로 미룬 것

실패 원인 진단(Stage2 builder·tester / Stage3 glusterfs 빌드 bisect + qahome 기록), qaresultpath 파싱 인프라, Jira 자동 전이·코멘트 게시(Stage 3), medium/shell 등 카테고리 확대, is_verified 쓰기, 무인 스케줄(야간 회귀 완료 트리거).
