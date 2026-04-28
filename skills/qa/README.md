# skills

CUBRID CTP skills installable across **Claude Code, Cursor, Codex, Gemini CLI, and [45+ other agents](https://github.com/vercel-labs/skills#available-agents)** via the [`skills`](https://github.com/vercel-labs/skills) CLI.

## Installation

**Prerequisites:** Node.js ≥ 18 (for `npx`)

```bash
# Install one skill to one or more agents (project scope by default)
npx skills add tw-kang/skills -a claude-code -a codex -a cursor -s cubrid-cci-tc-create

# Install to user (global) directory instead of project
npx skills add tw-kang/skills -g -s cubrid-cci-tc-runone

# Install every skill to every supported agent
npx skills add tw-kang/skills --all

# List available skills without installing
npx skills add tw-kang/skills --list

# Non-interactive (CI/CD)
npx skills add tw-kang/skills -s cubrid-shell-tc-create -a claude-code -g -y
```

See the [`skills` CLI docs](https://github.com/vercel-labs/skills) for the full agent list, `--copy` vs symlink install strategy, and other commands (`npx skills list`, `npx skills update`, `npx skills remove`).

> All skills in this repository were created using the [`skill-creator`](https://github.com/anthropics/skills/tree/main/skills/skill-creator) skill.
>
> **Install skill-creator:**
> ```bash
> npx skills add anthropics/skills --skill skill-creator
> ```
> Then invoke it in Claude Code with `/skill-creator` to scaffold, edit, or benchmark your own skills.

## Skills

| Skill | 설명 |
|-------|------|
| [cubrid-cci-tc-create](cubrid-cci-tc-create/) | CTP CCI testcase 초안 생성 |
| [cubrid-cci-tc-runone](cubrid-cci-tc-runone/) | CTP CCI testcase 단건 실행 및 결과 리포트 |
| [cubrid-cdc_repl-tc-create](cubrid-cdc_repl-tc-create/) | CTP CDC replication testcase 초안 생성 |
| [cubrid-cdc_repl-tc-runone](cubrid-cdc_repl-tc-runone/) | CTP CDC replication testcase 단건 실행 및 결과 리포트 |
| [cubrid-ha_repl-tc-create](cubrid-ha_repl-tc-create/) | CTP HA replication testcase 초안 생성 |
| [cubrid-ha_repl-tc-runone](cubrid-ha_repl-tc-runone/) | CTP HA replication testcase 단건 실행 및 결과 리포트 |
| [cubrid-ha-shell-tc-create](cubrid-ha-shell-tc-create/) | CTP HA shell testcase 초안 생성 |
| [cubrid-ha-shell-tc-runone](cubrid-ha-shell-tc-runone/) | CTP HA shell testcase 단건 실행 및 결과 리포트 |
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

---

### [cubrid-cci-tc-create](cubrid-cci-tc-create/)

CTP CCI(C Client Interface) testcase 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 `.c` 소스 파일과 CCI 테스트 스크립트를 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-cci-tc-create
```

**사용 예시:**
- "CBRD-12345 cci tc 만들어줘"
- "create cci testcase for CBRD-12345"
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
- "run cci test cbrd_12345"

---

### [cubrid-cdc_repl-tc-create](cubrid-cdc_repl-tc-create/)

CTP CDC replication testcase (`.sql`) 초안을 생성하는 스킬. `--test:` / `--check:` 마커 형식을 준수합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-cdc_repl-tc-create
```

**사용 예시:**
- "CBRD-12345 cdc_repl tc 만들어줘"
- "create cdc replication tc for CBRD-12345"

---

### [cubrid-cdc_repl-tc-runone](cubrid-cdc_repl-tc-runone/)

CTP CDC replication testcase 한 건을 실행하고 결과를 리포트하는 스킬. CDC 인프라(소스 + 타깃 노드) 설정이 필요합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-cdc_repl-tc-runone
```

**사용 예시:**
- "cbrd_12345.sql cdc_repl 테스트 돌려봐"
- "run cdc_repl test cbrd_12345"

---

### [cubrid-ha_repl-tc-create](cubrid-ha_repl-tc-create/)

CTP HA replication testcase (`.sql`) 초안을 생성하는 스킬. `--test:` / `--check:` 마커 형식을 준수합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-ha_repl-tc-create
```

**사용 예시:**
- "CBRD-12345 ha_repl tc 만들어줘"
- "create ha replication tc for CBRD-12345"
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
- "run ha_repl test cbrd_12345"

---

### [cubrid-ha-shell-tc-create](cubrid-ha-shell-tc-create/)

CTP HA shell testcase (`.sh`) 초안을 생성하는 스킬. `make_ha.sh` 헬퍼를 활용한 HA 복제 테스트 스크립트를 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-ha-shell-tc-create
```

**사용 예시:**
- "CBRD-12345 ha shell tc 만들어줘"
- "create ha shell tc for CBRD-12345"
- "ha shell testcase 초안 작성해줘"

---

### [cubrid-ha-shell-tc-runone](cubrid-ha-shell-tc-runone/)

로컬 HA 인프라에서 CTP HA shell testcase 한 건을 실행하고 결과를 리포트하는 스킬.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-ha-shell-tc-runone
```

**사용 예시:**
- "cbrd_12345 ha shell tc 돌려봐 (빌드 URL: http://...)"
- "run ha shell test cbrd_12345"

---

### [cubrid-isolation-tc-create](cubrid-isolation-tc-create/)

CTP isolation testcase (`.ctl`) 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 격리 수준 테스트 파일을 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-isolation-tc-create
```

**사용 예시:**
- "CBRD-12345 isolation tc 만들어줘"
- "create isolation tc for CBRD-12345"
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
- "run isolation test cbrd_12345"

---

### [cubrid-jdbc-tc-create](cubrid-jdbc-tc-create/)

CTP JDBC testcase (JUnit 4 Java `@Test` 메서드) 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 Java 테스트 파일을 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-jdbc-tc-create
```

**사용 예시:**
- "CBRD-12345 jdbc tc 만들어줘"
- "create jdbc testcase for CBRD-12345"
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
- "run jdbc test cbrd_12345"

---

### [cubrid-shell-tc-create](cubrid-shell-tc-create/)

CTP shell testcase 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 CTP 규칙을 준수하는 `.sh` 파일을 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-shell-tc-create
```

**사용 예시:**
- "CBRD-12345 버그픽스 shell tc 만들어줘"
- "create shell tc for CBRD-12345"
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
- "run shell tc cbrd_12345"

---

### [cubrid-sql-tc-create](cubrid-sql-tc-create/)

CTP SQL testcase (`.sql` + `.answer`) 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 CTP SQL 테스트 파일을 생성합니다. `.answer` 파일은 `cubrid-sql-tc-runone` 스킬을 통해 자동 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-sql-tc-create
```

**사용 예시:**
- "CBRD-12345 sql tc 만들어줘"
- "create sql tc for CBRD-12345"
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
- "run sql tc cbrd_12345"

---

### [cubrid-unittest-tc-create](cubrid-unittest-tc-create/)

CTP C/C++ unittest 초안을 생성하는 스킬. CUBRID 소스 코드 기반의 저수준 유닛 테스트를 생성합니다.

**설치:**
```bash
npx skills add tw-kang/skills --skill cubrid-unittest-tc-create
```

**사용 예시:**
- "CBRD-12345 unittest tc 만들어줘"
- "create C unit test for CBRD-12345"
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
- "run unittest cbrd_12345"

---

## 전체 설치

모든 스킬을 한 번에 설치하려면:

```bash
# 기본: 모든 스킬을 모든 지원 에이전트(Claude/Cursor/Codex/Gemini/...)에 설치
npx skills add tw-kang/skills --all

# 특정 에이전트만 대상
npx skills add tw-kang/skills --all -a claude-code -a codex -a cursor -a gemini-cli

# user-global 설치
npx skills add tw-kang/skills --all -g
```

Fallback — 수동 복사 (Claude Code 전용, `skills` CLI를 쓰지 못하는 환경에서만):

```bash
cp -r cubrid-cci-tc-create cubrid-cci-tc-runone cubrid-cdc_repl-tc-create cubrid-cdc_repl-tc-runone \
      cubrid-ha_repl-tc-create cubrid-ha_repl-tc-runone cubrid-ha-shell-tc-create cubrid-ha-shell-tc-runone \
      cubrid-isolation-tc-create cubrid-isolation-tc-runone cubrid-jdbc-tc-create cubrid-jdbc-tc-runone \
      cubrid-shell-tc-create cubrid-shell-tc-review cubrid-shell-tc-runone cubrid-sql-tc-create cubrid-sql-tc-runone \
      cubrid-unittest-tc-create cubrid-unittest-tc-runone ~/.claude/skills/
```

설치 후 해당 에이전트를 재시작하거나 새 세션을 열면 스킬이 활성화됩니다.
