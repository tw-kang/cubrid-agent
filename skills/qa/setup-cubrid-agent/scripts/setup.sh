#!/bin/bash
# cubrid-agent setup — provisions the machine state into the $HOME standard layout.
# This is the canonical script of the setup-cubrid-agent skill (entrypoint: /setup-cubrid-agent).
# CWD-independent, so it works from anywhere and a container image can RUN this path as-is. Decision: ADR 0003.
# Model & decisions: docs/deployment.md (3 tiers, $HOME runtime standard), ADR 0001 (component-skill absorption / plugin repackaging).
# Idempotent & non-interactive — safe to re-run; never touches an existing clone (creates only when absent).
# With --install-clis it also installs the three CLIs the skills require (gh, pandoc, cubrid-jira); without the
# flag they are only checked and reported. The flag exists so the operator's consent is collected once, in the
# skill, while this script stays non-interactive — a container RUNs it and CI executes it unattended.
# Does NOT: inject credentials, ever (Tier 3 — a human's job); install a CUBRID build unless given --build.
set -u

AGENT_DIR="$HOME/.cubrid-agent"
BUILD_URL=""
INSTALL_CLIS=0

TODOS=0
ok()   { printf '  OK   %s\n' "$1"; }
todo() { printf '  TODO %s\n' "$1"; TODOS=$((TODOS+1)); }
step() { printf '  ..   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; exit 1; }

USAGE="usage: setup.sh [--build <build-url>] [--install-clis]"
while [ $# -gt 0 ]; do
  case "$1" in
    --build)        BUILD_URL="${2:?$USAGE}"; shift 2 ;;
    --install-clis) INSTALL_CLIS=1; shift ;;
    *)              fail "unknown argument: $1 ($USAGE)" ;;
  esac
done

# Everything installed without sudo lands in ~/.local/bin. Make sure THIS run can see a binary it
# just installed, and remember whether the operator's own shell can — the checks below resolve by PATH,
# so a missing entry would make a successful install look like a failed one on the next login.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) LOCAL_BIN_ON_PATH=1 ;;
  *) LOCAL_BIN_ON_PATH=0; PATH="$HOME/.local/bin:$PATH" ;;
esac

echo "== Required tools =="
for c in git jq grep; do command -v "$c" >/dev/null || fail "$c not found (required)"; done
ok "git / jq / grep"

echo "== Component skills — bundled in this repo (plugin) (ADR 0001) =="
ok "skills live under skills/qa/ — Claude Code: 'claude plugin install'; other CLIs: 'npx skills add' (see README). No clone+symlink needed."

echo "== Plugin auto-update — so an install stays current =="
# Claude Code auto-updates marketplaces and their installed plugins shortly after a session starts,
# but third-party marketplaces have that OFF by default: without this flag a teammate keeps running
# whatever commit they first installed, and `claude plugin marketplace update` does NOT change the
# installed copy (it only refreshes the catalog). The flag cannot be declared marketplace-side, so
# enable it here, idempotently. Note that plugin.json deliberately omits `version` — that makes the
# git commit SHA the version, so every commit is a new version for the updater to pick up.
CC_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$CC_SETTINGS" ] && jq -e '.extraKnownMarketplaces["cubrid-agent"]' "$CC_SETTINGS" >/dev/null 2>&1; then
  if [ "$(jq -r '.extraKnownMarketplaces["cubrid-agent"].autoUpdate // false' "$CC_SETTINGS")" = true ]; then
    ok "plugin auto-update already enabled"
  else
    _tmp=$(mktemp)
    if jq '.extraKnownMarketplaces["cubrid-agent"].autoUpdate = true' "$CC_SETTINGS" > "$_tmp" 2>/dev/null \
       && jq empty "$_tmp" 2>/dev/null; then
      cp "$CC_SETTINGS" "$CC_SETTINGS.bak" && mv "$_tmp" "$CC_SETTINGS"
      ok "plugin auto-update enabled (an update lands on restart or /reload-plugins; backup: settings.json.bak)"
    else
      rm -f "$_tmp"
      todo "could not enable plugin auto-update — turn it on with /plugin → Marketplaces → cubrid-agent → Enable auto-update"
    fi
  fi
