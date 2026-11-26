// The chat bridge (chapter 10, tier 3), through NWNX_Chat itself: a shout reaches chat_out, a spoken line doesn't,
// and only BRIDGE_MAX_LINES a minute get through. The test server has no players, so a creature shouts.
#include "inc_test"
#include "inc_bridge_t"
#include "inc_bridge"
#include "nwnx_chat"

void main()
{
    BridgeTest_Tables();
    NWNX_SQL_ExecuteQuery("DELETE FROM chat_out");
    NWNX_Chat_RegisterChatScript("chat_bridge");
    SetLocalInt(GetModule(), "BRIDGE_ANY_SPEAKER", TRUE);
    object oMira = CreateObject(OBJECT_TYPE_CREATURE, "nw_badger", GetStartingLocation());
    Assert(GetIsObjectValid(oMira), "a creature to speak");
    SetName(oMira, "Mira");

    NWNX_Chat_SendMessage(NWNX_CHAT_CHANNEL_PLAYER_TALK, "only nearby", oMira);
    AssertStr(BridgeTest_One("SELECT COUNT(*) FROM chat_out"), "0", "a spoken line stays in the game");
    NWNX_Chat_SendMessage(NWNX_CHAT_CHANNEL_PLAYER_SHOUT, "the <c9 9>ferry</c> is late @everyone", oMira);
    AssertStr(BridgeTest_One("SELECT CONCAT(speaker, '|', text) FROM chat_out"), "Mira|the ferry is late @everyone",
        "a shout reaches chat_out, without colour (mentions are the bot's to strip)");
    int i;
    for (i = 0; i < 10; i++) NWNX_Chat_SendMessage(NWNX_CHAT_CHANNEL_PLAYER_SHOUT, "again " + IntToString(i), oMira);
    AssertStr(BridgeTest_One("SELECT COUNT(*) FROM chat_out"), IntToString(BRIDGE_MAX_LINES), "only so many lines a minute");

    DeleteLocalInt(GetModule(), "BRIDGE_ANY_SPEAKER");
    NWNX_Chat_SendMessage(NWNX_CHAT_CHANNEL_PLAYER_SHOUT, "a creature", oMira);
    DestroyObject(oMira);
}
