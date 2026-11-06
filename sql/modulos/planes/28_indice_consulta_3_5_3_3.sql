-- Proyecto Final, Seccion 5.3.3, Consulta 3.
-- Indice candidato para lecturas agrupadas por estacion.
-- Ejecutar SOLO en bd_sismologico_exp_1000000, despues del archivo 27.
-- Conservar la misma sesion de psql para el archivo 29.
\set ON_ERROR_STOP on
\pset pager off
BEGIN;
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: use bd_sismologico_exp_1000000.';
    END IF;
    IF (SELECT COUNT(*) FROM lectura_onda) <> 875000
       OR (SELECT COUNT(*) FROM sensor) <> 300
       OR (SELECT COUNT(*) FROM estacion_sismica) <> 100 THEN
        RAISE EXCEPTION 'La base no coincide con el escenario verificado.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid=i.indrelid
        JOIN pg_namespace n ON n.oid=t.relnamespace
        WHERE n.nspname='monitoreo_sismologico'
          AND t.relname IN ('lectura_onda','sensor','estacion_sismica')
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid=i.indexrelid AND c.contype IN ('p','u','x')
          )
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios no previstos en las tablas C3.';
    END IF;
END;
$$;

\echo
\echo === C3 - PARAMETROS PARA LA COMPARACION ===
SHOW work_mem;
SHOW enable_seqscan;
SHOW enable_indexscan;
SHOW enable_indexonlyscan;

\echo
\echo === C3 - FIRMA DEL RESULTADO SIN INDICE SECUNDARIO ===
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
\gset c3_base_
\echo Estaciones: :c3_base_estaciones_resultado
\echo Lecturas agrupadas: :c3_base_lecturas_agrupadas
\echo Lecturas invalidas: :c3_base_invalidas_agrupadas
\echo Firma base: :c3_base_firma

\echo
\echo === C3 - INDICE CANDIDATO POR SENSOR Y FECHA ===
-- Diferente del UNIQUE obligatorio (id_sensor, fecha_hora, canal):
-- cubre es_valida para una posible lectura desde indice sin acceder al heap.
-- La fecha puede ser poco selectiva cuando todas las lecturas pertenecen al periodo.
CREATE INDEX idx_lectura_sensor_fecha_c3
ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora)
INCLUDE (es_valida);

ANALYZE monitoreo_sismologico.lectura_onda;

\echo
\echo === C3 - INDICES ACTUALES EN LECTURA_ONDA ===
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='monitoreo_sismologico'
  AND tablename='lectura_onda'
ORDER BY indexname;

\echo
\echo === C3 - TAMANO DEL INDICE CANDIDATO ===
SELECT pg_size_pretty(pg_relation_size(
    'monitoreo_sismologico.idx_lectura_sensor_fecha_c3'::regclass
)) AS espacio_indice_c3;

COMMIT;
\echo
\echo === C3 - INDICE CREADO; CONTINUAR CON ARCHIVO 29 ===
