-- ============================================================
-- packages/pkg_journal_entry_body.sql
-- Depende de: pkg_journal_entry_spec.sql
-- ============================================================

CREATE OR REPLACE PACKAGE BODY pkg_journal_entry AS

    ------------------------------------------------------------
    FUNCTION create_header(
        p_company_id  IN journal_entry.company_id%TYPE,
        p_period_id   IN journal_entry.period_id%TYPE,
        p_entry_date  IN journal_entry.entry_date%TYPE,
        p_description IN journal_entry.description%TYPE,
        p_created_by  IN journal_entry.created_by%TYPE,
        p_entry_type  IN journal_entry.entry_type%TYPE DEFAULT 'MANUAL'
    ) RETURN journal_entry.id%TYPE
    IS
        v_period_company   accounting_period.company_id%TYPE;
        v_period_status    accounting_period.status%TYPE;
        v_period_start     accounting_period.start_date%TYPE;
        v_period_end       accounting_period.end_date%TYPE;
        v_new_id           journal_entry.id%TYPE;
    BEGIN
        BEGIN
            SELECT company_id, status, start_date, end_date
              INTO v_period_company, v_period_status, v_period_start, v_period_end
              FROM accounting_period
             WHERE id = p_period_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20010, 'No existe un período con id ' || p_period_id || '.');
        END;

        IF v_period_company <> p_company_id THEN
            RAISE_APPLICATION_ERROR(-20011, 'El período no pertenece a la empresa indicada.');
        END IF;

        IF v_period_status <> 'OPEN' THEN
            RAISE_APPLICATION_ERROR(-20002, 'El período contable está cerrado.');
        END IF;

        IF p_entry_date NOT BETWEEN v_period_start AND v_period_end THEN
            RAISE_APPLICATION_ERROR(-20003, 'La fecha del asiento está fuera del rango del período contable.');
        END IF;

        INSERT INTO journal_entry (company_id, period_id, entry_date, description, entry_type, created_by)
        VALUES (p_company_id, p_period_id, p_entry_date, p_description, p_entry_type, p_created_by)
        RETURNING id INTO v_new_id;

        RETURN v_new_id;
    END create_header;


    ------------------------------------------------------------
    PROCEDURE add_line(
        p_entry_id      IN journal_entry_line.journal_entry_id%TYPE,
        p_account_id    IN journal_entry_line.account_id%TYPE,
        p_movement_type IN journal_entry_line.movement_type%TYPE,
        p_amount        IN journal_entry_line.amount%TYPE,
        p_description   IN journal_entry_line.description%TYPE DEFAULT NULL
    )
    IS
        v_entry_company     journal_entry.company_id%TYPE;
        v_entry_status      journal_entry.status%TYPE;
        v_account_company   gl_account.company_id%TYPE;
        v_is_posting        gl_account.is_posting_account%TYPE;
        v_is_active         gl_account.is_active%TYPE;
    BEGIN
        BEGIN
            SELECT company_id, status INTO v_entry_company, v_entry_status
              FROM journal_entry
             WHERE id = p_entry_id
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20008, 'No existe un asiento con id ' || p_entry_id || '.');
        END;

        IF v_entry_status <> 'DRAFT' THEN
            RAISE_APPLICATION_ERROR(-20012,
                'No se pueden agregar líneas a un asiento que ya fue posteado o reversado.');
        END IF;

        IF p_movement_type NOT IN ('D','C') THEN
            RAISE_APPLICATION_ERROR(-20013, 'Tipo de movimiento inválido, debe ser D (Debe) o C (Haber).');
        END IF;

        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20014, 'El monto de la línea debe ser mayor a cero.');
        END IF;

        BEGIN
            SELECT company_id, is_posting_account, is_active
              INTO v_account_company, v_is_posting, v_is_active
              FROM gl_account
             WHERE id = p_account_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20015, 'No existe una cuenta con id ' || p_account_id || '.');
        END;

        IF v_account_company <> v_entry_company THEN
            RAISE_APPLICATION_ERROR(-20016, 'La cuenta pertenece a otra empresa distinta a la del asiento.');
        END IF;

        IF v_is_posting <> 'Y' THEN
            RAISE_APPLICATION_ERROR(-20017, 'No se puede contabilizar en una cuenta de agrupación (no es de detalle).');
        END IF;

        IF v_is_active <> 'Y' THEN
            RAISE_APPLICATION_ERROR(-20018, 'La cuenta está inactiva.');
        END IF;

        INSERT INTO journal_entry_line (journal_entry_id, account_id, movement_type, amount, description)
        VALUES (p_entry_id, p_account_id, p_movement_type, p_amount, p_description);
    END add_line;


    ------------------------------------------------------------
    PROCEDURE post_entry(p_entry_id IN journal_entry.id%TYPE)
    IS
        v_company_id        journal_entry.company_id%TYPE;
        v_period_id         journal_entry.period_id%TYPE;
        v_entry_date        journal_entry.entry_date%TYPE;
        v_status            journal_entry.status%TYPE;
        v_period_status     accounting_period.status%TYPE;
        v_period_start      accounting_period.start_date%TYPE;
        v_period_end        accounting_period.end_date%TYPE;
        v_line_count        NUMBER;
        v_total_debit       NUMBER;
        v_total_credit      NUMBER;
        v_invalid_accounts  NUMBER;
        v_next_number       NUMBER;
        v_lock_dummy        company.id%TYPE;
    BEGIN
        BEGIN
            SELECT company_id, period_id, entry_date, status
              INTO v_company_id, v_period_id, v_entry_date, v_status
              FROM journal_entry
             WHERE id = p_entry_id
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20008, 'No existe un asiento con id ' || p_entry_id || '.');
        END;

        IF v_status <> 'DRAFT' THEN
            RAISE_APPLICATION_ERROR(-20001, 'El asiento ' || p_entry_id || ' ya fue posteado o reversado.');
        END IF;

        -- Se revalida el período por si cambió de estado entre que se
        -- creó el encabezado y este momento (defensa en profundidad).
        SELECT status, start_date, end_date
          INTO v_period_status, v_period_start, v_period_end
          FROM accounting_period
         WHERE id = v_period_id;

        IF v_period_status <> 'OPEN' THEN
            RAISE_APPLICATION_ERROR(-20002, 'El período contable está cerrado.');
        END IF;

        IF v_entry_date NOT BETWEEN v_period_start AND v_period_end THEN
            RAISE_APPLICATION_ERROR(-20003, 'La fecha del asiento está fuera del rango del período contable.');
        END IF;

        SELECT COUNT(*),
               NVL(SUM(CASE WHEN movement_type = 'D' THEN amount END), 0),
               NVL(SUM(CASE WHEN movement_type = 'C' THEN amount END), 0)
          INTO v_line_count, v_total_debit, v_total_credit
          FROM journal_entry_line
         WHERE journal_entry_id = p_entry_id;

        IF v_line_count < 2 THEN
            RAISE_APPLICATION_ERROR(-20004, 'El asiento necesita al menos dos líneas (Debe y Haber).');
        END IF;

        IF v_total_debit <> v_total_credit THEN
            RAISE_APPLICATION_ERROR(-20005,
                'El asiento no cuadra: Debe (' || v_total_debit || ') distinto de Haber (' || v_total_credit || ').');
        END IF;

        -- Defensa en profundidad: por si alguna cuenta se desactivó
        -- entre que se agregó la línea (add_line) y este momento.
        SELECT COUNT(*)
          INTO v_invalid_accounts
          FROM journal_entry_line l
          JOIN gl_account a ON a.id = l.account_id
         WHERE l.journal_entry_id = p_entry_id
           AND (a.company_id <> v_company_id
                OR a.is_posting_account <> 'Y'
                OR a.is_active <> 'Y');

        IF v_invalid_accounts > 0 THEN
            RAISE_APPLICATION_ERROR(-20006,
                'El asiento usa una cuenta que no es de detalle, está inactiva, o es de otra empresa.');
        END IF;

        SELECT id INTO v_lock_dummy FROM company WHERE id = v_company_id FOR UPDATE;

        SELECT NVL(MAX(entry_number), 0) + 1
          INTO v_next_number
          FROM journal_entry
         WHERE company_id = v_company_id;

        UPDATE journal_entry
           SET entry_number = v_next_number,
               status       = 'ACTIVE'
         WHERE id = p_entry_id;
    END post_entry;


    ------------------------------------------------------------
    PROCEDURE discard_draft(p_entry_id IN journal_entry.id%TYPE)
    IS
        v_status journal_entry.status%TYPE;
    BEGIN
        BEGIN
            SELECT status INTO v_status
              FROM journal_entry
             WHERE id = p_entry_id
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20008, 'No existe un asiento con id ' || p_entry_id || '.');
        END;

        IF v_status <> 'DRAFT' THEN
            RAISE_APPLICATION_ERROR(-20007,
                'Solo se pueden descartar asientos en borrador. Este ya fue posteado o reversado.');
        END IF;

        -- CORRECCIÓN (ver test/HALLAZGOS.md, hallazgo alto #6): si un
        -- inventory_movement quedó vinculado a este DRAFT (Kardex ligado
        -- a un asiento aún no posteado), el DELETE de abajo revienta con
        -- un ORA-02292 crudo. Se valida antes y se traduce a un error de
        -- negocio propio.
        DECLARE
            v_linked_movements NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_linked_movements
              FROM inventory_movement
             WHERE journal_entry_id = p_entry_id;

            IF v_linked_movements > 0 THEN
                RAISE_APPLICATION_ERROR(-20009,
                    'No se puede descartar: tiene ' || v_linked_movements ||
                    ' movimiento(s) de inventario vinculado(s). Desvinculalos o eliminalos primero.');
            END IF;
        END;

        DELETE FROM journal_entry_line WHERE journal_entry_id = p_entry_id;
        DELETE FROM journal_entry WHERE id = p_entry_id;
    END discard_draft;


    ------------------------------------------------------------
    FUNCTION reverse_entry(
        p_entry_id      IN journal_entry.id%TYPE,
        p_reversal_date IN journal_entry.entry_date%TYPE,
        p_created_by    IN journal_entry.created_by%TYPE,
        p_description   IN journal_entry.description%TYPE DEFAULT NULL
    ) RETURN journal_entry.id%TYPE
    IS
        v_company_id     journal_entry.company_id%TYPE;
        v_orig_status    journal_entry.status%TYPE;
        v_new_period_id  accounting_period.id%TYPE;
        v_new_entry_id   journal_entry.id%TYPE;
        v_test  inventory_movement.id%TYPE;
    BEGIN
        BEGIN
            SELECT company_id, status INTO v_company_id, v_orig_status
              FROM journal_entry
             WHERE id = p_entry_id
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20008, 'No existe un asiento con id ' || p_entry_id || '.');
        END;

        IF v_orig_status <> 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20019,
                'Solo se pueden anular asientos ACTIVE. Este está en ' || v_orig_status || '.');
        END IF;

        BEGIN
            SELECT id INTO v_new_period_id
              FROM accounting_period
             WHERE company_id = v_company_id
               AND p_reversal_date BETWEEN start_date AND end_date
               AND status = 'OPEN';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20020,
                    'No hay un período abierto de esta empresa que cubra la fecha de reverso.');
        END;

        v_new_entry_id := create_header(
            p_company_id  => v_company_id,
            p_period_id   => v_new_period_id,
            p_entry_date  => p_reversal_date,
            p_description => NVL(p_description, 'Reverso del asiento ' || p_entry_id),
            p_created_by  => p_created_by,
            p_entry_type  => 'REVERSAL'
        );

        UPDATE journal_entry SET reverses_entry_id = p_entry_id WHERE id = v_new_entry_id;

        -- Copiar las líneas del original con Debe/Haber invertidos
        FOR rec IN (
            SELECT account_id, movement_type, amount, description
              FROM journal_entry_line
             WHERE journal_entry_id = p_entry_id
        ) LOOP
            add_line(
                p_entry_id      => v_new_entry_id,
                p_account_id    => rec.account_id,
                p_movement_type => CASE rec.movement_type WHEN 'D' THEN 'C' ELSE 'D' END,
                p_amount        => rec.amount,
                p_description   => rec.description
            );
        END LOOP;

        post_entry(v_new_entry_id);

        -- Reversar también cualquier movimiento de Kardex que haya
        -- quedado vinculado al asiento original (ej. si era una venta
        -- que afectó inventario). Si el asiento original no tenía
        -- movimientos de Kardex (por ejemplo, un asiento sin relación
        -- a inventario), este bucle simplemente no encuentra nada y
        -- no hace nada -- no rompe asientos que nunca tocaron el Kardex.
        FOR inv_rec IN (
            SELECT id FROM inventory_movement WHERE journal_entry_id = p_entry_id
        ) LOOP
            v_test:=pkg_inventory.reverse_movement(
                p_movement_id      => inv_rec.id,
                p_movement_date    => p_reversal_date,
                p_journal_entry_id => v_new_entry_id
            );
        END LOOP;

        UPDATE journal_entry SET status = 'REVERSED' WHERE id = p_entry_id;

        RETURN v_new_entry_id;
    END reverse_entry;

END pkg_journal_entry;
/
