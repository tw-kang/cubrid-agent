---
name: shell-review
description: Review CUBRID CTP shell testcase diffs and related shell helper/config/doc changes for path conventions, lifecycle correctness, helper usage, logic correctness, portability, hang risk, and syntax errors. Use this skill whenever a PR/commit touches cubrid-testcases-private-ex/shell, CTP/shell/init_path, CTP/conf/shell*.conf, or doc/shell_guide.md, or when asked whether a shell testcase follows CTP conventions.
---

# Shell Testcase Review (CTP)

Evaluate shell testcase diffs with CTP-specific rules, then produce a structured review report.

## Skill-local reference usage

- `@references/...` and `@examples/...` mean files bundled inside this skill directory.
- Use these bundled files as quick guidance, and validate against repository files in changed diffs.

## Design intent

This skill is optimized for practical CTP shell testcase review with clear scope boundaries, false-positive control, and actionable severity-based findings.

## Important Note on CTP Code

**CTP program code is for REVIEW REFERENCE ONLY.** The skill uses CTP code (`cubrid-testtools/CTP/shell/init_path/init.sh`, helper functions, configuration patterns) to understand expected testcase behavior and validation rules. **Do NOT suggest modifications to CTP code** - only use this knowledge to evaluate testcase correctness. CTP modifications are explicitly out of scope for this skill.

## Scope

### In scope
- Changed shell testcase files under `cubrid-testcases-private-ex/shell/**/cases/*.sh`.
- Related helper/config/docs diffs only when they affect testcase behavior:
  - `cubrid-testtools/CTP/shell/init_path/*.sh` (for reference only)
  - `cubrid-testtools/CTP/conf/shell*.conf` (for reference only)
  - `cubrid-testtools/doc/shell_guide.md` (for reference only)

### Out of scope
- CTP program code modifications.
- SQL/MEDIUM/JDBC/CCI/Isolation/HA logic changes that are not part of shell testcase review.
- CI workflow design or auto-fixing code.
- Broad shell style advice not tied to CTP conventions.

## Inputs

- PR or commit diff.
- File list of changed paths.
- Optional: baseline scripts in nearby directories for pattern comparison.

## Review procedure

1. **Filter changed files**
   - Primary target: `cubrid-testcases-private-ex/shell/**/cases/*.sh`.
   - Keep non-case scripts only if they materially change testcase semantics.

2. **Classify each changed `.sh` file**
   - `test-entry`: script that sources `. $init_path/init.sh` and owns testcase lifecycle/result reporting.
   - `helper`: script invoked by another case script or used only for parsing/transformation; do not require `init test`, `write_ok`/`write_nok`, `finish`, or entry-name matching.
   - If classification is ambiguous, review as `test-entry` first and explicitly record that assumption in the report.

3. **Validate path and naming (entry scripts)**
   - Preferred pattern: `.../<test_name>/cases/<test_name>.sh`.
   - Allow nested scenario variants where immediate parent and file stem still align.
   - If file is clearly a helper, do not raise naming mismatch as a hard failure.

4. **Validate no absolute paths**
    - Entry scripts must use `$init_path` to reference CTP resources.
    - No hardcoded absolute paths like `/home/...`, `/opt/...`, `/tmp/...`.
    - Temporary files should use relative paths or `$TMPDIR`.

5. **Validate lifecycle contract (entry scripts)**
   - Must source init: `. $init_path/init.sh` (or equivalent forms like `. "$init_path/init.sh"` or `source "$init_path/init.sh"` in bash).
   - Must call `init test` before core test logic.
   - Must complete with cleanup path ending in `finish`.
   - Must record outcome using `write_ok`/`write_nok` directly or via helper flow.

6. **Validate CTP helper usage**
   - Prefer `cubrid_createdb` over raw `cubrid createdb` for compatibility.
   - For config mutation, use helper APIs (`change_db_parameter`, `change_broker_parameter`, `change_ha_parameter`) rather than ad-hoc edits.
   - If comparing outputs, ensure normalization/filtering is present for unstable content (for example timestamps, PIDs, hostnames, ports, temp paths, and version-dependent strings). `format_csql_output`, `format_query_plan`, `format_path_output`, sorting, or targeted filtering are all valid approaches.

7. **Logic correctness review**
   - Verify command flow is clear and sequential (no race conditions).
   - Check error handling: commands that may fail should have exit code checks.
   - Validate variable initialization: all variables used should be defined before use.
   - Ensure proper cleanup sequence: stop services before deleting databases, release resources in reverse order of allocation.
   - Check for resource leaks: file descriptors, temporary files, database connections.
   - Verify background processes (`&`) have corresponding `wait` calls to prevent orphans.

