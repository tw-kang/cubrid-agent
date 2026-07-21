# tc-reviewer — 설계 (cubrid-agent)

cubrid-testcases의 sql TC PR을 심사하는 **평가형 횡단 에이전트**. 사람 리뷰어의 병목(왕복)을 줄이는 첫 리뷰어. 용어·위치는 [CONTEXT.md](./CONTEXT.md), 구현체는 [`.claude/skills/tc-reviewer/`](../../../.claude/skills/tc-reviewer/) — 관점 정본·few-shot bank는 스킬 `references/`에 내장(자기완결, deployment.md D8).

## 범위

- **한다**: 지정한 sql TC PR 1건을 3층(L1 컨벤션 / L2 도메인 관점 / L3 실행)으로 심사 → 권고 판정 + 라인 코멘트·종합 리뷰 **초안** 산출(게시는 사람).
- **안 한다**: GitHub 직접 게시(초안까지만), approve/merge, sql 외 카테고리(medium/isolation/shell), PR 자동 감시(webhook), Jira 쓰기.

## 확정 결정

- **D1 대상 = 모든 sql TC PR**: 사람·봇 구분 없음. 병목 해소 목적에 직접 부합하고, 마이닝(사람 PR 리뷰 데이터)의 관점을 그대로 재사용.
- **D2 깊이 = 3층**: 정적+실행 검증에 더해, **마이닝으로 추출한 사람 리뷰어의 경험적 도메인 관점(L2)을 별도 층**으로 둔다. answer 정합성·결정성은 실행(L3)으로만 확실.
- **D3 게시 = 초안, 이후 자동(단계적)**: 오탐이 실제 PR 작성자에게 노출되는 리스크 차단.
- **D4 판정 = 권고 + 지적 목록**: READY-TO-MERGE / NEEDS-WORK + 심각도별 지적. approve·merge는 항상 사람.
- **D5 PR 성격 2종 × 렌즈 라우팅**: ①**변경형**(답지/기존 TC 수정) ②**신규형**(새 TC 추가). Ground에서 diff로 판별하고 L2를 성격별 지배 렌즈로 라우팅 — 변경형=**answer-vs-spec**(P7·P11), 신규형=**coverage-expansion**(P4). L1·P2·P5·P6·봇 분업은 공통 적용.

## 3층 리뷰

**L1 컨벤션 (정적 린트)** — `cubrid-sql-tc-create` 스킬 체크리스트 재사용: 헤더 블록(≤200자, 영문), `evaluate 'Case N'` 넘버링, DROP-before-CREATE, cleanup(만든 것 되돌리기, `deallocate prepare`), 경로·네이밍(`sql/_36_guava/cbrd_XXXXX/{cases,answers}/`), 주석 영문, 기대값이 주석/SQL 판정에 새어 있지 않은가. **마이닝 승격 자동 린트**: 다행 SELECT의 `ORDER BY` 누락(최다 반복 지적), `set trace on`↔`off` 페어 불균형, 빈 `.queryPlan` 유무 vs answer의 plan 출력, evaluate 라벨 없이 주석만, `prepare` 후 `deallocate` 누락, `.sql`↔`.answer` evaluate 라벨 짝 일치.

**L2 도메인 관점 (정적, 마이닝 기반)** — 관점 카탈로그(스킬 references/)를 렌즈 단위로 판정. **봇 분업**: greptile/codex가 badge로 잡는 P1(answer)·P3(fix 경로)는 참조/보강만 하고, L2 역량은 봇이 약한 **P4 케이스 커버리지·P7 답지 정당성·P11 이슈 의도 정합·P8 중복**에 집중(중복 코멘트 억제). 신규 관점 P11(이슈 의도)·P12(버그 판별 유보)·P13(플랜 flaky)·P14(최소성)·P15(불변식만 단언)는 마이닝이 발견.

