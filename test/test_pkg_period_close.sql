-- ============================================================
-- tests/test_pkg_period_close.sql
-- Correr conectado como CONTA_SCHEMA.
-- Suite de regresión de pkg_period_close: crea sus propios datos de
-- prueba, corre varios escenarios usando SOLO la API pública de
-- pkg_period_close y pkg_journal_entry (nunca INSERT directo sobre
-- journal_entry/journal_entry_line), y borra todo al final.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_company_id        company.id%TYPE;
    v_user_id           user_account.id%TYPE;

    v_acc_cash          gl_account.id%TYPE;
    v_acc_inventory     gl_account.id%TYPE;
    v_acc_purchases     gl_account.id%TYPE;
    v_acc_sales         gl_account.id%TYPE;
    v_acc_expense       gl_account.id%TYPE;
    v_acc_retained      gl_account.id%TYPE;

    v_period_a          accounting_period.id%TYPE;  -- se cierra en Escenario 3b
    v_period_b          accounting_period.id%TYPE;  -- se abre en Escenario 6
    v_period_pre_closed accounting_period.id%TYPE;  -- forzado a CLOSED por fixture
    v_period_first      accounting_period.id%TYPE;  -- sin período anterior cerrado
    v_period_wrongtype  accounting_period.id%TYPE;  -- Hallazgo E
    v_period_anomaly    accounting_period.id%TYPE;  -- Hallazgo F

    v_entry_id          journal_entry.id%TYPE;

    PROCEDURE report(p_case IN VARCHAR2, p_passed IN BOOLEAN, p_detail IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CASE WHEN p_passed THEN '[PASS] ' ELSE '[FAIL] ' END
                              || p_case || CASE WHEN p_detail IS NOT NULL THEN ' -- ' || p_detail END);
    END;

