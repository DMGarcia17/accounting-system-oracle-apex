# Hallazgos — sesión de pruebas exhaustivas (2026-09-10)

Bitácora consolidada de bugs e inconsistencias confirmados **ejecutando** los
scripts de `test/` contra la base de desarrollo local (Oracle XE 21c,
`CONTA_SCHEMA`, vía `docker exec oracle-xe-contable sqlplus`). No son
hipótesis de lectura de código: cada entrada tiene un escenario que lo
reprodujo con evidencia real (mensaje de error / valores observados).

**Resultado final de la suite**: 100 escenarios/hallazgos ejecutados en los 6
scripts de `test/`, **0 fallos** (cada uno confirmó exactamente lo que debía
confirmar, sea un comportamiento correcto o un bug).

Convención de severidad: 🔴 Crítico (rompe un flujo real u otro objeto
documentado) · 🟠 Alto (bug de validación/seguridad real) · 🟡 Medio (diseño
inconsistente o limitación no documentada del todo) · ⚪ Riesgo documentado
sin prueba ejecutada (concurrencia) · ℹ️ Nota de entorno (no es bug de código).

---

## 🔴 Críticos

### 1. `mv_account_balances` NO se refresca sola con el `COMMIT`
- **Objeto**: `db/10_mv_account_balances.sql`, `pkg_period_close`.
- **Escenario que lo expone**: `test/test_views_and_constraints.sql`,
  "Escenario 1 / Hallazgo crítico"; también forzó el ajuste de
  `test/test_pkg_period_close.sql` (Escenarios 3a, 3b, 6).
- **Qué pasa**: la MV está creada con `REFRESH FAST ON COMMIT`
  (`db/10_mv_account_balances.sql:17`) y `db/README.md` documenta esto como
  el mecanismo de saldos "en tiempo real". En la práctica, tras postear un
  asiento y hacer `COMMIT`, `mv_account_balances` sigue **vacía/desactualizada**
  — solo se actualiza si alguien llama `DBMS_MVIEW.REFRESH` a mano. Además,
  un refresh manual `'F'` (fast) falla con `ORA-12057: materialized view or
  zonemap ... is invalid and must use complete refresh`; solo funciona `'C'`
  (complete).
- **Impacto real**: `pkg_period_close.estimate_period_result` y
  `pkg_period_close.open_period` leen `vw_account_balance` (que se apoya en
  esta MV) inmediatamente después de un `COMMIT` — sin un refresh manual
  intercalado, ambas funciones fallan con `NO_DATA_FOUND` o devuelven datos
  viejos. Cualquier reporte "en tiempo real" sobre `vw_account_balance`
  también queda afectado.
- **Hipótesis de causa raíz** (no confirmada, para investigar): `db/09b_mv_log_journal_entry.sql`
  hace `DROP MATERIALIZED VIEW LOG ON journal_entry;` y lo vuelve a crear
  ("versión CORREGIDA"). Si ese `DROP`+`CREATE` se ejecutó **después** de que
  `mv_account_balances` ya existiera, es un patrón conocido que invalida el
  fast refresh aunque `user_mviews.refresh_mode` siga mostrando `COMMIT`.
- **Sugerencia**: recrear la MV desde cero (`DROP` + `db/10...sql` de nuevo)
  ya con el log corregido en su lugar, y confirmar `user_mviews.staleness =
  'FRESH'` y `fast_refreshable` sin banderas de invalidez después de un
  `COMMIT` real (no un refresh manual).

### 2. Dos asientos en `DRAFT` (`entry_number NULL`) de la misma empresa NO pueden coexistir
- **Objeto**: `UQ_ENTRY_COMPANY_NUMBER` (`company_id, entry_number`) en
  `journal_entry`, `db/16_alter_journal_entry_draft.sql`.
- **Escenario que lo expone**: "Hallazgo D" en
  `test/test_pkg_journal_entry.sql` y el Escenario 4 (renombrado) en
  `test/test_views_and_constraints.sql`.
- **Qué pasa**: `db/16_alter_journal_entry_draft.sql:22-23` y
  `db/README.md` afirman literalmente: *"como `entry_number` ahora es
  NULL-able, y Oracle permite múltiples NULLs en un UNIQUE compuesto, varios
  DRAFTs de la misma empresa pueden coexistir con `entry_number IS NULL` sin
  violar el UNIQUE"*. **Esto es falso**, confirmado con una reproducción
  mínima de 2 `INSERT` crudos: Oracle excluye una fila de la comprobación de
  unicidad de una clave compuesta **solo si TODAS las columnas de la clave
  son NULL**. Acá `company_id` nunca es NULL, así que dos filas
  `(company_id=X, entry_number=NULL)` **sí** se consideran duplicadas entre
  sí y el segundo `INSERT`/`UPDATE` revienta con `ORA-00001`.
