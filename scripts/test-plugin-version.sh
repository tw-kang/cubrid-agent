#!/bin/bash
# Behavioural test for the released version — the number a teammate's update check compares.
#
# Dev-only, run by check-invariants.sh. Offline: reads the manifests and CHANGELOG in place.
#
# What it pins: the declared version and the newest dated CHANGELOG release never drift apart.
# It does NOT check that a shipped change bumped the version — what earns a bump is undecided.
set -u

ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
MANIFEST="$ROOT/.claude-plugin/plugin.json"
CHANGELOG="$ROOT/CHANGELOG.md"
[ -f "$MANIFEST" ] || { echo "test-plugin-version: no manifest at $MANIFEST" >&2; exit 1; }
[ -f "$CHANGELOG" ] || { echo "test-plugin-version: no changelog at $CHANGELOG" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-plugin-version: jq is required." >&2; exit 1; }

T_PASS=0; T_FAIL=0; FAILURES=""
note_fail() { T_FAIL=$((T_FAIL+1)); FAILURES="$FAILURES
    $1"; }

VERSION=$(jq -r '.version // empty' "$MANIFEST")
if [ -n "$VERSION" ]; then T_PASS=$((T_PASS+1))
else note_fail "plugin.json declares no version — the fleet would resolve to a commit SHA again"; fi

if [[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then T_PASS=$((T_PASS+1))
else note_fail "version \"$VERSION\" is not semver X.Y.Z"; fi

# The newest release heading, skipping an Unreleased section that carries no version to compare.
LATEST=$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' "$CHANGELOG" | head -1)
if [ -n "$VERSION" ] && [ "$LATEST" = "$VERSION" ]; then T_PASS=$((T_PASS+1))
else note_fail "plugin.json says $VERSION but the newest CHANGELOG release is ${LATEST:-none}"; fi

# A released heading without a date reads as still-open, which is how a version ships twice.
_v=${VERSION//./\\.}
if grep -q "^## \[$_v\] - [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$" "$CHANGELOG"; then
  T_PASS=$((T_PASS+1))
else
  note_fail "CHANGELOG heading for $VERSION carries no ISO date"
fi

if [ "$T_FAIL" -eq 0 ]; then
  printf 'plugin-version: %d/%d\n' "$T_PASS" "$T_PASS"
  exit 0
else
  printf 'plugin-version: %d passed, %d FAILED%s\n' "$T_PASS" "$T_FAIL" "$FAILURES"
  exit 1
fi
