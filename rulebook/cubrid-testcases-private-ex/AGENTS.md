# cubrid-testcases-private-ex rulebook

The rules for the TCs under `shell/` are in [shell/AGENTS.md](shell/AGENTS.md) and the two files it links.

**Open the clone of this repo as the working directory for TC work.** An agent finds `shell/AGENTS.md` only when it lies under the working directory. Example: start the agent in `~/cubrid-testcases-private-ex`, not in `~/cubrid` with an absolute path to `~/cubrid-testcases-private-ex/shell/`.

**Propose a *rulebook* change to the QA team in [CUBRIDQA-1505](https://jira.cubrid.org/browse/CUBRIDQA-1505) or as a PR to [cubrid-agent](https://github.com/tw-kang/cubrid-agent), with one piece of evidence.** This repo holds the *deployed copy*; QA edits the *canonical copy* in `cubrid-agent` and deploys it here after approval. The evidence is one of a review that rejected a TC (comment link), a regression failure (QAHome or CI link), or a mining result. Example: a comment on CUBRIDQA-1505 that proposes a rule and links the CI run it would have prevented.

## Terms

| Term | Korean | Meaning |
|---|---|---|
| rulebook | 룰북 | The `AGENTS.md` files and the `<category>/rules/` files that say how to write a TC in this repo. |
| canonical copy | 정본 | The rulebook source in `cubrid-agent`, under `rulebook/<tc repo>/`. QA edits only this copy. |
| deployed copy | 배포본 | The copy of the canonical copy in this repo. Developers and their agents read it. |
| test perspectives | 테스트 관점 | What a TC checks. File: `<category>/rules/test-perspectives.md`. |
| writing rules | 작성 규칙 | How to write the files of a TC. File: `<category>/rules/writing-rules.md`. |
| verdict | OK/NOK 판정 | One `write_ok` or `write_nok` call in a TC. |
| answer file | 답지 | The file of expected output that a TC compares its output with (`.answer`). |
| quarantine | 격리 | Moving an unstable TC to the same relative path under `_25_unstable`. |
| exclusion | 제외 | Adding a TC to the excluded list. |
| wait limit | 대기 상한 | The timeout given to `wait_until`. |
| owner checklist | 담당자 확인 목록 | The list in a rulebook PR body of the points that the category owner confirms. |
| CI pod | CI 파드 | The pod in which the CI of the engine repo (`CUBRID/cubrid`) runs the TCs. |
| VM daily | VM 정기 회귀 | The daily regression on shared VMs. |
| excluded list | 제외 목록 | The file of the TC paths that no regression runs: `shell/config/daily_regression_test_excluded_list_linux.conf`. |
