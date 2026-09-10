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

COMMENT ON COLUMN journal_entry.status IS
    'DRAFT=insertado sin validar, ACTIVE=posteado y válido, REVERSED=anulado por otro asiento';
COMMENT ON COLUMN journal_entry.entry_number IS
    'NULL mientras está en DRAFT. Se asigna en PKG_JOURNAL_ENTRY.post_entry, correlativo por empresa';
