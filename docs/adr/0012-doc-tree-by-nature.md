# 문서 트리를 성격 기준으로 배치한다 — 최상위 3분법 + docs/ 성격 디렉토리

스킬 자기완결(deployment.md D8) 이후 저장소의 문서·실행 자산을 **성격 기준**으로 배치한다. 에이전트 설계 기록이 실행체처럼 읽히는 문제와, 문서 한 평면에 규범·기록·가이드가 섞여 파일명으로 구분되지 않는 문제를 없애기 위함이다.

- **최상위 3분법**: 루트 = 지도(`CONTEXT-MAP.md`)·진입점(설치 진입점은 [ADR 0017](./0017-setup-entrypoint-skill.md)로 `/setup-cubrid-agent` 스킬로 이동 — 루트 스크립트 없음) / **플러그인 = 실행 계약** / `docs/` = 사람이 읽는 문서 전부. 재패키징([ADR 0014](./0014-repackage-as-plugin.md)) 이후 실행 계약은 **루트 플러그인**이다 — `.claude-plugin/`(매니페스트) + `skills/qa/`(스킬·연료) + `hooks/`·`scripts/`(hook), 배포되는 전부. (이전엔 `.claude/`가 실행 계약이었다.)
- **에이전트 설계 기록은 `docs/agents/<name>/`**: 설계 기록임이 위치로 드러난다. 컨텍스트 패턴(CONTEXT-MAP → 각 `CONTEXT.md`·`docs/adr/`)은 그대로다(ADR 0008의 모노레포 결정 유지, 위치만 성격에 맞춤).
- **`docs/` 내부 = "규범만 평면"**: `docs/` 바로 아래는 **현행 유효한 전역 규범·참조만**(design-principles·staging·deployment·dev-process). 나머지는 성격 디렉토리 — `guides/`(실행 가이드), `adr/`(결정 기록), `agents/`(에이전트 설계 기록).
- **문서는 항상 최신만**: 과거 이력(변경 경위·supersede 서사·완료된 설계문서)은 문서에 남기지 않는다 — **역사는 git commit이 보존한다**. 역사화된 문서는 삭제한다(아카이브 디렉토리를 두지 않는다).

대안: ① 이름 유지+README 표지(오독 잔존 — 기각), ② `design/` 최상위 신설(최상위가 4개가 되고 docs와의 경계 설명이 또 필요 — 기각), ③ 규범까지 `norms/` 하위화(소수 파일에 과함 — 기각), ④ archive/ 디렉토리 운영(git이 이미 역사를 보존하므로 중복 — 기각).

## Consequences

- 신규 합류자 규칙 한 줄: **"실행은 루트 플러그인(`skills/qa/`·`hooks/`·`scripts/`·`.claude-plugin/`), 문서는 `docs/`, `docs/` 평면은 지금 유효한 규범"**.
- 결정 표는 관례대로 정본 문서 본문에 산다(DESIGN·staging·deployment의 Q/S/D 표) — ADR은 3조건(비가역·의아·트레이드오프)을 채우는 것만.
- 스킬 이름 = 에이전트 이름(`gate-resolved`·`author-testcase`·`review-testcase` — 이후 에이전트도 동일 규약).
- dev 로컬 산출물은 이원화: `docs/agents/<name>/reports/`(gitignore, dev 기록)와 `~/.cubrid-agent/reports/`(런타임 산출).
