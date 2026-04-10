---
name: unittest-create
description: Use this skill whenever the user wants to create, draft, write, or scaffold a new C/C++ unit test for CUBRID CTP's unittest category. These are low-level unit tests compiled from CUBRID source code. Common requests: "unittest tc 만들어줘", "unit test 작성", "create unittest for CUBRID", "새 유닛테스트", "C unit test 추가". NOT for: CCI tests (use cci-create), shell tests (use shell-create), JDBC tests (use jdbc-create).
---

# CUBRID Unittest Creator (CTP)

Generate well-formed CUBRID C/C++ unit test files that integrate with CTP's unittest runner.

## What is a CUBRID Unittest?

CUBRID unittests are C or C++ programs written by developers to test internal CUBRID components at the unit level. Unlike CCI or shell tests, they:

- Are compiled **from CUBRID source code** (not from a separate testcases repo)
- Test **internal APIs and data structures** directly (no broker or server required)
- Are discovered and run by CTP automatically by scanning `$CUBRID/build_release/bin/unittests_*`
- Are pass/fail based on **text output**, not exit codes

## Pass/Fail Criteria

CTP uses this logic to judge each unittest binary:

```bash
if [ `cat ${unittestlog} | grep -i 'fail\|Unit tests failed' | wc -l` -eq 0 \
  -a `cat ${unittestlog} | grep -i 'OK\|success' | wc -l` -ne 0 ]; then
    IS_SUCC=true
fi
```

**PASS** = output has **no** `fail` or `Unit tests failed` (case-insensitive) **AND** has at least one `OK` or `success`.

**FAIL** = output contains `fail` or `Unit tests failed`, OR has no `OK`/`success`.

## Quick Start

1. Identify the CUBRID internal module or function to test.
2. Determine the binary name: `unittests_<module>`.
3. Write the C/C++ test file following the output convention.
4. Place the source in the CUBRID source tree.
5. Add it to the build system (CMakeLists.txt or Makefile).

## File Location in CUBRID Source

Unittest source files live in the CUBRID source repository, not in `cubrid-testcases`. Typical locations:

```
cubrid/unit_tests/<module>/test_<module>.cpp
cubrid/unit_tests/common/test_output.hpp
```

Or within the module being tested:
```
cubrid/src/<module>/test_<name>.c
cubrid/src/<module>/test_<name>.cpp
```

After compilation, the binary appears at:
```
cubrid/build_release/bin/unittests_<module>
cubrid/build_debug/bin/unittests_<module>     # for debug build
```

CTP discovers all files matching `$CUBRID/build_release/bin/unittests_*` automatically.

## Test Output Convention

Your unittest binary must print pass/fail-indicator lines to stdout. Follow these conventions:

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
    /* test logic here */
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

The binary must be installed to `bin/` so CTP finds it as `build_release/bin/unittests_mymodule`.

## Existing Unittest Binaries (reference)

```
build_release/bin/unittests_area       — area/extent management
build_release/bin/unittests_bit        — bit manipulation
build_release/bin/unittests_lf         — lock-free data structures
build_release/bin/unittests_snapshot   — MVCC snapshot logic
```

These are examples of the naming and scope convention.

## Writing Rules

1. **Binary name**: `unittests_<module>` — always plural, always `unittests_` prefix
2. **Print `OK` or `success`** when all tests pass — required for CTP PASS judgment
3. **Print `fail`** for each failing assertion — CTP counts these
4. **No external dependencies** beyond CUBRID internal headers — unittests run without a running CUBRID server
5. **No broker, no server** — unittests test pure C/C++ logic, not server behavior
6. **Build with `build_release`** target (`sh build.sh -t 64 -m release -b build_release`) or `build_debug` for debug builds
7. **One logical module per binary** — keep scope narrow and focused

## Generation Process

1. **Clarify**: Which CUBRID internal function, data structure, or algorithm to test?
2. **Name**: pick `unittests_<module>` matching the module (e.g., `unittests_btree`, `unittests_heap`).
3. **Draft**: C or C++ test file with assertions printing `FAIL:` on failure and `OK` on success.
4. **CMake**: show how to add the binary to the build.
5. **Self-review**:
   - Does the program print `OK` or `success` when all tests pass?
   - Does it print `fail` when any test fails?
   - No hardcoded file paths or server dependencies?
   - Binary will be named `unittests_<module>`?
6. **Present**: source file content + CMakeLists.txt addition.

## Examples

- `@examples/test_simple_module.c` — minimal C unittest template
- `@examples/test_simple_module.cpp` — minimal C++ unittest template

## References

- `~/cubrid-testtools/doc/unittest_guide.md` — full unittest guide
- `$CUBRID/build_release/bin/unittests_*` — existing compiled unittest binaries
- CUBRID source: `unit_tests/` directory in CUBRID git repo
