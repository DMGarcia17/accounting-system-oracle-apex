-- ============================================================
-- tests/test_pkg_inventory.sql
-- Correr conectado como CONTA_SCHEMA.
-- Suite de regresión de pkg_inventory (Kardex): crea sus propios
-- datos de prueba, corre varios escenarios usando SOLO la API
-- pública del paquete (nunca INSERT directo sobre inventory_movement),
-- y borra todo al final.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_company_id       company.id%TYPE;
    v_company_other_id company.id%TYPE;
    v_company_fifo_id  company.id%TYPE;
    v_item_id          inventory_item.id%TYPE;
    v_item_other_id    inventory_item.id%TYPE;
    v_item_inactive_id inventory_item.id%TYPE;
    v_item_fifo_id     inventory_item.id%TYPE;
    v_mov_id           inventory_movement.id%TYPE;

    PROCEDURE report(p_case IN VARCHAR2, p_passed IN BOOLEAN, p_detail IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CASE WHEN p_passed THEN '[PASS] ' ELSE '[FAIL] ' END
                              || p_case || CASE WHEN p_detail IS NOT NULL THEN ' -- ' || p_detail END);
    END;

BEGIN
    ------------------------------------------------------------------
    -- FIXTURES
    ------------------------------------------------------------------
    INSERT INTO company (name) VALUES ('Empresa de Prueba - test_pkg_inventory')
        RETURNING id INTO v_company_id;

    INSERT INTO company (name) VALUES ('Empresa de Prueba (otra) - test_pkg_inventory')
        RETURNING id INTO v_company_other_id;

    INSERT INTO company (name, inventory_costing_method)
        VALUES ('Empresa de Prueba FIFO - test_pkg_inventory', 'FIFO')
        RETURNING id INTO v_company_fifo_id;

    INSERT INTO inventory_item (company_id, code, name, unit_of_measure)
        VALUES (v_company_id, 'TEST-ITEM', 'Artículo de prueba', 'unidad')
        RETURNING id INTO v_item_id;

    INSERT INTO inventory_item (company_id, code, name, unit_of_measure)
        VALUES (v_company_other_id, 'TEST-ITEM-OTHER', 'Artículo de otra empresa', 'unidad')
        RETURNING id INTO v_item_other_id;

    INSERT INTO inventory_item (company_id, code, name, unit_of_measure, is_active)
        VALUES (v_company_id, 'TEST-ITEM-INACTIVE', 'Artículo inactivo', 'unidad', 'N')
        RETURNING id INTO v_item_inactive_id;

    INSERT INTO inventory_item (company_id, code, name, unit_of_measure)
        VALUES (v_company_fifo_id, 'TEST-ITEM-FIFO', 'Artículo empresa FIFO', 'unidad')
        RETURNING id INTO v_item_fifo_id;

    COMMIT;

    ------------------------------------------------------------------
    -- ESCENARIO 1: record_opening_balance con artículo inexistente
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.record_opening_balance(v_company_id, -999999, 10, 5, DATE '2026-01-01');
        report('Escenario 1: rechazar artículo inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 1: rechazar artículo inexistente', SQLCODE = -20050, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 2: record_opening_balance con artículo de otra empresa
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.record_opening_balance(v_company_id, v_item_other_id, 10, 5, DATE '2026-01-01');
        report('Escenario 2: rechazar artículo de otra empresa', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 2: rechazar artículo de otra empresa', SQLCODE = -20051, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 3: record_opening_balance con artículo inactivo
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.record_opening_balance(v_company_id, v_item_inactive_id, 10, 5, DATE '2026-01-01');
        report('Escenario 3: rechazar artículo inactivo', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 3: rechazar artículo inactivo', SQLCODE = -20052, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 4: record_opening_balance con cantidad <= 0
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.record_opening_balance(v_company_id, v_item_id, 0, 5, DATE '2026-01-01');
        report('Escenario 4: rechazar cantidad <= 0', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 4: rechazar cantidad <= 0', SQLCODE = -20053, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 5: record_opening_balance válida (carga inicial 100 @ 10)
    ------------------------------------------------------------------
    DECLARE
        v_qty NUMBER;
        v_val NUMBER;
    BEGIN
        v_mov_id := pkg_inventory.record_opening_balance(v_company_id, v_item_id, 100, 10, DATE '2026-01-01');
        COMMIT;

        SELECT quantity_on_hand, inventory_value INTO v_qty, v_val
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        report('Escenario 5: carga inicial válida', v_qty = 100 AND v_val = 1000,
               'qty=' || v_qty || ' val=' || v_val);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5: carga inicial válida', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 6: record_opening_balance de nuevo sobre el mismo
    -- artículo debe rechazarse (ya tiene movimientos)
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.record_opening_balance(v_company_id, v_item_id, 5, 1, DATE '2026-01-02');
        report('Escenario 6: rechazar segunda carga inicial', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 6: rechazar segunda carga inicial', SQLCODE = -20054, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 7: record_purchase con costo unitario negativo
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.record_purchase(v_company_id, v_item_id, 10, -1, DATE '2026-01-03');
        report('Escenario 7: rechazar costo unitario negativo', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 7: rechazar costo unitario negativo', SQLCODE = -20055, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 8: record_purchase válida (compra 50 @ 20) -> queda
    -- 150 unidades, valor 2000
    ------------------------------------------------------------------
    DECLARE
        v_qty NUMBER;
        v_val NUMBER;
    BEGIN
        v_mov_id := pkg_inventory.record_purchase(v_company_id, v_item_id, 50, 20, DATE '2026-01-03');
        COMMIT;

        SELECT quantity_on_hand, inventory_value INTO v_qty, v_val
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        report('Escenario 8: compra válida', v_qty = 150 AND v_val = 2000,
               'qty=' || v_qty || ' val=' || v_val);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 8: compra válida', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 9: record_sale sin existencia suficiente
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.record_sale(v_company_id, v_item_id, 999, DATE '2026-01-04');
        report('Escenario 9: rechazar venta sin existencia suficiente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 9: rechazar venta sin existencia suficiente', SQLCODE = -20056, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 10: record_sale válida (vende 30 al costo promedio
    -- actual, 2000/150) -> queda 120 unidades
    ------------------------------------------------------------------
    DECLARE
        v_qty          NUMBER;
        v_val          NUMBER;
        v_sale_cost    NUMBER;
        v_expected_val NUMBER;
    BEGIN
        v_mov_id := pkg_inventory.record_sale(v_company_id, v_item_id, 30, DATE '2026-01-04');
        COMMIT;

        SELECT unit_cost INTO v_sale_cost FROM inventory_movement WHERE id = v_mov_id;
        SELECT quantity_on_hand, inventory_value INTO v_qty, v_val
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        v_expected_val := 2000 - (30 * v_sale_cost);

        report('Escenario 10: venta válida al costo promedio', v_qty = 120 AND v_val = v_expected_val,
               'qty=' || v_qty || ' val=' || v_val || ' costo_venta=' || v_sale_cost);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 10: venta válida al costo promedio', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 11: record_purchase_return válida (devuelve 20 al
    -- proveedor, al costo promedio actual)
    ------------------------------------------------------------------
    DECLARE
        v_qty NUMBER;
    BEGIN
        v_mov_id := pkg_inventory.record_purchase_return(v_company_id, v_item_id, 20, DATE '2026-01-05');
        COMMIT;

        SELECT quantity_on_hand INTO v_qty
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        report('Escenario 11: devolución sobre compra válida', v_qty = 100, 'qty=' || v_qty);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 11: devolución sobre compra válida', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 12: record_sales_return válida (cliente devuelve 10,
    -- costo unitario explícito 15)
    ------------------------------------------------------------------
    DECLARE
        v_qty NUMBER;
    BEGIN
        v_mov_id := pkg_inventory.record_sales_return(v_company_id, v_item_id, 10, 15, DATE '2026-01-06');
        COMMIT;

        SELECT quantity_on_hand INTO v_qty
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        report('Escenario 12: devolución sobre venta válida', v_qty = 110, 'qty=' || v_qty);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 12: devolución sobre venta válida', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 13: record_closing_count NO debe alterar quantity_on_hand
    ------------------------------------------------------------------
    DECLARE
        v_qty_before NUMBER;
        v_qty_after  NUMBER;
    BEGIN
        SELECT quantity_on_hand INTO v_qty_before
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        v_mov_id := pkg_inventory.record_closing_count(v_company_id, v_item_id, 99999, 1, DATE '2026-12-31');
        COMMIT;

        SELECT quantity_on_hand INTO v_qty_after
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        report('Escenario 13: closing_count no altera existencia', v_qty_after = v_qty_before,
               'antes=' || v_qty_before || ' después=' || v_qty_after);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 13: closing_count no altera existencia', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 14: record_closing_count con cantidad negativa
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.record_closing_count(v_company_id, v_item_id, -1, 1, DATE '2026-12-31');
        report('Escenario 14: rechazar closing_count negativo', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 14: rechazar closing_count negativo', SQLCODE = -20053, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 15: reverse_movement con movimiento inexistente
    ------------------------------------------------------------------
    BEGIN
        v_mov_id := pkg_inventory.reverse_movement(-999999, DATE '2026-01-07');
        report('Escenario 15: rechazar reverso de movimiento inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 15: rechazar reverso de movimiento inexistente', SQLCODE = -20057, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 16: reverse_movement sobre OPENING_BALANCE debe
    -- rechazarse
    ------------------------------------------------------------------
    DECLARE
        v_opening_id inventory_movement.id%TYPE;
    BEGIN
        SELECT id INTO v_opening_id FROM inventory_movement
         WHERE item_id = v_item_id AND movement_type = 'OPENING_BALANCE';

        v_mov_id := pkg_inventory.reverse_movement(v_opening_id, DATE '2026-01-07');
        report('Escenario 16: rechazar reverso de OPENING_BALANCE', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 16: rechazar reverso de OPENING_BALANCE', SQLCODE = -20058, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 17: reverse_movement sobre CLOSING_BALANCE debe
    -- rechazarse
    ------------------------------------------------------------------
    DECLARE
        v_closing_id inventory_movement.id%TYPE;
    BEGIN
        SELECT id INTO v_closing_id FROM inventory_movement
         WHERE item_id = v_item_id AND movement_type = 'CLOSING_BALANCE';

        v_mov_id := pkg_inventory.reverse_movement(v_closing_id, DATE '2026-01-07');
        report('Escenario 17: rechazar reverso de CLOSING_BALANCE', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 17: rechazar reverso de CLOSING_BALANCE', SQLCODE = -20058, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 18: reverse_movement sobre una compra (PURCHASE)
    -- crea un PURCHASE_RETURN y descuenta existencia
    ------------------------------------------------------------------
    DECLARE
        v_purchase_id inventory_movement.id%TYPE;
        v_qty_before  NUMBER;
        v_qty_after   NUMBER;
        v_reversal_id inventory_movement.id%TYPE;
        v_rev_type    inventory_movement.movement_type%TYPE;
    BEGIN
        SELECT id INTO v_purchase_id FROM inventory_movement
         WHERE item_id = v_item_id AND movement_type = 'PURCHASE' AND ROWNUM = 1;

        SELECT quantity_on_hand INTO v_qty_before
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        v_reversal_id := pkg_inventory.reverse_movement(v_purchase_id, DATE '2026-01-08');
        COMMIT;

        SELECT movement_type INTO v_rev_type FROM inventory_movement WHERE id = v_reversal_id;
        SELECT quantity_on_hand INTO v_qty_after
          FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        report('Escenario 18: reversar una compra genera devolución y descuenta existencia',
               v_rev_type = 'PURCHASE_RETURN' AND v_qty_after = v_qty_before - 50,
               'tipo=' || v_rev_type || ' antes=' || v_qty_before || ' después=' || v_qty_after);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 18: reversar una compra genera devolución y descuenta existencia', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO: reverse_movement no impide reversar el MISMO
    -- movimiento dos veces (no existe columna is_reversed / reversed_by
    -- en inventory_movement que lo bloquee). Si hay existencia
    -- suficiente, la segunda llamada también se ejecuta sin error --
    -- eso es justo lo que confirmamos acá.
    ------------------------------------------------------------------
    DECLARE
        v_purchase_id    inventory_movement.id%TYPE;
        v_reversal_id    inventory_movement.id%TYPE;
        v_bug_confirmado BOOLEAN := FALSE;
    BEGIN
        SELECT id INTO v_purchase_id FROM inventory_movement
         WHERE item_id = v_item_id AND movement_type = 'PURCHASE' AND ROWNUM = 1;

        -- Esta compra YA fue reversada en el Escenario 18. La volvemos
        -- a reversar para confirmar que no hay protección contra el
        -- doble reverso.
        BEGIN
            v_reversal_id := pkg_inventory.reverse_movement(v_purchase_id, DATE '2026-01-09');
            COMMIT;
            v_bug_confirmado := TRUE;
        EXCEPTION
            WHEN OTHERS THEN
                v_bug_confirmado := FALSE;
                ROLLBACK;
        END;

        report('Hallazgo: reverse_movement permite reversar el mismo movimiento más de una vez',
               v_bug_confirmado,
               CASE WHEN v_bug_confirmado THEN 'confirmado: el segundo reverso se ejecutó sin error'
                    ELSE 'no se pudo reproducir en este dataset (probablemente falló por -20059)' END);
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo: reverse_movement permite reversar el mismo movimiento más de una vez', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO: una empresa con inventory_costing_method='FIFO' igual
    -- se costea por Promedio Ponderado -- pkg_inventory ignora esa
    -- columna por completo.
    ------------------------------------------------------------------
    DECLARE
        v_p1           inventory_movement.id%TYPE;
        v_p2           inventory_movement.id%TYPE;
        v_s            inventory_movement.id%TYPE;
        v_sale_cost    NUMBER;
        v_expected_avg NUMBER;
    BEGIN
        v_p1 := pkg_inventory.record_purchase(v_company_fifo_id, v_item_fifo_id, 10, 10, DATE '2026-01-01'); -- 10@10=100
        v_p2 := pkg_inventory.record_purchase(v_company_fifo_id, v_item_fifo_id, 10, 20, DATE '2026-01-02'); -- 10@20=200
        -- total: 20 unidades, valor 300, promedio 15. Si fuera FIFO real,
        -- vender 10 debería salir a 10 (el lote más viejo), no a 15.
        v_s := pkg_inventory.record_sale(v_company_fifo_id, v_item_fifo_id, 10, DATE '2026-01-03');
        COMMIT;

        SELECT unit_cost INTO v_sale_cost FROM inventory_movement WHERE id = v_s;
        v_expected_avg := 300 / 20; -- 15

        report('Hallazgo: empresa con costing_method=FIFO igual se costea por promedio ponderado',
               v_sale_cost = v_expected_avg,
               'costo_usado=' || v_sale_cost || ' (promedio esperado=' || v_expected_avg ||
               ', FIFO real habría usado 10)');
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo: empresa con costing_method=FIFO igual se costea por promedio ponderado', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- LIMPIEZA
    ------------------------------------------------------------------
    DELETE FROM inventory_movement WHERE company_id IN (v_company_id, v_company_other_id, v_company_fifo_id);
    DELETE FROM inventory_item WHERE company_id IN (v_company_id, v_company_other_id, v_company_fifo_id);
    DELETE FROM company WHERE id IN (v_company_id, v_company_other_id, v_company_fifo_id);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('--- limpieza de datos de prueba completada ---');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR INESPERADO EN EL SETUP DE FIXTURES: ' || SQLERRM);
        ROLLBACK;
END;
/
