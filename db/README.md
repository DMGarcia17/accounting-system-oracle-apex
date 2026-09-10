# Estructura de base de datos - Sistema Contable

## Convención de idioma

Código, nombres de tablas/columnas/constraints: **en inglés**.
Comentarios y documentación: **en español**.
(Misma convención que el resto de tus proyectos.)

## Orden de ejecución

Correr conectado como `CONTA_SCHEMA` en `XEPDB1` (no como `sys`), en este orden exacto:

1. `01_company.sql`
2. `02_accounting_period.sql`
3. `03_role.sql`
4. `04_user_account.sql`
5. `05_user_role.sql`
6. `06_gl_account.sql`
7. `07_journal_entry.sql`
8. `08_journal_entry_line.sql`
9. `09_mv_log_journal_entry_line.sql`
9b. `09b_mv_log_journal_entry.sql` (log adicional requerido por el JOIN, ver nota abajo)
10. `10_mv_account_balances.sql`
11. `11_vw_account_balance.sql`
12. `12_alter_company_costing_method.sql`
13. `13_inventory_item.sql`
14. `14_inventory_movement.sql`
15. `15_vw_inventory_balance.sql`
16. `16_alter_journal_entry_draft.sql`
17. `17_alter_journal_entry_reversal.sql`
18. `18_permission.sql`
19. `19_role_permission.sql`
20. `20_journal_entry_template.sql`
21. `21_journal_entry_template_line.sql`
22. `22_alter_gl_account_current_classification.sql`

El orden respeta las dependencias de llaves foráneas y de vistas materializadas.

**Nota sobre `09b`**: Oracle exige un materialized view log en cada tabla que participa
en el `JOIN` de una vista materializada con `FAST REFRESH`, no solo en la tabla de
detalle. `mv_account_balances` hace `JOIN` entre `journal_entry_line` y `journal_entry`,
así que ambas necesitan su propio log (09 y 09b respectivamente) — esto no era evidente
hasta que Oracle lo exigió en tiempo de ejecución (`ORA-23413`).

**Nota sobre `10` y `11`**: la primera versión de `mv_account_balances` tenía un
`WHERE e.status = 'ACTIVE'`, pero Oracle no permite `FAST REFRESH` en un `JOIN` cuando
hay un filtro que no es parte de la condición de unión (`ORA-12033`). Se corrigió
sacando el filtro de la vista materializada (agregando `status` al `GROUP BY` en su
lugar) y aplicándolo en `vw_account_balance`, donde un `WHERE` normal no tiene esa
restricción.

**Causa raíz real del `ORA-12033`** (confirmada, no solo la primera hipótesis): el
`JOIN` usa la llave primaria de `journal_entry` (`e.id = l.journal_entry_id`). Para que
Oracle permita `FAST REFRESH` sobre un `JOIN` así, el materialized view log de la tabla
cuya llave primaria se usa en la condición de unión necesita la opción `WITH PRIMARY KEY`
explícita, no alcanza con `WITH ROWID` solo. Por eso `09b_mv_log_journal_entry.sql`
tiene `WITH ROWID, PRIMARY KEY, SEQUENCE (...)`.

## Decisiones de diseño (para no repreguntarlas después)

- **Multi-empresa**: un solo schema, aislamiento por columna `company_id` en cada tabla transaccional.
- **Autenticación**: tabla `user_account` propia (no cuentas de workspace de APEX). Password se guarda como `SHA-256(password + salt)`, hexadecimal, 64 caracteres. La función que calcula el hash se arma en el esquema de autenticación de APEX (próximo paso). Se llama `user_account` y no `user` porque `USER` es palabra reservada en Oracle.
- **Roles múltiples por usuario**: tabla intermedia `user_role` (muchos a muchos). Un administrador puede tener asignados tanto `ADMIN_EMPRESA` como `CONTADOR`, para operar como cualquiera de los dos sin necesitar una cuenta separada. Roles base: `ADMIN_EMPRESA`, `CONTADOR`, `CONSULTA`.
- **Multi-empresa por usuario**: cada usuario pertenece a una sola empresa fija.
- **Catálogo de cuentas**: tabla `gl_account` (GL = General Ledger / Libro Mayor), jerárquica (`parent_account_id` autorreferenciado). Se llama `gl_account` y no `account` para no confundirla con `user_account`. Solo las cuentas con `is_posting_account = 'Y'` pueden recibir movimientos directos — esto lo valida el paquete PL/SQL, no un CHECK de tabla.
- **Número correlativo de asiento**: NO es una columna IDENTITY. Lo asigna el paquete `PKG_JOURNAL_ENTRY` (pendiente de escribir) porque debe ser correlativo *por empresa*, sin saltos — un requisito legal del libro diario.
- **Inventario periódico/analítico**: Compras y Ventas son cuentas de resultado normales; "Inventarios" solo se toca en los asientos de apertura y cierre (generados por el sistema, no por el usuario a mano).
- **Saldos**: vista materializada (`mv_account_balances`) con `REFRESH FAST ON COMMIT`, agrupada por `company_id + period_id + account_id`. Encima, la vista `vw_account_balance` aplica la regla de naturaleza (Deudora/Acreedora) y expone dos columnas:
  - `period_balance` → para el Estado de Resultados (solo el período actual)
  - `accumulated_balance` → para el Balance General (acumulado desde el primer período)

