-- Lines from the game for the Discord chat bridge (chapter 10, tier 3). The game adds one row per line said on the
-- bridged channel; the bot reads the new rows every few seconds and posts them. The game removes rows older than a
-- day when it starts. Copy this into your migrations folder under the next free number.
CREATE TABLE IF NOT EXISTS chat_out (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  speaker    VARCHAR(64)  NOT NULL,
  text       VARCHAR(512) NOT NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY created_at (created_at)
) DEFAULT CHARSET = utf8mb4;
