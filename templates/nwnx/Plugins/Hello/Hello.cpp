// NWNX_Hello: the smallest useful NWNX plugin, to prove your own image works end to end.
// Switch it on with NWNX_HELLO_SKIP=n. NWNX_HELLO_GREETING changes the first word (default "Hello").
#include "nwnx.hpp"

#include <string>

using namespace NWNXLib;

static std::string s_greeting = Config::Get<std::string>("GREETING", "Hello");

// Called from NWScript as NWNX_Hello_Greet(sName), see NWScript/nwnx_hello.nss.
NWNX_EXPORT ArgumentStack Greet(ArgumentStack&& args)
{
    const auto name = args.extract<std::string>();
    LOG_INFO("Greeting %s", name);
    return s_greeting + ", " + name + ", from your own NWNX plugin";
}
