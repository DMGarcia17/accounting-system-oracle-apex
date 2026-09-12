-- ============================================================
-- tests/test_pkg_journal_entry.sql
-- Correr conectado como CONTA_SCHEMA.
-- Suite de regresión: crea sus propios datos de prueba, corre
-- varios escenarios usando SOLO la API pública del paquete
-- (nunca INSERT directo sobre journal_entry/journal_entry_line,
-- a propósito -- así el test también valida que la API alcanza
-- para hacer todo lo necesario), y borra todo al final.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_company_id    company.id%TYPE;
    v_period_id     accounting_period.id%TYPE;
    v_user_id       user_account.id%TYPE;
    v_account_cash  gl_account.id%TYPE;
    v_account_rev   gl_account.id%TYPE;
    v_entry_id      journal_entry.id%TYPE;

    -- fixtures adicionales para Escenarios 7+ (otra empresa, cuenta inactiva)
    v_company2_id     company.id%TYPE;
    v_period2_id      accounting_period.id%TYPE;
    v_account_cash2   gl_account.id%TYPE;
    v_account_inactive gl_account.id%TYPE;

    PROCEDURE report(p_case IN VARCHAR2, p_passed IN BOOLEAN, p_detail IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CASE WHEN p_passed THEN '[PASS] ' ELSE '[FAIL] ' END
                              || p_case || CASE WHEN p_detail IS NOT NULL THEN ' -- ' || p_detail END);
    END;

