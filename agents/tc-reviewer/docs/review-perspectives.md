# 관점 카탈로그 (review perspectives) — L2 정본

**상태: 5년 마이닝 반영 (사람 라인 코멘트 1,358건 분류, 2021-07~2026-07 머지 PR, 2026-07-16). 1년 600건 → 5년 확장 완료.**

tc-reviewer L2와 tc-author Review lane이 공유하는 단일 정본. 목적은 "관점 목록"이 아니라 **각 관점을 어떻게 처리하는가**의 지정: 어느 층(L1 정적 린트 / L2 LLM 판정 / L3 실행)에서 잡는가, greptile/codex 봇과 중복되는가, 어느 리뷰어 렌즈가 강한가, few-shot 앵커는 무엇인가.

## 처리 층 배정 (마이닝의 핵심 산출)

| id | 관점 | 빈도 | 처리 층 | 봇 중복 | 담당 렌즈 |
|---|---|---|---|---|---|
| P4 | 케이스 커버리지 (시나리오 추가) | 최다 | **L2**(이슈·diff 필독) | 약함 | bagus-kim, kwonhoil |
| P2 | 결정성 — ORDER BY 누락 | 매우높음 | **L1**(정적) + L3(확인) | 부분 | ssihil |
| P7 | 답지 변경 정당성·기대값 정합성 | 매우높음 | **L2**(이슈 대조) | 약함 | kwonhoil, ssihil |
| P6 | 컨벤션 — evaluate/trace/queryPlan/server-message | 높음 | **L1**(정적) | 아니오 | ssihil |
| P11 | TC 의도 ↔ 이슈 정합성 *(신규)* | 높음 | **L2**(이슈본문 필수) | 부분 | 다수 |
| P3 | fix 경로 커버리지 | 중간 | L2 + **L3**(plan/trace) | **강함(봇)** | youngjinj, shparkcubrid |
| P13 | 옵티마이저 플랜 안정화 — tie/flaky *(신규)* | 중간 | **L3**(반복 실행 plan) | 아니오 | shparkcubrid |
| P5 | 격리·자기완결 — DROP/commit/deallocate | 중간 | **L1**(정적) | 부분 | ssihil, bagus-kim |
| P8 | 기존 TC 중복 | 낮음 | **L2**(corpus 검색) | 아니오 | youngjinj |
| P12 | 버그/스펙 판별 유보 *(신규)* | 낮음 | **L2**(사람 에스컬레이션) | 아니오 | 다수 |
| P9 | 러닝타임·성능 | 낮음 | **L3**(elapse) | 아니오 | bagus-kim |
| P1 | answer 무결성 | 낮음(사람) | L3 | **강함(봇)** | — |
| P10 | 언어(주석·커밋 영문) | 낮음 | **L1** | 부분 | — |
| P14 | 최소성 — 불필요 힌트·설정·중복 케이스 제거, 최소 재현 *(신규)* | 중간 | **L2** | 아니오 | youngjinj, ssihil |
| P15 | 불변식만 단언 — 환경/빌드 의존 값(page id·시작값·시간) 회피 *(신규)* | 중간 | **L2**+L3 | 부분 | shparkcubrid, ssihil |

## L1로 승격할 자동 린트 규칙 (마이닝이 짚은 반복 지적)

사람이 *반복*하던 기계적 지적은 LLM 판정이 아니라 정적 규칙으로. 이걸 L1에서 자동 검출하면 리뷰어 반복 노동이 사라진다:

- **P2** 다행 결과를 내는 SELECT에 `ORDER BY` 없음 (ssihil이 최다 반복). 집계/스칼라/에러 케이스는 예외.
- **P6** `set trace on` ↔ `set trace off` 페어 불균형; trace 사용 후 미해제.
- **P6** 빈 `.queryPlan` 파일 유무 vs answer의 plan 출력 존재(짝 안 맞으면 지적).
- **P6** 시나리오 주석만 있고 `evaluate 'Case N: ...'` 라벨 없음.
- **P5** `CREATE TABLE` 앞 `DROP TABLE IF EXISTS` 누락; `prepare` 후 cleanup에 `deallocate prepare` 누락; view/synonym/serial cleanup 누락.
- **P10** `.sql` 주석·커밋 메시지 비영문.

## 봇 분업 경계

greptile/codex 봇은 **P1(answer 무결성)·P2(결정성 일부)·P3(fix 경로 커버리지)**를 P1/P2 심각도 badge로 이미 정교하게 잡는다(예: "NULL 결과값 오염", "샘플링 결과 고정값", "새 문법 미검증"·"DROP 경로 우회"). tc-reviewer는:
- 이 관점들은 **봇 지적을 참조/보강**만(중복 코멘트 억제).
- L2 역량을 **봇이 약한 P4·P7·P11·P13·P6·P8**에 집중.

## 신규 관점 정의 (시드에 없던 것 — 마이닝 발견)

