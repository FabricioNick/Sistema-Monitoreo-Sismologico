-- 07. DEMOSTRACION DE CONSULTAS
\set ON_ERROR_STOP on
\pset pager off
\timing off

\if :{?consulta}
\else
\set consulta 1
\endif

\if :{?escala}
\else
\set escala 1000000
\endif
SELECT 1 / CASE WHEN :'escala' IN ('100','1000','10000','100000','1000000') THEN 1 ELSE 0 END AS escala_valida;
SELECT 'bd_sismologico_prueba_exp_' || :'escala' AS base_destino \gset
\connect :base_destino
\echo === DEMOSTRACION DE CONSULTA C:consulta ===
SELECT set_config('sismo.video_consulta', :'consulta', false) AS consulta_seleccionada,
       set_config('sismo.video_escala', :'escala', false) AS escala;

DO $validacion$
DECLARE
    v_consulta INTEGER := current_setting('sismo.video_consulta')::INTEGER;
    v_escala INTEGER := current_setting('sismo.video_escala')::INTEGER;
    v_tablas BIGINT[];
    v_esperado BIGINT[];
    v_igp INTEGER;
BEGIN
    IF v_consulta NOT BETWEEN 1 AND 5 OR v_escala NOT IN (100,1000,10000,100000,1000000) THEN
        RAISE EXCEPTION 'Consulta o escala incorrecta';
    END IF;
    IF current_database() <> 'bd_sismologico_prueba_exp_' || v_escala THEN
        RAISE EXCEPTION 'Base experimental incorrecta';
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
    IF v_tablas IS DISTINCT FROM v_esperado OR
       (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico
        WHERE id_evento BETWEEN 200000000 AND 299999999) <> v_igp THEN
        RAISE EXCEPTION 'La base experimental no contiene la distribucion validada';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'Existen indices secundarios previos';
    END IF;
    RAISE NOTICE 'OK: escala %, % eventos IGP, sin indices secundarios', v_escala, v_igp;
END;
$validacion$;

\echo === COMPARACION DE PLANES ===
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

CREATE TEMP TABLE planes_demostracion (
    consulta TEXT NOT NULL,
    escenario TEXT NOT NULL,
    execution_ms NUMERIC NOT NULL,
    shared_hit BIGINT NOT NULL,
    shared_read BIGINT NOT NULL,
    temp_read BIGINT NOT NULL,
    temp_written BIGINT NOT NULL,
    indice_usado TEXT NOT NULL,
    filas_resultado INTEGER NOT NULL,
    firma_resultados TEXT NOT NULL,
    muestra_resultados JSONB NOT NULL,
    plan_json JSONB NOT NULL,
    PRIMARY KEY (consulta, escenario)
) ON COMMIT DROP;

DO $demo$
DECLARE
    v_consulta INTEGER := current_setting('sismo.video_consulta')::INTEGER;
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
      $consulta_4$SELECT ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
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
LIMIT 15$consulta_4$,
      $consulta_5$SELECT s.id_sensor, s.numero_serie, e.codigo AS codigo_estacion,
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
LIMIT 15$consulta_5$
    ];
    v_idx TEXT[][] := ARRAY[
      ARRAY['idx_ev_igp_m6_fecha', '', ''],
      ARRAY['idx_ev_igp_geo_c2', '', ''],
      ARRAY['idx_lectura_sensor_fecha_c3', '', ''],
      ARRAY['idx_evento_fecha_c4', 'idx_deteccion_evento_hora_c4', 'idx_alerta_evento_hora_c4'],
      ARRAY['idx_lectura_fecha_sensor_c5', 'idx_deteccion_sensor_hora_c5', '']
    ];
    v_idx_ddl TEXT[][] := ARRAY[
      ARRAY[$ddl_1_1$CREATE INDEX idx_ev_igp_m6_fecha ON monitoreo_sismologico.evento_sismico (fecha_hora_origen) INCLUDE (magnitud, profundidad_km) WHERE id_evento BETWEEN 200000000 AND 299999999 AND magnitud >= 6$ddl_1_1$, '', ''],
      ARRAY[$ddl_2_1$CREATE INDEX idx_ev_igp_geo_c2 ON monitoreo_sismologico.evento_sismico (latitud_epicentro, longitud_epicentro) INCLUDE (magnitud) WHERE id_evento BETWEEN 200000000 AND 299999999 AND fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00' AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00' AND magnitud >= 5$ddl_2_1$, '', ''],
      ARRAY[$ddl_3_1$CREATE INDEX idx_lectura_sensor_fecha_c3 ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora) INCLUDE (es_valida)$ddl_3_1$, '', ''],
      ARRAY[$ddl_4_1$CREATE INDEX idx_evento_fecha_c4 ON monitoreo_sismologico.evento_sismico (fecha_hora_origen) INCLUDE (magnitud, estado_revision)$ddl_4_1$, $ddl_4_2$CREATE INDEX idx_deteccion_evento_hora_c4 ON monitoreo_sismologico.deteccion (id_evento, hora_deteccion)$ddl_4_2$, $ddl_4_3$CREATE INDEX idx_alerta_evento_hora_c4 ON monitoreo_sismologico.alerta (id_evento, fecha_hora_emision)$ddl_4_3$],
      ARRAY[$ddl_5_1$CREATE INDEX idx_lectura_fecha_sensor_c5 ON monitoreo_sismologico.lectura_onda (fecha_hora, id_sensor) INCLUDE (es_valida, valor)$ddl_5_1$, $ddl_5_2$CREATE INDEX idx_deteccion_sensor_hora_c5 ON monitoreo_sismologico.deteccion (id_sensor, hora_deteccion)$ddl_5_2$, '']
    ];
    v_tables TEXT[][] := ARRAY[
      ARRAY['evento_sismico', '', ''],
      ARRAY['evento_sismico', '', ''],
      ARRAY['lectura_onda', '', ''],
      ARRAY['evento_sismico', 'deteccion', 'alerta'],
      ARRAY['lectura_onda', 'deteccion', '']
    ];
    k INTEGER;
    escenario INTEGER;
    v_plan JSONB;
    v_raiz JSONB;
    v_usados TEXT;
    v_filas INTEGER;
    v_firma TEXT;
    v_filas_sin INTEGER;
    v_firma_sin TEXT;
    v_muestra JSONB;
