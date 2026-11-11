---
name: create-sql
description: "Create, draft, or scaffold a new CUBRID CTP SQL testcase (.sql + .answer) from scratch — for a CBRD bug fix or feature. Use this whenever someone says \"sql tc 만들어줘\", \"sql tc 초안 작성해줘\", \"create sql tc\", \"draft sql test\", \"새 sql testcase\", \"sql 테스트케이스 작성\", or \"create draft sql tc for CBRD-XXXXX\", even if they don't say the word \"testcase\". They usually give a CBRD number, the behavior to test, and sometimes a target release dir. NOT for: running existing SQL tests, reviewing diffs/PRs, CTP configuration, or SQL scripting unrelated to CTP test creation."
---

# SQL Testcase Creator (CTP)

Generate a CUBRID CTP SQL testcase that passes review on the first try: a `.sql` file plus the `.answer` that CTP compares its output with. **The rules a TC follows are not in this skill.** They are the testcase repo's rulebook, which you read from `origin/develop` before you write (Before you start). This skill holds the steps around them: what to look up, how the `.answer` gets made, and what to hand off.

## Scope

**Produces:** the `.sql` file, any file the rulebook puts beside it in `cases/` (such as an empty `.queryPlan`), and their paths under `cases/` + `answers/`.

**Does NOT produce:** the `.answer` file (CTP generates it by running the `.sql` — see Lifecycle contract), CTP framework changes, CI config, or shell/JDBC/CCI/HA tests (route those to the matching `cubrid-*-tc-create` skill).

## Before you start

- **One call answers the three points below: `~/.cubrid-agent/bin/scout.sh [CBRD-XXXXX] --grep <repro pattern>`** (installed by `/setup-cubrid-agent`). It reports whether CTP and the build are there, which tree this issue's TC goes in and which sibling to read first, and what the corpus already covers — and when something is absent it names it and stops (exit 3) instead of letting the first CTP run find out. When `origin/develop` of `$TC` lacks the rulebook it stops with exit 1 instead: stop and tell the user to run the `git -C "$TC" fetch origin` it prints; do not fetch yourself. **The key is optional**, so a request with no CBRD number still gets the environment and the pattern search. It reads only: no writes, no network, so calling it costs nothing but the call. Run it yourself when invoked directly; under `author-testcase` you may be handed its answer instead. What it does **not** decide is the TC's path — that is the rulebook's (Directory convention below).
- **CTP must be installed.** Expect it at `$CTP_HOME`, `~/CTP`, or `~/cubrid-testtools/CTP` — the scout reports which. If absent, stop and tell the user to install it (`git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`).
- **Testcase repo.** `$TC` = `$CUBRID_TESTCASES` if set, else `~/cubrid-testcases` — never a hardcoded home path. On a machine where `~/cubrid-testcases` is a human's working tree, that variable is how a caller points this at a separate clone.
- **Rulebook — read all seven files before you write, from `origin/develop`, never from the working tree.** The clone may sit on any branch, and the rules must not change with it.
  ```bash
  git -C "$TC" show origin/develop:AGENTS.md
  git -C "$TC" show origin/develop:sql/AGENTS.md
  git -C "$TC" show origin/develop:sql/rules/writing-rules.md
  git -C "$TC" show origin/develop:sql/rules/test-perspectives.md
  git -C "$TC" show origin/develop:medium/AGENTS.md
  git -C "$TC" show origin/develop:medium/rules/writing-rules.md
  git -C "$TC" show origin/develop:medium/rules/test-perspectives.md
  ```
  **If any of them fails, stop** and tell the user to run `git -C "$TC" fetch origin` — never write the TC from what you remember of the rules. The scout stops on the same gap with exit 1. This skill names a rule by its file and section heading, such as `sql/rules/writing-rules.md` "Place and files".
