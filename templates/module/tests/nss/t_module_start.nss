// An example test: the module has a place for players to start.
#include "inc_test"

void main()
{
    location lStart = GetStartingLocation();
    object oArea = GetAreaFromLocation(lStart);
    Assert(GetIsObjectValid(oArea), "the starting location is in an area");
    Assert(GetTag(oArea) != "", "the starting area has a tag");
}
