-- Proyecto Final / Seccion 5.3.5 / Consulta 5.
-- Obtener plan real con ambos indices y comprobar equivalencia.
-- Ejecutar DESPUES del archivo 34 en la MISMA sesion de psql.
-- No modifica los registros ni fuerza el optimizador.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Conectese a bd_sismologico_exp_1000000.';
    END IF;
    IF to_regclass('monitoreo_sismologico.idx_lectura_sensor_hora_c5') IS NULL
       OR to_regclass('monitoreo_sismologico.idx_det_sensor_hora_c5') IS NULL THEN
        RAISE EXCEPTION 'Falta un indice candidato. Ejecute el archivo 34.';
    END IF;
    IF (SELECT COUNT(*) FROM estacion_sismica) <> 100
       OR (SELECT COUNT(*) FROM sensor) <> 300
       OR (SELECT COUNT(*) FROM evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM lectura_onda) <> 875000
       OR (SELECT COUNT(*) FROM deteccion) <> 3500
       OR (SELECT COUNT(*) FROM alerta) <> 1100 THEN
        RAISE EXCEPTION 'La base experimental tiene cantidades inesperadas.';
    END IF;
END;
$$;

\echo
\echo === C5 - PARAMETROS DEL PLANIFICADOR ===
SHOW work_mem;
SHOW enable_seqscan;
SHOW enable_indexscan;
SHOW enable_indexonlyscan;

\echo
\echo === C5 - PLAN REAL CON INDICES CANDIDATOS ===
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
\echo === C5 - FIRMA DE RESULTADOS CON INDICES ===
WITH resultado_consulta AS (
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
LIMIT 15
)
SELECT COUNT(*) AS filas_resultado,
       COALESCE(SUM(lecturas_periodo), 0) AS lecturas_top15,
       COALESCE(SUM(lecturas_invalidas), 0) AS invalidas_top15,
       MD5(COALESCE(STRING_AGG(TO_JSONB(r)::TEXT, '|' ORDER BY
           r.lecturas_invalidas DESC, r.lecturas_periodo DESC, r.id_sensor), '')) AS firma
FROM resultado_consulta r
\gset c5_indice_
\echo Filas: :c5_indice_filas_resultado
\echo Lecturas del top 15: :c5_indice_lecturas_top15
\echo Invalidas del top 15: :c5_indice_invalidas_top15
\echo Firma: :c5_indice_firma

\if :{?c5_base_firma}
SELECT CASE
    WHEN :'c5_base_firma' = :'c5_indice_firma'
     AND :c5_base_filas_resultado = :c5_indice_filas_resultado
     AND :c5_base_lecturas_top15 = :c5_indice_lecturas_top15
     AND :c5_base_invalidas_top15 = :c5_indice_invalidas_top15
    THEN 'OK' ELSE 'REVISAR'
END AS igualdad_resultados_base_indices;
\else
\echo AVISO: no se encontro la firma original. Ejecute 34 y 35 en la misma sesion de psql.
\endif

\echo
\echo === C5 - CONTROL DE CANTIDADES PERMANENTES ===
SELECT
    (SELECT COUNT(*) FROM estacion_sismica) AS estaciones,
    (SELECT COUNT(*) FROM sensor) AS sensores,
    (SELECT COUNT(*) FROM evento_sismico) AS eventos,
    (SELECT COUNT(*) FROM lectura_onda) AS lecturas,
    (SELECT COUNT(*) FROM deteccion) AS detecciones,
    (SELECT COUNT(*) FROM alerta) AS alertas;

\echo
\echo === C5 - DIAGNOSTICO CON INDICES (UNA EJECUCION, NO PROMEDIO) ===
