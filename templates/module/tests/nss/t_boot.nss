// t_boot: starts the test runner. Not a test itself (it has one underscore).
//
// The test server runs it as the module loads (NWNX_UTIL_PRE_MODULE_START_SCRIPT_CHUNK in tests/compose.yaml), so
// the module itself needs no change for tests. The module's own OnModuleLoad script runs after this, as it does
// on the live server; the short wait lets it finish, and gives anything it schedules a moment, before the first
// test starts.
#include "inc_test"

void main()
{
    Test_Log("BOOT", "filter " + GetLocalString(GetModule(), "TEST_FILTER"));
    DelayCommand(2.0, ExecuteScript("t_runner", GetModule()));
}
