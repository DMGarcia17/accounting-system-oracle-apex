-- ============================================================
-- 19_role_permission.sql
-- Depende de: 03_role.sql, 18_permission.sql
-- Tabla intermedia N:M entre ROL y PERMISO.
-- ============================================================

CREATE TABLE role_permission (
    role_id         NUMBER          NOT NULL
                                     CONSTRAINT fk_role_permission_role
                                     REFERENCES role(id),
    permission_id   NUMBER          NOT NULL
                                     CONSTRAINT fk_role_permission_permission
                                     REFERENCES permission(id),
    CONSTRAINT pk_role_permission PRIMARY KEY (role_id, permission_id)
);

COMMENT ON TABLE role_permission IS 'Asignación de permisos a roles (relación muchos a muchos)';

-- Mapeo inicial, punto de partida (ajustable después):
-- ADMIN_EMPRESA: todos los permisos
-- CONTADOR: puede contabilizar/anular y ver reportes, no administra catálogo/usuarios/cierre
-- CONSULTA: solo ver reportes
INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r CROSS JOIN permission p WHERE r.code = 'ADMIN_EMPRESA';

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r JOIN permission p
    ON p.code IN ('POST_JOURNAL_ENTRY', 'REVERSE_JOURNAL_ENTRY', 'VIEW_REPORTS')
WHERE r.code = 'CONTADOR';

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r JOIN permission p
    ON p.code = 'VIEW_REPORTS'
WHERE r.code = 'CONSULTA';

COMMIT;
