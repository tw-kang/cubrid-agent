# skills

CUBRID CTP 스킬 모음. **Claude Code, Cursor, Codex, Gemini CLI를 비롯한 [45개 이상의 에이전트](https://github.com/vercel-labs/skills#available-agents)** 에 [`skills`](https://github.com/vercel-labs/skills) CLI로 설치할 수 있습니다.

카테고리마다 두 가지 액션이 있습니다 — **`create`**(testcase 초안 생성)와 **`verify`**(testcase 한 건을 실행해 OK/NOK를 판정하고, 실패 시 원인까지 진단).

## 설치

**선행 조건:** Node.js 18 이상 (`npx` 사용)

```bash
# 단일 스킬을 하나 이상의 에이전트에 설치 (기본은 프로젝트 스코프)
npx skills add tw-kang/skills -a claude-code -a codex -a cursor -s cubrid-cci-tc-create

# 프로젝트 대신 사용자(글로벌) 디렉토리에 설치
npx skills add tw-kang/skills -g -s cubrid-cci-tc-verify

# 모든 스킬을 모든 지원 에이전트에 설치
npx skills add tw-kang/skills --all

# 사용 가능한 스킬 목록만 확인 (설치하지 않음)
npx skills add tw-kang/skills --list

# 비대화형 (CI/CD)
npx skills add tw-kang/skills -s cubrid-shell-tc-create -a claude-code -g -y
```

지원 에이전트 전체 목록, `--copy` vs symlink 설치 전략, 기타 명령(`npx skills list`, `npx skills update`, `npx skills remove`) 은 [`skills` CLI 문서](https://github.com/vercel-labs/skills)를 참고하세요.

> 이 저장소의 스킬들은 [`skill-creator`](https://github.com/anthropics/skills/tree/main/skills/skill-creator) 스킬로 작성·정비되었습니다. Claude Code에서 `/skill-creator` 명령으로 새 스킬을 생성·편집·벤치마크할 수 있습니다.

## 스킬 목록

| 스킬 | 설명 |
|------|------|
| [cubrid-cci-tc-create](cubrid-cci-tc-create/) | CTP CCI testcase 초안 생성 |
| [cubrid-cci-tc-verify](cubrid-cci-tc-verify/) | CTP CCI testcase 실행·판정·실패 진단 |
| [cubrid-cdc_repl-tc-create](cubrid-cdc_repl-tc-create/) | CTP CDC replication testcase 초안 생성 |
| [cubrid-cdc_repl-tc-verify](cubrid-cdc_repl-tc-verify/) | CTP CDC replication testcase 실행·판정·실패 진단 |
| [cubrid-ha_repl-tc-create](cubrid-ha_repl-tc-create/) | CTP HA replication testcase 초안 생성 |
| [cubrid-ha_repl-tc-verify](cubrid-ha_repl-tc-verify/) | CTP HA replication testcase 실행·판정·실패 진단 |
| [cubrid-ha_shell-tc-create](cubrid-ha_shell-tc-create/) | CTP HA shell testcase 초안 생성 |
| [cubrid-ha_shell-tc-verify](cubrid-ha_shell-tc-verify/) | CTP HA shell testcase 실행·판정·실패 진단 |
| [cubrid-isolation-tc-create](cubrid-isolation-tc-create/) | CTP isolation testcase 초안 생성 |
| [cubrid-isolation-tc-verify](cubrid-isolation-tc-verify/) | CTP isolation testcase 실행·판정·실패 진단 |
| [cubrid-jdbc-tc-create](cubrid-jdbc-tc-create/) | CTP JDBC testcase 초안 생성 |
| [cubrid-jdbc-tc-verify](cubrid-jdbc-tc-verify/) | CTP JDBC testcase 실행·판정·실패 진단 |
| [cubrid-shell-tc-create](cubrid-shell-tc-create/) | CTP shell testcase 초안 생성 |
| [cubrid-shell-tc-verify](cubrid-shell-tc-verify/) | CTP shell testcase 실행·판정·실패 진단 |
| [cubrid-sql-tc-create](cubrid-sql-tc-create/) | CTP SQL testcase (`.sql` + `.answer`) 초안 생성 |
| [cubrid-sql-tc-verify](cubrid-sql-tc-verify/) | CTP SQL testcase 실행·판정·실패 진단 |
| [cubrid-unittest-tc-create](cubrid-unittest-tc-create/) | CTP C/C++ unittest 초안 생성 |
| [cubrid-unittest-tc-verify](cubrid-unittest-tc-verify/) | CTP unittest 실행·판정·실패 진단 |

## JIRA 컨텍스트 (선택적 보강)

모든 스킬은 요청에 `CBRD-XXXXX`(또는 `cbrd_XXXXX`) 토큰이 있으면 [`cubrid-jira`](https://github.com/vimkim/cubrid-jira) CLI로 이슈 컨텍스트를 먼저 조회해 작업 정확도를 높입니다:

```bash
cubrid-jira search CBRD-XXXXX
```

- **선택 사항입니다.** `cubrid-jira`가 설치되어 있지 않으면 스킬은 이 단계를 조용히 건너뛰고 정상 동작합니다 — 다만 설치하면 testcase 작성 범위·기대 동작·실패 판정의 정확도가 눈에 띄게 올라갑니다.
- 따라서 `cubrid-jira` CLI는 스킬의 **런타임 의존성이 아니라 정확도 보강 도구**입니다. 배경과 결정 근거는 [ADR 0005](docs/adr/0005-jira-context-via-cubrid-jira-cli-optional-enrichment.md)를 참고하세요.

---

각 카테고리는 `create` / `verify` 두 스킬을 제공합니다. 설치는 스킬명을 `--skill` 뒤에 넣으면 됩니다.

### cci — `cubrid-cci-tc-create` / `cubrid-cci-tc-verify`

CCI(C Client Interface) testcase. `create`는 CBRD 이슈와 시나리오로 `.c` 소스 + CCI 스크립트 초안을 만들고, `verify`는 한 건을 실행해 OK/NOK를 판정하고 실패 시 원인을 진단합니다.

```bash
npx skills add tw-kang/skills -s cubrid-cci-tc-create -s cubrid-cci-tc-verify
```

**사용 예시:** "CBRD-12345 cci tc 만들어줘" · "cci tc cbrd_12345 돌려봐 (빌드 URL: http://...)" · "이 cci tc 패스하는지 검증해줘"

### cdc_repl — `cubrid-cdc_repl-tc-create` / `cubrid-cdc_repl-tc-verify`

CDC replication testcase (`.sql`, `--test:` / `--check:` 마커). `verify`는 CDC 인프라(소스 + 타깃 노드) 설정이 필요합니다.

```bash
npx skills add tw-kang/skills -s cubrid-cdc_repl-tc-create -s cubrid-cdc_repl-tc-verify
```

**사용 예시:** "CBRD-12345 cdc_repl tc 만들어줘" · "cbrd_12345.sql cdc_repl 테스트 돌려봐" · "cdc_repl tc 실패 원인 알려줘"

### ha_repl — `cubrid-ha_repl-tc-create` / `cubrid-ha_repl-tc-verify`

HA replication testcase (`.sql`, `--test:` / `--check:` 마커). `verify`는 HA 인프라(마스터 + 슬레이브 노드) 설정이 필요합니다.

```bash
npx skills add tw-kang/skills -s cubrid-ha_repl-tc-create -s cubrid-ha_repl-tc-verify
```

**사용 예시:** "CBRD-12345 ha_repl tc 만들어줘" · "cbrd_12345.sql ha_repl 테스트 돌려봐" · "ha_repl tc 검증해줘"

### ha_shell — `cubrid-ha_shell-tc-create` / `cubrid-ha_shell-tc-verify`

HA shell testcase (`.sh`, `make_ha.sh` 헬퍼 기반의 HA 복제 테스트). `verify`는 로컬 HA 인프라에서 실행합니다.

```bash
npx skills add tw-kang/skills -s cubrid-ha_shell-tc-create -s cubrid-ha_shell-tc-verify
```

**사용 예시:** "CBRD-12345 ha shell tc 만들어줘" · "ha shell tc cbrd_12345 돌려봐 (빌드 URL: http://...)" · "ha shell tc 패스하는지 확인"

### isolation — `cubrid-isolation-tc-create` / `cubrid-isolation-tc-verify`

isolation testcase (`.ctl`, 격리 수준 테스트).

```bash
npx skills add tw-kang/skills -s cubrid-isolation-tc-create -s cubrid-isolation-tc-verify
```

**사용 예시:** "CBRD-12345 isolation tc 만들어줘" · "cbrd_12345.ctl isolation 테스트 돌려봐" · "isolation tc 실패 원인 봐줘"

### jdbc — `cubrid-jdbc-tc-create` / `cubrid-jdbc-tc-verify`

JDBC testcase (JUnit 4 Java `@Test` 메서드).

```bash
npx skills add tw-kang/skills -s cubrid-jdbc-tc-create -s cubrid-jdbc-tc-verify
```

**사용 예시:** "CBRD-12345 jdbc tc 만들어줘" · "jdbc tc cbrd_12345 돌려봐 (빌드 URL: http://...)" · "이 jdbc tc 검증해줘"

### shell — `cubrid-shell-tc-create` / `cubrid-shell-tc-verify`

shell testcase (`.sh`, CTP 규칙 준수). `verify`는 CUBRID 빌드 설치 → 실행 → 결과 판정 → 실패 진단까지 처리합니다.

```bash
npx skills add tw-kang/skills -s cubrid-shell-tc-create -s cubrid-shell-tc-verify
```

**사용 예시:** "CBRD-12345 버그픽스 shell tc 만들어줘" · "cbrd_12345 테스트 돌려봐 (빌드 URL: http://...)" · "이 shell tc 패스하는지 확인해줘"

### sql — `cubrid-sql-tc-create` / `cubrid-sql-tc-verify`

SQL testcase (`.sql` + `.answer`). `.answer`는 `verify` 스킬로 생성하며, `verify`는 CTP interactive mode로 `sql`/`medium`/`sql_by_cci` 카테고리를 실행합니다.

```bash
npx skills add tw-kang/skills -s cubrid-sql-tc-create -s cubrid-sql-tc-verify
```

**사용 예시:** "CBRD-12345 sql tc 만들어줘" · "cbrd_12345.sql 돌려봐 (빌드 URL: http://...)" · "이 sql tc 패스하는지 확인해줘"

### unittest — `cubrid-unittest-tc-create` / `cubrid-unittest-tc-verify`

C/C++ unittest (CUBRID 소스 기반 저수준 유닛 테스트).

```bash
npx skills add tw-kang/skills -s cubrid-unittest-tc-create -s cubrid-unittest-tc-verify
```

**사용 예시:** "CBRD-12345 unittest tc 만들어줘" · "cbrd_12345 unittest 돌려봐" · "unittest 실패 원인 진단해줘"

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
cp -r cubrid-cci-tc-create cubrid-cci-tc-verify cubrid-cdc_repl-tc-create cubrid-cdc_repl-tc-verify \
      cubrid-ha_repl-tc-create cubrid-ha_repl-tc-verify cubrid-ha_shell-tc-create cubrid-ha_shell-tc-verify \
      cubrid-isolation-tc-create cubrid-isolation-tc-verify cubrid-jdbc-tc-create cubrid-jdbc-tc-verify \
      cubrid-shell-tc-create cubrid-shell-tc-verify cubrid-sql-tc-create cubrid-sql-tc-verify \
      cubrid-unittest-tc-create cubrid-unittest-tc-verify ~/.claude/skills/
```

설치 후 해당 에이전트를 재시작하거나 새 세션을 열면 스킬이 활성화됩니다.
