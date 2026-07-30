# Stage 2 셋업 — 팀 수동 트리거 (1순위 3종 스킬)

팀원이 **자기 로컬에서** 1순위 3종 스킬(`gate-resolved` · `author-testcase` · `review-testcase`)을 기동하기 위한 실행 가이드. 구조 정본(자산 3계층·확정 결정)은 [deployment.md](./deployment.md), 단계 모델은 staging.md (CUBRIDQA-1425).

> **Stage 2 = "배포"가 아니라 "공유"**. PoC의 로컬 흐름을 팀이 각자 재현하도록 패키징한 것. 검증은 로컬 CTP, **Jira 쓰기는 호출 의도로 게이팅**한다 — 사람이 키를 나열한 targeted 호출은 전이·코멘트·필드를 실제로 쓰고, JQL/큐로 만든 batch 호출은 초안 유지(오탐 가드가 걸리면 targeted여도 초안+@질의로 강등). 머지/승인과 무인 자동 호출은 여전히 사람/Stage 3. k8s·pod·자동 스케줄·무인 batch 쓰기는 전부 Stage 3. See ADR-0016 (CUBRIDQA-1440).

## 0. 한눈에 — 3종 스킬과 필요 자원

| 스킬 | 역할 | 필요 자원 | 기동 |
|---|---|---|---|
| **gate-resolved** | Resolved(QA to-do) 검토 → 반송/통과 | `cubrid-jira`+자격만 | `/cubrid-agent:gate-resolved [CBRD-XXXXX]` |
| **author-testcase** | Resolved 이슈 → TC 작성·검증 → PR(targeted=ready, batch=Draft) | + CTP·CUBRID 빌드·`$HOME` 자산 (= `/cubrid-agent:setup-cubrid-agent`) | `/cubrid-agent:author-testcase [N \| CBRD-XXXXX]` |
| **review-testcase** | 열린 SQL TC PR 첫 리뷰(targeted=코멘트 게시) | + CTP·CUBRID 빌드·`$HOME` 자산 (= `/cubrid-agent:setup-cubrid-agent`) | `/cubrid-agent:review-testcase [PR번호]` |

> 플러그인 스킬 이름에는 **플러그인 이름이 앞에 붙는다** — 정식 호출명은 `/cubrid-agent:<스킬>`이고 자동완성에 뜨는 것도 이 형태다. 앞을 뗀 `/<스킬>`도 같은 스킬을 부르지만, 같은 이름을 이미 쓰는 커맨드가 있으면 그쪽이 먼저 잡힌다. `npx skills add`로 깐 경우엔 접두어가 없어 `/<스킬>`이 정식이다.

## 1. 빠른 시작

**권장(플러그인 사용자)** — 설치 후 `/cubrid-agent:setup-cubrid-agent`가 프로비저닝·자격까지 안내한다:

```
claude plugin marketplace add tw-kang/cubrid-agent
claude plugin install cubrid-agent@cubrid-agent
/cubrid-agent:setup-cubrid-agent  # 설치 후 세션에서 한 번 — Tier 2 자동 + TODO(자격·CLI) 안내 + 스킬별 준비도 리포트
source ~/.cubrid-agent/env.sh     # CTP를 실행하는 세션마다 (CTP_HOME·JAVA_HOME·CUBRID_JIRA_USER·.cubrid.sh)
```

**repo 개발자(직접 실행)** — 진입점 스킬을 거치지 않고 정본 스크립트를 바로 돌린다:

```bash
git clone https://github.com/tw-kang/cubrid-agent.git && cd cubrid-agent
bash skills/qa/setup-cubrid-agent/scripts/setup.sh              # Tier 2 전부($HOME 표준). TODO는 사람이 처리(§2·§3)
bash skills/qa/setup-cubrid-agent/scripts/setup.sh --build <url> # CTP 검증 스킬용 — 빌드서버 192.168.1.91:8080
```

