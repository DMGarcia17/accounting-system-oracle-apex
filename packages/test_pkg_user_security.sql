-- ============================================================
-- tests/test_pkg_user_security.sql
-- Correr conectado como CONTA_SCHEMA.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_company_id  company.id%TYPE;
    v_role_id     role.id%TYPE;
    v_perm_id     permission.id%TYPE;
    v_user_id     user_account.id%TYPE;

    PROCEDURE report(p_case IN VARCHAR2, p_passed IN BOOLEAN, p_detail IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CASE WHEN p_passed THEN '[PASS] ' ELSE '[FAIL] ' END
                              || p_case || CASE WHEN p_detail IS NOT NULL THEN ' -- ' || p_detail END);
    END;

BEGIN
    ------------------------------------------------------------------
    -- FIXTURES
    ------------------------------------------------------------------
    INSERT INTO company (name) VALUES ('Empresa de Prueba - test_pkg_user_security')
        RETURNING id INTO v_company_id;

    INSERT INTO role (code, name) VALUES ('TEST_ROLE_' || v_company_id, 'Rol de prueba')
        RETURNING id INTO v_role_id;

    INSERT INTO permission (code, name) VALUES ('TEST_PERM_' || v_company_id, 'Permiso de prueba')
        RETURNING id INTO v_perm_id;

    COMMIT;

    ------------------------------------------------------------------
    -- ESCENARIO 1: crear usuario y autenticar con password correcto
    ------------------------------------------------------------------
    BEGIN
        v_user_id := pkg_user_security.create_user(
            v_company_id, 'test.user.' || v_company_id, 'Usuario de Prueba',
            'test@example.com', 'ClaveInicial123!');
        COMMIT;

        IF pkg_user_security.authenticate('test.user.' || v_company_id, 'ClaveInicial123!') THEN
            report('Escenario 1: autenticar con password correcto', TRUE);
        ELSE
            report('Escenario 1: autenticar con password correcto', FALSE);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 1: crear/autenticar usuario', FALSE, SQLERRM);
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 2: autenticar con password incorrecto debe fallar
    ------------------------------------------------------------------
    IF NOT pkg_user_security.authenticate('test.user.' || v_company_id, 'PasswordEquivocado') THEN
        report('Escenario 2: rechazar password incorrecto', TRUE);
    ELSE
        report('Escenario 2: rechazar password incorrecto', FALSE, 'autenticó con password malo');
    END IF;

    ------------------------------------------------------------------
    -- ESCENARIO 3: usuario inactivo no puede autenticar aunque el
    -- password sea correcto
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.deactivate_user(v_user_id);
        COMMIT;

        IF NOT pkg_user_security.authenticate('test.user.' || v_company_id, 'ClaveInicial123!') THEN
            report('Escenario 3: rechazar usuario inactivo', TRUE);
        ELSE
            report('Escenario 3: rechazar usuario inactivo', FALSE, 'autenticó estando inactivo');
        END IF;

        pkg_user_security.reactivate_user(v_user_id);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 3: rechazar usuario inactivo', FALSE, SQLERRM);
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 4: cambiar password, el viejo deja de servir y el
    -- nuevo funciona
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.change_password(v_user_id, 'ClaveInicial123!', 'ClaveNueva456!');
        COMMIT;

        IF NOT pkg_user_security.authenticate('test.user.' || v_company_id, 'ClaveInicial123!')
           AND pkg_user_security.authenticate('test.user.' || v_company_id, 'ClaveNueva456!') THEN
            report('Escenario 4: cambio de password', TRUE);
        ELSE
            report('Escenario 4: cambio de password', FALSE);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 4: cambio de password', FALSE, SQLERRM);
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 5: asignar rol + permiso, verificar has_permission,
    -- después revocar y verificar que vuelve a dar falso
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.assign_role(v_user_id, v_role_id);
        pkg_user_security.grant_permission(v_role_id, v_perm_id);
        COMMIT;

        DECLARE
            v_code permission.code%TYPE;
        BEGIN
            SELECT code INTO v_code FROM permission WHERE id = v_perm_id;

            IF pkg_user_security.has_permission(v_user_id, v_code) THEN
                report('Escenario 5a: has_permission tras asignar', TRUE);
            ELSE
                report('Escenario 5a: has_permission tras asignar', FALSE);
            END IF;

            pkg_user_security.revoke_role(v_user_id, v_role_id);
            COMMIT;

            IF NOT pkg_user_security.has_permission(v_user_id, v_code) THEN
                report('Escenario 5b: has_permission tras revocar rol', TRUE);
            ELSE
                report('Escenario 5b: has_permission tras revocar rol', FALSE);
            END IF;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 5: roles y permisos', FALSE, SQLERRM);
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 6: username duplicado debe ser rechazado
    ------------------------------------------------------------------
    BEGIN
        DECLARE
            v_dummy user_account.id%TYPE;
        BEGIN
            v_dummy := pkg_user_security.create_user(
                v_company_id, 'test.user.' || v_company_id, 'Otro Nombre',
                'otro@example.com', 'OtroPassword123!');
            report('Escenario 6: rechazar username duplicado', FALSE, 'no lanzó excepción');
            ROLLBACK;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 6: rechazar username duplicado', SQLCODE = -20030, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- LIMPIEZA
    ------------------------------------------------------------------
    DELETE FROM role_permission WHERE role_id = v_role_id OR permission_id = v_perm_id;
    DELETE FROM user_role WHERE user_id = v_user_id;
    DELETE FROM user_account WHERE id = v_user_id;
    DELETE FROM permission WHERE id = v_perm_id;
    DELETE FROM role WHERE id = v_role_id;
    DELETE FROM company WHERE id = v_company_id;
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('--- limpieza de datos de prueba completada ---');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR INESPERADO EN EL SETUP DE FIXTURES: ' || SQLERRM);
        ROLLBACK;
END;
/
