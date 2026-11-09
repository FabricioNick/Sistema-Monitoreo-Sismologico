-- 07. Demostracion de las consultas C1-C5 con un millon de registros.
-- Control de condiciones y restablecimiento mediante ROLLBACK.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico_exp_1000000
\ir modulos/demostracion/62_demostracion_video_1000000.sql
\connect bd_sismologico
