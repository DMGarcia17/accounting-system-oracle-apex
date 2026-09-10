-- Ejecutar conectado como SYS con rol SYSDBA, dentro del PDB XEPDB1
-- (verificá que estés en el contenedor correcto: SHOW CON_NAME; debe decir XEPDB1)

ALTER SESSION SET CONTAINER = XEPDB1;

-- Crear el usuario/schema de trabajo
CREATE USER CONTA_SCHEMA IDENTIFIED BY "CAMBIAR_PASSWORD_ANTES_DE_EJECUTAR"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS;

-- Privilegios básicos para desarrollo (crear tablas, vistas, procedimientos, etc.)
GRANT CREATE SESSION TO CONTA_SCHEMA;
GRANT CREATE TABLE TO CONTA_SCHEMA;
GRANT CREATE VIEW TO CONTA_SCHEMA;
GRANT CREATE SEQUENCE TO CONTA_SCHEMA;
GRANT CREATE PROCEDURE TO CONTA_SCHEMA;
GRANT CREATE TRIGGER TO CONTA_SCHEMA;
GRANT CREATE SYNONYM TO CONTA_SCHEMA;

-- Necesario más adelante para exponer el schema vía ORDS/APEX (job scheduling, etc.)
GRANT CREATE JOB TO CONTA_SCHEMA;

-- Confirmar que se creó correctamente
SELECT username, account_status, default_tablespace
FROM dba_users
WHERE username = 'CONTA_SCHEMA';
