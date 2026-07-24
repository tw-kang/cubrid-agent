# review-testcase L2 few-shot bank

A **collection of real human review examples** injected into the L2 domain-review subagent prompt. From 5 years of mining (2021-07 to 2026-07, `work/tc-review-mining/`), cases with a clearly reusable pattern were selected and structured per lens. The canonical perspective catalog is [review-perspectives.md](./review-perspectives.md).

## Usage
- review-testcase L2 injects, as few-shot examples, entries from the lens section matching the PR's nature: **new-testcase → coverage-expansion**, **change-testcase → answer-vs-spec**, **shared → determinism-convention · plan-stability** (plan TCs).
- Each entry: **Context** (situation) → **Finding** (verbatim reviewer comment) → **Pattern** (reusable rule the LLM generalizes) → **Source** (PR/reviewer).
- **The pattern is the point** — the goal is to make the bot apply this rule to new PRs. It should follow the pattern rather than copy-paste the quoted wording verbatim.

## Backtest isolation (important)
When backtesting a particular PR, inject the entries **excluding those whose source is that PR** (to prevent answer leakage). That is why each entry records its source PR.

## Caution — nature tags
The 4th field in the original mining files (`NEW`/`y1`) is a **time bucket** (y1 for the one-year set / NEW for the four-year extension), not the PR's nature (new-testcase/change-testcase). Judge the PR's nature from this document's **lens assignment**.

---

## coverage-expansion (new-testcase-dominant lens — P4 coverage · P8 duplication · P9 runtime · P14 minimality)

### [P4] Extend to sibling functions in the same parent category (family)
- **Context**: A TC covering the ORDERBY_NUM() function
- **Finding**: "Orderby_num()의 상위목록 'ROWNUM함수'에 ROWNUM, INST_NUM, GROUP_NUM도 포함됩니다. 이들에 대한 TC 추가가 필요하지 않을지 검토 바랍니다" + example `select ROWNUM rrnum,rnum,col_a,col_b from (select ROWNUM rnum,col_a,col_b from tbl order by col_a) where ROWNUM < 5 order by rnum desc`
- **Pattern**: When the function under test is one of several functions in a larger category (a parent concept), enumerate all the remaining functions in that category and propose an identically-shaped SQL case for each.
- **Source**: PR1790 / bagus-kim

### [P4] Symmetrically add hints/options applied to only one DML to the other DMLs
- **Context**: A TC that verified a hint combination on the delete statement only
- **Finding**: "cbrd_25382_2에서 delete문에 사용한 힌트 15~21도 update문에 추가하는 것이 좋겠습니다" (the same wording repeated for the select statement too)
- **Pattern**: When you find a set of hints/options applied to only one DML (delete), suggest symmetrically adding the same numbered hint set, in full, to the other DMLs (update, select) where the same hints are valid.
- **Source**: PR1936 / ssihil

