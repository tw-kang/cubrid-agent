# repo는 결과물(플러그인)만 담고 설계는 Jira에 산다 — 문서 트리를 mattpocock형으로 최소화

저장소의 비제품 문서를 최소화한다. **repo에는 결과물(플러그인)과 "제품이 왜 이 모양인가"만 남기고, 에이전트·스킬 설계 기록은 Jira(CUBRIDQA)로 옮긴다.** 목표 골격은 [mattpocock/skills](https://github.com/mattpocock/skills)의 최소 구조 — `.agents/`(규범+thin ADR) / `docs/`(사람용 런북) / 루트 `CONTEXT.md`(단일 용어집) / 루트 플러그인(제품). 이 repo를 개발하는 워크플로 자체가 `grill-with-docs → to-spec → to-tickets → implement`라, 설계는 그 사슬을 타고 자연히 Jira 티켓에 쌓인다.

## 배경 — "ADR 이력이 토큰을 먹는다"는 전제가 틀렸다

문서가 578KB·70여 파일로 불었다: ADR 17개가 3개 디렉토리(`docs/adr/` 9 + `author-testcase/docs/adr/` 7 + `test-runner/docs/adr/` 1)에 흩어지고, 에이전트마다 `DESIGN.md`+`CONTEXT.md` 트리가 서고, `docs/reference/`엔 벤더링된 Anthropic 공식 문서 143KB가 쌓였다.

압축 동기는 "과거 이력이 토큰만 차지한다"였으나 측정으로 뒤집혔다:
- `docs/`는 **런타임에 컨텍스트로 자동 로드되지 않는다** — `hooks.json`은 셸 스크립트 3개만 걸고, 어떤 훅·스크립트도 문서를 context에 넣지 않는다. 항상 로드되는 문서는 `AGENTS.md`(27줄) + `plugin.json` 등재 스킬 6종의 description뿐. **ADR·DESIGN·CONTEXT는 누가 열 때만 토큰을 쓴다.**
- 즉 ADR을 압축해도 런타임 토큰은 0 감소. 진짜 질문은 "압축"이 아니라 **"설계 문서가 repo에 살 이유가 있나"** 였다.

답: 대부분은 없다. repo의 존재 이유는 배포되는 **결과물(플러그인)**이다. 설계 rationale은 개발 과정의 산물이고, 이 프로젝트는 이미 `grill-with-docs → to-spec → to-tickets → implement` 워크플로로 개발되므로 설계는 **CUBRIDQA 티켓**에 기록되는 게 정합이다. 언어 정책([DP3](../design-principles.md))의 *배포=영문 제품 / 미배포=한글 Jira* 분리와도 맞물린다.

## 결정

문서를 **성격이 아니라 "배포되는가·누가 읽는가"** 로 4분한다:

| 갈래 | 무엇 | 위치 |
|---|---|---|
| **결과물(제품)** | `.claude-plugin/` · `skills/qa/` · `hooks/` · `scripts/` | repo (불변) |
| **제품/저장소 형태 결정** | ship-as-plugin · dual-channel · setup-entrypoint · 개인 식별자 제거 · 이 doc-strategy | repo `.agents/adr/` (thin, 5개 — 0001-0005) |
| **에이전트용 규범(횡단)** | design-principles · issue-tracker · triage-labels · domain | repo `.agents/` |
| **사람용 런북/참조** | setup · deployment · dev-process | repo `docs/` |
| **에이전트·스킬 설계** | `DESIGN.md`×N · 에이전트/방법론 ADR · staging · hook-gates 설계 | **Jira (CUBRIDQA)** |
| **단일 용어집 + 파이프라인 지도** | (CONTEXT-MAP + 에이전트별 CONTEXT×5 흡수) | repo 루트 `CONTEXT.md` |

- **역사는 git이 보존**(ADR 0012에서 계승 — 0012는 이 ADR로 대체·삭제됨, git 이력) — Jira로 옮긴 뒤 repo에서 지운 설계 문서는 삭제하고 아카이브 디렉토리를 두지 않는다. "내용손실없이"는 **Jira 백필 + git 이력**이 보장한다.
- **thin ADR = 코드 읽는 사람이 Jira 없이도 알아야 할 것만.** 플러그인은 공개 배포라 외부 기여자는 Jira 접근이 없다 — repo만으로 "왜 이 모양인지"가 서야 한다. mattpocock도 같은 이유로 ADR을 2개(둘 다 제품 형태 결정)만 둔다.
- **`docs/reference/` 143KB 삭제 + 포인터 1줄** — 벤더링된 Anthropic 공식 문서는 web+git에 있으므로 URL만 남긴다.

## 백필 매핑 (설계 문서 → CUBRIDQA 티켓)

부모 `CUBRIDQA-1425`("cubrid-agent for qa dev process") 아래로 흡수한다. 하위/연관 티켓은 제목까지 재작성 가능.

| repo 설계 문서 | → 티켓 |
|---|---|
| `gate-resolved/{DESIGN,CONTEXT}.md`, ADR 0016 잔여 서사 | **1440** (resolve-gate) |
| `author-testcase/{DESIGN,CONTEXT}.md`, ADR 0001-0006·0009 | **1429** (tc-author) |
| `review-testcase/{DESIGN,CONTEXT}.md` | **1441** (tc-reviewer) |
| `test-runner/{DESIGN,CONTEXT}.md`, ADR 0010 | **1444** (test-runner) |
| `close-backport/CONTEXT.md` (설계 전 stub) | **1425** (전용 subtask 신설은 설계 시) |
| ADR 0013 (첨부 읽기) | **1443** (품질 개선) |
| `staging.md` + ADR 0007 (rollout) · ADR 0008 (monorepo) | **1425 본문** |
| `stage2-hook-gates.md` | **1446** (hook 이관) |
| 이 결정 + 재편 실행 | **1454** (문서·ADR 정합) |

## 이 결정이 supersede하는 것

- **ADR 0012(문서 트리 성격 3분법 — 삭제됨, git 이력)** — "에이전트 설계 기록은 `docs/agents/<name>/`"를 뒤집는다(→ Jira). 유지되는 것: *역사는 git이 보존* 원칙, *ADR은 3조건 채우는 것만*(오히려 강화 — 3조건 미달 설계는 애초에 Jira로), *스킬 이름 = 에이전트 이름*. 0012는 이 재편에서 삭제됐다(git 이력이 보존).

## 근거

- **repo의 결합도를 낮춘다.** 설계가 코드 옆에 있으면 코드 변경마다 설계 문서가 따라 썩는다(스테일 `file:line` 인용, 완료된 구현 체크리스트). 설계를 티켓에 두면 repo diff는 제품 변경만 담는다.
- **워크플로와 정합.** `to-spec`/`to-tickets`가 이미 트래커에 발행한다 — 설계의 단일 원천을 Jira로 두면 도구 사슬과 어긋나지 않는다.
- **외부 기여자 = 제품 + 사람용 문서로 충분.** 공개 플러그인 사용자는 스킬 사용법(사람용 docs)이 필요하지 내부 설계 rationale이 아니다. 내부 개발자는 Jira를 본다.
- **thin ADR이 안전판.** 그래도 "왜 이 저장소가 이 모양인가"는 Jira 없이 읽혀야 하므로 제품 형태 결정만 repo에 남긴다.

## Considered Options

- **단순 압축(내용만 깎기)** — ADR의 죽은 부분(완료 체크리스트·스테일 줄번호)만 제거. 런타임 토큰 0 감소·파일 수 그대로라 동기 미충족. 기각.
- **mattpocock literal(설계까지 ADR+SKILL로 흡수)** — DESIGN 서술 밀도가 손실. "내용손실없이"와 충돌. 기각.
- **에이전트 ADR만 한 디렉토리로 통합(repo 유지)** — 파일 수는 줄지만 설계가 여전히 repo에 남아 결합도 문제 그대로. 기각.
- **백필 방식 — 앞으로만 Jira + git(과거 미이관)** vs **유효분만 백필** vs **전량 백필**: 전량 백필 채택. 부모 1425에 에이전트별 subtask + "문서·ADR 정합"(1454) 티켓이 이미 있어 매핑 비용이 낮고, 단일 원천(Jira)이 가장 깨끗하다.

## Consequences

- **repo 비제품 문서 ~70파일/578KB → ~15파일.** thin ADR 5 + `.agents/` 규범 4 + `docs/` 런북 3 + `CONTEXT.md` + README/CHANGELOG. 나머지는 Jira/git.
- **thin ADR 재번호** — `.agents/adr/`로 옮기며 0014/0015/0017/0018/0019 → 0001-0005 연속 시퀀스(전역 단일 시퀀스 규칙 폐기). 0018(개인 식별자 제거)은 배포 형태 결정이라 thin set에 포함. 참조는 Jira/git으로 이동하므로 재번호 비용 낮음.
- **CLI(fix 브랜치)로 백필** — 설치된 `cubrid-jira`는 read를 익명 전송해 CUBRIDQA에서 401을 낸다. fix 브랜치 `feat/authenticated-reads`(= PR #3)의 CLI로 `update --from jira --yes`를 쓴다(curl 아님). 레시피는 `.agents/issue-tracker.md`의 임시 섹션. **PR #3 머지 시** 설치본 CLI가 바로 되고 그 섹션은 삭제.
- **실행은 별도 단계** — 이 ADR은 결정 기록이다. 파일 이동·삭제·`CONTEXT.md` 합성·Jira 백필은 `/to-spec → /to-tickets → /implement`(1454 하위)에서. Jira 백필은 `--yes` 안전판이 없는 PUT이라 티켓별 승인 후 전송.
- **Track B(SKILL.md 런타임 토큰 다이어트)는 범위 밖** — evals 재검증이 필요해 별도 CUBRIDQA 티켓으로 분리.
- **언어 정책 유지** — 잔존 문서는 한글(팀용), 제품은 영문.
