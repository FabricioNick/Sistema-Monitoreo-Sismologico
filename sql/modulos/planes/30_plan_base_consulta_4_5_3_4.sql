-- Proyecto Final - Seccion 5.3.4 / Consulta 4: diagnostico base.
-- Ejecutar en psql sobre bd_sismologico_exp_1000000.
-- Retira SOLAMENTE el indice secundario experimental de la Consulta 3.
-- No modifica datos, claves primarias, restricciones, triggers ni archivos .dump.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: use bd_sismologico_exp_1000000.';
    END IF;
    IF (SELECT COUNT(*) FROM evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM deteccion) <> 3500
       OR (SELECT COUNT(*) FROM alerta) <> 1100
       OR (SELECT COUNT(*) FROM lectura_onda) <> 875000 THEN
        RAISE EXCEPTION 'La distribucion no coincide con la escala verificada.';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname IN ('evento_sismico', 'deteccion', 'alerta', 'lectura_onda')
          AND i.indexrelid <> COALESCE(
               to_regclass('monitoreo_sismologico.idx_lectura_sensor_fecha_c3')::oid, 0::oid)
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid = i.indexrelid AND c.contype IN ('p', 'u', 'x')
          )
    ) THEN
        RAISE EXCEPTION 'Se detectaron indices secundarios inesperados. Revise antes de continuar.';
    END IF;
END;
$$;

\echo
\echo === C4 - RESTABLECER ESCENARIO BASE SIN INDICES SECUNDARIOS ===
DROP INDEX IF EXISTS monitoreo_sismologico.idx_lectura_sensor_fecha_c3;

\echo
\echo === C4 - INDICES OBLIGATORIOS EXISTENTES ===
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename IN ('evento_sismico', 'deteccion', 'alerta')
ORDER BY tablename, indexname;

ANALYZE monitoreo_sismologico.evento_sismico;
ANALYZE monitoreo_sismologico.deteccion;
ANALYZE monitoreo_sismologico.alerta;

\echo
\echo === C4 - PARAMETROS RELEVANTES ===
SHOW work_mem;
SHOW enable_seqscan;
SHOW enable_indexscan;
SHOW enable_indexonlyscan;

\echo
\echo === C4 - PLAN REAL SIN INDICES SECUNDARIOS ===
-- Consulta 4 identica a la seleccionada en el archivo 15_consultas_5_1.sql.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
WITH detecciones_resumen AS (
    SELECT id_evento, COUNT(*) AS total_detecciones,
           MIN(hora_deteccion) AS primera_deteccion
    FROM deteccion
    GROUP BY id_evento
), alertas_resumen AS (
    SELECT id_evento, COUNT(*) AS total_alertas,
           MIN(fecha_hora_emision) AS primera_alerta
    FROM alerta
    GROUP BY id_evento
)
SELECT
    ev.id_evento,
    ev.fecha_hora_origen,
    ev.magnitud,
    COALESCE(d.total_detecciones, 0) AS total_detecciones,
    COALESCE(a.total_alertas, 0) AS total_alertas,
    ROUND(EXTRACT(EPOCH FROM (d.primera_deteccion - ev.fecha_hora_origen))::NUMERIC, 2)
        AS segundos_primera_deteccion,
    ROUND(EXTRACT(EPOCH FROM (a.primera_alerta - ev.fecha_hora_origen))::NUMERIC, 2)
        AS segundos_primera_alerta
FROM evento_sismico ev
LEFT JOIN detecciones_resumen d ON d.id_evento = ev.id_evento
LEFT JOIN alertas_resumen a ON a.id_evento = ev.id_evento
WHERE (ev.id_evento BETWEEN 810000001 AND 810000008
    OR ev.id_evento BETWEEN 820300001 AND 820300030)
  AND (COALESCE(d.total_detecciones, 0) > 0
    OR COALESCE(a.total_alertas, 0) > 0)
ORDER BY ev.fecha_hora_origen DESC, ev.id_evento
LIMIT 15;

\echo
\echo === C4 - CONTROL DE INTEGRIDAD Y VOLUMEN EXPERIMENTAL ===
SELECT
    (SELECT COUNT(*) FROM evento_sismico) AS eventos,
    (SELECT COUNT(*) FROM deteccion) AS detecciones,
    (SELECT COUNT(*) FROM alerta) AS alertas,
    (SELECT COUNT(*) FROM deteccion d
       JOIN evento_sismico e ON e.id_evento = d.id_evento
       WHERE e.id_evento BETWEEN 200000000 AND 299999999) AS detecciones_sobre_igp,
    (SELECT COUNT(*) FROM alerta a
       JOIN evento_sismico e ON e.id_evento = a.id_evento
       WHERE e.id_evento BETWEEN 200000000 AND 299999999) AS alertas_sobre_igp;

\echo
\echo === C4 - DIAGNOSTICO BASE COMPLETADO. UNA EJECUCION, NO UN PROMEDIO ===
