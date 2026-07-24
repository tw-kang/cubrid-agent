# Perspective catalog (review perspectives) — the canonical L2 reference

**Basis: classification of 1,358 human line comments on merged PRs over 5 years (2021-07 to 2026-07).**

The single canonical source shared by review-testcase L2 and the author-testcase Review lane. Its purpose is not to be a "list of perspectives" but to specify **how each perspective is handled**: which layer catches it (L1 static lint / L2 LLM judgment / L3 execution), whether it overlaps with the greptile/codex bots, which reviewer lens is strongest, and what the few-shot anchor is.

## Processing-layer assignment (the core output of the mining)

| id | Perspective | Frequency | Processing layer | Bot overlap | Owning lens |
|---|---|---|---|---|---|
| P4 | Case coverage (adding scenarios) | Most frequent | **L2** (must read issue + diff) | Weak | bagus-kim, kwonhoil |
| P2 | Determinism — missing ORDER BY | Very high | **L1** (static) + L3 (confirm) | Partial | ssihil |
| P7 | Justification for answer changes and consistency of expected values | Very high | **L2** (cross-check against the issue) | Weak | kwonhoil, ssihil |
| P6 | Convention — evaluate/trace/queryPlan/server-message | High | **L1** (static) | No | ssihil |
| P11 | TC intent ↔ issue alignment *(new)* | High | **L2** (issue body required) | Partial | many |
| P3 | Fix-path coverage | Medium | L2 + **L3** (plan/trace) | **Strong (bot)** | youngjinj, shparkcubrid |
| P13 | Optimizer plan stabilization — tie/flaky *(new)* | Medium | **L3** (repeated-run plan) | No | shparkcubrid |
| P5 | Isolation and self-containment — DROP/commit/deallocate | Medium | **L1** (static) | Partial | ssihil, bagus-kim |
| P8 | Duplication of an existing TC | Low | **L2** (corpus search) | No | youngjinj |
| P12 | Deferring the bug-vs-spec determination *(new)* | Low | **L2** (escalate to a human) | No | many |
| P9 | Runtime and performance | Low | **L3** (elapse) | No | bagus-kim |
| P1 | Answer integrity | Low (human) | L3 | **Strong (bot)** | — |
| P10 | Language (comments and commits in English) | Low | **L1** | Partial | — |
| P14 | Minimality — remove needless hints/settings/duplicate cases, minimal reproduction *(new)* | Medium | **L2** | No | youngjinj, ssihil |
| P15 | Assert only invariants — avoid environment/build-dependent values (page id, start value, time) *(new)* | Medium | **L2**+L3 | Partial | shparkcubrid, ssihil |

## Automatic lint rules to promote to L1 (the recurring comments the mining flagged)

Mechanical comments humans made *repeatedly* belong in static rules, not LLM judgment. Detecting these automatically at L1 removes the reviewer's repetitive labor:

