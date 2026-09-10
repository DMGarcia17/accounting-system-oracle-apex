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
    -- LIMPIEZA
    ------------------------------------------------------------------
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
