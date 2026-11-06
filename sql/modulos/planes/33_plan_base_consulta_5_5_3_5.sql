-- Proyecto Final - Seccion 5.3.5 - Consulta 5: plan base.
-- Ejecutar exclusivamente en bd_sismologico_exp_1000000 con psql.
-- Retira SOLO los dos indices experimentales de la Consulta 4.
-- No borra datos, restricciones, triggers ni archivos .dump.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Conectese primero a bd_sismologico_exp_1000000.';
    END IF;
    IF (SELECT COUNT(*) FROM estacion_sismica) <> 100
       OR (SELECT COUNT(*) FROM sensor) <> 300
       OR (SELECT COUNT(*) FROM lectura_onda) <> 875000
       OR (SELECT COUNT(*) FROM deteccion) <> 3500
       OR (SELECT COUNT(*) FROM evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM alerta) <> 1100 THEN
        RAISE EXCEPTION 'Los conteos no corresponden a la base experimental validada.';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname IN ('estacion_sismica', 'sensor', 'lectura_onda', 'deteccion')
          AND i.indexrelid NOT IN (
              COALESCE(to_regclass('monitoreo_sismologico.idx_det_evento_hora_c4')::oid, 0::oid),
              COALESCE(to_regclass('monitoreo_sismologico.idx_alerta_evento_hora_c4')::oid, 0::oid)
          )
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid = i.indexrelid AND c.contype IN ('p', 'u', 'x')
          )
    ) THEN
        RAISE EXCEPTION 'Existen indices secundarios inesperados; revise antes de continuar.';
    END IF;
END;
$$;

\echo
\echo === C5 - RESTABLECIMIENTO DEL ESCENARIO BASE ===
BEGIN;
DROP INDEX IF EXISTS monitoreo_sismologico.idx_det_evento_hora_c4;
DROP INDEX IF EXISTS monitoreo_sismologico.idx_alerta_evento_hora_c4;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname IN ('estacion_sismica','sensor','lectura_onda','deteccion')
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid = i.indexrelid AND c.contype IN ('p', 'u', 'x')
          )
    ) THEN
        RAISE EXCEPTION 'Todavia hay indices secundarios en las relaciones de la Consulta 5.';
    END IF;
END;
$$;
COMMIT;

\echo
\echo === C5 - INDICES OBLIGATORIOS DISPONIBLES ===
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename IN ('estacion_sismica', 'sensor', 'lectura_onda', 'deteccion')
ORDER BY tablename, indexname;

ANALYZE monitoreo_sismologico.estacion_sismica;
ANALYZE monitoreo_sismologico.sensor;
ANALYZE monitoreo_sismologico.lectura_onda;
ANALYZE monitoreo_sismologico.deteccion;

\echo
\echo === C5 - CONFIGURACION DEL PLANIFICADOR ===
SHOW work_mem;
SHOW enable_seqscan;
SHOW enable_indexscan;
SHOW enable_indexonlyscan;

\echo
\echo === C5 - PLAN REAL DE LA CONSULTA 5 SIN INDICES SECUNDARIOS ===
-- Consulta identica a la Consulta 5 del archivo 15_consultas_5_1.sql.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    s.id_sensor,
    s.numero_serie,
    e.codigo AS codigo_estacion,
    s.estado AS estado_sensor,
    COUNT(*) AS lecturas_periodo,
    COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
    MAX(l.fecha_hora) AS ultima_lectura
FROM sensor s
JOIN estacion_sismica e ON e.id_estacion = s.id_estacion
JOIN lectura_onda l ON l.id_sensor = s.id_sensor
WHERE l.fecha_hora >= TIMESTAMP '2026-08-01 00:00:00'
  AND l.fecha_hora < TIMESTAMP '2026-09-01 00:00:00'
  AND NOT EXISTS (
      SELECT 1
      FROM deteccion d
      WHERE d.id_sensor = s.id_sensor
        AND d.hora_deteccion >= TIMESTAMP '2026-08-01 00:00:00'
        AND d.hora_deteccion < TIMESTAMP '2026-09-01 00:00:00'
  )
GROUP BY s.id_sensor, s.numero_serie, e.codigo, s.estado
HAVING COUNT(*) >= 20
ORDER BY lecturas_invalidas DESC, lecturas_periodo DESC, s.id_sensor
LIMIT 15;

\echo
\echo === C5 - CONTROL DE LECTURAS Y DETECCIONES EN EL PERIODO ===
SELECT
    (SELECT COUNT(*) FROM lectura_onda) AS lecturas_totales,
    (SELECT COUNT(*) FROM lectura_onda
       WHERE fecha_hora >= TIMESTAMP '2026-08-01 00:00:00'
         AND fecha_hora < TIMESTAMP '2026-09-01 00:00:00') AS lecturas_agosto,
    (SELECT COUNT(*) FROM deteccion) AS detecciones_totales,
    (SELECT COUNT(*) FROM deteccion
       WHERE hora_deteccion >= TIMESTAMP '2026-08-01 00:00:00'
         AND hora_deteccion < TIMESTAMP '2026-09-01 00:00:00') AS detecciones_agosto;

\echo
\echo === C5 - DIAGNOSTICO BASE COMPLETO. UNA EJECUCION, NO UN PROMEDIO ===
