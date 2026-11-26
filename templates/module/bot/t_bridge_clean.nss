// The chat bridge (chapter 10, tier 3): colour codes go, long lines are cut.
#include "inc_test"
#include "inc_bridge"

void main()
{
    AssertStr(Bridge_Clean("plain words"), "plain words", "plain text stays");
    AssertStr(Bridge_Clean("a <cA1z>red</c> word"), "a red word", "colour codes go");
    string s = "0123456789";
    int i; for (i = 0; i < 6; i++) s = s + s;
    AssertInt(GetStringLength(Bridge_Clean(s)), BRIDGE_MAX_LENGTH, "a long line is cut");
    Assert(Bridge_Now() > 1700000000, "the clock reads the time");
}
