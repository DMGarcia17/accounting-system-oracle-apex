-- ============================================================
-- packages/pkg_period_close_spec.sql
-- Depende de: pkg_journal_entry (lo reutiliza para postear),
--             15_vw_inventory_balance.sql, 11_vw_account_balance.sql
--
-- Este paquete NO recibe cuentas "hardcodeadas" (ni "Compras" ni
-- "Inventarios" tienen un id fijo) porque el sistema es multi-empresa
-- y cada una arma su propio catálogo -- por eso los ids de cuenta se
-- pasan como parámetro en cada llamada.
-- ============================================================

CREATE OR REPLACE PACKAGE pkg_period_close AS

    -- Cierre real de un período: postea el asiento que reduce Compras
    -- por el inventario final (dejándolo convertido en Costo de Ventas),
    -- cancela todas las cuentas de resultado (REVENUE/COST/EXPENSE) con
    -- movimiento en el período, traslada la utilidad o pérdida neta a
    -- la cuenta de patrimonio indicada, y bloquea el período (CLOSED).
    -- Es irreversible en el sentido de que el período queda cerrado --
    -- los asientos en sí se podrían reversar como cualquier otro con
    -- pkg_journal_entry.reverse_entry, pero el período no se reabre acá.
    PROCEDURE close_period(
        p_period_id                     IN accounting_period.id%TYPE,
        p_ending_inventory_value        IN NUMBER,
        p_inventory_account_id          IN gl_account.id%TYPE,
        p_purchases_account_id          IN gl_account.id%TYPE,
        p_retained_earnings_account_id  IN gl_account.id%TYPE,
        p_created_by                    IN user_account.id%TYPE
    );

    -- Apertura de un período: busca el período CERRADO inmediatamente
    -- anterior de la misma empresa, toma su saldo final de Inventarios,
    -- y postea el asiento que lo traslada a Compras (Debe Compras /
    -- Haber Inventarios). Si no hay un período anterior cerrado (primer
    -- ejercicio de la empresa), lanza una excepción -- ese caso se
    -- resuelve con un asiento manual de aporte inicial vía
    -- pkg_journal_entry, no con este procedimiento.
    PROCEDURE open_period(
        p_period_id             IN accounting_period.id%TYPE,
        p_inventory_account_id  IN gl_account.id%TYPE,
        p_purchases_account_id  IN gl_account.id%TYPE,
        p_created_by            IN user_account.id%TYPE
    );

    -- Vista previa SIN POSTEAR NADA: estima la utilidad/pérdida del
    -- período usando el saldo actual de Compras/Ventas/Gastos y el
    -- inventario TEÓRICO calculado por el Kardex en este momento
    -- (vw_inventory_balance), en vez del inventario final real (que
    -- solo existe al momento del cierre formal).
    FUNCTION estimate_period_result(
        p_period_id             IN accounting_period.id%TYPE,
        p_purchases_account_id  IN gl_account.id%TYPE
    ) RETURN NUMBER;

END pkg_period_close;
/
