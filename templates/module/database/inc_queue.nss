// The work queue and revision counters (chapter 5, tier 3), as small functions over NWNX_SQL.
#include "nwnx_sql"

// A claim older than this goes back in the queue: the game that held it stopped before it finished.
// Every wq_ script must finish its job well within it.
const int QUEUE_LEASE_SECONDS = 120;
const int QUEUE_MAX_ATTEMPTS = 3;

// Claims the oldest waiting job for sClaim, a new random id. Returns the job's id, or 0 when nothing waits.
// One UPDATE does the claim, so two games polling the same table can never claim the same row.
int Queue_Claim(string sClaim, string sBy)
{
    NWNX_SQL_PrepareQuery("UPDATE work_queue SET status = 'claimed', claim = ?, claimed_by = ?, " +
        "claimed_at = NOW(), attempts = attempts + 1 WHERE status = 'queued' ORDER BY id LIMIT 1");
    NWNX_SQL_PreparedString(0, sClaim);
    NWNX_SQL_PreparedString(1, sBy);
    if (!NWNX_SQL_ExecutePreparedQuery() || NWNX_SQL_GetAffectedRows() != 1) return 0;
    NWNX_SQL_PrepareQuery("SELECT id FROM work_queue WHERE claim = ?");
    NWNX_SQL_PreparedString(0, sClaim);
    if (!NWNX_SQL_ExecutePreparedQuery() || !NWNX_SQL_ReadyToReadNextRow()) return 0;
    NWNX_SQL_ReadNextRow();
    return StringToInt(NWNX_SQL_ReadDataInActiveRow(0));
}

// Writes the outcome of job nId. Only the holder of the claim can: returns FALSE if the claim was lost
// (the lease ran out and the job went back in the queue), and then the outcome is not written.
int Queue_Finish(int nId, string sClaim, int bOk, string sResult)
{
    NWNX_SQL_PrepareQuery("UPDATE work_queue SET status = ?, result = ?, done_at = NOW() " +
        "WHERE id = ? AND claim = ? AND status = 'claimed'");
    NWNX_SQL_PreparedString(0, bOk ? "done" : "failed");
    NWNX_SQL_PreparedString(1, GetSubString(sResult, 0, 500));
    NWNX_SQL_PreparedInt(2, nId);
    NWNX_SQL_PreparedString(3, sClaim);
    int bWritten = NWNX_SQL_ExecutePreparedQuery() && NWNX_SQL_GetAffectedRows() == 1;
    if (!bWritten) WriteTimestampedLogEntry("queue: job " + IntToString(nId) + ": claim lost, outcome not written");
    return bWritten;
}

// Claims older than the lease: back in the queue, or failed after QUEUE_MAX_ATTEMPTS tries.
void Queue_Recover()
{
    string sOld = "status = 'claimed' AND claimed_at < NOW() - INTERVAL " + IntToString(QUEUE_LEASE_SECONDS) + " SECOND";
    NWNX_SQL_ExecuteQuery("UPDATE work_queue SET status = 'failed', done_at = NOW(), result = 'gave up: no game " +
        "finished it in " + IntToString(QUEUE_MAX_ATTEMPTS) + " tries' WHERE " + sOld +
        " AND attempts >= " + IntToString(QUEUE_MAX_ATTEMPTS));
    NWNX_SQL_ExecuteQuery("UPDATE work_queue SET status = 'queued', claim = NULL, claimed_by = NULL WHERE " + sOld);
}

// Adds one to revision sName, the game's way of saying "what you cached about this is old".
// Call it in the same transaction as the change it describes.
void Rev_Bump(string sName)
{
    NWNX_SQL_PrepareQuery("UPDATE revisions SET rev = LAST_INSERT_ID(rev + 1) WHERE name = ?");
    NWNX_SQL_PreparedString(0, sName);
    if (!NWNX_SQL_ExecutePreparedQuery() || NWNX_SQL_GetAffectedRows() != 1)
    {
        WriteTimestampedLogEntry("revisions: no row '" + sName + "': add it in a migration");
        return;
    }
    // Remember the number we made, so db_poll doesn't take our own change for someone else's.
    if (NWNX_SQL_ExecuteQuery("SELECT LAST_INSERT_ID()") && NWNX_SQL_ReadyToReadNextRow())
    {
        NWNX_SQL_ReadNextRow();
        SetLocalInt(GetModule(), "REV_" + sName, StringToInt(NWNX_SQL_ReadDataInActiveRow(0)));
    }
}
