# sql rulebook

**Read [rules/test-perspectives.md](rules/test-perspectives.md) and [rules/writing-rules.md](rules/writing-rules.md) before you write or change a TC under `sql/`.** The first says what a TC checks; the second says how to write its files. Example: for a new TC, read the *test perspectives* and the "New TC" section of the *writing rules*; for a change, read the "Changing an existing TC" section as well.

## Operational facts

Opening an engine PR to develop or to a `feature/` branch makes a branch `tc/pr-<N>` in this repo, where `<N>` is the number of the engine PR, and opens a Draft TC PR from it.

Windows tests of sql and medium TCs have stopped: from the 11.4.6 and 11.3.6 patch releases, CUBRID ships CUBRID-For-WSL instead of a Windows build. No regression compares output with a `.answer_win` file any more. What this means when you change a TC is in [writing rules](rules/writing-rules.md#changing-an-existing-tc).

`sql/_13_issues/` holds one directory per half-year, `_<yy>_<1|2>h/`, such as `_26_2h/`. A code-name directory `_<no>_<codename>/`, such as `_36_guava/`, takes its name from a Jira version of CUBRID: `_35_fig_cake/` is the version `fig-cake`. Which TC goes into which directory is in [writing rules](rules/writing-rules.md#new-tc).

A TC file `bug_bts_<NNNN>.sql` belongs to the Jira issue `CUBRIDSUS-<NNNN>`: `sql/_13_issues/_12_2h/cases/bug_bts_8664.sql` is the TC of CUBRIDSUS-8664.

## Before the PR

**Before you write a scenario, search the existing TCs for one that already checks it, and drop the scenario or turn it into a variant that they do not cover.** A scenario that another TC already checks catches no new regression and adds one more *answer file* to keep up. Example: before you add a case of `MERGE` with a `DELETE` clause, `git grep -il 'merge into' -- 'sql/*.sql'` lists the TCs to read first.

**Make the *answer file* with a build of the target branch of the TC that contains the engine change, and make the answer file of a backport with a build of its own branch.** The output differs between branches and between builds before and after the change, so an answer file copied from another build fails in the regression of the branch. Example: the 11.4 backport of a TC gets its answer file from an 11.4 build, which prints no parallel-worker lines in a trace, not a copy of the develop answer file.

**Run a new TC on a build without the engine change and on a build with it, and write both results in the TC PR.** A TC whose output is the same on both builds does not take the *bug path*. A PR that only makes an existing TC stable, with no engine change, has no build without the change to run. Example: the PR says `fails on develop 1a2b3c4 without the fix (Case 2 returns 3 rows, not 2); passes on the build of CUBRID/cubrid#NNNN`.

**Before the PR, run the directory of the TC, and the whole of `sql/` when you can, the way the regression runs it, not the TC file alone.** CTP runs the TC files of a run one after another on one database, so an object or a catalog change that one TC leaves behind breaks a TC that runs after it. Example: set `scenario` in the `[sql]` section of the CTP conf to the directory of the TC, such as `${HOME}/cubrid-testcases/sql/_36_guava/cbrd_xxxxx`, and run `ctp.sh sql -c <conf>`, not only `run cbrd_xxxxx.sql` in the interactive mode.

## The PR

**Title a TC PR `[CBRD-XXXXX] Add sql testcase for …` for a new TC or `[CBRD-XXXXX] Revise testcase for …` for a change, and start its body with the Jira link and the engine PR, then the cases and the builds you ran the TC on.** A reviewer checks the TC against the issue and the engine change, and the builds show that the TC catches the bug. A backport takes the title `[CBRD-XXXXX] Backport from develop to 11.x - <original title>`. Example: `[CBRD-XXXXX] Add sql testcase for LEFT JOIN over a derived table`, with a body that starts with `http://jira.cubrid.org/browse/CBRD-XXXXX` and `Engine PR: CUBRID/cubrid#NNNN`.

**Replace the default title of the Draft TC PR that the engine repo opened for your engine PR with a title in the form above before the TC PR merges.** The default title starts `[CBRD-XXXXX] Draft: TC changes for PR`, and the squash merge of a TC PR keeps the PR title as the commit title on develop. Example: `[CBRD-XXXXX] Draft: TC changes for PR CUBRID/cubrid#NNNN` becomes `[CBRD-XXXXX] Add sql testcase for LEFT JOIN over a derived table`.

**When the CI of your engine PR needs a fix of an existing TC or a new TC, commit it to the `tc/pr-<N>` branch of that engine PR.** Example: for engine PR 1234, check out `tc/pr-1234` of this repo, commit the TC there, and push the branch.

**Put a fix of an existing TC and a new TC in separate commits, and write in each commit message why the change is needed and what it changes.** Example: one commit `Fix cbrd_xxxxx: add ORDER BY to Case 3, because a parallel scan returns its rows in another order`, and another commit `Add cbrd_yyyyy for LEFT JOIN over a derived table`.

**Commit only the files that the TC needs, and leave out the outputs of a run such as `.result` files and `csql.err`.** CTP writes a `.result` file next to each case on every run. Example: before you open the PR, `git status` lists `cases/cbrd_xxxxx.result` as untracked, and you leave it out.

**Change only the TCs and files of one issue in a PR, and merge no whole branch, such as develop into a release branch, through a TC PR.** An unrelated change in a TC PR gets no review of its own and cannot be reverted alone. Example: a PR for CBRD-XXXXX changes `cbrd_xxxxx.sql` and its *answer file* only, and a typo fix in another TC goes in a PR of its own.

**When you change an existing *answer file*, write in the PR which lines changed and why: the engine change or issue that changed them, or why the old lines were wrong.** An answer file overwritten with the run output alone can keep the output of a bug. Example: the PR says `cbrd_xxxxx.answer: Case 3 now prints an error instead of NULL because CBRD-YYYYY made the conversion strict`.

**Merge a TC PR once the engine PR it tests passes CI and meets its other merge requirements, and merge that engine PR right after the TC PR.** The engine repo blocks the merge of an engine PR until the TC PR on its `tc/pr-<N>` is merged or closed, and a TC on develop without its engine change fails in the CI of other engine PRs until that engine PR follows. Example: CUBRID/cubrid#NNNN passes CI and meets its merge requirements, the TC PR on `tc/pr-NNNN` is merged, and CUBRID/cubrid#NNNN is merged right after it.
