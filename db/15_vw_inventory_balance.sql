-- ============================================================
-- 15_vw_inventory_balance.sql  (CORREGIDO)
-- Depende de: 14_inventory_movement.sql
-- Existencia (unidades) y valor acumulado por artículo.
--
-- OPENING_BALANCE SÍ suma (es la carga inicial real de existencia,
-- se registra una sola vez por artículo, al empezar a usarlo en
-- el sistema -- a diferencia de la contabilidad periódica, el
-- Kardex es perpetuo y NO necesita "reabrirse" cada período: su
-- saldo corrido de un período es automáticamente el inicial del
-- siguiente, sin necesitar un asiento de traspaso).
--
-- CLOSING_BALANCE NO suma: es el conteo físico de cierre, guardado
-- solo como referencia para comparar contra lo que el sistema
-- calculó solo (la diferencia, si la hay, es un faltante/sobrante).
-- ============================================================

CREATE OR REPLACE VIEW vw_inventory_balance AS
SELECT
    company_id,
    item_id,
    SUM(
        CASE movement_type
            WHEN 'OPENING_BALANCE'  THEN  quantity
            WHEN 'PURCHASE'         THEN  quantity
            WHEN 'SALES_RETURN'     THEN  quantity
            WHEN 'SALE'             THEN -quantity
            WHEN 'PURCHASE_RETURN'  THEN -quantity
            ELSE 0   -- CLOSING_BALANCE: solo referencia, no suma
        END
    ) AS quantity_on_hand,
    SUM(
        CASE movement_type
            WHEN 'OPENING_BALANCE'  THEN  quantity * unit_cost
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
    'Existencia y valor por artículo. OPENING_BALANCE suma (carga inicial única), CLOSING_BALANCE no (es solo referencia de conteo físico)';
