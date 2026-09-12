-- ============================================================
-- tests/test_views_and_constraints.sql
-- Correr conectado como CONTA_SCHEMA.
-- Pruebas transversales que no pertenecen a un paquete específico:
-- refresco de mv_account_balances, comportamiento de vw_account_balance
-- frente a reversos, la ventana acumulada, vw_inventory_balance, y el
-- CHECK constraint ck_gl_account_is_current. Usa la API pública de
-- pkg_journal_entry / pkg_inventory para generar los datos; solo hace
-- INSERT directo sobre gl_account para el Escenario 5 (constraint que
-- no se puede ejercitar de otra forma).
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_company_id   company.id%TYPE;
    v_user_id      user_account.id%TYPE;

    v_period1_id   accounting_period.id%TYPE;
    v_period2_id   accounting_period.id%TYPE;
    v_period3_id   accounting_period.id%TYPE;

    v_acc_cash     gl_account.id%TYPE;
    v_acc_revenue  gl_account.id%TYPE;

    v_acc_cash_acc gl_account.id%TYPE;  -- dedicadas al Escenario 3 (acumulado)
    v_acc_rev_acc  gl_account.id%TYPE;

    v_acc_cash_rev gl_account.id%TYPE;  -- dedicadas al Escenario 2 (reverso), aisladas
    v_acc_rev_rev  gl_account.id%TYPE;  -- para que la cuenta no tenga otros movimientos

    v_entry_id     journal_entry.id%TYPE;

    PROCEDURE report(p_case IN VARCHAR2, p_passed IN BOOLEAN, p_detail IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CASE WHEN p_passed THEN '[PASS] ' ELSE '[FAIL] ' END
                              || p_case || CASE WHEN p_detail IS NOT NULL THEN ' -- ' || p_detail END);
    END;

