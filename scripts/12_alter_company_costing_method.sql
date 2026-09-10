-- ============================================================
-- 12_alter_company_costing_method.sql
-- Depende de: 01_company.sql
-- Agrega la política de costeo de inventario a nivel empresa.
-- Por defecto AVERAGE (Promedio Ponderado) porque no tenemos
-- confirmación del método exacto que usa la materia todavía.
-- Si resulta ser FIFO/PEPS, cambiar el valor y usar la columna
-- remaining_quantity de inventory_movement (14) para las capas.
-- ============================================================

ALTER TABLE company ADD (
    inventory_costing_method   VARCHAR2(10)  DEFAULT 'AVERAGE' NOT NULL
                                CONSTRAINT ck_company_costing_method
                                CHECK (inventory_costing_method IN ('AVERAGE','FIFO'))
);

COMMENT ON COLUMN company.inventory_costing_method IS
    'Método de costeo del Kardex: AVERAGE (Promedio Ponderado) o FIFO (PEPS). Pendiente confirmar con el curso.';
