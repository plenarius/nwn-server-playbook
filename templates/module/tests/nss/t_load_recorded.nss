// An example test of the module's own code: chapter 6's example load script (mod_load) writes a row to the
// database each time the module loads. It is skipped in a module that doesn't have that script.
#include "inc_test"
#include "nwnx_sql"

void main()
{
    if (ResManGetAliasFor("mod_load", RESTYPE_NCS) == "")
    {
        Test_Skip("this module has no mod_load script");
        return;
    }
    Assert(NWNX_SQL_ExecuteQuery("SELECT COUNT(*) FROM server_starts") && NWNX_SQL_ReadyToReadNextRow(),
           "read the server_starts table");
    NWNX_SQL_ReadNextRow();
    AssertStr(NWNX_SQL_ReadDataInActiveRow(0), "1", "rows written by this module load");
}