- setup 스크립트는 **멱등**(재실행 안전)·**비대화식**이며 CWD 비의존이다(정본은 setup-cubrid-agent 스킬 안, 루트 래퍼 없음 — [ADR 0003](../.agents/adr/0003-setup-entrypoint-skill.md)). 하는 일/안 하는 일 경계는 [deployment.md](./deployment.md)의 3계층: Tier 2(머신 상태)는 스크립트가, Tier 3(자격)는 사람이.
- gate-resolved만 쓸 거면 `cubrid-jira` + 자격이면 충분 — `--build` 불필요. 단 **Jira 사용자명이 해석돼 있어야** 대기열 JQL이 동작한다: `export CUBRID_JIRA_USER=<계정>` 하거나 `/cubrid-agent:setup-cubrid-agent`를 한 번 돌려 `env.sh`가 내보내게 한다(ADR 0004). 값이 없으면 스킬은 0건을 보고하지 않고 중단한다.
- 부품 스킬은 이 repo의 `skills/qa/`에 **소스로 들어 있다**(흡수 — [ADR 0001](../.agents/adr/0001-repackage-as-plugin.md)). 별도 clone·심링크는 불필요하지만, **플러그인이 로드하는 건 `plugin.json`에 적힌 6종뿐**이다(setup + 파이프라인 5종). 기본 `skills/` 스캔은 한 단계만 보므로 `skills/qa/<이름>/`은 자동 발견되지 않는다 — 부품 16종을 쓰려면 `npx skills add tw-kang/cubrid-agent -s <이름>`으로 따로 깐다. 어떤 설치본이 실제로 무엇을 로드했는지는 `claude plugin details cubrid-agent`로 확인한다(6종 = 세션당 상시 ~1,185 tok).

### 최신본 유지 — 설치는 한 번, 이후는 자동

**한 번 설치하면 자동으로 최신이 된다.** Claude Code가 세션 시작 뒤(최대 10분 지연) 마켓플레이스와 설치된 플러그인을 배후에서 갱신하고, 갱신되면 `/reload-plugins` 안내가 뜨거나 다음 실행에 적용된다.

단 **서드파티 마켓플레이스는 자동 갱신이 기본 꺼져 있다.** 그래서 `/cubrid-agent:setup-cubrid-agent`가 `~/.claude/settings.json`의 `extraKnownMarketplaces["cubrid-agent"].autoUpdate` 를 **켜 준다**(멱등, 백업 `settings.json.bak`). 수동으로 켜려면 `/plugin` → Marketplaces → cubrid-agent → **Enable auto-update**.

밟기 쉬운 함정 둘:

| 하는 일 | 결과 |
|---|---|
| `claude plugin marketplace update cubrid-agent` | **카탈로그만** 새로 받는다 — 설치본은 그대로인데 "성공"이라고 보고한다 |
| `claude plugin update cubrid-agent` | ✘ `Plugin not found` — 이름을 정규화해야 한다 |
| `claude plugin update cubrid-agent@cubrid-agent` | ✔ 설치본 교체(fetch까지 수행). **재시작 또는 `/reload-plugins` 후 적용** |

즉 자동 갱신이 꺼진 상태로 오래 쓰면 옛 스킬이 돌면서도 눈치채기 어렵다. 실제 로드되는 위치는 마켓플레이스 clone이 아니라 버전으로 고정된 캐시(`~/.claude/plugins/cache/cubrid-agent/cubrid-agent/<커밋SHA>/`)이고, 어느 버전을 쓰는지는 `claude plugin list` 또는 `~/.claude/plugins/installed_plugins.json`으로 확인한다.

> ⚠️ `.claude-plugin/plugin.json`에 `version`을 **넣지 마라**. 생략하면 git 커밋 SHA가 버전이 되어 **매 커밋이 새 버전**으로 감지된다. semver를 넣는 순간 그 값을 올리지 않는 한 새 커밋이 전달되지 않는다.

## 2. 자격 (Tier 3 — 사람만, repo·스크립트에 넣지 않는다)

표준은 **환경변수**(Stage 3 k8s Secret과 같은 형식), Stage 2에선 파일 방식 병행 허용:

```bash
export CUBRID_JIRA_USER="..."; export CUBRID_JIRA_PASSWORD="..."   # 표준 (또는 ~/.netrc: machine jira.cubrid.org, chmod 600)
gh auth login                                                       # 또는 GH_TOKEN. fork=각자 gh 계정(ADR 0004), base=CUBRID
```

## 3. CLI 수동 설치 (sudo 필요 — setup.sh는 확인·안내만)

