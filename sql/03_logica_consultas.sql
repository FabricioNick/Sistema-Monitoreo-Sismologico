-- ETAPA 3 - Vistas, procedimientos, triggers y cinco consultas
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- REQUIERE las etapas 1-2 realizadas. Pruebas de funciones y triggers usan transacciones reversibles.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico
\ir modulos/logica/09_vistas_4_4.sql
\ir modulos/logica/10_verificacion_vistas_4_4.sql
\ir modulos/logica/11_procedimientos_4_5.sql
\ir modulos/logica/12_pruebas_procedimientos_4_5.sql
\ir modulos/logica/13_triggers_4_6.sql
\ir modulos/logica/14_pruebas_triggers_4_6.sql
\ir modulos/consultas/15_consultas_5_1.sql
\ir modulos/consultas/16_verificacion_consultas_5_1.sql
