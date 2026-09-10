-- ============================================================
-- setup/02_ords_manual_fixes.sql
-- Correr conectado como SYS con rol SYSDBA, en el PDB XEPDB1.
--
-- CONTEXTO: en esta versión de la imagen container-registry.oracle.com/
-- database/ords (26.2.2) combinada con el instalador de APEX 26.1
-- montado por volumen, el schema ORDS_METADATA queda con las vistas
-- POOL_CONFIG y PLSQL_GATEWAY_CONFIG creadas pero SIN los permisos
-- de SELECT para ORDS_PUBLIC_USER, y sin la fila de configuración
-- del PL/SQL Gateway. Esto rompe el acceso a /ords/apex con errores
-- ORA-00942, aunque APEX y ORDS reporten instalación exitosa.
--
-- Este script solo hace falta correrlo SI vuelve a pasar lo mismo
-- (por ejemplo, después de recrear el contenedor de ords desde cero).
-- Si en una instalación futura los permisos y la fila ya existen,
-- estos comandos no hacen daño (el GRANT es idempotente, y el
-- INSERT falla controladamente si la fila ya existe -- revisar el
-- COUNT(*) antes de correrlo, ver más abajo).
-- ============================================================

ALTER SESSION SET CONTAINER = XEPDB1;

-- 1) Otorgar los permisos de lectura que el instalador no dejó puestos
GRANT SELECT ON ords_metadata.pool_config TO ORDS_PUBLIC_USER;
GRANT SELECT ON ords_metadata.plsql_gateway_config TO ORDS_PUBLIC_USER;

-- 2) Registrar la relación de proxy entre ORDS_PUBLIC_USER y APEX_PUBLIC_USER
ALTER USER APEX_PUBLIC_USER GRANT CONNECT THROUGH ORDS_PUBLIC_USER;

-- 3) Insertar la fila de configuración del PL/SQL Gateway.
--    Verificar PRIMERO que no exista ya (si ya hay una fila con
--    runtime_user='ORDS_PUBLIC_USER', NO correr el INSERT, o vas
--    a violar la PRIMARY KEY de ords_metadata.cfg_plsql_gateways).
SELECT COUNT(*) FROM ords_metadata.cfg_plsql_gateways
WHERE runtime_user = 'ORDS_PUBLIC_USER';

-- Si el COUNT anterior dio 0, correr esto:
INSERT INTO ords_metadata.cfg_plsql_gateways (
    id, runtime_user, plsql_gateway_user, comments, created_by, created_on
) VALUES (
    1, 'ORDS_PUBLIC_USER', 'APEX_PUBLIC_USER',
    'Configurado manualmente - paquete ORDS_ADMIN no disponible en esta instalación',
    'SYS', SYSDATE
);
COMMIT;

-- 4) Después de correr esto: docker compose restart ords
