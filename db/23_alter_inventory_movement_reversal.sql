-- ============================================================
-- 23_alter_inventory_movement_reversal.sql
-- Depende de: 14_inventory_movement.sql
-- Agrega el puntero de trazabilidad para reversos de Kardex, igual
-- patrón que 17_alter_journal_entry_reversal.sql para asientos:
-- vive en el movimiento de REVERSO (no en el original) y apunta
-- hacia atrás, al movimiento que está anulando.
--
-- CORRECCIÓN (ver test/HALLAZGOS.md, hallazgo alto #7):
-- pkg_inventory.reverse_movement no tenía ninguna protección contra
-- reversar el mismo movimiento más de una vez (cada llamada generaba
-- otro movimiento contrario adicional). Con esta columna,
-- reverse_movement puede validar si el movimiento ya fue reversado
-- antes de insertar uno nuevo:
--   SELECT COUNT(*) FROM inventory_movement WHERE reverses_movement_id = :id_original
-- ============================================================

ALTER TABLE inventory_movement ADD (
    reverses_movement_id   NUMBER
                            CONSTRAINT fk_movement_reverses
                            REFERENCES inventory_movement(id)
);

COMMENT ON COLUMN inventory_movement.reverses_movement_id IS
    'Solo se llena en el movimiento generado por reverse_movement: apunta al movimiento original que este anula';
