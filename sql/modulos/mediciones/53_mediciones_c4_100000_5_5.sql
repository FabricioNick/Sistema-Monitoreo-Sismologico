-- Proyecto Final / 5.5 / Consulta 4 / 100 000 registros.
-- Compara la Consulta 4 ORIGINAL sin y con dos indices secundarios candidatos.
-- Por escenario: 2 calentamientos + 5 mediciones con EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON).
-- Retira exclusivamente el indice experimental C3 que quedo de la prueba anterior.
-- No cambia registros, llaves, restricciones, triggers ni los archivos .dump.
-- Ejecutar una sola vez en psql, conectado a bd_sismologico_exp_100000.
-- La base debe conservar unicamente el indice C3 de la prueba 49.
-- Usa exactamente el rango original 810000001..810000008 de la Consulta 4.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $pre$
DECLARE v_total BIGINT;
BEGIN
    IF current_database() <> 'bd_sismologico_exp_100000' THEN
        RAISE EXCEPTION 'Base incorrecta. Conectarse a bd_sismologico_exp_100000.';
    END IF;
    SELECT (SELECT COUNT(*) FROM estacion_sismica) + (SELECT COUNT(*) FROM sensor) +
           (SELECT COUNT(*) FROM evento_sismico) + (SELECT COUNT(*) FROM lectura_onda) +
           (SELECT COUNT(*) FROM deteccion) + (SELECT COUNT(*) FROM alerta)
      INTO v_total;
    IF v_total <> 100000
       OR (SELECT COUNT(*) FROM estacion_sismica) <> 25
       OR (SELECT COUNT(*) FROM sensor) <> 75
       OR (SELECT COUNT(*) FROM evento_sismico) <> 24000
       OR (SELECT COUNT(*) FROM lectura_onda) <> 74700
       OR (SELECT COUNT(*) FROM deteccion) <> 900
       OR (SELECT COUNT(*) FROM alerta) <> 300 THEN
        RAISE EXCEPTION 'La distribucion no coincide con los 100000 registros verificados.';
    END IF;
    IF to_regclass('monitoreo_sismologico.idx_lectura_sensor_fecha_c3') IS NULL THEN
        RAISE EXCEPTION 'Falta el indice C3 esperado. Revisar el estado de la base antes de medir.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_class ix ON ix.oid = i.indexrelid
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
          AND ix.relname <> 'idx_lectura_sensor_fecha_c3'
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios inesperados; no mezclar escenarios.';
    END IF;
    RAISE NOTICE 'OK: base 100000, 24000 eventos, 900 detecciones, 300 alertas; solo indice C3 residual.';
END;
$pre$;

\echo
\echo === C4 / 100000 / RETIRAR SOLO INDICE EXPERIMENTAL C3 ===
BEGIN;
DROP INDEX monitoreo_sismologico.idx_lectura_sensor_fecha_c3;
COMMIT;

DO $check$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'El escenario base conserva indices secundarios.';
    END IF;
END;
$check$;

CREATE TEMP TABLE mediciones_c4_100000 (
    escenario TEXT NOT NULL,
    repeticion INTEGER NOT NULL,
    fase TEXT NOT NULL,
    execution_ms NUMERIC NOT NULL,
    planning_ms NUMERIC NOT NULL,
    shared_hit BIGINT NOT NULL,
    shared_read BIGINT NOT NULL,
    temp_read BIGINT NOT NULL,
    temp_written BIGINT NOT NULL,
    uso_indice_deteccion BOOLEAN NOT NULL,
    uso_indice_alerta BOOLEAN NOT NULL,
    filas_resultado INTEGER NOT NULL,
    detecciones_top15 BIGINT NOT NULL,
    alertas_top15 BIGINT NOT NULL,
    firma_resultados TEXT NOT NULL,
    PRIMARY KEY (escenario, repeticion)
) ON COMMIT PRESERVE ROWS;

ANALYZE monitoreo_sismologico.evento_sismico;
ANALYZE monitoreo_sismologico.deteccion;
ANALYZE monitoreo_sismologico.alerta;

DO $run$
DECLARE
    v_sql TEXT := $consulta$
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
    v_plan JSONB; v_root JSONB;
    v_mode INTEGER; v_iter INTEGER; v_stage TEXT;
    v_rows INTEGER; v_det BIGINT; v_alert BIGINT; v_hash TEXT;
    v_base_rows INTEGER; v_base_det BIGINT; v_base_alert BIGINT; v_base_hash TEXT;