BEGIN
    FOR escenario IN 1..2 LOOP
        IF escenario = 2 THEN
            FOR k IN 1..3 LOOP
                IF v_idx_ddl[v_consulta][k] <> '' THEN
                    EXECUTE v_idx_ddl[v_consulta][k];
                END IF;
                IF v_tables[v_consulta][k] <> '' THEN
                    EXECUTE format('ANALYZE monitoreo_sismologico.%I', v_tables[v_consulta][k]);
                END IF;
            END LOOP;
        END IF;

        EXECUTE format(
            'SELECT COUNT(*)::INTEGER, MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, ''|'' ORDER BY TO_JSONB(t)::TEXT), '''')) FROM (%s) t',
            v_queries[v_consulta]
        ) INTO v_filas, v_firma;
        IF v_filas < 1 THEN
            RAISE EXCEPTION 'La consulta C% no devolvio filas', v_consulta;
        END IF;
        IF escenario = 1 THEN
            v_filas_sin := v_filas;
            v_firma_sin := v_firma;
        ELSIF (v_filas, v_firma) IS DISTINCT FROM (v_filas_sin, v_firma_sin) THEN
            RAISE EXCEPTION 'Resultados distintos con y sin indices en C%', v_consulta;
        END IF;

        EXECUTE format(
            'SELECT COALESCE(JSONB_AGG(TO_JSONB(t)), ''[]''::JSONB) FROM (SELECT * FROM (%s) q LIMIT 5) t',
            v_queries[v_consulta]
        ) INTO v_muestra;

        EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_queries[v_consulta] INTO v_plan;
        v_raiz := v_plan->0->'Plan';
        v_usados := '';
        FOR k IN 1..3 LOOP
            IF v_idx[v_consulta][k] <> ''
               AND POSITION(v_idx[v_consulta][k] IN v_raiz::TEXT) > 0 THEN
                v_usados := v_usados || CASE WHEN v_usados <> '' THEN ', ' ELSE '' END
                    || v_idx[v_consulta][k];
            END IF;
        END LOOP;

        INSERT INTO planes_demostracion VALUES (
            'C' || v_consulta,
            CASE WHEN escenario = 1 THEN 'SIN INDICE' ELSE 'CON INDICE' END,
            (v_plan->0->>'Execution Time')::NUMERIC,
            COALESCE((v_raiz->>'Shared Hit Blocks')::BIGINT, 0),
            COALESCE((v_raiz->>'Shared Read Blocks')::BIGINT, 0),
            COALESCE((v_raiz->>'Temp Read Blocks')::BIGINT, 0),
            COALESCE((v_raiz->>'Temp Written Blocks')::BIGINT, 0),
            CASE WHEN v_usados = '' THEN 'ninguno' ELSE v_usados END,
            v_filas, v_firma, v_muestra, v_plan
        );
    END LOOP;
END;
$demo$;

\echo === RESULTADOS DE LA CONSULTA ===
SELECT escenario, filas_resultado, jsonb_pretty(muestra_resultados) AS muestra
FROM planes_demostracion
ORDER BY CASE escenario WHEN 'SIN INDICE' THEN 1 ELSE 2 END;

\echo === TIEMPOS Y USO DE INDICES ===
SELECT consulta, escenario, execution_ms AS tiempo_ms, shared_hit,
       shared_read, temp_read, temp_written, indice_usado
FROM planes_demostracion
ORDER BY CASE escenario WHEN 'SIN INDICE' THEN 1 ELSE 2 END;

\echo === PLANES DE EJECUCION ===
SELECT escenario, jsonb_pretty(plan_json) AS plan
FROM planes_demostracion
ORDER BY CASE escenario WHEN 'SIN INDICE' THEN 1 ELSE 2 END;

DO $control$
BEGIN
    IF (SELECT COUNT(*) FROM planes_demostracion) <> 2
       OR (SELECT COUNT(DISTINCT firma_resultados) FROM planes_demostracion) <> 1
       OR (SELECT COUNT(DISTINCT filas_resultado) FROM planes_demostracion) <> 1 THEN
        RAISE EXCEPTION 'Resultados de demostracion inconsistentes';
    END IF;
    RAISE NOTICE 'OK: consulta equivalente en ambos escenarios';
END;
$control$;

\echo === RESTAURACION ===
ROLLBACK;

DO $final$
BEGIN
    IF current_database() <> 'bd_sismologico_prueba_exp_' || current_setting('sismo.video_escala') THEN
        RAISE EXCEPTION 'La base activa ha cambiado';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'Persisten indices secundarios tras ROLLBACK';
    END IF;
    RAISE NOTICE 'OK: indices candidatos revertidos';
END;
$final$;

\echo === ETAPA 7 FINALIZADA ===
