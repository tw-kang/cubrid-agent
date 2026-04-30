# AGENTS.md

Project conventions for AI coding agents (Claude Code, Cursor, Codex, Gemini CLI, etc.) working in this repository.

## Project Overview

This repository ships a collection of [Agent Skills](https://github.com/vercel-labs/skills) for working with **CUBRID** — primarily CTP (CUBRID Test Program) testcase scaffolding/execution/review skills, plus auxiliary skills like `jira/` for JIRA lookup. Skills are distributed via the `vercel-labs/skills` CLI and are installable across 45+ AI agents.

Top-level layout:

```
<skill-name>/
  SKILL.md          # frontmatter (name, description) + body
  scripts/          # optional: bundled executable code (Python, shell, ...)
  examples/         # optional: reference example artifacts
  references/       # optional: domain references for the skill
  evals/            # optional: evaluation set for skill optimization
README.md           # Korean-only skill index + per-skill summaries
AGENTS.md           # this file
```

## Authoring Rules (MUST)

These rules are non-negotiable. Apply them to every new skill and every change to an existing skill.

### Language

- **All skills (`SKILL.md`, `references/`, `examples/` comments, `scripts/` comments) MUST be written in English.**
- **`README.md` MUST be written in Korean only** — every section, table cell, install instruction, and example phrase. Do not mix English prose into `README.md`. Untranslatable identifiers (skill names, CLI commands, file paths, code blocks) stay verbatim, but the surrounding narrative is Korean.
- Frontmatter `description` SHOULD include both English and Korean trigger phrases when the skill is invoked from Korean speech (e.g., `"shell tc 만들어줘"`, `"create shell tc"`), because the trigger sentence is matched literally — no translation happens at invocation time.

### Skill size

- **Every `SKILL.md` MUST be under 200 lines** (including frontmatter and code blocks).
- If you cannot fit the skill in 200 lines, factor content out:
  - Move long reference material into `references/*.md` and link with `@references/...`.
  - Move worked examples into `examples/...` and link with `@examples/...`.
  - Move executable logic into `scripts/...` (see "Bundled code" below).
- Run `wc -l <skill>/SKILL.md` before committing — if it exceeds 200, refactor before merging.

### Bundled code

- **Anything that can be expressed as code MUST be bundled inside the skill as code, not described in prose.**
- Place executable logic in `<skill>/scripts/` (Python, POSIX shell, etc.). The skill body should call the bundled script via Bash with an explicit relative-to-skill path.
- Do not require the user to `git clone` or install a separate companion repository. The skill must be self-contained.
- When a previously-external CLI is needed, vendor its source code into `scripts/` and credit the upstream project in both the script header and the commit message (`Co-Authored-By:`).

### Dependencies

- **Skills MUST be deployable with minimal library dependencies.**
  - Default to language standard libraries (Python: stdlib only; shell: POSIX `sh` unless bash features are justified; etc.).
  - Do not require `pip install`, `npm install`, `uv tool install`, or similar Python/Node third-party-package steps unless absolutely necessary.
- **If a runtime tool IS required** (e.g., `pandoc`, `jq`, `gh`):
  1. Document it in a `## Prerequisites` section of `SKILL.md`.
  2. Add a pre-flight `command -v <tool>` check as the first step of the skill's procedure.
  3. **If the tool is missing, halt and ask the user for explicit consent before installing.** Detect the package manager (`dnf` / `apt-get` / `pacman` / `brew`) and present the exact install command. Never auto-install without consent.
  4. If the user declines, stop and inform them the skill cannot proceed.

## SKILL.md Structure

Required frontmatter:

```yaml
---
name: <skill-name>             # must match the directory name
description: "<one-paragraph trigger description, English + Korean phrases>"
---
```

Recommended body sections (in order):

1. One-line restatement of the skill's purpose.
2. `## How it works` — short overview of what the skill does, where bundled scripts live, what data flows through.
3. `## Prerequisites` — runtime tools required (with consent flow described).
4. `## Steps` — numbered procedure the agent should follow on invocation.
5. `## Optional flags` / `## Output Format` / `## Failure Conditions` — as relevant to the skill.

YAML quoting: `description` MUST be wrapped in `"..."` (with `\"` for embedded quotes) and MUST NOT contain raw blank lines, or the `vercel-labs/skills` CLI will silently skip the skill during discovery.

## Skill Naming

CTP testcase skills follow the pattern:

```
cubrid-<test-category>-tc-<action>
```

where `<action>` is one of `create`, `runone`, `review`. Example: `cubrid-shell-tc-create`. Auxiliary skills (e.g. `jira`) may use a flat name when they are not testcase actions.

## Commit Conventions

- Use Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, ...). Scope by skill name when relevant: `feat(jira): ...`.
- Commit in **meaningful units** — separate "bundle code" from "wire SKILL.md" from "update README" when possible.
- Commit messages MUST be in English.
- When vendoring code from another repository, add a `Co-Authored-By:` line crediting the upstream author and link the source repo in the commit body.

## README.md

- **Korean-only** — see "Language" rule above.
- Index table at the top: one row per skill, 스킬명 + 한 줄 한국어 설명.
- Per-skill section: 설치 명령, 짧은 설명, 호출 예시 문구. 호출 예시는 한국어 자연어 위주로 적되 영어 trigger 문구도 포함해도 좋습니다.
- The manual `cp -r` fallback list at the bottom MUST include every skill directory.

## Pre-merge Checklist

Before committing any skill change:

- [ ] `wc -l <skill>/SKILL.md` < 200
- [ ] Skill content is English (frontmatter description may carry Korean trigger phrases)
- [ ] Code-executable steps are bundled under `scripts/`, not described in prose
- [ ] No new third-party Python/Node deps; runtime tools (if any) gated behind a consent prompt
- [ ] `README.md` updated (index table, per-skill section, fallback `cp -r` list) — **Korean only**
- [ ] Conventional-commit message in English
