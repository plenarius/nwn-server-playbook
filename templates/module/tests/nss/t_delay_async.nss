// An example of a test that waits for the game: it checks a DelayCommand ran, then tells the runner it is done.
#include "inc_test"

void Check()
{
    AssertInt(GetLocalInt(GetModule(), "t_delay_ran"), 1, "the delayed command ran");
    DeleteLocalInt(GetModule(), "t_delay_ran");
    Test_Done();
}

void main()
{
    Test_Async(5.0);
    DelayCommand(0.5, SetLocalInt(GetModule(), "t_delay_ran", 1));
    DelayCommand(1.0, Check());
}