- **Impacto real**: la simple **segunda** llamada a `create_header` de una
  empresa, mientras exista *cualquier* asiento sin postear (DRAFT) de esa
  empresa (por ejemplo, uno que el usuario dejó a medias, o uno que falló
  `reverse_entry` y quedó huérfano), revienta con un `ORA-00001` crudo — no
  un `RAISE_APPLICATION_ERROR` de negocio. Este bug además **contaminó en
  cascada** varios escenarios de prueba posteriores hasta que se identificó
  (cualquier DRAFT que quede sin postear/descartar bloquea TODO
  `create_header` posterior de la misma empresa).
- **Sugerencia**: la corrección más simple es asignar el `entry_number`
  **al crear** el encabezado (aunque sea un número "provisional" no
  correlativo hasta el posteo), o quitar `entry_number` del UNIQUE compuesto
  y usar un `UNIQUE` filtrado / índice funcional que solo aplique
  `WHERE entry_number IS NOT NULL`.

### 3. `close_period` puede duplicar (en vez de cancelar) el desbalance de una cuenta de resultado con saldo neto contrario a su `normal_balance`
- **Objeto**: `pkg_period_close.close_period` (`packages/pkg_period_close_body.sql:103-113`).
- **Escenario que lo expone**: "Hallazgo F" en `test/test_pkg_period_close.sql`.
- **Qué pasa**: la línea de "cancelación" que arma `close_period` para cada
  cuenta REVENUE/COST/EXPENSE con movimiento en el período usa **siempre**
  la dirección contraria al `normal_balance` de la cuenta (`CASE
  rec.normal_balance WHEN 'D' THEN 'C' ELSE 'D' END`), sin mirar el signo
  real del saldo calculado (`v_balance`). Si la cuenta terminó el período
  con saldo neto en la dirección **contraria** a su naturaleza (ej. una
  cuenta de Ventas —normalmente acreedora— que ese período tuvo más Debe que
  Haber, por una devolución sin ventas que la respalden), la "cancelación"
  la refuerza en la MISMA dirección del desbalance en vez de anularla.
- **Evidencia real**: con una cuenta Ventas con Debe=300/Haber=0 en el
  período, `close_period` intentó postear un asiento de cierre con
  **Debe=590 vs Haber=10** (`ORA-20005: El asiento no cuadra`) — el error
  se propaga crudo desde `pkg_journal_entry`, sin que `pkg_period_close` lo
  traduzca ni documente.
- **Sugerencia**: usar `SIGN(v_balance)` para elegir la dirección de la
  línea de cancelación en vez de asumir siempre la dirección contraria al
  `normal_balance` declarado de la cuenta.

---

## 🟠 Altos

### 4. `has_permission` no filtra por `user_account.is_active`
- **Objeto**: `pkg_user_security.has_permission`.
- **Escenario**: "Hallazgo L" en `test/test_pkg_user_security.sql`.
- **Qué pasa**: un usuario **desactivado** (`deactivate_user`) que conserva
  un rol asignado con permisos sigue devolviendo `TRUE` en `has_permission`.
  `authenticate` sí lo bloquearía en el login, pero cualquier chequeo de
  autorización posterior a la autenticación (ej. un esquema de autorización
  de APEX que no vuelve a autenticar en cada request) seguiría
  autorizándolo.
- **Sugerencia**: unir con `user_account` y agregar `AND ua.is_active = 'Y'`.

### 5. `create_user` / `change_password` / `reset_password` aceptan password `NULL` sin error
- **Escenario**: "Hallazgo J" y "Hallazgo K" en `test/test_pkg_user_security.sql`.
- **Qué pasa**: `hash_password(NULL, salt)` calcula un hash válido (Oracle
  trata `NULL || salt` como `salt`), así que un usuario puede quedar con un
  password efectivamente vacío/predecible sin que ninguna de las tres
  funciones lo impida. Confirmado: el usuario creado/reseteado con password
  `NULL` luego autentica exitosamente pasando `NULL` como password.
- **Sugerencia**: agregar `IF p_password IS NULL OR LENGTH(p_password) <
  <mínimo> THEN RAISE_APPLICATION_ERROR(...)` en las 3 funciones.

