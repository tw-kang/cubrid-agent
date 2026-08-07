# `main`은 릴리스, `develop`은 개발 — 작업 티켓은 GitHub Issues로 옮긴다

## 경고 — 범프 커밋은 반드시 `develop`을 경유한다

기존 설치자의 마켓플레이스 clone은 **shallow clone**이고 브랜치를 하나만 받는다. 그 하나는 clone 시점의 default branch다. 그때 default는 `develop`이었다. 그래서 default branch를 `main`으로 바꿔도 그들의 clone은 계속 `develop`을 추적한다.

따라서 **버전 범프 커밋은 `develop`에 먼저 올라간 뒤 `main`으로 간다.** 순서를 뒤집으면 기존 설치자에게 새 버전이 보이지 않는다. 오류도 경고도 없이 그들의 자동 갱신만 멈춘다. 이 아래의 모든 결정은 이 순서를 깨지 않는 선에서 성립한다.

## 배경

브랜치가 `develop` 하나였고, 커밋을 거기에 직접 쌓았다. 그래서 이력이 비대하고, 지금 릴리스로 나가 있는 상태를 가리키는 이름이 없다.

티켓도 한 곳에 몰렸다. CUBRIDQA Jira는 2계층이다. 스펙이 이미 sub-task이면 그 아래에 작업 티켓을 달 수 없다. 그래서 작업 기록이 전부 코멘트로 쌓였다. 부모 트리는 31건이 됐다([`.agents/issue-tracker.md`](../issue-tracker.md)).

## 결정

**브랜치 둘.** `main` = 릴리스, `develop` = 개발. GitHub default branch를 `main`으로 바꾼다. 작업 브랜치는 `cubridqa-XXXX/<slug>`이고 base는 `develop`이다. 릴리스 절차 자체는 [ADR 0007](./0007-versioning-and-releases.md)이 소유한다.

**브랜치 보호는 이 값으로 건다.**

| 브랜치 | 거는 것 |
|---|---|
| `develop` | required status check `validate`, linear history 요구, 관리자 우회 허용, force push·삭제 금지 |
| `main` | PR 필수(승인 0건), required status check `validate`, force push·삭제 금지 |

linear history 요구가 `develop`의 머지 커밋을 막는다. rebase 머지도 linear history를 만족하므로 repo 설정에서 rebase 머지를 끈다. 그래서 squash가 **설정으로** 강제된다. 산문 규약으로 부탁하지 않는다. `develop`에만 관리자 우회를 허용하는 이유는 하나다 — 릴리스 범프 커밋이 `develop`에 직접 push되기 때문이다. 우회를 막으면 릴리스가 자기 규칙에 막힌다.

**트래커 둘.** 스펙은 Jira sub-task로 남는다(현행 유지). 작업 티켓은 **GitHub Issues**로 옮기고, 그 본문에서 Jira 키를 링크한다.

**PR은 스펙이 있는 일에만 낸다.** Jira 스펙이 있는 일은 작업 브랜치에서 `develop`으로 squash PR을 내고, 사람이 머지한다. **GitHub Issue만 있는 일은 PR을 내지 않는다** — `develop`에 직접 커밋하고, 커밋 제목이 `[#NN]`으로 그 이슈를 가리킨다. 일이 끝나면 `gh issue close`로 닫는다. PR은 심사받을 것이 있을 때 쓰는 도구이지 모든 커밋이 통과하는 관문이 아니다.

**제목 규약.** PR 제목은 대괄호로 감싼 Jira 키로 시작한다 — PR은 스펙이 있는 일에만 나므로 그 키가 항상 있다. 커밋 제목은 **그 일을 소유한 티켓**으로 시작한다: GitHub Issue가 소유하면 `[#NN]`, 스펙 구현이면 Jira 키다. PR을 거치는 경로는 squash이므로 스펙 하나가 `develop` 커밋 하나가 된다.

**경고 — 작업 티켓은 손으로 닫는다.** GitHub 자동 닫기는 default branch로 머지될 때만 작동한다. 작업 PR은 `develop`으로 머지되므로 본문에 `Closes #NN`을 써도 이슈가 열린 채 남는다. 그래서 티켓은 PR 머지 시점에 `gh issue close`로 닫는다.

**사람이 보는 자리.** 배포면을 건드리는 PR은 사람의 머지 지시를 기다린다. 그 밖의 PR은 에이전트가 자율 머지한다. PR이 없는 경로(GitHub Issue만 있는 일)에서는 **릴리스 PR이 그 자리다** — `develop`→`main`은 사람이 머지하고, 배포면은 그 머지로만 나간다. 즉 사람의 게이트는 커밋 경계가 아니라 **배포 경계**에 있다.

