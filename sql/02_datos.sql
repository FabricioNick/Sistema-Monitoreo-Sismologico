-- ETAPA 2 - Datos sinteticos iniciales, IGP oficial, simulacion y controles
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- REQUIERE datos/igp_catalogo.csv original, cabecera y separador punto y coma. No es idempotente: ejecutar una vez con bd_sismologico previamente creada y sin carga.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico
\echo Carga inicial sintetica 232 registros
\ir modulos/carga/03_carga_inicial_4_2.sql
\ir modulos/carga/04_verificacion_carga_4_2.sql
\echo Catalogo IGP: requiere datos/igp_catalogo.csv descargado de la fuente oficial
\ir modulos/carga/05_importacion_igp_4_2.sql
\ir modulos/carga/06_verificacion_igp_4_2.sql
\echo Simulacion complementaria y validacion
\ir modulos/carga/07_simulacion_datos_4_3.sql
\ir modulos/carga/08_verificacion_simulacion_4_3.sql
