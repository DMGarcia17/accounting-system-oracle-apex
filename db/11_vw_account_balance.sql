-- ============================================================
-- 11_vw_account_balance.sql  (CORREGIDO)
-- Depende de: 10_mv_account_balances.sql, 06_gl_account.sql,
--             02_accounting_period.sql
-- Vista NORMAL (no materializada) que le aplica a los totales
-- crudos de la vista materializada la regla de naturaleza:
--   - Cuenta Deudora (normal_balance='D'): saldo = Debit - Credit
--   - Cuenta Acreedora (normal_balance='C'): saldo = Credit - Debit
--
-- El filtro status = 'ACTIVE' vive ACÁ (no en la vista materializada,
-- ver nota en 10_mv_account_balances.sql sobre el ORA-12033) -- así
-- los asientos REVERSADOS quedan excluidos de los saldos que ve
-- el usuario, sin romper el FAST REFRESH.
--
-- Expone DOS columnas de saldo:
--   period_balance      -> solo el movimiento de ESE período
--                          (lo que usa el Estado de Resultados)
--   accumulated_balance -> acumulado desde el primer período hasta
--                          este (lo que usa el Balance General)
-- ============================================================

CREATE OR REPLACE VIEW vw_account_balance AS
WITH base AS (
    SELECT
        mv.company_id,
        mv.period_id,
        p.start_date,
        mv.account_id,
        a.normal_balance,
        a.account_type,
        mv.total_debit,
        mv.total_credit,
        -- Acumulado de Debit y Credit desde el primer período hasta este,
        -- para la misma empresa y cuenta.
        SUM(mv.total_debit)  OVER (PARTITION BY mv.company_id, mv.account_id
                                    ORDER BY p.start_date) AS accumulated_debit,
        SUM(mv.total_credit) OVER (PARTITION BY mv.company_id, mv.account_id
                                    ORDER BY p.start_date) AS accumulated_credit
    FROM mv_account_balances mv
    JOIN accounting_period p ON p.id = mv.period_id
    JOIN gl_account         a ON a.id = mv.account_id
    WHERE mv.status = 'ACTIVE'
)
SELECT
    company_id,
    period_id,
    account_id,
    normal_balance,
    account_type,
    total_debit,
    total_credit,
    CASE WHEN normal_balance = 'D' THEN total_debit  - total_credit
         ELSE                         total_credit - total_debit
    END AS period_balance,
    CASE WHEN normal_balance = 'D' THEN accumulated_debit  - accumulated_credit
         ELSE                         accumulated_credit - accumulated_debit
    END AS accumulated_balance
FROM base;

COMMENT ON TABLE vw_account_balance IS
    'Saldos por cuenta aplicando naturaleza: period_balance para Estado de Resultados, accumulated_balance para Balance General. Filtra status=ACTIVE.';
