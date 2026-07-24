# Domain Docs

엔지니어링 스킬이 이 repo의 코드베이스를 탐색할 때 도메인 문서를 어떻게 소비해야 하는지.

레이아웃: **다중 컨텍스트(multi-context)**. 이 repo는 CBRD 이슈 워크플로의 각 상태 전이를 맡는 에이전트들의 모노레포이며, 루트 `CONTEXT-MAP.md`가 에이전트(=컨텍스트)별 문서를 가리킨다. 성격 3분법과 근거는 [ADR 0012](../adr/0012-doc-tree-by-nature.md), [ADR 0008](../adr/0008-monorepo-agents.md).

## 탐색 전에 읽을 것

- **`CONTEXT-MAP.md`** (루트) — 컨텍스트(에이전트) 지도. 다룰 주제와 관련된 에이전트의 `CONTEXT.md`를 각각 읽는다.
- **`docs/agents/<name>/CONTEXT.md`** — 에이전트별 컨텍스트·용어. (예: `docs/agents/tc-author/CONTEXT.md`)
- **`docs/adr/`** — 시스템 전역 결정. 작업할 영역에 닿는 ADR을 읽는다.
- **`docs/agents/<name>/docs/adr/`** — 해당 에이전트 전용 결정. 그 에이전트를 건드릴 때 함께 본다.

이 파일들이 없으면 **조용히 진행**한다. 부재를 지적하거나 미리 만들자고 제안하지 말 것. `/domain-modeling` 스킬(`/grill-with-docs`·`/improve-codebase-architecture` 경유)이 용어·결정이 실제로 확정될 때 lazy하게 만든다.

## 파일 구조 (이 repo의 실제 레이아웃)

```
/
├── CONTEXT-MAP.md                         ← 컨텍스트(에이전트) 지도 = 진입점
├── docs/
│   ├── adr/                               ← 시스템 전역 결정
│   │   ├── 0007-rollout-stages.md
│   │   ├── 0008-monorepo-agents.md
│   │   └── 0012-doc-tree-by-nature.md
│   └── agents/
│       ├── tc-author/
│       │   ├── CONTEXT.md                 ← 컨텍스트별 용어·설계 기록
│       │   ├── DESIGN.md
│       │   └── docs/adr/                  ← 컨텍스트별 결정
│       ├── resolve-gate/CONTEXT.md
│       ├── tc-reviewer/CONTEXT.md
│       ├── test-runner/CONTEXT.md
│       └── close-backport/CONTEXT.md
└── .claude/                               ← 실행 계약(스킬·연료·hook) — 배포되는 전부
```

> 일반적인 Matt Pocock 레이아웃은 컨텍스트를 `src/<context>/`에 두지만, 이 repo는 코드가 아니라 에이전트 설계 문서를 다루므로 컨텍스트를 `docs/agents/<name>/`에 둔다(ADR 0012의 문서 트리 성격 3분법). ADR 번호는 **전역 유일 단일 시퀀스** — 새 번호 부여 전 전역(`docs/adr/`)과 에이전트별(`docs/agents/<name>/docs/adr/`) 시퀀스를 모두 확인한다(`CONTEXT-MAP.md`의 "ADR 번호 규칙").

## 용어(glossary)의 어휘를 쓴다

출력이 도메인 개념을 이름지을 때(이슈 제목, 리팩터 제안, 가설, 테스트 이름) `CONTEXT-MAP.md`의 승격 용어표와 해당 에이전트 `CONTEXT.md`에 정의된 용어를 쓴다. 용어표가 명시적으로 피하는 동의어로 흘러가지 말 것. 여러 에이전트가 공유하는 용어는 `CONTEXT-MAP.md`로 승격한다.

필요한 개념이 아직 용어표에 없다면 그것도 신호다 — 프로젝트가 안 쓰는 언어를 지어내고 있거나(재고), 진짜 공백이 있거나(`/domain-modeling`에 기록).

## ADR 충돌은 드러낸다

출력이 기존 ADR과 모순되면 조용히 덮지 말고 명시적으로 드러낸다:

> _ADR-0012(문서 트리 성격 3분법)와 모순 — 그래도 다시 열어볼 가치가 있는 이유는…_
