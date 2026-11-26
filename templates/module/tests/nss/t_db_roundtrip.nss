// An example test: the game can write to the database and read it back, through NWNX_SQL.
// The test server has a database of its own, empty at every run, so a test may make and drop tables.
#include "inc_test"
#include "nwnx_sql"

void main()
{
    Assert(NWNX_SQL_ExecuteQuery("CREATE TABLE test_roundtrip (n INT)"), "make a table");
    Assert(NWNX_SQL_ExecuteQuery("INSERT INTO test_roundtrip VALUES (41), (1)"), "write two rows");
    Assert(NWNX_SQL_ExecuteQuery("SELECT SUM(n) FROM test_roundtrip") && NWNX_SQL_ReadyToReadNextRow(), "read them");
    NWNX_SQL_ReadNextRow();
    AssertStr(NWNX_SQL_ReadDataInActiveRow(0), "42", "the sum");
    NWNX_SQL_ExecuteQuery("DROP TABLE test_roundtrip");
}