else
  ok "plugin auto-update: nothing to set (no user-scope cubrid-agent marketplace entry — npx skills channel, or project/local scope)"
fi

echo "== \$HOME standard assets — clone only when absent (existing clones untouched) =="
clone_if_absent() { # <url> <dir> [extra git-clone args...]
  local url=$1 dir=$2; shift 2
  if [ -d "$dir/.git" ]; then ok "$(basename "$dir") present"
  else git clone "$@" "$url" "$dir" || fail "clone failed: $url"; ok "$(basename "$dir") cloned"; fi
}
clone_if_absent https://github.com/CUBRID/cubrid-testcases.git "$HOME/cubrid-testcases"
# Fork remote for submitting TC PRs — each teammate has their own fork, derived from the gh-authenticated account (ADR 0004).
# Source: $CUBRID_GH_FORK (override) -> gh api user. Remote name is the neutral 'fork', not a person's name.
FORK_OWNER="${CUBRID_GH_FORK:-}"
if [ -z "$FORK_OWNER" ] && command -v gh >/dev/null; then
  FORK_OWNER="$(gh api user --jq .login 2>/dev/null || true)"
  # Safety net: if the derived account has no fork, create it (idempotent — no-op if it exists).
  if [ -n "$FORK_OWNER" ] && ! gh repo view "$FORK_OWNER/cubrid-testcases" >/dev/null 2>&1; then
    gh repo fork CUBRID/cubrid-testcases --remote=false >/dev/null 2>&1 || true
  fi
fi
if [ -n "$FORK_OWNER" ]; then
  FORK_URL="https://github.com/$FORK_OWNER/cubrid-testcases.git"
  # If set-url fails (remote absent) add it — authoritative so a changed $CUBRID_GH_FORK is reflected on re-run.
  git -C "$HOME/cubrid-testcases" remote set-url fork "$FORK_URL" 2>/dev/null \
    || git -C "$HOME/cubrid-testcases" remote add fork "$FORK_URL"
  ok "cubrid-testcases fork remote ($FORK_OWNER)"
else
  todo "cubrid-testcases fork remote — re-run after gh auth (or export CUBRID_GH_FORK=<owner>)"
fi
if [ -d "$HOME/cubrid/.git" ]; then ok "cubrid present"
else # History is needed (Ground: log --grep, merge-base); blobs are lazy. Fall back to a plain clone on older git.
  git clone --filter=blob:none https://github.com/CUBRID/cubrid.git "$HOME/cubrid" 2>/dev/null \
    || git clone https://github.com/CUBRID/cubrid.git "$HOME/cubrid" || fail "cubrid clone failed"
  ok "cubrid cloned"
fi
# CTP: follow the component skills' resolution order ($CTP_HOME -> ~/CTP -> ~/cubrid-testtools/CTP)
if   [ -n "${CTP_HOME:-}" ] && [ -x "$CTP_HOME/bin/ctp.sh" ]; then CTP="$CTP_HOME"; ok "CTP: \$CTP_HOME=$CTP"
elif [ -x "$HOME/CTP/bin/ctp.sh" ]; then CTP="$HOME/CTP"; ok "CTP: ~/CTP"
elif [ -x "$HOME/cubrid-testtools/CTP/bin/ctp.sh" ]; then CTP="$HOME/cubrid-testtools/CTP"; ok "CTP: ~/cubrid-testtools/CTP"
else
  clone_if_absent https://github.com/CUBRID/cubrid-testtools.git "$HOME/cubrid-testtools"
  CTP="$HOME/cubrid-testtools/CTP"; ok "CTP: $CTP"
