/*
 * test_simple_module.cpp
 *
 * Example CUBRID unittest in C++ for an internal module.
 *
 * Compile (as part of CUBRID build):
 *   sh build.sh -t 64 -m release -b build_release
 *
 * The resulting binary must be named unittests_<module>:
 *   build_release/bin/unittests_simple_module
 *
 * CTP discovery: CTP scans $CUBRID/build_release/bin/unittests_* automatically.
 *
 * Pass criteria (CTP logic):
 *   PASS = output has 'OK' or 'success' AND no 'fail' or 'Unit tests failed'
 *   FAIL = output contains 'fail', OR no 'OK'/'success' found
 */

#include <iostream>
#include <string>
#include <vector>
#include <cstring>

/* --- Minimal test harness ------------------------------------------------ */

static int total_checks = 0;
static int failed_checks = 0;

#define CHECK(cond, msg) \
    do { \
        total_checks++; \
        if (!(cond)) { \
            std::cout << "FAIL: " << (msg) << std::endl; \
            failed_checks++; \
        } \
    } while (0)

#define CHECK_EQ(actual, expected, msg) \
    do { \
        total_checks++; \
        if ((actual) != (expected)) { \
            std::cout << "FAIL: " << (msg) \
                      << " (expected " << (expected) \
                      << ", got " << (actual) << ")" << std::endl; \
            failed_checks++; \
        } \
    } while (0)

/* --- Functions/classes under test ----------------------------------------
 * Replace these stubs with actual includes from CUBRID source.
 * Example: #include "some_module.hpp"
 */

class StringHelper
{
public:
  static std::string
  trim (const std::string &s)
  {
    size_t start = s.find_first_not_of (" \t\n\r");
    size_t end = s.find_last_not_of (" \t\n\r");
    if (start == std::string::npos)
      return "";
    return s.substr (start, end - start + 1);
  }

  static bool
  starts_with (const std::string &s, const std::string &prefix)
  {
    return s.substr (0, prefix.size ()) == prefix;
  }
};

/* --- Test functions ------------------------------------------------------- */

static void
test_trim_basic ()
{
  CHECK_EQ (StringHelper::trim ("  hello  "), std::string ("hello"),
	    "trim removes leading/trailing spaces");
  CHECK_EQ (StringHelper::trim ("hello"), std::string ("hello"),
	    "trim on clean string is no-op");
  CHECK_EQ (StringHelper::trim ("   "), std::string (""),
	    "trim all-whitespace returns empty");
}

static void
test_starts_with ()
{
  CHECK (StringHelper::starts_with ("hello world", "hello"),
	 "starts_with 'hello'");
  CHECK (!StringHelper::starts_with ("hello world", "world"),
	 "does not start_with 'world'");
  CHECK (StringHelper::starts_with ("", ""),
	 "empty string starts_with empty prefix");
}

static void
test_trim_tabs_newlines ()
{
  CHECK_EQ (StringHelper::trim ("\t  cubrid  \n"), std::string ("cubrid"),
	    "trim removes tabs and newlines");
}

/* --- Main ---------------------------------------------------------------- */

int
main ()
{
  test_trim_basic ();
  test_starts_with ();
  test_trim_tabs_newlines ();

  if (failed_checks == 0)
    {
      std::cout << "All " << total_checks << " tests passed. OK" << std::endl;
      return 0;
    }
  else
    {
      std::cout << failed_checks << " of " << total_checks
		<< " tests failed. Unit tests failed" << std::endl;
      return 1;
    }
}
