-- ============================================================
-- 17_alter_journal_entry_reversal.sql
-- Depende de: 16_alter_journal_entry_draft.sql
-- Agrega el puntero de trazabilidad para asientos de anulación.
-- Vive en el asiento de REVERSO (no en el original): apunta hacia
-- atrás, al asiento que está anulando. Así se puede recuperar
-- "qué lo anuló" con una consulta simple hacia adelante:
--   SELECT * FROM journal_entry WHERE reverses_entry_id = :id_original
-- ============================================================

ALTER TABLE journal_entry ADD (
    reverses_entry_id   NUMBER
                         CONSTRAINT fk_entry_reverses
                         REFERENCES journal_entry(id)
);

COMMENT ON COLUMN journal_entry.reverses_entry_id IS
    'Solo se llena en asientos entry_type=REVERSAL: apunta al asiento original que este anula';
