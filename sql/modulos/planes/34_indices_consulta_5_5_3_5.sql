-- Proyecto Final / Seccion 5.3.5 / Consulta 5.
-- Registrar la firma base y crear indices candidatos, sin modificar registros.
-- Ejecutar SOLO en bd_sismologico_exp_1000000 tras el archivo 33.
-- Ejecutar el archivo 35 en la MISMA sesion de psql.

\set ON_ERROR_STOP on
\pset pager off
BEGIN;
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Conectese a bd_sismologico_exp_1000000.';
    END IF;
    IF (SELECT COUNT(*) FROM estacion_sismica) <> 100
       OR (SELECT COUNT(*) FROM sensor) <> 300
       OR (SELECT COUNT(*) FROM evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM lectura_onda) <> 875000
       OR (SELECT COUNT(*) FROM deteccion) <> 3500
       OR (SELECT COUNT(*) FROM alerta) <> 1100 THEN
        RAISE EXCEPTION 'El volumen experimental difiere del verificado.';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname IN ('estacion_sismica','sensor','lectura_onda','deteccion')
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid = i.indexrelid AND c.contype IN ('p','u','x')
          )
    ) THEN
        RAISE EXCEPTION 'Existen indices secundarios: revise antes de ejecutar archivo 34.';
    END IF;
END;
$$;

\echo
\echo === C5 - PARAMETROS SIN CAMBIOS ===
SHOW work_mem;
SHOW enable_seqscan;
SHOW enable_indexscan;
SHOW enable_indexonlyscan;

\echo
\echo === C5 - FIRMA DEL RESULTADO ORIGINAL ===
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
\gset c5_base_
\echo Filas: :c5_base_filas_resultado
\echo Lecturas del top 15: :c5_base_lecturas_top15
\echo Invalidas del top 15: :c5_base_invalidas_top15
\echo Firma: :c5_base_firma

\echo
\echo === C5 - CREACION DE INDICES CANDIDATOS ===
-- El primero cubre busqueda por sensor, fecha y validez sin leer el heap
-- cuando el planificador considere conveniente un Index Only Scan.
-- Existe un UNIQUE obligatorio (id_sensor, fecha_hora, canal): se mide
-- el coste de almacenamiento adicional y posible solapamiento.
CREATE INDEX idx_lectura_sensor_hora_c5
    ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora)
    INCLUDE (es_valida);

-- El segundo se enfoca en el NOT EXISTS por sensor y hora de deteccion.
-- No sustituye la PK compuesta (id_sensor, id_evento).
CREATE INDEX idx_det_sensor_hora_c5
    ON monitoreo_sismologico.deteccion (id_sensor, hora_deteccion);

ANALYZE monitoreo_sismologico.lectura_onda;
ANALYZE monitoreo_sismologico.deteccion;

\echo
\echo === C5 - INDICES SOBRE LECTURA_ONDA Y DETECCION ===
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename IN ('lectura_onda','deteccion')
ORDER BY tablename, indexname;

\echo
\echo === C5 - ESPACIO DE LOS DOS INDICES ===
SELECT 'lectura_onda' AS tabla,
       pg_size_pretty(pg_relation_size('monitoreo_sismologico.idx_lectura_sensor_hora_c5'::regclass)) AS tamano
UNION ALL
SELECT 'deteccion',
       pg_size_pretty(pg_relation_size('monitoreo_sismologico.idx_det_sensor_hora_c5'::regclass));

COMMIT;
\echo
\echo === C5 - CONTINUAR CON ARCHIVO 35 EN LA MISMA SESION ===
