-- ETAPA 5 - Planes base, indices candidatos y planes optimizados de C1-C5
-- PSQL: ejecutar desde la carpeta sql/; NO desde pgAdmin Query Tool.
-- REQUIERE base del millon VERIFICADA con solo indices obligatorios. Escribe y reemplaza indices secundarios experimentales; NO ejecutar en base de produccion.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico_exp_1000000
\ir modulos/planes/21_plan_base_consulta_1_5_3_1.sql
\ir modulos/planes/22_indice_consulta_1_5_3_1.sql
\ir modulos/planes/23_plan_optimizado_consulta_1_5_3_1.sql
\ir modulos/planes/24_plan_base_consulta_2_5_3_2.sql
\ir modulos/planes/25_indice_consulta_2_5_3_2.sql
\ir modulos/planes/26_plan_optimizado_consulta_2_5_3_2.sql
\ir modulos/planes/27_plan_base_consulta_3_5_3_3.sql
\ir modulos/planes/28_indice_consulta_3_5_3_3.sql
\ir modulos/planes/29_plan_optimizado_consulta_3_5_3_3.sql
\ir modulos/planes/30_plan_base_consulta_4_5_3_4.sql
\ir modulos/planes/31_indice_consulta_4_5_3_4.sql
\ir modulos/planes/32_plan_optimizado_consulta_4_5_3_4.sql
\ir modulos/planes/33_plan_base_consulta_5_5_3_5.sql
\ir modulos/planes/34_indices_consulta_5_5_3_5.sql
\ir modulos/planes/35_plan_optimizado_consulta_5_5_3_5.sql
\ir modulos/diagnostico/36_diagnostico_plataforma_5_4.sql
