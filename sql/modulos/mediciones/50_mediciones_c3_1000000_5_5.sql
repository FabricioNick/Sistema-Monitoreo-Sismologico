-- Proyecto Final / 5.5 / Consulta 3 / 1 000 000 registros.
-- Compara la consulta original SIN y CON un indice secundario de cobertura.
-- 2 calentamientos + 5 mediciones por escenario; EXPLAIN ANALYZE BUFFERS JSON.
-- Solo elimina el indice experimental C2, no los indices de PK ni UNIQUE.
-- NO modifica registros, restricciones, triggers ni respaldos .dump.
-- Ejecutar UNA SOLA VEZ en psql (NO en pgAdmin Query Tool).

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $pre$
DECLARE v_total BIGINT; v_lect BIGINT; v_sens BIGINT; v_est BIGINT;
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: se requiere bd_sismologico_exp_1000000.';
    END IF;
    SELECT (SELECT COUNT(*) FROM estacion_sismica) + (SELECT COUNT(*) FROM sensor) +
           (SELECT COUNT(*) FROM evento_sismico) + (SELECT COUNT(*) FROM lectura_onda) +
           (SELECT COUNT(*) FROM deteccion) + (SELECT COUNT(*) FROM alerta)
    INTO v_total;
    SELECT COUNT(*) INTO v_lect FROM lectura_onda;
    SELECT COUNT(*) INTO v_sens FROM sensor;
    SELECT COUNT(*) INTO v_est FROM estacion_sismica;
    IF (v_total, v_lect, v_sens, v_est) IS DISTINCT FROM (1000000::BIGINT,875000::BIGINT,300::BIGINT,100::BIGINT) THEN
        RAISE EXCEPTION 'Cantidades inesperadas: total %, lecturas %, sensores %, estaciones %.',
            v_total, v_lect, v_sens, v_est;
    END IF;
    IF to_regclass('monitoreo_sismologico.idx_ev_igp_geo_c2') IS NULL THEN
        RAISE EXCEPTION 'No esta el indice C2 esperado. Revisar estado de la base antes de continuar.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_class ix ON ix.oid = i.indexrelid
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
          AND ix.relname <> 'idx_ev_igp_geo_c2'
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios inesperados; no medir escenarios mezclados.';
    END IF;
    RAISE NOTICE 'OK: base 1000000, 875000 lecturas, 300 sensores, 100 estaciones; solo indice C2 residual.';
END;
$pre$;

\echo
\echo === C3 / 1000000 / RETIRAR SOLO EL INDICE EXPERIMENTAL C2 ===
BEGIN;
DROP INDEX monitoreo_sismologico.idx_ev_igp_geo_c2;
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
        RAISE EXCEPTION 'No se restauro escenario sin indices secundarios.';
    END IF;
END;
$valid$;

CREATE TEMP TABLE mediciones_c3_1000000 (
    escenario TEXT NOT NULL,
    repeticion INTEGER NOT NULL,
    fase TEXT NOT NULL,
    execution_ms NUMERIC NOT NULL,
    planning_ms NUMERIC NOT NULL,
    shared_hit BIGINT NOT NULL,
    shared_read BIGINT NOT NULL,
    temp_read BIGINT NOT NULL,
    temp_written BIGINT NOT NULL,
    uso_indice_candidato BOOLEAN NOT NULL,
    filas_resultado INTEGER NOT NULL,
    lecturas_agrupadas BIGINT NOT NULL,
    lecturas_invalidas BIGINT NOT NULL,
    firma_resultados TEXT NOT NULL,
    PRIMARY KEY (escenario, repeticion)
) ON COMMIT PRESERVE ROWS;

ANALYZE monitoreo_sismologico.estacion_sismica;
ANALYZE monitoreo_sismologico.sensor;
ANALYZE monitoreo_sismologico.lectura_onda;

DO $run$
DECLARE
    v_sql TEXT := $consulta$
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
    v_plan JSONB; v_root JSONB; v_iter INTEGER; v_mode INTEGER;
    v_stage TEXT; v_rows INTEGER; v_sum BIGINT; v_invalid BIGINT; v_hash TEXT;
    v_base_hash TEXT; v_base_rows INTEGER; v_base_sum BIGINT; v_base_invalid BIGINT;