BEGIN
    FOR v_mode IN 1..2 LOOP
        IF v_mode = 2 THEN
            EXECUTE 'CREATE INDEX idx_det_evento_hora_c4 ON monitoreo_sismologico.deteccion (id_evento, hora_deteccion)';
            EXECUTE 'CREATE INDEX idx_alerta_evento_hora_c4 ON monitoreo_sismologico.alerta (id_evento, fecha_hora_emision)';
            EXECUTE 'ANALYZE monitoreo_sismologico.deteccion';
            EXECUTE 'ANALYZE monitoreo_sismologico.alerta';
            RAISE NOTICE 'Escenario CON dos indices candidatos C4.';
        ELSE
            RAISE NOTICE 'Escenario SIN indices secundarios.';
        END IF;
        v_stage := CASE WHEN v_mode = 1 THEN 'sin_indice' ELSE 'con_indice' END;

        -- Firma de EXACTAMENTE las mismas quince filas de la consulta original.
        EXECUTE FORMAT($hash_query$
            WITH resultado_consulta AS (%s)
            SELECT COUNT(*)::INTEGER,
                   COALESCE(SUM(total_detecciones),0)::BIGINT,
                   COALESCE(SUM(total_alertas),0)::BIGINT,
                   MD5(COALESCE(STRING_AGG(TO_JSONB(r)::TEXT, '|'
                       ORDER BY r.fecha_hora_origen DESC, r.id_evento), ''))
            FROM resultado_consulta r
        $hash_query$, v_sql)
        INTO v_rows, v_det, v_alert, v_hash;

        IF v_rows <> 15 OR v_det < 0 OR v_alert < 0 THEN
            RAISE EXCEPTION 'C4: resultados inesperados: filas %, detecciones %, alertas %.', v_rows, v_det, v_alert;
        END IF;
        IF v_mode = 1 THEN
            v_base_rows := v_rows;
            v_base_det := v_det;
            v_base_alert := v_alert;
            v_base_hash := v_hash;
            RAISE NOTICE 'Firma base: %, filas: %, detecciones top15: %, alertas top15: %',
                v_hash, v_rows, v_det, v_alert;
        ELSIF (v_rows, v_det, v_alert, v_hash)
               IS DISTINCT FROM (v_base_rows, v_base_det, v_base_alert, v_base_hash) THEN
            RAISE EXCEPTION 'Consulta 4: se modificaron resultados al agregar indices.';
        ELSE
            RAISE NOTICE 'OK: resultados identicos en ambos escenarios. Firma: %', v_hash;
        END IF;

        FOR v_iter IN 1..7 LOOP
            EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_sql INTO v_plan;
            v_root := v_plan->0->'Plan';
            INSERT INTO mediciones_c4_100000 VALUES (
                v_stage, v_iter,
                CASE WHEN v_iter <= 2 THEN 'calentamiento' ELSE 'medicion' END,
                (v_plan->0->>'Execution Time')::NUMERIC,
                (v_plan->0->>'Planning Time')::NUMERIC,
                COALESCE((v_root->>'Shared Hit Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Shared Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Written Blocks')::BIGINT, 0),
                POSITION('idx_det_evento_hora_c4' IN v_root::TEXT) > 0,
                POSITION('idx_alerta_evento_hora_c4' IN v_root::TEXT) > 0,
                v_rows, v_det, v_alert, v_hash
            );
        END LOOP;
    END LOOP;
END;
$run$;

\echo
\echo === C4 / 100000 / LAS 14 EJECUCIONES ===
SELECT escenario, repeticion, fase, execution_ms, planning_ms,
       shared_hit, shared_read, temp_read, temp_written,
       uso_indice_deteccion, uso_indice_alerta, filas_resultado
FROM mediciones_c4_100000
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion;

\echo
\echo === C4 / 100000 / RESUMEN (SOLO CINCO MEDICIONES POR ESCENARIO) ===
SELECT escenario, COUNT(*) AS mediciones,
       ROUND(AVG(execution_ms), 4) AS media_ms,
       ROUND(STDDEV_SAMP(execution_ms), 4) AS desviacion_ms,
       MIN(execution_ms) AS minimo_ms,
       MAX(execution_ms) AS maximo_ms,
       ROUND(AVG(shared_hit), 2) AS promedio_hit,
       ROUND(AVG(shared_read), 2) AS promedio_read,
       COUNT(*) FILTER (WHERE uso_indice_deteccion) AS usos_indice_deteccion,
       COUNT(*) FILTER (WHERE uso_indice_alerta) AS usos_indice_alerta,
       MIN(filas_resultado) AS filas_resultado
FROM mediciones_c4_100000
WHERE fase = 'medicion'
GROUP BY escenario
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END;

\echo
\echo === C4 / 100000 / INDICES Y ESPACIO ===
SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS espacio
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename IN ('deteccion', 'alerta')
ORDER BY tablename, indexname;

\echo
\echo === C4 / 100000 / CONTROL DE RESULTADOS ===
SELECT COUNT(DISTINCT firma_resultados) = 1 AS resultados_identicos,
       MIN(filas_resultado) AS filas_minimas,
       MAX(filas_resultado) AS filas_maximas,
       MIN(detecciones_top15) AS detecciones_top15,
       MIN(alertas_top15) AS alertas_top15
FROM mediciones_c4_100000;

\echo
\echo === C4 / 100000 / CONTROL DE VOLUMEN ORIGINAL ===
SELECT (SELECT COUNT(*) FROM estacion_sismica) AS estaciones,
       (SELECT COUNT(*) FROM sensor) AS sensores,
       (SELECT COUNT(*) FROM evento_sismico) AS eventos,
       (SELECT COUNT(*) FROM lectura_onda) AS lecturas,
       (SELECT COUNT(*) FROM deteccion) AS detecciones,
       (SELECT COUNT(*) FROM alerta) AS alertas;

\echo
\echo === C4 / 100000 / EXPORTAR CSV ===
\copy (SELECT * FROM mediciones_c4_100000 ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/53_resultados_c4_100000_5_5.csv' WITH (FORMAT csv, HEADER true)

\echo
\echo === C4 / 100000 / FINALIZADO: CONSERVAR CSV Y NO REPETIR ===
