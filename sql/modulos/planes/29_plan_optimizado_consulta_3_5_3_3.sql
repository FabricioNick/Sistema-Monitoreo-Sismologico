-- Proyecto Final, Seccion 5.3.3, Consulta 3.
-- Plan optimizado con indice candidato y verificacion de igualdad.
-- Ejecutar SOLO en bd_sismologico_exp_1000000 DESPUES del archivo 28.
-- No modifica datos ni ajustes del planificador.
\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: use bd_sismologico_exp_1000000.';
    END IF;
    IF to_regclass('monitoreo_sismologico.idx_lectura_sensor_fecha_c3') IS NULL THEN
        RAISE EXCEPTION 'Primero cree el indice ejecutando archivo 28.';
    END IF;
    IF (SELECT COUNT(*) FROM lectura_onda) <> 875000
       OR (SELECT COUNT(*) FROM sensor) <> 300
       OR (SELECT COUNT(*) FROM estacion_sismica) <> 100 THEN
        RAISE EXCEPTION 'Volumen experimental inesperado.';
    END IF;
END;
$$;

\echo
\echo === C3 - PARAMETROS DEL PLANIFICADOR ===
SHOW work_mem;
SHOW enable_seqscan;
SHOW enable_indexscan;
SHOW enable_indexonlyscan;

\echo
\echo === C3 - PLAN REAL CON INDICE SECUNDARIO ===
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
\echo === C3 - VERIFICACION DE RESULTADOS CON INDICE ===
WITH resultado_consulta AS (
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
ORDER BY porcentaje_invalidas DESC, total_lecturas DESC, e.id_estacion
)
SELECT
    COUNT(*) AS estaciones_resultado,
    COALESCE(SUM(total_lecturas),0) AS lecturas_agrupadas,
    COALESCE(SUM(lecturas_invalidas),0) AS invalidas_agrupadas,
    MD5(COALESCE(STRING_AGG(TO_JSONB(r)::text, '|' ORDER BY r.id_estacion), '')) AS firma
FROM resultado_consulta r
\gset c3_indice_
\echo Estaciones: :c3_indice_estaciones_resultado
\echo Lecturas agrupadas: :c3_indice_lecturas_agrupadas
\echo Lecturas invalidas: :c3_indice_invalidas_agrupadas
\echo Firma con indice: :c3_indice_firma

\if :{?c3_base_firma}
SELECT CASE WHEN
     :'c3_base_firma' = :'c3_indice_firma'
 AND :c3_base_estaciones_resultado = :c3_indice_estaciones_resultado
 AND :c3_base_lecturas_agrupadas = :c3_indice_lecturas_agrupadas
 AND :c3_base_invalidas_agrupadas = :c3_indice_invalidas_agrupadas
 THEN 'OK' ELSE 'REVISAR' END AS igualdad_resultados_base_indice;
\else
\echo AVISO: Falta la firma base en esta sesion. Ejecute los archivos 28 y 29 en la misma sesion.
\endif

\echo
\echo === C3 - CONTROL DEL VOLUMEN EXPERIMENTAL ===
SELECT
    (SELECT COUNT(*) FROM estacion_sismica) AS estaciones,
    (SELECT COUNT(*) FROM sensor) AS sensores,
    (SELECT COUNT(*) FROM lectura_onda) AS lecturas,
    (SELECT COUNT(*) FROM evento_sismico) AS eventos,
    (SELECT COUNT(*) FROM deteccion) AS detecciones,
    (SELECT COUNT(*) FROM alerta) AS alertas;

\echo
\echo === C3 - DIAGNOSTICO TERMINADO: UNA EJECUCION, NO PROMEDIO ===
