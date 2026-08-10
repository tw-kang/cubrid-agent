# 셋업 — 팀원이 자기 머신에서 3종 스킬을 돌리기까지

팀원이 **자기 로컬에서** 1순위 3종 스킬(`gate-resolved` · `author-testcase` · `review-testcase`)을 기동하기 위한 실행 가이드. 구조 정본(자산 3계층·확정 결정)은 [deployment.md](./deployment.md). 롤아웃 단계는 이 repo가 관리하지 않는다 — 정본은 CUBRIDQA-1425.

> **"배포"가 아니라 "공유"**. 한 사람의 로컬 흐름을 팀이 각자 재현하도록 패키징한 것. 검증은 로컬 CTP, **Jira 쓰기는 호출 의도로 게이팅**한다 — 사람이 키를 나열한 targeted 호출은 전이·코멘트·필드를 실제로 쓰고, JQL/큐로 만든 batch 호출은 초안 유지(오탐 가드가 걸리면 targeted여도 초안+@질의로 강등). 머지/승인은 여전히 사람이 한다. 무인 자동 호출·k8s·pod·자동 스케줄·무인 batch 쓰기는 이 repo 밖이다 — CUBRIDQA-1440·1425.

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
bash skills/qa/setup-cubrid-agent/scripts/setup.sh --install-clis # Tier 2 전부($HOME 표준) + 필수 CLI 3종 설치(§3)
bash skills/qa/setup-cubrid-agent/scripts/setup.sh              # 설치 없이 확인·안내만. TODO는 사람이 처리(§2·§3)
bash skills/qa/setup-cubrid-agent/scripts/setup.sh --build <url> # CTP 검증 스킬용 — ftp.cubrid.org/CUBRID_Engine/nightly/daily_build (사내 빌드서버를 쓰려면 CUBRID_BUILD_BASE)
```

- setup 스크립트는 **멱등**(재실행 안전)·**비대화식**이며 CWD 비의존이다(정본은 setup-cubrid-agent 스킬 안, 루트 래퍼 없음 — [ADR 0003](../.agents/adr/0003-setup-entrypoint-skill.md)). 하는 일/안 하는 일 경계는 [deployment.md](./deployment.md)의 3계층: Tier 2(머신 상태)는 스크립트가, Tier 3 중 **CLI 설치는 동의 한 번 뒤 스크립트가**(`--install-clis`, §3), **자격증명은 사람이**.
- gate-resolved만 쓸 거면 `cubrid-jira` + 자격이면 충분 — `--build` 불필요. 단 **Jira 사용자명이 해석돼 있어야** 대기열 JQL이 동작한다: `export CUBRID_JIRA_USER=<계정>` 하거나 `/cubrid-agent:setup-cubrid-agent`를 한 번 돌려 `env.sh`가 내보내게 한다(ADR 0004). 값이 없으면 스킬은 0건을 보고하지 않고 중단한다.
- 부품 스킬은 이 repo의 `skills/in-progress/`에 **소스로 들어 있다**(흡수 — [ADR 0001](../.agents/adr/0001-repackage-as-plugin.md), 2트리 분리 — [ADR 0006](../.agents/adr/0006-shipped-vs-in-progress-skill-trees.md)). 별도 clone·심링크는 불필요하지만, **플러그인이 로드하는 건 `skills/qa/`의 6종뿐**이다(setup + 파이프라인 5종 = `plugin.json` 등재분과 일치). 부품 16종을 쓰려면 `npx skills add tw-kang/cubrid-agent -s <이름>`으로 따로 깐다(이 채널은 두 트리를 다 발견한다). 어떤 설치본이 실제로 무엇을 로드했는지와 그 상시 비용은 `claude plugin details cubrid-agent`로 확인한다 — 숫자를 여기 적어두면 낡는다(2026-07-29 ~1,185 tok이 07-31엔 ~1,988 tok이었다. description이 자란 결과이고 로드 대상은 그대로다).

### 최신본 유지 — 설치는 한 번, 이후는 자동

**한 번 설치하면 자동으로 최신이 된다.** Claude Code가 세션 시작 뒤 마켓플레이스와 설치된 플러그인을 배후에서 갱신한다(실제 지연은 아래 실측).

단 **서드파티 마켓플레이스는 자동 갱신이 기본 꺼져 있다.** 그래서 `/cubrid-agent:setup-cubrid-agent`가 `~/.claude/settings.json`의 `extraKnownMarketplaces["cubrid-agent"].autoUpdate` 를 **켜 준다**(멱등, 백업 `settings.json.bak`). 수동으로 켜려면 `/plugin` → Marketplaces → cubrid-agent → **Enable auto-update**.

**마켓플레이스를 다시 등록하면 이 값이 사라진다.** 항목이 새로 써지기 때문이다. 그러니 `claude plugin marketplace add`를 다시 했으면 setup을 다시 돌려라. 안 그러면 카탈로그가 그 자리에 멈추고, **릴리스를 내도 그 설치본에는 영원히 안 간다.** 화면에는 아무 말도 안 나온다. 실제로 이 장비에서 4일간 그랬다(v1.0.3이 08-07에 나갔는데 08-10까지 1.0.0). 지금 값은 이렇게 본다:

```bash
jq -r '.extraKnownMarketplaces["cubrid-agent"].autoUpdate' ~/.claude/settings.json  # true 여야 한다
```

밟기 쉬운 함정 둘:

| 하는 일 | 결과 |
|---|---|
| `claude plugin marketplace update cubrid-agent` | **카탈로그만** 새로 받는다 — 설치본은 그대로인데 "성공"이라고 보고한다 |
| `claude plugin update cubrid-agent` | ✘ `Plugin not found` — 이름을 정규화해야 한다 |
| `claude plugin update cubrid-agent@cubrid-agent` | ✔ 설치본 교체(fetch까지 수행). **재시작 또는 `/reload-plugins` 후 적용** |

즉 자동 갱신이 꺼진 상태로 오래 쓰면 옛 스킬이 돌면서도 눈치채기 어렵다. 실제 로드되는 위치는 마켓플레이스 clone이 아니라 버전으로 고정된 캐시(`~/.claude/plugins/cache/cubrid-agent/cubrid-agent/<버전>/`)이고, 어느 버전을 쓰는지는 `claude plugin list` 또는 `~/.claude/plugins/installed_plugins.json`으로 확인한다.

**실측 4회, 전부 수동 명령 없이**: 17:14 push → **세션 시작 9분 뒤** 17:52:20 설치. 18:08 push → **2분 19초 뒤** 18:14:32 설치(둘 다 2026-08-04, 커밋 SHA가 버전이던 시절). **2026-08-06 첫 버전 릴리스 → 세션 시작 24초 뒤 05:26:33 설치**, **그 다음 버전 상승 → 2분 30초 뒤 05:56:51 설치**. 설치본의 `version`과 캐시 디렉토리 이름이 그 버전으로 바뀐다. 즉 **SHA→버전 전환도, 버전 상승도 자동으로 배달된다.**

**단, 점검에는 간격이 있다.** 같은 날 새 버전을 push한 뒤 연 세션 둘은 아무것도 못 받았다 — 직전 갱신 후 **4분**(11초 세션)과 **9분**(6분간 살아 있던 세션) 시점이었다. 실제로 점검이 돈 것들은 **22분·30분 간격**이다. 즉 **간격은 9분보다 크고 22분 이하**이고, 정확한 값은 모른다. 실무적으로: **직전 갱신 직후에 연 세션은 오래 켜 둬도 아무것도 안 받는다** — 점검은 세션 시작 후 한 번뿐이라 그 순간 간격이 안 찼으면 그 세션은 그걸로 끝이다. 급하면 아래 두 명령을 직접 친다. 지연은 세션 시작 후 **수 분**이고 회차마다 흔들린다. **점검은 세션당 한 번이다** — 18분짜리 세션에서 갱신은 18:14:32 한 번뿐이었고, 그 뒤 18:20·18:22에 push한 커밋은 같은 세션에서 반영되지 않았다. 즉 **세션을 하루 종일 켜 두면 그날 시작 직후 버전에 머문다.** 이때 `known_marketplaces.json`의 `autoUpdate`도 Claude Code가 직접 써 넣는다 — **그 파일은 우리가 건드리지 않는다.** 반대로 **아무 일도 시키지 않은 유휴 세션은 15분을 기다려도 갱신되지 않았다**: 점검이 세션 시작 후 타이머로 도는 것으로 보이고, 유휴로는 트리거되지 않는다.

즉 **push한 그 자리에서 반영되지는 않는다.** 그래서 `setup.sh`가 마지막에 위 두 명령을 **직접 한 번 실행한다**(`claude` CLI가 있을 때만) — 방금 설치한 사람이 10분을 기다리지 않게 하려는 것이다. fetch 자체는 3.4초지만 **적용은 재시작이나 `/reload-plugins` 이후**라는 점은 위 표와 같다.

**플러그인이 갱신되면 `/cubrid-agent:setup-cubrid-agent`를 한 번 더 돌려라.** 플러그인 갱신은 스킬 본문을 바꾸지만 `~/.cubrid-agent/bin/`의 헬퍼 사본은 그대로 둔다 — 새 스킬이 새 플래그(예: `verify-run.sh --generate`)를 부르면 옛 사본은 `unknown option`으로 죽는다. setup은 멱등이고 헬퍼를 항상 덮어쓰므로 재실행이 곧 갱신이다. 그 상황에 걸리면 헬퍼가 **스스로 그 사실을 말한다**("this installed copy is stale … run /setup-cubrid-agent").

> ⚠️ **팀에 전달되는 기준은 커밋이 아니라 `version`이다.** 고쳐서 push해도 버전을 안 올리면 아무에게도 가지 않는다. 버전이 사용자에게 무엇을 약속하는지는 `CHANGELOG.md`의 version note가 정본이다. 어떤 변경이 어느 자리를 얻는지와 릴리스 절차는 [ADR 0007](../.agents/adr/0007-versioning-and-releases.md)이 정본이다.

**무엇이 바뀌었는지는 GitHub Release 노트로 읽는다.** 릴리스마다 노트가 하나 생긴다 — [Releases](https://github.com/tw-kang/cubrid-agent/releases). 갱신을 받기 전에 읽으면 이번 버전이 무엇을 요구하는지 안다. 갱신이 안 온다고 느끼면 지금 버전부터 확인한다 — 위에서 말한 캐시 디렉토리의 이름이 그 버전이다.

## 2. 자격 (Tier 3 — 사람만, repo·스크립트에 넣지 않는다)

표준은 **환경변수**(컨테이너의 k8s Secret과 같은 형식), 지금은 파일 방식 병행 허용:

```bash
export CUBRID_JIRA_USER="..."; export CUBRID_JIRA_PASSWORD="..."   # 표준 (또는 ~/.netrc: machine jira.cubrid.org, chmod 600)
gh auth login                                                       # 또는 GH_TOKEN. fork=각자 gh 계정(ADR 0004), base=CUBRID
```

## 3. CLI 설치 — 기본은 셋업이 깐다, 아래는 수동 경로

`gh`·`pandoc`·`cubrid-jira` 세 개는 선택이 아니라 전제다(없으면 이슈를 못 읽고, Jira 쓰기가 실패하고, PR을 못 낸다). 그래서 **`/cubrid-agent:setup-cubrid-agent`가 무엇을 설치할지 먼저 보여주고 동의를 한 번 받은 뒤 직접 깐다** — 스킬이 `setup.sh --install-clis`로 실행한다. repo 개발자가 직접 돌릴 때도 같다:

```bash
bash skills/qa/setup-cubrid-agent/scripts/setup.sh --install-clis
```

멱등이다 — **능력 검사를 통과하는 도구는 건드리지 않으므로** 재실행하면 아무것도 설치하지 않는다. 플래그를 빼면 예전처럼 확인·안내만 한다(CUBRIDQA-1485).

강제할 수 없는 것 두 가지: **`gh`는 root가 필요해서** `sudo -n`이 안 통하면(비밀번호를 묻는 머신) 명령만 넘긴다. **자격증명은 절대 스크립트가 만들지 않는다**(§2). `pandoc`·`cubrid-jira`는 `~/.local` 아래로 들어가므로 sudo가 필요 없고, `uv`가 없으면 uv도 같이 깐다.

수동으로 할 때(또는 위 설치가 실패했을 때):

1. **cubrid-jira** ([github.com/vimkim/cubrid-jira](https://github.com/vimkim/cubrid-jira)) — 전제: **Python 3.14+**(uv가 알아서 받아온다), **pandoc 2.19 이상**.

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
   - ⚠ `show`/`get` 서브커맨드는 **없다**. 읽기는 `search <KEY>`(md) + `comment-list <KEY> --output json`(코멘트) + `jql '<query>' --output json`(대량/본문) + `attachment <KEY> --output json`(첨부 다운로드+매니페스트, 5MiB 초과는 자동 skip). 첨부는 `~/.local/share/cubrid-jira/attachments/<KEY>/`에 떨어지고 매니페스트의 `path`가 실제 위치를 알려준다(`--out DIR`로 변경 가능). **재현 절차가 comment·첨부에만 있는 이슈가 많으니 둘 다 읽어라.** 단 스킬은 이 명령들을 직접 부르지 않고 `~/.cubrid-agent/bin/ground-issue.sh <KEY>` 하나를 쓴다(§7).
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

**처음 쓸 때는 targeted(키 지정)로.** 큐 판정을 기다리지 않아 무엇이 도는지 보기 쉽다. 단 targeted는 **실제 쓰기가 나간다** — Jira 전이·코멘트(gate-resolved), ready-for-review PR(author-testcase), GitHub 리뷰 게시(review-testcase). 인자를 뺀 batch는 초안·Draft다(§6).

### 실행 중 — 30~60분, 조용한 게 정상

이슈 한 건이 **30분~1시간+** 걸린다(2026-07-30 실측 62분, 라운드 구조 개선 후 30분대 목표 — 재계측 전). 절반은 CTP 실행 대기이고, CTP 세션 하나가 기동에만 ~85초를 쓴다. 멈춘 게 아닌지는 산출물이 순서대로 생기는지로 본다:

`reports/author-testcase/_queue-<날짜>.md`(Select 끝) → `<KEY>/issue.txt`+`<KEY>/attachments/`(Ground) → `<KEY>/s*.log`(CTP: 답지 생성→결정성→CCI→fail→pass) → `<KEY>/manifest.json`(게이트 기록) → `reports/author-testcase/<KEY>.md`(리포트). 전부 `~/.cubrid-agent/` 아래다.

### 끝난 뒤 — 결과 읽기

```bash
jq '{verify: .verify.status, review: .review.verdict, submitted,
     failed_lint: (.lint | to_entries | map(select(.value != true)) | from_entries)}' \
  ~/.cubrid-agent/CBRD-XXXXX/manifest.json
