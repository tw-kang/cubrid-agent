# 루트를 Claude Code 플러그인으로 재패키징하고 부품 스킬을 흡수한다

Stage 2 팀 배포를 앞두고, cubrid-agent를 `git clone + setup.sh 심링크` 전달에서 **루트 자체가 Claude Code 플러그인**인 형태로 재패키징한다. 동시에 외부 `tw-kang/skills`(부품 스킬 18종)를 **이 repo로 흡수**한다. 이 결정은 ADR 0011(부품 스킬 clone+심링크 — 본 재패키징으로 삭제됨, git 이력에만 남음)을 **대체·폐기**한다.

## 결정

- **루트 = 플러그인 + 셀프 마켓플레이스**: `.claude-plugin/plugin.json`(플러그인) + `marketplace.json`(`source:"./"` — 루트가 곧 플러그인). Claude Code는 `claude plugin install`로 설치한다.
- **부품 스킬 흡수**: 18종을 `skills/qa/`로 편입(이력 보존 — `git subtree` 부재라 `git filter-branch`로 접두어 재작성 후 merge, `git log --follow` 네이티브). 외부 repo 의존·심링크 제거.
- **구조 C(등재 6 + 미등재 16)**: `plugin.json`의 `skills[]`엔 파이프라인 5종(`gate-resolved`·`author-testcase`·`review-testcase`·`create-sql`·`verify-sql`)과 진입점 `setup-cubrid-agent`([ADR 0003](./0003-setup-entrypoint-skill.md))만 등재해 상시 로드하고, 나머지 16종은 소스로만 두어 **플러그인이 로드하지 않는다**(always-on 0). ⚠ **배치는 [ADR 0006](./0006-shipped-vs-in-progress-skill-trees.md)이 대체한다** — 미등재 16종은 `skills/qa/`가 아니라 `skills/in-progress/`에 있다. 등재 6종과 always-on 비용 결정은 그대로 유효하다. 미등재 16종은 "필요할 때 이름으로 부르는" 것이 아니라 플러그인 채널에 **없다** — 쓰려면 `npx skills add` 채널로 개별 설치한다([ADR 0002](./0002-dual-channel-distribution.md)).
  - **왜 명시 등재가 필수인가 (2026-07-29 실측, Claude Code 2.1.220)**: 기본 `skills/` 스캔은 한 단계만 본다. 우리 배치는 `skills/qa/<이름>/`이므로 `skills[]`를 지우면 로드 0종이 된다. 즉 6종이 뜨는 건 순전히 경로를 명시했기 때문이고, 마켓플레이스 루트 예외(`source:"./"` + 명시 subdirectory가 기본 스캔을 대체)가 아니라 **중첩 배치**가 실제 원인이다. `"skills": ["./skills/qa/"]` 한 줄로 22종 전부 로드되지만 세션당 상시 비용이 ~1,185 → ~3,593 tok으로 3배가 된다. 확인 명령: `claude plugin details cubrid-agent`.
- **hook 이관**: 품질 게이트 hook을 `.claude/settings.json`에서 플러그인 형식(`hooks/hooks.json` + `scripts/`, `${CLAUDE_PLUGIN_ROOT}` 경로)으로 옮긴다.

## 근거

- **정본 분열 해소**: 부품 스킬을 별도 repo로 두면(0011) 이중 소스·버전 스큐가 생긴다. 흡수하면 파이프라인과 스킬이 한 커밋에서 원자적으로 진화한다.
- **표준 배포 경로**: 플러그인은 Claude Code의 1급 설치·갱신·버저닝 메커니즘(마켓플레이스·`plugin install`)을 그대로 쓴다 — clone+심링크 수작업 프로비저닝이 사라진다.
- **always-on 비용 통제**: 부품 16종을 로드하지 않으므로 시작 컨텍스트 비용이 6종(~1,185 tok)으로 제한된다 — 22종 전부면 ~3,593 tok.

## Consequences

- `setup.sh`의 부품 스킬 clone+심링크 절이 제거된다(스킬은 이제 repo/플러그인에 내장). setup.sh는 머신 상태(cubrid-testcases·cubrid·CTP) 프로비저닝만 담당.
- 배포 정본([deployment.md](../../docs/deployment.md))의 Tier 1이 바뀐다: "clone이 나른다"가 스킬까지 포함(별도 skills repo 없음).
- 기존 `~/skills` clone·`~/.claude/skills` 심링크는 흡수 후 불필요 — 재패키징 커밋과 무관하게 각 머신에서 정리(불가침 원칙상 자동 삭제 안 함).
- 버전은 당분간 생략(commit-SHA fallback) — semver pin + eval 게이트는 이후 단계(마켓플레이스 검증 `claude plugin validate . --strict`의 유일 경고).
- 기타 CLI(Codex·Cursor 등) 전달은 별도 결정 [ADR 0002](./0002-dual-channel-distribution.md)(이중 채널).
