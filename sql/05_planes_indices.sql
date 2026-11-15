-- 05. PLANES E INDICES

\set ON_ERROR_STOP on
\pset pager off
\timing off
\if :{?escala}
\else
\set escala 1000000
\endif
SELECT 1 / CASE WHEN :'escala' IN ('100','1000','10000','100000','1000000') THEN 1 ELSE 0 END AS escala_valida;
SELECT 'bd_sismologico_prueba_exp_' || :'escala' AS base_destino \gset
\connect :base_destino
SELECT set_config('sismo.planes_escala', :'escala', false) AS escala;

\echo
\echo === VALIDACION INICIAL ===
DO $validacion$
DECLARE
    v_escala INTEGER := current_setting('sismo.planes_escala')::INTEGER;
    v_tablas BIGINT[];
    v_esperado BIGINT[];
    v_igp INTEGER;
BEGIN
    IF current_database() <> 'bd_sismologico_prueba_exp_' || v_escala THEN
        RAISE EXCEPTION 'Base de datos incorrecta';
    END IF;

    SELECT ARRAY[
        (SELECT COUNT(*) FROM monitoreo_sismologico.estacion_sismica),
        (SELECT COUNT(*) FROM monitoreo_sismologico.sensor),
        (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico),
        (SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda),
        (SELECT COUNT(*) FROM monitoreo_sismologico.deteccion),
        (SELECT COUNT(*) FROM monitoreo_sismologico.alerta)
    ] INTO v_tablas;
    v_esperado := CASE v_escala
        WHEN 100 THEN ARRAY[2,6,45,34,8,5]::BIGINT[]
        WHEN 1000 THEN ARRAY[5,15,100,750,90,40]::BIGINT[]
        WHEN 10000 THEN ARRAY[10,30,2000,7550,300,110]::BIGINT[]
        WHEN 100000 THEN ARRAY[25,75,24000,74700,900,300]::BIGINT[]
        WHEN 1000000 THEN ARRAY[100,300,120000,875000,3500,1100]::BIGINT[]
    END;
    v_igp := CASE v_escala
        WHEN 100 THEN 5 WHEN 1000 THEN 50 WHEN 10000 THEN 800
        WHEN 100000 THEN 12000 WHEN 1000000 THEN 24289
    END;
    IF v_tablas IS DISTINCT FROM v_esperado THEN
        RAISE EXCEPTION 'Distribucion experimental incorrecta: %', v_tablas;
    END IF;
    IF (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico
        WHERE id_evento BETWEEN 200000000 AND 299999999) <> v_igp THEN
        RAISE EXCEPTION 'Catalogo IGP diferente del esperado';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico'
          AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios previos; no se modifico nada';
    END IF;
    RAISE NOTICE 'OK: % registros, % eventos IGP y sin indices secundarios',
        v_escala, v_igp;
END;
$validacion$;

BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

CREATE TEMP TABLE comparacion_planes (
    consulta TEXT PRIMARY KEY,
    filas_sin BIGINT NOT NULL,
    firma_sin TEXT NOT NULL,
    filas_con BIGINT,
    firma_con TEXT
) ON COMMIT DROP;

\echo
\echo === C1: ACTIVIDAD SISMICA ANUAL ===
\echo SIN INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
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

INSERT INTO comparacion_planes (consulta, filas_sin, firma_sin)
SELECT 'C1', COUNT(*),
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
FROM (
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
ORDER BY anio_utc
) AS t;

\echo INDICES CANDIDATOS
CREATE INDEX idx_ev_igp_m6_fecha
ON monitoreo_sismologico.evento_sismico (fecha_hora_origen)
INCLUDE (magnitud, profundidad_km)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND magnitud >= 6;
ANALYZE monitoreo_sismologico.evento_sismico;

\echo CON INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
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

UPDATE comparacion_planes
SET (filas_con, firma_con) = (
    SELECT COUNT(*),
           MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
    FROM (
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
ORDER BY anio_utc
    ) AS t
)
WHERE consulta = 'C1';

DROP INDEX monitoreo_sismologico.idx_ev_igp_m6_fecha;

\echo
\echo === C2: VENTANAS GEOGRAFICAS ===
\echo SIN INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
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

INSERT INTO comparacion_planes (consulta, filas_sin, firma_sin)
SELECT 'C2', COUNT(*),
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
FROM (
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
) AS t;

\echo INDICES CANDIDATOS
CREATE INDEX idx_ev_igp_geo_c2
ON monitoreo_sismologico.evento_sismico
    (latitud_epicentro, longitud_epicentro)
INCLUDE (magnitud)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00'
  AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND magnitud >= 5;
ANALYZE monitoreo_sismologico.evento_sismico;

