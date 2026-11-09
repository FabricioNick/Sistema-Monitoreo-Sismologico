-- 07. Demostracion de las consultas C1-C5 con un millon de registros.
-- Control de condiciones y restablecimiento mediante ROLLBACK.
\set ON_ERROR_STOP on
\pset pager off
\connect bd_sismologico_exp_1000000
-- 62. Comparacion de planes C1-C5 para un millon de registros.
-- Consultas equivalentes a las empleadas en las mediciones experimentales.
-- Una ejecucion ilustrativa por condicion, sin reemplazar las series de medicion.
-- Los cambios transitorios de indices se revierten mediante ROLLBACK.

\set ON_ERROR_STOP on
\pset pager off
\timing off

DO $guard$
DECLARE v_total BIGINT;
BEGIN
  IF current_database() <> 'bd_sismologico_exp_1000000' THEN
    RAISE EXCEPTION 'Base incorrecta: conectar a bd_sismologico_exp_1000000';
  END IF;
  SELECT (SELECT count(*) FROM monitoreo_sismologico.estacion_sismica)
       + (SELECT count(*) FROM monitoreo_sismologico.sensor)
       + (SELECT count(*) FROM monitoreo_sismologico.evento_sismico)
       + (SELECT count(*) FROM monitoreo_sismologico.lectura_onda)
       + (SELECT count(*) FROM monitoreo_sismologico.deteccion)
       + (SELECT count(*) FROM monitoreo_sismologico.alerta) INTO v_total;
  IF v_total <> 1000000
     OR (SELECT count(*) FROM monitoreo_sismologico.estacion_sismica) <> 100
     OR (SELECT count(*) FROM monitoreo_sismologico.sensor) <> 300
     OR (SELECT count(*) FROM monitoreo_sismologico.evento_sismico) <> 120000
     OR (SELECT count(*) FROM monitoreo_sismologico.lectura_onda) <> 875000
     OR (SELECT count(*) FROM monitoreo_sismologico.deteccion) <> 3500
     OR (SELECT count(*) FROM monitoreo_sismologico.alerta) <> 1100 THEN
    RAISE EXCEPTION 'Distribucion distinta de la base de un millon';
  END IF;
  IF to_regclass('monitoreo_sismologico.idx_lectura_sensor_hora_c5') IS NULL
     OR to_regclass('monitoreo_sismologico.idx_det_sensor_hora_c5') IS NULL THEN
    RAISE EXCEPTION 'No se cumple la condicion inicial de los indices experimentales C5';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_index i
    JOIN pg_class t ON t.oid=i.indrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    JOIN pg_class ix ON ix.oid=i.indexrelid
    LEFT JOIN pg_constraint c ON c.conindid=i.indexrelid
    WHERE n.nspname='monitoreo_sismologico' AND c.oid IS NULL
      AND ix.relname NOT IN ('idx_lectura_sensor_hora_c5','idx_det_sensor_hora_c5')
  ) THEN
    RAISE EXCEPTION 'Hay indices secundarios inesperados; no se cambio nada';
  END IF;
  RAISE NOTICE 'VERIFICADO: 1000000 registros y solo dos indices C5 originales de las pruebas';
END;
$guard$;

\echo
\echo === A. RESUMEN DEL MILLON DE REGISTROS ===
SELECT 'estacion_sismica' AS tabla, count(*) FROM monitoreo_sismologico.estacion_sismica
UNION ALL SELECT 'sensor', count(*) FROM monitoreo_sismologico.sensor
UNION ALL SELECT 'evento_sismico', count(*) FROM monitoreo_sismologico.evento_sismico
UNION ALL SELECT 'lectura_onda', count(*) FROM monitoreo_sismologico.lectura_onda
UNION ALL SELECT 'deteccion', count(*) FROM monitoreo_sismologico.deteccion
UNION ALL SELECT 'alerta', count(*) FROM monitoreo_sismologico.alerta;

\echo
\echo === B. ESCENARIOS REVERSIBLES DENTRO DE TRANSACCION ===
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;
DROP INDEX monitoreo_sismologico.idx_lectura_sensor_hora_c5;
DROP INDEX monitoreo_sismologico.idx_det_sensor_hora_c5;

DO $check$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_index i
    JOIN pg_class t ON t.oid=i.indrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    LEFT JOIN pg_constraint c ON c.conindid=i.indexrelid
    WHERE n.nspname='monitoreo_sismologico' AND c.oid IS NULL
  ) THEN RAISE EXCEPTION 'Aun hay indices secundarios en la condicion de referencia';
  END IF;
END;
$check$;

CREATE TEMP TABLE evidencia_video_62 (
  consulta TEXT NOT NULL,
  escenario TEXT NOT NULL,
  execution_ms NUMERIC NOT NULL,
  shared_hit BIGINT,
  shared_read BIGINT,
  temp_read BIGINT,
  temp_written BIGINT,
  indice_usado TEXT NOT NULL,
  PRIMARY KEY(consulta,escenario)
) ON COMMIT DROP;

