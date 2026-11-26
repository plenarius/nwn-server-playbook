/// @addtogroup hello Hello
/// @brief The example plugin from the NWN server playbook: proves your own NWNX image answers from NWScript.
/// @{
/// @file nwnx_hello.nss

const string NWNX_Hello = "NWNX_Hello"; ///< @private

/// @brief Returns a greeting made by the plugin, such as "Hello, Tester, from your own NWNX plugin".
/// @param sName Who to greet.
/// @return The greeting, or "" if the plugin is not loaded.
string NWNX_Hello_Greet(string sName);

/// @}

string NWNX_Hello_Greet(string sName)
{
    NWNXPushString(sName);
    NWNXCall(NWNX_Hello, "Greet");
    return NWNXPopString();
}
