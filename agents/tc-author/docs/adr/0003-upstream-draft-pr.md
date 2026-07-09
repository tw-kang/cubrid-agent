# PoC 산출물도 upstream에 Draft PR로 연다

PoC 산출물이므로 fork(tw-kang/cubrid-testcases) 내부 PR로 격리하는 안이 자연스러워 보이지만, **upstream(CUBRID/cubrid-testcases:develop ← tw-kang:이슈브랜치) Draft PR**로 결정했다. 기존 `cubrid-tc-sync-bot`도 upstream에 Draft PR을 올리는 선례가 있고, Draft 상태가 "검토 전"이라는 신호를 이미 제공하므로 별도 격리 계층이 불필요하다. 봇 산출물임은 브랜치 prefix(`tc/`)와 PR 본문으로 식별한다. fork 내부 PR로 되돌리는 비용은 낮지만, 이 결정을 모르는 독자가 "PoC인데 왜 upstream에 여나"라고 되돌리지 않도록 기록해 둔다.
