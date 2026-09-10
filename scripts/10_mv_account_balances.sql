-- ============================================================
-- 10_mv_account_balances.sql
-- Depende de: 09_mv_log_journal_entry_line.sql, 07_journal_entry.sql
-- Totales de Debit/Credit por company+account+PERÍODO.
-- Agrupar por período (no solo por cuenta) es lo que permite
-- distinguir después "saldo del período" (Estado de Resultados)
-- de "saldo acumulado" (Balance General) sin duplicar lógica acá.
--
-- COUNT(*) junto a cada SUM es requisito de Oracle para que el
-- fast refresh maneje correctamente NULLs y eliminaciones de filas.
-- ============================================================

CREATE MATERIALIZED VIEW mv_account_balances
BUILD IMMEDIATE
REFRESH FAST ON COMMIT
AS
SELECT
    e.company_id,
    e.period_id,
    l.account_id,
    SUM(CASE WHEN l.movement_type = 'D' THEN l.amount ELSE 0 END) AS total_debit,
    SUM(CASE WHEN l.movement_type = 'C' THEN l.amount ELSE 0 END) AS total_credit,
    COUNT(*) AS line_count
FROM journal_entry_line l
JOIN journal_entry e ON e.id = l.journal_entry_id
WHERE e.status = 'ACTIVE'
GROUP BY e.company_id, e.period_id, l.account_id;

COMMENT ON MATERIALIZED VIEW mv_account_balances IS
    'Totales Debit/Credit por company+period+account, refrescada automáticamente en cada commit';
