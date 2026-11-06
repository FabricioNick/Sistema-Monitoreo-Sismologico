-- ETAPA 4 - Crear, generar y verificar las cuatro bases experimentales
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- REQUIERE archivo datos/igp_catalogo.csv original. Crear y poblar CUATRO bases solo una vez; nunca ejecutar sobre bases con tablas existentes. No exporta dumps (usar herramientas/01_exportar_dumps.ps1).
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico
\ir modulos/preparacion/17_crear_bases_5_2.sql
\echo Preparando base experimental con 1000 registros
\connect bd_sismologico_exp_1000
\ir modulos/preparacion/18_generar_experimento_5_2.sql
\ir modulos/preparacion/19_verificar_experimento_5_2.sql
\echo Preparando base experimental con 10000 registros
\connect bd_sismologico_exp_10000
\ir modulos/preparacion/18_generar_experimento_5_2.sql
\ir modulos/preparacion/19_verificar_experimento_5_2.sql
\echo Preparando base experimental con 100000 registros
\connect bd_sismologico_exp_100000
\ir modulos/preparacion/18_generar_experimento_5_2.sql
\ir modulos/preparacion/19_verificar_experimento_5_2.sql
\echo Preparando base experimental con 1000000 registros
\connect bd_sismologico_exp_1000000
\ir modulos/preparacion/18_generar_experimento_5_2.sql
\ir modulos/preparacion/19_verificar_experimento_5_2.sql
\connect bd_sismologico
