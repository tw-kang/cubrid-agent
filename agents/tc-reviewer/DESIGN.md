# tc-reviewer — 설계 v1 (cubrid-agent)

cubrid-testcases의 sql TC PR을 심사하는 **평가형 횡단 에이전트**. 사람 리뷰어의 병목(왕복)을 줄이는 첫 리뷰어. 용어·위치는 [CONTEXT.md](./CONTEXT.md), 관점 정본은 [docs/review-perspectives.md](./docs/review-perspectives.md).

## 범위 (PoC)

- **한다**: 지정한 sql TC PR 1건을 3층(L1 컨벤션 / L2 도메인 관점 / L3 실행)으로 심사 → 권고 판정 + 라인 코멘트·종합 리뷰 **초안** 산출(게시는 사람).
- **안 한다**: GitHub 직접 게시(초안까지만), approve/merge, sql 외 카테고리(medium/isolation/shell), PR 자동 감시(webhook), Jira 쓰기.

## 확정 결정 (2026-07-15 인터뷰)

- **D1 대상 = 모든 sql TC PR**: 사람·봇 구분 없음. 병목 해소 목적에 직접 부합하고, 마이닝(사람 PR 리뷰 데이터)의 관점을 그대로 재사용.
- **D2 깊이 = 3층**: 정적+실행 검증에 더해, **마이닝으로 추출한 사람 리뷰어의 경험적 도메인 관점(L2)을 별도 층**으로 둔다. answer 정합성·결정성은 실행(L3)으로만 확실.
- **D3 게시 = PoC 초안, 이후 자동**: resolve-gate와 동일한 단계적 패턴. 오탐이 실제 PR 작성자에게 노출되는 리스크를 PoC에서 차단.
- **D4 판정 = 권고 + 지적 목록**: READY-TO-MERGE / NEEDS-WORK + 심각도별 지적. approve·merge는 항상 사람.
- **D5 PR 성격 2종 × 렌즈 라우팅**: 받는 PR은 ①**변경형**(이슈 동작 변경에 따른 답지/기존 TC 수정) ②**신규형**(새 TC 추가) 두 가지. Ground에서 diff로 판별하고 L2를 성격별 지배 렌즈로 라우팅 — 변경형=**answer-vs-spec 심문 렌즈**(P7·P11), 신규형=**coverage-expansion 확장 렌즈**(P4). L1·P2·P5·P6·봇 분업은 공통 적용. 상세는 아래 'PR 성격 2종과 렌즈 라우팅'.

## 3층 리뷰

**L1 컨벤션 (정적 린트)** — `cubrid-sql-tc-create` 스킬 체크리스트 재사용: 헤더 블록(≤200자, 영문), `evaluate 'Case N'` 넘버링, DROP-before-CREATE, cleanup(만든 것 되돌리기, `deallocate prepare`), 경로·네이밍(`sql/_36_guava/cbrd_XXXXX/{cases,answers}/`), 주석 영문, 기대값이 주석/SQL 판정에 새어 있지 않은가.

**마이닝 승격 자동 린트** — 사람이 *반복*하던 기계적 지적을 규칙화(마이닝 발견): 다행 SELECT의 `ORDER BY` 누락(최다 반복 지적), `set trace on`↔`off` 페어 불균형, 빈 `.queryPlan` 유무 vs answer의 plan 출력, evaluate 라벨 없이 주석만, `prepare` 후 `deallocate` 누락. 상세는 카탈로그의 'L1로 승격할 자동 린트 규칙'.

**L2 도메인 관점 (정적, 마이닝 기반)** — [review-perspectives.md](./docs/review-perspectives.md) 카탈로그를 순회하며 판정. 카탈로그는 사람 리뷰어 600건 분류로 채워졌다(2026-07-15). **봇 분업**: greptile/codex가 이미 badge로 잡는 P1(answer)·P3(fix 경로)는 봇 지적 참조/보강만 하고, L2 역량은 봇이 약한 **P4 케이스 커버리지·P7 답지 정당성·P11 이슈 의도 정합·P8 중복**에 집중(중복 코멘트 억제). **페르소나 렌즈**: 리뷰어별 강점(ssihil=결정성·컨벤션, kwonhoil=답지 사유·케이스, bagus-kim=케이스 SQL, shparkcubrid=플랜, youngjinj=인덱스 경로)을 렌즈로 나눠 재현율을 높일 여지. 신규 관점 **P11(이슈 의도)·P12(버그 판별 유보)·P13(플랜 flaky)** 은 마이닝이 발견(카탈로그 참조).