BEGIN
    ------------------------------------------------------------------
    -- FIXTURES
    ------------------------------------------------------------------
    INSERT INTO company (name) VALUES ('Empresa de Prueba - test_pkg_journal_entry')
        RETURNING id INTO v_company_id;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'Período de prueba', DATE '2026-01-01', DATE '2026-12-31', 'OPEN')
        RETURNING id INTO v_period_id;

    INSERT INTO user_account (company_id, username, full_name, password_hash, password_salt)
        VALUES (v_company_id, 'test_user_' || v_company_id, 'Usuario de Prueba', RPAD('x',64,'x'), RPAD('y',32,'y'))
        RETURNING id INTO v_user_id;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-CASH', 'Caja (prueba)', 'D', 'ASSET', 'Y')
        RETURNING id INTO v_account_cash;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-REV', 'Ventas (prueba)', 'C', 'REVENUE', 'Y')
        RETURNING id INTO v_account_rev;

    COMMIT;

    ------------------------------------------------------------------
    -- ESCENARIO 1: asiento descuadrado debe ser rechazado en post_entry
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-03-15', 'Escenario 1: descuadrado', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_account_cash, 'D', 100);
        pkg_journal_entry.add_line(v_entry_id, v_account_rev, 'C', 50);

        pkg_journal_entry.post_entry(v_entry_id);
        report('Escenario 1: rechazar asiento descuadrado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 1: rechazar asiento descuadrado', SQLCODE = -20005, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 2: asiento válido debe postear y recibir correlativo
    ------------------------------------------------------------------
    DECLARE
        v_status journal_entry.status%TYPE;
        v_number journal_entry.entry_number%TYPE;
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-03-16', 'Escenario 2: válido', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_account_cash, 'D', 100);
        pkg_journal_entry.add_line(v_entry_id, v_account_rev, 'C', 100);
        pkg_journal_entry.post_entry(v_entry_id);

        SELECT status, entry_number INTO v_status, v_number FROM journal_entry WHERE id = v_entry_id;
        report('Escenario 2: postear asiento válido',
               v_status = 'ACTIVE' AND v_number IS NOT NULL, 'entry_number=' || v_number);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 2: postear asiento válido', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 3: add_line debe rechazar cuenta no-detalle
    ------------------------------------------------------------------
    DECLARE
        v_parent_account gl_account.id%TYPE;
    BEGIN
        INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
            VALUES (v_company_id, 'TEST-PARENT', 'Cuenta padre (prueba)', 'D', 'ASSET', 'N')
            RETURNING id INTO v_parent_account;
        COMMIT;

        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-03-17', 'Escenario 3: cuenta padre', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_parent_account, 'D', 100);
        report('Escenario 3: rechazar cuenta no-detalle', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 3: rechazar cuenta no-detalle', SQLCODE = -20017, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 4: create_header debe rechazar período cerrado
    ------------------------------------------------------------------
    BEGIN
        UPDATE accounting_period SET status = 'CLOSED' WHERE id = v_period_id;
        COMMIT;

        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-03-18', 'Escenario 4: período cerrado', v_user_id);
        report('Escenario 4: rechazar período cerrado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 4: rechazar período cerrado', SQLCODE = -20002, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 5: discard_draft borra un asiento en DRAFT
    ------------------------------------------------------------------
    DECLARE
        v_count NUMBER;
    BEGIN
        UPDATE accounting_period SET status = 'OPEN' WHERE id = v_period_id;
        COMMIT;

        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-03-19', 'Escenario 5: descartar', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_account_cash, 'D', 50);
        COMMIT;

        pkg_journal_entry.discard_draft(v_entry_id);

        SELECT COUNT(*) INTO v_count FROM journal_entry WHERE id = v_entry_id;
        report('Escenario 5: descartar borrador', v_count = 0);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5: descartar borrador', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 6: reverse_entry anula un asiento ACTIVE correctamente
    ------------------------------------------------------------------
    DECLARE
        v_reversal_id     journal_entry.id%TYPE;
        v_orig_status     journal_entry.status%TYPE;
        v_reversal_type   journal_entry.entry_type%TYPE;
        v_reverses_id     journal_entry.reverses_entry_id%TYPE;
        v_line_cash_type  journal_entry_line.movement_type%TYPE;
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-03-20', 'Escenario 6: a anular', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_account_cash, 'D', 200);
        pkg_journal_entry.add_line(v_entry_id, v_account_rev, 'C', 200);
        pkg_journal_entry.post_entry(v_entry_id);
        COMMIT;

        v_reversal_id := pkg_journal_entry.reverse_entry(v_entry_id, DATE '2026-03-21', v_user_id);

        SELECT status INTO v_orig_status FROM journal_entry WHERE id = v_entry_id;
        SELECT entry_type, reverses_entry_id INTO v_reversal_type, v_reverses_id
          FROM journal_entry WHERE id = v_reversal_id;
        SELECT movement_type INTO v_line_cash_type
          FROM journal_entry_line WHERE journal_entry_id = v_reversal_id AND account_id = v_account_cash;

        report('Escenario 6: anular asiento activo',
               v_orig_status = 'REVERSED'
               AND v_reversal_type = 'REVERSAL'
               AND v_reverses_id = v_entry_id
               AND v_line_cash_type = 'C',  -- la línea de Caja era D en el original, ahora debe ser C
               'orig_status=' || v_orig_status || ' reversal_line_cash=' || v_line_cash_type);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 6: anular asiento activo', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- FIXTURES ADICIONALES (para Escenarios 7+): otra empresa con su
    -- propio período/cuenta, y una cuenta inactiva en la empresa base.
    ------------------------------------------------------------------
    INSERT INTO company (name) VALUES ('Empresa de Prueba (otra) - test_pkg_journal_entry')
        RETURNING id INTO v_company2_id;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company2_id, 'Período de otra empresa', DATE '2026-01-01', DATE '2026-12-31', 'OPEN')
        RETURNING id INTO v_period2_id;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company2_id, 'TEST-CASH-2', 'Caja de otra empresa (prueba)', 'D', 'ASSET', 'Y')
        RETURNING id INTO v_account_cash2;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_active)
        VALUES (v_company_id, 'TEST-INACTIVE', 'Cuenta inactiva (prueba)', 'D', 'ASSET', 'Y', 'N')
        RETURNING id INTO v_account_inactive;

    COMMIT;

    ------------------------------------------------------------------
    -- ESCENARIO 7: create_header con período inexistente
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, -999999, DATE '2026-04-01', 'Escenario 7: período inexistente', v_user_id);
        report('Escenario 7: rechazar período inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 7: rechazar período inexistente', SQLCODE = -20010, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 8: create_header con período de otra empresa
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period2_id, DATE '2026-04-01', 'Escenario 8: período de otra empresa', v_user_id);
        report('Escenario 8: rechazar período de otra empresa', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 8: rechazar período de otra empresa', SQLCODE = -20011, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 9: create_header con fecha fuera del rango del período
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2027-01-01', 'Escenario 9: fecha fuera de rango', v_user_id);
        report('Escenario 9: rechazar fecha fuera de rango', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 9: rechazar fecha fuera de rango', SQLCODE = -20003, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 10: add_line sobre un asiento inexistente
    ------------------------------------------------------------------
    BEGIN
        pkg_journal_entry.add_line(-999999, v_account_cash, 'D', 100);
        report('Escenario 10: rechazar add_line sobre asiento inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 10: rechazar add_line sobre asiento inexistente', SQLCODE = -20008, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 11: add_line con movement_type inválido
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-02', 'Escenario 11: tipo de movimiento inválido', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'X', 100);
        report('Escenario 11: rechazar movement_type inválido', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 11: rechazar movement_type inválido', SQLCODE = -20013, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 12: add_line con monto <= 0
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-03', 'Escenario 12: monto inválido', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'D', 0);
        report('Escenario 12: rechazar monto <= 0', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 12: rechazar monto <= 0', SQLCODE = -20014, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 13: add_line con cuenta inexistente
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-04', 'Escenario 13: cuenta inexistente', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, -999999, 'D', 100);
        report('Escenario 13: rechazar cuenta inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 13: rechazar cuenta inexistente', SQLCODE = -20015, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 14: add_line con cuenta de otra empresa
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-05', 'Escenario 14: cuenta de otra empresa', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash2, 'D', 100);
        report('Escenario 14: rechazar cuenta de otra empresa', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 14: rechazar cuenta de otra empresa', SQLCODE = -20016, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 15: add_line con cuenta inactiva
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-06', 'Escenario 15: cuenta inactiva', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_inactive, 'D', 100);
        report('Escenario 15: rechazar cuenta inactiva', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 15: rechazar cuenta inactiva', SQLCODE = -20018, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 16: add_line sobre un asiento ya posteado (ACTIVE)
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-07', 'Escenario 16: asiento ya posteado', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'D', 100);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_rev, 'C', 100);
        pkg_journal_entry.post_entry(v_tmp_entry);
        COMMIT;

        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'D', 50);
        report('Escenario 16: rechazar add_line sobre asiento ya posteado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 16: rechazar add_line sobre asiento ya posteado', SQLCODE = -20012, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 17: post_entry sobre un asiento inexistente
    ------------------------------------------------------------------
    BEGIN
        pkg_journal_entry.post_entry(-999999);
        report('Escenario 17: rechazar post_entry sobre asiento inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 17: rechazar post_entry sobre asiento inexistente', SQLCODE = -20008, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 18: post_entry llamado dos veces sobre el mismo asiento
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-08', 'Escenario 18: postear dos veces', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'D', 100);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_rev, 'C', 100);
        pkg_journal_entry.post_entry(v_tmp_entry);
        COMMIT;

        pkg_journal_entry.post_entry(v_tmp_entry);
        report('Escenario 18: rechazar post_entry duplicado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 18: rechazar post_entry duplicado', SQLCODE = -20001, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 19: post_entry con menos de 2 líneas
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-09', 'Escenario 19: una sola línea', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'D', 100);
        pkg_journal_entry.post_entry(v_tmp_entry);
        report('Escenario 19: rechazar asiento con menos de 2 líneas', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 19: rechazar asiento con menos de 2 líneas', SQLCODE = -20004, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 20: discard_draft sobre un asiento inexistente
    ------------------------------------------------------------------
    BEGIN
        pkg_journal_entry.discard_draft(-999999);
        report('Escenario 20: rechazar discard_draft sobre asiento inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 20: rechazar discard_draft sobre asiento inexistente', SQLCODE = -20008, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 21: discard_draft sobre un asiento ya posteado
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-10', 'Escenario 21: descartar posteado', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'D', 100);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_rev, 'C', 100);
        pkg_journal_entry.post_entry(v_tmp_entry);
        COMMIT;

        pkg_journal_entry.discard_draft(v_tmp_entry);
        report('Escenario 21: rechazar discard_draft sobre asiento posteado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 21: rechazar discard_draft sobre asiento posteado', SQLCODE = -20007, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 22: reverse_entry sobre un asiento en DRAFT (no ACTIVE)
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
        v_dummy     journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-11', 'Escenario 22: reversar un DRAFT', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'D', 100);
        COMMIT;

        v_dummy := pkg_journal_entry.reverse_entry(v_tmp_entry, DATE '2026-04-12', v_user_id);
        report('Escenario 22: rechazar reverse_entry sobre un DRAFT', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 22: rechazar reverse_entry sobre un DRAFT', SQLCODE = -20019, SQLERRM);
            ROLLBACK;
            -- OJO: la excepción de reverse_entry no deshace nada (nunca
            -- llegó a modificar datos), así que v_tmp_entry sigue ahí
            -- como DRAFT con entry_number NULL. Lo descartamos acá para
            -- no dejarlo huérfano -- ver HALLAZGO D más abajo sobre por
            -- qué un DRAFT huérfano de este tipo rompe cualquier
            -- create_header posterior de la misma empresa.
            pkg_journal_entry.discard_draft(v_tmp_entry);
            COMMIT;
    END;

    ------------------------------------------------------------------
    -- REGRESIÓN (antes "Hallazgo D", ya corregido -- ver
    -- test/HALLAZGOS.md #2): el UNIQUE (company_id, entry_number)
    -- original trataba dos DRAFTs (entry_number NULL) de la misma
    -- empresa como duplicados entre sí (Oracle solo excluye una fila
    -- del chequeo de unicidad si TODAS las columnas de la clave son
    -- NULL, y company_id nunca lo es acá). Se reemplazó el constraint
    -- por un índice único basado en función que solo indexa la fila
    -- cuando entry_number NO es NULL (ver
    -- db/16_alter_journal_entry_draft.sql). Este escenario confirma
    -- que ahora sí coexisten dos DRAFTs de la misma empresa.
    ------------------------------------------------------------------
    DECLARE
        v_draft1 journal_entry.id%TYPE;
        v_draft2 journal_entry.id%TYPE;
    BEGIN
        v_draft1 := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-11', 'Regresión: primer DRAFT', v_user_id);
        COMMIT;

        v_draft2 := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-11', 'Regresión: segundo DRAFT', v_user_id);
        COMMIT;
        report('Regresión: dos DRAFT de la misma empresa coexisten sin violar el UNIQUE', TRUE);

        pkg_journal_entry.discard_draft(v_draft2);
        pkg_journal_entry.discard_draft(v_draft1);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Regresión: coexistencia de DRAFTs con entry_number NULL', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 23: reverse_entry sin período abierto que cubra la
    -- fecha de reverso
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
        v_dummy     journal_entry.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-13', 'Escenario 23: sin período para reversar', v_user_id);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_cash, 'D', 100);
        pkg_journal_entry.add_line(v_tmp_entry, v_account_rev, 'C', 100);
        pkg_journal_entry.post_entry(v_tmp_entry);
        COMMIT;

        v_dummy := pkg_journal_entry.reverse_entry(v_tmp_entry, DATE '2099-01-01', v_user_id);
        report('Escenario 23: rechazar reverso sin período abierto que lo cubra', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 23: rechazar reverso sin período abierto que lo cubra', SQLCODE = -20020, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO A: discard_draft sobre un DRAFT con un inventory_movement
    -- vinculado por journal_entry_id -- no hay manejo amigable de la
    -- violación de integridad referencial (ORA-02292 crudo).
    ------------------------------------------------------------------
    DECLARE
        v_tmp_entry journal_entry.id%TYPE;
        v_item_id2  inventory_item.id%TYPE;
        v_mov_id2   inventory_movement.id%TYPE;
    BEGIN
        v_tmp_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-14', 'Hallazgo A: draft con movimiento de Kardex vinculado', v_user_id);
        COMMIT;

        INSERT INTO inventory_item (company_id, code, name, unit_of_measure)
            VALUES (v_company_id, 'TEST-ITEM-JE', 'Artículo vinculado a asiento (prueba)', 'unidad')
            RETURNING id INTO v_item_id2;
        COMMIT;

        v_mov_id2 := pkg_inventory.record_purchase(v_company_id, v_item_id2, 10, 5, DATE '2026-04-14', v_tmp_entry);
        COMMIT;

        pkg_journal_entry.discard_draft(v_tmp_entry);
        report('Hallazgo A: discard_draft con movimiento de Kardex vinculado', FALSE,
               'se esperaba ORA-02292 y no lanzó ninguna excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo A: discard_draft con Kardex vinculado deja pasar ORA-02292 sin traducir a error de negocio',
                   SQLCODE = -2292, SQLERRM);
            -- limpieza puntual: discard_draft falló entero (nada se
            -- borró), así que primero quitamos el movimiento de Kardex
            -- que bloquea la FK, y recién ahí sí podemos descartar el
            -- DRAFT -- si no, queda huérfano con entry_number NULL y
            -- rompe cualquier create_header posterior de esta empresa
            -- (ver HALLAZGO D).
            DELETE FROM inventory_movement WHERE id = v_mov_id2;
            COMMIT;
            pkg_journal_entry.discard_draft(v_tmp_entry);
            DELETE FROM inventory_item WHERE id = v_item_id2;
            COMMIT;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO B: reverse_entry no valida entry_type -- permite
    -- reversar un asiento que ya es de tipo REVERSAL (cadena de
    -- reversos, anular una anulación).
    ------------------------------------------------------------------
    DECLARE
        v_orig_entry  journal_entry.id%TYPE;
        v_reversal_1  journal_entry.id%TYPE;
        v_reversal_2  journal_entry.id%TYPE;
        v_type2       journal_entry.entry_type%TYPE;
        v_reverses2   journal_entry.reverses_entry_id%TYPE;
    BEGIN
        v_orig_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-04-15', 'Hallazgo B: base para cadena de reversos', v_user_id);
        pkg_journal_entry.add_line(v_orig_entry, v_account_cash, 'D', 300);
        pkg_journal_entry.add_line(v_orig_entry, v_account_rev, 'C', 300);
        pkg_journal_entry.post_entry(v_orig_entry);
        COMMIT;

        v_reversal_1 := pkg_journal_entry.reverse_entry(v_orig_entry, DATE '2026-04-16', v_user_id);
        COMMIT;

        v_reversal_2 := pkg_journal_entry.reverse_entry(v_reversal_1, DATE '2026-04-17', v_user_id);
        COMMIT;

        SELECT entry_type, reverses_entry_id INTO v_type2, v_reverses2
          FROM journal_entry WHERE id = v_reversal_2;

        report('Hallazgo B: reverse_entry permite reversar un asiento de tipo REVERSAL (sin restricción de entry_type)',
               v_type2 = 'REVERSAL' AND v_reverses2 = v_reversal_1,
               'se encadenó un reverso sobre otro reverso sin que el paquete lo impida');
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo B: reverse_entry sobre un asiento de tipo REVERSAL', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO C: reverse_entry no valida que la fecha de reverso sea
    -- posterior (o igual) a la fecha del asiento original.
    ------------------------------------------------------------------
    DECLARE
        v_orig_entry         journal_entry.id%TYPE;
        v_reversal           journal_entry.id%TYPE;
        v_reversal_date_out  journal_entry.entry_date%TYPE;
    BEGIN
        v_orig_entry := pkg_journal_entry.create_header(
            v_company_id, v_period_id, DATE '2026-06-15', 'Hallazgo C: asiento para reverso retroactivo', v_user_id);
        pkg_journal_entry.add_line(v_orig_entry, v_account_cash, 'D', 50);
        pkg_journal_entry.add_line(v_orig_entry, v_account_rev, 'C', 50);
        pkg_journal_entry.post_entry(v_orig_entry);
        COMMIT;

        -- fecha de reverso ANTERIOR a la fecha del asiento original
        -- (2026-06-15), pero dentro del mismo período abierto
        v_reversal := pkg_journal_entry.reverse_entry(v_orig_entry, DATE '2026-01-05', v_user_id);
        COMMIT;

        SELECT entry_date INTO v_reversal_date_out FROM journal_entry WHERE id = v_reversal;

        report('Hallazgo C: reverse_entry acepta una fecha de reverso anterior a la del asiento original',
               v_reversal_date_out = DATE '2026-01-05',
               'fecha_reverso=' || TO_CHAR(v_reversal_date_out,'YYYY-MM-DD') || ' -- no valida orden cronológico');
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo C: reverse_entry con fecha de reverso retroactiva', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- LIMPIEZA
    ------------------------------------------------------------------
    DELETE FROM inventory_movement WHERE company_id IN (v_company_id, v_company2_id);
    DELETE FROM inventory_item WHERE company_id IN (v_company_id, v_company2_id);
    DELETE FROM journal_entry_line WHERE journal_entry_id IN
        (SELECT id FROM journal_entry WHERE company_id IN (v_company_id, v_company2_id));
    UPDATE journal_entry SET reverses_entry_id = NULL WHERE company_id IN (v_company_id, v_company2_id);
    DELETE FROM journal_entry WHERE company_id IN (v_company_id, v_company2_id);
    DELETE FROM gl_account WHERE company_id IN (v_company_id, v_company2_id);
    DELETE FROM user_account WHERE company_id IN (v_company_id, v_company2_id);
    DELETE FROM accounting_period WHERE company_id IN (v_company_id, v_company2_id);
    DELETE FROM company WHERE id IN (v_company_id, v_company2_id);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('--- limpieza de datos de prueba completada ---');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR INESPERADO EN EL SETUP DE FIXTURES: ' || SQLERRM);
        ROLLBACK;
END;
/
