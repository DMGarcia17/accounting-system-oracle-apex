-- ============================================================
-- packages/pkg_user_security_body.sql
-- Depende de: pkg_user_security_spec.sql
-- ============================================================

CREATE OR REPLACE PACKAGE BODY pkg_user_security AS

    ------------------------------------------------------------
    -- Función privada: calcula el hash SHA-256 de password+sal,
    -- en hexadecimal (64 caracteres), para que coincida con el
    -- tamaño de la columna password_hash.
    ------------------------------------------------------------
    FUNCTION hash_password(p_password IN VARCHAR2, p_salt IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN RAWTOHEX(STANDARD_HASH(p_password || p_salt, 'SHA256'));
    END hash_password;


    ------------------------------------------------------------
    FUNCTION create_user(
        p_company_id  IN user_account.company_id%TYPE,
        p_username    IN user_account.username%TYPE,
        p_full_name   IN user_account.full_name%TYPE,
        p_email       IN user_account.email%TYPE,
        p_password    IN VARCHAR2
    ) RETURN user_account.id%TYPE
    IS
        v_salt   VARCHAR2(32);
        v_hash   VARCHAR2(64);
        v_new_id user_account.id%TYPE;
    BEGIN
        v_salt := RAWTOHEX(SYS_GUID());  -- 16 bytes -> 32 caracteres hex
        v_hash := hash_password(p_password, v_salt);

        BEGIN
            INSERT INTO user_account (company_id, username, full_name, email, password_hash, password_salt)
            VALUES (p_company_id, p_username, p_full_name, p_email, v_hash, v_salt)
            RETURNING id INTO v_new_id;
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                RAISE_APPLICATION_ERROR(-20030, 'Ya existe un usuario con el username "' || p_username || '".');
        END;

        RETURN v_new_id;
    END create_user;


    ------------------------------------------------------------
    PROCEDURE change_password(
        p_user_id      IN user_account.id%TYPE,
        p_old_password IN VARCHAR2,
        p_new_password IN VARCHAR2
    )
    IS
        v_current_hash user_account.password_hash%TYPE;
        v_salt         user_account.password_salt%TYPE;
        v_new_salt     VARCHAR2(32);
    BEGIN
        BEGIN
            SELECT password_hash, password_salt INTO v_current_hash, v_salt
              FROM user_account WHERE id = p_user_id FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20031, 'No existe un usuario con id ' || p_user_id || '.');
        END;

        IF hash_password(p_old_password, v_salt) <> v_current_hash THEN
            RAISE_APPLICATION_ERROR(-20032, 'El password actual no es correcto.');
        END IF;

        v_new_salt := RAWTOHEX(SYS_GUID());
        UPDATE user_account
           SET password_hash = hash_password(p_new_password, v_new_salt),
               password_salt = v_new_salt
         WHERE id = p_user_id;
    END change_password;


    ------------------------------------------------------------
    PROCEDURE reset_password(
        p_user_id      IN user_account.id%TYPE,
        p_new_password IN VARCHAR2
    )
    IS
        v_new_salt VARCHAR2(32);
        v_exists   NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_exists FROM user_account WHERE id = p_user_id;
        IF v_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20031, 'No existe un usuario con id ' || p_user_id || '.');
        END IF;

        v_new_salt := RAWTOHEX(SYS_GUID());
        UPDATE user_account
           SET password_hash = hash_password(p_new_password, v_new_salt),
               password_salt = v_new_salt
         WHERE id = p_user_id;
    END reset_password;


    ------------------------------------------------------------
    -- NOTA: esta es la ÚNICA función del paquete que hace COMMIT
    -- por su cuenta. Se justifica porque authenticate() la llama
    -- directo el esquema de autenticación de APEX en cada login --
    -- no hay un "caller" con transacción de negocio propia que vaya
    -- a decidir cuándo confirmar. Actualizar last_login_at es una
    -- bitácora, no una operación de negocio que deba poder revertirse.
    ------------------------------------------------------------
    FUNCTION authenticate(
        p_username IN user_account.username%TYPE,
        p_password IN VARCHAR2
    ) RETURN BOOLEAN
    IS
        v_id       user_account.id%TYPE;
        v_hash     user_account.password_hash%TYPE;
        v_salt     user_account.password_salt%TYPE;
        v_active   user_account.is_active%TYPE;
    BEGIN
        BEGIN
            SELECT id, password_hash, password_salt, is_active
              INTO v_id, v_hash, v_salt, v_active
              FROM user_account
             WHERE username = p_username;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN FALSE;  -- no revelar si el usuario existe o no
        END;

        IF v_active <> 'Y' THEN
            RETURN FALSE;
        END IF;

        IF hash_password(p_password, v_salt) = v_hash THEN
            UPDATE user_account SET last_login_at = SYSDATE WHERE id = v_id;
            COMMIT;
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    END authenticate;


    ------------------------------------------------------------
    PROCEDURE deactivate_user(p_user_id IN user_account.id%TYPE) IS
        v_exists NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_exists FROM user_account WHERE id = p_user_id;
        IF v_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20031, 'No existe un usuario con id ' || p_user_id || '.');
        END IF;
        UPDATE user_account SET is_active = 'N' WHERE id = p_user_id;
    END deactivate_user;

    PROCEDURE reactivate_user(p_user_id IN user_account.id%TYPE) IS
        v_exists NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_exists FROM user_account WHERE id = p_user_id;
        IF v_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20031, 'No existe un usuario con id ' || p_user_id || '.');
        END IF;
        UPDATE user_account SET is_active = 'Y' WHERE id = p_user_id;
    END reactivate_user;


    ------------------------------------------------------------
    PROCEDURE assign_role(p_user_id IN user_account.id%TYPE, p_role_id IN role.id%TYPE) IS
    BEGIN
        BEGIN
            INSERT INTO user_role (user_id, role_id) VALUES (p_user_id, p_role_id);
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                RAISE_APPLICATION_ERROR(-20033, 'El usuario ya tiene asignado ese rol.');
        END;
    END assign_role;

    PROCEDURE revoke_role(p_user_id IN user_account.id%TYPE, p_role_id IN role.id%TYPE) IS
    BEGIN
        DELETE FROM user_role WHERE user_id = p_user_id AND role_id = p_role_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20034, 'El usuario no tenía asignado ese rol.');
        END IF;
    END revoke_role;


    ------------------------------------------------------------
    PROCEDURE grant_permission(p_role_id IN role.id%TYPE, p_permission_id IN permission.id%TYPE) IS
    BEGIN
        BEGIN
            INSERT INTO role_permission (role_id, permission_id) VALUES (p_role_id, p_permission_id);
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                RAISE_APPLICATION_ERROR(-20035, 'El rol ya tiene asignado ese permiso.');
        END;
    END grant_permission;

    PROCEDURE revoke_permission(p_role_id IN role.id%TYPE, p_permission_id IN permission.id%TYPE) IS
    BEGIN
        DELETE FROM role_permission WHERE role_id = p_role_id AND permission_id = p_permission_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20036, 'El rol no tenía asignado ese permiso.');
        END IF;
    END revoke_permission;


    ------------------------------------------------------------
    FUNCTION has_permission(
        p_user_id        IN user_account.id%TYPE,
        p_permission_code IN permission.code%TYPE
    ) RETURN BOOLEAN
    IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO v_count
          FROM user_role ur
          JOIN role_permission rp ON rp.role_id = ur.role_id
          JOIN permission p       ON p.id = rp.permission_id
         WHERE ur.user_id = p_user_id
           AND p.code = p_permission_code;

        RETURN v_count > 0;
    END has_permission;


    ------------------------------------------------------------
    -- NOTA: usa APEX_UTIL.SET_SESSION_STATE, que solo existe/funciona
    -- corriendo dentro de una sesión de APEX. Si algún día se cambia
    -- de frontend (Angular, etc.), este procedimiento puntual dejaría
    -- de aplicar tal cual -- pero el resto del paquete (has_permission,
    -- authenticate, etc.) sigue siendo 100% reutilizable sin cambios,
    -- que es justo el objetivo.
    ------------------------------------------------------------
    PROCEDURE set_session_context(p_username IN user_account.username%TYPE) IS
        v_user_id    user_account.id%TYPE;
        v_company_id user_account.company_id%TYPE;
    BEGIN
        SELECT id, company_id INTO v_user_id, v_company_id
          FROM user_account
         WHERE username = p_username;

        apex_util.set_session_state('G_USER_ID', v_user_id);
        apex_util.set_session_state('G_COMPANY_ID', v_company_id);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20037, 'No existe un usuario con username "' || p_username || '".');
    END set_session_context;

END pkg_user_security;
/
