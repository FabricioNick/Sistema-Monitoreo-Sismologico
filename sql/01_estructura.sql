-- ETAPA 1 - Estructura y pruebas de restricciones
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- SOLO en base principal NUEVA. La prueba se revierte con ROLLBACK.
\set ON_ERROR_STOP on
\pset pager off
\echo Etapa 1: crear seis tablas y verificar restricciones en bd_sismologico
\connect bd_sismologico
\ir modulos/esquema/01_creacion_tablas.sql
\ir modulos/esquema/02_pruebas_4_1.sql
\echo Etapa 1 terminada.