8. **Portability and bashism review**
   - If a changed script declares `#!/bin/sh`, flag newly introduced bash-only syntax (`[[ ]]`, `source`, arrays, `<<<`, `function name {` etc.) unless the shebang is intentionally switched to `#!/bin/bash`.
   - `#!/bin/bash` is acceptable when the script actually depends on bash features.

9. **Syntax error detection**
   - Check for missing spaces in `[ ]` tests: `[ "$var"="value" ]` should be `[ "$var" = "value" ]`.
   - Verify variable expansions are quoted when single-argument/string semantics are required (for example `rm -- "$file"`, `[ "$value" = "x" ]`). Do not enforce blanket quoting when intentional word splitting/globbing is required and safe.
   - Ensure command substitutions are quoted when used as single string/test operands.
   - Check for balanced control structures: every `if` has `fi`, every `for` has `done`, every `while` has `done`.
   - Validate here-documents have proper terminators.
   - Check for array syntax in POSIX sh scripts (not supported).
   - Verify `local` keyword is not used in `/bin/sh` scripts (not POSIX-compliant).

10. **Stability / hang risk review**
   - Flag unbounded loops (`while true`, `until` without bounded break/timeout).
   - Flag risky sleep usage (see sleep usage guidelines below).
   - Prefer `xkill` for portable/process-name termination; flag raw `kill -9` only when it is broad, unguarded, or bypasses expected cleanup/retry flow.

11. **Orphan process prevention review**
    - Flag background processes (`cmd &`) without corresponding `wait $pid` or cleanup.
    - Flag `nohup` usage that may intentionally orphan processes.
    - Ensure `coproc` usages have proper cleanup.
    - Verify process groups are properly terminated (prefer `xkill` or `pkill` with specific patterns).
    - Check for subshells with process redirection `<(cmd)` that may leave processes running.

12. **Generate structured report**
    - Use severity levels: `blocker`, `major`, `minor`, `note`.
    - Include file path, evidence snippet, and concrete fix suggestion.

## Checklist

### A) Path and naming
- [ ] Entry script is in `cases/`.
- [ ] Entry script name matches scenario naming convention.
- [ ] Helper scripts are not misclassified as entry scripts.
- [ ] No hardcoded absolute paths (use `$init_path`, relative paths, or `$TMPDIR`).

### B) Lifecycle (entry scripts)
- [ ] `init.sh` is sourced via `$init_path` (equivalent valid sourcing forms for the active shell are allowed).
- [ ] `init test` appears before main operations.
- [ ] `write_ok`/`write_nok` path exists.
- [ ] `finish` is present in terminal cleanup flow.

### C) CTP helper APIs
- [ ] `cubrid_createdb` used when creating DB.
- [ ] Parameter changes use helper functions.
- [ ] Output comparison normalizes unstable content when needed.

### D) Logic correctness
- [ ] Command flow is clear and sequential.
- [ ] Error handling exists for commands that may fail.
- [ ] Variables are initialized before use.
- [ ] Cleanup sequence is proper (stop before delete).
- [ ] No resource leaks (files, connections, temp data).
- [ ] Background processes have proper `wait` or cleanup.

### E) Syntax correctness
- [ ] Proper spacing in `[ ]` tests.
- [ ] Variable expansions are quoted when single-argument/string semantics are required.
- [ ] Command substitutions are quoted when treated as single string/test operands.
- [ ] Control structures are balanced.
- [ ] No arrays in `/bin/sh` scripts.
- [ ] No `local` in `/bin/sh` scripts.

### F) Portability and safety
- [ ] Shebang and syntax are consistent (`sh` vs `bash`).
- [ ] No unintended bashisms under `#!/bin/sh`.
- [ ] No unbounded loop / unsafe hard kill pattern.
- [ ] No orphan process risks.
- [ ] Sleep usage follows guidelines.

## Failure conditions (raise issue)

### blocker
- Missing init/lifecycle contract (`init.sh`, `init test`, `finish`) in entry script.
- No result assertion path (`write_ok`/`write_nok` or equivalent helper flow).
- Changed `#!/bin/sh` entry script introduces bash-only syntax without switching to `#!/bin/bash` or otherwise making the requirement explicit.
- Critical syntax errors (unbalanced structures, missing quotes causing safety issues).
- Orphan process risks without cleanup (`&` without `wait`, `nohup` without justification).

