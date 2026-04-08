---
name: shell-review
description: Review CUBRID CTP shell testcase diffs for path conventions, lifecycle correctness, CTP helper usage, logic correctness, readability, portability, syntax errors, stability (loops/sleep/orphans), and unstable output handling. Use this skill whenever a PR or commit touches cubrid-testcases-private-ex/shell, CTP/shell/init_path, CTP/conf/shell*.conf, or doc/shell_guide.md. Also use when asked whether a shell testcase follows CTP conventions, or when reviewing any shell test script related to CUBRID.
---

# Shell Testcase Review (CTP)

Evaluate shell testcase diffs against CTP-specific rules and produce a structured review report.

## Quick Start

1. Classify changed scripts as `test-entry` vs `helper` — assume entry if ambiguous.
2. Run checks: lifecycle → logic/readability → syntax/portability → stability/orphans → unstable output.
3. Report findings with severity (`blocker/major/minor/note`) using the output template below.

**Key rules at a glance:**
- No absolute paths — use `$init_path`, relative paths, or `$TMPDIR`
- No `while true` or unbounded loops — always use bounded conditions
- No `sleep > 10s` without polling — use condition-based waiting
- No orphan processes — every `&` needs `wait` or cleanup
- No external query files in entry scripts — keep SQL inline
- Shebang-top summary comment required for entry scripts
- CTP helpers preferred (`cubrid_createdb`, `change_db_parameter`, `xkill`, etc.)

## Skill-local references

- `@references/...` and `@examples/...` are files bundled inside this skill directory.
- Use them as guidance; validate against actual repository files in the diff under review.

## Important: CTP Code is Reference Only

CTP program code (`cubrid-testtools/CTP/shell/init_path/init.sh`, helpers, configs) is used to understand expected testcase behavior. **Do NOT suggest modifications to CTP code** — only evaluate testcase correctness against it.

## Scope

**In scope:** Changed shell testcase files under `cubrid-testcases-private-ex/shell/**/cases/*.sh` and related helper/config/doc diffs that affect testcase behavior.

**Out of scope:** CTP program modifications, SQL/MEDIUM/JDBC/CCI/HA logic changes outside shell tests, CI workflow design, broad shell style advice not tied to CTP.

## Review Procedure

### 1. Filter and classify

- Target: `cubrid-testcases-private-ex/shell/**/cases/*.sh`
- **test-entry**: sources `. $init_path/init.sh` and owns lifecycle (init test → write_ok/write_nok → finish)
- **helper**: invoked by another script, does NOT own lifecycle. Do not require `init test`, `write_ok`/`write_nok`, or `finish` from helpers.
- If ambiguous, review as entry and note the assumption.

### 2. Path, naming, and absolute paths

- Entry script path pattern: `.../<test_name>/cases/<test_name>.sh`
- No hardcoded absolute paths (`/home/...`, `/opt/...`, `/tmp/...`). Use `$init_path`, relative paths, or `$TMPDIR`.
- Helpers are exempt from naming-match checks.

### 3. Lifecycle contract (entry scripts only)

- Must source init: `. $init_path/init.sh` (equivalent forms allowed)
- Must call `init test` before core logic
- Must record outcome via `write_ok`/`write_nok`
- Must end with cleanup path reaching `finish`

### 4. CTP helpers and logic correctness

**CTP helpers:**
- Prefer `cubrid_createdb` over raw `cubrid createdb`
- Use `change_db_parameter`, `change_broker_parameter`, `change_ha_parameter` for config changes
- Normalize unstable output with `format_csql_output`, `format_query_plan`, `format_path_output`, sorting, or filtering

**Logic correctness:**
- Command flow must be clear and sequential (no race conditions)
- Commands that may fail must have exit code checks
- Variables must be initialized before use
- Cleanup: stop services before deleting databases, release resources in reverse order
- Check for resource leaks: temp files, file descriptors, database connections
- Background processes (`&`) must have corresponding `wait` or cleanup

### 5. Readability and structure (entry scripts)

- **Shebang-top summary required:** immediately after `#!/bin/sh`, add a comment block with issue ID/context and testcase purpose. This is essential for human reviewers to understand intent without reading the entire script.
- **Inline SQL required:** when query steps are needed for testcase understanding, keep them in the `.sh` file (heredoc / inline csql) instead of splitting into separate query files. Reviewers should not need to cross-reference external files to follow the test logic.
- **Function extraction:** if the same multi-step sequence repeats, extract it into a function. Duplicated blocks increase review risk and maintenance burden.
- Logic flow must be readable to a human reviewer without reconstructing hidden steps.

### 6. Syntax and portability