**L3 실행 검증 (동적)** — PR 브랜치를 `$TC`에 **worktree**로 체크아웃(작업 clone 불오염) 후 로컬 CTP 실행. 검증 인프라는 $HOME 표준(신뢰 빌드 `$HOME/CUBRID`, 원본 `sql.conf`, 비기본 포트 — deployment.md D7):
1. **answer 정합성**: PR 상태 그대로 실행 → `Success`면 `.answer`=실제 실행 산출물, `Fail`이면 불일치 diff 확보. CTP는 evaluate 라벨을 echo·비교하므로 `.sql` 라벨 수정이 `.answer`에 반영 안 되면 데이터 무관 Fail이 난다.
2. **결정성**: 연속 3회 실행 매회 Success(N=3). plan/trace TC는 **실행계획도 3회 동일**한지 확인 — P13(동률 tie로 plan이 흔들리는 flaky)은 반복 실행으로만 검출. **L2가 정적으로 비결정을 의심한 케이스(ORDER BY 없는 다행, `LIMIT` 동률 절단, 동치 정렬키)는 여기서 반복 실행으로 확증** — 단 로컬 3회 안정 ≠ 스펙 보장, tie는 여전히 지적.
3. **경로 커버리지** (해당 시): plan/trace로 fix 코드 경로를 실제로 타는지 확인 (ADR 0009 게이트 준용).
4. **러닝타임**: CTP elapse 기록 — 과대 TC 지적 근거.

주의: **검증 빌드가 PR이 전제하는 fix를 포함하는지 확인**(`cubrid_rel` SHA → `git merge-base --is-ancestor`) — fix 미포함 빌드의 Fail은 가짜 신호. 리포트·초안에 검증 빌드를 항상 명시한다.

## PR 성격 2종과 렌즈 라우팅

| PR 성격 | diff 신호 | 지배 렌즈 | 핵심 질문 |
|---|---|---|---|
| **① 변경형** — 답지/기존 TC 수정 | 기존 `.sql`/`.answer` **modified** | **answer-vs-spec 심문**(P7·P11) | answer가 왜 바뀌었나? 이전이 틀렸었나? 이슈가 규정한 변경과 일치하나? 회귀를 은폐하는 변경 아닌가? `.sql` 단언·`.answer_cci` 짝도 갱신됐나? |
| **② 신규형** — 새 TC 추가 | 신규 `cbrd_XXXXX.sql`/`.answer` **added** | **coverage-expansion 확장**(P4) | 시나리오가 충분히 넓은가? positive마다 negative가 있나? 경계값은? 조합·이슈 영향범위 밖 케이스는? (부족 지적은 실행 가능한 `evaluate`+SQL 제안으로) |

- **판별**: Ground에서 PR diff의 파일 상태(added vs modified)로 기계 분류. 한 PR이 둘을 섞으면 두 렌즈 모두 적용. **`.sql`↔`.answer` 짝 일치 점검은 성격 무관 공통**(신규형에서도 저자가 후속 커밋으로 한쪽만 고칠 수 있다).
- **비대칭**: ①변경형의 "왜 바뀌었나"는 **작성자가 스스로 못 던지는 질문**이라 fresh-context 리뷰어(L2) 전용. ②신규형의 "더 넓게"는 작성자가 미리 할 수 있어 **create 스킬에서 예방**하고 리뷰어가 보강. 즉 예방은 author, 심문은 reviewer.

## 파이프라인

```
Select ─► Ground ─► L1 ─► L2 ─► L3 ─► Verdict ─► 리뷰 초안 + 리포트
```

