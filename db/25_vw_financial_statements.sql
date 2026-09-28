-- ============================================================
-- 25_vw_financial_statements.sql
-- Depende de: 11_vw_account_balance.sql, 22_alter_gl_account_current_classification.sql
--
-- Dos vistas de solo lectura para armar los estados financieros
-- en APEX. No agregan reglas de negocio nuevas -- solo reexponen
-- vw_account_balance filtrando por naturaleza de cuenta.
-- ============================================================

-- Balance General: Activo / Pasivo / Patrimonio, saldo ACUMULADO
-- (vive desde la apertura de la empresa, no se resetea por período).
CREATE OR REPLACE VIEW vw_balance_sheet AS
SELECT vab.company_id,
       vab.period_id,
       vab.account_id,
       ga.code,
       ga.name,
       ga.account_type,
       ga.is_current,
       vab.accumulated_balance
  FROM vw_account_balance vab
  JOIN gl_account ga ON ga.id = vab.account_id
 WHERE ga.account_type IN ('ASSET','LIABILITY','EQUITY');

COMMENT ON TABLE vw_balance_sheet IS
    'Cuentas de Balance General (Activo/Pasivo/Patrimonio) con saldo acumulado, para reporte por período.';

-- Estado de Resultados: Ingresos / Costos / Gastos, saldo del PERÍODO
-- (se resetea en cada ejercicio, no es acumulado).
CREATE OR REPLACE VIEW vw_income_statement AS
SELECT vab.company_id,
       vab.period_id,
       vab.account_id,
       ga.code,
       ga.name,
       ga.account_type,
       vab.period_balance
  FROM vw_account_balance vab
  JOIN gl_account ga ON ga.id = vab.account_id
 WHERE ga.account_type IN ('REVENUE','COST','EXPENSE');

COMMENT ON TABLE vw_income_statement IS
    'Cuentas de Estado de Resultados (Ingresos/Costos/Gastos) con saldo del período.';
