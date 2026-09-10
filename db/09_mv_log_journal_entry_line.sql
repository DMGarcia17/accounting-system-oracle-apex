-- ============================================================
-- 09_mv_log_journal_entry_line.sql
-- Depende de: 08_journal_entry_line.sql
-- Requisito obligatorio para que la vista materializada (10)
-- pueda hacer FAST REFRESH ON COMMIT. Sin este log, Oracle
-- rechaza la creación de la vista materializada.
-- ============================================================

CREATE MATERIALIZED VIEW LOG ON journal_entry_line
WITH ROWID, SEQUENCE (journal_entry_id, account_id, movement_type, amount)
INCLUDING NEW VALUES;
