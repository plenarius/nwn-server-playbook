// Starts the game's side of the Discord bot (chapter 10, tier 3). Run it once from your OnModuleLoad script:
//     ExecuteScript("bridge_start");
#include "nwnx_chat"
#include "nwnx_sql"

void main()
{
    NWNX_Chat_RegisterChatScript("chat_bridge");
    NWNX_SQL_ExecuteQuery("DELETE FROM chat_out WHERE created_at < NOW() - INTERVAL 1 DAY");
    ExecuteScript("roster_poll", GetModule());
    WriteTimestampedLogEntry("bridge_start: chat bridge and roster on");
}
