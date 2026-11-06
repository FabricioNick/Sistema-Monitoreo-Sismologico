-- Proyecto Final - Seccion 5.3.1
-- Diagnostico del plan BASE de la Consulta 1, SIN indices secundarios.
-- Ejecutar en psql conectado a bd_sismologico_exp_1000000.
-- No crea indices, no borra tablas y no cambia los datos.
-- Conservar la salida completa para comparar con el escenario optimizado.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

-- Detener la prueba si se utiliza otra base o si ya existe un indice
-- secundario sobre EVENTO_SISMICO que alteraria la linea base.
DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: %. Se requiere bd_sismologico_exp_1000000.', current_database();
    END IF;

    IF (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico) <> 120000 THEN
        RAISE EXCEPTION 'Cantidad inesperada en evento_sismico; no se ejecuta el diagnostico.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname = 'evento_sismico'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_constraint c
              WHERE c.conindid = i.indexrelid
                AND c.contype IN ('p', 'u', 'x')
          )
    ) THEN
        RAISE EXCEPTION 'Existen indices adicionales en evento_sismico; revisar antes de medir.';
    END IF;
END;
$$;

\echo
\echo === C1 - DIAGNOSTICO BASE / 1 000 000 REGISTROS ===
SELECT current_database() AS base_experimental,
       current_setting('server_version') AS version_postgresql;

\echo
\echo === INDICES YA EXISTENTES EN EVENTO_SISMICO ===
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename = 'evento_sismico'
ORDER BY indexname;

\echo
\echo === PARAMETROS RELEVANTES DEL PLANIFICADOR ===
SELECT name, setting, unit
FROM pg_settings
WHERE name IN (
    'work_mem', 'shared_buffers', 'effective_cache_size',
    'random_page_cost', 'seq_page_cost',
    'max_parallel_workers_per_gather', 'enable_seqscan', 'enable_indexscan'
)
ORDER BY name;

-- Las estadisticas se actualizaron tambien al construir la escala.
-- Ejecutar ANALYZE antes del diagnostico hace reproducible esta decision.
ANALYZE monitoreo_sismologico.evento_sismico;

\echo
\echo === PLAN REAL DE LA CONSULTA 1 (SIN INDICE SECUNDARIO) ===
-- Consulta identica a la Consulta 1 de 15_consultas_5_1.sql.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    EXTRACT(YEAR FROM ev.fecha_hora_origen)::INTEGER AS anio_utc,
    COUNT(*) AS cantidad_eventos,
    ROUND(AVG(ev.magnitud), 2) AS magnitud_promedio,
    MAX(ev.magnitud) AS magnitud_maxima,
    ROUND(AVG(ev.profundidad_km), 2) AS profundidad_promedio_km
FROM evento_sismico ev
WHERE ev.id_evento BETWEEN 200000000 AND 299999999
  AND ev.fecha_hora_origen >= TIMESTAMP '2010-01-01 00:00:00'
  AND ev.fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND ev.magnitud >= 6
GROUP BY EXTRACT(YEAR FROM ev.fecha_hora_origen)::INTEGER
HAVING COUNT(*) >= 1
ORDER BY anio_utc;

\echo
\echo === FIN DEL DIAGNOSTICO: CONSERVAR PLAN Y TIEMPOS ===