DO $demo$
DECLARE
    v_queries TEXT[] := ARRAY[
      $consulta_1$SELECT
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
ORDER BY anio_utc$consulta_1$,
      $consulta_2$SELECT
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
LIMIT 10$consulta_2$,
      $consulta_3$SELECT
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
ORDER BY porcentaje_invalidas DESC, total_lecturas DESC, e.id_estacion$consulta_3$,
      $consulta_4$WITH detecciones_resumen AS (
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
LIMIT 15$consulta_4$,
      $consulta_5$SELECT
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
LIMIT 15$consulta_5$
    ];
    v_idx TEXT[][] := ARRAY[
      ARRAY['idx_ev_igp_m6_fecha',''],
      ARRAY['idx_ev_igp_geo_c2',''],
      ARRAY['idx_lectura_sensor_fecha_c3',''],
      ARRAY['idx_det_evento_hora_c4','idx_alerta_evento_hora_c4'],
      ARRAY['idx_lectura_sensor_hora_c5','idx_det_sensor_hora_c5']
    ];
    v_idx_ddl TEXT[][] := ARRAY[
      ARRAY[$ddl_1_1$CREATE INDEX idx_ev_igp_m6_fecha ON monitoreo_sismologico.evento_sismico (fecha_hora_origen) INCLUDE (magnitud, profundidad_km) WHERE id_evento BETWEEN 200000000 AND 299999999 AND magnitud >= 6$ddl_1_1$, $ddl_1_2$$ddl_1_2$],
      ARRAY[$ddl_2_1$CREATE INDEX idx_ev_igp_geo_c2 ON monitoreo_sismologico.evento_sismico (latitud_epicentro, longitud_epicentro) INCLUDE (magnitud) WHERE id_evento BETWEEN 200000000 AND 299999999 AND fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00' AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00' AND magnitud >= 5$ddl_2_1$, $ddl_2_2$$ddl_2_2$],
      ARRAY[$ddl_3_1$CREATE INDEX idx_lectura_sensor_fecha_c3 ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora) INCLUDE (es_valida)$ddl_3_1$, $ddl_3_2$$ddl_3_2$],
      ARRAY[$ddl_4_1$CREATE INDEX idx_det_evento_hora_c4 ON monitoreo_sismologico.deteccion (id_evento, hora_deteccion)$ddl_4_1$, $ddl_4_2$CREATE INDEX idx_alerta_evento_hora_c4 ON monitoreo_sismologico.alerta (id_evento, fecha_hora_emision)$ddl_4_2$],
      ARRAY[$ddl_5_1$CREATE INDEX idx_lectura_sensor_hora_c5 ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora) INCLUDE (es_valida)$ddl_5_1$, $ddl_5_2$CREATE INDEX idx_det_sensor_hora_c5 ON monitoreo_sismologico.deteccion (id_sensor, hora_deteccion)$ddl_5_2$]
    ];
    v_tables TEXT[][] := ARRAY[
      ARRAY['evento_sismico',''],
      ARRAY['evento_sismico',''],
      ARRAY['lectura_onda',''],
      ARRAY['deteccion','alerta'],
      ARRAY['lectura_onda','deteccion']
    ];
    i INTEGER; k INTEGER; phase INTEGER;
    v_plan JSONB; v_root JSONB; v_used TEXT;
BEGIN
    FOR i IN 1..5 LOOP
        FOR phase IN 1..2 LOOP
            IF phase = 2 THEN
                FOR k IN 1..2 LOOP
                    IF v_idx_ddl[i][k] <> '' THEN
                        EXECUTE v_idx_ddl[i][k];
                    END IF;
                    IF v_tables[i][k] <> '' THEN
                        EXECUTE format('ANALYZE monitoreo_sismologico.%I',v_tables[i][k]);
                    END IF;
                END LOOP;
            END IF;
            EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_queries[i] INTO v_plan;
            v_root := v_plan->0->'Plan';
            v_used := '';
            FOR k IN 1..2 LOOP
                IF v_idx[i][k] <> '' AND POSITION(v_idx[i][k] IN v_root::TEXT) > 0 THEN
                    v_used := v_used || CASE WHEN v_used <> '' THEN ', ' ELSE '' END || v_idx[i][k];
                END IF;
            END LOOP;
            INSERT INTO evidencia_video_62 VALUES (
                'C'||i, CASE WHEN phase=1 THEN 'SIN' ELSE 'CON' END,
                (v_plan->0->>'Execution Time')::NUMERIC,
                COALESCE((v_root->>'Shared Hit Blocks')::BIGINT,0),
                COALESCE((v_root->>'Shared Read Blocks')::BIGINT,0),
                COALESCE((v_root->>'Temp Read Blocks')::BIGINT,0),
                COALESCE((v_root->>'Temp Written Blocks')::BIGINT,0),
                CASE WHEN v_used='' THEN 'ninguno' ELSE v_used END
            );
        END LOOP;
        FOR k IN 1..2 LOOP
            IF v_idx[i][k] <> '' THEN
                EXECUTE format('DROP INDEX monitoreo_sismologico.%I',v_idx[i][k]);
            END IF;
        END LOOP;
        RAISE NOTICE 'C% documentada en ambos escenarios; indice candidato retirado',i;
    END LOOP;
END;
$demo$;

\echo
\echo === C. PLANES DE DEMOSTRACION (UNA EJECUCION POR ESCENARIO) ===
SELECT consulta, escenario, execution_ms AS tiempo_ms,
       shared_hit, shared_read, temp_read, temp_written, indice_usado
FROM evidencia_video_62
ORDER BY consulta, CASE escenario WHEN 'SIN' THEN 1 ELSE 2 END;

\echo
\echo === D. ROLLBACK: RESTAURAR EL ESTADO ORIGINAL DE LOS INDICES ===
ROLLBACK;

\echo
\echo === E. VERIFICACION DE INDICES ORIGINALES TRAS ROLLBACK ===
SELECT indexname, tablename
FROM pg_indexes
WHERE schemaname='monitoreo_sismologico'
  AND indexname IN ('idx_lectura_sensor_hora_c5','idx_det_sensor_hora_c5')
ORDER BY indexname;

\echo
\echo === DEMOSTRACION COMPLETADA; NO SUSTITUYE LOS CSV DE 5 MEDICIONES ===
\connect bd_sismologico