- **Módulo de Kardex (inventario físico perpetuo, en paralelo a la contabilidad periódica)**: `inventory_item` (catálogo de artículos) + `inventory_movement` (las líneas del Kardex: entradas/salidas con cantidad y costo unitario). Vive en paralelo al libro mayor — una compra o venta genera A LA VEZ un asiento contable periódico (que no toca Inventarios) y un movimiento de Kardex (que sí actualiza existencias al instante). Al cierre, el saldo del Kardex (`vw_inventory_balance`) le da al sistema una cifra calculada de Inventario Final para contrastar contra el conteo físico real.
  - **Método de costeo: PENDIENTE DE CONFIRMAR.** Se dejó `AVERAGE` (Promedio Ponderado) como valor por defecto en `company.inventory_costing_method`, porque no hay un ejemplo de clase con dos compras a precios distintos que permita distinguir si es Promedio o PEPS. La tabla `inventory_movement` incluye la columna `remaining_quantity` (sin usar por ahora) reservada para si resulta ser FIFO/PEPS, que necesita rastrear lotes de compra por separado.
  - `OPENING_BALANCE` y `CLOSING_BALANCE` en `inventory_movement` son registros de referencia (el conteo físico al abrir/cerrar el ejercicio), no se suman como flujo en `vw_inventory_balance` — son para comparar contra lo que el sistema calculó solo.

## Pendiente para las próximas sesiones

- **Confirmar el método de costeo del Kardex** (Promedio vs PEPS) con un ejemplo de clase que tenga dos compras a precios distintos. `pkg_inventory` está escrito asumiendo Promedio Ponderado.

## Paquetes PL/SQL (carpeta packages/, ver README raíz)

Todos corren `CREATE OR REPLACE`, se pueden re-ejecutar sin problema.

**Orden de compilación importante**: `pkg_journal_entry_body` llama a
`pkg_inventory.reverse_movement` (para reversar movimientos de Kardex
vinculados a un asiento anulado), así que **`pkg_inventory` tiene que
compilarse ANTES que `pkg_journal_entry_body`**, o falla con "no existe
pkg_inventory.reverse_movement":

1. `pkg_inventory_spec.sql` → `pkg_inventory_body.sql`
2. `pkg_journal_entry_spec.sql` → `pkg_journal_entry_body.sql`
3. `pkg_period_close_spec.sql` → `pkg_period_close_body.sql` (depende de pkg_journal_entry)
4. `pkg_entry_template_spec.sql` → `pkg_entry_template_body.sql` (depende de pkg_journal_entry)
5. `pkg_user_security_spec.sql` → `pkg_user_security_body.sql` (independiente de los demás)

Qué hace cada uno:
- `pkg_inventory`: movimientos de Kardex (compras, ventas, devoluciones, conteo, reverso de movimientos).
- `pkg_journal_entry`: crear/completar/postear/descartar/anular asientos.
- `pkg_period_close`: cierre y apertura de ejercicio, vista previa de resultado.
- `pkg_entry_template`: instanciar asientos desde plantillas recurrentes.
- `pkg_user_security`: usuarios, roles, permisos, autenticación para APEX.

Pendiente: probar todo con Claude Code de punta a punta antes de tocar APEX.
- Paquete/proceso de cierre de ejercicio: cálculo de costo de ventas, generación automática del asiento de cierre, generación del asiento de apertura del siguiente período.
- Esquema de autenticación personalizado en APEX (función de validación contra `user_account`, hash de password).
- Esquemas de autorización en APEX ligados a `role`/`user_role` (qué botones/páginas ve cada rol).
- Catálogo de cuentas base (plantilla comercial estándar) para insertar como datos semilla.
