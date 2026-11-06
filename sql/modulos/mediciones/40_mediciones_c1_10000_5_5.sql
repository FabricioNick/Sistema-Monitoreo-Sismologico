-- Proyecto Final / 5.5 / Consulta 1 / escala 10 000
-- Comparacion repetida SIN y CON indice secundario, sobre datos identicos.
-- Dos calentamientos y cinco mediciones por escenario; EXPLAIN JSON.
-- Crea SOLO idx_ev_igp_m6_fecha en bd_sismologico_exp_10000.
-- Ejecutar UNA vez desde psql, no en pgAdmin Query Tool.
-- No modifica registros ni indices obligatorios.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $pre$
DECLARE v_total BIGINT; v_igp BIGINT; v_filtrados BIGINT;
BEGIN
    IF current_database() <> 'bd_sismologico_exp_10000' THEN
        RAISE EXCEPTION 'Base incorrecta: %, se requiere bd_sismologico_exp_10000.', current_database();
    END IF;
    SELECT (SELECT COUNT(*) FROM estacion_sismica) +
           (SELECT COUNT(*) FROM sensor) +
           (SELECT COUNT(*) FROM evento_sismico) +
           (SELECT COUNT(*) FROM lectura_onda) +
           (SELECT COUNT(*) FROM deteccion) +
           (SELECT COUNT(*) FROM alerta)
    INTO v_total;
    IF v_total <> 10000 THEN
        RAISE EXCEPTION 'Volumen inesperado: % (se esperaban 10000).', v_total;
    END IF;
    SELECT COUNT(*) INTO v_igp FROM evento_sismico
    WHERE id_evento BETWEEN 200000000 AND 299999999;
    IF v_igp <> 800 THEN
        RAISE EXCEPTION 'Se esperaban 800 eventos del IGP; encontrados: %.', v_igp;
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
        WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'Ya existen indices secundarios: no ejecutar sobre un escenario alterado.';
    END IF;
    SELECT COUNT(*) INTO v_filtrados FROM evento_sismico
    WHERE id_evento BETWEEN 200000000 AND 299999999
      AND fecha_hora_origen >= TIMESTAMP '2010-01-01 00:00:00'
      AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
      AND magnitud >= 6;
    IF v_filtrados = 0 THEN
        RAISE EXCEPTION 'No hay sismos elegibles para la Consulta 1.';
    END IF;
    RAISE NOTICE 'OK: 10000 filas, 800 eventos IGP, % cumplen C1, sin indices secundarios.', v_filtrados;
END;
$pre$;

-- Se usa una tabla temporal; se conservan solo los resultados de medicion.
CREATE TEMP TABLE mediciones_c1_10000 (
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
    PRIMARY KEY (escenario, repeticion)
) ON COMMIT PRESERVE ROWS;

ANALYZE monitoreo_sismologico.evento_sismico;

-- El mismo DO mide ambos escenarios, sin alterar la consulta ni GUCs.
DO $run$
DECLARE
    v_q TEXT := $consulta$
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
    v_plan JSONB;
    v_root JSONB;
    v_iter INTEGER;
    v_mode INTEGER;
    v_stage TEXT;
BEGIN
    FOR v_mode IN 1..2 LOOP
        IF v_mode = 2 THEN
            EXECUTE 'CREATE INDEX idx_ev_igp_m6_fecha ON monitoreo_sismologico.evento_sismico (fecha_hora_origen) INCLUDE (magnitud, profundidad_km) WHERE id_evento BETWEEN 200000000 AND 299999999 AND magnitud >= 6';
            EXECUTE 'ANALYZE monitoreo_sismologico.evento_sismico';
            RAISE NOTICE 'Indice secundario de C1 creado; comienza el escenario CON indice.';
        ELSE
            RAISE NOTICE 'Comienza escenario SIN indice secundario.';
        END IF;
        v_stage := CASE WHEN v_mode = 1 THEN 'sin_indice' ELSE 'con_indice' END;
        FOR v_iter IN 1..7 LOOP
            EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_q INTO v_plan;
            v_root := v_plan->0->'Plan';
            INSERT INTO mediciones_c1_10000
            VALUES (
                v_stage, v_iter,
                CASE WHEN v_iter <= 2 THEN 'calentamiento' ELSE 'medicion' END,
                (v_plan->0->>'Execution Time')::NUMERIC,
                (v_plan->0->>'Planning Time')::NUMERIC,
                COALESCE((v_root->>'Shared Hit Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Shared Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Read Blocks')::BIGINT, 0),
                COALESCE((v_root->>'Temp Written Blocks')::BIGINT, 0),
                POSITION('idx_ev_igp_m6_fecha' IN v_root::TEXT) > 0
            );
        END LOOP;
    END LOOP;
END;
$run$;

\echo
\echo === C1 / 10000 / 14 EJECUCIONES (2x7) ===
SELECT escenario, repeticion, fase, execution_ms, planning_ms,
       shared_hit, shared_read, temp_read, temp_written, uso_indice_candidato
FROM mediciones_c1_10000
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion;

\echo
\echo === C1 / 10000 / RESUMEN DE LAS CINCO MEDICIONES DE CADA ESCENARIO ===
SELECT escenario,
       COUNT(*) AS mediciones,
       ROUND(AVG(execution_ms), 4) AS media_ms,
       ROUND(STDDEV_SAMP(execution_ms), 4) AS desviacion_ms,
       ROUND(MIN(execution_ms), 4) AS minimo_ms,
       ROUND(MAX(execution_ms), 4) AS maximo_ms,
       ROUND(AVG(shared_hit), 2) AS promedio_hit,
       ROUND(AVG(shared_read), 2) AS promedio_read,
       COUNT(*) FILTER (WHERE uso_indice_candidato) AS mediciones_usando_indice
FROM mediciones_c1_10000
WHERE fase = 'medicion'
GROUP BY escenario
ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END;

\echo
\echo === C1 / 10000 / INDICE CANDIDATO Y TAMANO ===
SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS espacio
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico' AND tablename = 'evento_sismico'
ORDER BY indexname;

\echo
\echo === C1 / 10000 / CONTROL DE EVENTOS Y AGRUPACIONES ===
SELECT COUNT(*) AS eventos_elegibles,
       COUNT(DISTINCT EXTRACT(YEAR FROM fecha_hora_origen)::INTEGER) AS anios_con_resultados
FROM evento_sismico
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND fecha_hora_origen >= TIMESTAMP '2010-01-01 00:00:00'
  AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND magnitud >= 6;

\echo
\echo === EXPORTAR LOS RESULTADOS AL CSV DE LA CARPETA SQL ===
\copy (SELECT * FROM mediciones_c1_10000 ORDER BY CASE escenario WHEN 'sin_indice' THEN 1 ELSE 2 END, repeticion) TO 'resultados/40_resultados_c1_10000_5_5.csv' WITH (FORMAT csv, HEADER true)

\echo
\echo === FINALIZADO: CONSERVAR CSV. NO REPETIR EL ARCHIVO ===
