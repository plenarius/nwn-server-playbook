-- Revision counters (chapter 5, tier 3): one row per kind of data that something else caches. Whoever changes that
-- data adds one to its row, in the same transaction as the change. Anyone holding a copy compares the number with
-- the one they saw last, and reloads when it differs. Copy this into your migrations folder under the next free
-- number, and add a row for each kind of data you want watched.
CREATE TABLE IF NOT EXISTS revisions (
  name       VARCHAR(13)     NOT NULL PRIMARY KEY,
  rev        BIGINT UNSIGNED NOT NULL DEFAULT 1,
  changed_at TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
-- "server": the game adds one each time it starts, so a website knows its cached view of the server is old.
INSERT IGNORE INTO revisions (name) VALUES ('server');
