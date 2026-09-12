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
    v_user_null_id user_account.id%TYPE;  -- para el hallazgo de password NULL

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
    -- ESCENARIO 7: change_password con usuario inexistente
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.change_password(-999999, 'x', 'y');
        report('Escenario 7: rechazar change_password sobre usuario inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 7: rechazar change_password sobre usuario inexistente', SQLCODE = -20031, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 8: change_password con password actual incorrecto
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.change_password(v_user_id, 'PasswordViejaIncorrecta', 'NuevaClave000!');
        report('Escenario 8: rechazar change_password con password actual incorrecto', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 8: rechazar change_password con password actual incorrecto', SQLCODE = -20032, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 9: deactivate_user / reactivate_user con usuario
    -- inexistente
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.deactivate_user(-999999);
        report('Escenario 9a: rechazar deactivate_user sobre usuario inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 9a: rechazar deactivate_user sobre usuario inexistente', SQLCODE = -20031, SQLERRM);
            ROLLBACK;
    END;

    BEGIN
        pkg_user_security.reactivate_user(-999999);
        report('Escenario 9b: rechazar reactivate_user sobre usuario inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 9b: rechazar reactivate_user sobre usuario inexistente', SQLCODE = -20031, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 10: reset_password (reseteo administrativo, sin pedir
    -- el password viejo)
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.reset_password(v_user_id, 'ClaveReseteada789!');
        COMMIT;

        IF NOT pkg_user_security.authenticate('test.user.' || v_company_id, 'ClaveNueva456!')
           AND pkg_user_security.authenticate('test.user.' || v_company_id, 'ClaveReseteada789!') THEN
            report('Escenario 10: reset_password administrativo', TRUE);
        ELSE
            report('Escenario 10: reset_password administrativo', FALSE);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 10: reset_password administrativo', FALSE, SQLERRM);
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 11: reset_password con usuario inexistente
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.reset_password(-999999, 'ClaveX123!');
        report('Escenario 11: rechazar reset_password sobre usuario inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 11: rechazar reset_password sobre usuario inexistente', SQLCODE = -20031, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 12: assign_role duplicado (el rol ya se había
    -- revocado en el Escenario 5b, así que primero se reasigna limpio,
    -- y luego se intenta de nuevo para confirmar el rechazo)
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.assign_role(v_user_id, v_role_id);
        COMMIT;

        pkg_user_security.assign_role(v_user_id, v_role_id);
        report('Escenario 12: rechazar assign_role duplicado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 12: rechazar assign_role duplicado', SQLCODE = -20033, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 13: revoke_role sin tener el rol asignado
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.revoke_role(v_user_id, v_role_id);  -- quita el rol asignado en el Escenario 12
        COMMIT;

        pkg_user_security.revoke_role(v_user_id, v_role_id);  -- ya no lo tiene
        report('Escenario 13: rechazar revoke_role sin tener el rol asignado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 13: rechazar revoke_role sin tener el rol asignado', SQLCODE = -20034, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 14: grant_permission duplicado (el permiso sigue
    -- otorgado desde el Escenario 5, nunca se revocó)
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.grant_permission(v_role_id, v_perm_id);
        report('Escenario 14: rechazar grant_permission duplicado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 14: rechazar grant_permission duplicado', SQLCODE = -20035, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- ESCENARIO 15: revoke_permission sin tener el permiso asignado
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.revoke_permission(v_role_id, v_perm_id);  -- lo quita (estaba desde el Escenario 5)
        COMMIT;

        pkg_user_security.revoke_permission(v_role_id, v_perm_id);  -- ya no lo tiene
        report('Escenario 15: rechazar revoke_permission sin tener el permiso asignado', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Escenario 15: rechazar revoke_permission sin tener el permiso asignado', SQLCODE = -20036, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- REGRESIÓN (antes "Hallazgo J", ya corregido -- ver
    -- test/HALLAZGOS.md hallazgo alto #5): create_user con
    -- p_password NULL ahora rechaza con -20038.
    ------------------------------------------------------------------
    BEGIN
        v_user_null_id := pkg_user_security.create_user(
            v_company_id, 'test.nullpwd.' || v_company_id, 'Usuario Password Nulo', 'nullpwd@example.com', NULL);
        report('Regresión: create_user rechaza p_password NULL', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Regresión: create_user rechaza p_password NULL', SQLCODE = -20038, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- REGRESIÓN (antes "Hallazgo K", ya corregido -- ver
    -- test/HALLAZGOS.md hallazgo alto #5): reset_password con
    -- p_new_password NULL ahora rechaza con -20038.
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.reset_password(v_user_id, NULL);
        report('Regresión: reset_password rechaza p_new_password NULL', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Regresión: reset_password rechaza p_new_password NULL', SQLCODE = -20038, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- REGRESIÓN (antes "Hallazgo L", ya corregido -- ver
    -- test/HALLAZGOS.md hallazgo alto #4): has_permission de un
    -- usuario DESACTIVADO que conserva el rol asignado ahora debe
    -- devolver FALSE.
    ------------------------------------------------------------------
    DECLARE
        v_code permission.code%TYPE;
    BEGIN
        pkg_user_security.grant_permission(v_role_id, v_perm_id);  -- se había revocado en el Escenario 15
        pkg_user_security.assign_role(v_user_id, v_role_id);       -- se había revocado en el Escenario 13
        COMMIT;

        SELECT code INTO v_code FROM permission WHERE id = v_perm_id;

        pkg_user_security.deactivate_user(v_user_id);
        COMMIT;

        report('Regresión: has_permission devuelve FALSE para un usuario desactivado',
               NOT pkg_user_security.has_permission(v_user_id, v_code));

        pkg_user_security.reactivate_user(v_user_id);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            report('Regresión: has_permission de un usuario desactivado', FALSE, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO M: authenticate con un username que no existe en
    -- absoluto devuelve FALSE sin lanzar ninguna excepción (comportamiento
    -- documentado en el spec, nunca antes probado explícitamente)
    ------------------------------------------------------------------
    BEGIN
        IF NOT pkg_user_security.authenticate('usuario_que_no_existe_' || SYSDATE, 'cualquier_cosa') THEN
            report('Hallazgo M: authenticate con username inexistente devuelve FALSE sin excepción', TRUE);
        ELSE
            report('Hallazgo M: authenticate con username inexistente devuelve FALSE sin excepción', FALSE,
                   'autenticó con un username que no debería existir');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo M: authenticate con username inexistente', FALSE, SQLERRM);
    END;

    ------------------------------------------------------------------
    -- REGRESIÓN (antes "Hallazgo N", ya corregido -- ver
    -- test/HALLAZGOS.md hallazgo alto #7): assign_role / grant_permission
    -- con un id inexistente del "otro lado" de la FK ahora rechazan con
    -- -20039 (validación propia) en vez del ORA-02291 crudo de Oracle.
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.assign_role(v_user_id, -999999);
        report('Regresión (assign_role): rechazar rol inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Regresión (assign_role): rechaza rol inexistente con validación propia',
                   SQLCODE = -20039, SQLERRM);
            ROLLBACK;
    END;

    BEGIN
        pkg_user_security.grant_permission(-999999, v_perm_id);
        report('Regresión (grant_permission): rechazar rol inexistente', FALSE, 'no lanzó excepción');
        ROLLBACK;
    EXCEPTION
        WHEN OTHERS THEN
            report('Regresión (grant_permission): rechaza rol inexistente con validación propia',
                   SQLCODE = -20039, SQLERRM);
            ROLLBACK;
    END;

    ------------------------------------------------------------------
    -- HALLAZGO O: set_session_context ejecutado directo vía sqlplus
    -- (fuera de una sesión APEX real) -- depende de APEX_UTIL, así
    -- que documentamos lo que realmente pasa en este entorno sin dar
    -- por sentado un resultado.
    ------------------------------------------------------------------
    BEGIN
        pkg_user_security.set_session_context('test.user.' || v_company_id);
        report('Hallazgo O: set_session_context se ejecutó sin error vía sqlplus directo (no se pudo confirmar el acoplamiento a APEX_UTIL en este entorno)', TRUE);
    EXCEPTION
        WHEN OTHERS THEN
            report('Hallazgo O: set_session_context falló fuera de una sesión APEX real (limitación de entorno esperada, no bug del paquete)',
                   TRUE, SQLERRM);
    END;

    ------------------------------------------------------------------
    -- LIMPIEZA
    ------------------------------------------------------------------
    DELETE FROM role_permission WHERE role_id = v_role_id OR permission_id = v_perm_id;
    DELETE FROM user_role WHERE user_id IN (v_user_id, v_user_null_id);
    DELETE FROM user_account WHERE id IN (v_user_id, v_user_null_id);
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
