-- Proyecto Final - Seccion 5.3.4 - Consulta 4.
-- Plan tras instalar los dos indices y control de equivalencia de resultados.
-- Ejecutar tras archivo 31, en la MISMA sesion de psql.
-- No fuerza el planificador ni modifica los datos.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Conectese primero a bd_sismologico_exp_1000000.';
    END IF;
    IF to_regclass('monitoreo_sismologico.idx_det_evento_hora_c4') IS NULL
       OR to_regclass('monitoreo_sismologico.idx_alerta_evento_hora_c4') IS NULL THEN
        RAISE EXCEPTION 'Falta algun indice candidato. Ejecute primero archivo 31.';
    END IF;
    IF (SELECT COUNT(*) FROM evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM deteccion) <> 3500
       OR (SELECT COUNT(*) FROM alerta) <> 1100 THEN
        RAISE EXCEPTION 'El volumen experimental ha cambiado inesperadamente.';
    END IF;
END;
$$;

\echo
\echo === C4 - PARAMETROS DEL PLANIFICADOR ===
SHOW work_mem;
SHOW enable_seqscan;
SHOW enable_indexscan;
SHOW enable_indexonlyscan;

\echo
\echo === C4 - PLAN REAL CON INDICES CANDIDATOS ===
-- Consulta 4 original del archivo 15_consultas_5_1.sql.
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
    ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
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
\echo === C4 - RESULTADOS Y FIRMA CON INDICES ===
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
), resultado_consulta AS (
    SELECT
        ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
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
    LIMIT 15
)
SELECT COUNT(*) AS filas_resultado,
       COALESCE(SUM(total_detecciones), 0) AS detecciones_top15,
       COALESCE(SUM(total_alertas), 0) AS alertas_top15,
       MD5(COALESCE(STRING_AGG(TO_JSONB(r)::text, '|'
           ORDER BY r.fecha_hora_origen DESC, r.id_evento), '')) AS firma
FROM resultado_consulta r
\gset c4_indice_
\echo Filas con indices: :c4_indice_filas_resultado
\echo Detecciones en top 15: :c4_indice_detecciones_top15
\echo Alertas en top 15: :c4_indice_alertas_top15
\echo Firma con indices: :c4_indice_firma

\if :{?c4_base_firma}
SELECT CASE WHEN
     :'c4_base_firma' = :'c4_indice_firma'
 AND :c4_base_filas_resultado = :c4_indice_filas_resultado
 AND :c4_base_detecciones_top15 = :c4_indice_detecciones_top15
 AND :c4_base_alertas_top15 = :c4_indice_alertas_top15
 THEN 'OK' ELSE 'REVISAR' END AS igualdad_resultados_base_indices;
\else
\echo AVISO: Falta la firma base de esta sesion. Ejecute los archivos 31 y 32 en la misma sesion.
\endif

\echo
\echo === C4 - CONTROL DEL VOLUMEN EXPERIMENTAL ===
SELECT
    (SELECT COUNT(*) FROM estacion_sismica) AS estaciones,
    (SELECT COUNT(*) FROM sensor) AS sensores,
    (SELECT COUNT(*) FROM evento_sismico) AS eventos,
    (SELECT COUNT(*) FROM lectura_onda) AS lecturas,
    (SELECT COUNT(*) FROM deteccion) AS detecciones,
    (SELECT COUNT(*) FROM alerta) AS alertas;

\echo
\echo === C4 - DIAGNOSTICO FINALIZADO: UNA EJECUCION, NO UN PROMEDIO ===
