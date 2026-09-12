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
        v_line_count  NUMBER;
        v_var_count   NUMBER;
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

        -- CORRECCIÓN (ver test/HALLAZGOS.md, hallazgo medio #15): antes,
        -- una plantilla sin líneas creaba un DRAFT vacío que recién
        -- fallaba al postear, con un error genérico de pkg_journal_entry
        -- que no menciona la plantilla. Se valida acá, antes de crear
        -- el encabezado.
        SELECT COUNT(*) INTO v_line_count
          FROM journal_entry_template_line WHERE template_id = p_template_id;

        IF v_line_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20064, 'La plantilla "' || v_name || '" no tiene líneas configuradas.');
        END IF;

        -- CORRECCIÓN (ver test/HALLAZGOS.md, hallazgo medio #14): el caso
        -- soportado (TPL-VAR-OK) es 1 línea variable en Debe + 1 en Haber,
        -- ambas con el mismo p_variable_amount (plantilla simétrica). Lo
        -- que no tiene sentido -- y antes se aceptaba en silencio con un
        -- monto repetido incorrecto -- es 2+ líneas variables del MISMO
        -- lado (ej. dos Debe variables). Se valida por movement_type.
        SELECT COUNT(*) INTO v_var_count
          FROM (
              SELECT movement_type
                FROM journal_entry_template_line
               WHERE template_id = p_template_id AND fixed_amount IS NULL
               GROUP BY movement_type
              HAVING COUNT(*) > 1
          );

        IF v_var_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20065,
                'La plantilla "' || v_name || '" tiene 2 o más líneas de monto variable del mismo lado (Debe o Haber) -- ' ||
                'create_from_template solo admite un p_variable_amount único, que se aplica a lo sumo una vez por lado.');
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
