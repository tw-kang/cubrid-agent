# How the reasoning works

The skill's reasoning is **token-driven bisect**: instead of bisecting per TC
(slow, redundant for siblings sharing one root cause), it extracts the
smallest unique substring that appears only on the actual side of each TC's
diff and runs a single `git log -G '<token>' <range>`.

This works because most CUBRID test answer regressions come from a *parser
print* or *plandump format* tweak that changes a string fed into multiple
downstream surfaces (plandump output, SHA1Compute, plan cache memory
accounting). One commit, multiple symptom shapes.

## Token priority

1. `;<key>=<value>` suffixes attached to `sql hash text` lines. Examples seen
   so far: `;bind_var_cnt=N`, `;remote={...}`. These come from
   `pt_append_nulstring(parser, string, ";<key>=")` calls in
   `src/parser/parse_tree_cl.c::parser_print_tree` gated by `PT_PRINT_*`
   flags. The flag set used for SHA1 is the macro `CUSTOM_PRINT_4_SHA_COMPUTE`
   in `src/query/execute_statement.c`, so any new flag added there cascades.
2. `?<digit>="<value>"` host-variable / locale fingerprints (e.g.
   `?193="en_US"`).
3. New comma-separated KV pairs in plan / hint dump lines.
4. `sha1 = { … }` value differences. Treated as a *symptom*, not a token —
   the script never bisects sha1 directly because the byte-level digest
   doesn't appear in any commit. Instead, sha1-only failures piggyback on
   sibling failures whose upstream suffix token bisected cleanly.
5. Numeric byte-counter shifts in `QM_QUERY_*` lines. Same treatment as sha1:
   the delta isn't a stable git token.

## Why narrow git subtrees first

The first pass limits `git log -G` to `src/parser src/query src/optimizer`
because those are where the print routines, SHA1 wiring, and plan/cache
allocation live. This makes the search ~10× faster and almost always finds
the right commit. We widen to `src/` only on miss.

## Verdict triage

- Format / identifier / cache-key / hash text / sha1 / byte counter shifts →
  **answer-fix**. The change is intentional output evolution; the test answer
  files need to be regenerated.
- Crashes, wrong query results, lock/deadlock changes, performance regressions
  → **bug-report**. File JIRA, link the suspect commit.
- No suspect found via the automated bisect → **investigate**. The orchestrating
  agent must read the diff manually and apply a different bisect strategy
  (e.g., `git log -p` on suspect files).

## Worked example (CBRD-26059)

10 TCs failed in the 11.3.5 bisect window with three visible symptoms:
- 2 TCs: "sql hash text에 'bind_var_cnt'이 추가됨"
- 7 TCs: "XASL_ID 값 바뀜"
- 1 TC: "QM_QUERY_DROP_ALL_PLANS 값이 바뀜"

Token extraction:
- bug_bts_8511 / bug_bts_8662 → token `;bind_var_cnt=` (kind=suffix)
- cbrd_20149_xasl, cbrd_20510, cbrd_20149_filter, … → no suffix token (sha1)
- cbrd_20145_1 → no suffix token (byte_shift)

Single `git log -G ';bind_var_cnt='` pinpoints commit
`f1f5e9894 [CBRD-26059]`. The script then attributes the sha1 + byte_shift
groups to the same commit via the "shared hash text root" inference, marks
all rows as `verdict=answer-fix`, and writes one report.

Total reasoning cost: 3 TC executions + 1 git log invocation, not 10.
