-- Consulta 1 - mediciones de cuatro escalas
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- Ejecutar UNA sola vez por conjunto de bases con estado inicial esperado. Modifica solo indices experimentales, no datos.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico_exp_1000
\ir ../modulos/mediciones/38_piloto_mediciones_c1_5_5.sql
\ir ../modulos/mediciones/39_piloto_mediciones_c1_con_indice_5_5.sql
\connect bd_sismologico_exp_10000
\ir ../modulos/mediciones/40_mediciones_c1_10000_5_5.sql
\connect bd_sismologico_exp_100000
\ir ../modulos/mediciones/41_mediciones_c1_100000_5_5.sql
\connect bd_sismologico_exp_1000000
\ir ../modulos/mediciones/42_mediciones_c1_1000000_5_5.sql
