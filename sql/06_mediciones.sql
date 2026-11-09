-- 06. MEDICIONES
-- Dos calentamientos y cinco mediciones por escenario.

\set ON_ERROR_STOP on
\pset pager off
\timing off

\echo === VALIDACION INICIAL ===
SELECT set_config('sismo.consulta', :'consulta', false) AS consulta,
       set_config('sismo.escala', :'escala', false) AS escala;

DO $validacion$
DECLARE
    v_c INTEGER := current_setting('sismo.consulta')::INTEGER;
    v_e INTEGER := current_setting('sismo.escala')::INTEGER;
    v_tablas BIGINT[];
    v_esperado BIGINT[];
    v_igp INTEGER;
BEGIN
    IF v_c NOT BETWEEN 1 AND 5 OR v_e NOT IN (1000, 10000, 100000, 1000000) THEN
        RAISE EXCEPTION 'Consulta o escala incorrecta';
    END IF;
    IF current_database() <> 'bd_sismologico_prueba_exp_' || v_e THEN
        RAISE EXCEPTION 'Base incorrecta: %; se requiere bd_sismologico_prueba_exp_%',
            current_database(), v_e;
    END IF;
    SELECT ARRAY[
        (SELECT COUNT(*) FROM monitoreo_sismologico.estacion_sismica),
        (SELECT COUNT(*) FROM monitoreo_sismologico.sensor),
        (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico),
        (SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda),
        (SELECT COUNT(*) FROM monitoreo_sismologico.deteccion),
        (SELECT COUNT(*) FROM monitoreo_sismologico.alerta)
    ] INTO v_tablas;
    v_esperado := CASE v_e
        WHEN 1000 THEN ARRAY[5,15,100,750,90,40]::BIGINT[]
        WHEN 10000 THEN ARRAY[10,30,2000,7550,300,110]::BIGINT[]
        WHEN 100000 THEN ARRAY[25,75,24000,74700,900,300]::BIGINT[]
        WHEN 1000000 THEN ARRAY[100,300,120000,875000,3500,1100]::BIGINT[]
    END;
    IF v_tablas <> v_esperado THEN
        RAISE EXCEPTION 'Distribucion inesperada: %, esperado: %', v_tablas, v_esperado;
    END IF;
    v_igp := CASE v_e WHEN 1000 THEN 50 WHEN 10000 THEN 800
        WHEN 100000 THEN 12000 ELSE 24289 END;
    IF (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico
        WHERE id_evento BETWEEN 200000000 AND 299999999) <> v_igp THEN
        RAISE EXCEPTION 'Cantidad IGP inesperada';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios previos';
    END IF;
    RAISE NOTICE 'OK: C%, escala %, % registros, % eventos IGP, sin indices secundarios',
        v_c, v_e, v_e, v_igp;
END;
$validacion$;

BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

CREATE TEMP TABLE resultado_mediciones (
    consulta TEXT NOT NULL,
    escala INTEGER NOT NULL,
    escenario TEXT NOT NULL,
    repeticion INTEGER NOT NULL,
    fase TEXT NOT NULL,
    execution_ms NUMERIC NOT NULL,
    planning_ms NUMERIC NOT NULL,
    shared_hit BIGINT NOT NULL,
    shared_read BIGINT NOT NULL,
    temp_read BIGINT NOT NULL,
    temp_written BIGINT NOT NULL,
    uso_indice_1 BOOLEAN NOT NULL,
    uso_indice_2 BOOLEAN NOT NULL,
    filas_resultado INTEGER NOT NULL,
    firma_resultados TEXT NOT NULL,
    PRIMARY KEY (escenario, repeticion)
) ON COMMIT DROP;