BEGIN
    ------------------------------------------------------------------
    -- FIXTURES
    ------------------------------------------------------------------
    INSERT INTO company (name) VALUES ('Empresa de Prueba - test_pkg_period_close')
        RETURNING id INTO v_company_id;

    INSERT INTO user_account (company_id, username, full_name, password_hash, password_salt)
        VALUES (v_company_id, 'test_user_pc_' || v_company_id, 'Usuario de Prueba', RPAD('x',64,'x'), RPAD('y',32,'y'))
        RETURNING id INTO v_user_id;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-CASH-PC', 'Caja (prueba)', 'D', 'ASSET', 'Y')
        RETURNING id INTO v_acc_cash;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-INV-PC', 'Inventarios (prueba)', 'D', 'ASSET', 'Y')
        RETURNING id INTO v_acc_inventory;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-PUR-PC', 'Compras (prueba)', 'D', 'COST', 'Y')
        RETURNING id INTO v_acc_purchases;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-SALES-PC', 'Ventas (prueba)', 'C', 'REVENUE', 'Y')
        RETURNING id INTO v_acc_sales;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-EXP-PC', 'Gastos de operación (prueba)', 'D', 'EXPENSE', 'Y')
        RETURNING id INTO v_acc_expense;

    INSERT INTO gl_account (company_id, code, name, normal_balance, account_type, is_posting_account)
        VALUES (v_company_id, 'TEST-RE-PC', 'Resultados Acumulados (prueba)', 'C', 'EQUITY', 'Y')
        RETURNING id INTO v_acc_retained;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'Período A (a cerrar)', DATE '2026-01-01', DATE '2026-03-31', 'OPEN')
        RETURNING id INTO v_period_a;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'Período B (a abrir)', DATE '2026-04-01', DATE '2026-06-30', 'OPEN')
        RETURNING id INTO v_period_b;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'Período ya cerrado (fixture)', DATE '2026-07-01', DATE '2026-09-30', 'OPEN')
        RETURNING id INTO v_period_pre_closed;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'Período sin anterior cerrado', DATE '2020-01-01', DATE '2020-03-31', 'OPEN')
        RETURNING id INTO v_period_first;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'Período Hallazgo E (cuenta incorrecta)', DATE '2027-01-01', DATE '2027-03-31', 'OPEN')
        RETURNING id INTO v_period_wrongtype;

    INSERT INTO accounting_period (company_id, name, start_date, end_date, status)
        VALUES (v_company_id, 'Período Hallazgo F (saldo contrario)', DATE '2027-04-01', DATE '2027-06-30', 'OPEN')
        RETURNING id INTO v_period_anomaly;

    UPDATE accounting_period SET status = 'CLOSED', closed_at = SYSDATE WHERE id = v_period_pre_closed;

    COMMIT;

    ------------------------------------------------------------------
    -- ESCENARIO 1: close_period con período inexistente
    ------------------------------------------------------------------
    BEGIN
        pkg_period_close.close_period(-999999, 100, v_acc_inventory, v_acc_purchases, v_acc_retained, v_user_id);
        report('Escenario 1: rechazar close_period sobre período inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 1: rechazar close_period sobre período inexistente', SQLCODE = -20040, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 2: close_period sobre un período ya cerrado
    ------------------------------------------------------------------
    BEGIN
        pkg_period_close.close_period(v_period_pre_closed, 100, v_acc_inventory, v_acc_purchases, v_acc_retained, v_user_id);
        report('Escenario 2: rechazar close_period sobre período ya cerrado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 2: rechazar close_period sobre período ya cerrado', SQLCODE = -20041, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 3a/3b: ciclo completo sobre el Período A
    --   - Compra: Debe Compras 500 / Haber Caja 500
    --   - Venta:  Debe Caja 800 / Haber Ventas 800
    --   - Gasto:  Debe Gastos 100 / Haber Caja 100
    --   3a) estimate_period_result ANTES de cerrar (sin datos de Kardex,
    --       el inventario teórico es 0): 800 - (500-0) - 100 = 200
    --   3b) close_period con inventario final REAL = 200: COGS =
    --       500-200=300, resultado neto = 800-300-100 = 400 (ganancia)
    ------------------------------------------------------------------
    DECLARE
        v_estimate NUMBER;
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(v_company_id, v_period_a, DATE '2026-02-01', 'Compra del período', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_purchases, 'D', 500);
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash, 'C', 500);
        pkg_journal_entry.post_entry(v_entry_id);

        v_entry_id := pkg_journal_entry.create_header(v_company_id, v_period_a, DATE '2026-02-05', 'Venta del período', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash, 'D', 800);
        pkg_journal_entry.add_line(v_entry_id, v_acc_sales, 'C', 800);
        pkg_journal_entry.post_entry(v_entry_id);

        v_entry_id := pkg_journal_entry.create_header(v_company_id, v_period_a, DATE '2026-02-10', 'Gasto del período', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_expense, 'D', 100);
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash, 'C', 100);
        pkg_journal_entry.post_entry(v_entry_id);

        COMMIT;

        -- HALLAZGO CRÍTICO (ver HALLAZGOS.md): mv_account_balances está
        -- declarada REFRESH FAST ON COMMIT, pero empíricamente NO se
        -- refresca sola al hacer COMMIT en esta base -- queda vacía/
        -- desactualizada hasta que alguien llama DBMS_MVIEW.REFRESH a
        -- mano. Lo forzamos acá para poder seguir probando el resto de
        -- la lógica de pkg_period_close (que si depende de la vista).
        DBMS_MVIEW.REFRESH('MV_ACCOUNT_BALANCES', 'C');

        v_estimate := pkg_period_close.estimate_period_result(v_period_a, v_acc_purchases);
        report('Escenario 3a: estimate_period_result antes del cierre', v_estimate = 200, 'estimado=' || v_estimate);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 3a: estimate_period_result antes del cierre', FALSE, SQLERRM);
            ROLLBACK;
    END;

    DECLARE
        v_status         accounting_period.status%TYPE;
        v_bal_purchases  NUMBER;
        v_bal_sales      NUMBER;
        v_bal_expense    NUMBER;
        v_bal_retained   NUMBER;
        v_bal_inventory  NUMBER;
    BEGIN
        pkg_period_close.close_period(v_period_a, 200, v_acc_inventory, v_acc_purchases, v_acc_retained, v_user_id);
        COMMIT;

        -- workaround del mismo hallazgo: refrescar a mano antes de leer vw_account_balance
        DBMS_MVIEW.REFRESH('MV_ACCOUNT_BALANCES', 'C');

        SELECT status INTO v_status FROM accounting_period WHERE id = v_period_a;
        SELECT NVL(period_balance,0) INTO v_bal_purchases FROM vw_account_balance WHERE period_id = v_period_a AND account_id = v_acc_purchases;
        SELECT NVL(period_balance,0) INTO v_bal_sales     FROM vw_account_balance WHERE period_id = v_period_a AND account_id = v_acc_sales;
        SELECT NVL(period_balance,0) INTO v_bal_expense   FROM vw_account_balance WHERE period_id = v_period_a AND account_id = v_acc_expense;
        SELECT NVL(period_balance,0) INTO v_bal_retained  FROM vw_account_balance WHERE period_id = v_period_a AND account_id = v_acc_retained;
        SELECT NVL(period_balance,0) INTO v_bal_inventory FROM vw_account_balance WHERE period_id = v_period_a AND account_id = v_acc_inventory;

        report('Escenario 3b: close_period cierra el período y cancela cuentas de resultado',
               v_status = 'CLOSED' AND v_bal_purchases = 0 AND v_bal_sales = 0 AND v_bal_expense = 0
               AND v_bal_retained = 400 AND v_bal_inventory = 200,
               'status=' || v_status || ' compras=' || v_bal_purchases || ' ventas=' || v_bal_sales ||
               ' gastos=' || v_bal_expense || ' resultados=' || v_bal_retained || ' inventario=' || v_bal_inventory);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 3b: close_period cierra el período y cancela cuentas de resultado', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 4: open_period con período inexistente
    ------------------------------------------------------------------
    BEGIN
        pkg_period_close.open_period(-999999, v_acc_inventory, v_acc_purchases, v_user_id);
        report('Escenario 4: rechazar open_period sobre período inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 4: rechazar open_period sobre período inexistente', SQLCODE = -20040, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 5: open_period sin período anterior cerrado
    ------------------------------------------------------------------
    BEGIN
        pkg_period_close.open_period(v_period_first, v_acc_inventory, v_acc_purchases, v_user_id);
        report('Escenario 5: rechazar open_period sin período anterior cerrado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5: rechazar open_period sin período anterior cerrado', SQLCODE = -20042, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 6: open_period hereda el inventario del Período A
    -- (ya cerrado en el Escenario 3b con saldo de Inventarios = 200)
    ------------------------------------------------------------------
    DECLARE
        v_new_entry   journal_entry.id%TYPE;
        v_entry_type  journal_entry.entry_type%TYPE;
        v_status      journal_entry.status%TYPE;
        v_deb_amount  journal_entry_line.amount%TYPE;
        v_cred_amount journal_entry_line.amount%TYPE;
    BEGIN
        -- workaround del mismo hallazgo: open_period lee vw_account_balance
        -- para heredar el inventario del período anterior cerrado
        DBMS_MVIEW.REFRESH('MV_ACCOUNT_BALANCES', 'C');

        pkg_period_close.open_period(v_period_b, v_acc_inventory, v_acc_purchases, v_user_id);
        COMMIT;

        SELECT id, entry_type, status INTO v_new_entry, v_entry_type, v_status
          FROM journal_entry
         WHERE company_id = v_company_id AND period_id = v_period_b AND entry_type = 'OPENING';

        SELECT amount INTO v_deb_amount FROM journal_entry_line
         WHERE journal_entry_id = v_new_entry AND account_id = v_acc_purchases AND movement_type = 'D';
        SELECT amount INTO v_cred_amount FROM journal_entry_line
         WHERE journal_entry_id = v_new_entry AND account_id = v_acc_inventory AND movement_type = 'C';

        report('Escenario 6: open_period hereda el inventario del período anterior cerrado',
               v_status = 'ACTIVE' AND v_deb_amount = 200 AND v_cred_amount = 200,
               'status=' || v_status || ' debe_compras=' || v_deb_amount || ' haber_inventario=' || v_cred_amount);
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 6: open_period hereda el inventario del período anterior cerrado', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 7: estimate_period_result con período inexistente --
    -- NO tiene manejo de NO_DATA_FOUND (a diferencia del resto del
    -- sistema), así que se espera el error crudo de Oracle (SQLCODE=100),
    -- no un RAISE_APPLICATION_ERROR amigable.
    ------------------------------------------------------------------
    DECLARE
        v_dummy NUMBER;
    BEGIN
        v_dummy := pkg_period_close.estimate_period_result(-999999, v_acc_purchases);
        report('Escenario 7: estimate_period_result con período inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo: estimate_period_result con período inexistente propaga NO_DATA_FOUND crudo (sin RAISE_APPLICATION_ERROR)',
                   SQLCODE = 100, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO D: close_period no valida p_ending_inventory_value <= 0
    -- con un error propio -- pero como ese valor se usa como monto de
    -- línea en add_line, SÍ termina rechazado indirectamente por la
    -- validación genérica de add_line (monto debe ser > 0).
    ------------------------------------------------------------------
    BEGIN
        pkg_period_close.close_period(v_period_wrongtype, -100, v_acc_inventory, v_acc_purchases, v_acc_retained, v_user_id);
        report('Hallazgo D: close_period con p_ending_inventory_value negativo', FALSE, 'no lanzó excepción -- se aceptó un inventario final negativo');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo D: close_period no valida p_ending_inventory_value negativo con un error propio (lo rechaza vía add_line -20014)',
                   SQLCODE = -20014, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO E: close_period no valida que las cuentas recibidas
    -- correspondan al account_type esperado -- acá se le pasa una
    -- cuenta de GASTO (EXPENSE) como si fuera la cuenta de Inventarios,
    -- y no hay ninguna validación semántica que lo impida.
    ------------------------------------------------------------------
    DECLARE
        v_entry_close   journal_entry.id%TYPE;
        v_amount_used   journal_entry_line.amount%TYPE;
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(v_company_id, v_period_wrongtype, DATE '2027-02-01', 'Compra (Hallazgo E)', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_purchases, 'D', 200);
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash, 'C', 200);
        pkg_journal_entry.post_entry(v_entry_id);
        COMMIT;

        pkg_period_close.close_period(v_period_wrongtype, 50, v_acc_expense, v_acc_purchases, v_acc_retained, v_user_id);
        COMMIT;

        -- Se busca por entry_type + la línea sobre la cuenta EXPENSE en
        -- vez de por texto de descripción, para no depender de que el
        -- acento de "período" viaje byte a byte igual entre el cliente
        -- sqlplus y el literal compilado en el paquete.
        SELECT amount INTO v_amount_used
          FROM journal_entry_line l
          JOIN journal_entry e ON e.id = l.journal_entry_id
         WHERE e.company_id = v_company_id AND e.period_id = v_period_wrongtype
           AND e.entry_type = 'CLOSING' AND l.account_id = v_acc_expense AND l.movement_type = 'D';

        report('Hallazgo E: close_period acepta una cuenta EXPENSE como si fuera la cuenta de Inventarios (sin validar account_type)',
               v_amount_used = 50,
               'se contabilizó el "inventario final" en una cuenta de tipo EXPENSE sin ningún error');
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo E: close_period con cuenta de tipo incorrecto como inventario', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO F: cuando una cuenta de resultado termina el período
    -- con saldo neto en la dirección CONTRARIA a su normal_balance
    -- (ej. Ventas con más Debe que Haber -- una devolución sin ventas
    -- que la respalden en el mismo período), la línea de "cancelación"
    -- que arma close_period usa siempre la dirección contraria al
    -- normal_balance de la cuenta, SIN mirar el signo real del saldo
    -- -- así que en vez de cancelarlo, lo DUPLICA. Esto puede hacer
    -- que el asiento de cierre de resultados quede descuadrado
    -- (-20005 de pkg_journal_entry, no manejado por pkg_period_close)
    -- o que quede posteado pero con un saldo final incorrecto.
    ------------------------------------------------------------------
    DECLARE
        v_bal_sales_after NUMBER;
        v_bug_via_error   BOOLEAN := FALSE;
        v_bug_via_balance BOOLEAN := FALSE;
        v_detalle         VARCHAR2(400);
    BEGIN
        v_entry_id := pkg_journal_entry.create_header(
            v_company_id, v_period_anomaly, DATE '2027-05-01',
            'Devolución sobre venta sin venta previa en el período (Hallazgo F)', v_user_id);
        pkg_journal_entry.add_line(v_entry_id, v_acc_sales, 'D', 300);   -- anómalo: Ventas recibe un DEBE
        pkg_journal_entry.add_line(v_entry_id, v_acc_cash, 'C', 300);
        pkg_journal_entry.post_entry(v_entry_id);
        COMMIT;

        BEGIN
            pkg_period_close.close_period(v_period_anomaly, 10, v_acc_inventory, v_acc_purchases, v_acc_retained, v_user_id);
            COMMIT;

            SELECT NVL(period_balance,0) INTO v_bal_sales_after
              FROM vw_account_balance WHERE period_id = v_period_anomaly AND account_id = v_acc_sales;

            IF v_bal_sales_after <> 0 THEN
                v_bug_via_balance := TRUE;
                v_detalle := 'close_period terminó SIN error, pero el saldo de Ventas del período quedó en '
                             || v_bal_sales_after || ' en vez de 0 (la "cancelación" duplicó el desbalance)';
            ELSE
                v_detalle := 'close_period terminó sin error y el saldo de Ventas quedó en 0 -- no se pudo reproducir el hallazgo con este dataset';
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                v_bug_via_error := TRUE;
                v_detalle := 'close_period lanzó una excepción no manejada al intentar cuadrar el asiento de cierre: '
                             || SQLERRM || ' (SQLCODE=' || SQLCODE || ')';
                ROLLBACK;
        END;

        report('Hallazgo F: cancelación de cuentas de resultado con saldo contrario a su normal_balance',
               v_bug_via_error OR v_bug_via_balance, v_detalle);
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo F: cancelación de cuentas de resultado con saldo contrario a su normal_balance', FALSE, SQLERRM);
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