- **JIRA context (optional).** If a `CBRD-XXXXX` is referenced and `author-testcase` did not hand you grounded input, ground it yourself: `~/.cubrid-agent/bin/ground-issue.sh CBRD-XXXXX` (installed by `/setup-cubrid-agent`) puts the description **and every comment** in the run directory's `issue.txt`, downloads every attachment, and prints what to read: `read` (text, and extracted archive members), `view` (images — use the Read tool), `unread` **with the reason**. Read all of it: the rulebook gives a case to every scenario of the issue, one in a comment or an attachment too (`sql/rules/test-perspectives.md` "Scenarios to cover"). **Never infer an `unread` attachment's contents from its filename** (CUBRIDQA-1488). If neither the script nor `cubrid-jira` is installed, skip — but grounding improves accuracy.
- **Search for existing coverage first.** The scout's `--grep` is that search — give it the issue's tables/queries, since a search by cbrd number cannot see the same repro under another name. It also names the sibling tests under the target tree. **Read the header of the nearest sibling TC before writing**: it usually documents the area's conventions — which hints force the plan, how the data is sized against the thresholds CTP actually runs with, what the trace is expected to show. Skipping that step is what forced a rewrite round on a parallel-heap-scan TC whose sibling had already documented all of it (CUBRIDQA-1488). What to do when a TC already checks the scenario is in `sql/AGENTS.md` "Before the PR".
- **No hardcoded paths.** If a step needs scratch space, use `work=$(mktemp -d)` and reference `$work` — never a written-out path like `/tmp/foo` or `/home/<user>/foo`, which breaks on every other machine. When author-testcase drives this skill, anything worth keeping goes in its run directory (`$HOME/.cubrid-agent/CBRD-XXXXX/`) instead.

## Directory convention

The TC's path — its tree, its half-year directory, its file names, and when to split it into files — is `sql/rules/writing-rules.md` "Place and files"; for a TC under `medium/`, `medium/rules/writing-rules.md` "New TC" and "Place and names" as well. Once the run has recorded the issue type, the lint hook checks the tree and the half-year on the write itself. **When you match against siblings, match on issue type, not on release**: matching on a version is what sent two TCs into `_36_guava/`, and both drew the same review objection (CUBRIDQA-1486).

## Lifecycle contract

The `.answer` comes from a CTP run, never from your keyboard (`sql/rules/writing-rules.md` "Answer files"). These steps make it:

1. Write the `.sql` into `cases/`.
2. **Seed an empty `answers/cbrd_XXXXX.answer` first** — CTP's interactive `run` skips any case that has no answer file (it runs nothing: `Total:1 / Success:0 / Fail:0`). With the empty answer present, run it through `verify-sql` (needs a build URL — use one given, else ask). The run diffs against the empty answer (`Fail:1`). On every run CTP writes the output to `cases/cbrd_XXXXX.result`, next to the `.sql`; only because this case failed does it also copy it into the result tree, `$CTP_HOME/sql/result/<date>/schedule_…/sql/cbrd_XXXXX.result`.
3. Promote it: copy the `.result` next to the `.sql` over the seeded answer (`answers/cbrd_XXXXX.answer`), then re-run to confirm `Success:1`.
   - **Inside the author-testcase pipeline steps 2–3 are two commands, not six**: `~/.cubrid-agent/bin/verify-run.sh CBRD-XXXXX --generate` (seed + run + print the output) → you judge it → `--promote` (copy + record the provenance). Hand-run the steps only for an ad-hoc `.sql` with no run manifest.
4. Read the `.answer` and confirm it matches intent — DDL/DML show affected row count; SELECT shows headers + rows; each statement's output is split by `===...===` lines.

No build URL / no CUBRID env? Drop an empty `.answer` and tell the user to fill it later with `verify-sql`.

## Verify before claiming done

After authoring, prove the testcase actually runs — don't just eyeball it.

1. **Run it (ground truth):** push the `.sql` through `verify-sql` with a real build, generate the `.result`, promote it to `.answer`, and confirm the answer reflects intended behavior (right error codes, right row counts).
2. **No-build fallback** (a clean, expected path): leave the `.answer` empty and hand off to the user with `verify-sql` instructions.

## Self-review checklist

Check the `.sql` against every bold rule of `sql/rules/writing-rules.md` "New TC" and of `sql/rules/test-perspectives.md` — for a TC under `medium/`, the `medium/` files as well — in the copies you read in Before you start. The lint hook checks a few of them on each write; the rest are yours.

## Examples & references

Where an example and the rulebook differ, the rulebook wins.

- `@examples/bug_fix_error_cases.sql` — error cases checked by their `Error:` codes, with `server-message` on only around the call whose `DBMS_OUTPUT` Case 1 checks.
- `@examples/bug_fix_select.sql` — basic SELECT result verification.
- `@examples/feature_query_plan.sql` — every case checks a plan, so an empty `cbrd_25975.queryPlan` sits beside it.
- Test guide: `sql_guide.md` — https://github.com/CUBRID/cubrid-testtools/blob/develop/doc/sql_guide.md (or `$CTP_HOME/../doc/sql_guide.md` if CTP is checked out locally).
