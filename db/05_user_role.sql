-- ============================================================
-- 05_user_role.sql
-- Depende de: 04_user_account.sql, 03_role.sql
-- Tabla intermedia N:M. Resuelve el caso de un administrador que
-- también necesita operar como contador: simplemente se le asignan
-- ambos roles (ADMIN_EMPRESA + CONTADOR) en dos filas separadas.
-- ============================================================

CREATE TABLE user_role (
    user_id         NUMBER          NOT NULL
                                     CONSTRAINT fk_user_role_user
                                     REFERENCES user_account(id),
    role_id         NUMBER          NOT NULL
                                     CONSTRAINT fk_user_role_role
                                     REFERENCES role(id),
    assigned_at     DATE            DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_user_role PRIMARY KEY (user_id, role_id)
);

COMMENT ON TABLE user_role IS 'Asignación de roles a usuarios (relación muchos a muchos)';
