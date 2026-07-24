---
name: review-testcase
description: "Review a cubrid-testcases SQL TC pull request as the first reviewer, to cut the human-review round-trip. Judges in 3 layers -- L1 convention lint, L2 mined domain lenses (few-shot bank), L3 local CTP execution -- and emits READY-TO-MERGE / NEEDS-WORK plus a draft line-comment review (Korean). Use whenever someone says \"review-testcase 돌려줘\", \"이 PR 리뷰해줘\", \"sql tc pr 심사\", \"PR NNNN 리뷰\", \"리뷰 초안 만들어줘\", even without the exact word. Draft only -- a human posts and approves/merges. NOT for: writing testcases (cubrid-*-tc-create), approving/merging, non-SQL categories (medium/shell/isolation), or Jira writes."
---

# review-testcase — SQL TC PR reviewer (3-layer)

Review a cubrid-testcases **SQL TC pull request** as the **first reviewer** and produce a draft review, so the human reviewer's round-trip shrinks. Works on any SQL TC PR (human- or author-testcase-authored). Verdict = READY-TO-MERGE / NEEDS-WORK + severity-tagged findings.

**Self-contained**: perspective catalog [`references/review-perspectives.md`](./references/review-perspectives.md) + **few-shot bank (L2 fuel)** [`references/few-shot-bank.md`](./references/few-shot-bank.md) live inside this skill. Run the L2 lenses in parallel (DP1); judge from the user's black-box perspective (DP2 — see L2).

## Scope

**Produces:** a 3-layer review — L1 convention lint, L2 domain lenses, L3 local CTP execution → a verdict + a **draft** GitHub review (line comments + summary, Korean). A report at `$HOME/.cubrid-agent/reports/review-testcase/PR-NNNN.md`.

**Does NOT:** post to GitHub (draft only), approve/merge, review non-SQL categories, watch PRs (webhook), or write Jira.

## Before you start

