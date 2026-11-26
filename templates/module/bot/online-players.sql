-- Who is online, for the roster (chapter 10, tier 3). The game writes the whole table again every 30 seconds, so
-- seen_at says how fresh it is: a stopped game leaves rows that soon look old, and readers leave those out.
-- Copy this into your migrations folder under the next free number.
CREATE TABLE IF NOT EXISTS online_players (
  name     VARCHAR(64) NOT NULL,
  dm       TINYINT     NOT NULL DEFAULT 0,
  seen_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY seen_at (seen_at)
) DEFAULT CHARSET = utf8mb4;