BEGIN
    ------------------------------------------------------------------
    -- FIXTURES
    ------------------------------------------------------------------
    INSERT INTO company (name) VALUES ('Empresa de Prueba - test_views_and_constraints')
        RETURNING id INTO v_company_id;

    INSERT INTO user_account (company_id, username, full_name, password_hash, password_salt)
        VALUES (v_company_id, 'test_user_vc_' || v_company_id, 'Usuario de Prueba', RPAD('x',64,'x'), RPAD('y',32,'y'))
        RETURNING id INTO v_user_id;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'P1', DATE '2026-01-01', DATE '2026-03-31', 'OPEN')
        RETURNING id INTO v_period1_id;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'P2', DATE '2026-04-01', DATE '2026-06-30', 'OPEN')
        RETURNING id INTO v_period2_id;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'P3', DATE '2026-07-01', DATE '2026-09-30', 'OPEN')
        RETURNING id INTO v_period3_id;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_current)
        VALUES (v_company_id, 'TEST-CASH-VC', 'Caja (prueba)', 'D', 'ASSET', 'Y', 'Y')
        RETURNING id INTO v_acc_cash;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-REV-VC', 'Ventas (prueba)', 'C', 'REVENUE', 'Y')
        RETURNING id INTO v_acc_revenue;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_current)
        VALUES (v_company_id, 'TEST-CASH-ACUM', 'Caja acumulada (prueba)', 'D', 'ASSET', 'Y', 'Y')
        RETURNING id INTO v_acc_cash_acc;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-REV-ACUM', 'Ventas acumuladas (prueba)', 'C', 'REVENUE', 'Y')
        RETURNING id INTO v_acc_rev_acc;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_current)
        VALUES (v_company_id, 'TEST-CASH-REV', 'Caja para reverso (prueba)', 'D', 'ASSET', 'Y', 'Y')
        RETURNING id INTO v_acc_cash_rev;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-REV-REV', 'Ventas para reverso (prueba)', 'C', 'REVENUE', 'Y')
        RETURNING id INTO v_acc_rev_rev;

    COMMIT;

    ------------------------------------------------------------------
    -- ESCENARIO 1 / REGRESIÓN (antes "Hallazgo crítico", ya corregido --
    -- ver test/HALLAZGOS.md #1): mv_account_balances agrupa por status,
    -- y post_entry hace un UPDATE de status (DRAFT->ACTIVE) sobre una
    -- fila ya agregada -- eso es un cambio de grupo que el algoritmo de
    -- FAST REFRESH incremental no soporta, así que se cambió a REFRESH
    -- COMPLETE ON COMMIT (sigue siendo automático, solo que el método
    -- interno ya no es FAST). Este escenario confirma que, sin ningún
    -- DBMS_MVIEW.REFRESH manual, el COMMIT deja la MV actualizada.
    ------------------------------------------------------------------
    DECLARE
        v_total_debit  mv_account_balances.total_debit%TYPE;
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(v_company_id, v_period1_id, DATE '2026-01-10', 'Escenario 1: refresco automático', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash, 'D', 100);
        pkg_journal_entry.add_line(v_entry_id, v_acc_revenue, 'C', 100);
        pkg_journal_entry.post_entry(v_entry_id);
        COMMIT;  -- dispara el REFRESH ON COMMIT, sin intervención manual

        SELECT total_debit INTO v_total_debit
          FROM mv_account_balances
         WHERE company_id = v_company_id AND period_id = v_period1_id
           AND account_id = v_acc_cash AND status = 'ACTIVE';

        report('Escenario 1: mv_account_balances se refresca sola con el COMMIT, sin DBMS_MVIEW.REFRESH manual',
               v_total_debit = 100, 'total_debit tras el COMMIT=' || v_total_debit);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 1: mv_account_balances', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 2: al reversar un asiento, vw_account_balance deja de
    -- contarlo (solo filtra status='ACTIVE'), pero mv_account_balances
    -- conserva el original bajo status='REVERSED'. Usa una cuenta
    -- DEDICADA y aislada (sin otros movimientos) para que la aritmética
    -- sea inequívoca: el original aporta +300 (Haber); al reversarse,
    -- SALE por completo del bucket ACTIVE (se va al bucket REVERSED) y
    -- el asiento de reverso aporta su propia línea -300 (Debe) al
    -- bucket ACTIVE -- por eso el saldo final queda en -300, no en 0
    -- (reversar no es "cancelar y desaparecer", es "excluir el original
    -- y sumar un movimiento contrario nuevo, real y permanente").
    ------------------------------------------------------------------
    DECLARE
        v_entry_y       journal_entry.id%TYPE;
        v_bal_before    NUMBER;
        v_bal_after     NUMBER;
        v_reversed_cred mv_account_balances.total_credit%TYPE;
    BEGIN
        v_entry_y := pkg_journal_entry.create_header(v_company_id, v_period1_id, DATE '2026-02-01', 'Escenario 2: a reversar', v_user_id);
        pkg_journal_entry.add_line(v_entry_y, v_acc_cash_rev, 'D', 300);
        pkg_journal_entry.add_line(v_entry_y, v_acc_rev_rev, 'C', 300);
        pkg_journal_entry.post_entry(v_entry_y);
        COMMIT;

        SELECT NVL(period_balance,0) INTO v_bal_before
          FROM vw_account_balance WHERE period_id = v_period1_id AND account_id = v_acc_rev_rev;

        DECLARE
            v_reversal_id journal_entry.id%TYPE;
        BEGIN
            v_reversal_id := pkg_journal_entry.reverse_entry(v_entry_y, DATE '2026-02-15', v_user_id);
        END;
        COMMIT;

        SELECT NVL(period_balance,0) INTO v_bal_after
          FROM vw_account_balance WHERE period_id = v_period1_id AND account_id = v_acc_rev_rev;

        SELECT total_credit INTO v_reversed_cred
          FROM mv_account_balances
         WHERE company_id = v_company_id AND period_id = v_period1_id
           AND account_id = v_acc_rev_rev AND status = 'REVERSED';

        report('Escenario 2: vw_account_balance excluye lo reversado, mv_account_balances lo conserva como REVERSED',
               v_bal_before = 300 AND v_bal_after = -300 AND v_reversed_cred = 300,
               'antes=' || v_bal_before || ' después=' || v_bal_after || ' credito_reversado=' || v_reversed_cred);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 2: vw_account_balance excluye lo reversado', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 3: accumulated_balance es la suma corrida (SUM() OVER)
    -- de los period_balance ordenados por start_date, para la misma
    -- cuenta -- se prueba con una cuenta dedicada (100 en cada uno de
    -- 3 períodos consecutivos)
    ------------------------------------------------------------------
    DECLARE
        v_acc_p1 NUMBER; v_acc_p2 NUMBER; v_acc_p3 NUMBER;
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(v_company_id, v_period1_id, DATE '2026-01-05', 'Escenario 3: P1', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash_acc, 'D', 100);
        pkg_journal_entry.add_line(v_entry_id, v_acc_rev_acc, 'C', 100);
        pkg_journal_entry.post_entry(v_entry_id);

        v_entry_id := pkg_journal_entry.create_header(v_company_id, v_period2_id, DATE '2026-04-05', 'Escenario 3: P2', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash_acc, 'D', 100);
        pkg_journal_entry.add_line(v_entry_id, v_acc_rev_acc, 'C', 100);
        pkg_journal_entry.post_entry(v_entry_id);

        v_entry_id := pkg_journal_entry.create_header(v_company_id, v_period3_id, DATE '2026-07-05', 'Escenario 3: P3', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash_acc, 'D', 100);
        pkg_journal_entry.add_line(v_entry_id, v_acc_rev_acc, 'C', 100);
        pkg_journal_entry.post_entry(v_entry_id);

        COMMIT;

        SELECT accumulated_balance INTO v_acc_p1 FROM vw_account_balance WHERE period_id = v_period1_id AND account_id = v_acc_cash_acc;
        SELECT accumulated_balance INTO v_acc_p2 FROM vw_account_balance WHERE period_id = v_period2_id AND account_id = v_acc_cash_acc;
        SELECT accumulated_balance INTO v_acc_p3 FROM vw_account_balance WHERE period_id = v_period3_id AND account_id = v_acc_cash_acc;

        report('Escenario 3: accumulated_balance es la suma corrida a través de 3 períodos',
               v_acc_p1 = 100 AND v_acc_p2 = 200 AND v_acc_p3 = 300,
               'P1=' || v_acc_p1 || ' P2=' || v_acc_p2 || ' P3=' || v_acc_p3);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 3: accumulated_balance es la suma corrida a través de 3 períodos', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 4 / REGRESIÓN (antes "Hallazgo", ya corregido -- ver
    -- test/HALLAZGOS.md #2): el UNIQUE (company_id, entry_number)
    -- original NO dejaba coexistir 2+ DRAFTs (entry_number NULL) de la
    -- misma empresa, porque Oracle solo excluye una fila del chequeo de
    -- unicidad si TODAS las columnas de la clave son NULL, y
    -- company_id nunca lo es acá. Se reemplazó el constraint por un
    -- índice único basado en función (ver db/16_alter_journal_entry_draft.sql)
    -- que solo indexa la fila cuando entry_number NO es NULL. Este
    -- escenario confirma que ahora sí coexisten.
    ------------------------------------------------------------------
    DECLARE
        v_draft1 journal_entry.id%TYPE;
        v_draft2 journal_entry.id%TYPE;
    BEGIN
        v_draft1 := pkg_journal_entry.create_header(v_company_id, v_period1_id, DATE '2026-03-01', 'Escenario 4: draft 1', v_user_id);
        COMMIT;

        v_draft2 := pkg_journal_entry.create_header(v_company_id, v_period1_id, DATE '2026-03-02', 'Escenario 4: draft 2', v_user_id);
        COMMIT;
        report('Escenario 4: varios DRAFT con entry_number NULL coexisten sin violar el UNIQUE', TRUE);

        pkg_journal_entry.discard_draft(v_draft2);
        pkg_journal_entry.discard_draft(v_draft1);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 4: varios DRAFT con entry_number NULL', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 5 / REGRESIÓN (antes "Hallazgo", ya corregido -- ver
    -- test/HALLAZGOS.md hallazgo medio #17): ck_gl_account_is_current
    -- ahora exige `is_current IS NOT NULL` explícito en la rama de
    -- ASSET/LIABILITY, así que un ASSET con is_current NULL debe
    -- rechazarse con ORA-02290.
    ------------------------------------------------------------------
    DECLARE
        v_acc_tmp gl_account.id%TYPE;
    BEGIN
        INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_current)
            VALUES (v_company_id, 'TEST-ASSET-NULL', 'Activo con is_current NULL (prueba)', 'D', 'ASSET', 'Y', NULL)
            RETURNING id INTO v_acc_tmp;
        report('Escenario 5a: rechazar ASSET con is_current NULL', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5a: rechazar ASSET con is_current NULL', SQLCODE = -2290, SQLERRM);
            ROLLBACK;
    END;

    DECLARE
        v_acc_tmp gl_account.id%TYPE;
    BEGIN
        INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_current)
            VALUES (v_company_id, 'TEST-ASSET-Y', 'Activo con is_current Y (prueba)', 'D', 'ASSET', 'Y', 'Y')
            RETURNING id INTO v_acc_tmp;
        report('Escenario 5b: ASSET con is_current=''Y'' se acepta', TRUE);
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5b: ASSET con is_current=''Y'' se acepta', FALSE, SQLERRM);
            ROLLBACK;
    END;

    DECLARE
        v_acc_tmp gl_account.id%TYPE;
    BEGIN
        INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_current)
            VALUES (v_company_id, 'TEST-EQUITY-Y', 'Patrimonio con is_current Y (prueba, inválido)', 'C', 'EQUITY', 'Y', 'Y')
            RETURNING id INTO v_acc_tmp;
        report('Escenario 5c: rechazar EQUITY con is_current=''Y''', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5c: rechazar EQUITY con is_current=''Y''', SQLCODE = -2290, SQLERRM);
            ROLLBACK;
    END;

    DECLARE
        v_acc_tmp gl_account.id%TYPE;
    BEGIN
        INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_current)
            VALUES (v_company_id, 'TEST-EQUITY-NULL', 'Patrimonio con is_current NULL (prueba, válido)', 'C', 'EQUITY', 'Y', NULL)
            RETURNING id INTO v_acc_tmp;
        report('Escenario 5d: EQUITY con is_current NULL se acepta', TRUE);
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5d: EQUITY con is_current NULL se acepta', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 6: vw_inventory_balance -- CLOSING_BALANCE no altera
    -- quantity_on_hand (chequeo rápido a nivel de vista; la cobertura
    -- completa de pkg_inventory vive en test_pkg_inventory.sql)
    ------------------------------------------------------------------
    DECLARE
        v_item_id    inventory_item.id%TYPE;
        v_mov_id     inventory_movement.id%TYPE;
        v_qty_before NUMBER;
        v_qty_after  NUMBER;
    BEGIN
        INSERT INTO inventory_item (company_id, code, name, unit_of_measure)
            VALUES (v_company_id, 'TEST-ITEM-VC', 'Artículo de prueba (vistas)', 'unidad')
            RETURNING id INTO v_item_id;
        COMMIT;

        v_mov_id := pkg_inventory.record_opening_balance(v_company_id, v_item_id, 50, 5, DATE '2026-01-01');
        COMMIT;

        SELECT quantity_on_hand INTO v_qty_before FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        v_mov_id := pkg_inventory.record_closing_count(v_company_id, v_item_id, 99999, 1, DATE '2026-12-31');
        COMMIT;

        SELECT quantity_on_hand INTO v_qty_after FROM vw_inventory_balance WHERE company_id = v_company_id AND item_id = v_item_id;

        report('Escenario 6: CLOSING_BALANCE no altera quantity_on_hand en vw_inventory_balance',
               v_qty_before = v_qty_after, 'antes=' || v_qty_before || ' después=' || v_qty_after);

        DELETE FROM inventory_movement WHERE item_id = v_item_id;
        DELETE FROM inventory_item WHERE id = v_item_id;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 6: CLOSING_BALANCE no altera quantity_on_hand', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- LIMPIEZA
    ------------------------------------------------------------------
    DELETE FROM inventory_movement WHERE company_id = v_company_id;
    DELETE FROM inventory_item WHERE company_id = v_company_id;
    DELETE FROM journal_entry_line WHERE journal_entry_id IN
        (SELECT id FROM journal_entry WHERE company_id = v_company_id);
    UPDATE journal_entry SET reverses_entry_id = NULL WHERE company_id = v_company_id;
    DELETE FROM journal_entry WHERE company_id = v_company_id;
    DELETE FROM gl_account WHERE company_id = v_company_id;
    DELETE FROM user_account WHERE company_id = v_company_id;
    DELETE FROM accounting_period WHERE company_id = v_company_id;
    DELETE FROM company WHERE id = v_company_id;
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('--- limpieza de datos de prueba completada ---');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR INESPERADO EN EL SETUP DE FIXTURES: ' || SQLERRM);
        ROLLBACK;
END;
/
