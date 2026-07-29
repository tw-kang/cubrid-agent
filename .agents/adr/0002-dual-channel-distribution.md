# 한 소스에서 이중 채널로 배포한다 — 플러그인 + npx skills

재패키징([ADR 0001](./0001-repackage-as-plugin.md)) 이후, cubrid-agent를 **하나의 repo 소스에서 두 채널**로 배포한다. Claude Code 사용자와 다른 에이전트 CLI(Codex·Cursor·Gemini 등) 사용자를 모두 커버하기 위함이다.

## 결정

- **채널 1 — Claude Code 플러그인**: `claude plugin marketplace add tw-kang/cubrid-agent` → `claude plugin install cubrid-agent@cubrid-agent`. `plugin.json` 등재분 6종(setup + 파이프라인 5) 상시 로드 + hook 게이트 활성. 호출명은 플러그인 접두어가 붙은 `/cubrid-agent:<스킬>`.
- **채널 2 — `npx skills add`**([vercel-labs/skills](https://github.com/vercel-labs/skills)): `npx skills add tw-kang/cubrid-agent -s <skill>` (또는 `--all`). 개별 스킬을 여러 에이전트에 설치. 호출명은 접두어 없는 `/<스킬>`. **부품 16종은 이 채널만으로 접근한다** — 플러그인은 로드하지 않는다(ADR 0001).
- **구조 변경 없이 양립**: 스킬을 `skills/qa/<name>/SKILL.md`(카탈로그 레이아웃)로 두면 skills CLI가 GitHub에서 직접 발견한다(별도 publish·package.json 불필요). 같은 레이아웃을 플러그인 `skills[]`도 참조한다.
- **배포물**: 루트 `README`(두 채널 설치법)·`package.json`(repo 메타)·`CHANGELOG`·`LICENSE`(Apache-2.0) — 전부 영문(배포 대상).

## 근거

- **커버리지**: 플러그인만으론 비-Claude CLI를 못 태운다. skills CLI 채널이 Codex·Cursor 등을 흡수한다.
- **단일 소스**: 두 채널이 같은 `skills/qa/`를 읽으므로 정본 분열이 없다 — 카탈로그 레이아웃이 두 발견 방식(플러그인 `skills[]`, skills CLI 스캔)을 동시에 만족한다.
- **선례**: `mattpocock/skills`가 루트=플러그인 + skills 채널 이중 배포의 검증된 형태.

## Consequences

- 스킬은 반드시 `skills/qa/<name>/SKILL.md` 카탈로그 레이아웃(카테고리 `qa` 아래 스킬 dir 직접)을 유지해야 skills CLI가 발견한다 — 루트로 옮기면 플러그인 구조와 충돌.
- `package.json`은 발견에 불필요(skills CLI는 레이아웃 기반) — repo 메타데이터 용도로만 둔다.
- `npx skills add`의 실사용 검증은 브랜치를 GitHub에 push한 뒤에만 가능(로컬 미검증 — 카탈로그 레이아웃 일치로 구조 검증만 완료).
