-- ETAPA 7 - Demostracion reversible del millon (C1-C5)
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- REQUIERE base exp_1000000 al terminar la etapa 6 con indices C5. El script 62 hace ROLLBACK para dejar indices intactos.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico_exp_1000000
\ir modulos/demostracion/62_demostracion_video_1000000.sql
\connect bd_sismologico
