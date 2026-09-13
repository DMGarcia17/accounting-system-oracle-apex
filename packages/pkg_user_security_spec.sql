-- ============================================================
-- packages/pkg_user_security_spec.sql
-- Depende de: 19_role_permission.sql
--
-- API pública para todo lo relacionado a usuarios, roles y
-- permisos. Igual que con los asientos: ningún frontend hace
-- INSERT/UPDATE directo sobre user_account/user_role/role_permission.
--
-- authenticate() está pensada para conectarse DIRECTO como la
-- función de un esquema de autenticación personalizado en APEX
-- (tipo "PL/SQL Function Returning Boolean").
--
-- has_permission() está pensada para usarse en esquemas de
-- autorización de APEX, para decidir qué página/botón mostrar.
-- ============================================================

CREATE OR REPLACE PACKAGE pkg_user_security AS

    -- Crea un usuario nuevo, hasheando el password (SHA-256 + sal
    -- aleatoria). Devuelve el id nuevo.
    FUNCTION create_user(
        p_company_id  IN user_account.company_id%TYPE,
        p_username    IN user_account.username%TYPE,
        p_full_name   IN user_account.full_name%TYPE,
        p_email       IN user_account.email%TYPE,
        p_password    IN VARCHAR2
    ) RETURN user_account.id%TYPE;

    -- Cambio de password hecho por el propio usuario: exige el
    -- password viejo correcto antes de aceptar el nuevo.
    PROCEDURE change_password(
        p_user_id      IN user_account.id%TYPE,
        p_old_password IN VARCHAR2,
        p_new_password IN VARCHAR2
    );

    -- Reseteo administrativo: un ADMIN_EMPRESA lo fuerza sin
    -- necesitar el password viejo.
    PROCEDURE reset_password(
        p_user_id      IN user_account.id%TYPE,
        p_new_password IN VARCHAR2
    );

    -- Valida usuario+password. Devuelve FALSE tanto si el usuario
    -- no existe, como si está inactivo, como si el password no
    -- coincide -- nunca revela CUÁL de los tres pasó, por seguridad.
    -- Actualiza last_login_at y hace COMMIT internamente (es la
    -- única función del paquete que lo hace, ver nota en el body).
    FUNCTION authenticate(
        p_username IN user_account.username%TYPE,
        p_password IN VARCHAR2
    ) RETURN BOOLEAN;

    -- Activar / desactivar un usuario (acción administrativa).
    PROCEDURE deactivate_user(p_user_id IN user_account.id%TYPE);
    PROCEDURE reactivate_user(p_user_id IN user_account.id%TYPE);

    -- Asignar / quitar un rol a un usuario.
    PROCEDURE assign_role(p_user_id IN user_account.id%TYPE, p_role_id IN role.id%TYPE);
    PROCEDURE revoke_role(p_user_id IN user_account.id%TYPE, p_role_id IN role.id%TYPE);

    -- Asignar / quitar un permiso a un ROL (no a un usuario directo).
    PROCEDURE grant_permission(p_role_id IN role.id%TYPE, p_permission_id IN permission.id%TYPE);
    PROCEDURE revoke_permission(p_role_id IN role.id%TYPE, p_permission_id IN permission.id%TYPE);

    -- ¿El usuario tiene (a través de alguno de sus roles) el
    -- permiso indicado? Para usar en esquemas de autorización de APEX.
    FUNCTION has_permission(
        p_user_id        IN user_account.id%TYPE,
        p_permission_code IN permission.code%TYPE
    ) RETURN BOOLEAN;

    -- Resuelve username -> user_id/company_id y los guarda en items
    -- de sesión de APEX (G_USER_ID, G_COMPANY_ID).
    PROCEDURE set_session_context(p_username IN user_account.username%TYPE);

    -- CORRECCIÓN: el campo "Post-Authentication Procedure Name" de APEX
    -- valida el valor con DBMS_ASSERT antes de ejecutarlo, y solo acepta
    -- un nombre cualificado simple (paquete.procedimiento) -- NO permite
    -- pasarle parámetros entre paréntesis como se documentó originalmente
    -- (ORA-44004 al loguearse). Por eso este wrapper sin parámetros, que
    -- lee el usuario ya autenticado con V('APP_USER') y es el que
    -- realmente hay que configurar ahí:
    --   pkg_user_security.post_authentication_hook
    PROCEDURE post_authentication_hook;

END pkg_user_security;
/
