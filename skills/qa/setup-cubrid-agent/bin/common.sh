#!/bin/bash
# Shared preamble + primitives for the ~/.cubrid-agent/bin helpers. SOURCED, never run on its own.
# Hooks under scripts/ must NOT source this: they ship through the plugin, so at hook time this file
# may not exist, and a hook must not source the operator's env.
#
# Contract: the caller runs `set -u`, then sources this with $0 being the helper. Sourcing it
# immediately sources env.sh and resolves $TC.

# env.sh sources CUBRID's .cubrid.sh, which appends to LD_LIBRARY_PATH and PATH without guarding them
# — fatal under `set -u` where they are not already exported (non-interactive ssh).
# shellcheck disable=SC1090
if [ -f "$HOME/.cubrid-agent/env.sh" ]; then set +u; . "$HOME/.cubrid-agent/env.sh"; set -u; fi

TC=${CUBRID_TESTCASES:-$HOME/cubrid-testcases}

parse_issue_key() {  # <arg> -> CBRD-XXXXX (uppercased), or nothing
  printf '%s' "$1" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'
}

reject_unknown() {  # <usage> <arg> [option|argument]
  printf '%s: unknown %s: %s\n%s\n  If that is a documented flag, this installed copy is stale (the plugin updated, ~/.cubrid-agent/bin did not) — run /setup-cubrid-agent to refresh it.\n' \
    "$(basename "$0" .sh)" "${3:-option}" "$2" "$1" >&2
  exit 1
}

# A branch is checked out in exactly one working tree, so that place is where its work lives — it
# survives a forgotten $CUBRID_TESTCASES, which a path variable never does.
tc_root_for_branch() {  # <clone> <branch> -> the working tree that holds it, or nothing
  git -C "$1" worktree list --porcelain 2>/dev/null \
    | awk -v b="refs/heads/$2" '/^worktree /{p=$2} /^branch /{if ($2 == b) print p}' | head -1
}
