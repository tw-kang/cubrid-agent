---
name: cubrid-unittest-tc-runone
description: "Executes a single CUBRID unittest binary and reports pass/fail. Invoke when the user asks to run a specific unit test — Korean: unittest 돌려봐, 유닛테스트 실행, 유닛테스트 수행; English: \"run unittest\", \"execute unit test\". NOT for: creating new unit tests (use cubrid-unittest-tc-create), running full unittest regression."
---

# Unittest Runner (CTP)

Run a single CUBRID unittest binary on the local machine and report pass/fail.

## Prerequisites — CTP Installation Check (mandatory first step)

```bash
# Detect CTP_HOME: $CTP_HOME env var → $HOME/CTP → ~/cubrid-testtools/CTP (in order)
if [ -n "$CTP_HOME" ] && [ -f "$CTP_HOME/bin/ctp.sh" ]; then
    echo "CTP found: $CTP_HOME"
elif [ -f "$HOME/CTP/bin/ctp.sh" ]; then
    export CTP_HOME=$HOME/CTP
elif [ -f "$HOME/cubrid-testtools/CTP/bin/ctp.sh" ]; then
    export CTP_HOME=$HOME/cubrid-testtools/CTP
else
    echo "CTP not found"; exit 1
fi
```

If `ctp.sh` is not found, stop and display:

> "CTP is not installed. This skill cannot proceed.
> Install: `git clone https://github.com/CUBRID/cubrid-testtools.git && cp -rf cubrid-testtools/CTP ~/`
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

## JIRA Issue Context (do this when the test corresponds to a CBRD-XXXXX)

If the test path or user's request mentions a `cbrd_NNNNN` or `CBRD-NNNNN` (e.g. `cbrd_27100.sh`, `TestCbrd27100.java`), **invoke the `jira` skill first** to fetch the issue background — original symptom, expected behavior, affected components, comments — before running and diagnosing the test. This dramatically improves failure analysis: actual behavior can then be compared against the issue's stated expected behavior.

**Already fetched in this conversation?** Reuse the context — do not re-invoke. The fetcher caches issues, but the conversation should not redundantly re-display them.

1. **Normalize the ticket ID** — `jira_search.py` requires the canonical `CBRD-NNNNN` form. Filenames typically use `cbrd_NNNNN`:

   ```bash
   TICKET=$(echo "$RAW_INPUT" | grep -oiE 'cbrd[-_ ]?[0-9]+' | head -1 \
            | tr '[:lower:]' '[:upper:]' \
            | sed -E 's/^CBRD[-_ ]?/CBRD-/')
   ```

2. **Locate the `jira` skill** — search project-scope, user-scope, plugin cache, and any `CLAUDE_PLUGIN_ROOT` install path. Do **not** rely on developer-specific paths:

   ```bash
   JIRA_SCRIPT=""
   for d in \
       "$(pwd)/.claude/skills/jira" \
       "$HOME/.claude/skills/jira" \
       "$HOME/.claude/plugins/skills/jira" \
       "$HOME/skills/jira" \
       "${CLAUDE_PLUGIN_ROOT:-}/skills/jira"
   do
       [ -n "$d" ] && [ -f "$d/scripts/jira_search.py" ] && JIRA_SCRIPT="$d/scripts/jira_search.py" && break
   done
   ```

3. **If the skill is available** — prefer the slash form `/jira CBRD-XXXXX` when the harness exposes it (it honors the upstream `pandoc` prerequisite gate). Otherwise call the bundled script directly. Warn the user when `pandoc` is missing so they know the description/comments will fall back to raw Jira-wiki markup:

   ```bash
   command -v pandoc >/dev/null 2>&1 || \
       echo "WARNING: pandoc not installed — JIRA description/comments will be raw wiki markup (degraded readability)."
   python3 "$JIRA_SCRIPT" "$TICKET"
   ```

   Let the summary, description, and comments inform pass/fail interpretation and root-cause diagnosis.