\echo === MEDICIONES ===
DO $medicion$
DECLARE
    v_c INTEGER := current_setting('sismo.consulta')::INTEGER;
    v_e INTEGER := current_setting('sismo.escala')::INTEGER;
    v_sql TEXT;
    v_indices TEXT[];
    v_nombres TEXT[];
    v_tablas TEXT[];
    v_modo INTEGER;
    v_repeticion INTEGER;
    v_escenario TEXT;
    v_filas INTEGER;
    v_firma TEXT;
    v_filas_base INTEGER;
    v_firma_base TEXT;
    v_plan JSONB;
    v_raiz JSONB;
    v_uso_1 BOOLEAN;
    v_uso_2 BOOLEAN;
BEGIN
    CASE v_c
        WHEN 1 THEN
            v_sql := $consulta$
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
$consulta$;
            v_indices := ARRAY[
                $indice$CREATE INDEX idx_ev_igp_m6_fecha
ON monitoreo_sismologico.evento_sismico (fecha_hora_origen)
INCLUDE (magnitud, profundidad_km)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND magnitud >= 6$indice$
            ];
            v_nombres := ARRAY['idx_ev_igp_m6_fecha'];
            v_tablas := ARRAY['evento_sismico'];
        WHEN 2 THEN
            v_sql := $consulta$
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
$consulta$;
            v_indices := ARRAY[
                $indice$CREATE INDEX idx_ev_igp_geo_c2
ON monitoreo_sismologico.evento_sismico
    (latitud_epicentro, longitud_epicentro)
INCLUDE (magnitud)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00'
  AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND magnitud >= 5$indice$
            ];
            v_nombres := ARRAY['idx_ev_igp_geo_c2'];
            v_tablas := ARRAY['evento_sismico'];
        WHEN 3 THEN
            v_sql := $consulta$
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
$consulta$;
            v_indices := ARRAY[
                $indice$CREATE INDEX idx_lectura_sensor_fecha_c3
ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora)
INCLUDE (es_valida)$indice$
            ];
            v_nombres := ARRAY['idx_lectura_sensor_fecha_c3'];
            v_tablas := ARRAY['lectura_onda'];
        WHEN 4 THEN
            v_sql := $consulta$
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
LIMIT 15
$consulta$;
            v_indices := ARRAY[
                $indice$CREATE INDEX idx_det_evento_hora_c4
    ON monitoreo_sismologico.deteccion (id_evento, hora_deteccion)$indice$,
                $indice$CREATE INDEX idx_alerta_evento_hora_c4
    ON monitoreo_sismologico.alerta (id_evento, fecha_hora_emision)$indice$
            ];
            v_nombres := ARRAY['idx_det_evento_hora_c4', 'idx_alerta_evento_hora_c4'];
            v_tablas := ARRAY['deteccion', 'alerta'];
        WHEN 5 THEN
            v_sql := $consulta$
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
$consulta$;
            v_indices := ARRAY[
                $indice$CREATE INDEX idx_lectura_sensor_hora_c5
    ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora)
    INCLUDE (es_valida)$indice$,
                $indice$CREATE INDEX idx_det_sensor_hora_c5
    ON monitoreo_sismologico.deteccion (id_sensor, hora_deteccion)$indice$
            ];
            v_nombres := ARRAY['idx_lectura_sensor_hora_c5', 'idx_det_sensor_hora_c5'];
            v_tablas := ARRAY['lectura_onda', 'deteccion'];
    END CASE;

    FOREACH v_escenario IN ARRAY ARRAY['sin_indice', 'con_indice'] LOOP
        IF v_escenario = 'con_indice' THEN
            FOR v_modo IN 1..ARRAY_LENGTH(v_indices, 1) LOOP
                EXECUTE v_indices[v_modo];
            END LOOP;
            FOR v_modo IN 1..ARRAY_LENGTH(v_tablas, 1) LOOP
                EXECUTE 'ANALYZE monitoreo_sismologico.' || quote_ident(v_tablas[v_modo]);
            END LOOP;
        END IF;

        EXECUTE FORMAT(
            'SELECT COUNT(*)::INTEGER, MD5(COALESCE(STRING_AGG(TO_JSONB(t)::TEXT, ''|'' ORDER BY TO_JSONB(t)::TEXT), '''')) FROM (%s) t',
            v_sql
        ) INTO v_filas, v_firma;
        IF v_filas < 1 THEN
            RAISE EXCEPTION 'Consulta % sin resultados', v_c;
        END IF;
        IF v_escenario = 'sin_indice' THEN
            v_filas_base := v_filas;
            v_firma_base := v_firma;
        ELSIF (v_filas, v_firma) IS DISTINCT FROM (v_filas_base, v_firma_base) THEN
            RAISE EXCEPTION 'Resultados diferentes entre escenarios para C%', v_c;
        END IF;

        FOR v_repeticion IN 1..7 LOOP
            EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_sql INTO v_plan;
            v_raiz := v_plan->0->'Plan';
            v_uso_1 := POSITION(v_nombres[1] IN v_raiz::TEXT) > 0;
            v_uso_2 := CASE WHEN ARRAY_LENGTH(v_nombres, 1) > 1
                THEN POSITION(v_nombres[2] IN v_raiz::TEXT) > 0 ELSE FALSE END;
            INSERT INTO resultado_mediciones VALUES (
                'C' || v_c, v_e, v_escenario, v_repeticion,
                CASE WHEN v_repeticion <= 2 THEN 'calentamiento' ELSE 'medicion' END,
                (v_plan->0->>'Execution Time')::NUMERIC,
                (v_plan->0->>'Planning Time')::NUMERIC,
                COALESCE((v_raiz->>'Shared Hit Blocks')::BIGINT, 0),
                COALESCE((v_raiz->>'Shared Read Blocks')::BIGINT, 0),
                COALESCE((v_raiz->>'Temp Read Blocks')::BIGINT, 0),
                COALESCE((v_raiz->>'Temp Written Blocks')::BIGINT, 0),
                v_uso_1, v_uso_2, v_filas, v_firma
            );
        END LOOP;
    END LOOP;
    RAISE NOTICE 'OK: C%, escala %, 14 ejecuciones, resultados identicos', v_c, v_e;
END;
$medicion$;

\echo === RESUMEN ===
SELECT consulta, escala, escenario, COUNT(*) AS mediciones,
       ROUND(AVG(execution_ms), 4) AS media_ms,
       ROUND(STDDEV_SAMP(execution_ms), 4) AS desviacion_ms,
       MIN(execution_ms) AS minimo_ms,
       MAX(execution_ms) AS maximo_ms,
       ROUND(AVG(shared_hit), 2) AS media_shared_hit,
       ROUND(AVG(shared_read), 2) AS media_shared_read,
       ROUND(AVG(temp_read), 2) AS media_temp_read,
       ROUND(AVG(temp_written), 2) AS media_temp_written,
       COUNT(*) FILTER (WHERE uso_indice_1) AS usos_indice_1,
       COUNT(*) FILTER (WHERE uso_indice_2) AS usos_indice_2,
       MIN(filas_resultado) AS filas
FROM resultado_mediciones
WHERE fase = 'medicion'
GROUP BY consulta, escala, escenario
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END;

DO $verificacion$
BEGIN
    IF (SELECT COUNT(*) FROM resultado_mediciones) <> 14
       OR (SELECT COUNT(*) FROM resultado_mediciones WHERE fase='medicion') <> 10
       OR (SELECT COUNT(DISTINCT firma_resultados) FROM resultado_mediciones) <> 1
       OR (SELECT COUNT(DISTINCT filas_resultado) FROM resultado_mediciones) <> 1 THEN
        RAISE EXCEPTION 'Mediciones o resultados inconsistentes';
    END IF;
    RAISE NOTICE 'OK: 4 calentamientos, 10 mediciones, resultados equivalentes';
END;
$verificacion$;

\echo === EXPORTACION CSV ===
SELECT
    CASE WHEN current_setting('sismo.consulta')::INTEGER=1 AND current_setting('sismo.escala')::INTEGER=1000 THEN 'true' ELSE 'false' END AS guardar_c1_1000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=1 AND current_setting('sismo.escala')::INTEGER=10000 THEN 'true' ELSE 'false' END AS guardar_c1_10000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=1 AND current_setting('sismo.escala')::INTEGER=100000 THEN 'true' ELSE 'false' END AS guardar_c1_100000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=1 AND current_setting('sismo.escala')::INTEGER=1000000 THEN 'true' ELSE 'false' END AS guardar_c1_1000000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=2 AND current_setting('sismo.escala')::INTEGER=1000 THEN 'true' ELSE 'false' END AS guardar_c2_1000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=2 AND current_setting('sismo.escala')::INTEGER=10000 THEN 'true' ELSE 'false' END AS guardar_c2_10000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=2 AND current_setting('sismo.escala')::INTEGER=100000 THEN 'true' ELSE 'false' END AS guardar_c2_100000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=2 AND current_setting('sismo.escala')::INTEGER=1000000 THEN 'true' ELSE 'false' END AS guardar_c2_1000000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=3 AND current_setting('sismo.escala')::INTEGER=1000 THEN 'true' ELSE 'false' END AS guardar_c3_1000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=3 AND current_setting('sismo.escala')::INTEGER=10000 THEN 'true' ELSE 'false' END AS guardar_c3_10000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=3 AND current_setting('sismo.escala')::INTEGER=100000 THEN 'true' ELSE 'false' END AS guardar_c3_100000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=3 AND current_setting('sismo.escala')::INTEGER=1000000 THEN 'true' ELSE 'false' END AS guardar_c3_1000000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=4 AND current_setting('sismo.escala')::INTEGER=1000 THEN 'true' ELSE 'false' END AS guardar_c4_1000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=4 AND current_setting('sismo.escala')::INTEGER=10000 THEN 'true' ELSE 'false' END AS guardar_c4_10000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=4 AND current_setting('sismo.escala')::INTEGER=100000 THEN 'true' ELSE 'false' END AS guardar_c4_100000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=4 AND current_setting('sismo.escala')::INTEGER=1000000 THEN 'true' ELSE 'false' END AS guardar_c4_1000000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=5 AND current_setting('sismo.escala')::INTEGER=1000 THEN 'true' ELSE 'false' END AS guardar_c5_1000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=5 AND current_setting('sismo.escala')::INTEGER=10000 THEN 'true' ELSE 'false' END AS guardar_c5_10000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=5 AND current_setting('sismo.escala')::INTEGER=100000 THEN 'true' ELSE 'false' END AS guardar_c5_100000,
    CASE WHEN current_setting('sismo.consulta')::INTEGER=5 AND current_setting('sismo.escala')::INTEGER=1000000 THEN 'true' ELSE 'false' END AS guardar_c5_1000000
\gset

\if :guardar_c1_1000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C1_1000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c1_10000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C1_10000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c1_100000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C1_100000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c1_1000000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C1_1000000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c2_1000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C2_1000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c2_10000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C2_10000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c2_100000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C2_100000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c2_1000000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C2_1000000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c3_1000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C3_1000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c3_10000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C3_10000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c3_100000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C3_100000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c3_1000000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C3_1000000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c4_1000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C4_1000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c4_10000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C4_10000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c4_100000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C4_100000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c4_1000000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C4_1000000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c5_1000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C5_1000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c5_10000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C5_10000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c5_100000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C5_100000.csv' WITH (FORMAT csv, HEADER true)
\endif
\if :guardar_c5_1000000
\copy (SELECT * FROM resultado_mediciones ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/06_C5_1000000.csv' WITH (FORMAT csv, HEADER true)
\endif

\echo === RESTAURACION ===
ROLLBACK;

DO $final$
DECLARE v_e INTEGER := current_setting('sismo.escala')::INTEGER;
BEGIN
    IF current_database() <> 'bd_sismologico_prueba_exp_' || v_e THEN
        RAISE EXCEPTION 'Base final incorrecta';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'Indices secundarios persistentes';
    END IF;
    RAISE NOTICE 'OK: indices y datos iniciales preservados';
END;
$final$;

\echo === ETAPA 6: COMPARACION FINALIZADA ===
