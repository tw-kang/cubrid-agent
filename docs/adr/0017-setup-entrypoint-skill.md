# 설치 진입점은 커맨드가 아니라 스킬 — setup.sh는 스킬 안으로, 루트 스크립트는 삭제

## 배경

`claude plugin install`(또는 `npx skills add`) 직후엔 아무것도 못 돌린다. 프로비저닝은 루트 `setup.sh`에만 있고, 문서는 "플러그인 설치와 별개로 repo를 또 clone해서 `./setup.sh`를 돌려라"라고 안내한다 — 설치본과 별개의 두 번째 복사본을 요구하는 셈. matt-pocock 스킬의 "install + `/setup` 한 번 → 사용 가능" 바에 못 미친다(CUBRIDQA-1442 footer가 B로 지목).

## 결정

설치 후 진입점을 **`disable-model-invocation: true` 스킬 `setup-cubrid-agent`**로 만든다. 커맨드 파일(`commands/`)이 아니라 스킬인 이유: 커맨드는 Claude Code 플러그인 채널 전용이라 npx skills 채널(Codex·Cursor 등)에 안 실리지만, 스킬이면 **두 채널 모두**에 실린다.

- **위치**: `setup.sh` 정본을 `skills/qa/setup-cubrid-agent/scripts/setup.sh`로 옮기고, **루트 `./setup.sh`는 두지 않는다**(정본은 단 하나). npx는 스킬 디렉토리만 복사하므로 스크립트가 스킬 안에 있어야 두 채널 모두 self-contained다. repo 개발자·Stage 3 컨테이너는 `skills/qa/setup-cubrid-agent/scripts/setup.sh`를 직접 실행(CWD 비의존)하고, `./setup.sh`를 가리키던 문서는 이 경로 또는 `/setup-cubrid-agent`로 재지정한다.
- **동작**: 대화형 완주 — `setup.sh` 실행 → TODO 파싱 → sudo CLI 설치(사용자 승인 하에 스킬이 실행)·자격 체크리스트·sanity 확인(`cubrid-jira search`, `gh auth status`)까지 이어준다.
- **완주 판정**: 전부 충족이 아니라 **티어별 준비도 리포트**로 끝낸다 — gate-resolved는 자격만 있으면 즉시 가능, CTP 계열(author-testcase·review-testcase·verify-sql)은 사내망 빌드까지 받아야 가능. 부분 성공을 솔직하게 명시한다.
- **CUBRID 빌드(`--build <url>`)**: 이슈 의존 값(대상 이슈의 fix 포함 빌드)이라 스킬은 실행하지 않고 **항상 안내만** 한다.
- **모델 자동 호출 금지**: 머신 상태를 바꾸는 스킬이라 오발 기동을 막는다. 발견성은 README·stage2-setup의 수동 기동 안내로 확보.

## 근거

- 이중 채널 대칭(ADR-0015)을 진입점에도 적용 — 커맨드였다면 npx 채널은 항상 반쪽이다.
- `setup.sh`는 이미 CWD 독립($HOME 경로)·멱등·비대화식이라 스킬이 감싸기만 하면 된다. 스킬은 sudo·자격 등 스크립트가 못 하는 Tier 3만 사람과 함께 메운다.

## 이 결정이 바꾸지 않는 것

- **완전 원커맨드는 CTP 계열에서 구조적으로 불가** — 사내망 빌드서버·자격 의존. gate-resolved만 install+setup+자격으로 완결된다. 이 한계는 없애는 게 아니라 명시한다.
- npx 채널엔 hook·품질 게이트가 없다(ADR-0015) — 스킬은 실리지만 프로비저닝 실행은 되고 hook 게이트는 안 붙는다는 갭을 문서화한다.

## Considered Options

- **커맨드 파일(`commands/setup-cubrid-agent.md`)**: 더 가볍고 스킬 안 스크립트를 바로 부를 수 있으나 Claude Code 전용 — 기각(채널 비대칭).
- **루트 setup.sh를 스킬 스크립트로 exec하는 래퍼로 유지**: `./setup.sh` 경로를 보존해 기존 문서·`git clone → ./setup.sh` 관성을 안 깬다는 이점. 그러나 (1) 정본이 둘로 보이고(래퍼가 옛 진입점을 어정쩡하게 살림), (2) 이번 작업에서 그 문서들을 어차피 재지정하며, (3) Stage 3 컨테이너는 아직 미구현(park)이라 보존할 라이브 경로가 없다 — 기각, 삭제 채택.
- **루트 setup.sh 유지 + 스킬은 경로 분기**: 스킬이 `CLAUDE_PLUGIN_ROOT`면 그걸, npx면 raw curl/clone 안내. npx 쪽이 온전한 원커맨드가 못 됨 — 기각.

## Consequences

- 구현: `skills/qa/setup-cubrid-agent/`(SKILL.md ≤200줄 + `scripts/setup.sh`) 신설, `plugin.json` skills[]에 등재, **루트 `setup.sh` 삭제**.
- 문서: README 플러그인 절 + `docs/guides/stage2-setup.md` §1을 `install → /setup-cubrid-agent`로. repo 개발자 직접 실행은 `skills/qa/setup-cubrid-agent/scripts/setup.sh`. `./setup.sh`를 가리키던 CONTEXT-MAP·deployment·staging·author/review SKILL 참조를 재지정.
- CI: `claude plugin validate .`를 CI 게이트로 배선(구조 검증=차단, `--strict`=정보성). `--strict`는 현재 의도적 `version` 생략(commit-SHA 정책)만 경고하므로 차단 기준으로 쓰지 않는다 — semver pin 단계에서 승격(CUBRIDQA-1442 seam).
- Jira: CUBRIDQA-1442 코멘트에 마켓플레이스 설치 채널 추가(설치 UX 동작 확인 후).
- eval 없음: disable-model-invocation 스킬은 트리거 판정 대상이 아니다 — 품질은 plugin validate + 수동 기동 안내로 보장.
