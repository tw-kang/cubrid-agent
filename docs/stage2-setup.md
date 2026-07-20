# Stage 2 셋업 — 팀 수동 트리거 (1순위 3종 스킬)

팀원이 **자기 로컬에서** 1순위 3종 스킬(`resolve-gate` · `resolve-next` · `tc-reviewer`)을 기동하기 위한 실전 셋업 가이드. 설계 근거는 [stage2-design.md](./stage2-design.md), 단계 모델은 [staging.md](./staging.md), 파이프라인 지도는 [CONTEXT-MAP.md](../CONTEXT-MAP.md).

> **Stage 2 = "배포"가 아니라 "공유"**. PoC의 로컬 흐름을 팀이 각자 재현하도록 패키징한 것. 검증은 로컬 CTP, **Jira는 읽기 전용**(전이·코멘트는 사람이 수동), 산출은 Draft PR·리포트 초안. k8s·pod·자동 스케줄·Jira 쓰기는 전부 Stage 3.

## 0. 한눈에 — 3종 스킬과 필요 자원

| 스킬 | 역할 | 필요 자원 | 기동 |
|---|---|---|---|
| **resolve-gate** | Resolved(QA to-do) 검토 → 반송/통과 | `cubrid-jira`만 | `/resolve-gate [CBRD-XXXXX]` |
| **resolve-next** | Resolved 이슈 → TC 작성·검증 → Draft PR | `cubrid-jira`·`gh`·CTP·**CUBRID 빌드**·**부품 스킬**·work clone | `/resolve-next [N \| CBRD-XXXXX]` |
| **tc-reviewer** | 열린 SQL TC PR 첫 리뷰 초안 | `gh`·`cubrid-jira`·CTP·**CUBRID 빌드**·work clone | `/tc-reviewer [PR번호]` |

**가벼움→무거움 순**: resolve-gate(읽기 전용, 1분 셋업) < tc-reviewer(로컬 CTP) < resolve-next(로컬 CTP + 부품 스킬). 무거운 두 스킬은 §3의 로컬 CTP 셋업을 공유한다.

## 1. 공통 전제 (모든 스킬)

1. **cubrid-agent repo clone** — 3종 스킬은 `.claude/skills/` 아래에 git으로 공유된다. 이 repo를 clone하고 Claude Code를 이 디렉토리에서 열면 스킬이 인식된다.
   ```bash
   git clone https://github.com/tw-kang/cubrid-agent.git && cd cubrid-agent
   ls .claude/skills/    # resolve-gate  resolve-next  tc-reviewer
   ```
2. **cubrid-jira CLI** — 설치 후 인증(`~/.netrc`에 jira.cubrid.org 자격). 세 스킬 모두 이슈 본문을 읽는다.
   ```bash
   which cubrid-jira || echo "install: ~/.local/bin/cubrid-jira (별도 배포)"
   cubrid-jira search CBRD-25913     # sanity — 본문 markdown이 나오면 OK
   ```
   - ⚠ `show`/`get` 서브커맨드는 **없다**. 읽기는 `search <KEY>`(md) + `comment-list <KEY> --output json`(코멘트) + `jql '<query>' --output json`(대량/본문). **재현 절차가 description이 아니라 comment에만 있는 이슈가 많으니 comment까지 읽어라.**

## 2. resolve-gate 셋업 (가장 가벼움)

읽기 전용이라 **cubrid-jira 하나면 끝**. CTP·CUBRID 빌드·부품 스킬 불필요.

- 기동: `/resolve-gate [CBRD-XXXXX]`(단건) 또는 인자 없이(Select 범위 전체).
- Select 범위(스킬이 자동 적용): PoC=assignee twkang, 팀내=guava Resolved 전체.
- 산출: 게이트 리포트 + 반송(Need Something) 코멘트 **초안**. 실제 전이·게시는 사람이 한다.

## 3. 로컬 CTP 셋업 (resolve-next · tc-reviewer 공유)

두 스킬은 TC를 **실제로 실행**해 검증한다(L3). 아래는 공유 셋업이다.

### 3.1 CUBRID 빌드 (= 신뢰 빌드)
- **반드시 짧은 경로에 설치** — `/home/dev/CUBRID` 같은. Unix 소켓 경로가 108자를 넘으면 broker/master가 안 뜬다(PoC 함정). 깊은 중첩 경로 금지.
- 설치: `sh $CTP_HOME/common/script/run_cubrid_install <build-url>` → `source ~/.cubrid.sh && cubrid_rel`(버전 출력 확인). `run_cubrid_install`은 실패해도 0을 반환할 수 있으니 **버전 출력으로** 확인.
- **빌드는 대상 이슈의 fix를 포함해야 한다.** fix 없는 빌드로 검증하면 `.answer`가 틀린다(false signal). 빌드서버 규칙: `192.168.1.91:8080/REPO_ROOT/store_01/<ver>/drop/...`.
- `resolve-next`의 fail→pass 게이트용 **pre-fix 빌드**(fix 직전 커밋 산출물)도 필요하면 같은 서버에서 받는다.
- **빌드 fix 포함 판정**(tc-reviewer): `cubrid_rel`의 build SHA → `git -C work/cubrid merge-base --is-ancestor <fix-sha> <build-sha>`.

