-- Proyecto Final - 5.3.3 / Consulta 3: diagnostico BASE.
-- Ejecutar SOLO en bd_sismologico_exp_1000000 con psql.
-- Se elimina exclusivamente el indice secundario experimental de C2.
-- No modifica datos, restricciones, triggers ni respaldos .dump.
-- Los indices de PRIMARY KEY y UNIQUE se mantienen.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

-- Rechazar bases incorrectas o cambios imprevistos en la distribucion.
-- Aceptar unicamente el indice C2 como indice secundario en las
-- tablas utilizadas para C3 o en evento_sismico (indice residual de C2).
DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: conectar a bd_sismologico_exp_1000000.';
    END IF;
    IF (SELECT COUNT(*) FROM monitoreo_sismologico.estacion_sismica) <> 100
       OR (SELECT COUNT(*) FROM monitoreo_sismologico.sensor) <> 300
       OR (SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda) <> 875000
       OR (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico) <> 120000 THEN
        RAISE EXCEPTION 'Distribucion distinta del escenario verificado de 1 000 000 filas.';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname IN ('estacion_sismica','sensor','lectura_onda','evento_sismico')
          AND i.indexrelid <> COALESCE(
              to_regclass('monitoreo_sismologico.idx_ev_igp_geo_c2')::oid, 0::oid)
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid = i.indexrelid AND c.contype IN ('p','u','x')
          )
    ) THEN
        RAISE EXCEPTION 'Existen indices secundarios adicionales: revisar antes del diagnostico C3.';
    END IF;
END;
$$;

\echo
\echo === C3 - RESTABLECER ESCENARIO SIN INDICES SECUNDARIOS ===
DROP INDEX IF EXISTS monitoreo_sismologico.idx_ev_igp_geo_c2;

\echo
\echo === C3 - INDICES EXISTENTES (SOLO PK Y UNIQUE) ===
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename IN ('estacion_sismica','sensor','lectura_onda')
ORDER BY tablename, indexname;

-- ANALYZE actualiza estadisticas sin modificar registros de usuario.
ANALYZE monitoreo_sismologico.estacion_sismica;
ANALYZE monitoreo_sismologico.sensor;
ANALYZE monitoreo_sismologico.lectura_onda;

\echo
\echo === C3 - PLAN REAL SIN INDICES SECUNDARIOS ===
-- Consulta identica a la C3 de 15_consultas_5_1.sql.
-- Se conserva fecha, agregacion, HAVING y ORDER BY.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    e.id_estacion,
    e.codigo AS codigo_estacion,
    COUNT(DISTINCT s.id_sensor) AS sensores_con_lecturas,
    COUNT(*) AS total_lecturas,
    COUNT(*) FILTER (WHERE l.es_valida) AS lecturas_validas,
    COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
    ROUND(100.0 * COUNT(*) FILTER (WHERE NOT l.es_valida)
          / NULLIF(COUNT(*), 0), 2) AS porcentaje_invalidas
FROM estacion_sismica e
JOIN sensor s ON s.id_estacion = e.id_estacion
JOIN lectura_onda l ON l.id_sensor = s.id_sensor
WHERE l.fecha_hora >= TIMESTAMP '2026-08-01 00:00:00'
  AND l.fecha_hora < TIMESTAMP '2026-12-01 00:00:00'
GROUP BY e.id_estacion, e.codigo
HAVING COUNT(*) >= 10
ORDER BY porcentaje_invalidas DESC, total_lecturas DESC, e.id_estacion;

\echo
\echo === C3 - CONTROL DE RESULTADOS EN ESCENARIO BASE ===
-- Es una comprobacion de volumen, no una prediccion de filas de salida.
SELECT
    (SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda) AS lecturas_totales,
    (SELECT COUNT(*) FROM monitoreo_sismologico.sensor) AS sensores_totales,
    (SELECT COUNT(*) FROM monitoreo_sismologico.estacion_sismica) AS estaciones_totales,
    (SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda
       WHERE fecha_hora >= TIMESTAMP '2026-08-01 00:00:00'
         AND fecha_hora < TIMESTAMP '2026-12-01 00:00:00') AS lecturas_en_periodo;

\echo
\echo === C3 - DIAGNOSTICO BASE COMPLETADO; NO ES PROMEDIO ===
