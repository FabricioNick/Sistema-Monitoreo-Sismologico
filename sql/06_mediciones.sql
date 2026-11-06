-- ETAPA 6 - Cinco consultas x cuatro escalas x dos escenarios
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- EJECUTAR SOLO en las cuatro bases exp_* listas para mediciones, sin indices secundarios excepto los esperados al comenzar. Genera 21 CSV (piloto y 20 comparaciones) en resultados/. NO reejecutar en bases ya utilizadas.
\set ON_ERROR_STOP on
\pset pager off
\ir experimentacion/C1_cuatro_escalas.sql
\ir experimentacion/C2_cuatro_escalas.sql
\ir experimentacion/C3_cuatro_escalas.sql
\ir experimentacion/C4_cuatro_escalas.sql
\ir experimentacion/C5_cuatro_escalas.sql
\connect bd_sismologico