4. **If the skill is missing** — **halt and ask the user**:

   > The `jira` skill is required to fetch CBRD-XXXXX context for accurate failure diagnosis, but it is not installed. May I install it from this repo (`tw-kang/skills`) now?
   > Suggested: `npx skills add tw-kang/skills -s jira -a claude-code`
   >
   > After install, re-run the discovery step above. If the script is still not found, the install path may differ on this system — please report which directory under `~/.claude/` or the plugin cache contains the new `jira/scripts/jira_search.py`.

   Wait for explicit confirmation. If the user declines, proceed without JIRA context and warn them that issue-specific details may be missing.

5. **No CBRD-XXXXX in the test path or request** — skip this section.

## Execution Steps

### 1. Locate the unittest binary

Unittest binaries are compiled from CUBRID source — they are **not** in the testcases repo.

**If CUBRID was installed from a source tarball**, the binaries are already present:

```bash
ls $CUBRID/build_release/bin/unittests_*
```

**If CUBRID was installed from a build URL** (no source), ask the user for the source tarball URL, then build:

```bash
wget <source_tarball_url>
tar xzf cubrid-*.tar.gz
export CUBRID_SRC=$HOME/cubrid-<version>
cd $CUBRID_SRC
sh build.sh -t 64 -m release -b build_release
ls build_release/bin/unittests_*
```

### 2. Identify the target binary

List available unittest binaries so the user can confirm which one to run:

```bash
ls $CUBRID/build_release/bin/unittests_*
```

Map the user's request to the correct binary name (`unittests_<module>`). If ambiguous, list the available binaries and ask.

### 3. Run the binary

```bash
timeout 600 $CUBRID/build_release/bin/unittests_<module> 2>&1 | tee /tmp/unittest_output.log
```

### 4. Judge the result

Use CTP's pass/fail logic — output text, not exit code, determines the verdict:

```bash
FAIL_COUNT=$(grep -ci 'fail\|Unit tests failed' /tmp/unittest_output.log)
OK_COUNT=$(grep -ci 'OK\|success' /tmp/unittest_output.log)
if [ "$FAIL_COUNT" -eq 0 ] && [ "$OK_COUNT" -ne 0 ]; then
    echo "PASS"
else
    echo "FAIL"
fi
```

- **PASS** = no `fail`/`Unit tests failed` AND at least one `OK`/`success` (all case-insensitive)
- **FAIL** = contains `fail`/`Unit tests failed`, OR no `OK`/`success`

### 5. Failure analysis (when FAIL)

Show the specific failing lines:

```bash
grep -i 'fail\|Unit tests failed' /tmp/unittest_output.log
```

Check for segfaults or core dumps:

```bash
ls -la core* 2>/dev/null
ls -la $CUBRID/core* 2>/dev/null
```

If a core dump exists, it indicates a crash — report it as a crash, not a simple test failure.

## Output Format

**On success:**
```
[PASS] unittests_<module>
  - Output: <key OK/success lines>
  - Summary: <what the binary tested>
```

**On failure:**
```
[FAIL] unittests_<module>
  - Failed assertions: <FAIL lines from output>
  - Crash: <yes/no — core dump found?>
  - Root cause: <diagnosis based on output>
  - Suggestion: <what to investigate>
```

## Alternative: Run via CTP

Instead of running the binary directly, you can use the CTP runner:

```bash
ctp.sh unittest -c $CTP_HOME/conf/unittest.conf
```

This runs all discovered `unittests_*` binaries under `$CUBRID/build_release/bin/`. Use this only when the user wants a full unittest regression, not a single binary.

## Common Issues

- **Binary not found**: Unittest binaries are built from source — a build URL install does not include them. Ask the user for the source tarball.
- **Segfault / core dump**: The binary crashed. Check for core files and report the crash separately from test assertion failures.
- **`fail` word in unrelated output**: Grep is case-insensitive and broad — verify the matched line is actually a test failure, not a log message containing the word "fail".
- **No `OK` in output**: The binary may have exited early (segfault, missing dependency). Check stderr and the full output log.
- **Build required**: If `build_release/bin/` directory does not exist, the source tree has not been compiled yet. Run `sh build.sh -t 64 -m release -b build_release` from the CUBRID source root.
