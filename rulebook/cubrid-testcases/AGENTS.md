# cubrid-testcases rulebook

## Terms

| Term | Korean | Meaning |
|---|---|---|
| rulebook | 룰북 | The `AGENTS.md` files and the `<category>/rules/` files that say how to write a TC in this repo. |
| canonical copy | 정본 | The rulebook source in `cubrid-agent`, under `rulebook/<tc repo>/`. QA edits only this copy. |
| deployed copy | 배포본 | The copy of the canonical copy in this repo. Developers and their agents read it. |
| test perspectives | 테스트 관점 | What a TC checks. File: `<category>/rules/test-perspectives.md`. |
| writing rules | 작성 규칙 | How to write the files of a TC. File: `<category>/rules/writing-rules.md`. |
| answer file | 답지 | The file of expected output that a TC compares its output with (`.answer`). |
| bug path | 버그 경로 | The engine code path that the bug of the issue runs through. A TC that never reaches it passes on a build without the fix. |
| header block | 헤더 블록 | The `/** … */` block at the top of a TC file that names the issue and says what the TC checks. Its form is in `sql/rules/writing-rules.md`. |
| evaluate label | 케이스 라벨 | The string of an `evaluate '…';` statement. It shows in the answer file and marks where a scenario of the TC starts. |
| known wrong result | 알려진 오답 | A value in an answer file that is wrong because of an open issue. |
| threshold | 임계값 | A size, counted in rows or pages, at which the engine changes how it runs a query. |
| setup | 준비 단계 | The statements of a TC that create the schema and the data that its scenarios share. |
