# ADR 0013 — 첨부 필수 읽기 + cubrid-jira `attachment` 서브커맨드

## Context

cubrid-jira를 쓰는 파이프라인 에이전트(resolve-gate·tc-author·tc-reviewer, 단독 cubrid-sql-tc-create)는 이슈를 description·comment만으로 판단·작성·리뷰해 왔다. **이슈 첨부의 내용은 아무도 다운로드·정독하지 않았다** — resolve-gate가 `attachment` 필드를 파일명 수준으로 언급할 뿐이었다.

2026-07-21 팀 배포 전 스모크에서 tc-author가 CBRD-26864를 처리하며 첨부 `CBRD-26864_testcases.sql`(개발자가 첨부한 테스트케이스, 계정 전환 `csql -u dba`/`csql -u u1` 시나리오 명시)을 안 읽고 작성했다. 재현 절차·기대 결과·의도 시나리오가 첨부에만 있는 이슈가 많아 실제 누락이 발생했다.

## Decision

**1) 정책 — cubrid-jira를 쓰는 모든 에이전트는 판단·작성·리뷰 전에 이슈의 모든 첨부를 다운로드해 읽는다.**
- 메타데이터(파일명·크기·mimeType)는 항상 전부 나열.
- **텍스트·코드**(`.sql .txt .md .log .sh .csv .json`, 소형 `.zip`은 풀어 텍스트) → **정독**.
- **이미지**(Expected/Actual 스크린샷 등) → Read 툴 멀티모달로 **시각 판독**.
- **코어·바이너리·대용량(>5MB)** → 다운로드(또는 skip) 후 "미정독(사유)"만 기록. LLM이 수 GB 코어를 읽을 순 없다.

**2) 메커니즘 — cubrid-jira 업스트림에 `attachment` 서브커맨드 신설(근본 해결).** vimkim/cubrid-jira에 PR. cubrid-jira엔 attachment 서브커맨드가 없었고, `--fields attachment`가 각 첨부의 `content`(다운로드 URL)·`mimeType`·`size`를 이미 준다. 다운로드는 기존 http/session/auth(cli.py·http.py·session.py·auth.py) 재사용.

### 서브커맨드 스펙 (구현 시)
```
cubrid-jira attachment <KEY> [--out DIR] [--list] [--max-bytes N]
```
- 기본: `<KEY>`의 **모든 첨부를 DIR로 다운로드**. DIR 기본 = `~/.local/share/cubrid-jira/attachments/<KEY>/` (기존 `issues/` 캐시 관례와 일치). 파일별 **JSON 매니페스트** 출력: `{filename, size, mimeType, path, downloaded}`.
- `--list`: 다운로드 없이 메타데이터만.
- `--max-bytes N`(기본 5_242_880 = 5MB): 초과 파일은 다운로드 skip + 매니페스트에 `downloaded:false, skipped:"oversize"` 기록.
- 인증·에러·`--output json` 관례는 기존 서브커맨드(comment-list 등)와 동일.
- **책임 분리**: CLI = 다운로드 + 매니페스트. **읽기(위 타입 정책)는 에이전트(LLM)** — 매니페스트의 mimeType·size로 정책 적용.

**3) Interim(서브커맨드 배포 전) — curl fallback.** 각 스킬은 서브커맨드가 없을 때 다음으로 대체한다:
```
cubrid-jira jql 'key=<KEY>' --fields attachment --output json  # 각 .content = 다운로드 URL
curl --netrc -o <out> "<content-url>"                          # jira 자격(.netrc: jira.cubrid.org, 또는 -u $CUBRID_JIRA_USER:$CUBRID_JIRA_PASSWORD)
```
검증됨(2026-07-22, CBRD-26864 첨부 http 200). 서브커맨드 배포 시 스킬 지시를 `cubrid-jira attachment <KEY>` 한 줄로 교체.

## Rollout

- **이번 세션**: 스펙 확정(이 ADR) + 4개 스킬을 interim curl로 즉시 개선(결함 지금 닫음).
- **연기(외부 repo)**: vimkim/cubrid-jira `attachment` 서브커맨드 PR. 배포 후 스킬의 interim 블록을 서브커맨드 호출로 교체.
- **미정(enforcement)**: tc-author manifest에 `verify` 대신 grounding 단계의 `attachments_read`를 기록하고 gate가 "첨부 있는데 미독"을 차단하는 방안은 후속 검토(현재는 지시 강제만; 첨부 읽기는 LLM 판단이라 기계적 hook 검증이 어렵다).

## Consequences

- (+) 재현·의도 시나리오가 첨부에만 있는 이슈에서 누락 제거. resolve-gate 작성가능성 판정 정확도↑(첨부 repo TC 내용 실제 확인).
- (+) 근본 해결이라 cubrid-jira 전 사용자 혜택. 스킬은 자기완결 유지(외부 CLI 호출, docs/ 런타임 참조 없음 — D8 준수).
- (−) 서브커맨드 배포 전까지 스킬에 interim curl이 소량 중복(3~4곳). 서브커맨드 배포 시 한 줄로 수렴 → 중복 해소.
- CBRD-26864 TC는 첨부(계정 전환 시나리오)와 reconcile 필요 — 별도 백로그.
