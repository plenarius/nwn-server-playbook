// Lines from Discord (chapter 10, tier 3): a "chat" job is shown and finished, an old one dropped, a bad one failed.
#include "inc_test"
#include "inc_bridge_t"
#include "inc_queue"

string RunJob(string sArgs, string sAge)
{
    NWNX_SQL_ExecuteQuery("DELETE FROM work_queue");
    NWNX_SQL_PrepareQuery("INSERT INTO work_queue (kind, args, added_by, created_at) VALUES ('chat', ?, 'test', NOW() - INTERVAL " +
        sAge + " SECOND)");
    NWNX_SQL_PreparedString(0, sArgs);
    NWNX_SQL_ExecutePreparedQuery();
    string sClaim = GetRandomUUID();
    int nId = Queue_Claim(sClaim, "test");
    SetScriptParam("id", IntToString(nId));
    SetScriptParam("claim", sClaim);
    SetScriptParam("args", sArgs);
    ExecuteScript("wq_chat", GetModule());
    return BridgeTest_One("SELECT CONCAT(status, '|', result) FROM work_queue");
}

void main()
{
    BridgeTest_Tables();
    AssertStr(RunJob("Sam\nhello all", "0"), "done|shown to 0", "a fresh line is shown");
    AssertStr(RunJob("Sam\nhello all", "300"), "done|too old, not shown", "an old line is dropped");
    AssertStr(RunJob("no name", "0"), "failed|args are not <name>\\n<text>", "bad args fail");
}
