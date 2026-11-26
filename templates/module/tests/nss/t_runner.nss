// t_runner: finds the tests, runs them one at a time and logs each result. Not a test itself.
//
// The tests are the compiled scripts in the module of the form t_<system>_<case> that the filter names. The filter
// (default "t_") is a list split by commas: an entry ending in an underscore takes every test whose name starts
// with it (t_db_), any other entry is one test's whole name (t_db_roundtrip). That is how test selection and test
// lanes hand the runner an exact list (chapter 6, tier 3). They run in alphabetical order. For each one the log gets
//   TEST|START|t_x_y|   then any   TEST|ASSERT|t_x_y|<what failed>   and one of
//   TEST|PASS|t_x_y|<asserts>   TEST|FAIL|t_x_y|<why>   TEST|SKIP|t_x_y|<why>
// and after the last one TEST|END||<passed> <failed> <skipped>. tests/run.sh stops the server when it sees END.
#include "inc_test"

const string RUNNER_TESTS = "TEST_RUNNER_LIST";
const float RUNNER_POLL = 0.1;

// A test's name has a second underscore: t_<system>_<case>. That leaves out t_boot and t_runner.
int IsTestName(string sName)
{
    return GetStringLeft(sName, 2) == "t_" && FindSubString(sName, "_", 2) > 2;
}

void RunTest(int nIndex);

void Finish(int nIndex, int bTimedOut)
{
    object oModule = GetModule();
    int nAsserts = GetLocalInt(oModule, TEST_ASSERTS);
    int nFails = GetLocalInt(oModule, TEST_FAILS);
    string sResult = "PASS";
    string sDetail = IntToString(nAsserts) + " asserts";
    if (GetLocalInt(oModule, TEST_SKIP))
    {
        sResult = "SKIP";
        sDetail = "";
    }
    else if (bTimedOut)
    {
        sResult = "FAIL";
        sDetail = "did not call Test_Done() within " + FloatToString(GetLocalFloat(oModule, TEST_TIMEOUT), 0, 1) + " s";
    }
    else if (nFails > 0)
    {
        sResult = "FAIL";
        sDetail = IntToString(nFails) + " of " + IntToString(nAsserts) + " asserts failed";
    }
    else if (nAsserts == 0)
    {
        // Also what a script error looks like: the test stopped before its first assert.
        sResult = "FAIL";
        sDetail = "made no asserts (did it stop on a script error?)";
    }
    Test_Log(sResult, sDetail);
    SetLocalInt(oModule, "TEST_COUNT_" + sResult, GetLocalInt(oModule, "TEST_COUNT_" + sResult) + 1);
    DelayCommand(RUNNER_POLL, RunTest(nIndex + 1));
}

void Wait(int nIndex, float fWaited)
{
    object oModule = GetModule();
    if (GetLocalInt(oModule, TEST_DONE))
        Finish(nIndex, FALSE);
    else if (fWaited >= GetLocalFloat(oModule, TEST_TIMEOUT))
        Finish(nIndex, TRUE);
    else
        DelayCommand(RUNNER_POLL, Wait(nIndex, fWaited + RUNNER_POLL));
}

void RunTest(int nIndex)
{
    object oModule = GetModule();
    json jTests = GetLocalJson(oModule, RUNNER_TESTS);
    if (nIndex >= JsonGetLength(jTests))
    {
        SetLocalString(oModule, TEST_NAME, "");
        Test_Log("END", IntToString(GetLocalInt(oModule, "TEST_COUNT_PASS")) + " " +
                        IntToString(GetLocalInt(oModule, "TEST_COUNT_FAIL")) + " " +
                        IntToString(GetLocalInt(oModule, "TEST_COUNT_SKIP")));
        return;
    }
    string sTest = JsonGetString(JsonArrayGet(jTests, nIndex));
    SetLocalString(oModule, TEST_NAME, sTest);
    DeleteLocalInt(oModule, TEST_ASSERTS);
    DeleteLocalInt(oModule, TEST_FAILS);
    DeleteLocalInt(oModule, TEST_SKIP);
    DeleteLocalInt(oModule, TEST_ASYNC);
    DeleteLocalInt(oModule, TEST_DONE);
    Test_Log("START");
    ExecuteScript(sTest, oModule);
    if (GetLocalInt(oModule, TEST_ASYNC) && !GetLocalInt(oModule, TEST_SKIP))
        Wait(nIndex, 0.0);
    else
        Finish(nIndex, FALSE);
}

// Adds sName to jTests if it is a test and not there yet.
json AddTest(json jTests, string sName)
{
    if (IsTestName(sName) && JsonFind(jTests, JsonString(sName)) == JsonNull())
        jTests = JsonArrayInsert(jTests, JsonString(sName));
    return jTests;
}

void main()
{
    object oModule = GetModule();
    string sFilter = GetLocalString(oModule, "TEST_FILTER");
    if (GetStringLeft(sFilter, 2) != "t_")
        sFilter = "t_";
    json jTests = JsonArray();
    while (sFilter != "")
    {
        int nComma = FindSubString(sFilter, ",");
        string sEntry = nComma < 0 ? sFilter : GetStringLeft(sFilter, nComma);
        sFilter = nComma < 0 ? "" : GetSubString(sFilter, nComma + 1, GetStringLength(sFilter));
        if (GetStringRight(sEntry, 1) == "_")
        {
            int n = 1;
            string sName = ResManFindPrefix(sEntry, RESTYPE_NCS, n);
            while (sName != "")
            {
                jTests = AddTest(jTests, sName);
                sName = ResManFindPrefix(sEntry, RESTYPE_NCS, ++n);
            }
        }
        else if (ResManGetAliasFor(sEntry, RESTYPE_NCS) != "")
            jTests = AddTest(jTests, sEntry);
    }
    jTests = JsonArrayTransform(jTests, JSON_ARRAY_SORT_ASCENDING);
    SetLocalJson(oModule, RUNNER_TESTS, jTests);
    SetLocalString(oModule, TEST_NAME, "");
    Test_Log("FOUND", IntToString(JsonGetLength(jTests)) + " tests");
    RunTest(0);
}
