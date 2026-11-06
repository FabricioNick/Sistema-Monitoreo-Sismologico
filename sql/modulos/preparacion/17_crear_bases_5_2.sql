-- Proyecto Final - Seccion 5.2: bases independientes para el experimento.
-- Ejecutar UNA vez en psql desde bd_sismologico. NO elimina bases.
-- Las bases nuevas permanecen independientes de bd_sismologico.
\set ON_ERROR_STOP on
\connect postgres

SELECT format('CREATE DATABASE %I', x.nombre)
FROM (VALUES
    ('bd_sismologico_exp_1000'),
    ('bd_sismologico_exp_10000'),
    ('bd_sismologico_exp_100000'),
    ('bd_sismologico_exp_1000000')
) AS x(nombre)
WHERE NOT EXISTS (SELECT 1 FROM pg_database p WHERE p.datname = x.nombre)
\gexec

SELECT datname AS base_experimental
FROM pg_database
WHERE datname IN (
    'bd_sismologico_exp_1000',
    'bd_sismologico_exp_10000',
    'bd_sismologico_exp_100000',
    'bd_sismologico_exp_1000000'
)
ORDER BY datname;
\connect bd_sismologico
