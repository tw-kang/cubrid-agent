# 0002 — Default new shell testcases to `#!/bin/bash`

Date: 2026-06-23
Status: accepted

Scope: the `cubrid-shell-tc-create` skill.

## Context

The skill previously told authors to "default to `#!/bin/sh`, use `#!/bin/bash` only when bash features are needed," on portability grounds. Two facts contradict that rule:

- **The corpus is majority bash.** Across 3,692 CTP shell testcases, 2,087 (56%) start with `#!/bin/bash` and 1,401 (38%) with `#!/bin/sh`. Reviewers and tooling expect bash.
- **A review on a new testcase (CBRD-26745) asked for the shebang to be changed `#!/bin/sh` → `#!/bin/bash`** — confirming the lived convention, not just the counts.

The strict-POSIX portability the old rule protected is already not honored by the corpus, so it bought little.

## Decision

New testcases use `#!/bin/bash` by default. Keep the body portable anyway — avoid gratuitous bashisms — so a test reads cleanly and doesn't depend on bash quirks without reason. `#!/bin/sh` remains acceptable for a genuinely POSIX-only test, but it is no longer the stated default. The skill's bundled examples all use `#!/bin/bash`.

## Consequences

- New tests match the majority convention, so reviewers don't ask for the change after the fact (as happened on CBRD-26745).
- Authors no longer contort awk/string handling to satisfy `sh`.
- Cost: we drop the implicit "runs under any POSIX sh" guarantee — which the corpus already didn't provide. CTP runs on bash-capable hosts, so this is theoretical.
- Revisit trigger: if CTP ever has to run where only a POSIX `sh` exists (e.g. a stripped container), reinstate `sh` for the affected suite.
