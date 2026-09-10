-- ============================================================
-- packages/pkg_journal_entry_spec.sql
-- Depende de: 17_alter_journal_entry_reversal.sql
--
-- API pública para crear, completar, postear, descartar y anular
-- asientos contables. NINGÚN frontend (APEX, Angular, lo que sea)
-- debería hacer INSERT/UPDATE/DELETE directo sobre journal_entry
-- o journal_entry_line -- todo pasa por estas funciones, así la
-- lógica de negocio vive 100% en la base.
--
-- Flujo típico para crear un asiento manual:
--   1) v_id := create_header(...)
--   2) add_line(v_id, cuenta1, 'D', monto)
--      add_line(v_id, cuenta2, 'C', monto)
--   3) post_entry(v_id)
--   4) COMMIT (lo hace quien llama; el paquete nunca hace commit)
--
-- Para anular un asiento ya posteado:
--   v_reversal_id := reverse_entry(id_original, fecha_reverso, usuario)
--   COMMIT
--
-- Lectura de saldos/movimientos: NO va en este paquete. Se consulta
-- directo vw_account_balance / journal_entry_line -- son solo
-- lectura, sin reglas de negocio que proteger.
-- ============================================================

CREATE OR REPLACE PACKAGE pkg_journal_entry AS

    -- Crea el encabezado de un asiento en estado DRAFT. Valida que
    -- el período pertenezca a la empresa, esté ABIERTO, y que la
    -- fecha caiga dentro de su rango. Devuelve el id nuevo.
    FUNCTION create_header(
        p_company_id  IN journal_entry.company_id%TYPE,
        p_period_id   IN journal_entry.period_id%TYPE,
        p_entry_date  IN journal_entry.entry_date%TYPE,
        p_description IN journal_entry.description%TYPE,
        p_created_by  IN journal_entry.created_by%TYPE,
        p_entry_type  IN journal_entry.entry_type%TYPE DEFAULT 'MANUAL'
    ) RETURN journal_entry.id%TYPE;

    -- Agrega una línea a un asiento que sigue en DRAFT. Valida que
    -- la cuenta exista, sea de detalle, esté activa, y sea de la
    -- misma empresa del asiento.
    PROCEDURE add_line(
        p_entry_id      IN journal_entry_line.journal_entry_id%TYPE,
        p_account_id    IN journal_entry_line.account_id%TYPE,
        p_movement_type IN journal_entry_line.movement_type%TYPE,
        p_amount        IN journal_entry_line.amount%TYPE,
        p_description   IN journal_entry_line.description%TYPE DEFAULT NULL
    );

    -- Revalida período/cuadre con TODAS las líneas ya cargadas,
    -- asigna el correlativo, y pasa el asiento a ACTIVE.
    PROCEDURE post_entry(p_entry_id IN journal_entry.id%TYPE);

    -- Borra un asiento que sigue en DRAFT (encabezado + líneas).
    PROCEDURE discard_draft(p_entry_id IN journal_entry.id%TYPE);

    -- Anula un asiento ACTIVE: crea un asiento nuevo con las mismas
    -- cuentas y montos pero Debe/Haber invertidos, fechado dentro
    -- de un período ABIERTO, y marca el original como REVERSED.
    -- Devuelve el id del asiento de reverso.
    FUNCTION reverse_entry(
        p_entry_id      IN journal_entry.id%TYPE,
        p_reversal_date IN journal_entry.entry_date%TYPE,
        p_created_by    IN journal_entry.created_by%TYPE,
        p_description   IN journal_entry.description%TYPE DEFAULT NULL
    ) RETURN journal_entry.id%TYPE;

END pkg_journal_entry;
/
