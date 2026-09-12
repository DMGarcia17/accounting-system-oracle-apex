-- ============================================================
-- 10_mv_account_balances.sql  (CORREGIDO 2)
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
--
-- CORRECCIÓN 2 (encontrada probando en vivo, ver test/HALLAZGOS.md #1):
-- REFRESH FAST ON COMMIT nunca funcionó de verdad. status es parte
-- del GROUP BY, y PKG_JOURNAL_ENTRY.post_entry hace un UPDATE de
-- status (DRAFT->ACTIVE) sobre una fila que YA fue agregada a un
-- grupo -- eso es un cambio de membresía de grupo, no un INSERT
-- nuevo, y el algoritmo de fast refresh incremental para vistas
-- agregadas no lo soporta: cada UPDATE de status deja la MV en
-- staleness=UNUSABLE hasta un refresh COMPLETE manual (confirmado
-- con una reproducción real: INSERT-only mantiene FRESH, pero el
-- post_entry siguiente la vuelve UNUSABLE). Se cambia a REFRESH
-- COMPLETE ON COMMIT: sigue siendo automático (sin que ningún
-- caller tenga que acordarse de refrescar), sigue siendo "on commit"
-- como pide el diseño, solo que el método interno es COMPLETE en
-- vez de FAST -- para el volumen de este sistema el costo es
-- aceptable y la corrección es garantizada.
-- ============================================================

CREATE MATERIALIZED VIEW mv_account_balances
BUILD IMMEDIATE
REFRESH COMPLETE ON COMMIT
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