### major
- Raw `cubrid createdb` used where `cubrid_createdb` should be used.
- Unbounded loop or unguarded/overly broad process-kill pattern (`kill -9`, `pkill`, or grep/xargs kill pipeline).
- Naming/path mismatch for entry script that breaks scenario convention.
- Missing error handling for commands that may fail (no exit code checks).
- Resource leaks (unclosed files, unremoved temp data, unreleased database resources).
- Sleep > 10 seconds without condition-based waiting.
- Missing variable initialization causing undefined behavior.
- Hardcoded absolute paths instead of using `$init_path` or relative paths.

### minor
- Output/assertion path likely flaky due to missing normalization/filtering/sorting of volatile content.
- Non-critical portability smells or maintainability concerns.
- Sleep 3-10 seconds without justification comment.
- Quoting/style inconsistency that does not currently affect pass/fail behavior.

### note
- Sleep 0-2 seconds (acceptable but should have justification).
- Style suggestions not affecting functionality.
- Documentation comments could be improved.

## Sleep usage guidelines

| Duration | Severity | Requirement |
|----------|----------|-------------|
| 0-2 sec | Note | Acceptable for file system sync; should have brief comment |
| 3-10 sec | Minor | Must have comment explaining need |
| >10 sec | Major | Must use condition-based waiting (polling loop) |

### Good pattern: Justified short sleep

```bash
# Wait for broker to release port (typically <2s)
sleep 2
```

### Good pattern: Polling instead of sleep

```bash
# GOOD: Poll for condition instead of fixed long sleep
max_wait=30
waited=0
while [ $waited -lt $max_wait ]; do
    if cubrid broker status | grep -q "ACTIVE"; then
        break
    fi
    sleep 1
    waited=$((waited + 1))
done

if [ $waited -ge $max_wait ]; then
    write_nok "Timeout waiting for broker"
fi
```

### Bad pattern: Arbitrary long sleep

See `@examples/bad_patterns.sh` section "PATTERN 2: Unjustified Long Sleep" for examples.

## Well-written testcase examples

Complete working examples are provided in the `examples/` directory:

- `@examples/good_entry.sh` - Basic well-formed entry script with proper lifecycle
- `@examples/good_helper.sh` - Acceptable helper script (non-entry)
- `@examples/bad_patterns.sh` - Common anti-patterns with GOOD/BAD comparisons

### Quick reference

**Good entry script characteristics:**
- Proper lifecycle: `. $init_path/init.sh` → `init test` → test logic → `finish`
- Uses CTP helpers: `cubrid_createdb`, not raw `cubrid createdb`
- Error handling: checks exit codes before `write_ok`
- Cleanup: stop services before deleting databases
- Orphan prevention: `wait $pid` for background processes

**Good helper script characteristics:**
- Does NOT call `init test`
- Does NOT call `write_ok`/`write_nok`
- Does NOT call `finish`
- Caller (entry script) handles lifecycle

## False-positive policy

- Do not fail helper scripts in `cases/` with entry-script-only checks.
- Do not flag `#!/bin/bash` itself as an error unless the script claims `/bin/sh` compatibility.
- If a risky pattern is intentionally justified (commented guard, bounded retry, known test intent), downgrade severity and explain why.
- CTP helper functions (`xkill`, `cubrid_createdb`, `format_csql_output`, etc.) are preferred but their absence in legacy code is not a blocker unless the change introduces new issues.

## Output format

Use this exact structure:

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

## References

### Documentation
- `cubrid-testtools/doc/shell_guide.md` - Shell testing guide and conventions.
- `@references/shell_guide_excerpt.md` - Key points from shell guide (quick reference).
- `cubrid-testtools/CTP/AGENTS.md` - CTP-wide conventions.
- `cubrid-testtools/CTP/shell/src/AGENTS.md` - Shell orchestration context.

### CTP Helper Functions (Reference Only)
- `cubrid-testtools/CTP/shell/init_path/init.sh` - CTP helper functions and lifecycle.
- `@references/init_sh_helpers.md` - Quick reference for CTP helpers.

### Testcase Repository
- `cubrid-testcases-private-ex/shell` - Testcase repository.
- `@examples/` - Working example files:
  - `good_entry.sh` - Well-formed entry script
  - `good_helper.sh` - Acceptable helper script  
  - `bad_patterns.sh` - Anti-patterns with corrections

**Note on paths:** All paths in this skill are relative to the repository root. When reviewing, adapt to your local checkout structure. The `init_path` environment variable typically points to `cubrid-testtools/CTP/shell/init_path`.
