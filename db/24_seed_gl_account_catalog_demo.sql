-- ============================================================
-- 24_seed_gl_account_catalog_demo.sql
-- Depende de: 22_alter_gl_account_current_classification.sql (con el
--             CHECK ya relajado para cuentas de agrupación)
--
-- Carga el catálogo de cuentas comercial provisto por la docente
-- (Universidad Católica de El Salvador, Contabilidad 1) para la
-- empresa "Empresa Comercial Demo", creada por este mismo script.
--
-- Solo se cargan los grupos 1-5 (Activo, Pasivo, Patrimonio, Costos y
-- Gastos, Ingresos) -- los grupos 6 (Cuenta de Cierre / Pérdidas y
-- Ganancias) y 7 (Cuentas de Orden) se omiten a propósito: el 6 ya lo
-- resuelve pkg_period_close.close_period contra la cuenta EQUITY de
-- Resultados Acumulados, y el 7 (cuentas de orden/contingentes, fuera
-- de balance) no encaja en el diseño de doble partida de este sistema.
--
-- El catálogo original numera los niveles con cantidad de dígitos
-- irregular (ej. 1105 -> 110501, sin pasar por un nivel de 6 dígitos
-- intermedio en todos los casos), así que la jerarquía NO se arma por
-- "cada 2 dígitos son un nivel" sino por PREFIJO: la cuenta padre de
-- cada código es el código más largo ya cargado que sea prefijo
-- estricto del código actual. Esto se calcula en el loop de abajo,
-- no a mano.
--
-- account_type se deriva del primer dígito del código (1=ASSET,
-- 2=LIABILITY, 3=EQUITY, 5=REVENUE), excepto el grupo 4 que el
-- catálogo mezcla Costo de Ventas con Gastos: 4101* (Costo de Ventas)
-- se mapea a COST, el resto de 4* (Gastos Administrativos, Gastos de
-- Venta, Otros Costos y Gastos, y sus 2 cuentas de agrupación "4" y
-- "41" que abarcan ambos) se mapea a EXPENSE -- decisión sin impacto
-- real porque esas 2 cuentas de agrupación nunca reciben movimientos
-- directos (is_posting_account='N').
--
-- is_posting_account se deriva automáticamente: 'N' si existe otro
-- código en el catálogo que empiece con este código (tiene hijos),
-- 'Y' si es una hoja.
--
-- is_current (solo ASSET/LIABILITY de detalle) se deriva del código:
-- empieza con '11'/'21' -> Corriente (Y), con '12'/'22' -> No
-- Corriente (N).
-- ============================================================

WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE TABLE stg_gl_catalog_demo (
    code VARCHAR2(20),
    name VARCHAR2(150)
);

