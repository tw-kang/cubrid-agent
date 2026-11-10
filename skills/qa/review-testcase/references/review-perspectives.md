# Perspective catalog (review perspectives) — the canonical L2 reference

**Basis: classification of 1,358 human line comments on merged PRs.** [Data sources](#data-sources) gives the period.

Its purpose is not to hold the TC rules — those are the testcase repo's deployed rulebook, which [SKILL.md](../SKILL.md) reads from `origin/develop` — but to specify **how each perspective is handled**: which layer catches it (L1 static lint / L2 LLM judgment / L3 execution), whether it overlaps with the greptile/codex bots, which reviewer lens is strongest, which rulebook section holds its rule, and what the few-shot anchor is. A section named here is a `##` or `###` heading of that file in the rulebook.

## Processing-layer assignment (the core output of the mining)

| id | Perspective | Frequency | Processing layer | Bot overlap | Owning lens | Rule in the rulebook |
|---|---|---|---|---|---|---|
| P4 | Case coverage (adding scenarios) | Most frequent | **L2** (must read issue + diff) | Weak | bagus-kim, kwonhoil | `sql/rules/test-perspectives.md` "Scenarios to cover" |
| P2 | Determinism — missing ORDER BY | Very high | **L1** (static) + L3 (confirm) | Partial | ssihil | `sql/rules/test-perspectives.md` "What sql TCs cannot check" |
| P7 | Justification for answer changes and consistency of expected values | Very high | **L2** (cross-check against the issue) | Weak | kwonhoil, ssihil | `sql/AGENTS.md` "The PR"; `sql/rules/writing-rules.md` "Header and labels", "Answer files" |
| P6 | Convention — evaluate/trace/queryPlan/server-message | High | **L1** (static) | No | ssihil | `sql/rules/writing-rules.md` "Header and labels", "Statements and comments", "Plans and traces", "Cleanup" |
| P11 | TC intent ↔ issue alignment *(new)* | High | **L2** (issue body required) | Partial | many | `sql/rules/test-perspectives.md` "Scenarios to cover", "Evidence in the answer file" |
| P3 | Fix-path coverage | Medium | L2 + **L3** (plan/trace) | **Strong (bot)** | youngjinj, shparkcubrid | `sql/rules/test-perspectives.md` "Evidence in the answer file" |
| P13 | Optimizer plan stabilization — tie/flaky *(new)* | Medium | **L3** (repeated-run plan) | No | shparkcubrid | `sql/rules/test-perspectives.md` "Plans, hints, and data size" |
| P5 | Isolation and self-containment — DROP/commit/deallocate | Medium | **L1** (static) | Partial | ssihil, bagus-kim | `sql/rules/writing-rules.md` "Cleanup"; `medium/rules/writing-rules.md` "Start and end of the file" |
| P8 | Duplication of an existing TC | Low | **L2** (corpus search) | No | youngjinj | `sql/AGENTS.md` "Before the PR" |
| P12 | Deferring the bug-vs-spec determination *(new)* | Low | **L2** (escalate to a human) | No | many | `sql/rules/writing-rules.md` "Answer files", "Changing an existing TC" |
| P9 | Runtime and performance | Low | **L3** (elapse) | No | bagus-kim | `sql/rules/test-perspectives.md` "Plans, hints, and data size", "What sql TCs cannot check" |
| P1 | Answer integrity | Low (human) | L3 | **Strong (bot)** | — | `sql/rules/writing-rules.md` "Answer files" |
| P10 | Language of comments and commits | Low | **L1** | Partial | — | `sql/rules/writing-rules.md` "Header and labels"; `sql/AGENTS.md` "The PR" |
| P14 | Minimality *(new)* | Medium | **L2** | No | youngjinj, ssihil | `sql/rules/test-perspectives.md` "Scenarios to cover" |
| P15 | Assert only invariants *(new)* | Medium | **L2**+L3 | Partial | shparkcubrid, ssihil | `sql/rules/test-perspectives.md` "What sql TCs cannot check" |

## L1 — the perspectives humans flagged most

Mechanical comments humans made *repeatedly* belong in static rules, not LLM judgment. L1 checks the rulebook sections that [SKILL.md](../SKILL.md) L1 names, and the table above names the rule of each perspective. The mining found these perspectives repeated most, so look at them first:

- **P2** — ssihil's most-repeated comment. A tie under `ORDER BY` was PR#3091's major.
- **P6** — including the L1 check of a `.queryPlan` file against the plan output in the answer file ([SKILL.md](../SKILL.md) L1).
- **P6/P7 (shared)** — a label changed in the `.sql` file and not in the answer file was PR#3091's live blocker. It applies regardless of PR character.
- **P5** and **P10**.

## Division of labor with the bots

The greptile/codex bots already catch **P1 (answer integrity), P2 (part of determinism), and P3 (fix-path coverage)** precisely, with P1/P2 severity badges (e.g., "NULL result-value contamination", "sampling result is a fixed value", "new syntax not verified", "DROP path bypassed"). review-testcase therefore:
- Only **references/reinforces the bots' comments** for these perspectives (suppressing duplicate comments).
- Concentrates its L2 capacity on **P4, P7, P11, P13, P6, P8 — where the bots are weak**.

## New perspective definitions (not in the seed — discovered by mining)

**P11 — TC intent ↔ issue alignment**: its rule is `sql/rules/test-perspectives.md` "Scenarios to cover". Unlike P3 (the fix code path), this is about *the intent of the issue's scenario*. It can be judged only by reading the issue body (the L2 premise = Ground).
> "Not sure if you've grasped the JIRA issue fully.. This test case has little to do with the issue statement" — PR2271, junsklee
> "테스트 의도(HA 모드 UNIQUE 제약)가 파티션 오류로 가려지지 않도록..." — PR2489, zionyun

**P12 — Deferring the bug-vs-spec determination**: During review you find a product bug, decide "is this spec or a bug?", and then track it as a new issue. Review goes beyond regression checking to also *finding bugs*. This is an area the bots can't handle — review-testcase goes only as far as "flag the anomaly + escalate to a human". What the TC itself does with such a bug is `sql/rules/writing-rules.md` "Answer files" and "Changing an existing TC".
> "새로운 이슈를 수정했는데 기존 정상동작하던 TC가 fail... 스펙변경인지 버그인지 확인 필요" — PR2369, kwonhoil
> "This is exponential growth. It exhausts memory (OOM) before the depth-32 guard... let's track... CBRD-27032" — PR2988, kangmin5505

**P13 — Optimizer plan stabilization (tie/flaky)**: Flakiness where the plan changes from run to run due to tied indexes or a cost boundary. Distinct from P2 (output ordering), this stabilizes the *execution plan*. Detectable only through repeated L3 runs. The rule for a plan that a TC checks is `sql/rules/test-perspectives.md` "Plans, hints, and data size".
> "동률이라 run마다 plan이 바뀌는 flaky 상태... tie 안정화를 위해 ta 인덱스만 고정" — PR2871, shparkcubrid
> "플랜 고정 및 안정성 확보 차원에서, 옵티마이저 변화에 영향받지 않도록 인덱스를 추가" — PR2466, shparkcubrid

**P14 — Minimality**: its rule is `sql/rules/test-perspectives.md` "Scenarios to cover". The perspective became clear in the extended mining.
> "USE_MERGE 힌트를 사용했기 때문에 통계정보 갱신도 필요하지 않습니다" — PR1777, youngjinj
> "힌트 사용 없이 한 번씩만 테스트 하는 것이 좋을 것 같습니다" — PR1791, youngjinj

**P15 — Assert only invariants**: its rule is `sql/rules/test-perspectives.md` "What sql TCs cannot check". Unlike P2 (output order), this is the angle of "if the value itself isn't guaranteed, don't assert it".
> "The p_cur_volumeid may not be 0... What can be guaranteed is that when next is -1, cur page has the maximum value. Adding only guaranteed test cases will prevent unnecessary errors later" — PR1688, shparkcubrid
> "년도가 포함되어 있지 않아 현재는 2025년으로 answer와 동일하지만 내년에는 2026년으로 처리되면서 실패합니다" — PR2010, ssihil

## L2 persona lenses (the dominant lens by PR character)

Rather than iterating over perspectives one by one, L2 runs by the unit of a **review philosophy (lens)**. The two main lenses that emerged from the mining correspond to the two PR characters review-testcase receives (DESIGN D5). **Keep the lens names functional and record people's names only as few-shot sources** — no pinning to individuals (so the philosophy survives even when people change).

| Lens | PR character | Perspectives covered | Rulebook sections, then the questions the rulebook does not hold | Representatives (few-shot source) |
|---|---|---|---|---|
| **coverage-expansion** | New-type (new TC) | P4·P8·P9·P14 | `sql/rules/test-perspectives.md` "Scenarios to cover" (boundaries, invalid inputs, related functions and DML, minimality), "Evidence in the answer file" (the state after a success), "What sql TCs cannot check" (category fit); `sql/AGENTS.md` "Before the PR" (duplicates). Then: Combination matrix (JOIN × function × direction)? Multi-step chains (privilege delegation → residue after the user is dropped)? Discriminating power (distribution, statistics, scale)? | bagus-kim, ssihil |
| **answer-vs-spec** | Change-type (answer/TC modification) | P7·P11·P12·P15 | `sql/AGENTS.md` "The PR" (why answer lines changed); `sql/rules/writing-rules.md` "Answer files" (made by a run, `.sql` and answer in one PR, `.answer_cci`) and "Header and labels" (comments and labels match the answer); `sql/rules/test-perspectives.md` "Scenarios to cover" (the issue's scope) and "Evidence in the answer file" (no `'OK'`/`'FAIL'` verdict — the dead assertion). Then: Is the result value's meaning correct (rounding, truncation, type conversion, NULL)? Is it spec or a bug (confirm with the developer)? | kwonhoil, swi0110 |
| **determinism-convention** | Shared | P2·P5·P6·P10 | `sql/rules/test-perspectives.md` "What sql TCs cannot check"; `sql/rules/writing-rules.md` "Header and labels", "Statements and comments", "Cleanup", "Answer files". The rulebook holds every question of this lens; its few-shot entries carry the judgment cases. | ssihil |
| **plan-stability** | Shared (plan TCs) | P3·P13 | `sql/rules/test-perspectives.md` "Evidence in the answer file" (the bug path, and a hint that took effect) and "Plans, hints, and data size"; `sql/rules/writing-rules.md` "Header and labels" (an `evaluate` label, not a `select`). Then: Is the hint ignored because view merging renamed the alias? Pin the plan with statistics/indexes (tie/flaky)? Is the join-order change intended? | youngjinj, shparkcubrid |

- The PR character decides the dominant lens, and **determinism-convention always applies regardless of character**.
- Running the lenses **as independent sub-agents in parallel** raises recall through perspective diversity (perspective-diverse verify).
- **The layer a philosophy lands in depends on its character**: coverage-expansion is a predictable pattern, so its rules went into the rulebook (`sql/rules/test-perspectives.md` "Scenarios to cover", P4) that the authoring skills read, and it serves **prevention at authoring time** too; answer-vs-spec is a case-by-case judgment that can't be reduced to rules → reproduced **only as an L2 judgment angle**. The former is author, the latter reviewer.
- **The question sets and few-shots have been reinforced by the 1,358-comment classification.** Each lens's question set is derived from actual recurring comments.
- **Backtesting verified that the lenses reproduce the comments**: answer-vs-spec (P7·P12·P15) and coverage-expansion (P4) reproduce actual human comments, character routing is accurate, and false positives are effectively 0. The bot also adds valid comments humans missed (dead-assertion and physical-value-basis kinds).
- **coverage-expansion should not merely point out "it's lacking" but propose the cases to add as runnable `evaluate`+SQL** (backtest PoC improvement 1): the bot reproduced the *category*, such as "no negative case", but was weak on the volume of proposing many concrete cases the way bagus-kim does → the lens prompt forces concrete SQL proposals.

## Few-shot anchors (real examples to feed into the L2 prompt)

> The formal few-shot bank (curated from the extended mining): [few-shot-bank.md](./few-shot-bank.md). Each entry has the structure situation → comment (actual quote) → pattern (reusable rule) → source, and the source PR's own entry is excluded during backtesting. Below is a representative excerpt.

- **P4**: "prepare, execute 구문을 사용하는 케이스를 추가해 주세요 (Invalid, valid 케이스 추가)" — PR2431, kwonhoil / "scalar subquery in SELECT list - should not run in parallel; ... 추가 시나리오" — PR2497, bagus-kim
- **P7**: "이전 답지가 올바른 처리로 보여집니다. 위 답지가 어떤 이유로 변경된 건가요?" — PR2464, kwonhoil / "조인순서가 변경된 이유는?" — PR2462, kwonhoil
- **P6**: "answer file에서 테스트 위치를 확인할 수 있도록 각 주석에 evaluate 구문 추가... 나머지 sql tc도 동일" — PR2501, ssihil
- **P8**: "join_orderby_skip.sql의 Q130 테스트와 중복" — PR2427, youngjinj / "r_outer_join.sql에 동일한 right outer join 케이스가 존재" — PR2419, zionyun

## Proactive improvement feedback for author-testcase (cutting round-trips at the root)

The best way to reduce review round-trips is to not get it wrong in the first place. `create-sql` and `author-testcase` write a TC by the same deployed rulebook this review judges by, so the items humans comment on most often are prevented there. A finding that recurs and that no rule covers goes to the rulebook as a proposal, as the testcase repo's root `AGENTS.md` says, not into this file.

## Observations (incidental findings from the mining)

- **Language**: 90%+ of review comments are in Korean (English is some of junsklee/hyunikn plus the bots). → review-testcase's default comment draft = Korean.
- **Reviewer skew**: ssihil (determinism, convention, cleanup), kwonhoil (answer rationale, cases), bagus-kim (case SQL proposals), shparkcubrid (plan stabilization), youngjinj (index path, duplication). → Splitting L2 into persona lenses leaves room to improve recall.
- **Watch for distribution skew**: PR2738 (a NUMERIC draft) alone generated many of the P7 comments. Frequency is expressed as a grade that accounts for PR skew (most frequent / very high / high / medium / low).
- **Lens distribution of the extended mining** (1,358 valid): coverage-expansion 247, answer-vs-spec 215, determinism-convention 149, plan-stability 83, unclassified 664. Most of the unclassified re-attribute to the existing lenses, and it was here that the new P14 (minimality) and P15 (invariant assertion) were discovered. Top reviewers in the raw collection: kwonhoil, ssihil, hyunikn, swi0110, youngjinj.

## Data sources

`work/tc-review-mining/` (gitignored). **1 year (2025-07 to 2026-07)**: chunk_0..4.jsonl (600 human lines), greptile.jsonl (118, bot comparison), issue_human.jsonl (149). **Raw collection (created 2021-08 to 2026-07)**: review_comments_5y_raw.json (2,958 lines / 2,800 human). **Extended mining (PRs merged 2023-11-23 to 2026-07-15)**: merged_prs_5y.json (1,000 PRs — the query's cap, so it reaches back only to 2023-11-23), lens buckets (bucket_5y.py keeps only the raw comments on those PRs and auto-tags them to 1,358 valid → per-lens sample refinement). The `_5y` in the file names is not the range the data covers. During backtesting (recall measurement), the same data is the ground truth.
