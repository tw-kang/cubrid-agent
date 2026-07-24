# 스킬의 '완성'은 초안이 아니라 실제 쓰기다 — 호출 축과 분리, 쓰기는 호출 의도로 게이팅

스킬의 종료 산출물(완성 정의)을 **초안 + 리포트**에서 **실제 쓰기**(Jira 전이·코멘트·필드, GitHub PR 리뷰 코멘트 게시, Draft PR→ready PR)로 재정의한다. 단, 실제 쓰기는 **호출 의도**로 게이팅한다: 사람이 이슈/PR 키를 **나열**한 대상 지정(targeted) 호출은 실제 쓰기, 스킬이 **JQL/큐 쿼리**로 집합을 만든 배치(batch) 호출은 초안 유지. 이 재정의는 게시·전이하는 모든 스킬(gate-resolved · review-testcase · author-testcase)에 적용된다.

## 배경 — 두 축이 묶여 있었다

[ADR 0007](./0007-rollout-stages.md)과 [staging.md](../staging.md)는 롤아웃을 PoC → Stage 2(팀내 수동 트리거) → Stage 3(무인 자동 서비스)로 나누면서, 서로 다른 두 축을 하나로 묶었다:

- **호출 축** — 누가 스킬을 시작하나. 사람(Stage 2) vs 무인 트리거/cron(Stage 3).
- **완성 정의 축** — 스킬의 종료 산출물이 초안이냐 실제 쓰기냐.

`adr/0007:11`은 이 둘을 묶어 이렇게 못박았다:

> **Jira 쓰기**(Resolved→Test 전이 + 코멘트)는 **Stage 3부터**. 전이-as-완료마커는 무인 self-healing 루프의 장치라, 사람이 PR을 검토·전이하는 Stage 2까지는 읽기 전용.

`staging.md`도 같은 묶음을 반복한다 — S4 `"Jira 쓰기 | Stage 2까지 읽기 전용 (쓰기=Stage 3)"`(`staging.md:33`), 표의 `"Stage 2 … Jira 읽기 전용"`(`:10`), `"Jira 읽기 전용 — 전이·코멘트는 Stage 3. Stage 2는 사람이 PR 검토 후 수동 전이"`(`:23`).

이 묶음의 결과, Stage 2에서 스킬의 **완성 정의가 "초안 + 사람이 확인 후 수동 처리"** 로 고정됐다. gate-resolved는 반송을 결정해도 로컬 리포트에 코멘트 초안만 적고(`gate-resolved/SKILL.md:102` "the skill drafts only"), review-testcase는 리뷰를 짜도 게시하지 않으며(`review-testcase/SKILL.md:16` "post to GitHub (draft only)"), author-testcase는 Draft PR까지만 연다(`author-testcase/SKILL.md:14`).

**문제**: "무인 서비스"(호출 축)와 "실제 쓰기"(완성 정의 축)는 별개다. 사람이 스킬을 호출하더라도, 그 스킬의 완성이 "실제 게시"일 수 있다. 두 축을 묶어 두면 Stage 2에서 스킬은 늘 반쪽짜리 — 판정은 다 하고도 사람이 그 결과를 손으로 옮겨 적어야 한다. 이 수동 옮겨적기 단계는 판정 정확도가 확보된 뒤에는 지연만 만든다.

## 결정

**완성 정의 축을 호출 축에서 떼어낸다.** 완료마커 쓰기는 호출이 유인이든 무인이든 스킬의 "done" 정의다.

| 축 | Stage 2 | Stage 3 |
|---|---|---|
| **호출** | 사람이 호출 (그대로) | 무인 트리거/cron |
| **완성 정의** | **실제 쓰기** (호출 의도로 게이팅) | 실제 쓰기 |

실제 쓰기는 다음 규칙으로 게이팅한다:

1. **호출 의도로 쓰기 권한 결정 (targeted vs batch).** 사람이 이슈/PR 키를 **나열**하면 targeted → 실제 쓰기. 스킬이 **JQL/큐 쿼리**로 집합을 만들면 batch → 초안. 개수 무관 — JQL이 1건만 반환해도 batch(초안), 사람이 키 3개를 나열하면 targeted(실제 쓰기). 판단 기준은 "사람이 특정 이슈/PR에 책임을 졌는가".
2. **가드 강등 (guard-downgrade).** targeted여도 오탐 가드가 걸리면 게시하지 않고 **초안 + @질의**로 강등한다. 가드: sub-task 형제가 TC/시나리오를 커버하는데 개별 sub-task를 반송하려는 경우(핑퐁, `gate-resolved/SKILL.md:79`), repro "오타"가 line-정확도 버그의 의도된 입력일 수 있는 경우(`SKILL.md:90`, CBRD-26909), 판정 저신뢰. 되돌릴 수 없는 오게시를 막는 마지막 방어선이다.
3. **필드 쓰기 포함.** 통과 시 QA Scenario 재판정(Not Required↔Required)도 targeted에선 실제 쓰기. 전이만 실행하고 필드는 초안이면 "Test로 옮겼는데 필드는 Not Required"인 반쪽 상태가 남기 때문이다. 필드 쓰기는 전이보다 저위험(되돌리기 쉽고 @멘션 알림 없음)이라 함께 커밋해도 무방하다.
4. **감사(audit) 추적.** 실제 게시물에 봇 서명을 남기고("이 판정은 gate-resolved 봇이 자동 수행"), 리포트에 실행된 전이/코멘트의 키·id·시각을 기록한다. 핑퐁·오게시 발생 시 원인 추적과 롤백 판단에 필요하다.

**적용 범위**: 게시·전이하는 모든 스킬.
- **gate-resolved** — 반송(Need Something) 전이 + 반려 코멘트, 통과(Start Test) 전이, QA Scenario 필드.
- **review-testcase** — GitHub PR 리뷰 코멘트 게시. `/review-testcase PR-NNNN`은 본질적으로 targeted. 승인/머지는 여전히 사람(별도 권한).
- **author-testcase** — 완성물이 이미 실제 GitHub 쓰기(PR)다. targeted 호출은 **ready-for-review PR**, batch(큐 N건)는 Draft PR. 머지/승인은 사람. Jira `Start Test` 전이는 gate-resolved 소유이므로 author-testcase가 대신 발사하지 않는다(경계 유지).

## 이 결정이 뒤집는 것 (그리고 뒤집지 않는 것)

**뒤집는다 (완성 정의 축):**
- `adr/0007:11`의 "Jira 쓰기는 Stage 3부터 / Stage 2까지 읽기 전용" 중 **완성 정의 부분**. Stage 2 스킬은 이제 targeted 호출에서 실제로 쓴다.
- `staging.md` S4(`:33`)·표(`:10`)·본문(`:23`)의 "Stage 2 Jira 읽기 전용".
- Stage 3 park 목록(`staging.md:42`)의 "**상태전이=완료마커**" — 완료마커 쓰기 자체는 Stage 2로 내려온다.

**뒤집지 않는다 (호출 축·인프라):** ADR-0007의 나머지는 그대로다.
- Stage 3의 무인 인프라 — CronJob 야간 배치·Indexed Job/dispatcher fan-out·pod 검증(ADR 0001)·overlay·무인 관측은 여전히 Stage 3.
- Stage 3 park 목록의 "**self-healing 재시도/에스컬레이션**"(무인 루프) — 이건 호출 축이라 Stage 3 유지. ("상태전이=완료마커"만 분리해 Stage 2로 내린다.)
- `adr/0007:11`이 든 "전이=완료마커는 무인 self-healing 루프의 장치"라는 관찰 자체는 맞다 — 다만 그것이 **완료마커 쓰기를 무인일 때만 허용할** 이유는 아니다. 유인 호출에서도 완료마커는 완성의 정의다.

## 근거

- **두 축의 혼동을 바로잡는다.** "무인이라 쓴다"가 아니라 "완성이니까 쓴다"가 옳다. 사람이 특정 이슈를 콕 집어 스킬을 돌리는 것은, 그 판정에 책임을 지고 결과를 반영하겠다는 뜻이다. 초안을 만들어 사람이 다시 손으로 옮기는 단계는 판정을 한 번 더 사람이 재작성하는 중복일 뿐이다.
- **위험은 게이트로 남긴다, 능력을 막아서가 아니라.** draft-only가 막던 실제 위험은 오탐 반송 → status 핑퐁(`gate-resolved/DESIGN.md:37`)과 되돌릴 수 없는 @멘션 알림이다. 이 위험은 (1) batch=초안(대량 오게시 차단), (2) 가드 강등(단건 오탐 차단), (3) 감사 서명(사후 추적)으로 정면 방어한다. 능력을 통째로 끄는 것보다 정밀하다.
- **비대칭 반쪽 상태 제거.** 전이는 실행하고 필드/코멘트는 초안이면 Jira 상태가 내부적으로 어긋난다. 완성=실제 쓰기는 이슈를 일관된 종료 상태로 남긴다.
- **CLI가 이미 안전판이다.** `cubrid-jira`는 기본 dry-run이고 `--yes`가 사람의 게이트다(`issue-tracker.md`). 자격 만료 시 401 → exit 2 하드스톱(재시도 없음)이라 조용한 실패가 아니라 크게 실패한다.