**L3 실행 검증 (동적)** — PR 브랜치를 `work/cubrid-testcases`에 **worktree**로 체크아웃(작업 clone 불오염) 후 로컬 CTP 실행. tc-author Verify 인프라(`/home/dev/CUBRID` release 빌드, `work/sql.poc.conf`, 비기본 포트) 재사용:
1. **answer 정합성**: PR 상태 그대로 실행 → `Success`면 `.answer`=실제 실행 산출물, `Fail`이면 불일치 diff 확보. (신규 answer 생성이 아니라 검증이므로 빈-answer 트릭 불요.)
2. **결정성**: 연속 3회 실행 매회 Success (tc-author의 N=3과 동일 기준). plan/trace를 출력하는 TC는 **실행계획도 3회 동일**한지 확인 — P13(동률 인덱스 tie로 plan이 흔들리는 flaky) 검출은 반복 실행으로만 가능(마이닝 발견). **L2가 정적으로 비결정을 의심한 케이스(예: ORDER BY 없는 다행, `LIMIT`이 동률 블록을 절단)는 여기서 반복 실행으로 확증**(백테스트 개선점 3: 봇이 정적으로 P2 blocker를 추정 → L3 실측으로 신뢰도↑).
3. **경로 커버리지** (해당 시): plan/trace로 fix 코드 경로를 실제로 타는지 확인 (ADR 0009 게이트 준용).
4. **러닝타임**: CTP elapse 기록 — 과대 TC 지적 근거.

주의: 로컬 빌드에 PR이 전제하는 fix가 없으면 Fail이 가짜 신호다 → 이슈의 Fixed version과 로컬 빌드를 대조하고, 리포트·초안에 검증 빌드를 항상 명시한다.

## PR 성격 2종과 렌즈 라우팅

tc-reviewer가 받는 sql TC PR은 두 성격이고 리뷰 관점이 성격마다 다르다. 마이닝에서 드러난 두 리뷰 철학(coverage-expansion / answer-vs-spec)이 정확히 이 두 성격에 대응한다.

| PR 성격 | diff 신호 | 지배 렌즈 | 핵심 질문 |
|---|---|---|---|
| **① 변경형** — 이슈 동작 변경에 따른 답지/기존 TC 수정 | 기존 `.sql`/`.answer` **modified** | **answer-vs-spec 심문**(P7·P11) | answer가 왜 바뀌었나? 이전이 틀렸었나? 이슈가 규정한 변경과 일치하나? 회귀를 은폐하는 변경 아닌가? |
| **② 신규형** — 새 TC 추가 | 신규 `cbrd_XXXXX.sql`/`.answer` **added** | **coverage-expansion 확장**(P4) | 시나리오가 충분히 넓은가? positive마다 negative가 있나? 경계값(직전/경계/직후)은? 조합·이슈 영향범위 밖 케이스는? |

- **판별**: Ground에서 PR diff의 파일 상태(added vs modified)로 성격을 기계적으로 분류. 한 PR이 둘을 섞으면(신규 추가 + 기존 답지 수정) 두 렌즈를 모두 적용.
- **라우팅**: L2가 성격에 맞는 지배 렌즈를 돌리되, **공통층**(L1 컨벤션, P2 결정성, P5 격리, P6 trace/evaluate, 봇 분업)은 성격 무관하게 항상 적용.
- **비대칭(중요)**: ①변경형의 "왜 바뀌었나"는 **작성자가 스스로 못 던지는 질문**(자기 answer는 정당하다 여김)이라 fresh-context 리뷰어(L2) 전용. ②신규형의 "더 넓게"는 작성자가 미리 할 수 있어 **create 스킬에서 예방**(P4 매트릭스, skills 74f1ba3)하고 리뷰어가 보강. 즉 예방은 author, 심문은 reviewer.

렌즈의 질문셋·few-shot은 [review-perspectives.md](./docs/review-perspectives.md)의 'L2 페르소나 렌즈'에 둔다(5년 마이닝 수집 후 보강 예정).

## 파이프라인

```
Select ─► Ground ─► L1 ─► L2 ─► L3 ─► Verdict ─► 리뷰 초안 + 리포트
```

