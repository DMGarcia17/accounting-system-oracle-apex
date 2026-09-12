-- ============================================================
-- tests/test_pkg_entry_template.sql
-- Correr conectado como CONTA_SCHEMA.
-- Suite de regresión de pkg_entry_template: crea sus propios datos
-- de prueba, corre varios escenarios usando SOLO la API pública de
-- pkg_entry_template y pkg_journal_entry, y borra todo al final.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_company_id     company.id%TYPE;
    v_user_id        user_account.id%TYPE;
    v_period_id      accounting_period.id%TYPE;

    v_acc_cash       gl_account.id%TYPE;
    v_acc_expense1   gl_account.id%TYPE;
    v_acc_expense2   gl_account.id%TYPE;

    v_tpl_fixed        journal_entry_template.id%TYPE;
    v_tpl_variable_ok  journal_entry_template.id%TYPE;
    v_tpl_multi_var    journal_entry_template.id%TYPE;
    v_tpl_single_var   journal_entry_template.id%TYPE;
    v_tpl_empty        journal_entry_template.id%TYPE;
    v_tpl_partial      journal_entry_template.id%TYPE;
    v_tpl_inactive     journal_entry_template.id%TYPE;

    v_entry_id       journal_entry.id%TYPE;

    PROCEDURE report(p_case IN VARCHAR2, p_passed IN BOOLEAN, p_detail IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CASE WHEN p_passed THEN '[PASS] ' ELSE '[FAIL] ' END
                              || p_case || CASE WHEN p_detail IS NOT NULL THEN ' -- ' || p_detail END);
    END;

