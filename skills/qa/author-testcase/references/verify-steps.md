# Verify — why each step is shaped this way

Read this when a Verify step surprises you: a helper refuses something, a number looks wrong, or you are
about to hand-run a chain the skill says to run in one call. `SKILL.md` §4 carries the rules and the
commands; everything here is the reasoning behind them, kept out of the body because it is re-read on
every turn while this is needed once (CUBRIDQA-1487).

## Why the session count is the budget

Each `ctp.sh --interactive` invocation pays **~85s of setup** — JVM start, DB create, server up, then
server down and DB delete. An extra `run` **inside** a live session is **~1.5s**. So the whole of Verify
is **3 sessions, not ~6**: (S1) answer generation, (S2) confirm + determinism in one session, (S3) the CCI
cross-check, which needs its own conf. The debug check and the fail→pass contract each add a session plus
two installs, which is why both come last and run once.

Hand-running any of these chains costs far more than the CTP setup it wraps: the measured cost of the
S2 chain alone was **13 Bash round-trips**, each one a model turn.

## S1 — the empty-answer trick, and why it is two calls

`verify-run.sh --generate` seeds an empty `.answer`, runs the case once, and prints what the engine
produced. `--promote` copies that output over the answer and records `lint.answer_not_handwritten`.

- **An empty answer makes CTP report `Fail:1`, not a skip.** Nothing can match an empty file. That Fail
  is the expected outcome of generation; the real output is in `$CTP_HOME/sql/result/.../cbrd_XXXXX.result`.
- **`--generate --promote` in one call is refused.** The judgment between them — "is this the post-fix
  behaviour the issue states?" — is the entire point of generating an answer instead of writing one.
- **Promoting over a non-empty answer is refused.** Generation is for an answer that does not exist yet;
  overwriting a confirmed one destroys the thing CI compares against.
- `lint.answer_not_handwritten` is written by the step that *copies* the file, not asserted by the agent
  about its own work. An agent's claim is the weakest possible evidence for the one thing that field
  exists to rule out.

## S2 — what "deterministic" is measured as

`verify-run.sh --runs 3` runs the case three times in ONE session and writes `verify.build`,
`verify.determinism.{runs,all_pass}`, `verify.status=passed` on all-pass, `verify.result_dir`, and on a
mismatch the extracted `verify.diff`. Exit 0 = all pass, 1 = mismatch, 3 = blocked (recorded as
`blocked_*` with a note).

**N × `Success:1` is the signal, not byte-diffing three files.** `.result` is overwritten on every run,
and CTP's masked compare is what the regression suite itself uses. A nondeterministic token — a
`[Ljava...@hash`, an OID, a timestamp, a multi-row result with no `ORDER BY` — is an Author problem, not
a Verify one: feed it back.

## S3 — path coverage

A green TC on a path the fix never touches is worthless. Prove the path with `;plan detail`, a
`.queryPlan` sidecar, or `SET TRACE ON; <query>; SHOW TRACE;`, and size the data to clear the thresholds
the path needs. **Under CTP's `test_mode=yes` those thresholds are not the engine defaults** — the three
values are in `verify-sql`'s "Config can flip the path".

## CCI cross-check

`verify-run.sh --runs 1 --category sql_by_cci` swaps to `sql_by_cci.conf` and `run_cci`. When the CCI
output differs from the JDBC output, `--promote --category sql_by_cci` writes the
`answers/cbrd_XXXXX.answer_cci` **sidecar** instead of overwriting the JDBC-confirmed `.answer`: the two
drivers differ on purpose when they differ, and the default answer belongs to the default driver.

## The debug check

CI runs debug regression, so an assertion a new TC trips is found there and attributed to the TC. An
assert firing on a supported statement is usually an **engine defect the TC just exposed** — worth more
found while authoring than in someone's nightly.

- **The build TYPE is what proves the swap happened.** A debug build reports the *same version* as its
  release twin, so a version-only assertion passes on a machine that never left release — and the run
  then reports `clean` about a build nobody tested.
- `assert` has no self-service escape because "the engine asserted" is not something an author can answer
  away. A reviewer can accept it as out of this TC's scope (`review.debug_approved` + `verify.debug.note`),
  the same shape a `best_effort` fail→pass uses.
- Markers are read from **engine-owned output only** — the run's own CTP log and any server error log it
  touched. Not the captured stdout: that carries the first 20 lines of the answer diff, so a TC whose own
  output contains the word "assert" would be recorded as tripping one.

## The fail→pass contract

`failpass-run.sh --prefix-build <version|url>` installs the pre-fix build, runs the TC once (a FAIL is the
goal), restores the fixed build, runs it again (a PASS is the goal), and records `verify.fail_to_pass.*`.

- **Both build URLs are proven reachable before anything is installed.** The internal build server prunes
  old builds, so the build a fail→pass check needs is exactly the one that goes missing — and discovering
  that *after* installing the pre-fix build strands the machine on it. The public archive keeps a build
  until develop is released, which is why it is the default (`CUBRID_BUILD_BASE` overrides).
- **The restore is an EXIT trap, not a later step.** A sequence that dies in the middle would otherwise
  leave a pre-fix engine installed, after which every later verify runs against the bug and still reports
  green.
- The inner runs pass `--no-manifest`: a deliberate pre-fix failure must never become the verification the
  submit gate reads. Each run also gets its own `--log-label`, because three runs of the same category
  otherwise write one log and overwrite each other's evidence.
- `confirmed` only for FAIL→PASS. `contradicted` means the TC passes without the fix (no regression
  value — either it never reaches the fix path, or the build already contains it); `inconclusive` means the
  run proved nothing. Both leave submit blocked.
- A timing-sensitive race may legitimately not reproduce: that is `best_effort`, which needs
  `verify.fail_to_pass.note` **and** `review.failpass_approved`. Pin the server to **≥4 cores** when the
  repro needs parallelism — `system_core_count` is affinity-aware and ≤2 disables it. With no pre-fix
  build available at all, ground the pre-fix behaviour from the issue's Repro/Expected and say so.