- **P2** A SELECT that returns multiple rows has no `ORDER BY` (ssihil's most-repeated comment). Aggregate/scalar/error cases are exceptions. **Even with `ORDER BY`/`ORDER SIBLINGS BY`, if the sort keys tie, sibling order is not guaranteed** — sort down to a unique key, or use tie-free data (stable across 3 local runs ≠ guaranteed by spec; ties into P13). ← PR#3091 major.
- **P6** Unbalanced `set trace on` ↔ `set trace off` pairing; trace left on after use.
- **P6** Presence/absence of an empty `.queryPlan` file vs. plan output in the answer (flag when they don't match).
- **P6** Only a scenario comment is present, with no `evaluate 'Case N: ...'` label.
- **P6/P7 (shared)** Does the `evaluate` label **text match exactly between `.sql` and `.answer`** — because CTP echoes and compares the label in the result, if you change the label in `.sql` you must regenerate `.answer` (changing only one side makes that case Fail regardless of data). A shared check that applies regardless of PR character. ← PR#3091 live blocker.
- **P5** Missing `DROP TABLE IF EXISTS` before `CREATE TABLE`; missing `deallocate prepare` in cleanup after `prepare`; missing view/synonym/serial cleanup.
- **P10** Non-English `.sql` comments or commit messages.

## Division of labor with the bots

The greptile/codex bots already catch **P1 (answer integrity), P2 (part of determinism), and P3 (fix-path coverage)** precisely, with P1/P2 severity badges (e.g., "NULL result-value contamination", "sampling result is a fixed value", "new syntax not verified", "DROP path bypassed"). review-testcase therefore:
- Only **references/reinforces the bots' comments** for these perspectives (suppressing duplicate comments).
- Concentrates its L2 capacity on **P4, P7, P11, P13, P6, P8 — where the bots are weak**.

## New perspective definitions (not in the seed — discovered by mining)

**P11 — TC intent ↔ issue alignment**: Does the TC actually target the bug the issue describes? Unlike P3 (the fix code path), this is about *the intent of the issue's scenario*. It can be judged only by reading the issue body (the L2 premise = Ground).
> "Not sure if you've grasped the JIRA issue fully.. This test case has little to do with the issue statement" — PR2271, junsklee
> "테스트 의도(HA 모드 UNIQUE 제약)가 파티션 오류로 가려지지 않도록..." — PR2489, zionyun

**P12 — Deferring the bug-vs-spec determination**: During review you find a product bug, decide "is this spec or a bug?", and then track it as a new issue. Review goes beyond regression checking to also *finding bugs*. This is an area the bots can't handle — review-testcase goes only as far as "flag the anomaly + escalate to a human".
> "새로운 이슈를 수정했는데 기존 정상동작하던 TC가 fail... 스펙변경인지 버그인지 확인 필요" — PR2369, kwonhoil
> "This is exponential growth. It exhausts memory (OOM) before the depth-32 guard... let's track... CBRD-27032" — PR2988, kangmin5505

**P13 — Optimizer plan stabilization (tie/flaky)**: Flakiness where the plan changes from run to run due to tied indexes or a cost boundary. Distinct from P2 (output ordering), this stabilizes the *execution plan*. Detectable only through repeated L3 runs.
> "동률이라 run마다 plan이 바뀌는 flaky 상태... tie 안정화를 위해 ta 인덱스만 고정" — PR2871, shparkcubrid
> "플랜 고정 및 안정성 확보 차원에서, 옵티마이저 변화에 영향받지 않도록 인덱스를 추가" — PR2466, shparkcubrid

**P14 — Minimality**: Pare away hints, parameters, and duplicate cases that aren't needed to reproduce and verify the issue, down to a minimal reproduction. Irrelevant elements blur the verification and only add maintenance burden (a perspective that became clear over the 5-year expansion).
> "USE_MERGE 힌트를 사용했기 때문에 통계정보 갱신도 필요하지 않습니다" — PR1777, youngjinj
> "힌트 사용 없이 한 번씩만 테스트 하는 것이 좋을 것 같습니다" — PR1791, youngjinj

**P15 — Assert only invariants**: Don't hard-code values that can vary by environment, build, or time (page id, start value, the current year) into the answer; assert only *guaranteed invariants*. Unlike P2 (output order), this is the angle of "if the value itself isn't guaranteed, don't assert it".
> "The p_cur_volumeid may not be 0... What can be guaranteed is that when next is -1, cur page has the maximum value. Adding only guaranteed test cases will prevent unnecessary errors later" — PR1688, shparkcubrid
> "년도가 포함되어 있지 않아 현재는 2025년으로 answer와 동일하지만 내년에는 2026년으로 처리되면서 실패합니다" — PR2010, ssihil

## L2 persona lenses (the dominant lens by PR character)

Rather than iterating over perspectives one by one, L2 runs by the unit of a **review philosophy (lens)**. The two main lenses that emerged from the mining correspond to the two PR characters review-testcase receives (DESIGN D5). **Keep the lens names functional and record people's names only as few-shot sources** — no pinning to individuals (so the philosophy survives even when people change).

| Lens | PR character | Perspectives covered | Question set (gist) | Representatives (few-shot source) |
|---|---|---|---|---|
| **coverage-expansion** | New-type (new TC) | P4·P8·P9·P14 | positive↔negative symmetry? Three boundary points (just-before/boundary/just-after)? Combination matrix (JOIN × function × direction)? Parent/sibling concepts (if orderby_num, then rownum, inst_num, group_num too)? Symmetric operations (apply a delete hint to update/select as well)? Multi-step chains (privilege delegation → residue after the user is dropped)? Result-verification data/query (not just the error, but the state after success)? Discriminating power (distribution, statistics, scale)? Minimality (remove needless hints/duplicates)? Category fit (OOM and server-down go to shell)? | bagus-kim, ssihil |
| **answer-vs-spec** | Change-type (answer/TC modification) | P7·P11·P12·P15 | Why did the answer change — was the previous one wrong? Does execution match the answer (e.g., it succeeds yet fails)? Is it the exact scope the issue defines? Is the result value's meaning correct (rounding, truncation, type conversion, NULL)? Was the answer change announced/commented after the dependent issue merged? Is it spec or a bug (confirm with the developer)? When `.sql` was modified, were `.answer` and the comments updated too? **Prevent dead assertions**: if you change only `.answer` and leave the comparison literal/assertion in `.sql` (`if(…=target,'ok','nok')`) untouched, verification degrades into the meaningless act of confirming only "it differs from the old value" — did you fix the `.sql` assertion against the new correct answer too? Was the **`.answer_cci` counterpart** updated as well? | kwonhoil, swi0110 |
| **determinism-convention** | Shared | P2·P5·P6·P10 | ORDER BY on a multi-row SELECT (if keys tie, order isn't guaranteed → sort to a unique key)? cleanup restored? trace/evaluate pairs? **`.sql`↔`.answer` evaluate-label pair match (regenerate the answer if you change a label)**? Not a time/year-dependent value? Comment ↔ answer consistency? | ssihil |
| **plan-stability** | Shared (plan TCs) | P3·P13 | Does it exercise the fix path? Is the hint actually applied (not ignored due to a typo, view merging, or an ambiguous index name)? Label the plan with evaluate (suppress needless plan output from overusing select)? Pin the plan with statistics/indexes (tie/flaky)? Is the join-order change intended? | youngjinj, shparkcubrid |

- The PR character decides the dominant lens, and **determinism-convention always applies regardless of character**.
- Running the lenses **as independent sub-agents in parallel** raises recall through perspective diversity (perspective-diverse verify).
- **The layer a philosophy lands in depends on its character**: coverage-expansion is a predictable pattern, so it is turned into rules/templates (create skill, P4) and used for **prevention at authoring time** too; answer-vs-spec is a case-by-case judgment that can't be reduced to rules → reproduced **only as an L2 judgment angle**. The former is author, the latter reviewer.
- **The question sets and few-shots have been reinforced by the 5-year (1,358-comment) classification.** Each lens's question set is derived from actual recurring comments.
- **Backtesting verified that the lenses reproduce the comments**: answer-vs-spec (P7·P12·P15) and coverage-expansion (P4) reproduce actual human comments, character routing is accurate, and false positives are effectively 0. The bot also adds valid comments humans missed (dead-assertion and physical-value-basis kinds).
- **coverage-expansion should not merely point out "it's lacking" but propose the cases to add as runnable `evaluate`+SQL** (backtest PoC improvement 1): the bot reproduced the *category*, such as "no negative case", but was weak on the volume of proposing many concrete cases the way bagus-kim does → the lens prompt forces concrete SQL proposals.

## Few-shot anchors (real examples to feed into the L2 prompt)

> The formal few-shot bank (44 entries per lens, curated from the 5-year mining): [few-shot-bank.md](./few-shot-bank.md). Each entry has the structure situation → comment (actual quote) → pattern (reusable rule) → source, and the source PR's own entry is excluded during backtesting. Below is a representative excerpt.

- **P4**: "prepare, execute 구문을 사용하는 케이스를 추가해 주세요 (Invalid, valid 케이스 추가)" — PR2431, kwonhoil / "scalar subquery in SELECT list - should not run in parallel; ... 추가 시나리오" — PR2497, bagus-kim
- **P7**: "이전 답지가 올바른 처리로 보여집니다. 위 답지가 어떤 이유로 변경된 건가요?" — PR2464, kwonhoil / "조인순서가 변경된 이유는?" — PR2462, kwonhoil
- **P6**: "answer file에서 테스트 위치를 확인할 수 있도록 각 주석에 evaluate 구문 추가... 나머지 sql tc도 동일" — PR2501, ssihil
- **P8**: "join_orderby_skip.sql의 Q130 테스트와 중복" — PR2427, youngjinj / "r_outer_join.sql에 동일한 right outer join 케이스가 존재" — PR2419, zionyun

## Proactive improvement feedback for author-testcase (cutting round-trips at the root)

The best way to reduce review round-trips is to not get it wrong in the first place. Preemptively prevent the items humans comment on most often at the `create-sql` skill / author-testcase Author stage:
- Always ORDER BY on a multi-row SELECT (P2)
- An evaluate label per scenario, trace on/off pairs (P6)
- DROP IF EXISTS before CREATE, deallocate after prepare, clean up everything you created (P5)
- Cover the boundary and negative cases of the issue repro (P4)
- Remove needless hints/settings/duplicates, minimal reproduction (P14)
- Assert only invariants instead of environment/time-dependent values (P15)

## Observations (incidental findings from the mining)

- **Language**: 90%+ of review comments are in Korean (English is some of junsklee/hyunikn plus the bots). → review-testcase's default comment draft = Korean.
- **Reviewer skew**: ssihil (determinism, convention, cleanup), kwonhoil (answer rationale, cases), bagus-kim (case SQL proposals), shparkcubrid (plan stabilization), youngjinj (index path, duplication). → Splitting L2 into persona lenses leaves room to improve recall.
- **Watch for distribution skew**: PR2738 (a NUMERIC draft) alone generated many of the P7 comments. Frequency is expressed as a grade that accounts for PR skew (most frequent / very high / high / medium / low).
- **5-year lens distribution** (1,358 valid): coverage-expansion 247, answer-vs-spec 215, determinism-convention 149, plan-stability 83, unclassified 664. Most of the unclassified re-attribute to the existing lenses, and it was here that the new P14 (minimality) and P15 (invariant assertion) were discovered. Top 5-year reviewers: kwonhoil, ssihil, hyunikn, swi0110, youngjinj.

## Data sources

`work/tc-review-mining/` (gitignored). **1 year (2025-07 to 2026-07)**: chunk_0..4.jsonl (600 human lines), greptile.jsonl (118, bot comparison), issue_human.jsonl (149). **5 years (2021-07 to 2026-07)**: review_comments_5y_raw.json (2,958 lines / 2,800 human), merged_prs_5y.json, lens buckets (auto-tagged to 1,358 valid by bucket_5y.py → per-lens sample refinement). During backtesting (recall measurement), the same data is the ground truth.
