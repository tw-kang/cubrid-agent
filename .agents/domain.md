# Domain Docs

엔지니어링 스킬이 이 repo를 탐색할 때 도메인 문서를 어떻게 소비하는지.

레이아웃: **다중 컨텍스트(multi-context)**. 이 repo는 CBRD 이슈 워크플로의 각 상태 전이를 맡는 에이전트들의 모노레포다. 단, **에이전트별 상세 설계는 repo가 아니라 Jira(CUBRIDQA)에 산다** — repo=제품, 설계=Jira([ADR 0005](./adr/0005-repo-is-product-design-lives-in-jira.md); 모노레포 근거 ADR 0008 = CUBRIDQA-1425).

## 탐색 전에 읽을 것

- **루트 `CONTEXT.md`** — 단일 오리엔테이션 + 공유 용어집 + 파이프라인 지도 + 에이전트 로스터(각자의 설계 티켓 링크).
- **에이전트 상세 설계** — 대응 CUBRIDQA 티켓(gate-resolved→1440, author-testcase→1429, review-testcase→1441, test-runner→1444). `cubrid-jira`로 읽는다.
- **`.agents/adr/`** — 제품·저장소 형태 결정(thin ADR `0001`–`0005`). 작업 영역에 닿는 것을 읽는다.
- **`.agents/`** 규범 — `design-principles.md`·`issue-tracker.md`·`triage-labels.md`·이 문서.
- **`docs/`** — 사람용 런북(`setup`·`deployment`·`dev-process`).

이 파일들이 없으면 **조용히 진행**한다. 부재를 지적하거나 미리 만들자고 제안하지 말 것. `/domain-modeling` 스킬(`/grill-with-docs`·`/improve-codebase-architecture` 경유)이 용어·결정이 실제로 확정될 때 lazy하게 만든다.

## 파일 구조 (이 repo의 실제 레이아웃)

```
/
├── CONTEXT.md                 ← 단일 용어집 + 파이프라인 지도 = 진입점
├── .agents/
│   ├── adr/                   ← 제품·저장소 형태 결정 (thin, 0001–0005)
│   ├── design-principles.md
│   ├── issue-tracker.md  triage-labels.md  domain.md
├── docs/                      ← 사람용 런북 (setup·deployment·dev-process)
└── .claude-plugin/ · skills/qa/ · hooks/ · scripts/   ← 제품(배포되는 전부)

# 에이전트 상세 설계(DESIGN·방법론 ADR)는 repo가 아니라 Jira(CUBRIDQA) 티켓에 산다.
```

> 일반적인 Matt Pocock 레이아웃은 컨텍스트를 `src/<context>/`에 두지만, 이 repo는 에이전트 설계를 **Jira로 옮겼다**(ADR 0005). repo에는 제품 + 오리엔테이션(`CONTEXT.md`) + 규범(`.agents/`) + 런북(`docs/`)만 남는다. ADR은 제품·저장소 형태 결정만 `.agents/adr/`에 thin하게 둔다.

## 용어(glossary)의 어휘를 쓴다

출력이 도메인 개념을 이름지을 때(이슈 제목, 리팩터 제안, 가설, 테스트 이름) 루트 `CONTEXT.md`의 용어집 어휘를 쓴다. 용어표가 명시적으로 피하는 동의어로 흘러가지 말 것. 여러 에이전트가 공유하는 용어는 `CONTEXT.md`로 승격한다.

필요한 개념이 아직 용어표에 없다면 그것도 신호다 — 프로젝트가 안 쓰는 언어를 지어내고 있거나(재고), 진짜 공백이 있거나(`/domain-modeling`에 기록).

## ADR 충돌은 드러낸다

출력이 기존 ADR과 모순되면 조용히 덮지 말고 명시적으로 드러낸다:

> _ADR-0005(repo=제품·설계=Jira)와 모순 — 그래도 다시 열어볼 가치가 있는 이유는…_
