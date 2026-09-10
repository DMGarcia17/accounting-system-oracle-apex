-- ============================================================
-- packages/pkg_entry_template_spec.sql
-- Depende de: 21_journal_entry_template_line.sql, pkg_journal_entry
-- ============================================================

CREATE OR REPLACE PACKAGE pkg_entry_template AS

    -- Crea un asiento en DRAFT a partir de una plantilla, copiando
    -- sus líneas (con fixed_amount, o con p_variable_amount para
    -- las que tengan fixed_amount NULL). Devuelve el id del asiento
    -- nuevo -- sigue en DRAFT, el caller decide cuándo hacer
    -- pkg_journal_entry.post_entry(...) sobre él.
    FUNCTION create_from_template(
        p_template_id      IN journal_entry_template.id%TYPE,
        p_period_id        IN accounting_period.id%TYPE,
        p_entry_date       IN DATE,
        p_created_by       IN user_account.id%TYPE,
        p_variable_amount  IN NUMBER DEFAULT NULL,
        p_description      IN VARCHAR2 DEFAULT NULL
    ) RETURN journal_entry.id%TYPE;

END pkg_entry_template;
/
