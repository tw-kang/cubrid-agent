# shell rulebook

**Read [rules/test-perspectives.md](rules/test-perspectives.md) and [rules/writing-rules.md](rules/writing-rules.md) before you write or change a TC under `shell/`.** The first says what a TC checks; the second says how to write its files. Example: for a new TC, read the *test perspectives* and the "New TC" section of the *writing rules*; for a change, read the "Changing an existing TC" section as well.

## Operational facts

Two environments run the TCs under `shell/`. The rule that a TC fits both is in [writing rules](rules/writing-rules.md#new-tc).

- *CI pod*: runs as root, keeps the TCs and databases on tmpfs, and gives 8 CPUs, a 64 MB `/dev/shm`, and a TC timeout of 1200 seconds. It runs the image `cubridci/cubridci:test_rl8.10` from Docker Hub, built from [`docker/ci/Dockerfile`](https://github.com/CUBRID/cubridci/blob/test_rl8.10/docker/ci/Dockerfile) on the `test_rl8.10` branch of `CUBRID/cubridci`, so you can write and try a TC locally in the same environment.
- *VM daily*: runs as a normal user on shared machines that several users work on.

Both skip the TCs in the *excluded list*. Only the CI pod skips `_25_unstable/`, so a TC in *quarantine* still runs in VM daily, and a TC under *exclusion* runs nowhere. How to quarantine or exclude a TC is in [writing rules](rules/writing-rules.md#changing-an-existing-tc).

CTP judges a TC only by its `.result` file: the TC fails when the file has a NOK line or is empty. CTP does not read the exit code of the TC. The form of an *abort path* is in [writing rules](rules/writing-rules.md#new-tc).

Windows tests of shell TCs have stopped: from the 11.4.6 and 11.3.6 patch releases, CUBRID ships CUBRID-For-WSL instead of a Windows build. What this means for a new TC is in [writing rules](rules/writing-rules.md#new-tc).

Opening an engine PR to develop or to a `feature/` branch makes a branch `tc/pr-<N>` in this repo, where `<N>` is the number of the engine PR, and opens a Draft TC PR from it. When the engine PR merges, the engine repo deletes its `tc/pr-<N>` branches, so the TC changes of a Draft TC PR that was closed instead of merged are lost.

## Before the PR

**Before you write the TC, read the issue and its engine PR, run the reproduction steps of the issue yourself, and state in one sentence the behavior the TC reproduces.** The SQL in an issue can differ from the real syntax. Example: the issue shows `ANALYZE TABLE t UPDATE HISTOGRAM`, which CUBRID rejects, so the TC reproduces the bug with `UPDATE STATISTICS ON t`.

**Run each TC you submit through CTP at least once and read the OK and NOK lines of its `.result` file.** Some errors show only at run time, and `bash -n` passes them. Example: `cases/cbrd_xxxxx.result` holds `cbrd_xxxxx-1 : OK` and `cbrd_xxxxx-2 : OK`, one line per *verdict*.

**Run the TC on a release build and on a debug build.** A debug build changes the output with asserts and extra logs; a release build runs faster and exposes races. Example: the PR says `release: OK 2/2, debug: OK 2/2`.

**For a bug fix, run the TC on a develop build without the engine fix and on a build with it, and write both results in the TC PR.** A TC that passes without the fix does not take the *bug path*. For a new feature, the build without the fix has no feature to test, so the TC runs only on the build with it. Example: the PR says `NOK on develop 1a2b3c4 without the fix, OK with the engine PR`.

## The PR

**Start the PR title with the issue key in brackets, and put the Jira link on the first line of the body.** The words after the key are free. A PR without an engine issue uses the `CUBRIDQA-XXXX` key of the QA work. Example: `[CBRD-XXXXX] Add a TC for backupdb on a full volume and update the answer of cbrd_yyyyy`.

**Replace the default title of the Draft TC PR that the engine repo opened for your engine PR with a title that follows the rule above, before the Draft TC PR merges.** The default title holds `Draft: TC changes for PR`, with the issue key in front only when the engine PR title has one, and the squash merge keeps the PR title as the commit title on develop. Example: `[CBRD-XXXXX] Draft: TC changes for PR CUBRID/cubrid#1234` becomes `[CBRD-XXXXX] Add a TC for backupdb on a full volume`.

**When the CI of your engine PR needs a fix of an existing TC or a new TC, commit it to the `tc/pr-<N>` branch of that engine PR.** Example: for engine PR 1234, check out `tc/pr-1234` of this repo, commit the TC there, and push the branch.

**For an engine PR to a `release/11.x` branch, open the TC PR to the same release branch of this repo yourself.** No `tc/pr-<N>` is made for such a PR ([Operational facts](#operational-facts)). Example: the backport of CBRD-xxxxx to `release/11.4` gets a TC PR from your branch to `release/11.4`.

**When your TC needs a change that reached the base branch (develop) after `tc/pr-<N>` was made, merge the base branch into `tc/pr-<N>`, without a rebase or a force-push.** The CI of the engine PR reads `tc/pr-<N>` as it is and does not merge the base branch into it. Example: `git switch tc/pr-1234 && git merge origin/develop && git push origin tc/pr-1234`.

**Whenever you merge the base branch into `tc/pr-<N>`, for any reason, merge it into the engine PR as well, without a rebase or a force-push.** A `tc/pr-<N>` that carries newer base-branch history than the engine PR fails for reasons the change does not cause. Example: after `git merge origin/develop` on `tc/pr-1234`, run the same `git merge origin/develop` on the branch of engine PR 1234 and push it.

**Put a fix of an existing TC and a new TC in separate commits, and write in each commit message why the change is needed and what it changes.** Example: one commit `Fix cbrd_xxxxx: wait for the server with wait_until, because the fixed sleep was too short on the CI pod`, and another commit `Add cbrd_yyyyy for the new option of backupdb`.

**Commit only the files the TC needs.** Run outputs stay out: `.result`, `*.log`, `*.err`, DB volumes, core files, `lob/` directories. *Answer files* and the helper files the TC uses (`.java`, `.c`, compressed data) go in. Example: before you open the PR, `git status` lists `cases/cbrd_xxxxx.result` as untracked, and you leave it out.

**Shrink a large data or archive file before you commit it, or build the data inside the script.** Example: trim a `.tar.gz` to the files the TC reads, and create a large set of DB objects with a loop in the script instead of committing them.

**Change only the files, values, and TCs that the issue needs, and undo the edits you made for a local check before the PR.** Example: a loop count cut from 1000 to 10 for a quick local run goes back to 1000.

**In the same PR, fix the sibling TCs that have the same defect.** Example: you fix a wrong `grep` in `cbrd_xxxxx_1.sh`, and `cbrd_xxxxx_2.sh` has the same line, so the PR fixes both.

**When you change an *answer file*, write in the PR which lines changed and why.** An answer file overwritten with the run output alone can keep the output of a bug. Example: the PR says `plan.answer: the cost digits changed because the engine lowered parallel_hash_join_page_threshold from 2048 to 256`.

**Fix a TC problem in the TC, and send a CTP change that the TC needs to `cubrid-testtools` as its own PR.** Many TCs depend on how a CTP function behaves, so a change in `init.sh` or the CTP conf can break them without a NOK. Example: a TC needs a new wait helper, so the helper goes to `cubrid-testtools` first, as `wait_until` did, and the TC uses it after that PR is merged.

**When your engine PR changes no TC of this repo, close the Draft TC PR of this repo for it, and run the `Check TC PRs` check of the engine PR again.** That check blocks the engine PR while the Draft TC PR is open. Example: an engine PR that adds or changes only sql TCs leaves `tc/pr-1234` of this repo unchanged, so you close its Draft TC PR here and re-run `Check TC PRs` on engine PR 1234.

**Merge a TC PR once the engine PR it tests has passed CI and meets every merge requirement but the `Check TC PRs` check, and merge that engine PR right after it.** That check passes only after the TC PR merges, and while only one of the two PRs is on the base branch, the runs of other developers fail: a TC fails without its engine fix, and an engine fix fails the TCs whose answers it changes. Example: the engine PR for CBRD-xxxxx has passed CI and has the approvals it needs, so you merge its TC PR and then the engine PR at once.
