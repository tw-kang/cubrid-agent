# fail.txt format

Each failing TC appears as a block. The first non-empty line of a block is the
TC path with one of the recognized category prefixes (the parser's
`HEADER_RE`):

```
shell|sql|ha_shell|ha_repl|cdc_repl|isolation|jdbc|cci|unittest
```

followed by `/<sub-path>/...<.sh|.sql|.test|...>`. All subsequent non-empty
lines until the next path line are treated as the **annotation** and stored
verbatim. The annotation typically contains a row like:

```
2  N  Y  22h:1m  Won-ryong song  verified  [unknown] 원인 불명: <reason>
```

`generate_report.py` extracts `<reason>` (lines containing 원인/unknown/바뀜/
추가/원인:) into the report's *Symptom* column.

Example block (from the 11.3.5 round):

```
shell/_06_issues/_17_1h/cbrd_20145_1/cases/cbrd_20145_1.sh
[0]
[history]  [AI Analysis]  [verify]
2  N  Y  22h:1m  Won-ryong song  verified  [unknown] 원인 불명: QM_QUERY_DROP_ALL_PLANS 값이 바뀜
    25
```

Counter-examples (rejected by `parse_fail_list.py` because the leading
directory is not a recognized category):

```
build/intermittent/timeout.sh        # 'build' is not a category
random_dir/foo.sh                    # 'random_dir' is not a category
```

If you need to support additional test categories, extend
`CATEGORY_TO_RUNONE` in `scripts/parse_fail_list.py`.
