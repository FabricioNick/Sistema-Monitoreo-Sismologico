-- Proyecto Final - 5.3.2 / Consulta 2: plan con indice y validacion.
-- Ejecutar SOLO en bd_sismologico_exp_1000000, tras archivo 25.
-- No fuerza el planificador ni modifica filas ni indices.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Conectar primero a bd_sismologico_exp_1000000.';
    END IF;
    IF to_regclass('monitoreo_sismologico.idx_ev_igp_geo_c2') IS NULL THEN
        RAISE EXCEPTION 'No existe idx_ev_igp_geo_c2. Ejecutar antes archivo 25.';
    END IF;
    IF (SELECT COUNT(*) FROM evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM estacion_sismica) <> 100 THEN
        RAISE EXCEPTION 'La base experimental no tiene la distribucion esperada.';
    END IF;
END;
$$;

\echo
\echo === C2 - PLAN REAL CON INDICE GEOGRAFICO CANDIDATO ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT
    e.id_estacion,
    e.codigo AS codigo_estacion,
    e.nombre AS nombre_estacion,
    COUNT(*) AS eventos_en_ventana,
    ROUND(AVG(ev.magnitud), 2) AS magnitud_promedio,
    MAX(ev.magnitud) AS magnitud_maxima
FROM estacion_sismica e
JOIN evento_sismico ev
  ON ev.latitud_epicentro BETWEEN e.latitud - 1.5 AND e.latitud + 1.5
 AND ev.longitud_epicentro BETWEEN e.longitud - 1.5 AND e.longitud + 1.5
WHERE ev.id_evento BETWEEN 200000000 AND 299999999
  AND ev.fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00'
  AND ev.fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND ev.magnitud >= 5
GROUP BY e.id_estacion, e.codigo, e.nombre
HAVING COUNT(*) >= 1
ORDER BY eventos_en_ventana DESC, e.id_estacion
LIMIT 10;

\echo
\echo === C2 - RESULTADOS Y FIRMA CON INDICE ===
WITH resultado_consulta AS (
SELECT
    e.id_estacion,
    e.codigo AS codigo_estacion,
    e.nombre AS nombre_estacion,
    COUNT(*) AS eventos_en_ventana,
    ROUND(AVG(ev.magnitud), 2) AS magnitud_promedio,
    MAX(ev.magnitud) AS magnitud_maxima
FROM estacion_sismica e
JOIN evento_sismico ev
  ON ev.latitud_epicentro BETWEEN e.latitud - 1.5 AND e.latitud + 1.5
 AND ev.longitud_epicentro BETWEEN e.longitud - 1.5 AND e.longitud + 1.5
WHERE ev.id_evento BETWEEN 200000000 AND 299999999
  AND ev.fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00'
  AND ev.fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND ev.magnitud >= 5
GROUP BY e.id_estacion, e.codigo, e.nombre
HAVING COUNT(*) >= 1
ORDER BY eventos_en_ventana DESC, e.id_estacion
LIMIT 10
)
SELECT
    COUNT(*) AS filas_resultado,
    COALESCE(SUM(eventos_en_ventana),0) AS coincidencias_en_top10,
    MD5(COALESCE(STRING_AGG(TO_JSONB(r)::text, '|' ORDER BY eventos_en_ventana DESC, id_estacion),'')) AS firma
FROM resultado_consulta r
\gset c2_indice_
\echo Filas: :c2_indice_filas_resultado
\echo Coincidencias en top 10: :c2_indice_coincidencias_en_top10
\echo Firma con indice: :c2_indice_firma

-- Si se ejecutan los dos archivos en la misma sesion de psql, se
-- compara tambien la firma de salida contra el escenario base.
\if :{?c2_base_firma}
SELECT
    CASE WHEN :'c2_base_firma' = :'c2_indice_firma'
         AND :c2_base_filas_resultado = :c2_indice_filas_resultado
         AND :c2_base_coincidencias_en_top10 = :c2_indice_coincidencias_en_top10
         THEN 'OK' ELSE 'REVISAR' END AS igualdad_resultados_base_indice;
\else
\echo AVISO: firma base no disponible en esta sesion; compare firmas manualmente.
\endif

\echo
\echo === C2 - CONTROL DEL VOLUMEN EXPERIMENTAL ===
SELECT
    (SELECT COUNT(*) FROM estacion_sismica) AS estaciones,
    (SELECT COUNT(*) FROM evento_sismico) AS eventos,
    (SELECT COUNT(*) FROM sensor) AS sensores,
    (SELECT COUNT(*) FROM lectura_onda) AS lecturas,
    (SELECT COUNT(*) FROM deteccion) AS detecciones,
    (SELECT COUNT(*) FROM alerta) AS alertas;

\echo
\echo === C2 - DIAGNOSTICO CON INDICE TERMINADO; NO ES PROMEDIO ===