fi
# No conf copy needed: CTP's own sql.conf / sql_by_cci.conf already use scenario=${HOME}/cubrid-testcases/sql and non-default ports.

echo "== Runtime output directory — \$HOME/.cubrid-agent =="
mkdir -p "$AGENT_DIR/reports/gate-resolved" "$AGENT_DIR/reports/author-testcase" "$AGENT_DIR/reports/review-testcase" "$AGENT_DIR/worktrees"
ok "$AGENT_DIR/{<KEY>/ (per-run dir + manifest.json; skills create it), reports/, worktrees/}"

# Helpers the skills invoke by absolute path. They ship in this skill's bin/ and install into
# ~/.cubrid-agent/bin/ so that ONE path works on both channels: the plugin sets CLAUDE_PLUGIN_ROOT
# but `npx skills add` copies only a single skill's own directory, so no path relative to a skill
# resolves for every skill that needs the helper (ADR 0003's reasoning, applied to shared helpers).
# A copy, not a symlink: it must survive the source checkout being moved or deleted. Re-running
# setup refreshes it, which is also how a repo change reaches an already-provisioned machine.
SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)  # readlink: the skill dir may be symlinked in
HELPER_SRC="$SELF_DIR/../bin"   # scripts/setup.sh is the skill's implementation; bin/ is what it installs
mkdir -p "$AGENT_DIR/bin"
for h in ground-issue.sh select-queue.sh render-pr-body.sh verify-run.sh render-report.sh; do
  if [ -f "$HELPER_SRC/$h" ]; then
    install -m 755 "$HELPER_SRC/$h" "$AGENT_DIR/bin/$h" && ok "~/.cubrid-agent/bin/$h"
  else todo "$h not found in the skill's bin/ — the skills that call it by absolute path will report it missing"; fi
done

echo "== env — detect JDK + write ~/.cubrid-agent/env.sh =="
JH="${JAVA_HOME:-}"
if [ -z "$JH" ] || [ ! -x "$JH/bin/javac" ]; then
  if command -v javac >/dev/null; then
    JH="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
  else JH=""; fi
fi
if [ -n "$JH" ] && [ -x "$JH/bin/javac" ]; then ok "JDK: $JH"
else todo "JDK (javac) not found — e.g. sudo dnf install java-1.8.0-openjdk-devel, then re-run setup"; fi
# Jira username (identity role C — ADR 0004). Resolve it ONCE here and export it so that no
# skill re-parses ~/.netrc at run time: netrc tokens may sit on one line or on many, and an
# ad-hoc "grep -A2 … | grep login" returns the HOST on the single-line form — which silently
# turns the Select JQL into a 0-issue query instead of raising an error.
resolve_jira_user() {
  if [ -n "${CUBRID_JIRA_USER:-}" ]; then printf '%s\n' "$CUBRID_JIRA_USER"; return 0; fi
  [ -f "$HOME/.netrc" ] || return 0
  # Tokens may be spread over one line or many, so walk them — but drop #-comments first
  # (a commented-out stale entry must not win) and let only the FIRST matching machine block
  # decide, so a later block's login can never be picked up.
  awk '{ sub(/#.*/, ""); for (i = 1; i <= NF; i++) t[++n] = $i }
       END { for (i = 1; i <= n; i++)
               if (t[i] == "machine" && t[i+1] == "jira.cubrid.org") {
                 for (j = i + 2; j <= n; j++) {
                   if (t[j] == "machine" || t[j] == "default" || t[j] == "macdef") break
                   if (t[j] == "login") { print t[j+1]; exit }
                 }
                 exit
               } }' "$HOME/.netrc"
}
QA_USER="$(resolve_jira_user)"
# Defensive: never hand a hostname to the JQL, whatever the netrc layout.
[ "$QA_USER" = "jira.cubrid.org" ] && QA_USER=""
if [ -n "$QA_USER" ]; then ok "jira username: $QA_USER"
else todo "jira username unresolved — export CUBRID_JIRA_USER, or give machine jira.cubrid.org a 'login <user>' token in ~/.netrc"; fi
{
  echo "# generated by setup.sh — source ~/.cubrid-agent/env.sh in each CTP session"
  echo '[ -f "$HOME/.cubrid.sh" ] && source "$HOME/.cubrid.sh"'
  echo "export CTP_HOME=\"$CTP\""
  [ -n "$JH" ] && echo "export JAVA_HOME=\"$JH\""
  [ -n "$QA_USER" ] && echo "export CUBRID_JIRA_USER=\"$QA_USER\""
} > "$AGENT_DIR/env.sh"
ok "~/.cubrid-agent/env.sh"

