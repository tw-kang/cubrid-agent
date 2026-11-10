---
name: review-testcase
description: "Review a cubrid-testcases SQL TC pull request as the first reviewer, to cut the human-review round-trip. Judges in 3 layers -- L1 convention lint, L2 mined domain lenses (few-shot bank), L3 local CTP execution -- and emits READY-TO-MERGE / NEEDS-WORK plus a line-comment review (Korean). Use whenever someone says \"review-testcase 돌려줘\", \"이 PR 리뷰해줘\", \"sql tc pr 심사\", \"PR NNNN 리뷰\", \"리뷰 초안 만들어줘\", even without the exact word. A targeted call (`/review-testcase PR-NNNN`) posts the review to GitHub (bot signature); a human still approves/merges; a batch call drafts only. NOT for: writing testcases (cubrid-*-tc-create), approving/merging, non-SQL categories (medium/shell/isolation), or Jira writes."
---

# review-testcase — SQL TC PR reviewer (3-layer)

Review a cubrid-testcases **SQL TC pull request** as the **first reviewer** and produce a draft review, so the human reviewer's round-trip shrinks. Works on any SQL TC PR (human- or author-testcase-authored). Verdict = READY-TO-MERGE / NEEDS-WORK + severity-tagged findings.

**Where the rules come from**: the TC rules this review judges by are the testcase repo's deployed rulebook, read from `origin/develop` of `$TC` (Before you start), never the PR's own copy. This skill holds the review side: the perspective catalog [`references/review-perspectives.md`](./references/review-perspectives.md) (how each perspective is handled, and the lens questions the rulebook does not hold) and the **few-shot bank (L2 fuel)** [`references/few-shot-bank.md`](./references/few-shot-bank.md). Run the L2 lenses in parallel (DP1); judge from the user's black-box perspective (DP2 — see L2).

## Scope

**Produces:** a 3-layer review — L1 convention lint, L2 domain lenses, L3 local CTP execution → a verdict + a GitHub review (line comments + summary, Korean) that is **posted** on a targeted invocation, **draft** on batch. A report at `$HOME/.cubrid-agent/reports/review-testcase/PR-NNNN.md`.

**Does NOT:** approve/merge, review non-SQL categories, watch PRs (webhook), or write Jira.

## Before you start

