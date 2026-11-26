// A line from Discord for everyone in the game (chapter 10, tier 3): a work queue job of kind "chat" (chapter 5,
// tier 3). The bot adds it with args "<name>\n<text>"; a line older than two minutes (the game was away) is dropped.
#include "inc_queue"
#include "inc_bridge"

void main()
{
    int nId = StringToInt(GetScriptParam("id"));
    string sClaim = GetScriptParam("claim");
    string sArgs = GetScriptParam("args");

    NWNX_SQL_PrepareQuery("SELECT created_at < NOW() - INTERVAL 120 SECOND FROM work_queue WHERE id = ?");
    NWNX_SQL_PreparedInt(0, nId);
    if (NWNX_SQL_ExecutePreparedQuery() && NWNX_SQL_ReadyToReadNextRow())
    {
        NWNX_SQL_ReadNextRow();
        if (NWNX_SQL_ReadDataInActiveRow(0) == "1")
        {
            Queue_Finish(nId, sClaim, TRUE, "too old, not shown");
            return;
        }
    }

    int nBreak = FindSubString(sArgs, "\n");
    if (nBreak < 1)
    {
        Queue_Finish(nId, sClaim, FALSE, "args are not <name>\\n<text>");
        return;
    }
    string sLine = "[Discord] " + Bridge_Clean(GetStringLeft(sArgs, nBreak)) + ": " +
        Bridge_Clean(GetSubString(sArgs, nBreak + 1, BRIDGE_MAX_LENGTH));
    int nTold = 0;
    object oPC = GetFirstPC();
    while (GetIsObjectValid(oPC))
    {
        SendMessageToPC(oPC, sLine);
        nTold++;
        oPC = GetNextPC();
    }
    Queue_Finish(nId, sClaim, TRUE, "shown to " + IntToString(nTold));
}