BEGIN
    ------------------------------------------------------------------
    -- FIXTURES
    ------------------------------------------------------------------
    INSERT INTO company (name) VALUES ('Empresa de Prueba - test_pkg_entry_template')
        RETURNING id INTO v_company_id;

    INSERT INTO user_account (company_id, username, full_name, password_hash, password_salt)
        VALUES (v_company_id, 'test_user_et_' || v_company_id, 'Usuario de Prueba', RPAD('x',64,'x'), RPAD('y',32,'y'))
        RETURNING id INTO v_user_id;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'Período de prueba', DATE '2026-01-01', DATE '2026-12-31', 'OPEN')
        RETURNING id INTO v_period_id;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account, is_current)
        VALUES (v_company_id, 'TEST-CASH-ET', 'Caja (prueba)', 'D', 'ASSET', 'Y', 'Y')
        RETURNING id INTO v_acc_cash;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-EXP1-ET', 'Gasto 1 (prueba)', 'D', 'EXPENSE', 'Y')
        RETURNING id INTO v_acc_expense1;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-EXP2-ET', 'Gasto 2 (prueba)', 'D', 'EXPENSE', 'Y')
        RETURNING id INTO v_acc_expense2;

    -- plantilla 100% de montos fijos: Debe Gasto1 100 / Haber Caja 100
    INSERT INTO journal_entry_template (company_id, code, name)
        VALUES (v_company_id, 'TPL-FIXED', 'Plantilla monto fijo (prueba)')
        RETURNING id INTO v_tpl_fixed;
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_fixed, v_acc_expense1, 'D', 100);
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_fixed, v_acc_cash, 'C', 100);

    -- plantilla con las 2 líneas variables (caso soportado: mismo monto
    -- de los dos lados) -- Debe Gasto1 (variable) / Haber Caja (variable)
    INSERT INTO journal_entry_template (company_id, code, name)
        VALUES (v_company_id, 'TPL-VAR-OK', 'Plantilla monto variable simétrico (prueba)')
        RETURNING id INTO v_tpl_variable_ok;
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_variable_ok, v_acc_expense1, 'D', NULL);
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_variable_ok, v_acc_cash, 'C', NULL);

    -- plantilla con DOS líneas variables del MISMO lado (Debe Gasto1,
    -- Debe Gasto2) + una fija (Haber Caja) -- para confirmar la
    -- limitación documentada: ambas variables reciben el MISMO monto.
    INSERT INTO journal_entry_template (company_id, code, name)
        VALUES (v_company_id, 'TPL-MULTI-VAR', 'Plantilla con 2 líneas variables del mismo lado (prueba)')
        RETURNING id INTO v_tpl_multi_var;
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_multi_var, v_acc_expense1, 'D', NULL);
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_multi_var, v_acc_expense2, 'D', NULL);
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_multi_var, v_acc_cash, 'C', 200);

    -- plantilla de una sola línea, variable -- para probar -20062 de
    -- forma limpia (sin ambigüedad de estado parcial)
    INSERT INTO journal_entry_template (company_id, code, name)
        VALUES (v_company_id, 'TPL-SINGLE-VAR', 'Plantilla de una sola línea variable (prueba)')
        RETURNING id INTO v_tpl_single_var;
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_single_var, v_acc_expense1, 'D', NULL);

    -- plantilla sin ninguna línea
    INSERT INTO journal_entry_template (company_id, code, name)
        VALUES (v_company_id, 'TPL-EMPTY', 'Plantilla sin líneas (prueba)')
        RETURNING id INTO v_tpl_empty;

    -- plantilla con una línea fija (primero) y una variable (segundo)
    -- -- para confirmar que un fallo a mitad de camino deja el DRAFT
    -- con líneas parciales si el caller no hace ROLLBACK
    INSERT INTO journal_entry_template (company_id, code, name)
        VALUES (v_company_id, 'TPL-PARTIAL', 'Plantilla fija+variable (prueba)')
        RETURNING id INTO v_tpl_partial;
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_partial, v_acc_expense1, 'D', 50);
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_partial, v_acc_cash, 'C', NULL);

    -- plantilla inactiva
    INSERT INTO journal_entry_template (company_id, code, name, is_active)
        VALUES (v_company_id, 'TPL-INACTIVE', 'Plantilla inactiva (prueba)', 'N')
        RETURNING id INTO v_tpl_inactive;
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_inactive, v_acc_expense1, 'D', 10);
    INSERT INTO journal_entry_template_line (template_id, account_id, movement_type, fixed_amount)
        VALUES (v_tpl_inactive, v_acc_cash, 'C', 10);

    COMMIT;

    ------------------------------------------------------------------
    -- ESCENARIO 1: create_from_template con plantilla inexistente
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_entry_template.create_from_template(-999999, v_period_id, DATE '2026-05-01', v_user_id);
        report('Escenario 1: rechazar plantilla inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 1: rechazar plantilla inexistente', SQLCODE = -20060, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 2: create_from_template con plantilla inactiva
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_entry_template.create_from_template(v_tpl_inactive, v_period_id, DATE '2026-05-01', v_user_id);
        report('Escenario 2: rechazar plantilla inactiva', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 2: rechazar plantilla inactiva', SQLCODE = -20061, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 3: línea variable sin p_variable_amount
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_entry_template.create_from_template(v_tpl_single_var, v_period_id, DATE '2026-05-01', v_user_id);
        report('Escenario 3: rechazar plantilla variable sin p_variable_amount', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 3: rechazar plantilla variable sin p_variable_amount', SQLCODE = -20062, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 4: instanciar plantilla 100% de montos fijos
    ------------------------------------------------------------------
    DECLARE
        v_amt_d journal_entry_line.amount%TYPE;
        v_amt_c journal_entry_line.amount%TYPE;
        v_status journal_entry.status%TYPE;
    BEGIN
        v_entry_id := pkg_entry_template.create_from_template(v_tpl_fixed, v_period_id, DATE '2026-05-02', v_user_id);
        COMMIT;

        SELECT amount INTO v_amt_d FROM journal_entry_line WHERE journal_entry_id = v_entry_id AND account_id = v_acc_expense1;
        SELECT amount INTO v_amt_c FROM journal_entry_line WHERE journal_entry_id = v_entry_id AND account_id = v_acc_cash;

        pkg_journal_entry.post_entry(v_entry_id);
        COMMIT;

        SELECT status INTO v_status FROM journal_entry WHERE id = v_entry_id;

        report('Escenario 4: instanciar y postear plantilla de montos fijos',
               v_amt_d = 100 AND v_amt_c = 100 AND v_status = 'ACTIVE',
               'debe=' || v_amt_d || ' haber=' || v_amt_c || ' status=' || v_status);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 4: instanciar y postear plantilla de montos fijos', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 5: instanciar plantilla con 2 líneas variables
    -- simétricas (mismo monto en Debe y Haber)
    ------------------------------------------------------------------
    DECLARE
        v_amt_d journal_entry_line.amount%TYPE;
        v_amt_c journal_entry_line.amount%TYPE;
    BEGIN
        v_entry_id := pkg_entry_template.create_from_template(
            v_tpl_variable_ok, v_period_id, DATE '2026-05-03', v_user_id, p_variable_amount => 250);
        COMMIT;

        SELECT amount INTO v_amt_d FROM journal_entry_line WHERE journal_entry_id = v_entry_id AND account_id = v_acc_expense1;
        SELECT amount INTO v_amt_c FROM journal_entry_line WHERE journal_entry_id = v_entry_id AND account_id = v_acc_cash;

        report('Escenario 5: instanciar plantilla de monto variable simétrico', v_amt_d = 250 AND v_amt_c = 250,
               'debe=' || v_amt_d || ' haber=' || v_amt_c);

        -- posteamos para no dejar el DRAFT huérfano (entry_number NULL)
        -- -- ver HALLAZGO en test_pkg_journal_entry.sql sobre por qué
        -- dos DRAFT sin postear de la misma empresa no pueden coexistir.
        pkg_journal_entry.post_entry(v_entry_id);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5: instanciar plantilla de monto variable simétrico', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- REGRESIÓN (antes "Hallazgo G", ya corregido -- ver
    -- test/HALLAZGOS.md hallazgo medio #14): una plantilla con 2 líneas
    -- variables del MISMO lado (Debe Gasto1, Debe Gasto2) ahora se
    -- rechaza con -20065 en vez de asignarles el mismo monto en
    -- silencio. El caso soportado (1 variable en Debe + 1 en Haber,
    -- plantilla simétrica) sigue funcionando -- ver Escenario 5.
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_entry_template.create_from_template(
            v_tpl_multi_var, v_period_id, DATE '2026-05-04', v_user_id, p_variable_amount => 100);
        report('Regresión: 2 líneas variables del mismo lado se rechazan', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Regresión: 2 líneas variables del mismo lado se rechazan', SQLCODE = -20065, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- REGRESIÓN (antes "Hallazgo H", ya corregido -- ver
    -- test/HALLAZGOS.md hallazgo medio #15): una plantilla sin líneas
    -- ahora se rechaza con -20064 en create_from_template, en vez de
    -- crear un DRAFT vacío que recién fallaba al postear.
    ------------------------------------------------------------------
    BEGIN
        v_entry_id := pkg_entry_template.create_from_template(v_tpl_empty, v_period_id, DATE '2026-05-05', v_user_id);
        report('Regresión: plantilla sin líneas se rechaza en create_from_template', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Regresión: plantilla sin líneas se rechaza en create_from_template',
                   SQLCODE = -20064, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO I: fallo a mitad de la instanciación (línea fija ya
    -- insertada + línea variable sin monto) -- sin ROLLBACK explícito
    -- del caller, el DRAFT con líneas parciales queda persistido.
    ------------------------------------------------------------------
    DECLARE
        v_partial_entry journal_entry.id%TYPE;
        v_line_count     NUMBER;
        v_confirmado     BOOLEAN := FALSE;
    BEGIN
        v_entry_id := pkg_entry_template.create_from_template(
            p_template_id => v_tpl_partial,
            p_period_id   => v_period_id,
            p_entry_date  => DATE '2026-05-06',
            p_created_by  => v_user_id,
            p_description => 'Hallazgo I: instanciación parcial');
        report('Hallazgo I: fallo a mitad de plantilla sin monto variable', FALSE, 'no lanzó excepción -- se esperaba -20062');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20062 THEN
                -- A propósito NO hacemos ROLLBACK todavía: queremos
                -- confirmar que el DRAFT con la línea fija ya insertada
                -- sigue ahí mientras el caller no decida deshacerlo.
                BEGIN
                    SELECT id INTO v_partial_entry FROM journal_entry
                     WHERE company_id = v_company_id AND period_id = v_period_id
                       AND description = 'Hallazgo I: instanciación parcial'
                       AND status = 'DRAFT';
                    SELECT COUNT(*) INTO v_line_count FROM journal_entry_line WHERE journal_entry_id = v_partial_entry;
                    v_confirmado := (v_line_count = 1);
                EXCEPTION
                    WHEN OTHERS THEN
                        v_confirmado := FALSE;
                        v_line_count := -1;
                END;

                report('Hallazgo I: sin ROLLBACK del caller, un fallo a mitad de plantilla deja un DRAFT con líneas parciales',
                       v_confirmado, 'líneas encontradas en el DRAFT parcial=' || v_line_count);
                ROLLBACK;  -- limpieza, recién ahora
            ELSE
                report('Hallazgo I: fallo a mitad de plantilla sin monto variable', FALSE, SQLERRM);
                ROLLBACK;
            END IF;
    END;

    ------------------------------------------------------------------
    -- LIMPIEZA
    ------------------------------------------------------------------
    DELETE FROM journal_entry_line WHERE journal_entry_id IN
        (SELECT id FROM journal_entry WHERE company_id = v_company_id);
    UPDATE journal_entry SET reverses_entry_id = NULL WHERE company_id = v_company_id;
    DELETE FROM journal_entry WHERE company_id = v_company_id;
    DELETE FROM journal_entry_template_line WHERE template_id IN
        (SELECT id FROM journal_entry_template WHERE company_id = v_company_id);
    DELETE FROM journal_entry_template WHERE company_id = v_company_id;
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
