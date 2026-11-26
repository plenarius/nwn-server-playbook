// The chat script (chapter 10, tier 3): NWNX_Chat runs it for every line said in the game. Lines said on the
// shout channel go to Discord through chat_out. bridge_start registers it.
//
// NWNX_Chat runs one chat script for the whole server. If your module has one already, call Bridge_FromGame
// from it instead of registering this one.
#include "inc_bridge"
#include "nwnx_chat"

void main()
{
    int nChannel = NWNX_Chat_GetChannel();
    if (nChannel != NWNX_CHAT_CHANNEL_PLAYER_SHOUT && nChannel != NWNX_CHAT_CHANNEL_DM_SHOUT) return;
    object oSpeaker = NWNX_Chat_GetSender();
    // Players and DMs only. The tests set BRIDGE_ANY_SPEAKER to speak as a creature, as they have no player;
    // never set it on a live server, or creatures' shouts would reach Discord.
    if (!GetIsPC(oSpeaker) && !GetLocalInt(GetModule(), "BRIDGE_ANY_SPEAKER")) return;
    Bridge_FromGame(oSpeaker, NWNX_Chat_GetMessage());
}
