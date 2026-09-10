-- ============================================================
-- 15_vw_inventory_balance.sql
-- Depende de: 14_inventory_movement.sql
-- Existencia (unidades) y valor acumulado por artículo, calculado
-- sumando los movimientos con signo según el tipo.
--
-- OPENING_BALANCE y CLOSING_BALANCE se EXCLUYEN de la suma:
-- son registros de referencia/auditoría (el conteo físico que
-- se ingresa al abrir o cerrar el ejercicio), no un flujo que
-- deba sumarse o restarse. El objetivo es poder comparar el
-- inventario final que arroja el sistema (calculado acá) contra
-- el que se contó físicamente y quedó guardado como CLOSING_BALANCE.
-- ============================================================

CREATE OR REPLACE VIEW vw_inventory_balance AS
SELECT
    company_id,
    item_id,
    SUM(
        CASE movement_type
            WHEN 'PURCHASE'         THEN  quantity
            WHEN 'SALES_RETURN'     THEN  quantity
            WHEN 'SALE'             THEN -quantity
            WHEN 'PURCHASE_RETURN'  THEN -quantity
            ELSE 0   -- OPENING_BALANCE / CLOSING_BALANCE: solo referencia, no suman
        END
    ) AS quantity_on_hand,
    SUM(
        CASE movement_type
            WHEN 'PURCHASE'         THEN  quantity * unit_cost
            WHEN 'SALES_RETURN'     THEN  quantity * unit_cost
            WHEN 'SALE'             THEN -quantity * unit_cost
            WHEN 'PURCHASE_RETURN'  THEN -quantity * unit_cost
            ELSE 0
        END
    ) AS inventory_value
FROM inventory_movement
GROUP BY company_id, item_id;

COMMENT ON TABLE vw_inventory_balance IS
    'Existencia y valor por artículo calculado desde el Kardex (excluye filas OPENING/CLOSING_BALANCE, que son de referencia)';