**P11 — TC 의도 ↔ 이슈 정합성**: TC가 이슈가 말하는 버그를 실제로 겨냥하나. P3(fix 코드 경로)와 달리 *이슈 시나리오 의도* 차원. 이슈 본문을 읽어야만 판정 가능(L2 전제 = Ground).
> "Not sure if you've grasped the JIRA issue fully.. This test case has little to do with the issue statement" — PR2271, junsklee
> "테스트 의도(HA 모드 UNIQUE 제약)가 파티션 오류로 가려지지 않도록..." — PR2489, zionyun

**P12 — 버그/스펙 판별 유보**: 리뷰 중 제품 버그를 발견하고 "스펙인가 버그인가" 판단 후 신규 이슈로 트래킹. 리뷰가 회귀 검증을 넘어 *버그 발견* 역할. 봇이 못 하는 영역 — tc-reviewer는 "이상 신호 + 사람 에스컬레이션"까지만.
> "새로운 이슈를 수정했는데 기존 정상동작하던 TC가 fail... 스펙변경인지 버그인지 확인 필요" — PR2369, kwonhoil
> "This is exponential growth. It exhausts memory (OOM) before the depth-32 guard... let's track... CBRD-27032" — PR2988, kangmin5505

**P13 — 옵티마이저 플랜 안정화(tie/flaky)**: 동률 인덱스·비용 경계로 plan이 run마다 바뀌는 flaky. P2(출력 정렬)와 별개로 *실행계획* 안정화. L3 반복 실행으로만 검출.
> "동률이라 run마다 plan이 바뀌는 flaky 상태... tie 안정화를 위해 ta 인덱스만 고정" — PR2871, shparkcubrid
> "플랜 고정 및 안정성 확보 차원에서, 옵티마이저 변화에 영향받지 않도록 인덱스를 추가" — PR2466, shparkcubrid

**P14 — 최소성**: 이슈 재현·검증에 불필요한 힌트·파라미터·중복 케이스를 덜어 최소 재현으로. 무관한 요소는 검증을 흐리고 유지보수 부담만 는다(5년 확장에서 뚜렷해진 관점).
> "USE_MERGE 힌트를 사용했기 때문에 통계정보 갱신도 필요하지 않습니다" — PR1777, youngjinj
> "힌트 사용 없이 한 번씩만 테스트 하는 것이 좋을 것 같습니다" — PR1791, youngjinj

**P15 — 불변식만 단언**: 환경·빌드·시간마다 달라질 수 있는 값(page id, 시작값, 올해 연도)을 answer에 박지 말고 *보장되는 불변식*만 단언. P2(출력 순서)와 달리 "값 자체가 비보장이면 단언하지 말라"는 각도.
> "The p_cur_volumeid may not be 0... What can be guaranteed is that when next is -1, cur page has the maximum value. Adding only guaranteed test cases will prevent unnecessary errors later" — PR1688, shparkcubrid
> "년도가 포함되어 있지 않아 현재는 2025년으로 answer와 동일하지만 내년에는 2026년으로 처리되면서 실패합니다" — PR2010, ssihil

## L2 페르소나 렌즈 (PR 성격별 지배 렌즈)

L2는 관점을 개별로 순회하기보다 **리뷰 철학(렌즈)** 단위로 돌린다. 마이닝에서 드러난 두 주 렌즈가 tc-reviewer가 받는 두 PR 성격에 대응한다(DESIGN D5). **렌즈명은 기능으로 두고 사람 이름은 few-shot 출처로만** 기록한다 — 개인 박제 금지(사람이 바뀌어도 철학이 남게).

| 렌즈 | PR 성격 | 담는 관점 | 질문셋(요지) | 대표(few-shot 출처) |
|---|---|---|---|---|
| **coverage-expansion** | 신규형 (새 TC) | P4·P8·P9·P14 | positive↔negative 대칭? 경계 3점(직전/경계/직후)? 조합 매트릭스(JOIN×함수×방향)? 상위/형제 개념(orderby_num이면 rownum·inst_num·group_num도)? 대칭 연산(delete 힌트를 update/select에도)? 다단계 체인(권한 위임→유저 삭제 후 잔존)? 결과 검증 데이터/쿼리(에러만 말고 성공 후 상태)? 변별력(분포·통계·규모)? 최소성(불필요 힌트·중복 제거)? 카테고리 적합성(OOM·서버다운은 shell로)? | bagus-kim, ssihil |
| **answer-vs-spec** | 변경형 (답지/TC 수정) | P7·P11·P12·P15 | answer가 왜 바뀌었나·이전이 틀렸나? 실행과 answer가 일치하나(성공인데 fail 등)? 이슈가 규정한 정확한 범위인가? 결과값 의미가 맞나(반올림·잘림·타입변환·NULL)? 의존 이슈 머지 후 답지 변경을 예고·주석했나? 스펙인가 버그인가(개발자 확인)? .sql 수정 시 .answer·주석도 갱신됐나? | kwonhoil, swi0110 |
| **determinism-convention** | 공통 | P2·P5·P6·P10 | 다행 SELECT에 ORDER BY? cleanup 복원? trace/evaluate 페어? 시간·연도 의존 값 아닌가? 주석↔answer 정합? | ssihil |
| **plan-stability** | 공통(플랜 TC) | P3·P13 | fix 경로를 타나? 힌트가 실제 적용됐나(오타·뷰머징·모호한 인덱스명으로 무시 안 됨)? plan을 evaluate로 라벨(select 남발로 불필요 plan 출력 억제)? 통계·인덱스로 plan 고정(tie/flaky)? 조인순서 변경이 의도된 것? | youngjinj, shparkcubrid |

