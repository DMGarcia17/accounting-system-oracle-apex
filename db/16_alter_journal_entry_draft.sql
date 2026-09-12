-- ============================================================
-- 16_alter_journal_entry_draft.sql
-- Depende de: 07_journal_entry.sql
-- Ajusta JOURNAL_ENTRY para soportar el flujo "insertar como
-- borrador, validar y postear después" que maneja PKG_JOURNAL_ENTRY.
-- Sin este ajuste, la tabla exige el entry_number desde el insert,
-- lo cual no es compatible con ese flujo (el correlativo se asigna
-- recién al postear, no al crear el borrador).
-- ============================================================

ALTER TABLE journal_entry MODIFY (entry_number NULL);

ALTER TABLE journal_entry DROP CONSTRAINT ck_entry_status;

ALTER TABLE journal_entry ADD CONSTRAINT ck_entry_status
    CHECK (status IN ('DRAFT','ACTIVE','REVERSED'));

ALTER TABLE journal_entry MODIFY (status DEFAULT 'DRAFT');

-- CORRECCIÓN (ver test/HALLAZGOS.md #2): el UNIQUE (company_id, entry_number)
-- original NO deja coexistir 2+ DRAFTs (entry_number NULL) de la misma
-- empresa -- Oracle solo excluye una fila del chequeo de unicidad de una
-- clave compuesta si TODAS sus columnas son NULL, y company_id nunca lo es
-- acá. Confirmado con reproducción real: el segundo create_header de una
-- empresa con cualquier DRAFT pendiente revienta con ORA-00001. Se
-- reemplaza el constraint por un índice único basado en función que solo
-- indexa la fila cuando entry_number NO es NULL -- así, con entry_number
-- NULL, ambas expresiones de la clave dan NULL (fila excluida del índice,
-- múltiples DRAFTs conviven libremente), y con entry_number asignado la
-- unicidad real (company_id, entry_number) se sigue exigiendo igual que
-- antes.
ALTER TABLE journal_entry DROP CONSTRAINT uq_entry_company_number;

CREATE UNIQUE INDEX uq_entry_company_number ON journal_entry (
    CASE WHEN entry_number IS NOT NULL THEN company_id   END,
    CASE WHEN entry_number IS NOT NULL THEN entry_number END
);

COMMENT ON COLUMN journal_entry.status IS
    'DRAFT=insertado sin validar, ACTIVE=posteado y válido, REVERSED=anulado por otro asiento';
COMMENT ON COLUMN journal_entry.entry_number IS
    'NULL mientras está en DRAFT. Se asigna en PKG_JOURNAL_ENTRY.post_entry, correlativo por empresa';
