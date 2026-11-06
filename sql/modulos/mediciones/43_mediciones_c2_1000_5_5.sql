-- Proyecto Final / 5.5 / Consulta 2 / escala 1 000.
-- Comparacion SIN y CON indice geografico, conservando la misma consulta.
-- Dos calentamientos y cinco mediciones por escenario.
-- Solo se retira el indice secundario de C1 creado en el piloto anterior.
-- NO modifica registros, llaves primarias, triggers ni respaldos .dump.
-- Ejecutar SOLO UNA VEZ en psql (no en Query Tool de pgAdmin).

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $pre$
DECLARE v_total BIGINT; v_igp BIGINT; v_est BIGINT;
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000' THEN
        RAISE EXCEPTION 'Base incorrecta: %, se requiere bd_sismologico_exp_1000.', current_database();
    END IF;
    SELECT (SELECT COUNT(*) FROM estacion_sismica) + (SELECT COUNT(*) FROM sensor) +
           (SELECT COUNT(*) FROM evento_sismico) + (SELECT COUNT(*) FROM lectura_onda) +
           (SELECT COUNT(*) FROM deteccion) + (SELECT COUNT(*) FROM alerta)
    INTO v_total;
    SELECT COUNT(*) INTO v_igp FROM evento_sismico
    WHERE id_evento BETWEEN 200000000 AND 299999999;
    SELECT COUNT(*) INTO v_est FROM estacion_sismica;
    IF v_total <> 1000 OR v_igp <> 50 OR v_est <> 5 THEN
        RAISE EXCEPTION 'Datos no esperados (total %, IGP %, estaciones %).', v_total, v_igp, v_est;
    END IF;
    IF to_regclass('monitoreo_sismologico.idx_ev_igp_m6_fecha') IS NULL THEN
        RAISE EXCEPTION 'Falta indice del piloto C1. Verificar el estado de la base antes de continuar.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_class ix ON ix.oid = i.indexrelid
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
          AND ix.relname <> 'idx_ev_igp_m6_fecha'
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios inesperados; no se puede establecer escenario base.';
    END IF;
    RAISE NOTICE 'OK: 1000 filas, 50 IGP, 5 estaciones; solo indice experimental de C1.';
END;
$pre$;

\echo
\echo === C2 / 1000 / RETIRAR SOLO INDICE SECUNDARIO C1 ===
BEGIN;
DROP INDEX monitoreo_sismologico.idx_ev_igp_m6_fecha;
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
        RAISE EXCEPTION 'Todavia existen indices secundarios; no medir escenario base.';
    END IF;
END;
$valid$;

CREATE TEMP TABLE mediciones_c2_1000 (
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
    coincidencias BIGINT NOT NULL,
    firma_resultados TEXT NOT NULL,
    PRIMARY KEY (escenario, repeticion)
) ON COMMIT PRESERVE ROWS;

ANALYZE monitoreo_sismologico.evento_sismico;
ANALYZE monitoreo_sismologico.estacion_sismica;

DO $run$
DECLARE
    v_sql TEXT := $consulta$
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
    v_plan JSONB; v_root JSONB; v_iter INTEGER; v_mode INTEGER;
    v_stage TEXT; v_rows INTEGER; v_sum BIGINT; v_hash TEXT;
    v_firma_base TEXT; v_rows_base INTEGER; v_sum_base BIGINT;
