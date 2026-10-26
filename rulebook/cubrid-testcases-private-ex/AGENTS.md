# cubrid-testcases-private-ex rulebook

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
