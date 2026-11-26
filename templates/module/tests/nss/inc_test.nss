// inc_test: what a test script includes. Part of the headless test runner (tests/run.sh).
//
// A test is a script named t_<system>_<case>, at most 16 characters, in tests/nss. The runner runs each one on
// the module, one at a time, and counts its asserts. A test passes when it made at least one assert and none
// failed. A small one:
//
//   #include "inc_test"
//   void main()
//   {
//       AssertInt(GetIsObjectValid(GetModule()), TRUE, "the module exists");
//   }
//
// A test that has to wait for the game (a DelayCommand, an action) calls Test_Async() first and Test_Done() when
// it has finished; the runner waits for that, up to the timeout, before it starts the next test.

// Every line the runner writes to the server's log starts with this. tests/tools/results.py reads those lines.
const string TEST_TAG = "TEST";

// The runner's bookkeeping, as locals on the module.
const string TEST_NAME    = "TEST_NAME";
const string TEST_ASSERTS = "TEST_ASSERTS";
const string TEST_FAILS   = "TEST_FAILS";
const string TEST_SKIP    = "TEST_SKIP";
const string TEST_ASYNC   = "TEST_ASYNC";
const string TEST_DONE    = "TEST_DONE";
const string TEST_TIMEOUT = "TEST_TIMEOUT";

// Writes one line to the server's log: TEST|sEvent|<current test>|sDetail
void Test_Log(string sEvent, string sDetail = "")
{
    WriteTimestampedLogEntry(TEST_TAG + "|" + sEvent + "|" + GetLocalString(GetModule(), TEST_NAME) + "|" + sDetail);
}

// Records one check. sMessage says what should be true; it is logged only when the check fails.
void Assert(int bTrue, string sMessage)
{
    object oModule = GetModule();
    SetLocalInt(oModule, TEST_ASSERTS, GetLocalInt(oModule, TEST_ASSERTS) + 1);
    if (!bTrue)
    {
        SetLocalInt(oModule, TEST_FAILS, GetLocalInt(oModule, TEST_FAILS) + 1);
        Test_Log("ASSERT", sMessage);
    }
}

void AssertInt(int nGot, int nWant, string sMessage)
{
    Assert(nGot == nWant, sMessage + ": got " + IntToString(nGot) + ", want " + IntToString(nWant));
}

void AssertStr(string sGot, string sWant, string sMessage)
{
    Assert(sGot == sWant, sMessage + ": got \"" + sGot + "\", want \"" + sWant + "\"");
}

// Fails the current test outright.
void Test_Fail(string sMessage)
{
    Assert(FALSE, sMessage);
}

// Marks the current test skipped, with the reason. Use it for a test that can't run here.
void Test_Skip(string sReason)
{
    SetLocalInt(GetModule(), TEST_SKIP, TRUE);
    Test_Log("SKIP", sReason);
}

// Tells the runner this test finishes later. Call Test_Done() when it has; after fTimeout seconds it fails.
void Test_Async(float fTimeout = 10.0)
{
    SetLocalInt(GetModule(), TEST_ASYNC, TRUE);
    SetLocalFloat(GetModule(), TEST_TIMEOUT, fTimeout);
}

void Test_Done()
{
    SetLocalInt(GetModule(), TEST_DONE, TRUE);
}
