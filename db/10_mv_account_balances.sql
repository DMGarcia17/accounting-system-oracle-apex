-- ============================================================
-- 10_mv_account_balances.sql  (CORREGIDO)
-- Depende de: 09_mv_log_journal_entry_line.sql, 09b_mv_log_journal_entry.sql,
--             07_journal_entry.sql
--
-- Versión anterior tenía un WHERE e.status = 'ACTIVE', pero Oracle
-- no permite FAST REFRESH en un JOIN cuando hay un filtro que no es
-- parte de la condición de unión (ORA-12033). La solución: sacar el
-- filtro y agregar status al GROUP BY -- así la vista materializada
-- guarda los totales de ACTIVE y REVERSED por separado, sin filtrar
-- nada acá. El filtro se aplica después, en vw_account_balance (11),
-- donde un WHERE normal no tiene esa restricción.
-- ============================================================

CREATE MATERIALIZED VIEW mv_account_balances
BUILD IMMEDIATE
REFRESH FAST ON COMMIT
AS
SELECT
    e.company_id,
    e.period_id,
    l.account_id,
    e.status,
    SUM(CASE WHEN l.movement_type = 'D' THEN l.amount ELSE 0 END) AS total_debit,
    SUM(CASE WHEN l.movement_type = 'C' THEN l.amount ELSE 0 END) AS total_credit,
    COUNT(*) AS line_count
FROM journal_entry_line l
JOIN journal_entry e ON e.id = l.journal_entry_id
GROUP BY e.company_id, e.period_id, l.account_id, e.status;

COMMENT ON MATERIALIZED VIEW mv_account_balances IS
    'Totales Debit/Credit por company+period+account+status, refrescada automáticamente en cada commit. El filtro de status=ACTIVE se aplica en vw_account_balance, no acá.';
