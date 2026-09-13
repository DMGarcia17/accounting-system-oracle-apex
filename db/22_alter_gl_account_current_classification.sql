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

-- CORRECCIÓN (ver test/HALLAZGOS.md, hallazgo medio #17): la condición
-- original usaba `is_current IN ('Y','N')` para exigir Y/N en ASSET/
-- LIABILITY, pero por la lógica de 3 valores de SQL `NULL IN ('Y','N')`
-- evalúa a UNKNOWN (no FALSE), y un CHECK solo rechaza si evalúa a
-- FALSE -- así que un ASSET/LIABILITY con is_current NULL se aceptaba
-- sin error, contradiciendo la intención documentada arriba. Se agrega
-- `IS NOT NULL` explícito en esa rama.
--
-- AJUSTE (al cargar el catálogo de cuentas real de la docente, con
-- jerarquía profunda): la exigencia de Y/N solo tiene sentido en
-- cuentas de DETALLE (is_posting_account='Y') -- una cuenta ASSET/
-- LIABILITY que es puramente de agrupación (ej. la raíz "1 ACTIVO",
-- que agrupa tanto Corriente como No Corriente) no puede clasificarse
-- honestamente como una sola cosa. Para esas se permite NULL también.
ALTER TABLE gl_account ADD CONSTRAINT ck_gl_account_is_current CHECK (
    (account_type IN ('ASSET','LIABILITY') AND is_posting_account = 'Y' AND is_current IS NOT NULL AND is_current IN ('Y','N'))
    OR
    (account_type IN ('ASSET','LIABILITY') AND is_posting_account = 'N' AND is_current IS NULL)
    OR
    (account_type NOT IN ('ASSET','LIABILITY') AND is_current IS NULL)
);

COMMENT ON COLUMN gl_account.is_current IS
    'Solo para ASSET/LIABILITY de detalle (is_posting_account=Y): Y=Corriente, N=No Corriente. NULL para el resto (incluidas las cuentas de agrupación ASSET/LIABILITY).';
