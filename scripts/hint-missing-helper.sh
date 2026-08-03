#!/bin/bash
# Missing-helper hint — when a command invokes a ~/.cubrid-agent/bin helper that is not installed,
# say which one and why. Event: PreToolUse / Bash.
#
# The helpers already answer "this installed copy is stale" when handed a flag they do not know, but
# printing that needs the helper to run. A helper that a plugin update ADDED is simply absent, so the
# only thing printed is bash's errno — same cause, no hint, and the reader goes looking for a bug in
# the skill instead of re-running setup. This supplies the reason bash cannot give, and prescribes the
# same fix those helpers do.
set -u

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$COMMAND" ] || exit 0
case "$COMMAND" in *.cubrid-agent/bin/*) ;; *) exit 0 ;; esac

# A hint, never a gate. A missing file already stops itself, so there is nothing to block — and a deny
# would take the rest of the command with it (`cd $TC && git add … && …/render-report.sh KEY` would
# lose the add). Gates here are for irreversible outbound acts (the submit gate); this is not one.
# Being non-blocking is also what makes the crude parse below affordable: it has no notion of quoting,
# so a helper path quoted inside a commit message reads as an invocation, and the cost of that is one
# unnecessary sentence rather than refused work.
hint() {
  jq -n --arg c "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
  exit 0
}

# Only a path in COMMAND POSITION is an invocation. `install`, `cp`, `ls` and `diff` name the same path
# as an ARGUMENT, where its absence is normal — and `install` is the very recovery this hint asks for.
set -f   # the split below must not glob: the parse would otherwise depend on the caller's cwd
while IFS= read -r seg; do
  # shellcheck disable=SC2086  -- word splitting is the parse here
  set -- $seg
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*)         shift ;;   # VAR=value prefix
      bash|sh|env) shift ;;
      *)           break ;;
    esac
  done
  [ $# -gt 0 ] || continue
  case "$1" in *.cubrid-agent/bin/*) ;; *) continue ;; esac

  hp=$1
  hp=${hp//\"/}; hp=${hp//\'/}
  hp=${hp/#\~/$HOME}
  hp=${hp//\$\{HOME\}/$HOME}
  hp=${hp//\$HOME/$HOME}
  [ -e "$hp" ] && continue

  name=${hp##*/}
  have=$(ls "$HOME/.cubrid-agent/bin" 2>/dev/null | tr '\n' ' ')
  # Only claim a cause that was checked. Without the plugin root — the npx skills channel, or a session
  # with the plugin uninstalled — a stale copy and a misspelled name look identical from here, and
  # asserting the wrong one sends the reader to re-run setup for a helper nobody ships.
  if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    hint "cubrid-agent: $name is not installed at ~/.cubrid-agent/bin/, so this command will fail. Either this machine's helper copies predate the current plugin — run /setup-cubrid-agent to refresh them — or the name is wrong; the plugin is not visible from this session, so this cannot tell which. Installed here: ${have:-(none)}"
  elif [ -e "$CLAUDE_PLUGIN_ROOT/skills/qa/setup-cubrid-agent/bin/$name" ]; then
    hint "cubrid-agent: $name is not installed at ~/.cubrid-agent/bin/, so this command will fail. The plugin ships it, so this machine's helper copies predate the current plugin — run /setup-cubrid-agent to refresh them. Installed here: ${have:-(none)}"
  else
    hint "cubrid-agent: the plugin does not ship a helper named '$name', so no install will produce it and this command will fail — check the spelling. Installed here: ${have:-(none)}"
  fi
done <<EOF
$(printf '%s' "$COMMAND" | tr ';&|()\n' '\n\n\n\n\n\n')
EOF
exit 0
