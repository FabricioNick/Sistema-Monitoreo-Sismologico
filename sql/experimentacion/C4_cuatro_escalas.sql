-- Consulta 4 - mediciones de cuatro escalas
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- Ejecutar UNA sola vez por conjunto de bases con estado inicial esperado. Modifica solo indices experimentales, no datos.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico_exp_1000
\ir ../modulos/mediciones/51_mediciones_c4_1000_5_5.sql
\connect bd_sismologico_exp_10000
\ir ../modulos/mediciones/52_mediciones_c4_10000_5_5.sql
\connect bd_sismologico_exp_100000
\ir ../modulos/mediciones/53_mediciones_c4_100000_5_5.sql
\connect bd_sismologico_exp_1000000
\ir ../modulos/mediciones/54_mediciones_c4_1000000_5_5.sql
