-- Remember which module version each start was. Rows written before this have no version, which is honest.
ALTER TABLE server_starts ADD COLUMN IF NOT EXISTS module_version VARCHAR(32) NULL;
