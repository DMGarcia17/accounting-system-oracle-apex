-- ============================================================
-- packages/pkg_inventory_body.sql
-- Depende de: pkg_inventory_spec.sql
-- ============================================================

CREATE OR REPLACE PACKAGE BODY pkg_inventory AS

    ------------------------------------------------------------
    -- Privada: valida que el artículo exista, esté activo, y sea
    -- de la empresa indicada. Devuelve nada, solo lanza excepción
    -- si algo no cumple.
    ------------------------------------------------------------
    PROCEDURE validate_item(p_company_id IN inventory_item.company_id%TYPE, p_item_id IN inventory_item.id%TYPE) IS
        v_company inventory_item.company_id%TYPE;
        v_active  inventory_item.is_active%TYPE;
    BEGIN
        BEGIN
            SELECT company_id, is_active INTO v_company, v_active
              FROM inventory_item WHERE id = p_item_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20050, 'No existe un artículo con id ' || p_item_id || '.');
        END;

        IF v_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20051, 'El artículo pertenece a otra empresa.');
        END IF;

        IF v_active <> 'Y' THEN
            RAISE_APPLICATION_ERROR(-20052, 'El artículo está inactivo.');
        END IF;
    END validate_item;


    ------------------------------------------------------------
    -- Privada: existencia y costo promedio actual del artículo
    -- (antes de aplicar el movimiento que se esté por registrar).
    -- Lanza excepción si p_quantity pedida excede lo disponible.
    ------------------------------------------------------------
    PROCEDURE get_average_cost(
        p_company_id  IN inventory_item.company_id%TYPE,
        p_item_id     IN inventory_item.id%TYPE,
        p_quantity    IN NUMBER,
        p_unit_cost   OUT NUMBER
    ) IS
        v_qty_on_hand NUMBER;
        v_value       NUMBER;
    BEGIN
        BEGIN
            SELECT NVL(quantity_on_hand, 0), NVL(inventory_value, 0)
              INTO v_qty_on_hand, v_value
              FROM vw_inventory_balance
             WHERE company_id = p_company_id AND item_id = p_item_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_qty_on_hand := 0;
                v_value := 0;
        END;

        IF p_quantity > v_qty_on_hand THEN
            RAISE_APPLICATION_ERROR(-20056,
                'No hay existencia suficiente: se pidieron ' || p_quantity ||
                ' y solo hay ' || v_qty_on_hand || '.');
        END IF;

        p_unit_cost := v_value / v_qty_on_hand;
    END get_average_cost;


    ------------------------------------------------------------
    FUNCTION record_opening_balance(
        p_company_id    IN inventory_item.company_id%TYPE,
        p_item_id       IN inventory_item.id%TYPE,
        p_quantity      IN NUMBER,
        p_unit_cost     IN NUMBER,
        p_movement_date IN DATE
    ) RETURN inventory_movement.id%TYPE
    IS
        v_existing NUMBER;
        v_new_id   inventory_movement.id%TYPE;
    BEGIN
        validate_item(p_company_id, p_item_id);

        IF p_quantity <= 0 THEN
            RAISE_APPLICATION_ERROR(-20053, 'La cantidad debe ser mayor a cero.');
        END IF;

        SELECT COUNT(*) INTO v_existing FROM inventory_movement WHERE item_id = p_item_id;
        IF v_existing > 0 THEN
            RAISE_APPLICATION_ERROR(-20054,
                'El artículo ya tiene movimientos registrados. record_opening_balance solo se usa una vez, ' ||
                'para la carga inicial -- para compras normales usá record_purchase.');
        END IF;

        INSERT INTO inventory_movement (company_id, item_id, movement_date, movement_type, quantity, unit_cost, description)
        VALUES (p_company_id, p_item_id, p_movement_date, 'OPENING_BALANCE', p_quantity, p_unit_cost, 'Carga inicial de existencia')
        RETURNING id INTO v_new_id;

        RETURN v_new_id;
    END record_opening_balance;


    ------------------------------------------------------------
    FUNCTION record_purchase(
        p_company_id       IN inventory_item.company_id%TYPE,
        p_item_id          IN inventory_item.id%TYPE,
        p_quantity         IN NUMBER,
        p_unit_cost        IN NUMBER,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE
    IS
        v_new_id inventory_movement.id%TYPE;
    BEGIN
        validate_item(p_company_id, p_item_id);

        IF p_quantity <= 0 THEN
            RAISE_APPLICATION_ERROR(-20053, 'La cantidad debe ser mayor a cero.');
        END IF;
        IF p_unit_cost < 0 THEN
            RAISE_APPLICATION_ERROR(-20055, 'El costo unitario no puede ser negativo.');
        END IF;

        INSERT INTO inventory_movement (company_id, item_id, journal_entry_id, movement_date, movement_type, quantity, unit_cost, description)
        VALUES (p_company_id, p_item_id, p_journal_entry_id, p_movement_date, 'PURCHASE', p_quantity, p_unit_cost, p_description)
        RETURNING id INTO v_new_id;

        RETURN v_new_id;
    END record_purchase;


    ------------------------------------------------------------
    FUNCTION record_sale(
        p_company_id       IN inventory_item.company_id%TYPE,
        p_item_id          IN inventory_item.id%TYPE,
        p_quantity         IN NUMBER,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE
    IS
        v_avg_cost NUMBER;
        v_new_id   inventory_movement.id%TYPE;
    BEGIN
        validate_item(p_company_id, p_item_id);

        IF p_quantity <= 0 THEN
            RAISE_APPLICATION_ERROR(-20053, 'La cantidad debe ser mayor a cero.');
        END IF;

        get_average_cost(p_company_id, p_item_id, p_quantity, v_avg_cost);

        INSERT INTO inventory_movement (company_id, item_id, journal_entry_id, movement_date, movement_type, quantity, unit_cost, description)
        VALUES (p_company_id, p_item_id, p_journal_entry_id, p_movement_date, 'SALE', p_quantity, v_avg_cost, p_description)
        RETURNING id INTO v_new_id;

        RETURN v_new_id;
    END record_sale;


    ------------------------------------------------------------
    FUNCTION record_purchase_return(
        p_company_id       IN inventory_item.company_id%TYPE,
        p_item_id          IN inventory_item.id%TYPE,
        p_quantity         IN NUMBER,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE
    IS
        v_avg_cost NUMBER;
        v_new_id   inventory_movement.id%TYPE;
    BEGIN
        validate_item(p_company_id, p_item_id);

        IF p_quantity <= 0 THEN
            RAISE_APPLICATION_ERROR(-20053, 'La cantidad debe ser mayor a cero.');
        END IF;

        get_average_cost(p_company_id, p_item_id, p_quantity, v_avg_cost);

        INSERT INTO inventory_movement (company_id, item_id, journal_entry_id, movement_date, movement_type, quantity, unit_cost, description)
        VALUES (p_company_id, p_item_id, p_journal_entry_id, p_movement_date, 'PURCHASE_RETURN', p_quantity, v_avg_cost, p_description)
        RETURNING id INTO v_new_id;

        RETURN v_new_id;
    END record_purchase_return;


    ------------------------------------------------------------
    FUNCTION record_sales_return(
        p_company_id       IN inventory_item.company_id%TYPE,
        p_item_id          IN inventory_item.id%TYPE,
        p_quantity         IN NUMBER,
        p_unit_cost        IN NUMBER,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE
    IS
        v_new_id inventory_movement.id%TYPE;
    BEGIN
        validate_item(p_company_id, p_item_id);

        IF p_quantity <= 0 THEN
            RAISE_APPLICATION_ERROR(-20053, 'La cantidad debe ser mayor a cero.');
        END IF;
        IF p_unit_cost < 0 THEN
            RAISE_APPLICATION_ERROR(-20055, 'El costo unitario no puede ser negativo.');
        END IF;

        INSERT INTO inventory_movement (company_id, item_id, journal_entry_id, movement_date, movement_type, quantity, unit_cost, description)
        VALUES (p_company_id, p_item_id, p_journal_entry_id, p_movement_date, 'SALES_RETURN', p_quantity, p_unit_cost, p_description)
        RETURNING id INTO v_new_id;

        RETURN v_new_id;
    END record_sales_return;


    ------------------------------------------------------------
    FUNCTION record_closing_count(
        p_company_id    IN inventory_item.company_id%TYPE,
        p_item_id       IN inventory_item.id%TYPE,
        p_quantity      IN NUMBER,
        p_unit_cost     IN NUMBER,
        p_movement_date IN DATE
    ) RETURN inventory_movement.id%TYPE
    IS
        v_new_id inventory_movement.id%TYPE;
    BEGIN
        validate_item(p_company_id, p_item_id);

        IF p_quantity < 0 THEN
            RAISE_APPLICATION_ERROR(-20053, 'La cantidad no puede ser negativa.');
        END IF;

        INSERT INTO inventory_movement (company_id, item_id, movement_date, movement_type, quantity, unit_cost, description)
        VALUES (p_company_id, p_item_id, p_movement_date, 'CLOSING_BALANCE', p_quantity, p_unit_cost, 'Conteo físico de cierre')
        RETURNING id INTO v_new_id;

        RETURN v_new_id;
    END record_closing_count;


    ------------------------------------------------------------
    FUNCTION reverse_movement(
        p_movement_id      IN inventory_movement.id%TYPE,
        p_movement_date    IN DATE,
        p_journal_entry_id IN journal_entry.id%TYPE DEFAULT NULL
    ) RETURN inventory_movement.id%TYPE
    IS
        v_company_id     inventory_movement.company_id%TYPE;
        v_item_id        inventory_movement.item_id%TYPE;
        v_quantity       inventory_movement.quantity%TYPE;
        v_unit_cost      inventory_movement.unit_cost%TYPE;
        v_movement_type  inventory_movement.movement_type%TYPE;
        v_reverse_type   inventory_movement.movement_type%TYPE;
        v_current_qty    NUMBER;
        v_new_id         inventory_movement.id%TYPE;
        v_already_rev    NUMBER;
    BEGIN
        BEGIN
            SELECT company_id, item_id, quantity, unit_cost, movement_type
              INTO v_company_id, v_item_id, v_quantity, v_unit_cost, v_movement_type
              FROM inventory_movement
             WHERE id = p_movement_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20057, 'No existe un movimiento con id ' || p_movement_id || '.');
        END;

        -- CORRECCIÓN (ver test/HALLAZGOS.md, hallazgo alto #7): sin este
        -- chequeo, reversar el mismo movimiento dos veces generaba dos
        -- movimientos contrarios en vez de uno. -20063 queda fuera del
        -- rango original de este paquete (-20050 a -20059, ya completo)
        -- porque se agregó después.
        SELECT COUNT(*) INTO v_already_rev
          FROM inventory_movement
         WHERE reverses_movement_id = p_movement_id;

        IF v_already_rev > 0 THEN
            RAISE_APPLICATION_ERROR(-20063, 'El movimiento ' || p_movement_id || ' ya fue reversado anteriormente.');
        END IF;

        v_reverse_type := CASE v_movement_type
            WHEN 'PURCHASE'        THEN 'PURCHASE_RETURN'
            WHEN 'SALE'            THEN 'SALES_RETURN'
            WHEN 'PURCHASE_RETURN' THEN 'PURCHASE'
            WHEN 'SALES_RETURN'    THEN 'SALE'
            ELSE NULL
        END;

        IF v_reverse_type IS NULL THEN
            RAISE_APPLICATION_ERROR(-20058,
                'Solo se pueden reversar movimientos PURCHASE, SALE, PURCHASE_RETURN o SALES_RETURN.');
        END IF;

        -- Si el reverso RESTA existencia (reversar una entrada), hay que
        -- confirmar que todavía alcance -- pudo haberse vendido parte
        -- de esa mercadería después del movimiento original.
        IF v_reverse_type IN ('PURCHASE_RETURN', 'SALE') THEN
            SELECT NVL(quantity_on_hand, 0) INTO v_current_qty
              FROM vw_inventory_balance
             WHERE company_id = v_company_id AND item_id = v_item_id;

            IF v_quantity > v_current_qty THEN
                RAISE_APPLICATION_ERROR(-20059,
                    'No se puede reversar: ya no hay existencia suficiente (' || v_current_qty ||
                    ') para restar ' || v_quantity || ' -- probablemente ya se vendió parte de esa mercadería.');
            END IF;
        END IF;

        INSERT INTO inventory_movement (company_id, item_id, journal_entry_id, movement_date, movement_type, quantity, unit_cost, description, reverses_movement_id)
        VALUES (v_company_id, v_item_id, p_journal_entry_id, p_movement_date, v_reverse_type, v_quantity, v_unit_cost,
                'Reverso del movimiento ' || p_movement_id, p_movement_id)
        RETURNING id INTO v_new_id;

        RETURN v_new_id;
    END reverse_movement;

END pkg_inventory;
/
