# Stage 2 셋업 — 팀 수동 트리거 (1순위 3종 스킬)

팀원이 **자기 로컬에서** 1순위 3종 스킬(`resolve-gate` · `resolve-next` · `tc-reviewer`)을 기동하기 위한 실행 가이드. 구조 정본(자산 3계층·확정 결정)은 [deployment.md](./deployment.md), 설계는 [stage2-design.md](./stage2-design.md), 단계 모델은 [staging.md](./staging.md).

> **Stage 2 = "배포"가 아니라 "공유"**. PoC의 로컬 흐름을 팀이 각자 재현하도록 패키징한 것. 검증은 로컬 CTP, **Jira는 읽기 전용**(전이·코멘트는 사람이 수동), 산출은 Draft PR·리포트 초안. k8s·pod·자동 스케줄·Jira 쓰기는 전부 Stage 3.

## 0. 한눈에 — 3종 스킬과 필요 자원

| 스킬 | 역할 | 필요 자원 | 기동 |
|---|---|---|---|
| **resolve-gate** | Resolved(QA to-do) 검토 → 반송/통과 | `cubrid-jira`+자격만 | `/resolve-gate [CBRD-XXXXX]` |
| **resolve-next** | Resolved 이슈 → TC 작성·검증 → Draft PR | + CTP·CUBRID 빌드·부품 스킬·work clone (= `./setup.sh`) | `/resolve-next [N \| CBRD-XXXXX]` |
| **tc-reviewer** | 열린 SQL TC PR 첫 리뷰 초안 | + CTP·CUBRID 빌드·work clone (= `./setup.sh`) | `/tc-reviewer [PR번호]` |

## 1. 빠른 시작

```bash
git clone https://github.com/tw-kang/cubrid-agent.git && cd cubrid-agent
./setup.sh                        # Tier 2 전부: 부품스킬 clone+심링크, work clone 3종, conf 2종, env 탐지
#  → TODO로 나온 것만 사람이 처리: CLI 설치(§3)·자격(§2)
./setup.sh --build <build-url>    # CTP 검증 스킬(resolve-next·tc-reviewer)을 쓸 때 — 빌드서버 192.168.1.91:8080
source work/agent-env.sh          # CTP를 실행하는 세션마다 (CTP_HOME·JAVA_HOME·.cubrid.sh)
```

- `setup.sh`는 **멱등**(재실행 안전)·**비대화식**이다. 하는 일/안 하는 일 경계는 [deployment.md](./deployment.md)의 3계층 모델: Tier 2(머신 상태)는 스크립트가, Tier 3(자격)는 사람이.
- resolve-gate만 쓸 거면 `cubrid-jira` + 자격이면 충분 — `--build` 불필요.
- 부품 스킬(`cubrid-sql-tc-create/verify`)은 `tw-kang/skills` repo에서 clone+심링크로 설치된다([ADR 0010](./adr/0010-part-skills-boundary.md)). 갱신은 `./setup.sh` 재실행(내부에서 `git pull`).

## 2. 자격 (Tier 3 — 사람만, repo·스크립트에 넣지 않는다)

표준은 **환경변수**(Stage 3 k8s Secret과 같은 형식), Stage 2에선 파일 방식 병행 허용:

```bash
export CUBRID_JIRA_USER="..."; export CUBRID_JIRA_PASSWORD="..."   # 표준 (또는 ~/.netrc: machine jira.cubrid.org, chmod 600)
gh auth login                                                       # 또는 GH_TOKEN. fork=tw-kang, base=CUBRID
```

## 3. CLI 수동 설치 (sudo 필요 — setup.sh는 확인·안내만)

