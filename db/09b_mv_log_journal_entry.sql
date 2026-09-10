-- ============================================================
-- 09b_mv_log_journal_entry.sql  (CORREGIDO)
-- Depende de: 07_journal_entry.sql
-- Correr ANTES de 10_mv_account_balances.sql.
--
-- Como el JOIN usa la llave primaria de journal_entry (e.id =
-- l.journal_entry_id), el log necesita rastrear esa llave primaria
-- explícitamente (WITH PRIMARY KEY), no solo el ROWID -- si no,
-- Oracle rechaza el FAST REFRESH con ORA-12033 aunque las columnas
-- de filtro (SEQUENCE) estén bien puestas.
--
-- Si ya corriste la versión anterior (solo WITH ROWID), hay que
-- borrar el log viejo primero: DROP MATERIALIZED VIEW LOG ON journal_entry;
-- ============================================================

DROP MATERIALIZED VIEW LOG ON journal_entry;

CREATE MATERIALIZED VIEW LOG ON journal_entry
WITH ROWID, PRIMARY KEY, SEQUENCE (company_id, period_id, status)
INCLUDING NEW VALUES;
