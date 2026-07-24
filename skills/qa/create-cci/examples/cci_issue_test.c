#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cas_cci.h"

/* Issue test: verify cci_connect_with_url query_timeout option.
 * Usage: ./test <broker_port> <dbname> <timeout_ms>
 */

int
main (int argc, char *argv[])
{
  int port, conn, req, res;
  int timeout_ms;
  char url[512];
  char *dbname;
  T_CCI_ERROR error;

  if (argc < 4)
    {
      fprintf (stderr, "Usage: %s <port> <dbname> <timeout_ms>\n", argv[0]);
      return 1;
    }

  port = atoi (argv[1]);
  dbname = argv[2];
  timeout_ms = atoi (argv[3]);

  snprintf (url, sizeof (url),
	    "cci:CUBRID:localhost:%d:%s:dba::?query_timeout=%d&disconnect_on_query_timeout=yes",
	    port, dbname, timeout_ms);

  conn = cci_connect_with_url (url, "dba", "");
  if (conn < 0)
    {
      fprintf (stderr, "cci_connect_with_url failed\n");
      return 1;
    }

  /* cross join on db_class to trigger timeout */
  req = cci_prepare (conn,
		     "SELECT 1 FROM db_class A, db_class B, db_class C",
		     0, &error);
  if (req < 0)
    {
      fprintf (stderr, "cci_prepare failed: [%d] %s\n",
	       error.err_code, error.err_msg);
      cci_disconnect (conn, &error);
      return 1;
    }

  res = cci_execute (req, 0, 0, &error);
  if (res < 0)
    {
      printf ("query time out: [%d] %s\n", error.err_code, error.err_msg);
    }
  else
    {
      printf ("query completed without timeout (unexpected)\n");
    }

  cci_close_req_handle (req);
  cci_disconnect (conn, &error);
  return 0;
}