- **gh** authenticated (`gh pr view <N> --repo CUBRID/cubrid-testcases`).
- **cubrid-jira** for the issue body — `cubrid-jira search <KEY>` (full markdown) **and `cubrid-jira comment-list <KEY> --output json`** (there is no `show`/`get`). ⚠ Repro/scenario is often **only in comments** (empty description) — read them; that's where P11 (issue intent) lives.
- **Download + read every attachment (mandatory, before the P11 judgment).** If the intended scenario or the repro lives only in attachments, the PR coverage assessment goes wrong. `cubrid-jira attachment <KEY>` (if that subcommand isn't available yet, interim: for each `.content` URL from `cubrid-jira jql 'key=<KEY>' --fields attachment --output json`, `curl --netrc -o <file>` — credentials via `.netrc` (jira.cubrid.org) or `-u $CUBRID_JIRA_USER:$CUBRID_JIRA_PASSWORD`). **Check `.size` before downloading — skip curl for anything >5MB (cores/binaries included)** and record only the metadata + reason. Download only the rest; read text/code closely and open images with Read (multimodal).
- **Local CTP** for L3 — **$HOME standard** (`./setup.sh` provisions; env via `source ~/.cubrid-agent/env.sh`): `$HOME/CUBRID` (release build), testcases clone = `$CUBRID_TESTCASES` if set else `~/cubrid-testcases`, CTP = `$CTP_HOME` (else `~/CTP` → `~/cubrid-testtools/CTP`). Stock `$CTP_HOME/conf/sql.conf` already targets `${HOME}/cubrid-testcases/sql` (non-default ports). Check out the PR branch as a **git worktree** (don't pollute the clone) and **copy the stock conf with `scenario=` overridden to the worktree** — as-is it verifies the wrong branch.
- No local build / no CTP env? Run L1+L2 only and mark L3 as NOT-RUN in the report (don't fake it).

## Pipeline

```
Select → Ground → L1 → L2 → L3 → Verdict → draft review + report
```

## 1. Select
PR number as arg (default: oldest open SQL TC PR). Author-agnostic.

## 2. Ground
- `gh pr diff`/`view` for the diff + body; `[CBRD-XXXXX]` → issue body via `cubrid-jira search <KEY>` **+ `comment-list <KEY> --output json`** (repro may be comment-only) **+ download & read all attachments** (per Before-you-start — intended cases/repro may be attachment-only); fix merge diff in the cubrid repo; corpus search for near-duplicate TCs.
- **PR-kind classification (D5)** by diff file state: new `cbrd_XXXXX.sql/.answer` **added** = new-type; existing `.sql`/`.answer` **modified** = modified-type; a PR may be both → apply both lenses.
- **Mark which cases hit the fix code path** from the fix merge diff (feeds L2/L3, P3).

## 3. L1 — convention lint (static)
Reuse the `create-sql` checklist + mining-promoted auto-lint (details in [`references/review-perspectives.md`](./references/review-perspectives.md) 'Automatic lint rules to promote to L1'):
- header block (≤200 chars, English), `evaluate 'Case N'` numbering, DROP-before-CREATE, cleanup (`deallocate prepare`, restore SET), path/naming, English comments, no expected value leaking into comments/SQL.
- **auto-lint**: multi-row SELECT missing `ORDER BY` (only when a real tie is possible — a unique key or `COUNT(*)`/1-row is exempt), `set trace on`↔`off` imbalance, empty `.queryPlan` vs answer plan output, `evaluate` label missing, `prepare` without `deallocate`.

## 4. L2 — domain lenses (static, few-shot-driven) — DP1 parallel

Route by PR kind, **run the lenses as parallel subagents (DP1)**; each lens is fed its entries from [`references/few-shot-bank.md`](./references/few-shot-bank.md) + its question set from [`references/review-perspectives.md`](./references/review-perspectives.md) ('L2 persona lenses'):
- **new-type → coverage-expansion** (P4·P8·P9·P14): positive↔negative symmetry, boundary 3-points, combination matrix, sibling concepts, minimality. **Propose concrete `evaluate`+SQL, not just "missing"** (backtest improvement 1).
- **modified-type → answer-vs-spec** (P7·P11·P12·P15): why did the answer change / was the old one right? execution vs answer consistency? issue-intent match? spec-vs-bug (escalate)? **dead-assertion** (.answer flipped but .sql literal left, e.g. ok→nok) and **.answer_cci pair** updated? (backtest improvements 6·7).
- **common (always) → determinism-convention** (P2·P5·P6·P10) + **plan-stability** (P3·P13) for plan/trace TCs.

**Bot division**: greptile/codex already badge P1(answer)·P3(fix path) — reference/augment, don't re-file; focus L2 on bot-weak P4·P7·P11·P13.

**DP2 (black-box)**: every lens checks that the TC verifies **DBA / DB engineer / AP-developer-observable behavior** (SQL I/O via the sql-category driver — JDBC, or CCI in sql_by_cci; csql shows the same — plan, catalog, driver output) and **flags dependence on C internals** a user can't observe (asserts, code paths, physical values like page id/offset — ties to P15). AP-developer/field angle → value non-expert misuse & edge cases (coverage-expansion negative/boundary).

## 5. L3 — execution verification (dynamic)
Check out the PR as a worktree and run CTP. Concrete steps (fill `<...>`; `$TC` = testcases clone per Before-you-start):
- **env**: `source ~/.cubrid-agent/env.sh` (generated by setup.sh — `.cubrid.sh` + `CTP_HOME` + JDK `JAVA_HOME`).
- **worktree**: `git -C $TC fetch origin pull/<N>/head:pr-<N>` → `git -C $TC worktree add ~/.cubrid-agent/worktrees/pr-<N> pr-<N>`.
- **conf**: copy `$CTP_HOME/conf/sql.conf` → `~/.cubrid-agent/sql.pr<N>.conf`, set `scenario=` to the worktree's `sql/` (else you verify the wrong branch).
- **run**: `printf "run <case-dir>\nquit\n" | $CTP_HOME/bin/ctp.sh sql -c ~/.cubrid-agent/sql.pr<N>.conf --interactive`.

Checks:
1. **answer consistency**: run as-is → `Success` means `.answer` = real output; `Fail` → capture the diff. **CTP echoes each `evaluate` label into the result and compares it**, so a `.sql` label edit **not mirrored in `.answer`** Fails regardless of data (PR#3091 blocker) — check the diff is data, not just a stale label.
2. **determinism (single-session N-run)**: run the case **N (=3) times in ONE `ctp.sh --interactive` session** — `printf 'run <case-dir>\n'` repeated N times then `quit`. This same session also serves check 1 (run 1 = answer consistency). **All N `Success` = deterministic.** Each `ctp.sh` invocation pays ~85s setup (JVM + DB + server); an extra in-session `run` is ~1.5s, so **N=3 ≈ N=1 in wall time — never spawn N separate invocations** (~3×85s wasted). `.result` is overwritten each run, so **N-Success (CTP's masked compare = what regression uses) is the determinism signal, not byte-diffing 3 files**. Plan/trace TCs: plan identical across the N runs (P13 tie-flaky). **Confirm any nondeterminism L2 flagged statically** (ORDER-BY-less multi-row, tie-equal `ORDER (SIBLINGS) BY` keys, `LIMIT` cutting a tie block) here by repetition — but local N-run stability is **not** a spec guarantee; still flag the tie.
3. **path coverage** (if applicable): plan/trace shows the fix path is actually hit.
4. **runtime**: record CTP elapse (basis for over-sized-TC findings).
- **Always state the verification build AND whether it contains the fix** (mandatory Verdict input): build SHA from `cubrid_rel`, then `git -C <cubrid-src> merge-base --is-ancestor <fix-sha> <build-sha>` → ancestor = fix included. **Post-fix build failing = real defect; pre-fix build failing = false signal.** Reconcile with the issue's Fixed version.

## 6. Verdict
- **blocker** → NEEDS-WORK: execution failure, answer mismatch, nondeterminism (3-run diff), expected value contradicting issue/spec.
- **major** → NEEDS-WORK: fix path uncovered, isolation breach (shared-DB pollution / missing cleanup), real duplicate of an existing TC.
- **minor** → READY-TO-MERGE (with notes): convention/style/runtime.

## 7. Draft review + report
- **Draft GitHub review** (Korean, user-facing): line comments (file:line + finding + rationale) + summary (verdict, verification build, execution-evidence). **Posting volume: blocker/major first, minor bundled as '참고'** (backtest improvement 2 — don't spam minors).
- **PoC: human reviews the draft, then posts.** No auto-post, no approve/merge.
- **Report** to `$HOME/.cubrid-agent/reports/review-testcase/PR-NNNN.md`: per-layer results, execution log summary, verdict rationale.

## Staging
- **PoC (now)**: draft only; human posts. L2 lenses parallel, L3 local CTP.
- **Later**: auto-post (staged), PR opened/updated trigger (webhook/CI), non-SQL categories, quorum-contributing auto-approve (Stage 3).

## Note — backtest vs live
The few-shot bank cites source PRs; that isolation matters only for **backtesting** (don't feed a target PR's own entries). On a **live** PR there's no answer key — use the whole bank freely.
