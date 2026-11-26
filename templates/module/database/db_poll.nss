// Looks at the database every few seconds (chapter 5, tier 3). Start it once from your OnModuleLoad script:
//     ExecuteScript("db_poll");
// Each time it:
//   - runs waiting jobs from work_queue: a job of kind "announce" runs the script wq_announce;
//   - looks at the revisions table: when a row changed since last time, it runs rv_<name> if you have one,
//     so the game can reload what an outside service changed.
#include "inc_queue"

const float POLL_SECONDS = 10.0;
const int JOBS_PER_POLL = 10;

void RunJobs()
{
    object oModule = GetModule();
    Queue_Recover();
    int i;
    for (i = 0; i < JOBS_PER_POLL; i++)
    {
        string sClaim = GetRandomUUID();
        int nId = Queue_Claim(sClaim, GetLocalString(oModule, "DB_POLL_NAME"));
        if (nId == 0) return;
        NWNX_SQL_PrepareQuery("SELECT kind, IFNULL(args, '') FROM work_queue WHERE id = ?");
        NWNX_SQL_PreparedInt(0, nId);
        NWNX_SQL_ExecutePreparedQuery();
        NWNX_SQL_ReadNextRow();
        string sScript = "wq_" + NWNX_SQL_ReadDataInActiveRow(0);
        string sArgs = NWNX_SQL_ReadDataInActiveRow(1);
        if (ResManGetAliasFor(sScript, RESTYPE_NCS) == "")
            Queue_Finish(nId, sClaim, FALSE, "this game has no script " + sScript);
        else
        {
            // The script finishes the job itself with Queue_Finish, now or (within the lease) later. It reads
            // GetScriptParam into variables first: inside a DelayCommand it would be read when the delay ends,
            // and then it is empty.
            SetScriptParam("id", IntToString(nId));
            SetScriptParam("claim", sClaim);
            SetScriptParam("args", sArgs);
            ExecuteScript(sScript, oModule);
        }
    }
}

void WatchRevisions()
{
    object oModule = GetModule();
    int bFirst = !GetLocalInt(oModule, "DB_POLL_STARTED");
    // Collect first, act after: an rv_ script may run queries of its own.
    json jChanged = JsonArray();
    if (NWNX_SQL_ExecuteQuery("SELECT name, rev FROM revisions"))
    {
        while (NWNX_SQL_ReadyToReadNextRow())
        {
            NWNX_SQL_ReadNextRow();
            string sName = NWNX_SQL_ReadDataInActiveRow(0);
            int nRev = StringToInt(NWNX_SQL_ReadDataInActiveRow(1));
            if (GetLocalInt(oModule, "REV_" + sName) != nRev)
            {
                SetLocalInt(oModule, "REV_" + sName, nRev);
                if (!bFirst) jChanged = JsonArrayInsert(jChanged, JsonString(sName));
            }
        }
    }
    int i;
    for (i = 0; i < JsonGetLength(jChanged); i++)
    {
        string sScript = "rv_" + JsonGetString(JsonArrayGet(jChanged, i));
        if (ResManGetAliasFor(sScript, RESTYPE_NCS) != "") ExecuteScript(sScript, oModule);
    }
}

void main()
{
    object oModule = GetModule();
    if (!GetLocalInt(oModule, "DB_POLL_STARTED"))
    {
        // Which game claimed a job, for people reading the table: the server's name and a fresh id for this start.
        SetLocalString(oModule, "DB_POLL_NAME", GetSubString(GetName(oModule), 0, 27) + " " + GetRandomUUID());
        WatchRevisions();   // the first look only remembers the numbers: the module has just loaded everything
        Rev_Bump("server");
        SetLocalInt(oModule, "DB_POLL_STARTED", TRUE);
        WriteTimestampedLogEntry("db_poll: started as " + GetLocalString(oModule, "DB_POLL_NAME"));
    }
    else
        WatchRevisions();
    RunJobs();
    DelayCommand(POLL_SECONDS, ExecuteScript("db_poll", oModule));
}