- **gh** authenticated (`gh pr view <N> --repo CUBRID/cubrid-testcases`).
- **Scout first — `~/.cubrid-agent/bin/scout.sh`, once, at the start, with no issue key** (installed by `/setup-cubrid-agent`; with a key it reads the manifest of an authoring run, `~/.cubrid-agent/CBRD-XXXXX/`, which a review does not have). It reads only: no writes, no network. **Exit 1: stop the review** — its one line says why, such as `origin/develop` of the clone lacking the rulebook, and the `git -C "$TC" fetch origin` to run. **Exit 3: continue the review.** **Skip L3 only when a `MISSING:` line names the CUBRID build or CTP** (`MISSING: CUBRID build`, `MISSING: CTP`): run L1+L2 only and mark L3 as NOT-RUN in the report (don't fake it). No other `MISSING:` line, such as the JIRA username, the fork owner, or the gh credentials, skips a layer or enters the verdict: a step that needs the missing tool reports it when it runs.
- **`$TC`** (testcases clone) = `$CUBRID_TESTCASES` if set, else `~/cubrid-testcases` — the clone the scout and the helpers resolve.
- **Rulebook — the TC rules this review judges by, read from `origin/develop` of `$TC`, never from the PR worktree.** A PR is judged by the rules of the branch it goes into. The rulebook files in the PR worktree (`~/.cubrid-agent/worktrees/pr-<N>`) are the PR's own copy, and a PR that edits them would pass itself by its own edit. Read these for L1, and give each L2 lens the commands, not their output:
  ```bash
  git -C "$TC" show origin/develop:AGENTS.md
  git -C "$TC" show origin/develop:sql/AGENTS.md
  git -C "$TC" show origin/develop:sql/rules/writing-rules.md
  git -C "$TC" show origin/develop:sql/rules/test-perspectives.md
  # to judge whether a TC belongs under medium/ instead (it needs the data of mdb), also:
  git -C "$TC" show origin/develop:medium/AGENTS.md
  git -C "$TC" show origin/develop:medium/rules/writing-rules.md
  git -C "$TC" show origin/develop:medium/rules/test-perspectives.md
  ```
  **If any of them fails, stop** and tell the user to run `git -C "$TC" fetch origin` — never judge a TC from what you remember of the rules. A finding names its rule by file and section heading, such as `sql/rules/writing-rules.md` "Cleanup".
- **Ground the issue with one command (mandatory, before the P11 judgment).** `~/.cubrid-agent/bin/ground-issue.sh <KEY> --run-dir ~/.cubrid-agent/PR-NNNN` (installed by `/setup-cubrid-agent`; if it is missing, run that once rather than grounding by hand) puts the description **and every comment** in `issue.txt`, downloads every attachment, and prints what to read: `read` (text, and extracted archive members), `view` (images — use the Read tool), `unread` **with the reason**. ⚠ The repro/scenario is often **only in a comment or an attachment**: that is where P11 (issue intent) lives, and if it lives only in an attachment the PR coverage assessment goes wrong. **Never infer an `unread` attachment's contents from its filename** (CUBRIDQA-1488). Jira wiki markup reads fine as-is.
- **An empty description is a signal this skill uses — trust it only from `issue.txt`.** Never re-read the body with `cubrid-jira search`: its markdown goes through pandoc, and an old pandoc without the `jira` reader (the RHEL 8 package is one) returns a blank body with a success exit — indistinguishable from a genuinely empty description, which would fabricate the signal. The grounding script uses the pandoc-free read.
- **Run directory — `$HOME/.cubrid-agent/PR-NNNN/` per PR, never `$HOME` or the cwd.** Conf copies, run logs and anything else this review leaves behind go there (the worktree keeps its own place, `~/.cubrid-agent/worktrees/pr-<N>`; the report keeps its path below). Create it if absent. Short-lived in-step scratch may use `mktemp -d`. **Do not invent a directory** (`~/scratchpad…`, `~/work…`) and **do not delete it on the way out** — a disputed verdict is re-checked from what the run actually ran.
- **Local CTP** for L3 — **$HOME standard** (`/setup-cubrid-agent` provisions; env via `source ~/.cubrid-agent/env.sh`): `$HOME/CUBRID` (release build), testcases clone = `$TC`, CTP = `$CTP_HOME` (else `~/CTP` → `~/cubrid-testtools/CTP`). Stock `$CTP_HOME/conf/sql.conf` already targets `${HOME}/cubrid-testcases/sql` (non-default ports). The PR checkout and that conf are **both done by the helpers in L3** — never check out the PR in the clone yourself.

## Pipeline

```
Select → Ground → L1 → L2 → L3 → Verdict → draft review + report
```

## 1. Select
PR number as arg (default: oldest open SQL TC PR). Author-agnostic.

## 2. Ground
- `gh pr diff`/`view` for the diff + body; `[CBRD-XXXXX]` → `ground-issue.sh` (see Before-you-start), then read `issue.txt` in full plus every attachment it lists — the repro may be comment-only and the intended cases attachment-only; fix merge diff in the cubrid repo; corpus search for near-duplicate TCs.
- **PR-kind classification (D5)** by diff file state: new `cbrd_XXXXX.sql/.answer` **added** = new-type; existing `.sql`/`.answer` **modified** = modified-type; a PR may be both → apply both lenses.
- **Mark which cases hit the fix code path** from the fix merge diff (feeds L2/L3, P3).

## 3. L1 — convention lint (static)
Check the PR's files against every bold rule of the rulebook you read in Before you start: `sql/rules/writing-rules.md` "New TC", and also "Changing an existing TC" for a modified-type PR; `sql/rules/test-perspectives.md` "What sql TCs cannot check"; `sql/AGENTS.md` "The PR" for its title, body and commits; and the `medium/` files for a TC that belongs there. Which perspectives human reviewers flagged most is in [`references/review-perspectives.md`](./references/review-perspectives.md) 'L1 — the perspectives humans flagged most'.
- **Do not flag `; result =` at the end of an `evaluate` label.** `sql/rules/writing-rules.md` "Header and labels" puts a case's expected result there, and forbids it only in a comment.
- **A `.queryPlan` file and the answer file agree.** Flag a TC where the presence or absence of an empty `.queryPlan` file and the plan output in its answer file do not match. When to use the file and when `--@queryplan` is `sql/rules/writing-rules.md` "Plans and traces".
- **Placement — check the tree, not just the filename.** Read the issue type, then say which tree the file should be in by `sql/rules/writing-rules.md` "Place and files". Two PRs put bug fixes in a release dir and this lens passed both because it only looked at naming form (CUBRIDQA-1486).

## 4. L2 — domain lenses (static, few-shot-driven) — DP1 parallel

Route by PR kind, **run the lenses as parallel subagents (DP1)**; each lens is fed its entries from [`references/few-shot-bank.md`](./references/few-shot-bank.md) + its question set from [`references/review-perspectives.md`](./references/review-perspectives.md) ('L2 persona lenses'):
- **new-type → coverage-expansion** (P4·P8·P9·P14). **Propose concrete `evaluate`+SQL, not just "missing"** (backtest improvement 1).
- **modified-type → answer-vs-spec** (P7·P11·P12·P15).
- **common (always) → determinism-convention** (P2·P5·P6·P10) + **plan-stability** (P3·P13) for plan/trace TCs.

**Bot division**: greptile/codex already badge P1(answer)·P3(fix path) — reference/augment, don't re-file; focus L2 on bot-weak P4·P7·P11·P13.

**DP2 (black-box)**: every lens judges what the TC asserts by `sql/rules/test-perspectives.md` "Evidence in the answer file" and "What sql TCs cannot check" (P15, and the category a check belongs to).

## 5. L3 — execution verification (dynamic)
Two helpers do the mechanics (installed by `/setup-cubrid-agent`); the judging is yours. Fill `<...>`:
- **env**: `source ~/.cubrid-agent/env.sh` (generated by setup.sh — `.cubrid.sh` + `CTP_HOME` + JDK `JAVA_HOME` + `CUBRID_JIRA_USER`).
- **worktree**: `~/.cubrid-agent/bin/prepare-tc-workspace.sh --pr <N>` prints the path to review in — it fetches the PR head, checks it out **detached** at `~/.cubrid-agent/worktrees/pr-<N>`, and on a re-run moves it to the PR's **current** head. It creates no branch, checks nothing out in the clone, and pushes nothing. **An empty result is a stop.** **Paste that path literally into the command below** — a shell variable does not survive between calls, and an empty `CUBRID_TESTCASES` falls back to the human's clone without saying so, which is the wrong-branch verification this step exists to prevent.
- **run** (once per `.sql` the PR touches): `CUBRID_TESTCASES=<that path> ~/.cubrid-agent/bin/verify-run.sh <KEY> --tc-path <path-in-the-PR> --run-dir ~/.cubrid-agent/PR-<N> --log-label <case-name> --no-manifest --runs 3` — writes the conf with `scenario=` pointing at the worktree, runs 3× in ONE CTP session, and reports the pass count plus the diff on a mismatch. `--no-manifest` because the manifest is the author's record, not this review's; `--log-label` because the second `.sql` would otherwise overwrite the first one's log and diff.

Checks:
1. **answer consistency**: run as-is → `Success` means `.answer` = real output; `Fail` → capture the diff. **CTP echoes each `evaluate` label into the result and compares it**, so a `.sql` label edit **not mirrored in `.answer`** Fails regardless of data (PR#3091 blocker) — check the diff is data, not just a stale label.
2. **determinism (single-session N-run)**: `--runs 3` is one session, and run 1 doubles as check 1. **All N `Success` = deterministic.** `.result` is overwritten each run, so **N-Success (CTP's masked compare = what regression uses) is the determinism signal, not byte-diffing 3 files**. Plan/trace TCs: plan identical across the N runs (P13 tie-flaky). **Confirm any nondeterminism L2 flagged statically** (ORDER-BY-less multi-row, tie-equal `ORDER (SIBLINGS) BY` keys, `LIMIT` cutting a tie block) here by repetition — but local N-run stability is **not** a spec guarantee; still flag the tie.
3. **path coverage** (if applicable): plan/trace shows the fix path is actually hit.
4. **runtime**: record CTP elapse (basis for over-sized-TC findings).
- **Always state the verification build AND whether it contains the fix** (mandatory Verdict input): build SHA from `cubrid_rel`, then `git -C <cubrid-src> merge-base --is-ancestor <fix-sha> <build-sha>` → ancestor = fix included. **Post-fix build failing = real defect; pre-fix build failing = false signal.** Reconcile with the issue's Fixed version.

## 6. Verdict
- **blocker** → NEEDS-WORK: execution failure, answer mismatch, nondeterminism (3-run diff), expected value contradicting issue/spec.
- **major** → NEEDS-WORK: fix path uncovered, isolation breach (shared-DB pollution / missing cleanup), real duplicate of an existing TC.
- **minor** → READY-TO-MERGE (with notes): convention/style/runtime.

## 7. Draft review + report
- **Draft GitHub review** (Korean, user-facing): line comments (file:line + finding + rationale) + summary (verdict, verification build, execution-evidence). **Posting volume: blocker/major first, minor bundled as '참고'** (backtest improvement 2 — don't spam minors).
- **Targeted invocation: the skill posts the review** (bot signature); no approve/merge. **Batch invocation: draft only** — human reviews the draft, then posts.
- **Report** to `$HOME/.cubrid-agent/reports/review-testcase/PR-NNNN.md`: per-layer results, execution log summary, verdict rationale.

## Note — backtest vs live
The few-shot bank cites source PRs; that isolation matters only for **backtesting** (don't feed a target PR's own entries). On a **live** PR there's no answer key — use the whole bank freely.
