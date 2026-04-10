/*
 * test_simple_module.c
 *
 * Example CUBRID unittest for an internal module.
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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* --- Minimal test harness ------------------------------------------------ */

static int total = 0;
static int failed = 0;

#define CHECK(cond, msg) \
    do { \
        total++; \
        if (!(cond)) { \
            printf ("FAIL: %s\n", (msg)); \
            failed++; \
        } \
    } while (0)

#define CHECK_EQ_INT(actual, expected, msg) \
    do { \
        total++; \
        if ((actual) != (expected)) { \
            printf ("FAIL: %s (expected %d, got %d)\n", \
                    (msg), (int)(expected), (int)(actual)); \
            failed++; \
        } \
    } while (0)

#define CHECK_EQ_STR(actual, expected, msg) \
    do { \
        total++; \
        if (strcmp ((actual), (expected)) != 0) { \
            printf ("FAIL: %s (expected '%s', got '%s')\n", \
                    (msg), (expected), (actual)); \
            failed++; \
        } \
    } while (0)

/* --- Functions under test ------------------------------------------------
 * Replace these stubs with actual includes from CUBRID source.
 * Example: #include "some_module.h"
 */

static int
add (int a, int b)
{
  return a + b;
}

static const char *
get_greeting (void)
{
  return "hello";
}

/* --- Test functions ------------------------------------------------------- */

static void
test_add_positive (void)
{
  CHECK_EQ_INT (add (1, 2), 3, "add(1,2) == 3");
  CHECK_EQ_INT (add (0, 0), 0, "add(0,0) == 0");
  CHECK_EQ_INT (add (-1, 1), 0, "add(-1,1) == 0");
}

static void
test_add_overflow_guard (void)
{
  /* test with boundary values */
  CHECK_EQ_INT (add (2147483646, 1), 2147483647, "add near INT_MAX");
}

static void
test_greeting (void)
{
  CHECK_EQ_STR (get_greeting (), "hello", "greeting should be 'hello'");
  CHECK (strlen (get_greeting ()) > 0, "greeting should not be empty");
}

/* --- Main ---------------------------------------------------------------- */

int
main (void)
{
  test_add_positive ();
  test_add_overflow_guard ();
  test_greeting ();

  if (failed == 0)
    {
      printf ("All %d tests passed. OK\n", total);
      return 0;
    }
  else
    {
      printf ("%d of %d tests failed. Unit tests failed\n", failed, total);
      return 1;
    }
}
