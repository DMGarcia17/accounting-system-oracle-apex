-- ============================================================
-- packages/pkg_entry_template_body.sql
-- Depende de: pkg_entry_template_spec.sql
-- ============================================================

CREATE OR REPLACE PACKAGE BODY pkg_entry_template AS

    FUNCTION create_from_template(
        p_template_id      IN journal_entry_template.id%TYPE,
        p_period_id        IN accounting_period.id%TYPE,
        p_entry_date       IN DATE,
        p_created_by       IN user_account.id%TYPE,
        p_variable_amount  IN NUMBER DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN journal_entry.id%TYPE
    IS
        v_company_id  journal_entry_template.company_id%TYPE;
        v_entry_type  journal_entry_template.entry_type%TYPE;
        v_name        journal_entry_template.name%TYPE;
        v_is_active   journal_entry_template.is_active%TYPE;
        v_new_entry   journal_entry.id%TYPE;
        v_amount      NUMBER;
    BEGIN
        BEGIN
            SELECT company_id, entry_type, name, is_active
              INTO v_company_id, v_entry_type, v_name, v_is_active
              FROM journal_entry_template
             WHERE id = p_template_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20060, 'No existe una plantilla con id ' || p_template_id || '.');
        END;

        IF v_is_active <> 'Y' THEN
            RAISE_APPLICATION_ERROR(-20061, 'La plantilla está inactiva.');
        END IF;

        v_new_entry := pkg_journal_entry.create_header(
            p_company_id  => v_company_id,
            p_period_id   => p_period_id,
            p_entry_date  => p_entry_date,
            p_description => NVL(p_description, v_name),
            p_created_by  => p_created_by,
            p_entry_type  => v_entry_type
        );

        FOR rec IN (
            SELECT account_id, movement_type, fixed_amount, description
              FROM journal_entry_template_line
             WHERE template_id = p_template_id
        ) LOOP
            v_amount := NVL(rec.fixed_amount, p_variable_amount);

            IF v_amount IS NULL THEN
                RAISE_APPLICATION_ERROR(-20062,
                    'La plantilla tiene una línea de monto variable, pero no se proporcionó p_variable_amount.');
            END IF;

            pkg_journal_entry.add_line(v_new_entry, rec.account_id, rec.movement_type, v_amount, rec.description);
        END LOOP;

        RETURN v_new_entry;
    END create_from_template;

END pkg_entry_template;
/