1. **cubrid-jira** ([github.com/vimkim/cubrid-jira](https://github.com/vimkim/cubrid-jira)) — 전제: **Python 3.14+**, **pandoc**.
   ```bash
   sudo dnf install -y pandoc          # Debian/Ubuntu: sudo apt install pandoc  /  macOS: brew install pandoc
   # (uv가 없으면) curl -LsSf https://astral.sh/uv/install.sh | sh
   uv tool install git+https://github.com/vimkim/cubrid-jira.git    # 대안: pipx install git+…  (⚠ pip install -e . 금지)
   cubrid-jira search CBRD-25913       # sanity — 본문 markdown이 나오면 OK
   ```
   - ⚠ `show`/`get` 서브커맨드는 **없다**. 읽기는 `search <KEY>`(md) + `comment-list <KEY> --output json`(코멘트) + `jql '<query>' --output json`(대량/본문). **재현 절차가 comment에만 있는 이슈가 많으니 comment까지 읽어라.** 갱신 `uv tool upgrade cubrid-jira`.
2. **gh** — Rocky/RHEL 8 계열(dnf). Debian/Ubuntu는 apt, 그 외 [cli.github.com/manual](https://cli.github.com/manual) 참조.
   ```bash
   sudo dnf install -y 'dnf-command(config-manager)'
   sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
   sudo dnf install -y gh
   ```

## 4. 기동 (스킬별)

```
/resolve-gate  [CBRD-XXXXX]        # Resolved 검토 → 통과/반송 리포트 + 반송 초안
/resolve-next  [N | CBRD-XXXXX]    # 대기열 선두 N건(기본 1) → TC 작성·검증 → Draft PR
/tc-reviewer   [PR번호]            # 열린 SQL TC PR → 3층 리뷰 초안 + 리포트
```
정확한 문구 없이도 자연어로 뜬다("resolve-gate 돌려줘", "이 PR 리뷰해줘", "다음 이슈 tc 작성" 등 — 각 SKILL.md의 트리거 참조).

## 5. 함정 체크리스트 (PoC에서 규명 — setup.sh가 대부분 선처리, 진단용으로 유지)

| 증상 | 원인 | 대처 |
|---|---|---|
| broker/master 안 뜸, "socket path too long" | CUBRID 설치 경로 108자 초과 | 짧은 경로(`$HOME/CUBRID` — setup 규약)에 재설치 |
| DB setup 중 `javac not found` | `JAVA_HOME`이 JRE | `source work/agent-env.sh`(setup이 JDK 탐지) |
| CTP `run`이 케이스를 스킵(`Total:1/Success:0/Fail:0`) | `.answer` 파일 없음 | empty-answer 트릭(빈 answer → 실행 → `.result` 승격) |
| fail→pass가 병렬 경로를 안 탐 | `taskset` ≤2코어 → 병렬 disable | **≥4코어**로 실행 |
| 이슈 본문이 비어 보임 | `cubrid-jira search` md가 본문 누락 | `jql --output json` / `comment-list`로 재현 확보 |
| PR 검증이 엉뚱한 브랜치 검사 | conf `scenario=`가 working clone 지시 | conf 사본에서 scenario를 worktree로 덮기(tc-reviewer가 안내) |

## 6. Jira 읽기 전용 (Stage 2 규칙)

세 스킬 모두 **Jira에 쓰지 않는다**. resolve-gate의 전이(Need Something/Start Test)·반송 코멘트, resolve-next의 `Start Test` 전이는 **사람이 초안을 검토한 뒤 수동**으로 한다. 자동 전이·코멘트는 Stage 3.

## 7. 구현 상태

- **setup.sh**(Tier 2 자동화) — ✅ 구현. 멱등·비대화식·`$HOME` 규약, `--build <url>` 옵션, Stage 3 컨테이너 재사용 가능(D5). 이 머신 실측: 전 항목 OK.
- **부품 스킬 전달** — ✅ 해소. ~~미배포 blocker~~ → `tw-kang/skills` clone+심링크([ADR 0010](./adr/0010-part-skills-boundary.md)). 심링크 직후 세션에서 스킬 인식 확인.
- **hook 하드 게이트**([`.claude/hooks/`](../.claude/hooks/)) — ✅ 구현. `gate-pr-submit`(제출 차단)·`lint-sql-tc`(린트→manifest)·`gate-stop`(리마인드).
- **run manifest** — ✅ 구현. `work/CBRD-XXXXX/manifest.json`, 스키마 [`.claude/hooks/manifest.example.json`](../.claude/hooks/manifest.example.json).
- **CCI 교차 검증**(resolve-next Verify step 5) — ✅ 구현. `sql_by_cci.poc.conf`(setup이 생성)로 `run_cci`, csql과 다르면 `.answer_cci`.

hook은 **신뢰된 팀원의 실수 방지 가드레일**(적대적 우회 방지 아님) — 자세히 [`.claude/hooks/README.md`](../.claude/hooks/README.md).
