# accounting-system-oracle-apex

Sistema contable multi-empresa construido sobre Oracle Database XE, APEX y ORDS,
con Power BI como capa de reporting. Proyecto de portfolio, desarrollado en
paralelo a un curso universitario de contabilidad.

## Estructura de carpetas

```
accounting-system-oracle-apex/
├── docker-compose.yml       Contenedores: oracle-xe + ords
├── .env.example             Plantilla de variables de entorno (copiar a .env)
├── .gitignore
├── apex/                    Software de Oracle APEX descargado (NO se versiona)
├── setup/                   Scripts de un solo uso para preparar el entorno
│   ├── 01_create_schema.sql       Crea el usuario/schema CONTA_SCHEMA
│   └── 02_ords_manual_fixes.sql   Fixes puntuales si ORDS/APEX quedan
│                                   con permisos incompletos (ver sección
│                                   "Problemas conocidos" más abajo)
├── db/                      Estructura de tablas de la aplicación
│   ├── README.md                  Decisiones de diseño del modelo de datos
│   └── 01_company.sql … 15_vw_inventory_balance.sql
├── packages/                Paquetes PL/SQL de lógica de negocio (pendiente)
└── seed/                    Datos semilla: catálogo de cuentas base (pendiente)
```

## Requisitos

- **Docker Desktop** con backend WSL2 (Windows) o Docker Engine nativo (Linux/Mac).
- **Cuenta gratuita en Oracle Container Registry** ([container-registry.oracle.com](https://container-registry.oracle.com)),
  con la licencia aceptada para las imágenes `database/express` y `database/ords`.
- **SQL Developer** (o cualquier cliente SQL) para correr los scripts de `setup/` y `db/`.
- **Al menos 4GB de RAM libres** para Docker — Oracle XE + ORDS son livianos pero no triviales.
  Si tu máquina anda justa de RAM, ajustá un `.wslconfig` (Windows) limitando la memoria de WSL2,
  y los límites `mem_limit` de cada servicio en el `docker-compose.yml`.

## Preparar el entorno

1. **Cloná el repo** y entrá a la carpeta.

2. **Copiá `.env.example` a `.env`** y completá los passwords:
   ```
   cp .env.example .env
   ```
   Necesitás `ORACLE_PWD` (para SYS/SYSTEM) y `ORDS_PUBLIC_PWD` (para el usuario interno de ORDS).

3. **Descargá el software de Oracle APEX** desde la [página oficial de descargas](https://www.oracle.com/tools/downloads/apex-downloads/)
   (la versión "Full" o "English only" alcanza). Extraé el contenido del ZIP dentro de la carpeta `apex/`
   de este repo (la ruta final debe quedar como `apex/apxsilentins.sql`, `apex/images/`, etc. — sin una
   carpeta `apex/apex/` anidada).

4. **Levantá los contenedores**:
   ```
   docker compose up -d
   ```
   El primer arranque de `oracle-xe` tarda varios minutos (crea la base desde cero). Verificalo con:
   ```
   docker logs -f oracle-xe-contable
   ```
   hasta ver `DATABASE IS READY TO USE!`.

5. **Levantá ORDS** (instala ORDS y APEX dentro de la base, puede tardar varios minutos la primera vez):
   ```
   docker compose up -d ords
   docker logs -f apex-ords
   ```
   Esperá a ver `The Oracle APEX has been installed` y que el servidor quede escuchando en el puerto 8080.

6. **Creá el schema de la aplicación**: conectado como `sys`/SYSDBA vía SQL Developer
   (`localhost:1521/XEPDB1`), corré `setup/01_create_schema.sql`.

7. **Entrá a APEX** en `http://localhost:8080/ords/apex`, iniciá sesión como `ADMIN`
   (el password se define la primera vez que entrás a `http://localhost:8080/ords/apex_admin`),
   y creá tu workspace asociado a `CONTA_SCHEMA`.

8. **Cargá la estructura de tablas**: conectado como `CONTA_SCHEMA`, corré todos los scripts
   de `db/` en orden numérico (ver `db/README.md` para el detalle de cada uno).

## Problemas conocidos

Con la combinación de imágenes usada (`database/express` + `database/ords` + APEX montado por
volumen), el schema `ORDS_METADATA` puede quedar con permisos incompletos o sin la fila de
configuración del PL/SQL Gateway, aunque los logs digan que todo se instaló bien — se manifiesta
como un `404 Not Found` al entrar a `/ords/apex`, con errores `ORA-00942` en `docker logs apex-ords`.
Si te pasa esto, corré `setup/02_ords_manual_fixes.sql` y reiniciá el contenedor de `ords`.
