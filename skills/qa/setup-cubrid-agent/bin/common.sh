#!/bin/bash
# Shared preamble + primitives for the ~/.cubrid-agent/bin helpers. SOURCED, never run on its own
# (same contract as build-swap.sh; setup.sh installs it alongside the helpers).
#
# Why it is shared (DP7): these blocks were copy-pasted per helper and aged apart — the env preamble
# existed in six copies whose comments had already diverged, and its `set -u` bug was once fixed in
# five places for one cause. The hooks under scripts/ do NOT source this: they ship through the
# plugin, not through setup.sh's install into ~/.cubrid-agent/bin, so at hook time this file may not
# exist yet — and a hook must not source the operator's env.
#
# Contract: the caller runs `set -u`, then sources this with $0 being the helper. Sourcing it
# immediately sources env.sh and resolves $TC.

# env.sh sources CUBRID's .cubrid.sh, which appends to LD_LIBRARY_PATH and PATH without guarding
# them — fatal under `set -u` wherever they are not already exported. An interactive login has them
# (bashrc sourced .cubrid.sh earlier) and a non-interactive ssh does not, so this aborted the script
# on the second machine while looking fine on the first. -u is lifted for that one line only.
# shellcheck disable=SC1090
if [ -f "$HOME/.cubrid-agent/env.sh" ]; then set +u; . "$HOME/.cubrid-agent/env.sh"; set -u; fi

# The one resolution rule for the testcases clone — same as every skill states it.
TC=${CUBRID_TESTCASES:-$HOME/cubrid-testcases}

parse_issue_key() {  # <arg> -> CBRD-XXXXX (uppercased), or nothing
  printf '%s' "$1" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'
}

reject_unknown() {  # <usage> <arg> [option|argument] — print the stale-copy hint and stop
  printf '%s: unknown %s: %s\n%s\n  If that is a documented flag, this installed copy is stale (the plugin updated, ~/.cubrid-agent/bin did not) — run /setup-cubrid-agent to refresh it.\n' \
    "$(basename "$0" .sh)" "${3:-option}" "$2" "$1" >&2
  exit 1
}

# Where is this branch checked out? A branch can be checked out in exactly one working tree, so that
# place is the truth about where its work lives — it survives a forgotten $CUBRID_TESTCASES, which a
# path variable never does.
tc_root_for_branch() {  # <clone> <branch> -> the working tree that holds it, or nothing
  git -C "$1" worktree list --porcelain 2>/dev/null \
    | awk -v b="refs/heads/$2" '/^worktree /{p=$2} /^branch /{if ($2 == b) print p}' | head -1
}