echo "== CUBRID build — trusted build (optional; issue-dependent) =="
if [ -n "$BUILD_URL" ]; then
  sh "$CTP/common/script/run_cubrid_install" "$BUILD_URL" 2>&1 \
    | tee "$AGENT_DIR/install-build.log" | tail -3
  grep -q '\[ERROR\]' "$AGENT_DIR/install-build.log" && fail "build install failed — see ~/.cubrid-agent/install-build.log"
  # .cubrid.sh is externally generated — it may bare-reference unset vars (e.g. LD_LIBRARY_PATH) that abort under set -u. Relax only while sourcing.
  set +u; [ -f "$HOME/.cubrid.sh" ] && source "$HOME/.cubrid.sh"; set -u
  [ -n "${CUBRID:-}" ] && [ ! -f "$CUBRID/lib/libcubrid_all_locales.so" ] \
    && sh "$CUBRID/bin/make_locale.sh" -t 64bit >/dev/null 2>&1
  ok "build installed: $BUILD_URL"
elif [ -d "$HOME/CUBRID" ]; then
  ok "CUBRID present: \$HOME/CUBRID (whether it contains the target issue's fix is checked by the pipeline)"
else
  todo "no CUBRID build — setup --build <url> (build server 192.168.1.91:8080, URL shape http://192.168.1.91:8080/REPO_ROOT/store_01/<version>/drop/CUBRID-<version>-Linux.x86_64.sh; list store_01/ first, old builds get pruned and a version named in an issue may already be 404. Not needed unless using CTP skills)"
fi

# --- Tier 3 CLI installs. Only reached with --install-clis, i.e. after the skill got a yes. -------
# Each installer runs ONLY when its capability check already failed, so a re-run installs nothing.
GH_DNF_CMD="sudo dnf install -y 'dnf-command(config-manager)' && sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && sudo dnf install -y gh"

pandoc_can_jira() {
  pandoc --list-input-formats 2>/dev/null | grep -qx jira \
    && pandoc --list-output-formats 2>/dev/null | grep -qx jira
}
cj_can_attachment() { command -v cubrid-jira >/dev/null && cubrid-jira attachment --help >/dev/null 2>&1; }
pandoc_ver() { pandoc --version 2>/dev/null | head -1 | cut -d' ' -f2; }

install_gh() { # the ONLY CLI needing root. rc 2 = sudo wants a password, which a script cannot answer.
  sudo -n true 2>/dev/null || return 2
  if command -v dnf >/dev/null; then
    step "installing gh with dnf (sudo)"
    sudo -n dnf install -y 'dnf-command(config-manager)' >/dev/null 2>&1
    sudo -n dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo >/dev/null 2>&1
    sudo -n dnf install -y gh >/dev/null 2>&1
  elif command -v apt-get >/dev/null; then
    step "installing gh with apt-get (sudo)"
    sudo -n apt-get install -y gh >/dev/null 2>&1
  else
    return 1
  fi
  hash -r 2>/dev/null
  command -v gh >/dev/null
}

