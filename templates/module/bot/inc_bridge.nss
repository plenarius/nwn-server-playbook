// The game's side of the Discord bot (chapter 10, tier 3): the chat bridge and the roster, as small functions.
#include "nwnx_sql"

// A player's lines reach Discord at most BRIDGE_MAX_LINES times in BRIDGE_PER_SECONDS. More still reach everyone
// in the game, as always; only the copy to Discord is held back.
const int BRIDGE_MAX_LINES = 5;
const int BRIDGE_PER_SECONDS = 60;
const int BRIDGE_MAX_LENGTH = 400;

// Seconds since 1970, from the module's own SQLite database: NWScript has no clock of its own for this.
int Bridge_Now()
{
    sqlquery q = SqlPrepareQueryObject(GetModule(), "SELECT CAST(strftime('%s', 'now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// The text without the game's colour codes (<c...> and </c>), at most BRIDGE_MAX_LENGTH characters.
string Bridge_Clean(string sText)
{
    sText = RegExpReplace("<c...>|</c>", sText, "");
    return GetStringLeft(sText, BRIDGE_MAX_LENGTH);
}

// Whether oSpeaker may send one more line to Discord now, counting it if so. The count lives on the speaker, so
// it starts again when they log in.
int Bridge_Allow(object oSpeaker)
{
    int nNow = Bridge_Now();
    if (nNow - GetLocalInt(oSpeaker, "BRIDGE_SINCE") >= BRIDGE_PER_SECONDS)
    {
        SetLocalInt(oSpeaker, "BRIDGE_SINCE", nNow);
        SetLocalInt(oSpeaker, "BRIDGE_LINES", 0);
        SetLocalInt(oSpeaker, "BRIDGE_TOLD", FALSE);
    }
    int nLines = GetLocalInt(oSpeaker, "BRIDGE_LINES");
    if (nLines >= BRIDGE_MAX_LINES) return FALSE;
    SetLocalInt(oSpeaker, "BRIDGE_LINES", nLines + 1);
    return TRUE;
}

// One line from the game for Discord: rate-limited, cleaned, and added to chat_out for the bot to pick up.
// Returns TRUE when the line was added.
int Bridge_FromGame(object oSpeaker, string sText)
{
    sText = Bridge_Clean(sText);
    if (sText == "") return FALSE;
    if (!Bridge_Allow(oSpeaker))
    {
        if (!GetLocalInt(oSpeaker, "BRIDGE_TOLD"))
        {
            SetLocalInt(oSpeaker, "BRIDGE_TOLD", TRUE);
            SendMessageToPC(oSpeaker, "Only " + IntToString(BRIDGE_MAX_LINES) + " lines a minute go to Discord; " +
                "everyone here still hears you.");
        }
        return FALSE;
    }
    string sName = GetName(oSpeaker);
    if (GetIsDM(oSpeaker)) sName = "[DM] " + sName;
    NWNX_SQL_PrepareQuery("INSERT INTO chat_out (speaker, text) VALUES (?, ?)");
    NWNX_SQL_PreparedString(0, GetStringLeft(sName, 64));
    NWNX_SQL_PreparedString(1, sText);
    return NWNX_SQL_ExecutePreparedQuery();
}

// Writes online_players again: one row per player and DM in the game now. One transaction, so a reader never
// sees it half written.
int Roster_Write()
{
    NWNX_SQL_ExecuteQuery("START TRANSACTION");
    NWNX_SQL_ExecuteQuery("DELETE FROM online_players");
    int nRows = 0;
    object oPC = GetFirstPC();
    while (GetIsObjectValid(oPC))
    {
        NWNX_SQL_PrepareQuery("INSERT INTO online_players (name, dm) VALUES (?, ?)");
        NWNX_SQL_PreparedString(0, GetStringLeft(GetName(oPC), 64));
        NWNX_SQL_PreparedInt(1, GetIsDM(oPC));
        if (NWNX_SQL_ExecutePreparedQuery()) nRows++;
        oPC = GetNextPC();
    }
    NWNX_SQL_ExecuteQuery("COMMIT");
    return nRows;
}
