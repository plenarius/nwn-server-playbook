// The roster (chapter 10, tier 3): Roster_Write replaces online_players with who is in the game now.
#include "inc_test"
#include "inc_bridge_t"
#include "inc_bridge"

void main()
{
    BridgeTest_Tables();
    NWNX_SQL_ExecuteQuery("INSERT INTO online_players (name) VALUES ('Left an hour ago')");
    AssertInt(Roster_Write(), 0, "no players on the test server");
    AssertStr(BridgeTest_One("SELECT COUNT(*) FROM online_players"), "0", "the old row is gone");
}