install_pandoc() { # no sudo, no gh: a public release asset needs neither. ~/.local/bin shadows a system pandoc.
  [ "$(uname -m)" = x86_64 ] || return 3
  local ver=2.19.2 tgz
  tgz=$(mktemp) || return 1
  step "installing pandoc $ver into ~/.local (no sudo)"
  if curl -fsSL -o "$tgz" \
       "https://github.com/jgm/pandoc/releases/download/$ver/pandoc-$ver-linux-amd64.tar.gz" \
     && mkdir -p "$HOME/.local" \
     && tar xzf "$tgz" -C "$HOME/.local" --strip-components=1; then
    rm -f "$tgz"; hash -r 2>/dev/null; pandoc_can_jira; return $?
  fi
  rm -f "$tgz"; return 1
}

install_uv() {
  command -v uv >/dev/null && return 0
  step "installing uv into ~/.local (no sudo)"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
  hash -r 2>/dev/null
  command -v uv >/dev/null
}

install_cubrid_jira() { # uv fetches its own Python 3.14, so no system Python requirement
  install_uv || return 1
  if command -v cubrid-jira >/dev/null; then
    step "upgrading cubrid-jira (the installed build predates 'attachment')"
    uv tool upgrade cubrid-jira >/dev/null 2>&1
  else
    step "installing cubrid-jira with uv (no sudo)"
    uv tool install git+https://github.com/vimkim/cubrid-jira.git >/dev/null 2>&1
  fi
  hash -r 2>/dev/null
  cj_can_attachment
}

if [ "$INSTALL_CLIS" -eq 1 ]; then
  echo "== CLIs — installing whatever is missing; credentials stay yours =="
else
  echo "== CLIs & credentials — Tier 3 (human's job; only checked here) =="
fi

# gh — kept first because it is the one that can stall on a sudo password; a failure here must not
# stop pandoc and cubrid-jira, which need no root at all.
if command -v gh >/dev/null; then ok "gh"
elif [ "$INSTALL_CLIS" -eq 1 ]; then
  install_gh; _rc=$?
  case $_rc in
    0) ok "gh (installed)" ;;
    2) todo "gh needs root and sudo asked for a password this script cannot answer — run it yourself: $GH_DNF_CMD (docs/setup.md §3)" ;;
    *) todo "gh install failed (no dnf/apt-get, or the repo step failed) — install by hand: docs/setup.md §3" ;;
  esac
else todo "install gh — docs/setup.md §3"; fi

# pandoc: check the CAPABILITY, not the presence. cubrid-jira renders issue text with
# `pandoc -f jira` / `--to jira`. Without the writer a Jira write hard-fails; without the reader an
# older cubrid-jira returns an EMPTY body instead of erroring. The RHEL 8 package is 2.0.6 — neither.
_pandoc_ver=$(pandoc_ver)
if [ -n "$_pandoc_ver" ] && pandoc_can_jira; then ok "pandoc $_pandoc_ver (jira reader + writer)"
elif [ "$INSTALL_CLIS" -eq 1 ]; then
  install_pandoc; _rc=$?
  case $_rc in
    0) ok "pandoc $(pandoc_ver) (installed; jira reader + writer)" ;;
    3) todo "pandoc: no static build for $(uname -m) — install >= 2.19 by hand (docs/setup.md §3)" ;;
    *) todo "pandoc install failed (download or extract) — install >= 2.19 by hand (docs/setup.md §3)" ;;
  esac
elif [ -z "$_pandoc_ver" ]; then
  todo "install pandoc >= 2.19 (cubrid-jira renders issue text with it) — docs/setup.md §3"
else
  todo "pandoc $_pandoc_ver has no jira reader/writer — Jira writes hard-fail and issue bodies can read back EMPTY. Install >= 2.19 (no sudo needed) — docs/setup.md §3"
fi