- 지배 렌즈는 PR 성격이 정하고, **determinism-convention은 성격 무관 항상 적용**.
- 렌즈를 **독립 서브에이전트로 병렬 실행**하면 관점 다양성이 재현율을 높인다(perspective-diverse verify).
- **철학의 성격에 따라 담기는 층이 다르다**: coverage-expansion은 예측 가능한 패턴이라 규칙·템플릿화(create 스킬 P4)해 **작성 예방**에도 쓰고, answer-vs-spec은 케이스별 판단이라 규칙 불가 → **L2 판정 각도로만** 재현. 전자는 author, 후자는 reviewer.
- **질문셋·few-shot은 5년(1,358건) 분류로 보강 완료**. 각 렌즈 질문셋은 실제 반복 지적에서 도출.

## few-shot 앵커 (L2 프롬프트 투입용 실례)

- **P4**: "prepare, execute 구문을 사용하는 케이스를 추가해 주세요 (Invalid, valid 케이스 추가)" — PR2431, kwonhoil / "scalar subquery in SELECT list - should not run in parallel; ... 추가 시나리오" — PR2497, bagus-kim
- **P7**: "이전 답지가 올바른 처리로 보여집니다. 위 답지가 어떤 이유로 변경된 건가요?" — PR2464, kwonhoil / "조인순서가 변경된 이유는?" — PR2462, kwonhoil
- **P6**: "answer file에서 테스트 위치를 확인할 수 있도록 각 주석에 evaluate 구문 추가... 나머지 sql tc도 동일" — PR2501, ssihil
- **P8**: "join_orderby_skip.sql의 Q130 테스트와 중복" — PR2427, youngjinj / "r_outer_join.sql에 동일한 right outer join 케이스가 존재" — PR2419, zionyun

## tc-author 선제 개선 피드백 (왕복 근본 축소)

리뷰 왕복을 줄이는 최선은 애초에 안 틀리게 하는 것. 사람이 가장 자주 지적하는 항목을 `cubrid-sql-tc-create` 스킬·tc-author Author 단계에서 선제 방지:
- 다행 SELECT엔 항상 ORDER BY (P2)
- 시나리오마다 evaluate 라벨, trace on/off 페어 (P6)
- CREATE 앞 DROP IF EXISTS, prepare 후 deallocate, 만든 것 전부 cleanup (P5)
- 이슈 repro의 경계·부정 케이스까지 (P4)
- 불필요한 힌트·설정·중복 제거, 최소 재현 (P14)
- 환경/시간 의존 값 대신 불변식만 단언 (P15)

## 관찰 (마이닝 부수 발견)

- **언어**: 리뷰 코멘트 한국어 90%+ (영어는 junsklee/hyunikn 일부·봇). → tc-reviewer 코멘트 초안 기본 = 한국어.
- **리뷰어 편중**: ssihil(결정성·컨벤션·cleanup), kwonhoil(답지 사유·케이스), bagus-kim(케이스 SQL 제안), shparkcubrid(플랜 안정화), youngjinj(인덱스 경로·중복). → L2를 페르소나 렌즈로 분할 시 재현율 향상 여지.
- **분포 왜곡 주의**: PR2738(NUMERIC draft) 하나가 P7 지적 다수를 생성. 빈도는 PR 편중 감안한 등급(최다/매우높음/높음/중간/낮음)으로 표기.
- **5년 렌즈 분포**(유효 1,358건): coverage-expansion 247·answer-vs-spec 215·determinism-convention 149·plan-stability 83·미분류 664. 미분류 대부분은 기존 렌즈로 재귀속되며, 여기서 신규 P14(최소성)·P15(불변식 단언)를 발견. 5년 상위 리뷰어: kwonhoil·ssihil·hyunikn·swi0110·youngjinj.

## 데이터 출처

`work/tc-review-mining/`(gitignore). **1년(2025-07~2026-07)**: chunk_0..4.jsonl(사람 라인 600건), greptile.jsonl(118, 봇 대조), issue_human.jsonl(149). **5년(2021-07~2026-07)**: review_comments_5y_raw.json(라인 2,958/사람 2,800), merged_prs_5y.json, 렌즈 버킷(bucket_5y.py로 유효 1,358건 자동 태깅 → 렌즈별 샘플 정제). 백테스트(재현율 측정) 시 같은 데이터가 정답지.
