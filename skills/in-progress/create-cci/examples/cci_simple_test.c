#include <stdio.h>
#include "cas_cci.h"

/* Simple CCI test: connect, create table, insert, select.
 * Usage: ./test <broker_port>
 */

#define HOST "127.0.0.1"
#define USER "public"
#define PASSWD ""
#define DBNAME "ccidb"

static void
print_error (const char *func, T_CCI_ERROR *error)
{
  fprintf (stderr, "ERROR in %s: [%d] %s\n", func, error->err_code,
	   error->err_msg);
}

int
main (int argc, char *argv[])
{
  int port, conn, req, res, ind, col_count;
  T_CCI_ERROR error;
  T_CCI_COL_INFO *col_info;
  T_CCI_SQLX_CMD cmd_type;
  char *val;

  if (argc < 2)
    {
      fprintf (stderr, "Usage: %s <port>\n", argv[0]);
      return 1;
    }
  port = atoi (argv[1]);

  conn = cci_connect (HOST, port, DBNAME, USER, PASSWD);
  if (conn < 0)
    {
      fprintf (stderr, "cci_connect failed\n");
      return 1;
    }

  req = cci_prepare (conn, "CREATE TABLE cci_test (id INT, name VARCHAR(50))",
		     0, &error);
  if (req < 0)
    {
      print_error ("cci_prepare CREATE", &error);
      goto disconnect;
    }
  res = cci_execute (req, 0, 0, &error);
  cci_close_req_handle (req);
  if (res < 0)
    {
      print_error ("cci_execute CREATE", &error);
      goto disconnect;
    }

  req = cci_prepare (conn, "INSERT INTO cci_test VALUES (1, 'hello')",
		     0, &error);
  if (req < 0)
    {
      print_error ("cci_prepare INSERT", &error);
      goto disconnect;
    }
  cci_execute (req, 0, 0, &error);
  cci_close_req_handle (req);

  cci_end_tran (conn, CCI_TRAN_COMMIT, &error);

  req = cci_prepare (conn, "SELECT id, name FROM cci_test ORDER BY id",
		     0, &error);
  if (req < 0)
    {
      print_error ("cci_prepare SELECT", &error);
      goto disconnect;
    }

  col_info = cci_get_result_info (req, &cmd_type, &col_count);
  res = cci_execute (req, 0, 0, &error);
  if (res < 0)
    {
      print_error ("cci_execute SELECT", &error);
      cci_close_req_handle (req);
      goto disconnect;
    }

  while (1)
    {
      res = cci_cursor (req, 1, CCI_CURSOR_CURRENT, &error);
      if (res == CCI_ER_NO_MORE_DATA)
	break;
      if (res < 0)
	{
	  print_error ("cci_cursor", &error);
	  break;
	}

      cci_fetch (req, &error);

      cci_get_data (req, 1, CCI_A_TYPE_STR, &val, &ind);
      printf ("%s ", val);

      cci_get_data (req, 2, CCI_A_TYPE_STR, &val, &ind);
      printf ("%s\n", val);
    }

  cci_close_req_handle (req);

  req = cci_prepare (conn, "DROP TABLE cci_test", 0, &error);
  if (req >= 0)
    {
      cci_execute (req, 0, 0, &error);
      cci_close_req_handle (req);
      cci_end_tran (conn, CCI_TRAN_COMMIT, &error);
    }

disconnect:
  cci_disconnect (conn, &error);
  return 0;
}
