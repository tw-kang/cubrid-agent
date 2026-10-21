# Domain Docs

엔지니어링 스킬이 이 repo를 탐색할 때 도메인 문서를 어떻게 소비하는지.

레이아웃: **단일 컨텍스트(single-context)** — 용어집은 루트 `GLOSSARY.md` 하나이고 `GLOSSARY-MAP.md`는 없다. 이 repo는 CBRD 이슈 워크플로의 각 상태 전이를 맡는 에이전트들의 모노레포다. 단, **에이전트별 상세 설계는 repo가 아니라 Jira(CUBRIDQA)에 산다** — repo=제품, 설계=Jira(CUBRIDQA-1454).

## ADR을 만들지 않는다

**ADR을 만들지 않는다. 결정의 이유는 Jira에 둔다.** `/domain-modeling`이나 `/grill-with-docs`가 ADR을 쓰려 하면, 대신 지도에 결정 티켓을 올린다([`issue-tracker.md`](./issue-tracker.md)의 "새로 드러난 결정"). `.agents/`와 ADR 디렉토리(`docs/adr/` 등)는 `check-invariants.sh`가 막는다. 결정이 남긴 규칙은 기계가 판정할 수 있으면 check에, 아니면 이 디렉토리(`docs/agents/`)나 `AGENTS.md`에 둔다.

## 탐색 전에 읽을 것

- **루트 `GLOSSARY.md`** — 공유 용어집.
- **`docs/pipeline.md`** — 파이프라인 지도 + 에이전트 로스터. 로스터가 링크하는 CUBRIDQA 티켓에 에이전트 상세 설계가 있다. `cubrid-jira`로 읽는다.

이 파일들이 없으면 **조용히 진행**한다. 부재를 지적하거나 미리 만들자고 제안하지 말 것. `/domain-modeling` 스킬(`/grill-with-docs`·`/improve-codebase-architecture` 경유)이 용어가 실제로 확정될 때 `GLOSSARY.md`를 lazy하게 고친다.

## 파일 구조

레이아웃의 정본은 [`AGENTS.md`](../../AGENTS.md)의 "저장소 배치" 절이다. `src/<context>/`는 없다.

## 용어(glossary)의 어휘를 쓴다

출력이 도메인 개념을 이름지을 때(이슈 제목, 리팩터 제안, 가설, 테스트 이름) 루트 `GLOSSARY.md`의 용어집 어휘를 쓴다. 용어표가 명시적으로 피하는 동의어로 흘러가지 말 것. 여러 에이전트가 공유하는 용어는 `GLOSSARY.md`로 승격한다.

필요한 개념이 아직 용어표에 없다면 그것도 신호다 — 프로젝트가 안 쓰는 언어를 지어내고 있거나(재고), 진짜 공백이 있거나(`/domain-modeling`에 기록).

## 결정 충돌은 드러낸다

출력이 기록된 결정(Jira, 지도의 결정 티켓)과 모순되면 조용히 덮지 말고 명시적으로 드러낸다:

> _CUBRIDQA-1454(repo=제품·설계=Jira)와 모순 — 그래도 다시 열어볼 가치가 있는 이유는…_
