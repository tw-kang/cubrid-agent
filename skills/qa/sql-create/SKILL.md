---
name: sql-create
description: Use this skill whenever the user wants to create, draft, write, or scaffold a new SQL testcase (.sql + .answer) for CUBRID CTP. This is the right skill any time someone needs a new SQL test produced from scratch for a CBRD issue — bug fix or new feature. Common requests: "sql tc 만들어줘", "sql tc 초안 작성해줘", "create sql tc", "draft sql test", "새 sql testcase", "sql 테스트케이스 작성", "create draft sql tc for CBRD-XXXXX". NOT for: running existing SQL tests, reviewing diffs/PRs, CTP configuration, or general SQL scripting unrelated to CTP test creation.
---

# SQL Testcase Creator (CTP)

Generate well-formed CUBRID CTP SQL testcase files (`.sql` + `.answer`).

## Quick Start

1. Gather context: JIRA issue ID, feature/bug under test, expected behavior.
2. Determine directory path (bug fix vs. new feature).
3. Generate the `.sql` file following format conventions below.
4. Run the `.sql` via `sql-runone` skill to generate the `.answer` file.
5. Output both file paths and contents.

## Directory Path Convention

### Bug fixes

```
sql/_13_issues/_{yy}_{1|2}h/cases/cbrd_XXXXX.sql
sql/_13_issues/_{yy}_{1|2}h/answers/cbrd_XXXXX.answer
```

- `{yy}` = two-digit year, `{1|2}h` = first/second half of year
- Multiple tests for same issue: append suffix (`cbrd_27100_select.sql`, `cbrd_27100_update.sql`)

### New features

```
sql/_{no}_{release_code}/{feature_group}/cases/cbrd_XXXXX.sql
sql/_{no}_{release_code}/{feature_group}/answers/cbrd_XXXXX.answer
```

Multiple SQL test files share the same `cases/` and `answers/` directories — do not create per-test subdirectories.

## SQL File Format

```sql
/**
 * This test case verifies CBRD-XXXXX: Brief one-line title
 *
 * Coverage:
 * 1 - Scenario one description
 * 2 - Scenario two description
 */

--+ server-message on

DROP TABLE IF EXISTS tbl_name;
CREATE TABLE tbl_name (col1 INT, col2 VARCHAR(100));
INSERT INTO tbl_name VALUES (1, 'hello'), (2, 'world');

evaluate 'Case 1: description of what this tests';
SELECT col1, col2 FROM tbl_name WHERE col1 = 1;

evaluate 'Case 2: description of expected error';
SELECT col1 / 0 FROM tbl_name;

DROP TABLE IF EXISTS tbl_name;

--+ server-message off
```

### Header block

Always start with `/** ... */` comment:
- First line: `This test case verifies CBRD-XXXXX: <title>`
- `Coverage:` section listing numbered scenarios

### `evaluate` statements

Use `evaluate 'Case N: description'` before each test scenario. Number sequentially. This is the sole section marker — do NOT add `-- ===` style comment headers.

### `--+ server-message on/off`

Enable when testing error messages (negative tests expecting `-NNN` errors). Always pair on/off. Skip when the test only checks result sets.

### Setup and cleanup

- `DROP TABLE IF EXISTS` before every `CREATE TABLE` (re-runnable)
- Setup at top, cleanup at bottom
- Keep setup minimal, use simple names (`tbl1`, `col1`)

### Query plan tests

When verifying optimizer decisions, create an empty `.queryPlan` file alongside the `.sql`:
```
cases/cbrd_XXXXX.sql
cases/cbrd_XXXXX.queryPlan   ← empty file
answers/cbrd_XXXXX.answer
```

## Writing Rules

- Use explicit column lists in `INSERT` when it aids readability
- Keep test SQL focused — avoid unrelated complexity
- Prefer simple data values for easy answer diffs
- 3–10 `evaluate` sections per file is typical
- Each error case should have its own `evaluate` label

### Parameter changes (rare)
```sql
SET SYSTEM PARAMETERS 'param_name=value';
-- ... test ...
SET SYSTEM PARAMETERS 'param_name=original_value';
```

### `holdcas` directive (rare)
```sql
--+ holdcas on;
-- ... transaction-sensitive test ...
--+ holdcas off;
```

## Answer File Generation

`.answer` 파일은 직접 작성하지 않는다. `sql-runone` 스킬을 사용하여 생성한다.

### 절차

1. `.sql` 파일을 `cases/` 디렉토리에 작성한다.
2. `sql-runone` 스킬을 호출하여 해당 `.sql` 파일을 CTP로 실행한다.
   - 빌드 URL이 필요하다 — 사용자에게 요청하거나 이미 제공된 URL을 사용한다.
3. CTP 실행 후 `cases/` 디렉토리에 `.result` 파일이 생성된다.
4. `.result` 파일을 `answers/` 디렉토리에 `.answer` 확장자로 복사한다:

```bash
BASENAME=cbrd_XXXXX
cp sql/_13_issues/_26_1h/cases/${BASENAME}.result \
   sql/_13_issues/_26_1h/answers/${BASENAME}.answer
```

5. `.answer` 파일 내용을 확인하여 기대한 결과와 일치하는지 검토한다.
   - DDL/DML: 영향받은 행 수 (`0` 또는 정수)
   - SELECT: 컬럼 헤더 + 데이터 행
   - 에러: `Error:-NNN\n<에러 메시지>`
   - 각 SQL 문 출력은 `===...===` 줄로 구분

빌드 URL이 없거나 CUBRID 환경이 없는 경우, `.answer` 파일은 빈 파일로 생성하고 추후 `sql-runone`으로 완성하도록 안내한다.

## Generation Process

1. **Clarify the test target**: JIRA issue ID, behavior under test, test type (bug fix / new feature).
2. **Determine the directory path**: current date (year + half) for bug fixes, or release code for new features.
3. **Draft the `.sql` file**: header → server-message → setup → evaluate sections → cleanup.
4. **Generate `.answer`**: invoke `sql-runone` skill to run the test and copy `.result` → `.answer`.
5. **Self-review**: header present? evaluate labels? DROP IF EXISTS? server-message paired? queryPlan needed?
6. **Present the output**: show file paths and contents.

## Examples

- `@examples/bug_fix_error_cases.sql` — negative test with server-message
- `@examples/bug_fix_select.sql` — basic SELECT result verification
- `@examples/feature_query_plan.sql` — test with queryPlan for optimizer verification