1. **Select** — 인자로 PR 번호 지정(기본: 열린 sql TC PR 중 최고령 1건). 작성자 무관.
2. **Ground** — PR diff·본문, 제목의 `[CBRD-XXXXX]` 키로 이슈 본문(+comment — 재현이 comment에만 있을 수 있음), cubrid repo에서 fix merge diff, corpus에서 유사·중복 TC 검색. **PR 성격 판별 → L2 렌즈 라우팅**(D5). **fix merge diff로 어느 케이스가 fix 코드 경로를 타는지 표식**(P3)해 L2·L3에 넘긴다.
3. **L1→L2→L3** — 위 3층. L2 렌즈는 병렬 서브에이전트(DP1). L3는 변경된 케이스 파일 각각에 수행.
4. **Verdict** — **blocker**(실행 실패·answer 불일치·비결정·기대값이 이슈/스펙과 모순)→NEEDS-WORK / **major**(fix 경로 미커버·격리 위반·실질 중복)→NEEDS-WORK / **minor**(컨벤션·스타일·러닝타임)→READY-TO-MERGE 가능(지적 포함).
5. **리뷰 초안** — 라인 코멘트(파일:라인+지적+근거) + 종합(판정·검증 빌드·실행 증거). **게시 볼륨: blocker/major 우선, minor는 묶어 '참고'로**(minor 남발은 소음). 사람이 검토 후 게시.
6. **리포트** — `~/.cubrid-agent/reports/tc-reviewer/PR-NNNN.md`: 층별 결과, 실행 로그 요약, 판정 근거.

## 근거 — 실측 (CUBRID/cubrid-testcases, 1년 창)

| 항목 | 값 | 설계 반영 |
|---|---|---|
| 머지 PR | 381건 (사람 작성 대다수 + sync 봇 38) | 물량 = 주 ~7건, tc-author 가세 시 증가 |
| 머지 소요 | 중앙값 3.8일, p75 11일, p90 25.8일, 30일 초과 31건 | 병목은 첫 리뷰(중앙값 0.3일)가 아니라 **왕복** — 봇이 왕복 소재를 선제 제거 |
| 사람 라인 코멘트 | 600건 / 87 PR (전체의 23%) | L2 관점의 원천(마이닝 대상) |
| 리뷰 제출 | approve 904 / commented 523 / changes-requested 1 | 반려는 공식 상태가 아닌 코멘트로 이뤄지는 문화 → 봇도 코멘트 기반 권고 |
| greptile 봇 | 라인 코멘트 149건(1년) | 범용 지적은 이미 존재 → L2·L3가 차별화 |

**마이닝 산출 3가지**: ① 봇 분업 경계(P1/P3은 봇 커버 → L2는 봇 약한 관점 집중) ② L1 자동 린트 승격(반복 기계 지적의 규칙화) ③ tc-author 선제 개선 피드백(최다 지적을 create 단계에서 방지 → 왕복 근본 축소). 원본 데이터: `work/tc-review-mining/`(dev 로컬, gitignore) — 백테스트 정답지로도 사용.

**백테스트로 검증됨**(머지 PR의 리뷰-전 diff를 blind 심사해 사람 지적과 대조): 성격 라우팅 정확, 사람 핵심 지적 재현, 오탐 실질 0, 봇이 사람 미지적 valid 지적 추가(死단언·물리값 근거·`LIMIT` 동률 절단 등). 한계: 리뷰-전=첫 커밋 스냅샷이라 후속 커밋 반영 지적은 미가시(실운영은 PR open 시점이라 무관). **라이브 검증됨**(실 PR): L3 로컬 실행이 정적 diff로 안 보이는 blocker(`.sql` 라벨만 고치고 `.answer` 미재생성 → 결정적 Fail)를 확증 — L3의 차별 가치.

## tc-author와의 관계

- tc-author **Submit의 다음 단계**가 tc-reviewer 심사다(봇 PR도 예외 없음 — 내부 self-review와 별개의 fresh-context 심사).
- **관점 카탈로그 공유**: L2 카탈로그(스킬 references/)는 tc-author Review lane의 체크리스트로도 쓰인다. 카탈로그가 좋아지면 작성 품질도 같이 올라간다.

## 열린 질문

- **재리뷰 트리거**: PR 업데이트(push) 시 증분 리뷰 — 현재는 수동 재실행.
- **검증 빌드 선정**: PR이 전제하는 엔진(fix 포함 develop)과 로컬 빌드의 정합 — 현재는 fix-in-build 확인+명시, 이후 빌드서버 최신 develop 자동 추적.

## 미룬 것 (backlog)

자동 게시(단계적 승격), PR opened/updated 자동 트리거(webhook/CI), sql 외 카테고리, 자동 approve(정족수 기여 — Stage 3 성격), 마이닝 주기 갱신(카탈로그 재추출).
