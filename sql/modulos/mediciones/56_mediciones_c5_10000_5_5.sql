-- Proyecto Final / 5.5 / Consulta 5 / 10 000 registros.
-- Compara la Consulta 5 EXACTA sin y con los dos indices secundarios candidatos.
-- En cada escenario: dos calentamientos y cinco mediciones EXPLAIN ANALYZE BUFFERS JSON.
-- Se comprueba la igualdad mediante la firma de las filas reales; se exporta CSV.
-- Solo retira los indices experimentales C4 de la prueba 52: no cambia datos,
-- llaves, restricciones, triggers ni ninguno de los respaldos .dump.
-- Ejecutar UNA SOLA VEZ en psql conectado a bd_sismologico_exp_10000.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $pre$
DECLARE v_total BIGINT;
BEGIN
    IF current_database() <> 'bd_sismologico_exp_10000' THEN
        RAISE EXCEPTION 'Base incorrecta: conectarse a bd_sismologico_exp_10000.';
    END IF;
    SELECT (SELECT COUNT(*) FROM estacion_sismica) + (SELECT COUNT(*) FROM sensor) +
           (SELECT COUNT(*) FROM evento_sismico) + (SELECT COUNT(*) FROM lectura_onda) +
           (SELECT COUNT(*) FROM deteccion) + (SELECT COUNT(*) FROM alerta)
    INTO v_total;
    IF (v_total,
        (SELECT COUNT(*) FROM estacion_sismica), (SELECT COUNT(*) FROM sensor),
        (SELECT COUNT(*) FROM evento_sismico), (SELECT COUNT(*) FROM lectura_onda),
        (SELECT COUNT(*) FROM deteccion), (SELECT COUNT(*) FROM alerta))
       IS DISTINCT FROM (10000::BIGINT, 10::BIGINT, 30::BIGINT, 2000::BIGINT,
                         7550::BIGINT, 300::BIGINT, 110::BIGINT) THEN
        RAISE EXCEPTION 'La distribucion no coincide con los 10000 registros verificados.';
    END IF;
    IF to_regclass('monitoreo_sismologico.idx_det_evento_hora_c4') IS NULL
       OR to_regclass('monitoreo_sismologico.idx_alerta_evento_hora_c4') IS NULL THEN
        RAISE EXCEPTION 'Se esperaban los dos indices C4 residuales. Revisar el estado antes de continuar.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_class ix ON ix.oid = i.indexrelid
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
          AND ix.relname NOT IN ('idx_det_evento_hora_c4', 'idx_alerta_evento_hora_c4')
    ) THEN
        RAISE EXCEPTION 'Existen indices secundarios inesperados: no mezclar escenarios.';
    END IF;
    RAISE NOTICE 'OK: base 10000, 7550 lecturas, 30 sensores, 300 detecciones; solo dos indices residuales de C4.';
END;
$pre$;

\echo
\echo === C5 / 10000 / RETIRAR SOLO LOS DOS INDICES EXPERIMENTALES C4 ===
BEGIN;
DROP INDEX monitoreo_sismologico.idx_det_evento_hora_c4;
DROP INDEX monitoreo_sismologico.idx_alerta_evento_hora_c4;
COMMIT;

DO $valid$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'El escenario base aun contiene indices secundarios.';
    END IF;
END;
$valid$;

CREATE TEMP TABLE mediciones_c5_10000 (
    escenario TEXT NOT NULL,
    repeticion INTEGER NOT NULL,
    fase TEXT NOT NULL,
    execution_ms NUMERIC NOT NULL,
    planning_ms NUMERIC NOT NULL,
    shared_hit BIGINT NOT NULL,
    shared_read BIGINT NOT NULL,
    temp_read BIGINT NOT NULL,
    temp_written BIGINT NOT NULL,
    uso_indice_lectura BOOLEAN NOT NULL,
    uso_indice_deteccion BOOLEAN NOT NULL,
    filas_resultado INTEGER NOT NULL,
    lecturas_top15 BIGINT NOT NULL,
    invalidas_top15 BIGINT NOT NULL,
    firma_resultados TEXT NOT NULL,
    PRIMARY KEY (escenario, repeticion)
) ON COMMIT PRESERVE ROWS;

ANALYZE monitoreo_sismologico.estacion_sismica;
ANALYZE monitoreo_sismologico.sensor;
ANALYZE monitoreo_sismologico.lectura_onda;
ANALYZE monitoreo_sismologico.deteccion;

DO $run$
DECLARE
    v_sql TEXT := $consulta$
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
    v_plan JSONB; v_root JSONB; v_iter INTEGER; v_mode INTEGER;
    v_stage TEXT; v_rows INTEGER; v_sum BIGINT; v_invalid BIGINT; v_hash TEXT;
    v_base_hash TEXT; v_base_rows INTEGER; v_base_sum BIGINT; v_base_invalid BIGINT;
