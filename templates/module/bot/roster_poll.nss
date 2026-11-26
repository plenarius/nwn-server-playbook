// Writes who is online to online_players every 30 seconds (chapter 10, tier 3). bridge_start starts it.
#include "inc_bridge"

const float ROSTER_SECONDS = 30.0;

void main()
{
    Roster_Write();
    DelayCommand(ROSTER_SECONDS, ExecuteScript("roster_poll", GetModule()));
}