- If shebang is `#!/bin/sh`, flag bash-only syntax (`[[ ]]`, `source`, arrays, `<<<`, `function name {`, etc.)
- `#!/bin/bash` is fine when bash features are actually needed
- Check: spacing in `[ ]` tests, quoted variables for string semantics, balanced control structures, valid here-documents
- No `local` keyword or arrays in `/bin/sh` scripts

### 7. Stability: loops, sleep, and orphan processes

**Loops — no unbounded loops allowed:**
- `while true`, `while :`, `until false` without any exit mechanism → **blocker**.
- `while true` with bounded break/timeout counter inside → **major** (refactor to bounded condition like `while [ $count -lt $max ]`).
- Preferred: always use bounded loop conditions directly.

**Sleep guidelines:**

| Duration | Severity | Requirement |
|----------|----------|-------------|
| 0-2 sec | note | Acceptable; add brief comment |
| 3-10 sec | minor | Must have comment explaining need |
| >10 sec | major | Must use condition-based waiting (polling) |

**Orphan processes:**
- `cmd &` without `wait $pid` or cleanup → blocker
- `nohup` without justification → flag
- Prefer `xkill` over raw `kill -9` for process termination
- Verify process groups are properly cleaned up

### 8. Generate report

Use severity levels: `blocker`, `major`, `minor`, `note`. Include file path, evidence snippet, and concrete fix suggestion. Reference checklist sections where relevant.

## Failure Conditions

### blocker
- Missing lifecycle contract (init.sh, init test, finish) in entry script
- No result assertion path (write_ok/write_nok)
- `while true` / `while :` / unbounded loop without any exit mechanism
- Orphan process risks (`&` without `wait`, `nohup` without justification)
- Changed `#!/bin/sh` script introduces bash-only syntax without switching shebang
- Critical syntax errors (unbalanced structures, missing quotes causing safety issues)
- Query logic split into external files when it should be inline in entry script

### major
- `while true` / `while :` with bounded break/timeout counter (refactor to bounded condition)
- Raw `cubrid createdb` instead of `cubrid_createdb`
- Hardcoded absolute paths
- Sleep > 10 seconds without condition-based waiting
- Unguarded broad process-kill pattern (`kill -9`, `pkill` pipeline)
- Entry script naming/path mismatch
- Missing error handling for commands that may fail
- Missing shebang-top summary comment (issue context + testcase purpose)
- Repeated multi-step sequences not extracted into functions
- Missing variable initialization causing undefined behavior

### minor
- Flaky output from missing normalization/filtering of volatile content (PID, timestamp, hostname, port, temp paths, version strings)
- Non-critical portability concerns
- Sleep 3-10 seconds without justification
- Quoting inconsistency not currently affecting behavior
- Readability issue where intent/flow is unclear

### note
- Sleep 0-2 seconds (acceptable with comment)
- Style suggestions not affecting functionality
- Documentation improvements

## False-Positive Policy

- Do not fail helper scripts with entry-script-only checks (lifecycle, naming).
- Do not flag `#!/bin/bash` as error unless the script claims `/bin/sh` compatibility.
- If a risky pattern is intentionally justified (commented guard, known test intent), downgrade severity.
- CTP helpers are preferred but their absence in legacy code is not a blocker unless the change introduces new issues.

## Output Format

```markdown
# Shell Testcase Review Report

## Summary
- Reviewed files: <N>
- Findings: <blocker=X, major=Y, minor=Z, note=W>

## Findings
### [SEVERITY] <short title>
- File: `<path>`
- Evidence: `<code or pattern>`
- Why it matters: <impact>
- Suggested fix: <concrete action>

## Passed checks
- <key checks that passed>

## Risk notes
- <flakiness/hang/portability notes if any>
```

## Well-Written Testcase Examples

See `@examples/` directory for working examples:
- `@examples/good_entry.sh` — proper lifecycle, CTP helpers, error handling, cleanup ordering
- `@examples/good_helper.sh` — helper pattern: no lifecycle ownership, exit codes for caller
- `@examples/bad_patterns.sh` — anti-patterns with GOOD/BAD comparisons

## References

- `cubrid-testtools/doc/shell_guide.md` — Shell testing conventions
- `@references/shell_guide_excerpt.md` — Quick reference from shell guide
- `@references/init_sh_helpers.md` — CTP helper functions reference
- `cubrid-testtools/CTP/shell/init_path/init.sh` — CTP helpers (reference only)
- `cubrid-testcases-private-ex/shell` — Testcase repository

**Note:** All paths are relative to repository root. `init_path` typically points to `cubrid-testtools/CTP/shell/init_path`.
