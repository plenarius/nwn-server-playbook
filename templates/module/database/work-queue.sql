-- A work queue (chapter 5, tier 3): outside services add a row, the game claims it, does the work and writes the
-- outcome back. Copy this into your migrations folder under the next free number.
--
--   kind        which script does the work: the game runs wq_<kind> (so at most 13 lowercase letters, digits, _)
--   args        what that script needs, as text (JSON is handy)
--   status      queued (new), claimed (a game is doing it), done, failed
--   claimed_by  which game claimed it; claim is a fresh random id for each claim, so a game that lost its
--               claim can't finish someone else's
--   attempts    how often it was claimed; a claim older than the lease goes back in the queue, three times at most
CREATE TABLE IF NOT EXISTS work_queue (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  kind        VARCHAR(13)  NOT NULL,
  args        TEXT         NULL,
  added_by    VARCHAR(64)  NOT NULL DEFAULT '',
  status      ENUM('queued','claimed','done','failed') NOT NULL DEFAULT 'queued',
  claimed_by  VARCHAR(64)  NULL,
  claim       CHAR(36)     NULL,
  claimed_at  DATETIME     NULL,
  attempts    TINYINT UNSIGNED NOT NULL DEFAULT 0,
  result      VARCHAR(500) NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  done_at     DATETIME     NULL,
  KEY status_id (status, id)
);
