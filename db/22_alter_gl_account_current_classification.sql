-- ============================================================
-- 22_alter_gl_account_current_classification.sql
-- Depende de: 06_gl_account.sql
--
-- Agrega la distinción Corriente / No Corriente para armar el
-- Balance General con el detalle clásico. Solo aplica a cuentas
-- ASSET y LIABILITY -- para EQUITY/REVENUE/COST/EXPENSE queda NULL
-- (no tiene sentido esa clasificación ahí), y el CHECK constraint
-- lo obliga: si es ASSET/LIABILITY tiene que venir Y o N, si no,
-- tiene que quedar NULL.
-- ============================================================

ALTER TABLE gl_account ADD (
    is_current CHAR(1)
);

ALTER TABLE gl_account ADD CONSTRAINT ck_gl_account_is_current CHECK (
    (account_type IN ('ASSET','LIABILITY') AND is_current IN ('Y','N'))
    OR
    (account_type NOT IN ('ASSET','LIABILITY') AND is_current IS NULL)
);

COMMENT ON COLUMN gl_account.is_current IS
    'Solo para ASSET/LIABILITY: Y=Corriente, N=No Corriente. NULL para el resto de los tipos de cuenta.';