### [P4] After deleting a middle node in a delegation chain, verify what remains
- **Context**: A TC for privilege handling when a user is deleted
- **Finding**: "u1이 u2에 조회·권한부여, u3엔 조회만; u2가 u3에 조회·권한부여(u3는 u1·u2 양쪽에서 받음) → u2 삭제 → u3에 u1으로부터 받은 권한만 남는지 확인" (+case #2)
- **Pattern**: For chain features delegated A→B→C, such as privileges or ownership, propose a multi-step scenario for "when the middle node (B) is deleted, what remains on the rest (C)" — grant across two or more levels → delete the middle → query for what survives.
- **Source**: PR1950 / kwonhoil

### [P4] Strengthen system-catalog verification queries with identifying columns, ordering, and noise filters
- **Context**: The result-checking select in several privilege (grant/revoke) TCs (the same finding repeated across 4 PRs)
- **Finding**: "select grantor_name, grantee_name, object_name, auth_type, is_grantable from db_auth where grantee_name != 'PUBLIC' order by grantor_name, grantee_name; — object_name·auth_type 값이 여러 행에서 동일하니 바꾸는 게 좋다", "object_type, object_name, auth_type 추가; 동일 쿼리는 파일 내 모두 고쳐달라"
- **Pattern**: Make verification queries that check results via a system catalog (db_auth, etc.) have (1) a noise filter like `!= 'PUBLIC'`, (2) enough columns to distinguish rows, and (3) an order by over multiple key columns. When the same-shaped query appears several times in a file, require that they all be fixed identically. (repeated across 4 PRs = highly reusable)
- **Source**: PR1948·1950·1956·1957 / ssihil·kwonhoil

### [P4] Test type conversion/precision with digit-boundary values
- **Context**: Four conversion TCs that pass NUMERIC as a procedure parameter
- **Finding**: `call numeric_test(1234567890123456789.1234567890123456789);` / `call t_NUMERIC_CHAR('NUMERIC(8,4)', 'CHAR', cast(0.123456789 as numeric(8,4)));` (repeated for VARCHAR and DOUBLE too)
- **Pattern**: For type-conversion/precision TCs, propose SQL cases that check boundary behavior using values that exactly fill or overflow the declared digit count, plus decimal values where rounding/truncation actually occurs. When there are multiple target types (CHAR/VARCHAR/DOUBLE), apply the same boundary values to each type repeatedly.
- **Source**: PR1683·1687 / ssihil

### [P4] For predicates containing a function, build an operator × logical-connective × sign combination matrix
- **Context**: A numbered combination TC (17+) that classifies predicates containing the abs() function as key range vs. data filter
- **Finding**: "predicate: (ta.b <= abs(tb.b) or ta.c > abs(tb.b)) key range: ((abs(tb.b)>=ta.b) or (abs(tb.b)<ta.c))", "predicate: (ta.b <= -abs(tb.b) or ta.c > abs(tb.b)) key range: NULL"
- **Pattern**: For predicates containing a function, enumerate every combination of comparison operator (>=, <=, =, <, >) × logical connective (and/or) × sign (positive/negative) with numbers, and for each combination state the expected value — whether the optimizer takes a key range or defers it to a data filter/NULL (full scan). When easily-missed combinations like or-connectives or negative abs are absent, point out that they should be filled in.
- **Source**: PR1884 / youngjinj

### [P4] List every function in a family that pairs by prefix/abbreviated form
- **Context**: Adding a new scenario to a TC for SYS_DATE-style time functions
- **Finding**: "개발팀이 SYS_DATE, SYS_DATETIME, SYS_TIME, SYS_TIMESTAMP, SYSDATE, SYSDATETIME, SYSTIME, SYSTIMESTAMP 8개 모두 추가 요청" + "실행마다 값이 달라지니 기존 bfn_datetime_sysdatetime.sql처럼 값이 안 바뀌는 형태로 8개 모두 작성"
- **Pattern**: Enumerate and add every function in a family whose names pair by prefix (SYS_) or abbreviated form, without omission; for functions that change on every run, like the current time, require a rewrite that checks only a fixed reference value and stable derived values, referencing a similar existing TC.
- **Source**: PR1961 / kiho-um·ssihil

### [P4] Test constraints not just for creation but the add→drop lifecycle, including composite keys
- **Context**: A foreign-key (FK) constraint TC
- **Finding**: "alter table b_child add constraint fk_id_name2 FOREIGN KEY(id,name) REFERENCES a_parent(id,name); alter table b_child drop constraint fk_id_name2;"
- **Pattern**: For constraint features, don't test only creation (add); attach removal (drop) to the same case to propose the full lifecycle. When only a single-column FK exists, also add a composite (two or more columns) FK case.
- **Source**: PR1844 / kwonhoil

### [P4] Pair positive cases with matching negative cases (nonexistent target, typo)
- **Context**: A privilege error-case TC
- **Finding**: "에러케이스 추가: 'show grant for 없는user명;' 에러·메시지 확인, grant/revoke 오탈자 명령 실행 에러메시지 확인"
- **Pattern**: When the TC is positive-heavy, propose symmetrically adding the matching negative cases (specifying a nonexistent target, a command typo) in a form that verifies the actual error message as well.
- **Source**: PR1901 / kwonhoil

### [P8] Attach a "check for existing duplicates first" caveat to coverage-expansion suggestions
- **Context**: A privilege re-grant (WITH GRANT OPTION) combination TC
- **Finding**: "select 권한은 재부여 가능, insert 권한은 재부여 불가일 것 같습니다. TC 추가 검토 (관련 TC가 존재하면 생략 가능)"
- **Pattern**: When proposing coverage expansion, always attach the caveat "first look for a TC that already verifies the same thing, and skip it if one exists," so that new proposals are checked for overlap with existing ones.
- **Source**: PR1944 / kwonhoil

### [category-fitness] OOM, server-down, and infinite-loop cases belong in shell, not sql
- **Context**: A string-length-limit test (in .todo state)
- **Finding**: "SQL 테스트는 DB 재시작 없이 각 질의를 수행하므로, OOM이 발생할 수 있는 이 케이스는 shell 기반 테스트에 추가하는 게 좋겠습니다."
- **Pattern**: The sql category runs queries back-to-back in the same DB process. For cases that affect the process or server — OOM, server-down, infinite loop — point out that they should move from the sql category to the shell category.
- **Source**: PR1754 / hgryoo

### [P14] Explicitly restore changed system parameters/session settings at the end
- **Context**: The wrap-up of a TC that verifies by changing an index-related system parameter
- **Finding**: "set system parameters 'deduplicate_key_level=default'; — 명시적으로 default를 추가해 다른 케이스가 default로 동작함을 보장"
- **Pattern**: If you changed a system parameter or session setting during the test, add a statement at the end of the case that explicitly restores it to default, so later TCs aren't affected — you must not skip this restore on the grounds of "minimal reproduction."
- **Source**: PR1844 / tw-kang

---

## answer-vs-spec (change-testcase-dominant lens — P7 answer justification · P11 issue intent · P12 bug/spec · P15 invariants)

### [P7] Success/failure outcome recorded backwards from the answer state
- **Context**: Across 3 files of a parameter type-conversion TC, the actual execution result and the answer's success/failure marking are opposite
- **Finding**: "It's a failure, but the answer file it was successful. Need to check." / "It's a success, but the answer file it was fail." — 3 times in one PR, switching files each time
- **Pattern**: First check that the answer's success/failure (normal result vs. error) matches the actual execution success/failure. When the same mismatch repeats across several files in one PR, suspect the answer-generation method (build version, environment) rather than an isolated problem, and require re-verification while naming the files.
- **Source**: PR1687 / ssihil

### [P7] Only .sql edited while .answer is left stale — the pair must always change together
- **Context**: A .sql case was modified but the change wasn't reflected in the paired .answer
- **Finding**: "As you modify the .sql file, the .answer must also be modified."
- **Pattern**: If the diff changes only the .sql while the .answer (/.answer_cci) stays the same, or conversely only the answer changes while the comparison literals in the .sql stay the same, one of them was left stale. Confirm that the two files must always change as a pair.
- **Source**: PR2004 / ssihil

### [P7] answer state changed but the status tag in the .sql comment is unchanged
- **Context**: The bit_length answer changed from error→normal, but the old "[er]" tag remains in the .sql comment
- **Finding**: ".answer 수정뿐 아니라 .sql 주석도 수정 필요. '[er]' 삭제 필요."
- **Pattern**: When the answer's success/failure state changes, the .sql's status comments and prefix tags ([er], -- error) must change with it. Don't look only at the answer diff — cross-check that the adjacent .sql comment doesn't contradict the new state.
- **Source**: PR1939 / tw-kang·kwonhoil

### [P7] Verify whether a rounded/truncated value is an intended conversion
- **Context**: Rounded/truncated values in the answer of a TC that passes DOUBLE/FLOAT as an INT/NUMERIC parameter
- **Finding**: "double 1234.56789가 int 1235로 반올림됐는데 문제없나요?" / "float 16777.217이 16777.21로 잘린 것 같습니다. 확인 부탁."
- **Pattern**: In type-conversion cases, when the answer value differs from the input in digit count or decimal places (rounding/truncation/precision loss), ask specifically whether it is a spec-correct conversion or merely a copy of the execution result. Don't let it pass without an explanation of "why this value."
- **Source**: PR1934 / swi0110

### [P7] A result line disappears from the answer due to NULL handling
- **Context**: In a procedure default-value TC, the answer output line for the empty-string case is missing entirely
- **Finding**: "빈 문자열이 null로 처리되어 답지에 '5: p_empty_string' 결과가 없는 것 같습니다. '5: '로 출력됐어야 맞을 것 같습니다."
- **Pattern**: When a particular case's output line has disappeared from the answer, first suspect a confusion between "there is no value" and "it was NULL-handled and therefore not printed." For empty-string/NULL boundary values, cross-check against the spec whether "no output" is correct.
- **Source**: PR2022 / swi0110

### [P11] Quote the issue's "expected behavior" and compare it against the TC
- **Context**: A TC verifying a sub-item of a privilege issue
- **Finding**: "이슈 기대 동작: DBA에게 권한 부여 시 소유자에게 부여하는 경우와 동일하게 에러 출력해야 함. 이 이슈를 진행할지 확인하거나 다른 계정으로 변경 검토해 주세요."
- **Pattern**: When judging whether a TC properly targets the issue, pull the issue body's "expected behavior" sentence verbatim and compare it side by side with what the TC verifies. If they don't match, before telling the author to fix the TC, first re-confirm whether the issue should proceed in its current form.
- **Source**: PR1944 / kwonhoil

### [P11] Check whether an error-free case is even in scope for this issue
- **Context**: The issue requires that a type mismatch at view creation "creates successfully but errors on query," yet some cases that don't error are mixed in
- **Finding**: "케이스마다 select 실행해 에러 나는지 확인 필요. 에러 안 나는 것은 본 이슈 해당 TC인지도 확인 바랍니다."
- **Pattern**: When the issue says "an error must occur under a specific condition," don't wave through error-free cases as "normal cases" — ask back whether they even fit this issue's scenario in the first place. A case outside the issue's scope may have been mixed in by mistake.
- **Source**: PR1923 / kwonhoil

### [P12] For odd behavior, ask the developer directly whether it's a bug or the spec
- **Context**: The rewritten query has the leading hint, but it isn't applied to the view table
- **Finding**: "뷰테이블에 leading 힌트 적용 안 되는 게 스펙인지 개발자 문의" → "뷰테이블도 적용돼야 하는 게 스펙. 개발자 수정중."
- **Pattern**: When behavior is odd and the reviewer can't decide whether it's a bug or the spec, don't just fix the answer to match that behavior and move on. First ask the developer "is this the spec?", and if it's a bug, keep the TC on the premise that it will be fixed and leave it as an issue.
- **Source**: PR1736 / kwonhoil·zionyun

### [P12] For cross-component criterion mismatches, go as far as filing an issue and updating the manual
- **Context**: Suspicion that PL/CSQL character(N)'s length basis (characters vs. bytes) behaves differently from SQL
- **Finding**: "sql에선 문자길이. 일관성 위해 문자길이가 맞을 듯. 기준이 다르면 관련 이슈에 꼭 작성하고 매뉴얼에도 추가돼야 함."
- **Pattern**: When the same concept's basis differs between components (SQL vs. PL/CSQL), don't just reconcile the answer on the spot and move on. Confirm whether the difference is intended, and if not, require a new issue plus a manual update. Hold the TC until a determination is made.
- **Source**: PR1997 / kwonhoil·swi0110

### [P15] Freezing a year into the answer breaks the moment the year rolls over
- **Context**: The default-parameter timestamp value omits the year, so it happens to match the execution year right now
- **Finding**: "년도가 없어 현재는 2025로 answer와 동일하지만 내년엔 2026으로 처리되며 실패. 년도 포함을 고려."
- **Pattern**: When an input value implicitly depends on the current time (year, month) and the answer is pinned to "the value at this moment," it will inevitably break over time. Require that the year be hard-coded into the value to pin it, or that the varying part be removed from the output via DATE_FORMAT or the like.
- **Source**: PR2010 / ssihil

### [P15] Ever-changing sys_date values cannot be pinned for comparison in an answer
- **Context**: A case that calls PL/CSQL sys_date-style built-in functions
- **Finding**: "sys_date 등은 테스트마다 값이 변경돼 answer와 비교 불가. bfn_datetime_sysdatetime.sql 참조해 재작성이 좋겠습니다."
- **Pattern**: When the result of a function that changes on every run (current time, random number) is exposed directly, first point out that its value can't be pinned into the answer. Require a rewrite that "checks only the format" instead of the exact value, and if an existing file has already solved the same problem, follow its approach.
- **Source**: PR1961 / ssihil

### [P15] Multi-row results without order by have no guaranteed ordering
- **Context**: An attempt to freeze the result of an order-by-less select from several CTE combinations into the answer
- **Finding**: "order by를 쓰는 이유는 답지가 안 바뀌게 하기 위함. 생략 가능한 건 count(*)·결과 1건뿐. 그 외엔 order by가 있어야 regression마다 답지가 안 흔들림."
- **Pattern**: An order-by-less multi-row select is an unguaranteed value whose order varies with the optimizer and storage layout. Unless it's a count(*) or a guaranteed single row, don't finalize an order-by-less result as the answer — require adding order by.
- **Source**: PR1767 / kwonhoil

---

## determinism-convention (shared — P2 determinism · P5 isolation · P6 convention · P10 language. Judgment-type only, what L1 static rules can't catch)

### [P2] Even with ORDER BY, ordering is nondeterministic if the sort key isn't unique
- **Context**: A db_auth query uses only `order by grantor_name`
- **Finding**: "order by가 grantor_name이라 출력 순서가 바뀔 수도. grantor_name, auth_type 순으로 처리하는 게 좋겠습니다."
- **Pattern**: Don't just look at whether ORDER BY exists — also look at whether the sort key uniquely distinguishes the results (the possibility of ties). When the leading key value is duplicated, the remaining order is still nondeterministic, so require adding a tie-breaker column.
- **Source**: PR1944 / kwonhoil

### [P2] A zero-row query needs no ORDER BY — also check whether the finding points at the wrong query
- **Context**: A query that checks package information
- **Finding**: "본 쿼리는 결과가 없습니다. 정렬 조건 추가가 불필요합니다. 수정 대상 쿼리가 잘못된 것 아닌가요?"
- **Pattern**: Don't flag every missing ORDER BY unconditionally. First confirm whether the query actually returns rows (a confirmed zero rows is an exception), and when a file has multiple queries, pin down exactly which query the finding refers to — there have been real cases of an automated suggestion attaching to the wrong query.
- **Source**: PR2036 / ssihil

### [P2] Determinism can break not only on row order but on execution-plan choice — pin CTEs with MATERIALIZE
- **Context**: Three CTE TCs aimed at reproducing SQL Trace / core dump (the same finding repeated 3 times in one PR)
- **Finding**: "INLINE CTE가 되면 초기 테스트 목적과 다른 테스트가 됩니다. `/*+ MATERIALIZE */` 힌트를 쓰는 게 좋겠습니다."
- **Pattern**: When the test's purpose depends on a specific execution plan (CTE materialization), pin the plan with a hint so the intent holds even if the optimizer later picks a different plan (inline). The point where determinism collapses may be not only "row order" but also "plan choice."
- **Source**: PR2187 / youngjinj

### [P5] A technically redundant cleanup may still be a deliberate ordering convention — confirm intent rather than forcing removal
- **Context**: A TC that explicitly DROPs an index before dropping the table
- **Finding**: ssihil "drop table 시 함께 삭제되므로 불필요" / author "한 테이블 삭제 시 순서적으로 삭제하는 게 맞다고 봄"
- **Pattern**: Don't force removal on the mere fact that "DROP TABLE also drops the index, so it's redundant." It may be a symmetric convention of cleaning up in reverse creation order — a style judgment, not right or wrong → prefer confirming intent over a firm "delete it."
- **Source**: PR1859 / ssihil·kiho-um

### [P5] You must know each runner's execution-exclusion rules to catch isolation violations
- **Context**: A SQL-category TC whose comment says "HA synchronization test"
- **Finding**: "ha_repl은 파싱 단계에서 DDL/DML이 아닌 것(AUTOCOMMIT/ROLLBACK/COMMIT/$/SHOW/CALL/SELECT)은 실행 안 함. call login에 의한 사용자 변경 포함 → ha_shell tc로 작성 필요."
- **Pattern**: When a TC spans multiple execution contexts (the SQL runner, ha_repl), a particular runner may silently skip a particular statement (CALL). Even when it's syntactically fine, differences in per-category execution rules sometimes require splitting it into another category (ha_shell).
- **Source**: PR1904 / ssihil

### [P5] A defensive DROP IF EXISTS guards against others (other TCs), not yourself
- **Context**: The pre-table-creation step of a shared-DB TC
- **Finding**: "생성 전에 drop table if exists로 다른 tc에서 삭제 안 되고 남아 있을 경우를 대비하는 게 좋습니다."
- **Pattern**: Don't view DROP-before-CREATE only as "the habit of cleaning up what I created." In a shared-DB environment its purpose is to guard even against "another TC's cleanup failure" — check whether this TC protects itself from other TCs' isolation failures.
- **Source**: PR1911 / ssihil

### [P6] Delete BUG comments for already-fixed issues — comments must reflect the state at review time
- **Context**: A %TYPE procedure return-value TC
- **Finding**: "CBRD-25557에서 수정돼 develop에 반영됨(결과 0.1). 이 주석은 지워져야 합니다."
- **Pattern**: A BUG/TODO comment reflects only the state when it was written and isn't permanently accurate. At review time, check whether the issue has landed in develop and been fixed, and if so require deleting the comment — the comment text alone isn't enough to judge; you must check external state.
- **Source**: PR1847 / hyunikn

### [P6] When expected and actual differ, that itself is a BUG — a case where the comment must not be deleted
- **Context**: A TC that passes a collection-type parameter to PLCSQL
- **Finding**: "컬렉션 타입은 PLCSQL 미지원이라 에러를 기대했으나 정상 처리됨 → BUG 주석 유지."
- **Pattern**: When the spec means "it's unsupported, so an error is the correct outcome" but it processed without an error, that mismatch is itself a regression / undocumented change. Don't read it as "no error, so it passes" — you can only judge whether to keep the BUG comment once you've reconciled the direction of expected vs. actual behavior (error expected vs. success).
- **Source**: PR1687 / kwonhoil

### [P6] Even when a trace looks unnecessary, the trace output itself may be the verification target
- **Context**: A TC that checks whether the hash-join build is skipped
- **Finding**: ssihil "trace 쓸 이유 없어 보임" / author "결과 없으면 해시 테이블 빌드 안 해야 하고, sql trace의 hash_method: skip으로 확인함"
- **Pattern**: Beyond "is the trace on/off pairing correct," look at whether the trace usage is directly tied to that TC's verification purpose. Even when it looks unrelated to the purpose, the trace output is sometimes the only means of verification, so you must not flag it merely on "looks like there's no reason for it."
- **Source**: PR1936 / ssihil·youngjinj

---

## plan-stability (shared, plan TCs — P3 fix path · P13 plan stability)

### [P3] Use evaluate, not select, for case labels — suppress unnecessary queryPlan output
- **Context**: A new TC uses a select statement for its case description (label)
- **Finding**: "select 대신 evaluate를 쓰는 건 어떤가요? select는 불필요한 queryPlan을 출력합니다."
- **Pattern**: For case labels use evaluate, not select. A select emits a queryPlan by itself, which mixes with the plan output of the real verification target (the recompile-hint select) and becomes noise. When you find a label-purpose select, require replacing it with evaluate.
- **Source**: PR1792 / youngjinj (repeated PR1849 / ssihil)

### [P3] A hint typo silently falls back to TABLE SCAN — don't overwrite the answer to match the result
- **Context**: The answer expects an INDEX SCAN but the actual plan is a TABLE SCAN
- **Finding**: "인덱스 힌트 이름에 오타가 있어 TABLE SCAN이 수행된 듯. 오타 수정 후 answer도 같이 변경 요망." (+ "FORCE로 USING INDEX를 써야 확실히 INDEX SCAN")
- **Pattern**: (1) USING INDEX only enforces reliably with FORCE; without it the optimizer picks a different path. (2) On an index-name typo, the hint is silently ignored without an error and detours to sscan. If you approve the answer to match the actual output (the typo state), a state that can never verify the fix path (index scan) hardens into the regression baseline — before approving the answer, check that the hint string matches the actual index name.
- **Source**: PR1884 / youngjinj

### [P3] View merging renames the alias and voids the hint
- **Context**: A NO_USE_HASH(ab) hint was given, but it was processed as a hash-join
- **Finding**: "뷰 머징으로 별칭 a→ab가 되어 힌트의 ab와 달라 no_use_hash(ab)가 무시됨. no_merge 힌트를 함께 써야 함."
- **Pattern**: When an inline view is merged, its internal alias changes automatically, so a hint referencing the old alias no longer matches and is silently ignored. For a TC with an alias-referencing hint, check whether view merging occurs, and to see the result with the hint applied, pin the alias with no_merge.
- **Source**: PR1936 / youngjinj (finding by ssihil)

### [P3] An ambiguous index name → USING INDEX hint is ignored
- **Context**: A plan change in an existing TC
- **Finding**: "예전엔 인덱스가 없으면 오류가 났으나 최근엔 힌트가 무시됨. 현재는 인덱스명이 모호하여 무시된 경우."
- **Pattern**: When an index name is ambiguous across multiple tables, USING INDEX is ignored without an error. Don't be reassured just because a hint is present — confirm in the actual plan that that index was chosen, and require qualifying an ambiguous name as table.index.
- **Source**: PR2381 / shparkcubrid

### [P3] Ordering already trivial from an equality condition — false-positive coverage
- **Context**: A query claimed to be aimed at verifying "order by skip"
- **Finding**: "order by skip은 인덱스로 정렬이 불필요할 때. 첫 쿼리는 order by의 upper(a)에 ='A' 등호조건이 있어 인덱스 무관하게 정렬 불필요 → order by skip 테스트로 보기 어렵다."
- **Pattern**: Even if the TC's intent is "sorting is skipped thanks to the index," when the WHERE clause already pins the order-by column with an equality condition, sorting is unnecessary regardless of the index = false-positive coverage that can't verify the fix path. First ask "does this condition hold even without the index?"
- **Source**: PR2369 / HyunukLee

### [P13] Pin the plan by adding an index plus statistics
- **Context**: In a multi-table join TC, the plan can waver because of missing indexes
- **Finding**: "create index … ; update statistics on ta,tb,tc; 플랜 고정·안정성 확보 차원에서 옵티마이저 변화에 영향받지 않게 인덱스 추가가 좋겠습니다."
- **Pattern**: When a join or scan risks wavering per run due to missing statistics or tied costs, create indexes on the relevant columns and explicitly run update statistics to pin the plan to a specific path — so it takes the same path every time rather than passing by luck.
- **Source**: PR2466 / shparkcubrid

### [P13] Trace join-order changes down to tie-cost and selectivity computation
- **Context**: The answer's join processing order changed from a,b,c,d → a,c,d,b
- **Finding**: (question) "조인순서가 변경된 이유는?" / (answer) "유니크라 NL조인은 어떤 순서든 동일 cost. 변경 전 b,c 우선은 조인조건 2건이라 선택도가 과소평가된 것(이전 1/MIN(3*3,9), 변경 1/MIN(3*3,3))"
- **Pattern**: An answer with a changed join order can't be approved on a qualitative explanation alone like "NL join is advantageous." When costs are theoretically tied, what decides the actual order is how a multi-condition index's selectivity is computed — when that computation changes, the direction in which the tie breaks also changes. Require tracing down to the selectivity/cost formula level.
- **Source**: PR2462 / kwonhoil·shparkcubrid

### [P13] A trace shaken by an unrelated change — separate minimal-diff stabilization from new coverage
- **Context**: An engine parallel-scan extension shakes the INSERT row order and NLJOIN trace of an existing regression TC
- **Finding**: "이 PR은 신규 커버리지가 아니라 기존 cbrd_24148.sql이 흔들린 것을 안정화하는 수정. 원 케이스는 CBRD-24148 회귀 목적이라 의도 유지 선에서 최소 변경만. parallel scan 회귀는 별도 케이스로 분리."
- **Pattern**: When an engine change makes an existing regression TC flaky by shaking only its byproducts (row order, trace), don't mix "new-feature coverage" and "stabilizing the existing case" in one PR. Stabilize with a minimal diff that preserves the original intent, and split coverage for the new path into a separate case.
- **Source**: PR2827 / xmilex-git

### [P13] Justify an answer update with numeric evidence proving it's "not hiding a regression"
- **Context**: Join order / scan method changed, prompting an answer update, with whether it hides a regression at issue
- **Finding**: "이 갱신은 회귀 은폐가 아니라 옵티마이저의 합리적 선택. cc는 5 rows, aa/bb는 ~512 rows. 5행 cc를 sscan으로 outer에 두고 aa로 index probe하는 건 정당한 plan."
- **Pattern**: When updating the answer because the plan changed, present "why the optimizer chose that" with row-count/cardinality numbers. An unsupported "it just changed, so I updated it" is grounds for rejection — only with numeric evidence can you distinguish hiding a regression behind an answer update from a legitimate cost-based choice.
- **Source**: PR2704 / xmilex-git

### [P13] For cost-model-wide changes, make a policy determination and document the supporting commit
- **Context**: An engine cost-model (overhead) change shifts the plans of several TCs (Q101/Q121/Q123) toward skip ORDER BY all at once
- **Finding**: "policy A로 수용. overhead=1(엔진 PR #7262)로 비커버링 인덱스 스캔이 비용 경쟁력을 얻어 skip ORDER BY가 적용되는 의도된 변경. Q101 evaluate 설명 갱신(commit 1098cec1f)."
- **Pattern**: When an engine cost-model change shifts many TCs' plans as a family, make a per-case determination of whether it's an "intended change (policy)," then update the evaluate/answer descriptions to match the new behavior and record the supporting engine commit/PR number. Documenting the policy and its basis reduces repeated investigation when the same change recurs.
- **Source**: PR2871 / shparkcubrid

---

## Sources and scale
Selected from `work/tc-review-mining/lens_*.txt` (5-year mining, gitignored). **44 entries** total (coverage-expansion 12 · answer-vs-spec 12 · determinism-convention 9 · plan-stability 11). Since this is the same data as the backtest answer key, follow the "Backtest isolation" rule above. When the mining is re-extracted, this bank is also subject to update.