1. **Select** — 인자로 PR 번호 지정(기본: 열린 sql TC PR 중 최고령 1건). tc-author 봇 PR·사람 PR 무관.
2. **Ground** — PR diff·본문, 제목의 `[CBRD-XXXXX]` 키로 이슈 본문(cubrid-jira jql json), cubrid repo에서 fix merge diff, corpus에서 유사·중복 TC 검색. **PR diff 파일 상태(added/modified)로 PR 성격(변경형/신규형)을 판별해 L2 렌즈 라우팅에 넘긴다**(D5). **fix merge diff로 어느 케이스가 fix 코드 경로를 타는지 표식**(P3)해 L2·L3에 넘긴다(백테스트 개선점 4: 봇의 fix 경로 분석이 강점이었음 — Ground에서 fix diff를 더 적극 활용).
3. **L1→L2→L3** — 위 3층. L3는 변경된 케이스 파일 각각에 수행.
4. **Verdict** — 지적을 심각도로 묶어 판정:
   - **blocker**: 실행 실패, answer 불일치, 비결정(3회 중 상이), 기대값이 이슈/스펙과 모순 → NEEDS-WORK
   - **major**: fix 경로 미커버, 격리 위반(공유 DB 오염·cleanup 누락), 기존 TC와 실질 중복 → NEEDS-WORK
   - **minor**: 컨벤션·스타일·러닝타임 권고 → READY-TO-MERGE 가능(지적 포함)
5. **리뷰 초안** — GitHub 리뷰 형식: 라인 코멘트(파일:라인 + 지적 + 근거)+ 종합 코멘트(판정, 검증 빌드, 실행 증거 요약). **게시 볼륨: blocker/major 우선, minor는 묶어 '참고'로**(백테스트 개선점 2: 봇이 minor를 남발해 소음 → 우선순위 필터). **PoC에선 사람이 검토 후 게시.**
6. **리포트** — `reports/PR-NNNN.md`(gitignore): 층별 결과, 실행 로그 요약, 판정 근거.

## 근거 — 1년 실측 (2025-07-15~2026-07-15, CUBRID/cubrid-testcases)

| 항목 | 값 | 설계 반영 |
|---|---|---|
| 머지 PR | 381건 (사람 작성 대다수 + sync 봇 38) | 물량 = 주 ~7건, tc-author 가세 시 증가 |
| 머지 소요 | 중앙값 3.8일, p75 11일, p90 25.8일, 30일 초과 31건 | 병목은 첫 리뷰(중앙값 0.3일)가 아니라 **왕복** — 봇이 왕복 소재를 선제 제거 |
| 사람 라인 코멘트 | 600건 / 87 PR (전체의 23%) | L2 관점의 원천(마이닝 대상) |
| 리뷰 제출 | approve 904 / commented 523 / **changes-requested 1** | 반려는 공식 상태가 아닌 코멘트로 이뤄지는 문화 → 봇도 코멘트 기반 권고가 부합 |
| 리뷰 본문 | 1,428건 중 비어있지 않은 것 17건 | 리뷰 내용은 전부 라인 코멘트에 → 초안도 라인 코멘트 중심 |
| greptile 봇 | 라인 코멘트 149건(1년) | 범용 지적은 이미 존재 → L2·L3가 차별화 |

## 리뷰 마이닝 (완료 2026-07-15)

사람 리뷰어 600건을 분류해 [review-perspectives.md](./docs/review-perspectives.md)에 반영: 관점별 처리 층(L1/L2/L3)·봇 중복·담당 렌즈·few-shot 앵커. 신규 관점 P11(이슈 의도)·P12(버그 판별 유보)·P13(플랜 flaky) 발견.

**핵심 산출 3가지**(카탈로그가 아니라 이것이 실제 가치):
1. **봇 분업 경계** — greptile/codex가 P1/P3을 badge로 커버 → L2는 봇 약한 P4/P7/P11에 집중, 중복 억제.
2. **L1 자동 린트 승격** — 사람이 반복하던 기계적 지적(ORDER BY 누락·trace 페어·cleanup·evaluate 라벨)을 정적 규칙으로. 리뷰어 반복 노동 제거.
3. **tc-author 선제 개선 피드백** — 최다 지적(P2 ORDER BY·P6 evaluate/trace·P5 cleanup·P4 케이스)을 create 단계에서 방지 → 왕복 근본 축소. `cubrid-sql-tc-create` 스킬 반영 대상.

**원본**: `work/tc-review-mining/`(gitignore) — 머지 PR 381건, 사람 라인 600건(`chunk_0..4.jsonl`), greptile 118건(대조), 대화 149건, 리뷰 제출 1,428건. **백테스트**: 같은 데이터가 재현율/오탐 정답지 — PoC 검증 시 머지 PR 2~3건에 tc-reviewer를 돌려 사람 지적과 대조.