\echo CON INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
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

UPDATE comparacion_planes
SET (filas_con, firma_con) = (
    SELECT COUNT(*),
           MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
    FROM (
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
    ) AS t
)
WHERE consulta = 'C2';

DROP INDEX monitoreo_sismologico.idx_ev_igp_geo_c2;

\echo
\echo === C3: CALIDAD DE LECTURAS ===
\echo SIN INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
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

INSERT INTO comparacion_planes (consulta, filas_sin, firma_sin)
SELECT 'C3', COUNT(*),
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
FROM (
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
) AS t;

\echo INDICES CANDIDATOS
CREATE INDEX idx_lectura_sensor_fecha_c3
ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora)
INCLUDE (es_valida);
ANALYZE monitoreo_sismologico.lectura_onda;

\echo CON INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
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

UPDATE comparacion_planes
SET (filas_con, firma_con) = (
    SELECT COUNT(*),
           MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
    FROM (
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
    ) AS t
)
WHERE consulta = 'C3';

DROP INDEX monitoreo_sismologico.idx_lectura_sensor_fecha_c3;

\echo
\echo === C4: SEGUIMIENTO DE DETECCIONES Y ALERTAS POR FECHA ===
\echo SIN INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
       d.total_detecciones, a.total_alertas,
       ROUND(EXTRACT(EPOCH FROM
           (d.primera_deteccion - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_deteccion,
       ROUND(EXTRACT(EPOCH FROM
           (a.primera_alerta - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_alerta
FROM evento_sismico ev
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_detecciones,
           MIN(hora_deteccion) AS primera_deteccion
    FROM deteccion d
    WHERE d.id_evento = ev.id_evento
) d ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_alertas,
           MIN(fecha_hora_emision) AS primera_alerta
    FROM alerta a
    WHERE a.id_evento = ev.id_evento
) a ON TRUE
WHERE ev.estado_revision = 'simulado'
  AND ev.fecha_hora_origen >= TIMESTAMP '2026-08-05 00:00:00'
  AND ev.fecha_hora_origen < TIMESTAMP '2026-08-06 00:00:00'
  AND (d.total_detecciones > 0 OR a.total_alertas > 0)
ORDER BY ev.fecha_hora_origen DESC, ev.id_evento
LIMIT 15;

INSERT INTO comparacion_planes (consulta, filas_sin, firma_sin)
SELECT 'C4', COUNT(*),
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
FROM (
SELECT ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
       d.total_detecciones, a.total_alertas,
       ROUND(EXTRACT(EPOCH FROM
           (d.primera_deteccion - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_deteccion,
       ROUND(EXTRACT(EPOCH FROM
           (a.primera_alerta - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_alerta
FROM evento_sismico ev
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_detecciones,
           MIN(hora_deteccion) AS primera_deteccion
    FROM deteccion d
    WHERE d.id_evento = ev.id_evento
) d ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_alertas,
           MIN(fecha_hora_emision) AS primera_alerta
    FROM alerta a
    WHERE a.id_evento = ev.id_evento
) a ON TRUE
WHERE ev.estado_revision = 'simulado'
  AND ev.fecha_hora_origen >= TIMESTAMP '2026-08-05 00:00:00'
  AND ev.fecha_hora_origen < TIMESTAMP '2026-08-06 00:00:00'
  AND (d.total_detecciones > 0 OR a.total_alertas > 0)
ORDER BY ev.fecha_hora_origen DESC, ev.id_evento
LIMIT 15
) AS t;

\echo INDICES CANDIDATOS
CREATE INDEX idx_evento_fecha_c4
    ON monitoreo_sismologico.evento_sismico (fecha_hora_origen) INCLUDE (magnitud, estado_revision);
CREATE INDEX idx_deteccion_evento_hora_c4
    ON monitoreo_sismologico.deteccion (id_evento, hora_deteccion);
CREATE INDEX idx_alerta_evento_hora_c4
    ON monitoreo_sismologico.alerta (id_evento, fecha_hora_emision);
ANALYZE monitoreo_sismologico.evento_sismico;
ANALYZE monitoreo_sismologico.deteccion;
ANALYZE monitoreo_sismologico.alerta;

\echo CON INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
       d.total_detecciones, a.total_alertas,
       ROUND(EXTRACT(EPOCH FROM
           (d.primera_deteccion - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_deteccion,
       ROUND(EXTRACT(EPOCH FROM
           (a.primera_alerta - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_alerta
FROM evento_sismico ev
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_detecciones,
           MIN(hora_deteccion) AS primera_deteccion
    FROM deteccion d
    WHERE d.id_evento = ev.id_evento
) d ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_alertas,
           MIN(fecha_hora_emision) AS primera_alerta
    FROM alerta a
    WHERE a.id_evento = ev.id_evento
) a ON TRUE
WHERE ev.estado_revision = 'simulado'
  AND ev.fecha_hora_origen >= TIMESTAMP '2026-08-05 00:00:00'
  AND ev.fecha_hora_origen < TIMESTAMP '2026-08-06 00:00:00'
  AND (d.total_detecciones > 0 OR a.total_alertas > 0)
ORDER BY ev.fecha_hora_origen DESC, ev.id_evento
LIMIT 15;

UPDATE comparacion_planes
SET (filas_con, firma_con) = (
    SELECT COUNT(*),
           MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
    FROM (
SELECT ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
       d.total_detecciones, a.total_alertas,
       ROUND(EXTRACT(EPOCH FROM
           (d.primera_deteccion - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_deteccion,
       ROUND(EXTRACT(EPOCH FROM
           (a.primera_alerta - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_alerta
FROM evento_sismico ev
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_detecciones,
           MIN(hora_deteccion) AS primera_deteccion
    FROM deteccion d
    WHERE d.id_evento = ev.id_evento
) d ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_alertas,
           MIN(fecha_hora_emision) AS primera_alerta
    FROM alerta a
    WHERE a.id_evento = ev.id_evento
) a ON TRUE
WHERE ev.estado_revision = 'simulado'
  AND ev.fecha_hora_origen >= TIMESTAMP '2026-08-05 00:00:00'
  AND ev.fecha_hora_origen < TIMESTAMP '2026-08-06 00:00:00'
  AND (d.total_detecciones > 0 OR a.total_alertas > 0)
ORDER BY ev.fecha_hora_origen DESC, ev.id_evento
LIMIT 15
    ) AS t
)
WHERE consulta = 'C4';

DROP INDEX monitoreo_sismologico.idx_evento_fecha_c4;
DROP INDEX monitoreo_sismologico.idx_deteccion_evento_hora_c4;
DROP INDEX monitoreo_sismologico.idx_alerta_evento_hora_c4;

\echo
\echo === C5: SENSORES SIN DETECCIONES EN UNA VENTANA DE LECTURAS ===
\echo SIN INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT s.id_sensor, s.numero_serie, e.codigo AS codigo_estacion,
       COUNT(*) AS lecturas_periodo,
       COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
       ROUND(AVG(ABS(l.valor)), 6) AS amplitud_media_absoluta,
       MAX(l.fecha_hora) AS ultima_lectura
FROM lectura_onda l
JOIN sensor s ON s.id_sensor = l.id_sensor
JOIN estacion_sismica e ON e.id_estacion = s.id_estacion
WHERE l.fecha_hora >= TIMESTAMP '2026-08-05 00:00:00'
  AND l.fecha_hora < TIMESTAMP '2026-08-06 00:00:00'
  AND NOT EXISTS (
      SELECT 1 FROM deteccion d
      WHERE d.id_sensor = s.id_sensor
        AND d.hora_deteccion >= TIMESTAMP '2026-08-05 00:00:00'
        AND d.hora_deteccion < TIMESTAMP '2026-08-06 00:00:00'
  )
GROUP BY s.id_sensor, s.numero_serie, e.codigo
HAVING COUNT(*) >= 1
ORDER BY lecturas_invalidas DESC,
         lecturas_periodo DESC, s.id_sensor
LIMIT 15;

INSERT INTO comparacion_planes (consulta, filas_sin, firma_sin)
SELECT 'C5', COUNT(*),
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
FROM (
SELECT s.id_sensor, s.numero_serie, e.codigo AS codigo_estacion,
       COUNT(*) AS lecturas_periodo,
       COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
       ROUND(AVG(ABS(l.valor)), 6) AS amplitud_media_absoluta,
       MAX(l.fecha_hora) AS ultima_lectura
FROM lectura_onda l
JOIN sensor s ON s.id_sensor = l.id_sensor
JOIN estacion_sismica e ON e.id_estacion = s.id_estacion
WHERE l.fecha_hora >= TIMESTAMP '2026-08-05 00:00:00'
  AND l.fecha_hora < TIMESTAMP '2026-08-06 00:00:00'
  AND NOT EXISTS (
      SELECT 1 FROM deteccion d
      WHERE d.id_sensor = s.id_sensor
        AND d.hora_deteccion >= TIMESTAMP '2026-08-05 00:00:00'
        AND d.hora_deteccion < TIMESTAMP '2026-08-06 00:00:00'
  )
GROUP BY s.id_sensor, s.numero_serie, e.codigo
HAVING COUNT(*) >= 1
ORDER BY lecturas_invalidas DESC,
         lecturas_periodo DESC, s.id_sensor
LIMIT 15
) AS t;

\echo INDICES CANDIDATOS
CREATE INDEX idx_lectura_fecha_sensor_c5
    ON monitoreo_sismologico.lectura_onda (fecha_hora, id_sensor) INCLUDE (es_valida, valor);
CREATE INDEX idx_deteccion_sensor_hora_c5
    ON monitoreo_sismologico.deteccion (id_sensor, hora_deteccion);
ANALYZE monitoreo_sismologico.lectura_onda;
ANALYZE monitoreo_sismologico.deteccion;

\echo CON INDICE
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT s.id_sensor, s.numero_serie, e.codigo AS codigo_estacion,
       COUNT(*) AS lecturas_periodo,
       COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
       ROUND(AVG(ABS(l.valor)), 6) AS amplitud_media_absoluta,
       MAX(l.fecha_hora) AS ultima_lectura
FROM lectura_onda l
JOIN sensor s ON s.id_sensor = l.id_sensor
JOIN estacion_sismica e ON e.id_estacion = s.id_estacion
WHERE l.fecha_hora >= TIMESTAMP '2026-08-05 00:00:00'
  AND l.fecha_hora < TIMESTAMP '2026-08-06 00:00:00'
  AND NOT EXISTS (
      SELECT 1 FROM deteccion d
      WHERE d.id_sensor = s.id_sensor
        AND d.hora_deteccion >= TIMESTAMP '2026-08-05 00:00:00'
        AND d.hora_deteccion < TIMESTAMP '2026-08-06 00:00:00'
  )
GROUP BY s.id_sensor, s.numero_serie, e.codigo
HAVING COUNT(*) >= 1
ORDER BY lecturas_invalidas DESC,
         lecturas_periodo DESC, s.id_sensor
LIMIT 15;

UPDATE comparacion_planes
SET (filas_con, firma_con) = (
    SELECT COUNT(*),
           MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, '|' ORDER BY TO_JSONB(t)::TEXT), ''))
    FROM (
SELECT s.id_sensor, s.numero_serie, e.codigo AS codigo_estacion,
       COUNT(*) AS lecturas_periodo,
       COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
       ROUND(AVG(ABS(l.valor)), 6) AS amplitud_media_absoluta,
       MAX(l.fecha_hora) AS ultima_lectura
FROM lectura_onda l
JOIN sensor s ON s.id_sensor = l.id_sensor
JOIN estacion_sismica e ON e.id_estacion = s.id_estacion
WHERE l.fecha_hora >= TIMESTAMP '2026-08-05 00:00:00'
  AND l.fecha_hora < TIMESTAMP '2026-08-06 00:00:00'
  AND NOT EXISTS (
      SELECT 1 FROM deteccion d
      WHERE d.id_sensor = s.id_sensor
        AND d.hora_deteccion >= TIMESTAMP '2026-08-05 00:00:00'
        AND d.hora_deteccion < TIMESTAMP '2026-08-06 00:00:00'
  )
GROUP BY s.id_sensor, s.numero_serie, e.codigo
HAVING COUNT(*) >= 1
ORDER BY lecturas_invalidas DESC,
         lecturas_periodo DESC, s.id_sensor
LIMIT 15
    ) AS t
)
WHERE consulta = 'C5';

DROP INDEX monitoreo_sismologico.idx_lectura_fecha_sensor_c5;
DROP INDEX monitoreo_sismologico.idx_deteccion_sensor_hora_c5;

\echo === EQUIVALENCIA DE RESULTADOS ===
SELECT consulta, filas_sin, filas_con,
       CASE WHEN filas_sin = filas_con AND firma_sin = firma_con
            THEN 'OK' ELSE 'ERROR' END AS resultado
FROM comparacion_planes
ORDER BY consulta;

DO $control$
BEGIN
    IF (SELECT COUNT(*) FROM comparacion_planes) <> 5
       OR EXISTS (
          SELECT 1 FROM comparacion_planes
          WHERE filas_con IS NULL OR firma_con IS NULL
             OR filas_sin <> filas_con OR firma_sin <> firma_con
       ) THEN
        RAISE EXCEPTION 'Diferencia en los resultados de las consultas';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico'
          AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'Quedaron indices secundarios temporales';
    END IF;

    RAISE NOTICE 'OK: cinco consultas equivalentes; indices candidatos retirados';
END;
$control$;

\echo
\echo === RESTAURAR ESTADO INICIAL ===
ROLLBACK;

\echo
\echo === COMPROBACION FINAL ===
DO $final$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico'
          AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios tras ROLLBACK';
    END IF;
    RAISE NOTICE 'OK: indices originales preservados';
END;
$final$;

\echo === ETAPA 5 FINALIZADA ===