BEGIN
    FOR v_mode IN 1..2 LOOP
        IF v_mode = 2 THEN
            EXECUTE $idx1$
                CREATE INDEX idx_lectura_sensor_hora_c5
                ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora)
                INCLUDE (es_valida)
            $idx1$;
            EXECUTE $idx2$
                CREATE INDEX idx_det_sensor_hora_c5
                ON monitoreo_sismologico.deteccion (id_sensor, hora_deteccion)
            $idx2$;
            EXECUTE 'ANALYZE monitoreo_sismologico.lectura_onda';
            EXECUTE 'ANALYZE monitoreo_sismologico.deteccion';
            RAISE NOTICE 'Escenario CON dos indices candidatos C5.';
        ELSE
            RAISE NOTICE 'Escenario SIN indices secundarios.';
        END IF;
        v_stage := CASE WHEN v_mode = 1 THEN 'sin_indice' ELSE 'con_indice' END;

        -- Firma de EXACTAMENTE las mismas filas (con LIMIT 15 y orden estable).
        EXECUTE FORMAT($hash_query$
            WITH resultado_consulta AS (%s)
            SELECT COUNT(*)::INTEGER,
                   COALESCE(SUM(lecturas_periodo),0)::BIGINT,
                   COALESCE(SUM(lecturas_invalidas),0)::BIGINT,
                   MD5(COALESCE(STRING_AGG(TO_JSONB(r)::TEXT, '|'
                       ORDER BY r.lecturas_invalidas DESC,
                                r.lecturas_periodo DESC, r.id_sensor), ''))
            FROM resultado_consulta r
        $hash_query$, v_sql)
        INTO v_rows, v_sum, v_invalid, v_hash;

        IF v_rows < 1 OR v_rows > 15 OR v_sum < 20 * v_rows
           OR v_invalid < 0 OR v_invalid > v_sum THEN
            RAISE EXCEPTION 'C5: resultados inesperados (filas %, lecturas %, invalidas %).',
                v_rows, v_sum, v_invalid;
        END IF;
        IF v_mode = 1 THEN
            v_base_hash := v_hash;
            v_base_rows := v_rows;
            v_base_sum := v_sum;
            v_base_invalid := v_invalid;
            RAISE NOTICE 'Firma base: %, filas: %, lecturas top15: %, invalidas top15: %',
                v_hash, v_rows, v_sum, v_invalid;
        ELSIF (v_base_hash, v_base_rows, v_base_sum, v_base_invalid)
               IS DISTINCT FROM (v_hash, v_rows, v_sum, v_invalid) THEN
            RAISE EXCEPTION 'Consulta 5: los resultados cambiaron al crear los indices.';
        ELSE
            RAISE NOTICE 'OK: resultados identicos en ambos escenarios. Firma: %', v_hash;
        END IF;

        FOR v_iter IN 1..7 LOOP
            EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_sql INTO v_plan;
            v_root := v_plan->0->'Plan';
            INSERT INTO mediciones_c5_10000 VALUES (
                v_stage, v_iter,
                CASE WHEN v_iter <= 2 THEN 'calentamiento' ELSE 'medicion' END,
                (v_plan->0->>'Execution Time')::NUMERIC,
                (v_plan->0->>'Planning Time')::NUMERIC,
                COALESCE((v_root->>'Shared Hit Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Shared Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Written Blocks')::BIGINT, 0),
                POSITION('idx_lectura_sensor_hora_c5' IN v_root::TEXT) > 0,
                POSITION('idx_det_sensor_hora_c5' IN v_root::TEXT) > 0,
                v_rows, v_sum, v_invalid, v_hash
            );
        END LOOP;
    END LOOP;
END;
$run$;

\echo
\echo === C5 / 10000 / LAS 14 EJECUCIONES ===
SELECT escenario, repeticion, fase, execution_ms, planning_ms,
       shared_hit, shared_read, temp_read, temp_written,
       uso_indice_lectura, uso_indice_deteccion, filas_resultado
FROM mediciones_c5_10000
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion;

\echo
\echo === C5 / 10000 / RESUMEN (SOLO CINCO MEDICIONES POR ESCENARIO) ===
SELECT escenario, COUNT(*) AS mediciones,
       ROUND(AVG(execution_ms), 4) AS media_ms,
       ROUND(STDDEV_SAMP(execution_ms), 4) AS desviacion_ms,
       MIN(execution_ms) AS minimo_ms,
       MAX(execution_ms) AS maximo_ms,
       ROUND(AVG(shared_hit), 2) AS promedio_hit,
       ROUND(AVG(shared_read), 2) AS promedio_read,
       ROUND(AVG(temp_read), 2) AS promedio_temp_read,
       ROUND(AVG(temp_written), 2) AS promedio_temp_written,
       COUNT(*) FILTER (WHERE uso_indice_lectura) AS usos_indice_lectura,
       COUNT(*) FILTER (WHERE uso_indice_deteccion) AS usos_indice_deteccion,
       MIN(filas_resultado) AS filas_resultado
FROM mediciones_c5_10000
WHERE fase = 'medicion'
GROUP BY escenario
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END;

\echo
\echo === C5 / 10000 / INDICES Y ESPACIO ===
SELECT tablename, indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS espacio
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename IN ('lectura_onda','deteccion')
ORDER BY tablename, indexname;

\echo
\echo === C5 / 10000 / CONTROL DE RESULTADOS ===
SELECT COUNT(DISTINCT firma_resultados) = 1 AS resultados_identicos,
       MIN(filas_resultado) AS filas_minimas,
       MAX(filas_resultado) AS filas_maximas,
       MIN(lecturas_top15) AS lecturas_top15,
       MIN(invalidas_top15) AS invalidas_top15
FROM mediciones_c5_10000;

\echo
\echo === C5 / 10000 / CONTROL DEL VOLUMEN ORIGINAL ===
SELECT (SELECT COUNT(*) FROM estacion_sismica) AS estaciones,
       (SELECT COUNT(*) FROM sensor) AS sensores,
       (SELECT COUNT(*) FROM evento_sismico) AS eventos,
       (SELECT COUNT(*) FROM lectura_onda) AS lecturas,
       (SELECT COUNT(*) FROM deteccion) AS detecciones,
       (SELECT COUNT(*) FROM alerta) AS alertas;

\echo
\echo === C5 / 10000 / EXPORTAR CSV ===
\copy (SELECT * FROM mediciones_c5_10000 ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/56_resultados_c5_10000_5_5.csv' WITH (FORMAT csv, HEADER true)

\echo
\echo === C5 / 10000 / FINALIZADO: CONSERVAR CSV Y NO REPETIR ===
