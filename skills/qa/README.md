# skills

CUBRID CTP 스킬 모음. **Claude Code, Cursor, Codex, Gemini CLI를 비롯한 [45개 이상의 에이전트](https://github.com/vercel-labs/skills#available-agents)** 에 [`skills`](https://github.com/vercel-labs/skills) CLI로 설치할 수 있습니다.

## 설치

**선행 조건:** Node.js 18 이상 (`npx` 사용)

```bash
# 단일 스킬을 하나 이상의 에이전트에 설치 (기본은 프로젝트 스코프)
npx skills add tw-kang/skills -a claude-code -a codex -a cursor -s cubrid-cci-tc-create

# 프로젝트 대신 사용자(글로벌) 디렉토리에 설치
npx skills add tw-kang/skills -g -s cubrid-cci-tc-runone

# 모든 스킬을 모든 지원 에이전트에 설치
npx skills add tw-kang/skills --all

# 사용 가능한 스킬 목록만 확인 (설치하지 않음)
npx skills add tw-kang/skills --list

# 비대화형 (CI/CD)
npx skills add tw-kang/skills -s cubrid-shell-tc-create -a claude-code -g -y
```

지원 에이전트 전체 목록, `--copy` vs symlink 설치 전략, 기타 명령(`npx skills list`, `npx skills update`, `npx skills remove`) 은 [`skills` CLI 문서](https://github.com/vercel-labs/skills)를 참고하세요.

> 이 저장소의 스킬들은 [`skill-creator`](https://github.com/anthropics/skills/tree/main/skills/skill-creator) 스킬로 작성되었습니다.
>
> **skill-creator 설치:**
> ```bash
> npx skills add anthropics/skills --skill skill-creator
> ```
> Claude Code에서 `/skill-creator` 명령으로 새 스킬을 생성·편집·벤치마크할 수 있습니다.

## 스킬 목록

| 스킬 | 설명 |
|------|------|
| [cubrid-cci-tc-create](cubrid-cci-tc-create/) | CTP CCI testcase 초안 생성 |
| [cubrid-cci-tc-runone](cubrid-cci-tc-runone/) | CTP CCI testcase 단건 실행 및 결과 리포트 |
| [cubrid-cdc_repl-tc-create](cubrid-cdc_repl-tc-create/) | CTP CDC replication testcase 초안 생성 |
| [cubrid-cdc_repl-tc-runone](cubrid-cdc_repl-tc-runone/) | CTP CDC replication testcase 단건 실행 및 결과 리포트 |
| [cubrid-ha_repl-tc-create](cubrid-ha_repl-tc-create/) | CTP HA replication testcase 초안 생성 |
| [cubrid-ha_repl-tc-runone](cubrid-ha_repl-tc-runone/) | CTP HA replication testcase 단건 실행 및 결과 리포트 |
| [cubrid-ha_shell-tc-create](cubrid-ha_shell-tc-create/) | CTP HA shell testcase 초안 생성 |
| [cubrid-ha_shell-tc-runone](cubrid-ha_shell-tc-runone/) | CTP HA shell testcase 단건 실행 및 결과 리포트 |
| [cubrid-isolation-tc-create](cubrid-isolation-tc-create/) | CTP isolation testcase 초안 생성 |
| [cubrid-isolation-tc-runone](cubrid-isolation-tc-runone/) | CTP isolation testcase 단건 실행 및 결과 리포트 |
| [cubrid-jdbc-tc-create](cubrid-jdbc-tc-create/) | CTP JDBC testcase 초안 생성 |
| [cubrid-jdbc-tc-runone](cubrid-jdbc-tc-runone/) | CTP JDBC testcase 단건 실행 및 결과 리포트 |
| [cubrid-shell-tc-create](cubrid-shell-tc-create/) | CTP shell testcase 초안 생성 |
| [cubrid-shell-tc-review](cubrid-shell-tc-review/) | CTP shell testcase diff 리뷰 |
| [cubrid-shell-tc-runone](cubrid-shell-tc-runone/) | CTP shell testcase 단건 실행 및 결과 리포트 |
| [cubrid-sql-tc-create](cubrid-sql-tc-create/) | CTP SQL testcase (`.sql` + `.answer`) 초안 생성 |
| [cubrid-sql-tc-runone](cubrid-sql-tc-runone/) | CTP SQL testcase 단건 실행 및 결과 리포트 |
| [cubrid-unittest-tc-create](cubrid-unittest-tc-create/) | CTP C/C++ unittest 초안 생성 |
| [cubrid-unittest-tc-runone](cubrid-unittest-tc-runone/) | CTP unittest 단건 실행 및 결과 리포트 |
| [cubrid-test-fail-reasoning](cubrid-test-fail-reasoning/) | 실패한 CUBRID testcase 묶음을 커밋 범위 안에서 bisect하여 의심 커밋과 답지 수정/버그 리포트 판정을 단일 `report.md`로 출력 |
| [jira](jira/) | CUBRID JIRA 이슈 조회 (캐시 우선, stdlib 전용) |

## JIRA 스킬 자동 호출 (cross-cutting)

`cubrid-*-tc-create` / `cubrid-*-tc-runone` / `cubrid-shell-tc-review` / `cubrid-test-fail-reasoning` 스킬은 요청에 `CBRD-XXXXX` 또는 `cbrd_XXXXX` 토큰이 포함된 경우 [jira](jira/) 스킬을 **먼저 호출**해 이슈 컨텍스트(제목, 설명, 재현 절차, 영향 컴포넌트, 코멘트)를 가져옵니다. 이 컨텍스트가 testcase 작성 범위·기대 동작·실패 진단 정확도를 크게 끌어올립니다.

- `jira` 스킬이 설치되어 있지 않으면 호출 측 스킬이 사용자에게 설치 동의를 먼저 요청합니다 (`npx skills add tw-kang/skills -s jira -a claude-code`).
- 따라서 위 스킬 중 하나라도 사용할 계획이라면 `jira` 스킬을 함께 설치하길 권장합니다.
- `jira` 스킬은 `pandoc`을 필요로 합니다 — 없으면 description/comments가 raw Jira-wiki 마크업으로 출력되어 가독성이 떨어집니다. 호출 측 스킬은 `pandoc` 부재 시 사전에 경고를 출력합니다.
- 디스커버리 경로 순서: `$(pwd)/.claude/skills/jira` → `$HOME/.claude/skills/jira` → `$HOME/.claude/plugins/skills/jira` → `$HOME/skills/jira` → `${CLAUDE_PLUGIN_ROOT}/skills/jira`.

---

### [cubrid-cci-tc-create](cubrid-cci-tc-create/)

CTP CCI(C Client Interface) testcase 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 `.c` 소스 파일과 CCI 테스트 스크립트를 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-cci-tc-create
```

**사용 예시:**
- "CBRD-12345 cci tc 만들어줘"
- "CBRD-12345 용 cci 테스트케이스 작성"
- "cci 테스트케이스 초안 작성해줘"

---

### [cubrid-cci-tc-runone](cubrid-cci-tc-runone/)

로컬 머신에서 CTP CCI testcase 한 건을 실행하고 결과를 리포트하는 스킬.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-cci-tc-runone
```

**사용 예시:**
- "cbrd_12345 cci tc 돌려봐 (빌드 URL: http://...)"
- "cci tc cbrd_12345 실행해줘"

---

### [cubrid-cdc_repl-tc-create](cubrid-cdc_repl-tc-create/)

CTP CDC replication testcase (`.sql`) 초안을 생성하는 스킬. `--test:` / `--check:` 마커 형식을 준수합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-cdc_repl-tc-create
```

**사용 예시:**
- "CBRD-12345 cdc_repl tc 만들어줘"
- "CBRD-12345 cdc replication 테스트 작성"

---

### [cubrid-cdc_repl-tc-runone](cubrid-cdc_repl-tc-runone/)

CTP CDC replication testcase 한 건을 실행하고 결과를 리포트하는 스킬. CDC 인프라(소스 + 타깃 노드) 설정이 필요합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-cdc_repl-tc-runone
```

**사용 예시:**
- "cbrd_12345.sql cdc_repl 테스트 돌려봐"
- "cdc_repl tc cbrd_12345 실행"

---

### [cubrid-ha_repl-tc-create](cubrid-ha_repl-tc-create/)

CTP HA replication testcase (`.sql`) 초안을 생성하는 스킬. `--test:` / `--check:` 마커 형식을 준수합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-ha_repl-tc-create
```

**사용 예시:**
- "CBRD-12345 ha_repl tc 만들어줘"
- "CBRD-12345 ha replication 테스트 작성"
- "ha_repl tc 초안 작성해줘"

---

### [cubrid-ha_repl-tc-runone](cubrid-ha_repl-tc-runone/)

CTP HA replication testcase 한 건을 실행하고 결과를 리포트하는 스킬. HA 인프라(마스터 + 슬레이브 노드) 설정이 필요합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-ha_repl-tc-runone
```

**사용 예시:**
- "cbrd_12345.sql ha_repl 테스트 돌려봐"
- "ha_repl tc cbrd_12345 실행"

---

### [cubrid-ha_shell-tc-create](cubrid-ha_shell-tc-create/)

CTP HA shell testcase (`.sh`) 초안을 생성하는 스킬. `make_ha.sh` 헬퍼를 활용한 HA 복제 테스트 스크립트를 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-ha_shell-tc-create
```

**사용 예시:**
- "CBRD-12345 ha shell tc 만들어줘"
- "CBRD-12345 ha shell 테스트 작성"
- "ha shell testcase 초안 작성해줘"

---

### [cubrid-ha_shell-tc-runone](cubrid-ha_shell-tc-runone/)

로컬 HA 인프라에서 CTP HA shell testcase 한 건을 실행하고 결과를 리포트하는 스킬.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-ha_shell-tc-runone
```

**사용 예시:**
- "cbrd_12345 ha shell tc 돌려봐 (빌드 URL: http://...)"
- "ha shell tc cbrd_12345 실행"

---

### [cubrid-isolation-tc-create](cubrid-isolation-tc-create/)

CTP isolation testcase (`.ctl`) 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 격리 수준 테스트 파일을 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-isolation-tc-create
```

**사용 예시:**
- "CBRD-12345 isolation tc 만들어줘"
- "CBRD-12345 isolation 테스트 작성"
- "isolation testcase 초안 작성해줘"

---

### [cubrid-isolation-tc-runone](cubrid-isolation-tc-runone/)

CTP isolation testcase 한 건을 실행하고 결과를 리포트하는 스킬.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-isolation-tc-runone
```

**사용 예시:**
- "cbrd_12345.ctl isolation 테스트 돌려봐"
- "isolation tc cbrd_12345 실행"

---

### [cubrid-jdbc-tc-create](cubrid-jdbc-tc-create/)

CTP JDBC testcase (JUnit 4 Java `@Test` 메서드) 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 Java 테스트 파일을 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-jdbc-tc-create
```

**사용 예시:**
- "CBRD-12345 jdbc tc 만들어줘"
- "CBRD-12345 jdbc 테스트케이스 작성"
- "jdbc 테스트케이스 초안 작성해줘"

---

### [cubrid-jdbc-tc-runone](cubrid-jdbc-tc-runone/)

CTP JDBC testcase 한 건을 실행하고 결과를 리포트하는 스킬.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-jdbc-tc-runone
```

**사용 예시:**
- "cbrd_12345 jdbc tc 돌려봐 (빌드 URL: http://...)"
- "jdbc tc cbrd_12345 실행"

---

### [cubrid-shell-tc-create](cubrid-shell-tc-create/)

CTP shell testcase 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 CTP 규칙을 준수하는 `.sh` 파일을 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-shell-tc-create
```

**사용 예시:**
- "CBRD-12345 버그픽스 shell tc 만들어줘"
- "CBRD-12345 shell tc 작성"
- "shell testcase 초안 작성해줘"

---

### [cubrid-shell-tc-review](cubrid-shell-tc-review/)

CTP shell testcase diff를 리뷰하는 스킬. 경로 규칙, 라이프사이클 계약, CTP 헬퍼 사용, 이식성, 안정성 등을 점검하고 구조화된 리뷰 리포트를 출력합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-shell-tc-review
```

**사용 예시:**
- "이 shell tc PR 리뷰해줘"
- "shell testcase가 CTP 규칙을 따르는지 확인해줘"

---

### [cubrid-shell-tc-runone](cubrid-shell-tc-runone/)

로컬 머신에서 CTP shell testcase 한 건을 실행하고 결과를 리포트하는 스킬. CUBRID 빌드 설치, 테스트 수행, 실패 진단까지 처리합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-shell-tc-runone
```

**사용 예시:**
- "cbrd_12345 테스트 돌려봐 (빌드 URL: http://...)"
- "이 shell tc 패스하는지 확인해줘"
- "shell tc cbrd_12345 실행"

---

### [cubrid-sql-tc-create](cubrid-sql-tc-create/)

CTP SQL testcase (`.sql` + `.answer`) 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 CTP SQL 테스트 파일을 생성합니다. `.answer` 파일은 `cubrid-sql-tc-runone` 스킬을 통해 자동 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-sql-tc-create
```

**사용 예시:**
- "CBRD-12345 sql tc 만들어줘"
- "CBRD-12345 sql tc 작성"
- "sql testcase 초안 작성해줘"

---

### [cubrid-sql-tc-runone](cubrid-sql-tc-runone/)

CTP SQL testcase 한 건을 CTP interactive mode로 실행하고 결과를 리포트하는 스킬. `sql`, `medium`, `sql_by_cci` 카테고리를 지원합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-sql-tc-runone
```

**사용 예시:**
- "cbrd_12345.sql 돌려봐 (빌드 URL: http://...)"
- "이 sql tc 패스하는지 확인해줘"
- "sql tc cbrd_12345 실행"

---

### [cubrid-unittest-tc-create](cubrid-unittest-tc-create/)

CTP C/C++ unittest 초안을 생성하는 스킬. CUBRID 소스 코드 기반의 저수준 유닛 테스트를 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-unittest-tc-create
```

**사용 예시:**
- "CBRD-12345 unittest tc 만들어줘"
- "CBRD-12345 C 유닛 테스트 작성"
- "유닛테스트 초안 작성해줘"

---

### [cubrid-unittest-tc-runone](cubrid-unittest-tc-runone/)

CTP unittest 바이너리 한 건을 실행하고 결과를 리포트하는 스킬.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-unittest-tc-runone
```

**사용 예시:**
- "cbrd_12345 unittest 돌려봐"
- "unittest cbrd_12345 실행"

---

### [cubrid-test-fail-reasoning](cubrid-test-fail-reasoning/)

실패 목록 + 브랜치 + 커밋 범위를 입력으로 받아 모든 실패 testcase를 실행하고, diff 토큰 bisect (`git log -G`)로 각 실패의 원인 커밋을 식별한 뒤, 답지 수정 / 버그 리포트 판정을 포함한 단일 `report.md`를 출력하는 end-to-end 파이프라인. 모든 로직은 Python stdlib 스크립트로 번들되며, 빌드는 플러그형 백엔드(kubectl 파드 또는 HTTP tarball URL — `kubectl`은 사용자 동의 프롬프트를 거침)로 가져옵니다. 세 가지 입력(실패 목록, 브랜치, 커밋 범위)이 모두 제공되지 않으면 단호히 거절합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-test-fail-reasoning
```

**사용 예시:**
- "release/11.3 fail list /tmp/fail.txt 분석해줘 (range good_sha..bad_sha)"
- "이게 답지 수정인지 버그인지 봐줘"
- "develop a1b2c3d..e5f6789 회귀 bisect"

---

### [jira](jira/)

CUBRID JIRA 이슈를 조회해 마크다운으로 보여주는 스킬. 스킬에 stdlib 전용 Python fetcher가 번들되어 있어 Python 패키지·`uv`·별도 CLI 등의 외부 의존성이 없습니다. 단, **`pandoc`은 필수**입니다 (Jira wiki markup → 마크다운 변환). `pandoc`이 없으면 스킬이 사용자에게 설치 여부를 먼저 묻고 동의를 얻은 뒤 진행합니다.

캐시 디렉토리는 `--dir` → `$CUBRID_JIRA_DIR` → `~/.local/share/cubrid-jira/issues/` 순서로 결정됩니다. 한 번 받아온 이슈는 캐시에 남아 다음 호출 때 네트워크 없이 즉시 출력됩니다.

번들된 fetcher 로직은 [vimkim/cubrid-jira-fetcher](https://github.com/vimkim/cubrid-jira-fetcher)에서 가져왔습니다.

> **다른 스킬과의 관계:** `cubrid-*-tc-create` / `cubrid-*-tc-runone` / `cubrid-shell-tc-review` / `cubrid-test-fail-reasoning` 스킬은 CBRD 이슈 번호가 포함된 요청을 받으면 이 `jira` 스킬을 자동으로 호출합니다. 위 스킬 중 하나라도 사용한다면 `jira` 스킬을 함께 설치하길 권장합니다 — 자세한 내용은 상단의 "JIRA 스킬 자동 호출 (cross-cutting)" 섹션을 참고하세요.

**설치:**
```bash
npx skills add tw-kang/skills --skill jira
```

**사용 예시:**
- "CBRD-26463 봐줘"
- "이 JIRA 이슈 요약해줘 (CBRD-25123)"
- "CBRD-26463 무슨 내용이야?"

---

## 전체 설치

모든 스킬을 한 번에 설치하려면:

```bash
# 기본: 모든 스킬을 모든 지원 에이전트(Claude/Cursor/Codex/Gemini/...)에 설치
npx skills add tw-kang/skills --all

# 특정 에이전트만 대상
npx skills add tw-kang/skills --all -a claude-code -a codex -a cursor -a gemini-cli

# 사용자 글로벌 설치
npx skills add tw-kang/skills --all -g
```

폴백 — 수동 복사 (Claude Code 전용, `skills` CLI를 쓰지 못하는 환경에서만):

```bash
cp -r cubrid-cci-tc-create cubrid-cci-tc-runone cubrid-cdc_repl-tc-create cubrid-cdc_repl-tc-runone \
      cubrid-ha_repl-tc-create cubrid-ha_repl-tc-runone cubrid-ha_shell-tc-create cubrid-ha_shell-tc-runone \
      cubrid-isolation-tc-create cubrid-isolation-tc-runone cubrid-jdbc-tc-create cubrid-jdbc-tc-runone \
      cubrid-shell-tc-create cubrid-shell-tc-review cubrid-shell-tc-runone cubrid-sql-tc-create cubrid-sql-tc-runone \
      cubrid-unittest-tc-create cubrid-unittest-tc-runone cubrid-test-fail-reasoning jira ~/.claude/skills/
```

설치 후 해당 에이전트를 재시작하거나 새 세션을 열면 스킬이 활성화됩니다.
