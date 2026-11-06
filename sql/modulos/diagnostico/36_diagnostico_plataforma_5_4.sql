-- Proyecto Final / Seccion 5.4 / Plataforma de pruebas.
-- Diagnostico de solo lectura. No altera bases, tablas, indices ni registros.
-- Ejecutar desde psql, preferentemente en bd_sismologico_exp_1000000.

\set ON_ERROR_STOP on
\pset pager off

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Conectese primero a bd_sismologico_exp_1000000.';
    END IF;
END;
$$;

\echo
\echo === 5.4 - SERVIDOR Y BASE ACTUAL ===
SELECT current_database() AS base_actual,
       current_setting('server_version') AS version_postgresql,
       version() AS compilacion_servidor;

\echo
\echo === 5.4 - CONFIGURACION DEL OPTIMIZADOR Y DE MEMORIA ===
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'shared_buffers', 'work_mem', 'maintenance_work_mem',
    'effective_cache_size', 'seq_page_cost', 'random_page_cost',
    'effective_io_concurrency', 'max_parallel_workers',
    'max_parallel_workers_per_gather', 'max_worker_processes',
    'enable_seqscan', 'enable_indexscan', 'enable_indexonlyscan',
    'enable_bitmapscan', 'jit', 'track_io_timing', 'block_size',
    'server_encoding', 'TimeZone'
)
ORDER BY name;

\echo
\echo === 5.4 - TAMANOS ACTUALES DE LAS BASES EXPERIMENTALES ===
SELECT datname AS base_experimental,
       pg_size_pretty(pg_database_size(oid)) AS tamano_actual
FROM pg_database
WHERE datname IN (
    'bd_sismologico_exp_1000',
    'bd_sismologico_exp_10000',
    'bd_sismologico_exp_100000',
    'bd_sismologico_exp_1000000'
)
ORDER BY pg_database_size(oid);

\echo
\echo === 5.4 - ESTADO ACTUAL DE LOS INDICES SECUNDARIOS EN EL MILLON ===
SELECT tablename, indexname, pg_size_pretty(pg_relation_size(format('%I.%I', schemaname, indexname)::regclass)) AS tamano
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND indexname IN (
    'idx_ev_igp_m6_fecha', 'idx_ev_igp_geo_c2',
    'idx_lectura_sensor_fecha_c3',
    'idx_det_evento_hora_c4', 'idx_alerta_evento_hora_c4',
    'idx_lectura_sensor_hora_c5', 'idx_det_sensor_hora_c5'
)
ORDER BY tablename, indexname;

\echo
\echo === FIN DEL DIAGNOSTICO: NO SE MODIFICARON DATOS ===
