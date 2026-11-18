// An example for chapter 6. It runs once, when the module loads:
// first the game's own load script, then one row in the database from chapter 5.
#include "nwnx_sql"

void main()
{
    ExecuteScript("x2_mod_def_load");
    NWNX_SQL_ExecuteQuery("CREATE TABLE IF NOT EXISTS server_starts (at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
    NWNX_SQL_ExecuteQuery("INSERT INTO server_starts VALUES ()");
    WriteTimestampedLogEntry("mod_load: recorded this start in the database");
}
