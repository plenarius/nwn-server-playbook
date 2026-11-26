// For the chat bridge's tests only (chapter 10, tier 3): the tables they need, as the migrations make them, since
// the test server's database is empty at every run.
#include "nwnx_sql"

void BridgeTest_Tables()
{
    NWNX_SQL_ExecuteQuery("CREATE TABLE IF NOT EXISTS chat_out (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, " +
        "speaker VARCHAR(64) NOT NULL, text VARCHAR(512) NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) " +
        "DEFAULT CHARSET = utf8mb4");
    NWNX_SQL_ExecuteQuery("CREATE TABLE IF NOT EXISTS online_players (name VARCHAR(64) NOT NULL, dm TINYINT NOT NULL DEFAULT 0, " +
        "seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) DEFAULT CHARSET = utf8mb4");
    NWNX_SQL_ExecuteQuery("CREATE TABLE IF NOT EXISTS work_queue (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, " +
        "kind VARCHAR(13) NOT NULL, args TEXT NULL, added_by VARCHAR(64) NOT NULL DEFAULT '', " +
        "status ENUM('queued','claimed','done','failed') NOT NULL DEFAULT 'queued', claimed_by VARCHAR(64) NULL, claim CHAR(36) NULL, " +
        "claimed_at DATETIME NULL, attempts TINYINT UNSIGNED NOT NULL DEFAULT 0, result VARCHAR(500) NULL, " +
        "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, done_at DATETIME NULL)");
}

string BridgeTest_One(string sQuery)
{
    if (!NWNX_SQL_ExecuteQuery(sQuery) || !NWNX_SQL_ReadyToReadNextRow()) return "<no row>";
    NWNX_SQL_ReadNextRow();
    return NWNX_SQL_ReadDataInActiveRow(0);
}
