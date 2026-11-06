-- Consulta 5 - mediciones de cuatro escalas
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- Ejecutar UNA sola vez por conjunto de bases con estado inicial esperado. Modifica solo indices experimentales, no datos.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico_exp_1000
\ir ../modulos/mediciones/55_mediciones_c5_1000_5_5.sql
\connect bd_sismologico_exp_10000
\ir ../modulos/mediciones/56_mediciones_c5_10000_5_5.sql
\connect bd_sismologico_exp_100000
\ir ../modulos/mediciones/57_mediciones_c5_100000_5_5.sql
\connect bd_sismologico_exp_1000000
\ir ../modulos/mediciones/58_mediciones_c5_1000000_5_5.sql