```

- `verify.status` = `passed` | `blocked_no_build` | `blocked_no_ctp` | `blocked_nondeterministic` | `blocked_review_unresolved`. `passed`가 아니면 "여기서 멈췄다"는 뜻이고 이유는 `verify.note`에 있다 — **실패가 아니라 정해진 정지점**이다.
- `review.verdict` = `PASS` | `NEEDS-WORK` 둘뿐.
- `lint`은 8개 항목이고, **그중 7개를 훅이** 파일 쓸 때 자동 기록한다(헤더 형식·범위·길이, 케이스 번호, cleanup, 영문 주석, 배치 경로). 나머지 `answer_not_handwritten`(답지가 CTP 출력인지)은 에이전트가 기록한다. 위 명령은 통과하지 못한 것만 보여준다.
- `verify.preconditions`에 `verified: false`가 있으면 초록불이어도 결론은 유보다.

**배치인데 "0건, 정지"는 정상이다** — 실측에서 대기열 8건이 전부 Select에서 탈락했다(이미 처리됨·SQL로 관측 불가·중복). 큐를 넓히는 건 사람의 결정이라 자동으로 넓히지 않는다.

**`gh` 미인증으로 돌리면 중복 검사가 GitHub를 못 본다** — 남이 이미 만든 TC를 또 만들 수 있다. `gh auth login`을 먼저.

**Claude Code의 auto-memory는 끄기를 권한다** — `~/.claude/settings.json`에 `"autoMemoryEnabled": false`. 켜져 있으면 에이전트가 이전 실행의 판정을 캐시해 다시 도출하지 않아, 같은 이슈가 사람마다 다른 결과를 내고 실행 시간 측정도 믿을 수 없게 된다(CUBRIDQA-1488).

## 5. 함정 체크리스트 (PoC에서 규명 — setup.sh가 대부분 선처리, 진단용으로 유지)

| 증상 | 원인 | 대처 |
|---|---|---|
| broker/master 안 뜸, "socket path too long" | CUBRID 설치 경로 108자 초과 | 짧은 경로(`$HOME/CUBRID` — setup 규약)에 재설치 |
| DB setup 중 `javac not found` | `JAVA_HOME`이 JRE | `source ~/.cubrid-agent/env.sh`(setup이 JDK 탐지) |
| CTP `run`이 케이스를 스킵(`Total:1/Success:0/Fail:0`) | `.answer` 파일 없음 | empty-answer 트릭(빈 answer → 실행 → `.result` 승격) |
| fail→pass가 병렬 경로를 안 탐 | `taskset` ≤2코어 → 병렬 disable | **≥4코어**로 실행 |
| 이슈 본문이 비어 보임 | **pandoc이 낡아 `jira` reader가 없다**(2.0.6). 2026-07-30 이전 `cubrid-jira`는 pandoc 실패를 검사하지 않아 빈 문자열이 본문이 된다(그 이후 설치본은 경고 한 줄 + 원문) | pandoc 2.19+ 설치(§3). 급하면 pandoc 무관 경로인 `jql '<query>' --output json`으로 원문(Jira 마크업) 직접 읽기 — LLM은 `h2.`·`||표||`를 그대로 읽는다 |
| PR 검증이 엉뚱한 브랜치 검사 | 원본 conf `scenario=`는 `~/cubrid-testcases` 지시 | PR 워크트리 검증 시 conf 사본에 scenario를 worktree로 덮기(review-testcase가 안내) |

## 6. Jira 쓰기 — 호출 의도로 게이팅

세 스킬은 **targeted 호출(사람이 이슈/PR 키를 나열)에서 실제로 쓴다** — gate-resolved의 전이(Need Something/Start Test)·반송 코멘트·QA Scenario 필드, review-testcase의 PR 리뷰 코멘트, author-testcase의 ready-for-review PR. **batch 호출(JQL/큐 쿼리로 만든 집합, 건수 무관)은 초안 유지**. targeted여도 오탐 가드(형제 sub-task가 이미 커버, repro "오타"가 line-정확도 버그의 의도된 입력일 수 있음(CBRD-26909), 저신뢰)가 걸리면 게시하지 않고 초안+@질의로 강등한다. 머지/승인은 여전히 사람이 하고, `Start Test` 전이는 gate-resolved 소유다(author-testcase가 대신 쏘지 않음). 무인 자동 전이·cron batch 쓰기는 이 repo 밖이다(CUBRIDQA-1440).

## 7. 구성 요소

- **setup-cubrid-agent 스킬 + `scripts/setup.sh`**(Tier 2 자동화, 진입점 `/cubrid-agent:setup-cubrid-agent` — [ADR 0003](../.agents/adr/0003-setup-entrypoint-skill.md)) — 스크립트가 `$HOME` 표준 배치(D7: 테스트케이스 clone·`~/cubrid`·CTP·`~/.cubrid-agent`), 멱등·비대화식·기존 clone 불가침, `--build <url>` 옵션, 컨테이너 이미지에서 그대로 재사용 가능(D5). 테스트케이스 clone 경로는 [D7](deployment.md)의 오버라이드 규약을 그대로 따른다 — 오버라이드가 있으면 기본 경로는 **만들지도 않고**, 그 값을 `env.sh`에 남기되 호출자가 export한 값이 이긴다. conf 사본은 setup이 만들지 않는다(`verify-run.sh`가 매 실행 만든다). 정본은 스킬 안 단 하나(루트 래퍼 없음).
- **부품 스킬** — 이 repo `skills/in-progress/`에 소스로 들어 있다(흡수 — [ADR 0001](../.agents/adr/0001-repackage-as-plugin.md)). 배포분이 아니므로 플러그인은 로드하지 않는다 — `npx skills add` 채널로 개별 설치(§0 표 아래 주석).
- **스킬 자기완결**(D8) — 스킬·hook은 `docs/`를 런타임 참조하지 않는다. review-testcase 연료(few-shot bank·카탈로그)는 스킬 `references/`에 내장.
- **hook 하드 게이트**([`hooks/`](../hooks/)) — `gate-pr-submit`(제출 차단)·`lint-sql-tc`(린트→manifest)·`gate-stop`(리마인드). 여기에 게이트가 아닌 힌트가 하나 붙는다 — `hint-missing-helper`는 설치 안 된 헬퍼를 부르는 명령에 **어느 헬퍼가 왜 없는지**를 덧붙인다(막지 않는다. 그 명령은 어차피 실패한다).
- **이슈 grounding = 명령 하나**, `~/.cubrid-agent/bin/ground-issue.sh <KEY>` (setup이 깐다) — 본문+**전체 코멘트**를 `<KEY>/issue.txt`로, 첨부 전체를 `<KEY>/attachments/`로 내려받고 **내용 기준으로** 분류해 읽을 것을 알려준다(`read`/`view`/못 읽으면 `unread`+사유). 스킬이 산문으로 갖고 있던 규칙 — `search` 금지(pandoc), mimeType 불신, 압축 풀기, PDF는 `pdftotext` 필요 — 이 스크립트 한 곳에 있다. 스킬은 절대경로로 부르므로 **헬퍼가 바뀌면 setup을 다시 돌려야** 새 사본이 깔린다.
- **run 디렉토리 = `~/.cubrid-agent/<KEY>/`** (`CBRD-XXXXX`, review-testcase는 `PR-NNNN`) — 실행 하나가 남기는 것은 TC 자체를 빼고 **전부 여기**다. manifest(`manifest.json`, 스키마 [`scripts/manifest.example.json`](../scripts/manifest.example.json))가 이미 여기 있고 hook 둘(`lint-sql-tc`·`gate-pr-submit`)이 이 경로를 찾는다. 스킬은 홈이나 현재 디렉토리에 쓰지 않고, 없던 디렉토리를 새로 만들지도 않는다(`~/scratchpad…` 같은 것 — 사람 파일과 구분이 안 된다). **실행이 끝나도 지우지 않는다** — 실패한 실행의 잔여물이 진단 자료다. 리포트는 `reports/<스킬>/`, worktree는 `worktrees/`에 따로 둔다.
- **CCI 교차 검증**(author-testcase Verify) — 원본 `$CTP_HOME/conf/sql_by_cci.conf`로 `run_cci`, 기본 sql(JDBC) 출력과 다르면 `.answer_cci`.

hook은 **신뢰된 팀원의 실수 방지 가드레일**(적대적 우회 방지 아님) — 자세히 설계: CUBRIDQA-1446.