# cubrid-jira: check the CAPABILITY, not the presence. The tool never bumps its version
# (every build is `1.0.0`), so `command -v` and `--version` both pass on a build that is
# missing what the skills call. `attachment --help` is the floor probe: no `attachment`
# means an install older than 2026-07-29, which also has no authenticated reads and so
# answers every CUBRIDQA read with HTTP 401. The commit id is printed rather than compared —
# git shas carry no order offline, so the operator matches it against docs/setup.md §3.
cj_commit() {
  sed -n 's/.*"commit_id": *"\([0-9a-f]\{7,40\}\)".*/\1/p' \
    "$HOME"/.local/share/uv/tools/cubrid-jira/lib/python3*/site-packages/cubrid_jira-*.dist-info/direct_url.json \
    2>/dev/null | head -1 | cut -c1-12
}
_cj_commit=$(cj_commit)
if cj_can_attachment; then
  ok "cubrid-jira${_cj_commit:+ (uv install: $_cj_commit)} — attachment + authenticated reads present"
elif [ "$INSTALL_CLIS" -eq 1 ]; then
  if install_cubrid_jira; then _cj_commit=$(cj_commit); ok "cubrid-jira${_cj_commit:+ (uv install: $_cj_commit)} — installed; attachment + authenticated reads present"
  else todo "cubrid-jira install failed — uv tool install git+https://github.com/vimkim/cubrid-jira.git (docs/setup.md §3)"; fi
elif ! command -v cubrid-jira >/dev/null; then
  todo "install cubrid-jira — docs/setup.md §3"
else
  todo "cubrid-jira is older than 2026-07-29${_cj_commit:+ (uv install: $_cj_commit)}: no 'attachment' subcommand and no authenticated reads, so the skills fail with 'invalid choice' and HTTP 401 on CUBRIDQA. Run: uv tool upgrade cubrid-jira — docs/setup.md §3"
fi

# A tool in ~/.local/bin that the operator's shell cannot see is not installed as far as the next
# session is concerned — report it rather than letting the next run re-install on top of itself.
if [ "$LOCAL_BIN_ON_PATH" -eq 0 ] && { [ -x "$HOME/.local/bin/pandoc" ] || [ -x "$HOME/.local/bin/cubrid-jira" ]; }; then
  todo "~/.local/bin is not on your PATH, so the tools installed there are invisible to a new shell — add: export PATH=\"\$HOME/.local/bin:\$PATH\" to ~/.bashrc"
fi
# PDF attachments: the mandatory "read every attachment" rule cannot be met without a text
# extractor — the Read tool cannot render a PDF either. Checked, not installed: it needs root and
# is outside the three CLIs this script installs, so the operator decides (CUBRIDQA-1488).
if command -v pdftotext >/dev/null; then ok "pdftotext (PDF attachments readable)"
else todo "pdftotext missing — a PDF attachment will be recorded as unread instead of read: sudo dnf install -y poppler-utils (Debian/Ubuntu: sudo apt install poppler-utils)"; fi
if [ -n "${CUBRID_JIRA_USER:-}" ] && [ -n "${CUBRID_JIRA_PASSWORD:-}" ]; then ok "jira credentials (env — standard)"
elif [ -n "$QA_USER" ] && grep -qs 'jira\.cubrid\.org' "$HOME/.netrc"; then ok "jira credentials (.netrc — also allowed; user=$QA_USER)"
else todo "jira credentials — export CUBRID_JIRA_USER/CUBRID_JIRA_PASSWORD (or ~/.netrc with a 'login <user>' token)"; fi
if [ -n "${GH_TOKEN:-}" ] || gh auth status >/dev/null 2>&1; then ok "gh authenticated"
else todo "gh auth — gh auth login (or GH_TOKEN)"; fi

echo
if [ "$TODOS" -eq 0 ]; then echo "setup complete — no TODOs left. Launch: docs/setup.md §4"
elif [ "$INSTALL_CLIS" -eq 1 ]; then echo "setup complete — ${TODOS} TODO(s) above (credentials are yours to set; a CLI TODO here means its install could not be forced)"
else echo "setup complete — ${TODOS} TODO(s) (above: CLI installs & credentials are a human's job; re-run with --install-clis to install them)"; fi
