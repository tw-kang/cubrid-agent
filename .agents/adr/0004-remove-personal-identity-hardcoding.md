# 팀 배포를 위해 개인 식별자 하드코딩을 제거한다 — 배포처는 유지, fork·jira는 런타임 유도

## 배경

repo가 private인 채로 `claude plugin marketplace add tw-kang/cubrid-agent`를 돌리면 다른 팀원 계정에서 SSH host key·접근권한 벽에 막혀 설치가 실패한다(실관찰). 팀 배포(Stage 2)를 앞두고 배포처를 public으로 열되, 그와 별개로 `tw-kang`·`twkang`이 20+ 파일에 박혀 있다. 팀원은 **각자 자기 GitHub fork와 자기 Jira 계정**을 쓰므로, 개인 식별자를 그대로 두면 누가 돌려도 tw-kang의 fork·대기열로 흘러간다.

배포 경로 계획: **Stage 2 = `tw-kang/cubrid-agent` public 유지**, **Stage 3 = 같은 repo를 CUBRID org에 private로 이전 기여**. 팀 공용 org는 두지 않는다(없음). 이 ADR은 배포 채널 결정([ADR 0002](./0002-dual-channel-distribution.md))을 보충한다.

## 결정

박힌 `tw-kang`/`twkang`을 **4역할로 분류**하고 역할별로 다르게 처리한다.

| 역할 | 무엇 | 처리 |
|---|---|---|
| **A. 배포처 repo** | 매니페스트(`marketplace.json`·`plugin.json`·`package.json`)의 owner·repo URL·author·email, 두 채널 설치 명령(README·stage2-setup·ADR 0002·stage2-hook-gates 예제) | **유지** — 팀 전체가 하나의 tw-kang public repo에서 설치하는 공유 자원. "각자 보유" 이유가 성립하지 않음 |
| **A′. 흡수된 옛 skills repo** | `ADR 0001`·`CHANGELOG`의 `tw-kang/skills` | **유지** — 흡수된 외부 repo의 과거 사실(역사 기록) |
| **B. 각자 TC fork** | `--head tw-kang:tc/…`, `twkang` 리모트(`tw-kang/cubrid-testcases`) | **런타임 유도** (아래) |
| **C. 각자 Jira QA Assignee** | JQL `cf[213834] = twkang` | **런타임 유도** (아래) |
| **D. few-shot 출처 인용** | `few-shot-bank.md`의 `PR1844 / tw-kang` 등 | **유지** — 설정이 아니라 역사적 증거. 선택적 삭제는 인용 위조라 금지 |

**B — fork owner 유도**: 기본은 `gh api user --jq .login`(PR 생성에 이미 필수인 gh 인증 계정)에서 유도해 fork=`<login>/cubrid-testcases`, head=`<login>:tc/cbrd-XXXXX`. 예외(gh 로그인 ≠ fork owner: CI·다계정)만 `CUBRID_GH_FORK` env로 덮는다. 리모트 이름은 개인명 `twkang` 대신 중립명 **`fork`**로 통일한다. fork 미보유 팀원 안전망으로 setup.sh에 멱등 `gh repo fork CUBRID/cubrid-testcases --remote=false` 한 줄(이미 있으면 no-op).

**C — Jira 사용자명 유도**: `currentUser()`는 이 Jira에서 **못 쓴다**(아래 실측). 대신 cubrid-jira 자신의 자격 순서를 따르는 dual-source(`$CUBRID_JIRA_USER` 우선, 없으면 `~/.netrc`의 `machine jira.cubrid.org` login)를 쓰되, **해석은 `setup.sh`가 한 번만 하고 `~/.cubrid-agent/env.sh`로 `CUBRID_JIRA_USER`를 내보낸다**. 스킬은 그 값을 읽어 `cf[213834] = <사용자명>`에 끼우고 **직접 netrc를 파싱하지 않는다** — 스킬마다 즉석 파싱하면 한 줄 netrc에서 호스트명이, 주석 처리된 옛 항목이 있으면 엉뚱한 사용자명이 나와 JQL이 조용히 0건을 돌려준다(CUBRIDQA-1464에서 실측·수정). 값이 비었거나 호스트명처럼 보이면 스킬은 0건을 보고하지 않고 중단한다.