### 6. `discard_draft` con un `inventory_movement` vinculado deja pasar `ORA-02292` crudo
- **Objeto**: `pkg_journal_entry.discard_draft`.
- **Escenario**: "Hallazgo A" en `test/test_pkg_journal_entry.sql`.
- **Qué pasa**: si un DRAFT tiene un `inventory_movement.journal_entry_id`
  apuntándolo (Kardex vinculado a un asiento aún no posteado), el `DELETE
  FROM journal_entry` de `discard_draft` falla con
  `ORA-02292: integrity constraint (FK_MOVEMENT_ENTRY) violated - child
  record found` — un error crudo de Oracle, no uno de negocio.
- **Sugerencia**: envolver el `DELETE` y traducir a un
  `RAISE_APPLICATION_ERROR` propio, o validar antes de intentar borrar.

### 7. `assign_role` / `grant_permission` con id inexistente propagan `ORA-02291` crudo
- **Escenario**: "Hallazgo N" en `test/test_pkg_user_security.sql`.
- **Qué pasa**: a diferencia del resto del paquete (que valida existencia
  explícitamente con mensajes propios), estas dos funciones confían
  enteramente en la FK y dejan pasar `ORA-02291: integrity constraint
  violated - parent key not found` sin traducir.
- **Sugerencia**: validar existencia de `p_role_id`/`p_permission_id` antes
  del `INSERT`, igual que en el resto del paquete.

### 8. `estimate_period_result` con período inexistente propaga `NO_DATA_FOUND` crudo
- **Objeto**: `pkg_period_close.estimate_period_result`.
- **Escenario**: Escenario 7 / Hallazgo en `test/test_pkg_period_close.sql`.
- **Qué pasa**: el primer `SELECT company_id INTO ... FROM accounting_period
  WHERE id = p_period_id` no está envuelto en manejo de excepción (a
  diferencia de `close_period`/`open_period`, que sí capturan
  `NO_DATA_FOUND` y lanzan `-20040`). Confirmado: `SQLCODE = 100`
  (`ORA-01403: no data found`) crudo.
- **Sugerencia**: agregar el mismo bloque `WHEN NO_DATA_FOUND THEN
  RAISE_APPLICATION_ERROR(-20040, ...)` que ya usan las otras dos funciones.

### 9. `close_period` no valida el `account_type` de las cuentas recibidas
- **Escenario**: "Hallazgo E" en `test/test_pkg_period_close.sql`.
- **Qué pasa**: se le pasó una cuenta de tipo `EXPENSE` como
  `p_inventory_account_id`, y `close_period` la aceptó sin ningún error,
  contabilizando el "inventario final" ahí. Solo se apoya en las
  validaciones genéricas de `pkg_journal_entry.add_line` (cuenta exista, sea
  de detalle, activa, misma empresa), que no verifican que el tipo
  semántico sea el esperado.
- **Sugerencia**: validar `account_type` de las 3 cuentas recibidas
  (`ASSET` para inventario, `COST` para compras, `EQUITY` para resultados
  acumulados) antes de usarlas.

### 10. `pkg_inventory.reverse_movement` permite reversar el mismo movimiento más de una vez
- **Escenario**: "Hallazgo" en `test/test_pkg_inventory.sql`.
- **Qué pasa**: no existe una columna tipo `is_reversed`/`reversed_by_id` en
  `inventory_movement` que lo bloquee. Si hay existencia suficiente, un
  segundo `reverse_movement` sobre el mismo `p_movement_id` se ejecuta sin
  error, generando otro movimiento contrario adicional.
- **Sugerencia**: agregar una columna de control (o una tabla de reversos)
  y validar antes de reversar.

---

## 🟡 Medios

### 11. `reverse_entry` no valida `entry_type` — permite reversar un `REVERSAL`
- **Escenario**: "Hallazgo B" en `test/test_pkg_journal_entry.sql`.
- Se pudo encadenar un reverso sobre otro reverso (anular una anulación) sin
  ninguna restricción. Puede ser intencional, pero no está documentado ni
  probado hasta ahora — vale la pena decidir explícitamente si se permite.

### 12. `reverse_entry` no valida que la fecha de reverso sea posterior a la del asiento original
- **Escenario**: "Hallazgo C" en `test/test_pkg_journal_entry.sql`.
- Se aceptó un reverso fechado **antes** que el asiento original (mientras
  caiga en algún período abierto), permitiendo anulaciones retroactivas
  cronológicamente incoherentes.

