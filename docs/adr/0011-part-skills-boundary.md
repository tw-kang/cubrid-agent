# 부품 스킬은 tw-kang/skills 정본을 유지하고 clone+심링크로 전달한다

tc-author의 Author/Verify가 위임하는 부품 스킬(`cubrid-sql-tc-create`/`-verify`)은 cubrid-agent 밖의 **발행된 repo `tw-kang/skills`**(9카테고리×create/verify, `npx skills add` 채널 보유)에 있다. 팀 배포 시 이를 어떻게 전달할지 — cubrid-agent로 편입, git submodule, 채널 연결 — 중 **채널 연결(clone+심링크)**을 택한다: `setup.sh`가 `~/skills`를 clone/pull하고 필요한 스킬만 `~/.claude/skills/`에 심링크한다.

- **정본 분열 방지**: skills repo는 9카테고리의 단일 정본이고 자주 갱신된다(마이닝 반영 커밋 등). SQL 2종만 cubrid-agent로 편입하면 이중 소스가 되고, shell/CCI 카테고리 확장 때마다 재편입해야 한다.
- **갱신 = `git pull` 하나**: 심링크라 skills repo를 당기면 즉시 반영된다. `npx skills add`(복사 설치)는 갱신마다 재실행이 필요하고 Node 18+ 의존이 생긴다 — 스킬이 빠르게 진화하는 현 단계에 불리.
- **submodule은 이중화**: clone-follows이긴 하나 재귀 clone·포인터 갱신 마찰이 있고, 이미 있는 배포 채널(git repo)과 역할이 겹친다.
- **검증된 형태**: 개발 머신이 이미 이 구조(`~/skills` clone)로 PoC를 통과했다.

## Consequences

- cubrid-agent는 외부 repo(tw-kang/skills) 가용성에 의존한다 — Stage 3 이미지는 빌드 시점에 clone을 bake해 런타임 의존을 없앤다.
- `~/.claude/skills`의 심링크는 사용자 전역이라 다른 프로젝트 세션에서도 부품 스킬이 보인다(부작용 아님 — 단독 사용도 유효한 유스케이스).
- skills repo의 파괴적 변경이 cubrid-agent 파이프라인을 깰 수 있다 — 신뢰된 단일 팀이 양쪽을 관리하는 동안은 수용; 분리 소유가 되면 버전 pin(태그 checkout)을 재논의.
- `docs/stage2-setup.md`의 "부품 스킬 미배포 blocker" 서술은 이 결정으로 해소·정정된다.