## Considered Options

- **draft-only 유지 (현행)**: 가장 안전하나, 판정 정확도가 확보된 뒤에도 수동 옮겨적기 지연을 강제한다 → 사용자가 뒤집기를 요청.
- **호출=배치 전체 무조건 실제 쓰기**: "완성=실제 쓰기"에 가장 충실하나, 큐 스윕 1회로 오탐까지 전부 되돌릴 수 없이 발사 → batch를 초안으로 게이팅해 기각.
- **전부 실제 쓰기 + 실행 중 확인 체크포인트**: 배치도 쓰되 게시 직전 사람 확인. 그러나 "수동 확인 단계 제거"라는 목적과 부딪힘 → 기각(가드 강등이 이 역할의 안전 버전을 이미 수행).
- **targeted 경계를 개수 기준(1건=쓰기)으로**: 명확하나 사람이 3건 나열해도 초안이라 과보수적 → 의도 기준(나열 vs JQL)이 사람의 책임 표명을 더 정확히 반영.
- **targeted 경계에 안전 상한(N건 초과 나열=초안)**: 200개 붙여넣기 방지책이나, 가드 강등이 이슈별로 걸려 애매한 건은 각각 초안으로 떨어지므로 상한 없이도 방어됨 → 기각(magic number 회피).

## Consequences

**구현 체크리스트** (이 ADR을 정본으로 반영):
- `gate-resolved/SKILL.md` — `:14`(staged)·`:79`(draft+manual)·`:102`(drafts only)·Stage matrix(`:94-98`)·description(`:3`)를 "targeted=실제 쓰기 / batch=초안 / 가드 강등"으로.
- `review-testcase/SKILL.md` — `:3,16,77`(draft only)·Stage matrix(`:81-82`)를 동일 규칙으로. 승인/머지는 사람 유지.
- `author-testcase/SKILL.md` — Stage matrix(`:92-93`)에 targeted=ready PR / batch=Draft PR. 머지는 사람, Start Test는 미소유.
- 3개 `evals/evals.json` 재작성 — 단건(targeted)=실제 쓰기 검증, 배치=초안 유지 검증, 가드 케이스=강등 검증. (gate-resolved eval3의 "실행 안 함"은 stage가 아니라 **guard** 때문으로 근거를 바꾼다.)
- `docs/staging.md`·`docs/adr/0007-rollout-stages.md` — 위 supersede 반영(0016 포인터).
- `docs/design-principles.md` — DP4(완성=실제 쓰기, 호출 의도 게이팅) 추가.
- `docs/guides/stage2-setup.md`·`README` — "세 스킬 모두 Jira에 쓰지 않는다" 류 서술 갱신.
- 각 에이전트 `CONTEXT.md` 용어집에 targeted/batch·완성 정의·가드 강등 추가.

**받아들이는 새 실패 모드** (게이트로 완화하되 0은 아님): targeted 단건 오반송(가드를 통과한 경우)은 실제로 나갈 수 있고 @멘션은 되돌릴 수 없다 — 단건이라 blast radius가 작고, 사람이 그 이슈를 콕 집었다는 책임 표명이 전제다.

**Deferred — Stage 3 batch 쓰기**: cron이 JQL 스윕(=batch)을 돌리면 이 ADR 규칙상 초안이지만, Stage 3는 무인 게시가 목적이라 충돌한다. 이 ADR의 **batch=초안은 Stage 2 규칙**으로 한정하고, Stage 3의 무인 batch-write(이벤트 트리거 per-issue로 갈지, batch 스윕을 실제 쓰기로 승격할지)는 Stage 3 설계 시 별도 결정한다.