INSERT INTO stg_gl_catalog_demo VALUES ('1','ACTIVO');
INSERT INTO stg_gl_catalog_demo VALUES ('11','ACTIVO CORRIENTE');
INSERT INTO stg_gl_catalog_demo VALUES ('1101','EFECTIVO Y EQUIVALENTES DE EFECTIVO');
INSERT INTO stg_gl_catalog_demo VALUES ('110101','CAJA');
INSERT INTO stg_gl_catalog_demo VALUES ('11010101','Caja General');
INSERT INTO stg_gl_catalog_demo VALUES ('11010102','Caja Chica');
INSERT INTO stg_gl_catalog_demo VALUES ('110102','BANCOS MONEDA NACIONAL');
INSERT INTO stg_gl_catalog_demo VALUES ('11010201','CUENTA CORRIENTE');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020101','Banco de America Central, S.A.');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020103','Banco Davivienda, S.A.');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020105','Banco Agricola, S.A.');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020106','Banco Promerica');
INSERT INTO stg_gl_catalog_demo VALUES ('11010202','CUENTA DE AHORRO');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020201','Banco de America Central, S.A.');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020205','Banco Agricola, S.A.');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020206','Banco Promerica');
INSERT INTO stg_gl_catalog_demo VALUES ('11010203','DEPOSITOS A PLAZO');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020301','Deposito a Plazo menor de tres meses');
INSERT INTO stg_gl_catalog_demo VALUES ('1101020302','Deposito a Plazo menor de seis meses');
INSERT INTO stg_gl_catalog_demo VALUES ('110103','BANCOS MONEDA EXTRANJERA');
INSERT INTO stg_gl_catalog_demo VALUES ('11010301','CUENTA CORRIENTE');
INSERT INTO stg_gl_catalog_demo VALUES ('1101030101','Banco en el extranjero 1');
INSERT INTO stg_gl_catalog_demo VALUES ('1101030102','Banco en el extranjero 2');
INSERT INTO stg_gl_catalog_demo VALUES ('11010302','CUENTAS DE AHORRO');
INSERT INTO stg_gl_catalog_demo VALUES ('1101030201','Banco en el extranjero 1');
INSERT INTO stg_gl_catalog_demo VALUES ('1101030202','Banco en el extranjero 2');
INSERT INTO stg_gl_catalog_demo VALUES ('11010303','DEPOSITOS A PLAZO');
INSERT INTO stg_gl_catalog_demo VALUES ('1101030301','Deposito a Plazo menor de tres meses');
INSERT INTO stg_gl_catalog_demo VALUES ('1101030302','Deposito a Plazo menor de seis meses');
INSERT INTO stg_gl_catalog_demo VALUES ('1102','CUENTAS Y DOCUMENTOS POR COBRAR');
INSERT INTO stg_gl_catalog_demo VALUES ('110201','CUENTAS POR COBRAR CREDITOS OTORGADOS');
INSERT INTO stg_gl_catalog_demo VALUES ('11020101','CUENTAS POR COBRAR CLIENTES');
INSERT INTO stg_gl_catalog_demo VALUES ('11020101001','Cliente numero 1');
INSERT INTO stg_gl_catalog_demo VALUES ('11020101002','Cliente numero 2');
INSERT INTO stg_gl_catalog_demo VALUES ('11020101003','Cliente numero 3');
INSERT INTO stg_gl_catalog_demo VALUES ('110202','OTRAS CUENTAS POR COBRAR');
INSERT INTO stg_gl_catalog_demo VALUES ('11020201','VENTA CON TARJETA DE CREDITO');
INSERT INTO stg_gl_catalog_demo VALUES ('1102020101','Credomatic de El Salvador, S.A');
INSERT INTO stg_gl_catalog_demo VALUES ('1102020102','Serfinsa');
INSERT INTO stg_gl_catalog_demo VALUES ('110203','PRESTAMOS A FUNCIONARIOS Y EMPLEADOS');
INSERT INTO stg_gl_catalog_demo VALUES ('11020301','Empleado 1');
INSERT INTO stg_gl_catalog_demo VALUES ('110204','DOCUMENTOS POR COBRAR');
INSERT INTO stg_gl_catalog_demo VALUES ('11020401','Prestamos con garantia personal');
INSERT INTO stg_gl_catalog_demo VALUES ('1103','ESTIMACION PARA CUENTAS INCOBRABLES (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('110301','Estimacion para cuentas incobrables (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1104','INVERSIONES A CORTO PLAZO');
INSERT INTO stg_gl_catalog_demo VALUES ('110401','INVERSIONES EN BOLSA DE VALORES');
INSERT INTO stg_gl_catalog_demo VALUES ('11040101','Bolproes');
INSERT INTO stg_gl_catalog_demo VALUES ('1105','INVENTARIOS');
INSERT INTO stg_gl_catalog_demo VALUES ('110501','Bodega sucursal 01');
INSERT INTO stg_gl_catalog_demo VALUES ('110502','Bodega sucursal 02');
INSERT INTO stg_gl_catalog_demo VALUES ('110503','Bodega sucursal 03');
INSERT INTO stg_gl_catalog_demo VALUES ('110504','Mercaderia en Transito');
INSERT INTO stg_gl_catalog_demo VALUES ('110505','Estimacion por obsolescencia de inventarios (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1106','ACCIONISTAS');
INSERT INTO stg_gl_catalog_demo VALUES ('110601','ACCIONISTA 01');
INSERT INTO stg_gl_catalog_demo VALUES ('110602','ACCIONISTA 02');
INSERT INTO stg_gl_catalog_demo VALUES ('110603','ACCIONISTA 03');
INSERT INTO stg_gl_catalog_demo VALUES ('1107','GASTOS PAGADOS POR ANTICIPADO');
INSERT INTO stg_gl_catalog_demo VALUES ('110701','Seguros pagados por anticipado');
INSERT INTO stg_gl_catalog_demo VALUES ('110702','Alquileres pagados por anticipado');
INSERT INTO stg_gl_catalog_demo VALUES ('110703','Papeleria y utiles');
INSERT INTO stg_gl_catalog_demo VALUES ('110704','Uniformes y equipo');
INSERT INTO stg_gl_catalog_demo VALUES ('110705','Contratos por servicios');
INSERT INTO stg_gl_catalog_demo VALUES ('110706','Otros gastos pagados por anticipado');
INSERT INTO stg_gl_catalog_demo VALUES ('1108','PAGO A CUENTA - ISR');
INSERT INTO stg_gl_catalog_demo VALUES ('110801','Pago a cuenta ISR');
INSERT INTO stg_gl_catalog_demo VALUES ('11080101','Pago a Cuenta del periodo');
INSERT INTO stg_gl_catalog_demo VALUES ('11080102','Pago a Cuenta periodo anterior');
INSERT INTO stg_gl_catalog_demo VALUES ('1109','CREDITO FISCAL - IVA');
INSERT INTO stg_gl_catalog_demo VALUES ('110901','Compras Locales');
INSERT INTO stg_gl_catalog_demo VALUES ('110902','Importaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('110903','Percepciones 1%');
INSERT INTO stg_gl_catalog_demo VALUES ('110904','IVA pagado por anticipado 2%');
INSERT INTO stg_gl_catalog_demo VALUES ('110905','Retenciones 1%');
INSERT INTO stg_gl_catalog_demo VALUES ('12','ACTIVO NO CORRIENTE');
INSERT INTO stg_gl_catalog_demo VALUES ('1201','PROPIEDADES, PLANTA Y EQUIPO');
INSERT INTO stg_gl_catalog_demo VALUES ('120101','Terrenos');
INSERT INTO stg_gl_catalog_demo VALUES ('120102','Edificios');
INSERT INTO stg_gl_catalog_demo VALUES ('120103','MOBILIARIO Y EQUIPO');
INSERT INTO stg_gl_catalog_demo VALUES ('12010301','Mobiliario y equipo de Oficina');
INSERT INTO stg_gl_catalog_demo VALUES ('12010302','Equipo de computo');
INSERT INTO stg_gl_catalog_demo VALUES ('120104','Herramientas y equipos');
INSERT INTO stg_gl_catalog_demo VALUES ('120105','Instalaciones y mejoras');
INSERT INTO stg_gl_catalog_demo VALUES ('120106','Equipo de transporte');
INSERT INTO stg_gl_catalog_demo VALUES ('120107','CONSTRUCCIONES EN PROCESO');
INSERT INTO stg_gl_catalog_demo VALUES ('12010701','Edificios');
INSERT INTO stg_gl_catalog_demo VALUES ('12010702','Instalaciones y mejoras locativas');
INSERT INTO stg_gl_catalog_demo VALUES ('120108','DEPRECIACION ACUMULADA - PROPIEDADES, PLANTA Y EQUIPO (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12010801','Depreciacion acumulada de Edificios (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12010802','Depreciacion acumulada de mobiliario y equipo (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1201080201','Depreciacion acumulada de Mobiliario y equipo de oficina (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1201080202','Depreciacion acumulada de equipo de computo (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1201080203','Depreciacion acumulada de otros equipos (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12010803','Depreciacion acumulada de instalaciones y mejoras (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12010804','Depreciacion acumulada de equipo de transporte (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12010805','Depreciacion acumulada de revaluaciones (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1201080501','Depr. acum. revaluacion edificios (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1201080502','Depr. acum. revaluacion mobiliario y equipo (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1201080503','Depr. acum. revaluacion instalaciones y mejoras (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1201080504','Depr. acum. revaluacion equipo de transporte (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1202','PROPIEDADES, PLANTA Y EQUIPO - EN ARRENDAMIENTO FINANCIERO');
INSERT INTO stg_gl_catalog_demo VALUES ('120201','Terrenos en arrendamiento financiero');
INSERT INTO stg_gl_catalog_demo VALUES ('120202','Edificios en arrendamiento financiero');
INSERT INTO stg_gl_catalog_demo VALUES ('120203','Mobiliario y equipo en arrendamiento financiero');
INSERT INTO stg_gl_catalog_demo VALUES ('120204','Instalaciones y mejoras en arrendamiento financiero');
INSERT INTO stg_gl_catalog_demo VALUES ('120205','Equipo de transporte en arrendamiento financiero');
INSERT INTO stg_gl_catalog_demo VALUES ('120206','Otros equipos en arrendamiento financiero');
INSERT INTO stg_gl_catalog_demo VALUES ('120207','DEPRECIACION ACUMULADA DE PPE EN ARRENDAMIENTO FINANCIERO (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12020701','Depreciacion acumulada de edificios en arrend. Financiero (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12020702','Depreciacion acumulada de mobiliario y equipo en arrend. Fin. (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12020703','Depreciacion acumulada de instalaciones y mejoras en arrend. Fin. (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12020704','Depreciacion acumulada de equipo de transporte en arrend. Fin. (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12020705','Depreciacion acumulada de otros equipos en arrend. Fin. (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1203','PROPIEDADES DE INVERSION');
INSERT INTO stg_gl_catalog_demo VALUES ('120301','Terrenos');
INSERT INTO stg_gl_catalog_demo VALUES ('120302','Edificios');
INSERT INTO stg_gl_catalog_demo VALUES ('120303','Otros');
INSERT INTO stg_gl_catalog_demo VALUES ('1204','INTANGIBLES');
INSERT INTO stg_gl_catalog_demo VALUES ('120401','Derecho de llave');
INSERT INTO stg_gl_catalog_demo VALUES ('120402','Patentes y marcas');
INSERT INTO stg_gl_catalog_demo VALUES ('120403','Franquicias');
INSERT INTO stg_gl_catalog_demo VALUES ('120404','Licencias y concesiones');
INSERT INTO stg_gl_catalog_demo VALUES ('120405','Programas y sistemas');
INSERT INTO stg_gl_catalog_demo VALUES ('120406','Amortizacion acumulada de activos intangibles (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12040601','Amortizacion acumulada de derecho de llave (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12040602','Amortizacion acumulada de patentes y marcas (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12040603','Amortizacion acumulada de franquicias (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12040604','Amortizacion acumulada de licencias y concesiones (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('12040605','Amortizacion acumulada de programas y sistemas (CR)');
INSERT INTO stg_gl_catalog_demo VALUES ('1205','CUENTAS POR COBRAR A LARGO PLAZO');
INSERT INTO stg_gl_catalog_demo VALUES ('120501','Clientes / Largo plazo');
INSERT INTO stg_gl_catalog_demo VALUES ('120502','Otras cuentas por cobrar a largo plazo');
INSERT INTO stg_gl_catalog_demo VALUES ('1206','INVERSIONES PERMANENTES');
INSERT INTO stg_gl_catalog_demo VALUES ('120601','Acciones');
INSERT INTO stg_gl_catalog_demo VALUES ('120602','Participaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('1207','DEPOSITOS EN GARANTIA');
INSERT INTO stg_gl_catalog_demo VALUES ('120701','Fianzas');
INSERT INTO stg_gl_catalog_demo VALUES ('120702','Cheque certificados');
INSERT INTO stg_gl_catalog_demo VALUES ('120703','Depositos por bienes tomados en arrendamiento');
INSERT INTO stg_gl_catalog_demo VALUES ('120704','Otras garantias');
INSERT INTO stg_gl_catalog_demo VALUES ('1208','IMPUESTO SOBRE LA RENTA DIFERIDO - ACTIVO');
INSERT INTO stg_gl_catalog_demo VALUES ('120801','Credito ISR anos anteriores');
INSERT INTO stg_gl_catalog_demo VALUES ('120802','Activo por Impuesto S/ Renta Diferido');
INSERT INTO stg_gl_catalog_demo VALUES ('1209','OTRAS CUENTAS DEUDORAS');
INSERT INTO stg_gl_catalog_demo VALUES ('120901','Otras cuentas deudoras a largo plazo');
INSERT INTO stg_gl_catalog_demo VALUES ('2','PASIVO');
INSERT INTO stg_gl_catalog_demo VALUES ('21','PASIVO CORRIENTE');
INSERT INTO stg_gl_catalog_demo VALUES ('2101','PRESTAMOS A CORTO PLAZO Y SOBREGIROS');
INSERT INTO stg_gl_catalog_demo VALUES ('210101','Sobregiros bancarios');
INSERT INTO stg_gl_catalog_demo VALUES ('210102','Prestamos bancarios (porcion a corto plazo)');
INSERT INTO stg_gl_catalog_demo VALUES ('210103','Prestamos personales (porcion a corto plazo)');
INSERT INTO stg_gl_catalog_demo VALUES ('2102','CUENTAS COMERCIALES POR PAGAR');
INSERT INTO stg_gl_catalog_demo VALUES ('210201','PROVEEDORES POR PAGAR');
INSERT INTO stg_gl_catalog_demo VALUES ('21020101','PROVEEDORES NACIONALES');
INSERT INTO stg_gl_catalog_demo VALUES ('21020101001','Proveedor 01');
INSERT INTO stg_gl_catalog_demo VALUES ('21020101002','Proveedor 02');
INSERT INTO stg_gl_catalog_demo VALUES ('21020101003','Proveedor 03');
INSERT INTO stg_gl_catalog_demo VALUES ('21020102','OTROS PROVEEDORES');
INSERT INTO stg_gl_catalog_demo VALUES ('21020102001','Proveedor 01');
INSERT INTO stg_gl_catalog_demo VALUES ('21020102002','Proveedor 02');
INSERT INTO stg_gl_catalog_demo VALUES ('21020102003','Proveedor 03');
INSERT INTO stg_gl_catalog_demo VALUES ('21020103','PROVEEDORES DEL EXTERIOR');
INSERT INTO stg_gl_catalog_demo VALUES ('21020103001','Proveedor 01');
INSERT INTO stg_gl_catalog_demo VALUES ('21020103002','Proveedor 02');
INSERT INTO stg_gl_catalog_demo VALUES ('21020103003','Proveedor 03');
INSERT INTO stg_gl_catalog_demo VALUES ('210202','DOCUMENTOS POR PAGAR');
INSERT INTO stg_gl_catalog_demo VALUES ('21020201','Documentos por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('2103','ACREEDORES VARIOS');
INSERT INTO stg_gl_catalog_demo VALUES ('210301','Cuota patronal ISSS');
INSERT INTO stg_gl_catalog_demo VALUES ('210302','Cuota patronal AFP');
INSERT INTO stg_gl_catalog_demo VALUES ('210303','IVA por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210304','Pago a cuenta');
INSERT INTO stg_gl_catalog_demo VALUES ('210305','Impuestos municipales');
INSERT INTO stg_gl_catalog_demo VALUES ('210306','Otros impuestos por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210307','Intereses por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210308','Honorarios por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210309','Alquileres por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210310','Servicio telefonico por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210311','Anticipos de clientes');
INSERT INTO stg_gl_catalog_demo VALUES ('210312','Provisiones de caja chica');
INSERT INTO stg_gl_catalog_demo VALUES ('210313','Provisiones de arrendamiento');
INSERT INTO stg_gl_catalog_demo VALUES ('210314','Otras cuentas por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('2104','RETENCIONES POR PAGAR');
INSERT INTO stg_gl_catalog_demo VALUES ('210401','Cotizacion ISSS / Salud');
INSERT INTO stg_gl_catalog_demo VALUES ('210402','COTIZACION A FONDOS DE PENSIONES');
INSERT INTO stg_gl_catalog_demo VALUES ('21040201','ISSS provisional');
INSERT INTO stg_gl_catalog_demo VALUES ('21040202','AFP Crecer');
INSERT INTO stg_gl_catalog_demo VALUES ('21040203','AFP Confia');
INSERT INTO stg_gl_catalog_demo VALUES ('21040204','IPSFA');
INSERT INTO stg_gl_catalog_demo VALUES ('21040205','INPEP');
INSERT INTO stg_gl_catalog_demo VALUES ('210403','RETENCION DE IMPUESTO SOBRE LA RENTA');
INSERT INTO stg_gl_catalog_demo VALUES ('21040301','Retencion con subordinacion laboral');
INSERT INTO stg_gl_catalog_demo VALUES ('21040302','Retencion 10% eventuales');
INSERT INTO stg_gl_catalog_demo VALUES ('21040303','Retencion Pensionados');
INSERT INTO stg_gl_catalog_demo VALUES ('2105','BENEFICIOS A EMPLEADOS POR PAGAR');
INSERT INTO stg_gl_catalog_demo VALUES ('210501','Sueldos por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210502','Comisiones por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210503','Horas extras por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210504','Vacaciones por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210505','Aguinaldos por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210506','Gratificaciones y bonificaciones por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210507','Indemnizaciones por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210508','Bonificaciones por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('210509','Otros beneficios a empleados por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('2106','IMPUESTO SOBRE LA RENTA POR PAGAR');
INSERT INTO stg_gl_catalog_demo VALUES ('210601','Impuesto sobre la Renta Anual');
INSERT INTO stg_gl_catalog_demo VALUES ('210602','Pago a cuenta');
INSERT INTO stg_gl_catalog_demo VALUES ('2107','OBLIGACIONES POR ARRENDAMIENTO FINANCIERO');
INSERT INTO stg_gl_catalog_demo VALUES ('210701','Arrendamientos por leasing (Porcion a corto plazo)');
INSERT INTO stg_gl_catalog_demo VALUES ('2108','IVA - DEBITO FISCAL');
INSERT INTO stg_gl_catalog_demo VALUES ('210801','IVA - DEBITO FISCAL');
INSERT INTO stg_gl_catalog_demo VALUES ('21080101','IVA - debito fiscal - facturas de consumidor final');
INSERT INTO stg_gl_catalog_demo VALUES ('21080102','IVA - debito fiscal - comprobante credito fiscal');
INSERT INTO stg_gl_catalog_demo VALUES ('21080103','IVA - retenido por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('2109','CUENTAS POR PAGAR COMPANIAS RELACIONADAS Y ACCIONISTAS');
INSERT INTO stg_gl_catalog_demo VALUES ('210901','ACCIONISTA 01');
INSERT INTO stg_gl_catalog_demo VALUES ('210902','ACCIONISTA 02');
INSERT INTO stg_gl_catalog_demo VALUES ('2110','DIVIDENDOS POR PAGAR');
INSERT INTO stg_gl_catalog_demo VALUES ('211001','ACCIONISTA 01');
INSERT INTO stg_gl_catalog_demo VALUES ('211002','ACCIONISTA 02');
INSERT INTO stg_gl_catalog_demo VALUES ('22','PASIVO NO CORRIENTE');
INSERT INTO stg_gl_catalog_demo VALUES ('2201','PRESTAMOS POR PAGAR A LARGO PLAZO');
INSERT INTO stg_gl_catalog_demo VALUES ('220101','Prestamos bancarios (Porcion a largo plazo)');
INSERT INTO stg_gl_catalog_demo VALUES ('220102','Prestamos personales (Porcion a largo plazo)');
INSERT INTO stg_gl_catalog_demo VALUES ('2202','OBLIGACIONES POR ARRENDAMIENTO FINANCIERO');
INSERT INTO stg_gl_catalog_demo VALUES ('220201','Arrendamientos por leasing (Porcion a largo plazo)');
INSERT INTO stg_gl_catalog_demo VALUES ('2203','BENEFICIOS POR PAGAR A EMPLEADOS - LARGO PLAZO');
INSERT INTO stg_gl_catalog_demo VALUES ('220301','Indemnizaciones por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('220302','Otras prestaciones por pagar a largo plazo');
INSERT INTO stg_gl_catalog_demo VALUES ('2204','IMPUESTO SOBRE LA RENTA DIFERIDO - PASIVO');
INSERT INTO stg_gl_catalog_demo VALUES ('220401','Pasivo por Impuesto sobre la Renta diferido');
INSERT INTO stg_gl_catalog_demo VALUES ('3','PATRIMONIO');
INSERT INTO stg_gl_catalog_demo VALUES ('31','CAPITAL Y RESERVAS');
INSERT INTO stg_gl_catalog_demo VALUES ('3101','CAPITAL SOCIAL');
INSERT INTO stg_gl_catalog_demo VALUES ('310101','CAPITAL SOCIAL MINIMO');
INSERT INTO stg_gl_catalog_demo VALUES ('31010101','Capital Social Minimo pagado');
INSERT INTO stg_gl_catalog_demo VALUES ('31010102','Capital Social Minimo por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('310102','CAPITAL SOCIAL VARIABLE');
INSERT INTO stg_gl_catalog_demo VALUES ('31010201','Capital social variable pagado');
INSERT INTO stg_gl_catalog_demo VALUES ('31010202','Capital social variable por pagar');
INSERT INTO stg_gl_catalog_demo VALUES ('3102','RESERVA LEGAL');
INSERT INTO stg_gl_catalog_demo VALUES ('3103','SUPERAVIT POR REVALUACIONES');
INSERT INTO stg_gl_catalog_demo VALUES ('32','RESULTADOS POR APLICAR');
INSERT INTO stg_gl_catalog_demo VALUES ('3201','UTILIDADES DE EJERCICIOS ANTERIORES');
INSERT INTO stg_gl_catalog_demo VALUES ('320101','UTILIDADES DE EJERCICIOS ANTERIORES');
INSERT INTO stg_gl_catalog_demo VALUES ('32010101','Utilidad ano anterior');
INSERT INTO stg_gl_catalog_demo VALUES ('3202','UTILIDAD DEL PRESENTE EJERCICIO');
INSERT INTO stg_gl_catalog_demo VALUES ('320201','UTILIDAD DEL PRESENTE EJERCICIO');
INSERT INTO stg_gl_catalog_demo VALUES ('32020101','Utilidad del presente ejercicio');
INSERT INTO stg_gl_catalog_demo VALUES ('3203','DEFICIT DE EJERCICIOS ANTERIORES');
INSERT INTO stg_gl_catalog_demo VALUES ('320301','DEFICIT DE EJERCICIOS ANTERIORES');
INSERT INTO stg_gl_catalog_demo VALUES ('32030101','Ejercicio pasado');
INSERT INTO stg_gl_catalog_demo VALUES ('32030102','Ejercicio anterior');
INSERT INTO stg_gl_catalog_demo VALUES ('3204','DEFICIT DEL PRESENTE EJERCICIO');
INSERT INTO stg_gl_catalog_demo VALUES ('320401','Deficit del presente ejercicio');
INSERT INTO stg_gl_catalog_demo VALUES ('32040101','Deficit del presente ejercicio');
INSERT INTO stg_gl_catalog_demo VALUES ('4','CUENTAS DE RESULTADO DEUDORAS');
INSERT INTO stg_gl_catalog_demo VALUES ('41','COSTOS Y GASTOS DE OPERACION');
INSERT INTO stg_gl_catalog_demo VALUES ('4101','COSTO DE VENTAS');
INSERT INTO stg_gl_catalog_demo VALUES ('410101','COSTO DE VENTA MERCADERIA ADQUIRIDA PARA LA VENTA SUCURSAL 01');
INSERT INTO stg_gl_catalog_demo VALUES ('41010101','Compra de mercaderia adquirida para linea de venta 01');
INSERT INTO stg_gl_catalog_demo VALUES ('41010102','Compra de mercaderia adquirida para linea de venta 02');
INSERT INTO stg_gl_catalog_demo VALUES ('41010103','Compra de mercaderia adquirida para linea de venta 03');
INSERT INTO stg_gl_catalog_demo VALUES ('410102','COSTO DE VENTA MERCADERIA ADQUIRIDA PARA LA VENTA SUCURSAL 02');
INSERT INTO stg_gl_catalog_demo VALUES ('41010201','Compra de mercaderia adquirida para linea de venta 01');
INSERT INTO stg_gl_catalog_demo VALUES ('41010202','Compra de mercaderia adquirida para linea de venta 02');
INSERT INTO stg_gl_catalog_demo VALUES ('41010203','Compra de mercaderia adquirida para linea de venta 03');
INSERT INTO stg_gl_catalog_demo VALUES ('410103','COSTO DE VENTA MERCADERIA ADQUIRIDA PARA LA VENTA SUCURSAL 03');
INSERT INTO stg_gl_catalog_demo VALUES ('41010301','Compra de mercaderia adquirida para linea de venta 01');
INSERT INTO stg_gl_catalog_demo VALUES ('41010302','Compra de mercaderia adquirida para linea de venta 02');
INSERT INTO stg_gl_catalog_demo VALUES ('41010303','Compra de mercaderia adquirida para linea de venta 03');
INSERT INTO stg_gl_catalog_demo VALUES ('4102','GASTOS ADMINISTRATIVOS');
INSERT INTO stg_gl_catalog_demo VALUES ('410201','GASTOS DE PERSONAL');
INSERT INTO stg_gl_catalog_demo VALUES ('41020101','Salarios');
INSERT INTO stg_gl_catalog_demo VALUES ('41020102','Vacaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41020103','Aguinaldos');
INSERT INTO stg_gl_catalog_demo VALUES ('41020104','Bonificaciones y gratificaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41020105','Horas extras');
INSERT INTO stg_gl_catalog_demo VALUES ('41020106','Indemnizaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41020107','Viaticos');
INSERT INTO stg_gl_catalog_demo VALUES ('41020108','Cuota patronal seguridad social ISSS');
INSERT INTO stg_gl_catalog_demo VALUES ('41020109','Cuota patronal fondo de pensiones AFP');
INSERT INTO stg_gl_catalog_demo VALUES ('41020110','INSAFORP');
INSERT INTO stg_gl_catalog_demo VALUES ('41020111','Comisiones, premios e incentivos');
INSERT INTO stg_gl_catalog_demo VALUES ('41020112','Gastos por equipos de proteccion contra COVID');
INSERT INTO stg_gl_catalog_demo VALUES ('41020113','Otros gastos del personal');
INSERT INTO stg_gl_catalog_demo VALUES ('410202','GASTOS DE MANTENIMIENTO');
INSERT INTO stg_gl_catalog_demo VALUES ('41020201','Mantenimiento de edificaciones e instalaciones propias');
INSERT INTO stg_gl_catalog_demo VALUES ('41020202','Mantenimiento de Mobiliario Equipo De Oficina');
INSERT INTO stg_gl_catalog_demo VALUES ('41020203','Mantenimiento y Reparacion De Vehiculos');
INSERT INTO stg_gl_catalog_demo VALUES ('41020204','Otros gastos por mantenimiento');
INSERT INTO stg_gl_catalog_demo VALUES ('410203','GASTOS POR SERVICIOS PUBLICOS Y PRIVADOS');
INSERT INTO stg_gl_catalog_demo VALUES ('41020301','Servicio de agua');
INSERT INTO stg_gl_catalog_demo VALUES ('41020302','Servicio de energia electrica');
INSERT INTO stg_gl_catalog_demo VALUES ('41020303','Servicio de Telefono');
INSERT INTO stg_gl_catalog_demo VALUES ('41020304','Servicio de internet/cable');
INSERT INTO stg_gl_catalog_demo VALUES ('41020305','Servicio de vigilancia');
INSERT INTO stg_gl_catalog_demo VALUES ('41020306','Publicidad y promocion');
INSERT INTO stg_gl_catalog_demo VALUES ('41020307','Impresiones y Encuadernaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41020308','Suscripciones periodicos y Revistas');
INSERT INTO stg_gl_catalog_demo VALUES ('41020309','Servicios de limpieza y Ornamentacion');
INSERT INTO stg_gl_catalog_demo VALUES ('41020310','Otros servicios');
INSERT INTO stg_gl_catalog_demo VALUES ('410204','HONORARIOS PROFESIONALES');
INSERT INTO stg_gl_catalog_demo VALUES ('41020401','Honorarios legales');
INSERT INTO stg_gl_catalog_demo VALUES ('41020402','Honorarios contables');
INSERT INTO stg_gl_catalog_demo VALUES ('41020403','Honorarios de auditoria');
INSERT INTO stg_gl_catalog_demo VALUES ('41020404','Honorarios por servicios administrativos');
INSERT INTO stg_gl_catalog_demo VALUES ('41020405','Otros honorarios');
INSERT INTO stg_gl_catalog_demo VALUES ('410205','GASTOS POR DEPRECIACION');
INSERT INTO stg_gl_catalog_demo VALUES ('41020501','Depreciacion de edificaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41020502','Depreciacion a instalaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41020503','Depreciacion de mejoras a propiedades arrendadas');
INSERT INTO stg_gl_catalog_demo VALUES ('41020504','Depreciacion de Maquinaria y Equipo Industrial');
INSERT INTO stg_gl_catalog_demo VALUES ('41020505','Depreciacion de Mobiliario y Equipo de Oficina');
INSERT INTO stg_gl_catalog_demo VALUES ('41020506','Depreciacion de Herramientas y Equipo Pequeno');
INSERT INTO stg_gl_catalog_demo VALUES ('41020507','Depreciacion de Equipo de transporte');
INSERT INTO stg_gl_catalog_demo VALUES ('41020508','Depreciacion de edificaciones bajo arrendamiento financiero');
INSERT INTO stg_gl_catalog_demo VALUES ('41020509','Depreciacion de Maquinaria y Equipo Industrial bajo arrend. fin.');
INSERT INTO stg_gl_catalog_demo VALUES ('41020510','Depreciacion de Mobiliario y Equipo de Oficina bajo arrend. fin.');
INSERT INTO stg_gl_catalog_demo VALUES ('41020511','Depreciacion de Equipo de transporte bajo arrend. fin.');
INSERT INTO stg_gl_catalog_demo VALUES ('410206','GASTOS POR AMORTIZACION');
INSERT INTO stg_gl_catalog_demo VALUES ('41020601','Amortizacion de activos intangibles');
INSERT INTO stg_gl_catalog_demo VALUES ('41020602','Amortizacion Licencias de software');
INSERT INTO stg_gl_catalog_demo VALUES ('410207','GASTOS POR SEGUROS');
INSERT INTO stg_gl_catalog_demo VALUES ('41020701','Seguro de vida y medico');
INSERT INTO stg_gl_catalog_demo VALUES ('41020702','Seguro de activos');
INSERT INTO stg_gl_catalog_demo VALUES ('410208','GASTOS POR IMPUESTOS, TASAS MUNICIPALES Y OTRAS CONTRIBUCIONES');
INSERT INTO stg_gl_catalog_demo VALUES ('41020801','Impuestos y tasas municipales');
INSERT INTO stg_gl_catalog_demo VALUES ('41020802','Derechos y aranceles de registros de comercio');
INSERT INTO stg_gl_catalog_demo VALUES ('41020803','Impuestos y derechos de aduanas');
INSERT INTO stg_gl_catalog_demo VALUES ('41020804','Otras contribuciones publicas');
INSERT INTO stg_gl_catalog_demo VALUES ('410209','GASTOS A CLIENTES Y EMPLEADOS');
INSERT INTO stg_gl_catalog_demo VALUES ('41020901','Atencion a visitas y funcionarios');
INSERT INTO stg_gl_catalog_demo VALUES ('41020902','Atencion a empleados');
INSERT INTO stg_gl_catalog_demo VALUES ('41020903','Atencion a Clientes');
INSERT INTO stg_gl_catalog_demo VALUES ('41020904','Cursos de capacitacion a empleados');
INSERT INTO stg_gl_catalog_demo VALUES ('41020905','Otras atenciones a clientes y empleados');
INSERT INTO stg_gl_catalog_demo VALUES ('41020906','Promocion y difusion de medidas sanitaria por COVID');
INSERT INTO stg_gl_catalog_demo VALUES ('41021','GASTOS DE VIATICOS, VIAJES Y DE REPRESENTACION');
INSERT INTO stg_gl_catalog_demo VALUES ('41021001','Gastos de transportes');
INSERT INTO stg_gl_catalog_demo VALUES ('41021002','Gastos de Viajes');
INSERT INTO stg_gl_catalog_demo VALUES ('41021003','Gastos de Alimentacion');
INSERT INTO stg_gl_catalog_demo VALUES ('41021004','Gastos de representacion');
INSERT INTO stg_gl_catalog_demo VALUES ('41021005','Gasto de Hospedaje');
INSERT INTO stg_gl_catalog_demo VALUES ('41021006','Gasto de boletos aereos');
INSERT INTO stg_gl_catalog_demo VALUES ('41021007','Combustibles y lubricantes');
INSERT INTO stg_gl_catalog_demo VALUES ('41021008','FOVIAL');
INSERT INTO stg_gl_catalog_demo VALUES ('41021009','Alquileres');
INSERT INTO stg_gl_catalog_demo VALUES ('41021010','Papeleria y utiles');
INSERT INTO stg_gl_catalog_demo VALUES ('41021011','Donaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41021012','Otros gastos varios administrativos');
INSERT INTO stg_gl_catalog_demo VALUES ('4103','GASTOS DE VENTA');
INSERT INTO stg_gl_catalog_demo VALUES ('410301','GASTOS DE PERSONAL');
INSERT INTO stg_gl_catalog_demo VALUES ('41030101','Salarios');
INSERT INTO stg_gl_catalog_demo VALUES ('41030102','Vacaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41030103','Aguinaldos');
INSERT INTO stg_gl_catalog_demo VALUES ('41030104','Bonificaciones y gratificaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41030105','Horas extras');
INSERT INTO stg_gl_catalog_demo VALUES ('41030106','Indemnizaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41030107','Viaticos');
INSERT INTO stg_gl_catalog_demo VALUES ('41030108','Cuota patronal seguridad social ISSS');
INSERT INTO stg_gl_catalog_demo VALUES ('41030109','Cuota patronal fondo de pensiones AFP');
INSERT INTO stg_gl_catalog_demo VALUES ('41030110','INSAFORP');
INSERT INTO stg_gl_catalog_demo VALUES ('41030111','Comisiones, premios e incentivos');
INSERT INTO stg_gl_catalog_demo VALUES ('41030112','Gastos por equipos de proteccion contra COVID');
INSERT INTO stg_gl_catalog_demo VALUES ('41030113','Otros gastos del personal');
INSERT INTO stg_gl_catalog_demo VALUES ('410302','GASTOS DE MANTENIMIENTO');
INSERT INTO stg_gl_catalog_demo VALUES ('41030201','Mantenimiento de edificaciones e instalaciones propias');
INSERT INTO stg_gl_catalog_demo VALUES ('41030202','Mantenimiento de Mobiliario Equipo De Oficina');
INSERT INTO stg_gl_catalog_demo VALUES ('41030203','Mantenimiento y Reparacion De Vehiculos');
INSERT INTO stg_gl_catalog_demo VALUES ('41030204','Otros gastos por mantenimiento');
INSERT INTO stg_gl_catalog_demo VALUES ('410303','GASTOS POR SERVICIOS PUBLICOS Y PRIVADOS');
INSERT INTO stg_gl_catalog_demo VALUES ('41030301','Servicio de agua');
INSERT INTO stg_gl_catalog_demo VALUES ('41030302','Servicio de energia electrica');
INSERT INTO stg_gl_catalog_demo VALUES ('41030303','Servicio de Telefono');
INSERT INTO stg_gl_catalog_demo VALUES ('41030304','Servicio de internet/cable');
INSERT INTO stg_gl_catalog_demo VALUES ('41030305','Servicio de vigilancia');
INSERT INTO stg_gl_catalog_demo VALUES ('41030306','Publicidad y promocion');
INSERT INTO stg_gl_catalog_demo VALUES ('41030307','Impresiones y Encuadernaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41030308','Suscripciones periodicos y Revistas');
INSERT INTO stg_gl_catalog_demo VALUES ('41030309','Servicios de limpieza y Ornamentacion');
INSERT INTO stg_gl_catalog_demo VALUES ('410304','HONORARIOS PROFESIONALES');
INSERT INTO stg_gl_catalog_demo VALUES ('41030401','Honorarios legales');
INSERT INTO stg_gl_catalog_demo VALUES ('41030402','Honorarios contables');
INSERT INTO stg_gl_catalog_demo VALUES ('41030403','Honorarios de auditoria');
INSERT INTO stg_gl_catalog_demo VALUES ('41030404','Honorarios por servicios administrativos');
INSERT INTO stg_gl_catalog_demo VALUES ('410305','GASTOS POR DEPRECIACION');
INSERT INTO stg_gl_catalog_demo VALUES ('41030501','Depreciacion de edificaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41030502','Depreciacion a instalaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41030503','Depreciacion de mejoras a propiedades arrendadas');
INSERT INTO stg_gl_catalog_demo VALUES ('41030504','Depreciacion de Maquinaria y Equipo Industrial');
INSERT INTO stg_gl_catalog_demo VALUES ('41030505','Depreciacion de Mobiliario y Equipo de Oficina');
INSERT INTO stg_gl_catalog_demo VALUES ('41030506','Depreciacion de Herramientas y Equipo Pequeno');
INSERT INTO stg_gl_catalog_demo VALUES ('41030507','Depreciacion de Equipo de transporte');
INSERT INTO stg_gl_catalog_demo VALUES ('41030508','Depreciacion de edificaciones bajo arrend. financiero');
INSERT INTO stg_gl_catalog_demo VALUES ('41030509','Depreciacion de Maquinaria y Equipo Industrial bajo arrend. fin.');
INSERT INTO stg_gl_catalog_demo VALUES ('41030510','Depreciacion de Mobiliario y Equipo de Oficina bajo arrend. fin.');
INSERT INTO stg_gl_catalog_demo VALUES ('41030511','Depreciacion de Equipo de transporte bajo arrend. fin.');
INSERT INTO stg_gl_catalog_demo VALUES ('410306','GASTOS POR AMORTIZACION');
INSERT INTO stg_gl_catalog_demo VALUES ('41030601','Amortizacion de activos intangibles');
INSERT INTO stg_gl_catalog_demo VALUES ('41030602','Amortizacion Licencias de software');
INSERT INTO stg_gl_catalog_demo VALUES ('410307','GASTOS POR SEGUROS');
INSERT INTO stg_gl_catalog_demo VALUES ('41030701','Seguro de vida y medico');
INSERT INTO stg_gl_catalog_demo VALUES ('41030702','Seguro de activos');
INSERT INTO stg_gl_catalog_demo VALUES ('410308','GASTOS POR IMPUESTOS, TASAS MUNICIPALES Y OTRAS CONTRIBUCIONES');
INSERT INTO stg_gl_catalog_demo VALUES ('41030801','Impuestos y tasas municipales');
INSERT INTO stg_gl_catalog_demo VALUES ('41030802','Derechos y aranceles de registros de comercio');
INSERT INTO stg_gl_catalog_demo VALUES ('41030803','Impuestos y derechos de aduanas');
INSERT INTO stg_gl_catalog_demo VALUES ('41030804','Otras contribuciones publicas');
INSERT INTO stg_gl_catalog_demo VALUES ('41030805','Gastos a clientes y empleados');
INSERT INTO stg_gl_catalog_demo VALUES ('41030806','Atencion a visitas y funcionarios');
INSERT INTO stg_gl_catalog_demo VALUES ('410309','ATENCION A EMPLEADOS');
INSERT INTO stg_gl_catalog_demo VALUES ('41030901','Atencion a empleados repatriados');
INSERT INTO stg_gl_catalog_demo VALUES ('41030902','Atencion a Clientes');
INSERT INTO stg_gl_catalog_demo VALUES ('41030903','Cursos de capacitacion a empleados');
INSERT INTO stg_gl_catalog_demo VALUES ('41030904','Otras atenciones a clientes y empleados');
INSERT INTO stg_gl_catalog_demo VALUES ('41030905','Promocion y difusion de medidas sanitaria por COVID');
INSERT INTO stg_gl_catalog_demo VALUES ('41031','GASTOS DE VIATICOS, VIAJES Y DE REPRESENTACION');
INSERT INTO stg_gl_catalog_demo VALUES ('41031001','Gastos de transportes');
INSERT INTO stg_gl_catalog_demo VALUES ('41031002','Gastos de Viajes');
INSERT INTO stg_gl_catalog_demo VALUES ('41031003','Gastos de Alimentacion');
INSERT INTO stg_gl_catalog_demo VALUES ('41031004','Gastos de representacion');
INSERT INTO stg_gl_catalog_demo VALUES ('41031005','Gasto de Hospedaje');
INSERT INTO stg_gl_catalog_demo VALUES ('41031006','Gasto de boletos aereos');
INSERT INTO stg_gl_catalog_demo VALUES ('41031007','Combustibles y lubricantes');
INSERT INTO stg_gl_catalog_demo VALUES ('41031008','FOVIAL');
INSERT INTO stg_gl_catalog_demo VALUES ('41031009','Alquileres');
INSERT INTO stg_gl_catalog_demo VALUES ('41031010','Papeleria y utiles');
INSERT INTO stg_gl_catalog_demo VALUES ('41031011','Donaciones');
INSERT INTO stg_gl_catalog_demo VALUES ('41031012','Otros gastos varios administrativos');
INSERT INTO stg_gl_catalog_demo VALUES ('42','OTROS COSTOS Y GASTOS');
INSERT INTO stg_gl_catalog_demo VALUES ('4201','GASTOS FINANCIEROS');
INSERT INTO stg_gl_catalog_demo VALUES ('420101','Intereses sobre prestamos');
INSERT INTO stg_gl_catalog_demo VALUES ('420102','Comisiones');
INSERT INTO stg_gl_catalog_demo VALUES ('420103','Seguros');
INSERT INTO stg_gl_catalog_demo VALUES ('420104','Impuesto a las Operaciones Financieras');
INSERT INTO stg_gl_catalog_demo VALUES ('4202','PERDIDA EN VENTA O RETIRO DE ACTIVOS FIJOS');
INSERT INTO stg_gl_catalog_demo VALUES ('420201','Perdida en venta o retiro de activos fijos');
INSERT INTO stg_gl_catalog_demo VALUES ('4203','GASTOS POR DETERIORO EN EL VALOR DE ACTIVOS');
INSERT INTO stg_gl_catalog_demo VALUES ('420301','Gastos por deterioro en el valor de activos');
INSERT INTO stg_gl_catalog_demo VALUES ('4204','PERDIDAS POR SINIESTROS');
INSERT INTO stg_gl_catalog_demo VALUES ('420401','Perdidas por siniestros');
INSERT INTO stg_gl_catalog_demo VALUES ('4205','GASTOS DE EJERCICIOS ANTERIORES');
INSERT INTO stg_gl_catalog_demo VALUES ('420501','Gastos de ejercicios anteriores');
INSERT INTO stg_gl_catalog_demo VALUES ('4206','OTROS GASTOS');
INSERT INTO stg_gl_catalog_demo VALUES ('420601','Otros Gastos no Clasificados');
INSERT INTO stg_gl_catalog_demo VALUES ('5','CUENTAS DE RESULTADO ACREEDORAS');
INSERT INTO stg_gl_catalog_demo VALUES ('51','INGRESOS POR VENTAS');
INSERT INTO stg_gl_catalog_demo VALUES ('5101','INGRESOS OPERACIONALES');
INSERT INTO stg_gl_catalog_demo VALUES ('510101','VENTAS LOCALES SALA DE VENTAS 01');
INSERT INTO stg_gl_catalog_demo VALUES ('51010101','Ventas a contribuyentes');
INSERT INTO stg_gl_catalog_demo VALUES ('51010102','Ventas a consumidor final');
INSERT INTO stg_gl_catalog_demo VALUES ('51010103','Ventas de exportacion');
INSERT INTO stg_gl_catalog_demo VALUES ('510102','VENTAS LOCALES SALA DE VENTAS 02');
INSERT INTO stg_gl_catalog_demo VALUES ('51010201','Ventas a contribuyentes');
INSERT INTO stg_gl_catalog_demo VALUES ('51010202','Ventas a consumidor final');
INSERT INTO stg_gl_catalog_demo VALUES ('51010203','Ventas de exportacion');
INSERT INTO stg_gl_catalog_demo VALUES ('510103','VENTAS LOCALES SALA DE VENTAS 03');
INSERT INTO stg_gl_catalog_demo VALUES ('51010301','Ventas a contribuyentes');
INSERT INTO stg_gl_catalog_demo VALUES ('51010302','Ventas a consumidor final');
INSERT INTO stg_gl_catalog_demo VALUES ('51010303','Ventas de exportacion');
INSERT INTO stg_gl_catalog_demo VALUES ('510104','REBAJAS Y DEVOLUCIONES SOBRE VENTAS');
INSERT INTO stg_gl_catalog_demo VALUES ('51010401','Rebajas sobre ventas');
INSERT INTO stg_gl_catalog_demo VALUES ('51010402','Devoluciones sobre ventas');
INSERT INTO stg_gl_catalog_demo VALUES ('52','OTROS PRODUCTOS');
INSERT INTO stg_gl_catalog_demo VALUES ('5201','PRODUCTOS FINANCIEROS');
INSERT INTO stg_gl_catalog_demo VALUES ('520101','Intereses bancarios');
INSERT INTO stg_gl_catalog_demo VALUES ('520102','Intereses sobre inversiones exentas de impuestos');
INSERT INTO stg_gl_catalog_demo VALUES ('520103','Otros Intereses');
INSERT INTO stg_gl_catalog_demo VALUES ('5202','GANANCIA EN VENTA DE ACTIVOS FIJOS');
INSERT INTO stg_gl_catalog_demo VALUES ('520201','Ganancia en venta de activos fijos');
INSERT INTO stg_gl_catalog_demo VALUES ('5203','INDEMNIZACIONES POR SINIESTROS');
INSERT INTO stg_gl_catalog_demo VALUES ('520301','Indemnizaciones por siniestros');
INSERT INTO stg_gl_catalog_demo VALUES ('5204','OTROS PRODUCTOS');
INSERT INTO stg_gl_catalog_demo VALUES ('520401','Diferencia en cambio de moneda extranjera');
INSERT INTO stg_gl_catalog_demo VALUES ('520402','Comisiones');
INSERT INTO stg_gl_catalog_demo VALUES ('520403','Otros productos');

COMMIT;

-- ============================================================
-- Carga real: recorre la staging table en orden de longitud de
-- código (los padres, más cortos, siempre antes que sus hijos) y
-- calcula todo lo demás por código.
-- ============================================================
DECLARE
    v_company_id gl_account.company_id%TYPE;
    v_type       gl_account.account_type%TYPE;
    v_normal     gl_account.normal_balance%TYPE;
    v_posting    gl_account.is_posting_account%TYPE;
    v_current    gl_account.is_current%TYPE;
    v_parent_id  gl_account.parent_account_id%TYPE;
    v_has_child  NUMBER;
    v_count      NUMBER := 0;
BEGIN
    BEGIN
        SELECT id INTO v_company_id FROM company WHERE name = 'Empresa Comercial Demo';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            INSERT INTO company (name) VALUES ('Empresa Comercial Demo') RETURNING id INTO v_company_id;
            COMMIT;
    END;

    FOR rec IN (SELECT code, name FROM stg_gl_catalog_demo ORDER BY LENGTH(code), code) LOOP

        v_type := CASE
                    WHEN rec.code LIKE '1%'    THEN 'ASSET'
                    WHEN rec.code LIKE '2%'    THEN 'LIABILITY'
                    WHEN rec.code LIKE '3%'    THEN 'EQUITY'
                    WHEN rec.code LIKE '4101%' THEN 'COST'
                    WHEN rec.code LIKE '4%'    THEN 'EXPENSE'
                    WHEN rec.code LIKE '5%'    THEN 'REVENUE'
                  END;

        v_normal := CASE WHEN v_type IN ('ASSET','COST','EXPENSE') THEN 'D' ELSE 'C' END;

        SELECT COUNT(*) INTO v_has_child
          FROM stg_gl_catalog_demo WHERE code LIKE rec.code || '_%';
        v_posting := CASE WHEN v_has_child > 0 THEN 'N' ELSE 'Y' END;

        IF v_type IN ('ASSET','LIABILITY') AND v_posting = 'Y' THEN
            v_current := CASE SUBSTR(rec.code,1,2)
                            WHEN '11' THEN 'Y' WHEN '21' THEN 'Y'
                            WHEN '12' THEN 'N' WHEN '22' THEN 'N'
                            ELSE NULL
                         END;
        ELSE
            v_current := NULL;
        END IF;

        BEGIN
            SELECT id INTO v_parent_id
              FROM gl_account
             WHERE company_id = v_company_id
               AND rec.code LIKE code || '%' AND code <> rec.code
             ORDER BY LENGTH(code) DESC
             FETCH FIRST 1 ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN v_parent_id := NULL;
        END;

        INSERT INTO gl_account (
            company_id, parent_account_id, code, name,
            normal_balance, account_type, is_posting_account, is_current
        ) VALUES (
            v_company_id, v_parent_id, rec.code, rec.name,
            v_normal, v_type, v_posting, v_current
        );

        v_count := v_count + 1;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Cuentas cargadas: ' || v_count);
END;
/

DROP TABLE stg_gl_catalog_demo PURGE;
