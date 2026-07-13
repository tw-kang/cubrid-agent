# Stage 2 설계 — tc-author 팀 수동 트리거

PoC(Stage 1)에서 검증된 tc-author 파이프라인을, **팀원이 자기 로컬에서 커맨드 하나로** 돌리고 Draft PR까지 내되 필수 게이트는 우회 불가하게 패키징하는 설계. 상위 결정은 [staging.md](./staging.md)(S1–S5)·[ADR 0007](./adr/0007-rollout-stages.md), 게이트 근거는 [ADR 0009](../agents/tc-author/docs/adr/0009-poc2-pipeline-hardening.md). **이 문서는 설계만** — 구현(스킬/hook 코드)은 다음 단계.

핵심 형태(결정): **얇은 오케스트레이터**. `resolve-next`가 Select·Ground·Review·loop·Submit만 오케스트레이션하고, Author/Verify는 기존 `cubrid-sql-tc-create`/`cubrid-sql-tc-verify` 스킬을 호출한다(PoC 자산 재사용, 로직 중복 없음).

## 1. `resolve-next` 스킬 (오케스트레이터)

- 배치: `cubrid-agent/agents/tc-author/.claude/skills/resolve-next/`(git으로 팀 공유·버전관리).
- 호출: `/resolve-next [N | CBRD-XXXXX]` — N건 처리(기본 1) 또는 특정 이슈.
- 흐름(각 단계가 호출하는 자산):

  | 단계 | 하는 일 | 재사용 자산 |
  |---|---|---|
  | Select | JQL 후보 조회 → repro/SQL재현성/중복 판정 → 대기열 | `cubrid-jira`, DESIGN §Select |
  | Ground | fix 커밋/PR diff·기존 TC(동작기준 커버리지 검색) 대조 | `~/cubrid`, `work/cubrid-testcases`, ADR 0009 |
  | Author | `.sql` 작성(경로 유도·evaluate·독립성·영문) | **`cubrid-sql-tc-create`** |
  | Verify | 로컬 CTP: answer 생성·결정성 N=3·경로 커버리지·(CCI 교차)·fail→pass | **`cubrid-sql-tc-verify`** |
  | Review | fresh-context 서브에이전트 심사 | DESIGN §Review |
  | loop | 게이트 미통과 시 Author↔Verify↔Review 재수행(최소 2·최대 5) | — |
  | Submit | 커밋·push·Draft PR(사용자 확인) | `gh`, DESIGN §Submit |

- 각 단계 종료 시 **run manifest**(§2)에 결과 기록. 오케스트레이터는 로직을 재구현하지 않고 스킬·도구를 호출·연결하는 얇은 층.

## 2. 증거 추적 — run manifest (하드 게이트의 근거)

hook이 게이트 통과를 기계적으로 확인하려면, 파이프라인이 결과를 남긴 파일이 필요하다.

- 위치: `work/<CBRD-XXXXX>/manifest.json`(gitignore된 `work/` 아래).
- 스키마(초안):
  ```json
  {
    "issue": "CBRD-26799", "branch": "tc/cbrd-26799", "build": "11.5.0.2300-04192d6",
    "author": {"sql": "...path", "answer_generated": true},
    "verify": {
      "success": true, "determinism": {"n": 3, "all_pass": true},
      "path_coverage": {"checked": true, "method": "queryplan", "on_path": true},
      "cci": {"checked": true, "matches_csql": true},
      "fail_to_pass": {"status": "confirmed|best_effort|deferred", "prefix_build": "...", "note": "race, 로컬 미재현"}
    },
    "review": {"verdict": "PASS", "loops": 2},
    "lint": {"header": true, "evaluate": true, "cleanup": true, "answer_not_handwritten": true, "english_comments": true}
  }
  ```
- 신뢰 모델: Stage 2는 **신뢰된 팀원의 실수 방지용 가드레일**(적대적 우회 방지 아님). manifest는 파이프라인이 기록하고 hook이 검사 — 팀원이 고의로 조작하면 막지 못하나, 게이트를 **깜빡 건너뛰는 것**은 막는다. (적대적 강제는 Stage 3에서 CTP 결과 산출물 직접 검증으로.)