BEGIN
    FOR v_mode IN 1..2 LOOP
        IF v_mode = 2 THEN
            EXECUTE $indice$
                CREATE INDEX idx_lectura_sensor_fecha_c3
                ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora)
                INCLUDE (es_valida)
            $indice$;
            EXECUTE 'ANALYZE monitoreo_sismologico.lectura_onda';
            RAISE NOTICE 'Comienza escenario CON indice de cobertura C3.';
        ELSE
            RAISE NOTICE 'Comienza escenario SIN indices secundarios.';
        END IF;
        v_stage := CASE WHEN v_mode = 1 THEN 'sin_indice' ELSE 'con_indice' END;

        -- Firma calculada sobre TODAS las filas, sin LIMIT y en orden estable.
        EXECUTE FORMAT($hash_query$
            WITH resultado_consulta AS (%s)
            SELECT COUNT(*)::INTEGER,
                   COALESCE(SUM(total_lecturas),0)::BIGINT,
                   COALESCE(SUM(lecturas_invalidas),0)::BIGINT,
                   MD5(COALESCE(STRING_AGG(TO_JSONB(r)::TEXT, '|'
                       ORDER BY id_estacion), ''))
            FROM resultado_consulta r
        $hash_query$, v_sql)
        INTO v_rows, v_sum, v_invalid, v_hash;
        IF v_rows <= 0 OR v_sum <> 875000 THEN
            RAISE EXCEPTION 'Consulta 3: resultados inesperados (estaciones %, lecturas %).', v_rows, v_sum;
        END IF;
        IF v_mode = 1 THEN
            v_base_hash := v_hash;
            v_base_rows := v_rows;
            v_base_sum := v_sum;
            v_base_invalid := v_invalid;
            RAISE NOTICE 'Firma base: %, estaciones: %, lecturas: %, invalidas: %',
                v_hash, v_rows, v_sum, v_invalid;
        ELSIF (v_base_hash, v_base_rows, v_base_sum, v_base_invalid)
               IS DISTINCT FROM (v_hash, v_rows, v_sum, v_invalid) THEN
            RAISE EXCEPTION 'La Consulta 3 cambio resultados al crear el indice.';
        ELSE
            RAISE NOTICE 'OK: resultados identicos en ambos escenarios. Firma: %', v_hash;
        END IF;

        FOR v_iter IN 1..7 LOOP
            EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_sql INTO v_plan;
            v_root := v_plan->0->'Plan';
            INSERT INTO mediciones_c3_1000000 VALUES (
                v_stage, v_iter,
                CASE WHEN v_iter <= 2 THEN 'calentamiento' ELSE 'medicion' END,
                (v_plan->0->>'Execution Time')::NUMERIC,
                (v_plan->0->>'Planning Time')::NUMERIC,
                COALESCE((v_root->>'Shared Hit Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Shared Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Written Blocks')::BIGINT, 0),
                POSITION('idx_lectura_sensor_fecha_c3' IN v_root::TEXT) > 0,
                v_rows, v_sum, v_invalid, v_hash
            );
        END LOOP;
    END LOOP;
END;
$run$;

\echo
\echo === C3 / 1000000 / LAS 14 EJECUCIONES ===
SELECT escenario, repeticion, fase, execution_ms, planning_ms,
       shared_hit, shared_read, temp_read, temp_written,
       uso_indice_candidato, filas_resultado
FROM mediciones_c3_1000000
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion;

\echo
\echo === C3 / 1000000 / RESUMEN (CINCO MEDICIONES POR ESCENARIO) ===
SELECT escenario, COUNT(*) AS mediciones,
       ROUND(AVG(execution_ms), 4) AS media_ms,
       ROUND(STDDEV_SAMP(execution_ms), 4) AS desviacion_ms,
       MIN(execution_ms) AS minimo_ms, MAX(execution_ms) AS maximo_ms,
       ROUND(AVG(shared_hit), 2) AS promedio_hit,
       ROUND(AVG(shared_read), 2) AS promedio_read,
       ROUND(AVG(temp_read), 2) AS promedio_temp_read,
       ROUND(AVG(temp_written), 2) AS promedio_temp_written,
       COUNT(*) FILTER (WHERE uso_indice_candidato) AS mediciones_usando_indice,
       MIN(filas_resultado) AS estaciones_resultado
FROM mediciones_c3_1000000
WHERE fase = 'medicion'
GROUP BY escenario
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END;

\echo
\echo === C3 / 1000000 / INDICES Y ESPACIO ===
SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS espacio
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico' AND tablename = 'lectura_onda'
ORDER BY indexname;

\echo
\echo === C3 / 1000000 / CONTROL DE RESULTADOS ===
SELECT COUNT(DISTINCT firma_resultados) = 1 AS resultados_identicos,
       MIN(filas_resultado) AS estaciones_minimas,
       MAX(filas_resultado) AS estaciones_maximas,
       MIN(lecturas_agrupadas) AS lecturas_agrupadas,
       MIN(lecturas_invalidas) AS lecturas_invalidas
FROM mediciones_c3_1000000;

\echo
\echo === C3 / 1000000 / EXPORTAR CSV ===
\copy (SELECT * FROM mediciones_c3_1000000 ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/50_resultados_c3_1000000_5_5.csv' WITH (FORMAT csv, HEADER true)

\echo
\echo === C3 / 1000000 / FINALIZADO: CONSERVAR CSV Y NO REPETIR ===