1. **cubrid-jira** ([github.com/vimkim/cubrid-jira](https://github.com/vimkim/cubrid-jira)) — 전제: **Python 3.14+**, **pandoc 2.19 이상**.

   > ⚠️ **배포판 pandoc을 쓰지 마라.** Rocky/RHEL 8의 `dnf install pandoc`은 **2.0.6**을 주는데, 이 버전엔 `jira` reader/writer가 **둘 다 없다**. writer가 없으면 markdown 본문을 넣는 **쓰기(`update`·`comment`)가 하드 실패**한다. reader가 없으면 읽기는 CLI 버전에 갈린다 — **2026-07-30 이전 설치본은 이슈 본문이 에러 없이 빈칸으로** 나오고(셋업은 통과했다고 보고하고 에이전트는 아무 내용 없이 판정한다), 그 이후 설치본은 경고 한 줄과 함께 **Jira 마크업 원문**으로 폴백한다. 최소 2.19인 이유: 2.9.1은 reader·writer가 있지만 쓰기에서 **마크다운 표의 헤더 행을 버린다**(실측). 상세는 CUBRIDQA-1473·1478.

   ```bash
   # pandoc — sudo·gh 불필요(공개 릴리스 자산은 인증 없이 받힌다). 정적 바이너리를 ~/.local에
   # 풀면 시스템 pandoc을 PATH 우선순위로 가린다. gh를 쓰면 gh 설치·인증이 선행돼야 해서 안 쓴다
   mkdir -p ~/.local
   curl -fL -o /tmp/pandoc.tar.gz https://github.com/jgm/pandoc/releases/download/2.19.2/pandoc-2.19.2-linux-amd64.tar.gz
   tar xzf /tmp/pandoc.tar.gz -C ~/.local --strip-components=1
   pandoc --list-input-formats | grep -qx jira && echo OK   # 존재가 아니라 능력을 확인 (2.0.6도 command -v는 통과한다)

   # (uv가 없으면) curl -LsSf https://astral.sh/uv/install.sh | sh
   uv tool install git+https://github.com/vimkim/cubrid-jira.git    # 대안: pipx install git+…  (⚠ pip install -e . 금지)
   cubrid-jira search CBRD-25913       # sanity — Description 절에 내용이 있으면 OK (비어 있거나 pandoc 경고가 뜨면 위 pandoc 문제)
   ```
   - ⚠ `show`/`get` 서브커맨드는 **없다**. 읽기는 `search <KEY>`(md) + `comment-list <KEY> --output json`(코멘트) + `jql '<query>' --output json`(대량/본문) + `attachment <KEY> --output json`(첨부 다운로드+매니페스트, 5MiB 초과는 자동 skip). 첨부는 `~/.local/share/cubrid-jira/attachments/<KEY>/`에 떨어지고 매니페스트의 `path`가 실제 위치를 알려준다(`--out DIR`로 변경 가능). **재현 절차가 comment·첨부에만 있는 이슈가 많으니 둘 다 읽어라.**
   - **버전**: semver가 없어서(전부 `1.0.0`) "최신"은 git HEAD를 뜻한다. **최소선은 2026-07-29 머지분** — 그 전 설치본은 `attachment` 서브커맨드가 없고(스킬 지시가 `invalid choice`로 실패) **인증 읽기**도 없다(CUBRIDQA 등 비공개 프로젝트에서 HTTP 401). **그 위로는 날짜로 고르지 말고 그냥 최신을 쓴다** — 2026-07-30에 두 건이 두 시간 간격으로 머지돼 "07-30 머지분"으로는 구분이 안 된다. 최신이 사는 것: 낡은 pandoc에서 본문이 빈칸이 되지 않고, 잘못된 비밀번호로 401이 났을 때 CLI가 **첫 시도에서 멈춘다**(그 전에는 관련 이슈마다 재전송해 CAPTCHA 잠금을 유발). 갱신은 `uv tool upgrade cubrid-jira`.
2. **gh** — Rocky/RHEL 8 계열(dnf). Debian/Ubuntu는 apt, 그 외 [cli.github.com/manual](https://cli.github.com/manual) 참조.
   ```bash
   sudo dnf install -y 'dnf-command(config-manager)'
   sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
   sudo dnf install -y gh
   ```

## 4. 기동 (스킬별)

```
/cubrid-agent:gate-resolved    [CBRD-XXXXX]        # Resolved 검토 → 통과/반송 전이·코멘트(targeted) 또는 초안(batch) + 리포트
/cubrid-agent:author-testcase  [N | CBRD-XXXXX]    # 대기열 선두 N건(기본 1) → TC 작성·검증 → PR(키 지정=ready, 큐=Draft)
/cubrid-agent:review-testcase  [PR번호]            # 열린 SQL TC PR → 3층 리뷰 코멘트 게시(targeted) + 리포트
```
정확한 문구 없이도 자연어로 뜬다("gate-resolved 돌려줘", "이 PR 리뷰해줘", "다음 이슈 tc 작성" 등 — 각 SKILL.md의 트리거 참조).

## 5. 함정 체크리스트 (PoC에서 규명 — setup.sh가 대부분 선처리, 진단용으로 유지)

| 증상 | 원인 | 대처 |
|---|---|---|
| broker/master 안 뜸, "socket path too long" | CUBRID 설치 경로 108자 초과 | 짧은 경로(`$HOME/CUBRID` — setup 규약)에 재설치 |
| DB setup 중 `javac not found` | `JAVA_HOME`이 JRE | `source ~/.cubrid-agent/env.sh`(setup이 JDK 탐지) |
| CTP `run`이 케이스를 스킵(`Total:1/Success:0/Fail:0`) | `.answer` 파일 없음 | empty-answer 트릭(빈 answer → 실행 → `.result` 승격) |
| fail→pass가 병렬 경로를 안 탐 | `taskset` ≤2코어 → 병렬 disable | **≥4코어**로 실행 |
| 이슈 본문이 비어 보임 | **pandoc이 낡아 `jira` reader가 없다**(2.0.6). 2026-07-30 이전 `cubrid-jira`는 pandoc 실패를 검사하지 않아 빈 문자열이 본문이 된다(그 이후 설치본은 경고 한 줄 + 원문) | pandoc 2.19+ 설치(§3). 급하면 pandoc 무관 경로인 `jql '<query>' --output json`으로 원문(Jira 마크업) 직접 읽기 — LLM은 `h2.`·`||표||`를 그대로 읽는다 |
| PR 검증이 엉뚱한 브랜치 검사 | 원본 conf `scenario=`는 `~/cubrid-testcases` 지시 | PR 워크트리 검증 시 conf 사본에 scenario를 worktree로 덮기(review-testcase가 안내) |

## 6. Jira 쓰기 — 호출 의도로 게이팅 (Stage 2 규칙)

세 스킬은 **targeted 호출(사람이 이슈/PR 키를 나열)에서 실제로 쓴다** — gate-resolved의 전이(Need Something/Start Test)·반송 코멘트·QA Scenario 필드, review-testcase의 PR 리뷰 코멘트, author-testcase의 ready-for-review PR. **batch 호출(JQL/큐 쿼리로 만든 집합, 건수 무관)은 초안 유지**. targeted여도 오탐 가드(형제 sub-task가 이미 커버, repro "오타"가 line-정확도 버그의 의도된 입력일 수 있음(CBRD-26909), 저신뢰)가 걸리면 게시하지 않고 초안+@질의로 강등한다. 머지/승인은 여전히 사람이 하고, `Start Test` 전이는 gate-resolved 소유다(author-testcase가 대신 쏘지 않음). 무인 자동 전이·cron batch 쓰기만 Stage 3. See ADR-0016 (CUBRIDQA-1440).

## 7. 구성 요소

- **setup-cubrid-agent 스킬 + `scripts/setup.sh`**(Tier 2 자동화, 진입점 `/cubrid-agent:setup-cubrid-agent` — [ADR 0003](../.agents/adr/0003-setup-entrypoint-skill.md)) — 스크립트가 `$HOME` 표준 배치(D7: `~/cubrid-testcases`·`~/cubrid`·CTP·`~/.cubrid-agent`), 멱등·비대화식·기존 clone 불가침, `--build <url>` 옵션, Stage 3 컨테이너 재사용 가능(D5). conf 사본 불필요(원본 conf가 이미 `${HOME}` 기준). 정본은 스킬 안 단 하나(루트 래퍼 없음).
- **부품 스킬** — 이 repo `skills/qa/`에 소스로 들어 있다(흡수 — [ADR 0001](../.agents/adr/0001-repackage-as-plugin.md)). 플러그인은 로드하지 않으므로 `npx skills add` 채널로 개별 설치(§0 표 아래 주석).
- **스킬 자기완결**(D8) — 스킬·hook은 `docs/`를 런타임 참조하지 않는다. review-testcase 연료(few-shot bank·카탈로그)는 스킬 `references/`에 내장.
- **hook 하드 게이트**([`hooks/`](../hooks/)) — `gate-pr-submit`(제출 차단)·`lint-sql-tc`(린트→manifest)·`gate-stop`(리마인드).
- **run 디렉토리 = `~/.cubrid-agent/<KEY>/`** (`CBRD-XXXXX`, review-testcase는 `PR-NNNN`) — 실행 하나가 남기는 것은 TC 자체를 빼고 **전부 여기**다. manifest(`manifest.json`, 스키마 [`scripts/manifest.example.json`](../scripts/manifest.example.json))가 이미 여기 있고 hook 둘(`lint-sql-tc`·`gate-pr-submit`)이 이 경로를 찾는다. 스킬은 홈이나 현재 디렉토리에 쓰지 않고, 없던 디렉토리를 새로 만들지도 않는다(`~/scratchpad…` 같은 것 — 사람 파일과 구분이 안 된다). **실행이 끝나도 지우지 않는다** — 실패한 실행의 잔여물이 진단 자료다. 리포트는 `reports/<스킬>/`, worktree는 `worktrees/`에 따로 둔다.
- **CCI 교차 검증**(author-testcase Verify) — 원본 `$CTP_HOME/conf/sql_by_cci.conf`로 `run_cci`, 기본 sql(JDBC) 출력과 다르면 `.answer_cci`.

hook은 **신뢰된 팀원의 실수 방지 가드레일**(적대적 우회 방지 아님) — 자세히 설계: CUBRIDQA-1446.