## 3. 하드 게이트 = hook (우회 불가)

스킬·CLAUDE.md는 '요청'이라 우회 가능 → 필수 게이트는 Claude Code hook으로 강제.

| hook 이벤트 | 검사 | 동작 |
|---|---|---|
| **PreToolUse** (Bash가 `gh pr create` 매칭) | manifest의 `verify.determinism.all_pass`, `verify.fail_to_pass.status ∈ {confirmed, best_effort(+note)}`, `review.verdict=PASS`, `lint.*` | 미충족 시 **제출 차단**(deny) + 사유 출력 |
| **PreToolUse** (Bash가 `git push` 매칭, 선택) | 위와 동일(브랜치→이슈 매핑) | push 차단 |
| **PostToolUse** (Write/Edit가 `cases/*.sql`) | 컨벤션 린트(헤더·`evaluate`·DROP-before-CREATE·answer 손작성 아님·영문 주석) → manifest.lint 갱신 | 위반 경고 + manifest 기록 |
| **Stop** (세션 종료) | manifest 미완(게이트 누락) 경고 | 미완 항목 리마인드 |

- fail→pass가 race라 `best_effort`인 경우: `note` 필수(무엇을 왜 못 했는지) — 그래야 제출 통과. 빈 best_effort는 차단.
- hook은 셸 스크립트로 `.claude/settings.json`(팀 공유)에 등록.

## 4. CCI 교차 검증 (S3, Stage 2 채택)

- Verify에 공식 9단계 step 6 추가: `run_cci`로 동일 `.sql`을 CCI 인터페이스로 실행.
- csql 결과와 다르면 `.answer_cci` 생성(인터페이스별 답지). 같으면 불필요.
- `cubrid-sql-tc-verify`가 이미 `sql_by_cci`/`run_cci`를 지원 → 오케스트레이터가 Verify에서 한 번 더 호출.

## 5. 팀 셋업 문서 (구조)

`agents/tc-author/SETUP.md`(신규, 다음 단계 작성). 담을 것 — PoC에서 규명한 함정을 셋업 가이드로:
- 로컬 CTP·CUBRID 설치: **짧은 경로**(소켓 108자 한계), release + 필요 시 `-debug`, `make_locale.sh`.
- `JAVA_HOME`은 **JDK**(javac) — JRE 아님(Java SP 컴파일).
- 빌드서버 URL 규칙(`192.168.1.91:8080/REPO_ROOT/store_01/<ver>/drop/...`), pre-fix 빌드 찾는 법(fix 직전 커밋).
- `cubrid-jira`(~/.netrc)·`gh` 인증(fork=tw-kang, base=CUBRID).
- CTP conf: 사용자 `~/cubrid-testcases` 불가침 → `sql.poc.conf` 사본으로 scenario 지정.
- empty-answer 트릭, 결정성 N=3, 경로 커버리지 확인법.

## 6. 유지(PoC와 동일)

- **Jira 읽기 전용**(S4): 전이·코멘트는 Stage 3. Stage 2는 사람이 PR 검토 후 수동 전이.
- **멱등성**: 결정적 `tc/cbrd-XXXXX` 브랜치/PR, 기존 존재 시 스킵.
- **언어**: `.sql` 주석·커밋 영문 / PR 본문 한글.

## 7. Stage 2에서 하지 않는 것 (= Stage 3)

k8s Job/pod 검증, dispatcher, 병렬 fan-out, 자동 스케줄, Jira 쓰기, self-healing 재시도/에스컬레이션, 무인 관측, rate-limit 분리 — 전부 park.

## 8. 열린 질문 (구현 전 결정 필요)

- manifest를 오케스트레이터가 직접 쓸지, 각 스킬이 자기 몫을 append할지.
- hook이 브랜치명→이슈→manifest 경로를 어떻게 해석할지(명명 규칙 의존).
- 컨벤션 린트를 hook(셸)로 할지, Review 서브에이전트로 할지, 둘 다.
- best_effort fail→pass의 승인 기준(note만으로 충분한지 vs 리뷰어 승인 필요).
- resolve-next를 tc-author 전용으로 둘지, 4개 에이전트 공용 오케스트레이터로 일반화할지.
