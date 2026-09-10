-- ============================================================
-- packages/pkg_inventory_spec.sql
-- Depende de: 15_vw_inventory_balance.sql (corregida)
--
-- Registra movimientos de Kardex. Nadie hace INSERT directo sobre
-- inventory_movement -- todo pasa por acá, igual que con los asientos.
--
-- El costeo es Promedio Ponderado (ver README de db/ sobre el
-- método pendiente de confirmar): en cada salida (venta o
-- devolución sobre compra), el costo unitario se calcula al vuelo
-- como inventory_value / quantity_on_hand ANTES de esa salida.
-- ============================================================

CREATE OR REPLACE PACKAGE pkg_inventory AS

    -- Carga la existencia inicial de un artículo. Se usa UNA SOLA
    -- VEZ por artículo, al empezar a trackearlo en el sistema. Si
    -- el artículo ya tiene movimientos, lanza excepción (para una
    -- compra normal después de la carga inicial, usar record_purchase).
    FUNCTION record_opening_balance(
        p_company_id    IN inventory_item.company_id%TYPE,
        p_item_id       IN inventory_item.id%TYPE,
        p_quantity      IN NUMBER,
        p_unit_cost     IN NUMBER,
        p_movement_date IN DATE
    ) RETURN inventory_movement.id%TYPE;

    -- Registra una compra: entra mercadería al costo pagado.
    FUNCTION record_purchase(
        p_company_id       IN inventory_item.company_id%TYPE,
        p_item_id          IN inventory_item.id%TYPE,
        p_quantity         IN NUMBER,
        p_unit_cost        IN NUMBER,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE;

    -- Registra una venta: sale mercadería al costo promedio actual
    -- (calculado solo, no se pasa como parámetro). Valida que haya
    -- existencia suficiente.
    FUNCTION record_sale(
        p_company_id       IN inventory_item.company_id%TYPE,
        p_item_id          IN inventory_item.id%TYPE,
        p_quantity         IN NUMBER,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE;

    -- Devolución sobre compra: sale mercadería (se le devuelve al
    -- proveedor) al costo promedio actual, igual que una venta.
    FUNCTION record_purchase_return(
        p_company_id       IN inventory_item.company_id%TYPE,
        p_item_id          IN inventory_item.id%TYPE,
        p_quantity         IN NUMBER,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE;

    -- Devolución sobre venta: vuelve a entrar mercadería que un
    -- cliente devolvió. El costo unitario SÍ se pasa como parámetro
    -- (idealmente el mismo costo con el que se registró la venta
    -- original, para revertir el Costo de Ventas correctamente).
    FUNCTION record_sales_return(
        p_company_id       IN inventory_item.company_id%TYPE,
        p_item_id          IN inventory_item.id%TYPE,
        p_quantity         IN NUMBER,
        p_unit_cost        IN NUMBER,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE;

    -- Registra el conteo físico de cierre (solo referencia, no
    -- suma en vw_inventory_balance) -- para comparar contra el
    -- saldo teórico que el sistema calculó solo.
    FUNCTION record_closing_count(
        p_company_id    IN inventory_item.company_id%TYPE,
        p_item_id       IN inventory_item.id%TYPE,
        p_quantity      IN NUMBER,
        p_unit_cost     IN NUMBER,
        p_movement_date IN DATE
    ) RETURN inventory_movement.id%TYPE;

    -- Reversa un movimiento existente (PURCHASE/SALE/PURCHASE_RETURN/
    -- SALES_RETURN): crea el movimiento contrario con la MISMA
    -- cantidad y el MISMO costo unitario del original -- NO recalcula
    -- promedio, porque el objetivo es deshacer exactamente ese evento,
    -- no crear una transacción nueva independiente. Pensada para que
    -- pkg_journal_entry.reverse_entry la llame automáticamente cuando
    -- anula un asiento que tenía movimientos de Kardex vinculados.
    FUNCTION reverse_movement(
        p_movement_id      IN inventory_movement.id%TYPE,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE;

END pkg_inventory;
/
