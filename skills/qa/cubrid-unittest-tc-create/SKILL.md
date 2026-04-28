---
name: cubrid-unittest-tc-create
description: "Use this skill whenever the user wants to create, draft, write, or scaffold a new C/C++ unit test for CUBRID CTP's unittest category. These are low-level unit tests compiled from CUBRID source code. Common requests: \"unittest tc 만들어줘\", \"unit test 작성\", \"create unittest for CUBRID\", \"새 유닛테스트\", \"C unit test 추가\". NOT for: CCI tests (use cubrid-cci-tc-create), shell tests (use cubrid-shell-tc-create), JDBC tests (use cubrid-jdbc-tc-create)."
---

# CUBRID Unittest Creator (CTP)

Generate well-formed CUBRID C/C++ unit test files that integrate with CTP's unittest runner.

## Prerequisites — CTP Installation Check (mandatory first step)

```bash
# Detect CTP_HOME: $CTP_HOME env var → $HOME/CTP → ~/cubrid-testtools/CTP (in order)
if [ -n "$CTP_HOME" ] && [ -f "$CTP_HOME/bin/ctp.sh" ]; then
    echo "CTP found: $CTP_HOME"
elif [ -f "$HOME/CTP/bin/ctp.sh" ]; then
    export CTP_HOME=$HOME/CTP
elif [ -f "$HOME/cubrid-testtools/CTP/bin/ctp.sh" ]; then
    export CTP_HOME=$HOME/cubrid-testtools/CTP
else
    echo "CTP not found"; exit 1
fi
# Verify conf directory exists
ls $CTP_HOME/conf/
```

If `ctp.sh` or `conf/` is not found, stop and display:

> "CTP is not installed. This skill cannot proceed.
> Installation: `git clone https://github.com/CUBRID/cubrid-testtools.git`
> Reference: ~/cubrid-testtools/doc/ctp_install_guide.md"

## What is a CUBRID Unittest?

C/C++ programs that test internal CUBRID components at the unit level. Compiled from CUBRID source (not testcases repo), test internal APIs directly (no broker/server), discovered by CTP via `$CUBRID/build_release/bin/unittests_*`, and judged by text output (not exit codes).

## Pass/Fail Criteria

CTP judges each unittest binary by scanning stdout:

```bash
if [ `cat ${unittestlog} | grep -i 'fail\|Unit tests failed' | wc -l` -eq 0 \
  -a `cat ${unittestlog} | grep -i 'OK\|success' | wc -l` -ne 0 ]; then
    IS_SUCC=true
fi
```

- **PASS** = no `fail`/`Unit tests failed` (case-insensitive) AND at least one `OK`/`success`
- **FAIL** = contains `fail`/`Unit tests failed`, OR no `OK`/`success`

## File Location

Source files live in the CUBRID source repo (not `cubrid-testcases`):

```
cubrid/unit_tests/<module>/test_<module>.cpp
cubrid/unit_tests/common/test_output.hpp
cubrid/src/<module>/test_<name>.c
cubrid/src/<module>/test_<name>.cpp
```

Compiled binaries:
```
cubrid/build_release/bin/unittests_<module>
cubrid/build_debug/bin/unittests_<module>
```

## Test Output Convention

The binary must print pass/fail indicators to stdout.

### Minimal C example
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failed = 0;

#define ASSERT_EQ(a, b, msg) \
    do { \
        if ((a) != (b)) { \
            printf("FAIL: %s (expected %d, got %d)\n", msg, (int)(b), (int)(a)); \
            failed++; \
        } \
    } while (0)

#define ASSERT_STR_EQ(a, b, msg) \
    do { \
        if (strcmp((a), (b)) != 0) { \
            printf("FAIL: %s (expected '%s', got '%s')\n", msg, (b), (a)); \
            failed++; \
        } \
    } while (0)

static void test_example_function(void)
{
    int result = 1 + 1;
    ASSERT_EQ(result, 2, "1+1 should equal 2");
}

int main(void)
{
    test_example_function();

    if (failed == 0) {
        printf("All tests passed. OK\n");
        return 0;
    } else {
        printf("%d test(s) failed.\n", failed);
        return 1;
    }
}
```

### Minimal C++ example
```cpp
#include <iostream>
#include <cassert>
#include <string>

static int failed = 0;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            std::cout << "FAIL: " << (msg) << std::endl; \
            failed++; \
        } \
    } while (0)

static void test_string_ops()
{
    std::string s = "hello";
    CHECK(s.length() == 5, "string length should be 5");
    CHECK(s.substr(0, 3) == "hel", "substr(0,3) should be 'hel'");
}

int main()
{
    test_string_ops();

    if (failed == 0) {
        std::cout << "All unit tests passed. OK" << std::endl;
        return 0;
    } else {
        std::cout << failed << " unit test(s) failed." << std::endl;
        return 1;
    }
}
```

## Output Rules

| Requirement | Details |
|-------------|---------|
| Print `OK` or `success` (case-insensitive) on pass | Required for CTP to record PASS |
| Print `fail` or `Unit tests failed` on failure | CTP will record FAIL |
| One binary per module | Named `unittests_<module>` |
| stdout, not stderr | CTP reads stdout for pass/fail |
| Exit code is not used | CTP checks output text, not exit code |

## Build Integration

### CMakeLists.txt (typical pattern)
```cmake
add_executable(unittests_mymodule
    unit_tests/mymodule/test_mymodule.cpp
    src/mymodule/mymodule.c        # module under test
)
target_include_directories(unittests_mymodule PRIVATE src/include)
target_link_libraries(unittests_mymodule cubrid_static)
install(TARGETS unittests_mymodule DESTINATION bin)
```

The binary must install to `bin/` so CTP discovers it.

## Existing Unittest Binaries

```
build_release/bin/unittests_area       — area/extent management
build_release/bin/unittests_bit        — bit manipulation
build_release/bin/unittests_lf         — lock-free data structures
build_release/bin/unittests_snapshot   — MVCC snapshot logic
```

## Writing Rules

1. **Binary name**: `unittests_<module>` — always plural, always `unittests_` prefix
2. **Print `OK` or `success`** when all tests pass — required for CTP PASS judgment
3. **Print `fail`** for each failing assertion — CTP counts these
4. **No external dependencies** beyond CUBRID internal headers — unittests run without a running CUBRID server
5. **No broker, no server** — unittests test pure C/C++ logic, not server behavior
6. **Build with `build_release`** (`sh build.sh -t 64 -m release -b build_release`) or `build_debug`
7. **One logical module per binary**

## Generation Checklist

- Prints `OK`/`success` when all tests pass?
- Prints `fail` when any test fails?
- No hardcoded file paths or server dependencies?
- Binary named `unittests_<module>`?
- CMakeLists.txt entry included?

## Examples

- `@examples/test_simple_module.c` — minimal C unittest template
- `@examples/test_simple_module.cpp` — minimal C++ unittest template

## References

- `~/cubrid-testtools/doc/unittest_guide.md` — full unittest guide
- `$CUBRID/build_release/bin/unittests_*` — existing compiled unittest binaries
- CUBRID source: `unit_tests/` directory in CUBRID git repo