BEGIN
    FOR v_mode IN 1..2 LOOP
        IF v_mode = 2 THEN
            EXECUTE $indice$
                CREATE INDEX idx_ev_igp_geo_c2
                ON monitoreo_sismologico.evento_sismico
                  (latitud_epicentro, longitud_epicentro)
                INCLUDE (magnitud)
                WHERE id_evento BETWEEN 200000000 AND 299999999
                  AND fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00'
                  AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
                  AND magnitud >= 5
            $indice$;
            EXECUTE 'ANALYZE monitoreo_sismologico.evento_sismico';
            RAISE NOTICE 'Escenario CON indice geografico C2.';
        ELSE
            RAISE NOTICE 'Escenario SIN indices secundarios.';
        END IF;
        v_stage := CASE WHEN v_mode = 1 THEN 'sin_indice' ELSE 'con_indice' END;

        -- La firma se calcula sobre exactamente las mismas diez filas ordenadas.
        EXECUTE FORMAT($hash_query$
            WITH resultado_consulta AS (%s)
            SELECT COUNT(*)::INTEGER,
                   COALESCE(SUM(eventos_en_ventana),0)::BIGINT,
                   MD5(COALESCE(STRING_AGG(TO_JSONB(r)::TEXT, '|'
                       ORDER BY eventos_en_ventana DESC, id_estacion), ''))
            FROM resultado_consulta r
        $hash_query$, v_sql)
        INTO v_rows, v_sum, v_hash;
        IF v_rows = 0 THEN
            RAISE EXCEPTION 'C2 no devuelve filas en la base de 1000. Revisar datos del experimento.';
        END IF;
        IF v_mode = 1 THEN
            v_firma_base := v_hash; v_rows_base := v_rows; v_sum_base := v_sum;
            RAISE NOTICE 'Firma base: %, filas: %, coincidencias: %', v_hash, v_rows, v_sum;
        ELSIF (v_firma_base, v_rows_base, v_sum_base) IS DISTINCT FROM (v_hash, v_rows, v_sum) THEN
            RAISE EXCEPTION 'La Consulta 2 cambio resultados al crear indice.';
        ELSE
            RAISE NOTICE 'OK: resultados identicos en ambos escenarios. Firma: %', v_hash;
        END IF;

        FOR v_iter IN 1..7 LOOP
            EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_sql INTO v_plan;
            v_root := v_plan->0->'Plan';
            INSERT INTO mediciones_c2_1000
            VALUES (
                v_stage, v_iter,
                CASE WHEN v_iter <= 2 THEN 'calentamiento' ELSE 'medicion' END,
                (v_plan->0->>'Execution Time')::NUMERIC,
                (v_plan->0->>'Planning Time')::NUMERIC,
                COALESCE((v_root->>'Shared Hit Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Shared Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Written Blocks')::BIGINT, 0),
                POSITION('idx_ev_igp_geo_c2' IN v_root::TEXT) > 0,
                v_rows, v_sum, v_hash
            );
        END LOOP;
    END LOOP;
END;
$run$;

\echo
\echo === C2 / 1000 / LAS 14 EJECUCIONES ===
SELECT escenario, repeticion, fase, execution_ms, planning_ms,
       shared_hit, shared_read, temp_read, temp_written,
       uso_indice_candidato, filas_resultado
FROM mediciones_c2_1000
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion;

\echo
\echo === C2 / 1000 / RESUMEN (SOLO 5 MEDICIONES POR ESCENARIO) ===
SELECT escenario,
       COUNT(*) AS mediciones,
       ROUND(AVG(execution_ms), 4) AS media_ms,
       ROUND(STDDEV_SAMP(execution_ms), 4) AS desviacion_ms,
       MIN(execution_ms) AS minimo_ms, MAX(execution_ms) AS maximo_ms,
       ROUND(AVG(shared_hit),2) AS promedio_hit,
       ROUND(AVG(shared_read),2) AS promedio_read,
       COUNT(*) FILTER (WHERE uso_indice_candidato) AS mediciones_usando_indice,
       MIN(filas_resultado) AS filas_resultado
FROM mediciones_c2_1000
WHERE fase = 'medicion'
GROUP BY escenario
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END;

\echo
\echo === C2 / 1000 / INDICE CANDIDATO Y TAMANO ===
SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS espacio
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico' AND tablename = 'evento_sismico'
ORDER BY indexname;

\echo
\echo === C2 / 1000 / IGUALDAD DE RESULTADOS ===
SELECT COUNT(DISTINCT firma_resultados) = 1 AS resultados_identicos,
       MIN(filas_resultado) AS filas_minimas,
       MAX(filas_resultado) AS filas_maximas
FROM mediciones_c2_1000;

\echo
\echo === EXPORTACION CSV / CONSULTA 2, 1000 REGISTROS ===
\copy (SELECT * FROM mediciones_c2_1000 ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/43_resultados_c2_1000_5_5.csv' WITH (FORMAT csv, HEADER true)

\echo
\echo === FINALIZADO: CONSERVAR CSV Y NO REPETIR ESTE ARCHIVO ===
