# Dev Process v2.4 (CUBRID) — 요약

> 사내 자료 `DevProcess-v2.4.pdf`(대부분 도식)의 텍스트 요약. 원본 PDF는 gitignore(로컬 보관). 우리 4-에이전트가 이 워크플로의 어느 전이를 맡는지는 [../../CONTEXT-MAP.md](../../CONTEXT-MAP.md).

## Jira 워크플로 (상태)

```
Open → Confirmed → Analysis → Develop → Handover → Resolved → Test → Tested → Closed   (+ Backport, reopen)
└──────────────── Dev 팀 ────────────────┘  (triage)  └──────────── QA 팀 ────────────┘
```

전이(공식 액션):
- Open→Confirmed: accept issue (reject = 반려)
- Confirmed→Analysis: Start Analysis
- Analysis→Develop: Start Develop
- Develop→Handover: handover (dev 완료)
- Handover→Resolved: **Accept the fix / Check-in Fix** (또는 Resolve without fix = Bug Invalid)
- Resolved→Test: **Start Test** (+ Assign QA)
- Test→Tested: **Verify** (Stop Test로 되돌림)
- Tested→Closed: **Close**
- Tested→Backport: **Need Backport**
- 예외: 각 단계 ask recommendation(re-triage), reopen, propose a change

## 단계별 역할 (p4)

- **Dev**: analysis · POC · design & review · implement · self test · code review & merge
- **QA**: make test scenario & case · review test case · make test spec · manual · revise regression test

## 핵심 운영 규칙

- **Description (p17)**: description만으로 무엇이 추가/수정됐는지 이해 가능해야. 대상 = QA·PM·기술본부. Handover 시점 최종 반영. 스펙/설정 변경은 본문, 코드 위치·수정 방향·분석은 comment.
- **Handover (p18)**: Fixed version(Planned 대비 머지 version 필수), Need Manual(yes → CUBRIDMAN 이슈 + link), **QA 시나리오**(필요없으면 comment 사유, 필요하면 test case 첨부).
- **Backport (p19)**: Affected version 필수(10.2+ 최신 patch), com-jira↔org-jira 상호 comment 링크, Planned version = develop 코드명, patch release 시점에 반영 결정.
- **Merge (p20)**: squash & merge 영문, 제목 `[jira번호] 영문`, 본문 = Jira URL + 영문 요약, PR 리뷰 소통은 한글 무방, **머지 후 regression test 결과 1~2일 내 확인**, 답지/TC 수정은 comment.

## 도구 (p3)

- Jira: jira.cubrid.org (doc.cubrid.org) · GitHub: github.com/CUBRID
- build & test(sql & medium): **CircleCI** · 리포트(QA home): **qahome.cubrid.org**
- main branch: `develop` · special branch: long-term project

## 우리 프로젝트와의 접점

- cubrid-agent 4 에이전트 = **QA-side 자동화**: gate-resolved(Resolved QA-readiness 검토 → 부적격 `Need Something`으로 Handover 반송), author-testcase(Resolved→Test), test-runner(Test→Tested), close-backport(Tested→Closed/Backport). **Check-in Fix(Handover→Resolved)는 개발자 몫**, dev-side(Open~Develop)는 범위 밖.
- **QA 시나리오 필드** = author-testcase Select 게이트(ADR 0002)의 공식 출처.
- **리포트 = QA home**(repo 아님) → reports/ 커밋 제외 결정과 정합.
- **Merge 규칙** = 우리 PR/커밋 규칙. **build/test=CircleCI** = Stage 3 자동화 접점.