## currentUser() 실측 (재도입 방지)

`cf[213834] = currentUser()`가 문법상 자연스러워 보이지만 **이 on-prem Jira(jira.cubrid.org, REST api/2)에서 anonymous로 풀려 조용히 빈 결과를 낸다.** 현재 인증 계정이 twkang인 상태에서:

| 쿼리 | total |
|---|---|
| `cf[213834] = twkang` (명시) | 230 |
| `cf[213834] = currentUser()` | 0 |
| `assignee = currentUser()` | 0 |

인증은 정상(명시 쿼리가 230 반환)인데 `currentUser()`만 0 — 에러가 아니라 **조용한 빈 결과**라, 넣었으면 팀원 전원이 "대기열 0건"으로 무증상 오작동했을 것이다. 그래서 C는 dual-source 문자열 치환으로 간다.

## 근거

- 제거 이유("팀원은 각자 fork·jira를 가진다")는 **B·C에만** 성립한다. A(배포처)는 공유 자원, D(인용)는 증거라 이유가 걸리지 않는다 — 그래서 넷을 한 덩어리로 밀지 않는다.
- B의 원천을 gh 로그인으로 잡으면 추가 설정 0개다(자격이 이미 있음). C도 자격 하나(`CUBRID_JIRA_USER` 또는 .netrc)로 분기된다.
- 배포처를 Stage 2에 tw-kang으로 유지하면 팀 공용 org 신설·mid-flight 소유권 이전을 Stage 3까지 미룰 수 있다.

## 이 결정이 바꾸지 않는 것

- 배포처 repo는 Stage 2 내내 `tw-kang/cubrid-agent` public이다 — 매니페스트·설치 명령의 tw-kang은 손대지 않는다.
- few-shot 출처 표기는 verbatim 유지(언어 정책: 인용 리뷰어 코멘트 원문 보존). tw-kang만 지우는 선택적 삭제는 금지.
- gate-pr-submit.sh의 게이트 로직은 이미 owner-무관(브랜치 패턴만 검사) — 에러 메시지 문구의 tw-kang만 중립화한다.

## Consequences

- **Stage 3 이전 시 설치가 다시 막힌다** — CUBRID org private repo는 익명 clone이 안 되므로 `marketplace add`에 gh HTTPS 인증 또는 SSH known_hosts+키가 선행돼야 한다(배경의 그 벽). Stage 3 셋업 문서에 "설치 전 GitHub 자격 준비"를 선행 단계로 넣는다.
- B·C 치환 대상 파일: `setup.sh`, `gate-pr-submit.sh`, `skills/qa/author-testcase/SKILL.md`(+evals), `skills/qa/gate-resolved/SKILL.md`, 그리고 dev 문서 `docs/agents/author-testcase/{CONTEXT,DESIGN,docs/adr/0003}`, `docs/agents/gate-resolved/DESIGN.md`, `docs/agents/test-runner/DESIGN.md`, `docs/deployment.md`, `docs/stage2-hook-gates.md`, `docs/guides/stage2-setup.md`.
- Stage 3에서 자격은 Secret→env라 B는 `CUBRID_GH_FORK`(또는 gh 토큰 계정), C는 `CUBRID_JIRA_USER` 앞 갈래만 쓴다 — dual-source가 자동으로 env 경로로 수렴.

## Considered Options

- **JQL `currentUser()`(C)**: 치환 로직이 아예 불필요해 가장 깔끔하나, 실측상 이 Jira에서 anonymous로 풀려 조용히 0건 — 기각.
- **팀 공용 org 신설 후 거기로 공개(A)**: 개인 종속을 지금 끊고 Stage 3 이전을 org→org로 대칭화. 그러나 org가 없고, Stage 3까지 배포처를 tw-kang으로 둬도 무방 — 기각(park).
- **tw-kang을 전 파일에서 일괄 삭제**: D(인용) 위조·A(매니페스트에 owner 필수) 파손 — 기각.
