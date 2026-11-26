// An example job for the work queue (chapter 5, tier 3): tells everyone online what args says.
// An outside service adds it with:
//     INSERT INTO work_queue (kind, args, added_by) VALUES ('announce', 'The bank closes in five minutes', 'website');
#include "inc_queue"

void main()
{
    int nId = StringToInt(GetScriptParam("id"));
    string sText = GetScriptParam("args");
    object oPC = GetFirstPC();
    int nTold = 0;
    while (GetIsObjectValid(oPC))
    {
        SendMessageToPC(oPC, sText);
        nTold++;
        oPC = GetNextPC();
    }
    WriteTimestampedLogEntry("wq_announce: job " + IntToString(nId) + ": " + sText);
    Queue_Finish(nId, GetScriptParam("claim"), TRUE, "told " + IntToString(nTold) + " online");
}