## 백테스트 검증 (2026-07-16, 표본 7건)

머지 PR의 리뷰-전 diff를 fresh-context 서브에이전트가 렌즈로 심사(정답지 blind)해 당시 사람 지적과 대조. 1차 2건(PR2433 신규형·PR2462 변경형) + 2차 확대 5건(미검증 신규 관점 P12/P15/P7: PR2988·2369·1688·2010·2464). 상세 [reports/backtest-poc.md](./reports/backtest-poc.md).
- **재현율**: PR 성격 라우팅(변경형→answer-vs-spec / 신규형→coverage-expansion) **7/7 정확**. 사람 핵심 지적 재현, 오탐 실질 0.
- **신규 관점 실전 재현**: P15(1688 완전·2010 부분), P12(2369 완전, 2988은 스냅샷 한계로 미탐), P7(2462·2464 완전) 모두 실제 사람 지적으로 확인.
- **봇>사람**: 7/7에서 봇이 사람 미지적 valid 지적 추가. 백미 = 2464 **ok→nok 죽은 단언**(answer만 뒤집고 .sql 비교 리터럴 방치 → 검증 무의미화), 1688 물리값 근거 깊이, 2369 본문 vs 실제 diff 불일치, 2433 `LIMIT` 동률 절단 blocker.
- **반영된 개선점 7**: (1차) ① coverage 구체 SQL 제안, ② 게시 볼륨 우선순위, ③ 정적 비결정→L3 확증, ④ Ground fix-diff 표식 / (2차) ⑤ 리뷰-전 스냅샷 확장(첫 커밋→첫 리뷰 직전), ⑥ 변경형 **답지 死단언 감지**(.answer 변경 시 .sql 단언·리터럴도 새 정답 기준으로), ⑦ **.answer_cci 짝 갱신 확인**.
- **방법론 한계**: 리뷰-전=첫 커밋이라 후속 추가 케이스·answer 미가시(2988 P12 exponential 미탐, 2010 오탐 1). 실운영은 PR open 시점을 보므로 백테스트 특유 한계.

## tc-author와의 관계

- tc-author **Submit의 다음 단계**가 tc-reviewer 심사다(봇 PR도 예외 없음 — 내부 self-review와 별개의 fresh-context 심사).
- **관점 카탈로그 공유**: L2 카탈로그는 tc-author Review lane의 체크리스트로도 쓰인다. 마이닝으로 카탈로그가 좋아지면 작성 품질도 같이 올라간다.

## 열린 질문

- **리뷰 코멘트 언어** → **한국어 확정**(마이닝: 사람 코멘트 90%+ 한국어).
- **greptile 중복 처리** → **참조/보강 확정**(봇이 잡는 P1/P3은 재지적 억제, L2는 봇 약한 관점 집중; 겹치면 봇 코멘트 링크만).
- **재리뷰 트리거**: PR 업데이트(push) 시 증분 리뷰 — PoC는 수동 재실행.
- **검증 빌드 선정**: PR이 전제하는 엔진(fix 포함 develop)과 로컬 빌드의 정합 — PoC는 수동 확인+명시, 이후 빌드서버 최신 develop 자동 추적.

## 구현 (Stage 2 리뷰 스킬)

오케스트레이션을 [`.claude/skills/tc-reviewer/`](../../.claude/skills/tc-reviewer/)로 스킬화(팀 git 공유, Stage 2).
- **SKILL.md**: Select→Ground(PR 성격 판별·fix diff 표식)→L1(컨벤션 린트)→L2(렌즈 4종 **DP1 병렬**, few-shot bank 주입, **DP2 블랙박스**, 봇 분업)→L3(worktree 로컬 CTP, 3회 결정성)→Verdict(blocker/major/minor)→리뷰 초안(볼륨 우선순위)+리포트.
- **few-shot bank**([docs/few-shot-bank.md](./docs/few-shot-bank.md), 44 엔트리)가 L2 재료. 백테스트 7건으로 렌즈 재현 검증됨.
- 게시 PoC=초안(사람 게시), 이후 자동(단계적). approve·merge는 항상 사람.
- **남은 것**: 실 PR 라이브 리뷰 스모크, 자동 게시·트리거(Stage 3).

## PoC 이후로 미룬 것

자동 게시(단계적 승격), PR opened/updated 자동 트리거(webhook/CI), sql 외 카테고리, 자동 approve(정족수 기여 — Stage 3 성격), 마이닝 주기 갱신(카탈로그 재추출).