### 13. Inconsistencia de método de costeo: `FIFO` configurado no cambia nada
- **Escenario**: "Hallazgo" en `test/test_pkg_inventory.sql`.
- Con `company.inventory_costing_method = 'FIFO'`, una venta después de dos
  compras a costos distintos (10 y 20) se costeó al promedio ponderado (15),
  no al costo de la compra más antigua (10) como exigiría FIFO real.
  Coincide con lo ya documentado como "pendiente" en `db/README.md`, ahora
  confirmado con números reales.

### 14. Plantilla con 2+ líneas variables del mismo lado reciben el mismo monto
- **Escenario**: "Hallazgo G" en `test/test_pkg_entry_template.sql`.
- Limitación ya documentada en `db/21_journal_entry_template_line.sql`,
  nunca antes ejercitada con una prueba real. Confirmado: ambas líneas
  reciben exactamente el mismo `p_variable_amount`.

### 15. Plantilla sin líneas crea un DRAFT vacío que falla al postear
- **Escenario**: "Hallazgo H" en `test/test_pkg_entry_template.sql`.
- `create_from_template` no valida que la plantilla tenga al menos una
  línea; el error que sale al intentar postear (`-20004`, "necesita al
  menos dos líneas") es genérico de `pkg_journal_entry`, no uno propio de
  plantillas que diga "la plantilla no tiene líneas".

### 16. Sin `ROLLBACK` del caller, un fallo a mitad de instanciación de plantilla deja un DRAFT parcial
- **Escenario**: "Hallazgo I" en `test/test_pkg_entry_template.sql`.
- Si una plantilla tiene una línea fija y luego una variable sin
  `p_variable_amount`, la línea fija ya insertada persiste en un DRAFT
  huérfano si el caller no hace `ROLLBACK` tras la excepción -20062.
  Comportamiento esperable dado que el paquete nunca hace commit/rollback
  por diseño, pero vale la pena que quede documentado como responsabilidad
  explícita del caller.

### 17. `ck_gl_account_is_current` no bloquea `ASSET`/`LIABILITY` con `is_current IS NULL`
- **Escenario**: "Hallazgo" (Escenario 5) en `test/test_views_and_constraints.sql`.
- **Objeto**: `db/22_alter_gl_account_current_classification.sql`.
- El comentario del script dice que ASSET/LIABILITY "tiene que venir Y o N".
  Pero el `CHECK` usa `is_current IN ('Y','N')` en la primera rama, y por la
  lógica de 3 valores de SQL, `NULL IN ('Y','N')` evalúa a `UNKNOWN` (no
  `FALSE`) — y un CHECK constraint solo rechaza la fila si evalúa a `FALSE`.
  Confirmado con `INSERT`: una cuenta `ASSET` con `is_current = NULL` se
  acepta sin error, contradiciendo la intención documentada.
- **Sugerencia**: cambiar la condición a algo que fuerce explícitamente
  `is_current IS NOT NULL` en la rama de ASSET/LIABILITY, ej.:
  `(account_type IN ('ASSET','LIABILITY') AND is_current IS NOT NULL AND is_current IN ('Y','N'))`.

### 18. Reversar una cuenta no siempre la deja en el saldo "de antes" si tuvo otra actividad en el período
- **Escenario**: Escenario 2 en `test/test_views_and_constraints.sql`
  (aritmética verificada con cuenta dedicada aislada).
- No es un bug, es una característica del diseño que vale la pena que quede
  explícita: reversar NO es "cancelar y desaparecer" — es "excluir el
  original del bucket ACTIVE (se va al bucket REVERSED) y sumar un
  movimiento contrario nuevo, real y permanente". Si la cuenta tenía otra
  actividad en el mismo período, el saldo final después de un reverso NO
  vuelve a ser el que había antes del asiento original — queda desplazado
  por el monto del reverso. Documentarlo así evita sorpresas al usar
  `reverse_entry` para "deshacer" un asiento en una cuenta con movimiento
  activo simultáneo.

---

## ⚪ Riesgos de diseño documentados (sin prueba ejecutada — concurrencia)

No se intentó reproducir con sesiones paralelas (decisión tomada al inicio
de la sesión); quedan anotados con la cita exacta del código para la
próxima sesión:

- **`post_entry` vs. `close_period` sobre `accounting_period`**:
  `pkg_journal_entry.post_entry` revalida el período con un `SELECT` plano
  (sin `FOR UPDATE`, `packages/pkg_journal_entry_body.sql:153-156`),
  mientras que `pkg_period_close.close_period` sí bloquea la fila con `FOR
  UPDATE` (`packages/pkg_period_close_body.sql:43-47`). En teoría, un
  `post_entry` podría leer el período como `OPEN` justo cuando otra sesión
  lo está cerrando, en la ventana antes de que esa otra transacción haga
  commit.
- **Asimetría de locking en `pkg_user_security`**: `change_password` usa
  `FOR UPDATE` al leer el usuario (`packages/pkg_user_security_body.sql:68`),
  pero `reset_password`/`deactivate_user`/`reactivate_user` solo hacen
  `SELECT COUNT(*)` sin lock (líneas 98, 159, 169).
- **`post_entry` serializa TODOS los posteos de una empresa**: el `SELECT
  id FROM company ... FOR UPDATE` (`packages/pkg_journal_entry_body.sql:198`)
  usado para asignar el correlativo bloquea la fila de `company` completa
  — cualquier `post_entry` concurrente de la misma empresa queda en cola,
  lo cual es correcto para evitar duplicados de `entry_number`, pero es un
  cuello de botella a vigilar si el volumen de posteos concurrentes crece.

---

## ℹ️ Notas de entorno (no son bugs de código)

- **Codificación de acentos en la salida de sqlplus**: al ejecutar los
  scripts vía `docker exec -i oracle-xe-contable sqlplus ...`, todos los
  caracteres acentuados (á, é, í, ó, ú, ñ) de los mensajes de error y
  comentarios se muestran como `??` en la terminal. Es un problema de
  `NLS_LANG`/juego de caracteres del cliente sqlplus dentro del contenedor,
  no de los datos ni del código — los mensajes en sí (uppercase/contenido)
  son correctos, verificado comparando con el texto fuente de los paquetes.
- **`set_session_context`**: se ejecutó sin lanzar ninguna excepción al
  llamarlo directo por sqlplus (fuera de una sesión APEX real). No se pudo
  determinar si `APEX_UTIL.SET_SESSION_STATE` tiene algún comportamiento de
  fallback fuera de una sesión APEX o si simplemente no tuvo ningún efecto
  perceptible sin `:APP_USER` real. No se considera un bug del paquete —
  su acoplamiento a APEX está documentado a propósito en el spec.
- **La variable `v_test` en `pkg_journal_entry_body.sql:249,315`** no es
  residuo de depuración: `pkg_inventory.reverse_movement` es una `FUNCTION`
  y PL/SQL exige asignar su retorno a algo para poder invocarla (no se
  puede llamar como sentencia suelta como con un `PROCEDURE`). Aclarado por
  el usuario durante la sesión; no se reporta como hallazgo.

---

## Resumen por archivo de test

| Archivo | Escenarios | Hallazgos | Total | Resultado final |
|---|---|---|---|---|
| `test_pkg_inventory.sql` | 18 | 2 | 20 | ✅ todos confirmaron lo esperado |
| `test_pkg_journal_entry.sql` | 23 | 4 (A-D) | 27 | ✅ todos confirmaron lo esperado |
| `test_pkg_period_close.sql` | 7 | 5 | 12* | ✅ todos confirmaron lo esperado |
| `test_pkg_entry_template.sql` | 5 | 3 (G-I) | 8 | ✅ todos confirmaron lo esperado |
| `test_pkg_user_security.sql` | 15 | 8 (J-O) | 23* | ✅ todos confirmaron lo esperado |
| `test_views_and_constraints.sql` | 6 | 2 | 8 | ✅ todos confirmaron lo esperado |

\* el conteo real de líneas `[PASS]` impreso difiere levemente del número de
"casos" nombrados porque algunos escenarios compuestos (5a/5b, etc.) o con
sub-verificaciones imprimen más de una línea — la corrida final consolidada
contó **100** líneas `[PASS]` y **0** `[FAIL]` en total.

## Pendiente para la próxima sesión (a corregir, no solo documentar)

Orden sugerido por severidad/impacto:

1. Arreglar el refresh de `mv_account_balances` (crítico #1) — probablemente
   recrear la MV después de confirmar el log en su estado final.
2. Resolver el UNIQUE de `entry_number` NULL (crítico #2) — bloquea
   cualquier flujo real con más de un DRAFT simultáneo por empresa.
3. Corregir el signo en la cancelación de `close_period` (crítico #3).
4. Los 7 hallazgos 🟠 altos (uno por uno son cambios chicos y localizados).
5. Evaluar los 🟡 medios — varios son decisiones de producto pendientes
   (¿se permite reversar un REVERSAL? ¿reverso retroactivo?) más que bugs
   puros; conviene decidir el comportamiento deseado antes de "corregir".