### 3.2 환경 변수 (매 세션)
```bash
export HOME=/home/dev; source /home/dev/.cubrid.sh        # CUBRID=/home/dev/CUBRID
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-...       # ⚠ JDK(javac 포함). JRE 아님 — CTP가 Java SP를 컴파일
export CTP_HOME="$PWD/work/cubrid-testtools/CTP"
[ -x "$JAVA_HOME/bin/javac" ] || echo "JAVA_HOME이 JRE임 — JDK로 고칠 것"
```

### 3.3 CTP + work clone (봇 전용, `~/cubrid-testcases` 불가침)
사용자의 `~/cubrid-testcases`는 건드리지 않는다. 봇은 `work/` 아래 전용 clone을 쓴다.
```bash
git clone https://github.com/CUBRID/cubrid-testtools.git work/cubrid-testtools   # CTP
git clone https://github.com/CUBRID/cubrid-testcases.git work/cubrid-testcases
git -C work/cubrid-testcases remote add twkang https://github.com/tw-kang/cubrid-testcases.git
git clone https://github.com/CUBRID/cubrid.git work/cubrid                        # Ground용(fix diff)
[ -f $CUBRID/lib/libcubrid_all_locales.so ] || sh $CUBRID/bin/make_locale.sh -t 64bit
```
- **CTP conf**: `work/sql.poc.conf` = CTP `sql.conf` 사본에서 `scenario=`를 `work/cubrid-testcases/sql`로 덮은 것. 비기본 포트(1822/33120)를 써 호스트와 충돌하지 않는다. tc-reviewer는 PR 브랜치 worktree를 검증하므로 **conf 사본을 하나 더 만들어 `scenario=`를 worktree로** 덮는다(스킬이 안내).

### 3.4 gh 인증
```bash
gh auth status    # fork=tw-kang, base=CUBRID. PR: tw-kang:<branch> → CUBRID/<repo>:develop
```

### 3.5 resolve-next 전용 — 부품 스킬 (⚠ 배포 blocker)
`resolve-next`는 Author/Verify를 **부품 스킬** `cubrid-sql-tc-create`·`cubrid-sql-tc-verify`에 위임한다. 이들은 현재 **`~/skills/`(미배포 개발 디렉토리)**에만 있다 — 팀원 머신엔 없다.
- 셋업하려면 이 부품 스킬들을 `~/.claude/skills/`(또는 `~/skills`)에 설치해야 한다.
- **부품 스킬 배포 경로는 아직 확정 안 됨**(열린 항목). 확정 전까지 `resolve-next`는 부품 스킬을 갖춘 머신에서만 완전 동작한다. resolve-gate·tc-reviewer는 이 의존이 없다.

## 4. 기동 (스킬별)

```
/resolve-gate  [CBRD-XXXXX]        # Resolved 검토 → 통과/반송 리포트 + 반송 초안
/resolve-next  [N | CBRD-XXXXX]    # 대기열 선두 N건(기본 1) → TC 작성·검증 → Draft PR
/tc-reviewer   [PR번호]            # 열린 SQL TC PR → 3층 리뷰 초안 + 리포트
```
정확한 문구 없이도 자연어로 뜬다("resolve-gate 돌려줘", "이 PR 리뷰해줘", "다음 이슈 tc 작성" 등 — 각 SKILL.md의 트리거 참조).

## 5. 함정 체크리스트 (PoC에서 규명)

| 증상 | 원인 | 대처 |
|---|---|---|
| broker/master 안 뜸, "socket path too long" | CUBRID 설치 경로 108자 초과 | 짧은 경로(`/home/dev/CUBRID`)에 재설치 |
| DB setup 중 `javac not found` | `JAVA_HOME`이 JRE | JDK 루트로 지정(`bin/javac` 존재) |
| CTP `run`이 케이스를 스킵(`Total:1/Success:0/Fail:0`) | `.answer` 파일 없음 | empty-answer 트릭(빈 answer → 실행 → `.result` 승격) |
| fail→pass가 병렬 경로를 안 탐 | `taskset` ≤2코어 → 병렬 disable | **≥4코어**로 실행 |
| 이슈 본문이 비어 보임 | `cubrid-jira search` md가 본문 누락 | `jql --output json` / `comment-list`로 재현 확보 |
| PR 검증이 엉뚱한 브랜치 검사 | conf `scenario=`가 working clone 지시 | conf 사본에서 scenario를 worktree로 덮기 |

## 6. Jira 읽기 전용 (Stage 2 규칙)

세 스킬 모두 **Jira에 쓰지 않는다**. resolve-gate의 전이(Need Something/Start Test)·반송 코멘트, resolve-next의 `Start Test` 전이는 **사람이 초안을 검토한 뒤 수동**으로 한다. 자동 전이·코멘트는 Stage 3.

## 7. 아직 미구현 (구현 예정 — 셋업엔 영향 없음)

stage2-design.md가 설계했으나 아직 코드로 없는 것:
- **hook 하드 게이트**(§3) — fail→pass·결정성 미통과 시 `gh pr create` 차단. 현재는 사람이 게이트 확인.
- **run manifest**(§2) — 게이트 근거 파일. 현재는 리포트로 대체.
- **CCI 교차 검증**(§4) — `run_cci`/`.answer_cci`. 현재는 csql만.

이 셋이 붙기 전까지 Stage 2는 **신뢰된 팀원의 수동 확인**에 의존한다(가드레일 없이도 셋업·기동은 가능).
