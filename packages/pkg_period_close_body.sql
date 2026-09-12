-- ============================================================
-- packages/pkg_period_close_body.sql
-- Depende de: pkg_period_close_spec.sql
--
-- NOTA TÉCNICA IMPORTANTE: dentro de close_period, el cálculo del
-- resultado de cada cuenta de resultado se hace con una consulta
-- DIRECTA a journal_entry_line/journal_entry (no contra
-- vw_account_balance / mv_account_balances). Esto es a propósito:
-- la vista materializada solo se refresca al hacer COMMIT, y como
-- este paquete postea el asiento de inventario y NECESITA ver su
-- efecto reflejado antes de terminar de calcular el resultado --
-- todo dentro de la MISMA transacción, sin commits intermedios --
-- una consulta directa sí ve los cambios sin confirmar todavía,
-- mientras que la vista materializada NO los vería hasta el commit.
-- ============================================================

CREATE OR REPLACE PACKAGE BODY pkg_period_close AS

    ------------------------------------------------------------
    PROCEDURE close_period(
        p_period_id                     IN accounting_period.id%TYPE,
        p_ending_inventory_value        IN NUMBER,
        p_inventory_account_id          IN gl_account.id%TYPE,
        p_purchases_account_id          IN gl_account.id%TYPE,
        p_retained_earnings_account_id  IN gl_account.id%TYPE,
        p_created_by                    IN user_account.id%TYPE
    )
    IS
        v_company_id        accounting_period.company_id%TYPE;
        v_status            accounting_period.status%TYPE;
        v_end_date          accounting_period.end_date%TYPE;
        v_inventory_entry   journal_entry.id%TYPE;
        v_result_entry      journal_entry.id%TYPE;
        v_total_revenue     NUMBER := 0;
        v_total_cost_exp    NUMBER := 0;
        v_net_result        NUMBER;
        v_balance           NUMBER;
    BEGIN
        ------------------------------------------------------------
        -- 1) Bloquear y validar el período
        ------------------------------------------------------------
        BEGIN
            SELECT company_id, status, end_date
              INTO v_company_id, v_status, v_end_date
              FROM accounting_period
             WHERE id = p_period_id
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20040, 'No existe un período con id ' || p_period_id || '.');
        END;

        IF v_status <> 'OPEN' THEN
            RAISE_APPLICATION_ERROR(-20041, 'El período ya está cerrado.');
        END IF;

        ------------------------------------------------------------
        -- 2) Asiento de cierre de inventario: Debe Inventarios,
        --    Haber Compras -- esto es lo que convierte a Compras en
        --    Costo de Ventas (Inv. Inicial + Compras - Inv. Final).
        ------------------------------------------------------------
        v_inventory_entry := pkg_journal_entry.create_header(
            p_company_id  => v_company_id,
            p_period_id   => p_period_id,
            p_entry_date  => v_end_date,
            p_description => 'Cierre de inventario - período ' || p_period_id,
            p_created_by  => p_created_by,
            p_entry_type  => 'CLOSING'
        );
        pkg_journal_entry.add_line(v_inventory_entry, p_inventory_account_id, 'D', p_ending_inventory_value);
        pkg_journal_entry.add_line(v_inventory_entry, p_purchases_account_id, 'C', p_ending_inventory_value);
        pkg_journal_entry.post_entry(v_inventory_entry);

        ------------------------------------------------------------
        -- 3) Cancelar TODAS las cuentas de resultado (REVENUE/COST/
        --    EXPENSE) con movimiento en el período -- incluye el
        --    asiento recién posteado en el paso 2, porque esta
        --    consulta lee directo de journal_entry_line, no de la
        --    vista materializada (ver nota técnica arriba).
        ------------------------------------------------------------
        v_result_entry := pkg_journal_entry.create_header(
            p_company_id  => v_company_id,
            p_period_id   => p_period_id,
            p_entry_date  => v_end_date,
            p_description => 'Cierre de resultados - período ' || p_period_id,
            p_created_by  => p_created_by,
            p_entry_type  => 'CLOSING'
        );

        FOR rec IN (
            SELECT a.id, a.normal_balance, a.account_type,
                   NVL(SUM(CASE l.movement_type WHEN 'D' THEN l.amount ELSE 0 END), 0) AS total_debit,
                   NVL(SUM(CASE l.movement_type WHEN 'C' THEN l.amount ELSE 0 END), 0) AS total_credit
              FROM gl_account a
              JOIN journal_entry_line l ON l.account_id = a.id
              JOIN journal_entry e      ON e.id = l.journal_entry_id
             WHERE a.company_id = v_company_id
               AND a.account_type IN ('REVENUE','COST','EXPENSE')
               AND e.period_id = p_period_id
               AND e.status = 'ACTIVE'
             GROUP BY a.id, a.normal_balance, a.account_type
        ) LOOP
            v_balance := CASE rec.normal_balance
                            WHEN 'D' THEN rec.total_debit - rec.total_credit
                            ELSE          rec.total_credit - rec.total_debit
                         END;

            -- CORRECCIÓN (ver test/HALLAZGOS.md #3): la cancelación NO puede
            -- asumir siempre la dirección contraria a normal_balance -- eso
            -- solo cancela bien cuando la cuenta terminó el período con
            -- saldo en su dirección "normal". Si terminó con saldo neto
            -- contrario (ej. una cuenta de Ventas con más Debe que Haber),
            -- esa suposición REFUERZA el desbalance en vez de anularlo
            -- (confirmado con una reproducción real: Debe 590 vs Haber 10).
            -- La cancelación correcta se decide con el saldo real en bruto
            -- (Debe vs Haber), sin pasar por normal_balance: lo que sobra
            -- en Debe se cancela con Haber, y viceversa, cualquiera sea el
            -- tipo de cuenta.
            IF rec.total_debit > rec.total_credit THEN
                pkg_journal_entry.add_line(
                    v_result_entry, rec.id, 'C', rec.total_debit - rec.total_credit
                );
            ELSIF rec.total_credit > rec.total_debit THEN
                pkg_journal_entry.add_line(
                    v_result_entry, rec.id, 'D', rec.total_credit - rec.total_debit
                );
            END IF;

            IF v_balance <> 0 THEN
                IF rec.account_type = 'REVENUE' THEN
                    v_total_revenue  := v_total_revenue + v_balance;
                ELSE
                    v_total_cost_exp := v_total_cost_exp + v_balance;
                END IF;
            END IF;
        END LOOP;

        v_net_result := v_total_revenue - v_total_cost_exp;

        IF v_net_result > 0 THEN
            pkg_journal_entry.add_line(v_result_entry, p_retained_earnings_account_id, 'C', v_net_result);
        ELSIF v_net_result < 0 THEN
            pkg_journal_entry.add_line(v_result_entry, p_retained_earnings_account_id, 'D', ABS(v_net_result));
        END IF;
        -- si v_net_result = 0, las líneas de cancelación ya cuadran solas, no hace falta línea extra

        pkg_journal_entry.post_entry(v_result_entry);

        ------------------------------------------------------------
        -- 4) Bloquear el período
        ------------------------------------------------------------
        UPDATE accounting_period
           SET status = 'CLOSED', closed_at = SYSDATE
         WHERE id = p_period_id;
    END close_period;


    ------------------------------------------------------------
    PROCEDURE open_period(
        p_period_id             IN accounting_period.id%TYPE,
        p_inventory_account_id  IN gl_account.id%TYPE,
        p_purchases_account_id IN gl_account.id%TYPE,
        p_created_by            IN user_account.id%TYPE
    )
    IS
        v_company_id      accounting_period.company_id%TYPE;
        v_start_date      accounting_period.start_date%TYPE;
        v_prior_period_id accounting_period.id%TYPE;
        v_beginning_inv   NUMBER;
        v_opening_entry   journal_entry.id%TYPE;
    BEGIN
        BEGIN
            SELECT company_id, start_date INTO v_company_id, v_start_date
              FROM accounting_period WHERE id = p_period_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20040, 'No existe un período con id ' || p_period_id || '.');
        END;

        BEGIN
            SELECT id INTO v_prior_period_id
              FROM accounting_period
             WHERE company_id = v_company_id
               AND status = 'CLOSED'
               AND end_date < v_start_date
             ORDER BY end_date DESC
             FETCH FIRST 1 ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20042,
                    'No hay un período anterior cerrado del cual heredar el inventario inicial. ' ||
                    'Si es el primer ejercicio de la empresa, contabilizá el aporte inicial ' ||
                    'manualmente con pkg_journal_entry, no con open_period.');
        END;

        -- El período anterior ya está CERRADO (y su cierre ya hizo commit
        -- en su momento, en una llamada separada), así que acá sí es
        -- seguro leer vw_account_balance sin el problema de staleness
        -- que tenemos dentro de close_period.
        SELECT NVL(accumulated_balance, 0)
          INTO v_beginning_inv
          FROM vw_account_balance
         WHERE period_id = v_prior_period_id
           AND account_id = p_inventory_account_id;

        v_opening_entry := pkg_journal_entry.create_header(
            p_company_id  => v_company_id,
            p_period_id   => p_period_id,
            p_entry_date  => v_start_date,
            p_description => 'Apertura de ejercicio - período ' || p_period_id,
            p_created_by  => p_created_by,
            p_entry_type  => 'OPENING'
        );
        pkg_journal_entry.add_line(v_opening_entry, p_purchases_account_id, 'D', v_beginning_inv);
        pkg_journal_entry.add_line(v_opening_entry, p_inventory_account_id, 'C', v_beginning_inv);
        pkg_journal_entry.post_entry(v_opening_entry);
    END open_period;


    ------------------------------------------------------------
    FUNCTION estimate_period_result(
        p_period_id             IN accounting_period.id%TYPE,
        p_purchases_account_id  IN gl_account.id%TYPE
    ) RETURN NUMBER
    IS
        v_company_id            accounting_period.company_id%TYPE;
        v_purchases_balance     NUMBER;
        v_theoretical_inventory NUMBER;
        v_estimated_cogs        NUMBER;
        v_revenue_balance       NUMBER;
        v_expense_balance       NUMBER;
    BEGIN
        SELECT company_id INTO v_company_id FROM accounting_period WHERE id = p_period_id;

        SELECT NVL(period_balance, 0) INTO v_purchases_balance
          FROM vw_account_balance
         WHERE period_id = p_period_id AND account_id = p_purchases_account_id;

        SELECT NVL(SUM(inventory_value), 0) INTO v_theoretical_inventory
          FROM vw_inventory_balance
         WHERE company_id = v_company_id;

        v_estimated_cogs := v_purchases_balance - v_theoretical_inventory;

        SELECT NVL(SUM(b.period_balance), 0) INTO v_revenue_balance
          FROM vw_account_balance b
          JOIN gl_account a ON a.id = b.account_id
         WHERE b.period_id = p_period_id AND a.account_type = 'REVENUE';

        SELECT NVL(SUM(b.period_balance), 0) INTO v_expense_balance
          FROM vw_account_balance b
          JOIN gl_account a ON a.id = b.account_id
         WHERE b.period_id = p_period_id AND a.account_type = 'EXPENSE';

        RETURN v_revenue_balance - v_estimated_cogs - v_expense_balance;
    END estimate_period_result;

END pkg_period_close;
/
