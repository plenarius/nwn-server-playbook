-- The table the example script from chapter 6 writes to. The script makes it too, so on a server that has
-- already started once this changes nothing, and that is fine: every migration should be safe to run twice.
CREATE TABLE IF NOT EXISTS server_starts (at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