이것은 **절차 규칙이고 GitHub 설정이 아니다.** GitHub은 본인 PR의 본인 승인을 허용하지 않는다. 이 repo는 유지보수자가 1인이다. 그래서 승인 필수 설정을 걸면 배포면 PR이 아니라 **모든 PR**이 영구히 막힌다. CODEOWNERS도 같은 이유로 성립하지 않는다 — 지정된 소유자가 자기 PR의 리뷰어가 될 수 없다. 기계로 강제할 수단이 없으므로, 규칙을 에이전트가 읽는 자리([`AGENTS.md`](../../AGENTS.md))에 둔다.

**부트스트랩 예외.** 이 결정 자체의 구현은 직접 커밋으로 실었다. 규칙과 그 규칙을 검사하는 CI가 같은 변경 안에 있어서, 그 PR을 심사할 기준이 아직 머지되지 않은 상태였다. PR 흐름은 다음 작업인 **CUBRIDQA-1507부터** 적용한다.

## 근거

- **릴리스 상태에 이름이 생긴다.** `main`을 default로 두면 repo를 처음 여는 사람과 `npx skills add` 사용자가 검증된 릴리스를 먼저 받는다. 미검증 HEAD가 기본값이 아니게 된다.
- **작업 티켓이 코드와 같은 도구에 산다.** PR·커밋·이슈가 서로를 참조하고, 닫히는 시점이 머지 시점과 같다. Jira에는 스펙만 남으므로 트리를 읽는 비용이 준다.
- **경계가 한 문장으로 읽힌다.** 왜 바꾸나(스펙)는 Jira, 무엇을 하나(작업)는 GitHub이다.

## 이 결정이 바꾸지 않는 것

- **스펙은 여전히 Jira에 산다.** repo=제품, 설계=Jira는 [ADR 0005](./0005-repo-is-product-design-lives-in-jira.md) 그대로다. GitHub Issues가 흡수하는 것은 작업 단위뿐이다.
- **CUBRID 사내 PR 규칙**(제목 영문, 본문 한글·사용자 관점, 템플릿 절 구성)은 그대로다.
- **대상 repo로 나가는 TC PR**은 이 결정의 범위 밖이다. 그쪽 base는 `CUBRID/<repo>:develop`이고 티켓도 CBRD다.

## Considered Options

- **`develop` 하나만 유지**: 변경이 0이고 기존 설치자의 추적 대상도 그대로다. 그러나 릴리스된 상태를 가리키는 브랜치가 없어, 지금 나가 있는 것을 보려면 태그를 되짚어야 한다. 새 clone과 npx 채널이 미검증 HEAD를 받는 문제도 남는다. 기각.
- **작업 티켓도 Jira에 둔다**: 트래커가 하나로 남아 이동 비용이 없다. 그러나 2계층 제약이 그대로라, 스펙 sub-task 아래에 작업을 달 수 없다. Task를 형제로 만들고 link하는 우회는 이미 쓰고 있고, 그것이 트리를 31건으로 부풀린 방식이다. 기각.
- **default는 `develop`에 두고 릴리스 브랜치만 추가**: 위 경고의 위험을 아예 만들지 않는다. 그러나 목적의 절반을 버린다 — 처음 오는 사람과 npx 채널이 여전히 미검증 HEAD를 본다. 위험은 default 전환 자체가 아니라 범프 경로에 있고, 그것은 순서 규칙 한 줄로 막힌다. 기각.

## Consequences

- GitHub 설정 변경 4건(default branch, rebase 머지 끄기, `develop` 보호, `main` 보호)이 생긴다. 오프라인 테스트가 불가능하므로 각 변경 직후 `gh api` readback으로 값을 확인한다.
- 기존 설치자는 아무것도 하지 않는다. `develop` 추적이 유지되므로 자동 갱신이 계속된다.
- 새 작업은 GitHub Issue 하나로 시작한다. Jira에 새로 생기는 것은 스펙 sub-task뿐이다.
- 운영 규약(브랜치명·제목 형식·머지 지시)은 [`AGENTS.md`](../../AGENTS.md)가, 두 트래커의 경계는 [`.agents/issue-tracker.md`](../issue-tracker.md)가 적는다. 에이전트는 그 둘을 읽는다.
- 티켓: CUBRIDQA-1508.
