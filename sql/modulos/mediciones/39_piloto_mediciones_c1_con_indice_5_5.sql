-- Proyecto Final / 5.5 / Piloto C1 con indice secundario
-- Base: bd_sismologico_exp_1000 (1 000 filas).
-- Mismos filtros, 2 calentamientos y 5 repeticiones que el archivo 38.
-- Crea solo el indice experimental; NO inserta, actualiza ni borra registros.
-- Ejecutar mediante psql (no Query Tool). Se detiene al encontrar un error.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $pre$
DECLARE v_total BIGINT; v_eventos BIGINT; v_filtrados BIGINT;
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000' THEN
        RAISE EXCEPTION 'Conectese a bd_sismologico_exp_1000; base actual: %.', current_database();
    END IF;
    SELECT (SELECT COUNT(*) FROM estacion_sismica) +
           (SELECT COUNT(*) FROM sensor) +
           (SELECT COUNT(*) FROM evento_sismico) +
           (SELECT COUNT(*) FROM lectura_onda) +
           (SELECT COUNT(*) FROM deteccion) +
           (SELECT COUNT(*) FROM alerta)
    INTO v_total;
    IF v_total <> 1000 THEN
        RAISE EXCEPTION 'Se esperaban 1000 registros; encontrados: %.', v_total;
    END IF;
    SELECT COUNT(*) INTO v_eventos FROM evento_sismico
    WHERE id_evento BETWEEN 200000000 AND 299999999;
    IF v_eventos <> 50 THEN
        RAISE EXCEPTION 'Se esperaban 50 eventos IGP; encontrados: %.', v_eventos;
    END IF;
    SELECT COUNT(*) INTO v_filtrados FROM evento_sismico
    WHERE id_evento BETWEEN 200000000 AND 299999999
      AND fecha_hora_origen >= TIMESTAMP '2010-01-01 00:00:00'
      AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
      AND magnitud >= 6;
    IF v_filtrados = 0 THEN
        RAISE EXCEPTION 'C1 no selecciona eventos en esta base: revisar muestreo antes de medir.';
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
        RAISE EXCEPTION 'Existen indices secundarios; no repetir ni mezclar escenarios.';
    END IF;
    RAISE NOTICE 'OK: base de 1000 filas; 50 IGP; % eventos elegibles para C1; sin indices secundarios.', v_filtrados;
END;
$pre$;

\echo
\echo === 5.5 - C1 / 1000 FILAS / CREACION DEL INDICE PARCIAL ===
BEGIN;
CREATE INDEX idx_ev_igp_m6_fecha
ON monitoreo_sismologico.evento_sismico (fecha_hora_origen)
INCLUDE (magnitud, profundidad_km)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND magnitud >= 6;
ANALYZE monitoreo_sismologico.evento_sismico;
COMMIT;

SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS tamano
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename = 'evento_sismico'
ORDER BY indexname;

CREATE TEMP TABLE IF NOT EXISTS piloto_c1_indice_55 (
    repeticion INTEGER PRIMARY KEY,
    fase TEXT NOT NULL,
    execution_ms NUMERIC NOT NULL,
    planning_ms NUMERIC NOT NULL,
    shared_hit BIGINT NOT NULL,
    shared_read BIGINT NOT NULL,
    temp_read BIGINT NOT NULL,
    temp_written BIGINT NOT NULL,
    uso_indice_candidato BOOLEAN NOT NULL
) ON COMMIT PRESERVE ROWS;
TRUNCATE piloto_c1_indice_55;

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
    v_iter INTEGER;
    v_root JSONB;
BEGIN
    FOR v_iter IN 1..7 LOOP
        EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || v_q INTO v_plan;
        v_root := v_plan->0->'Plan';
        INSERT INTO piloto_c1_indice_55 (
            repeticion, fase, execution_ms, planning_ms,
            shared_hit, shared_read, temp_read, temp_written,
            uso_indice_candidato
        ) VALUES (
            v_iter,
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
    RAISE NOTICE 'OK: dos calentamientos y cinco mediciones completados.';
END;
$run$;

\echo
\echo === C1 - SIETE EJECUCIONES CON INDICE (2 CALENTAMIENTOS + 5 MEDICIONES) ===
SELECT * FROM piloto_c1_indice_55 ORDER BY repeticion;

\echo
\echo === C1 - RESUMEN DE CINCO MEDICIONES CON INDICE ===
SELECT COUNT(*) AS mediciones,
       ROUND(AVG(execution_ms), 4) AS media_ms,
       ROUND(STDDEV_SAMP(execution_ms), 4) AS desviacion_ms,
       ROUND(MIN(execution_ms), 4) AS minimo_ms,
       ROUND(MAX(execution_ms), 4) AS maximo_ms,
       ROUND(AVG(shared_hit), 2) AS promedio_hit,
       ROUND(AVG(shared_read), 2) AS promedio_read,
       COUNT(*) FILTER (WHERE uso_indice_candidato) AS mediciones_que_usaron_indice
FROM piloto_c1_indice_55
WHERE fase = 'medicion';

\echo
\echo === C1 - COMPROBACION DE RESULTADOS SIN CAMBIOS ===
SELECT COUNT(*) AS eventos_filtrados,
       COUNT(DISTINCT EXTRACT(YEAR FROM fecha_hora_origen)::INTEGER) AS anios_con_resultados
FROM evento_sismico
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND fecha_hora_origen >= TIMESTAMP '2010-01-01 00:00:00'
  AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND magnitud >= 6;

\echo
\echo === EXPORTACION CSV / ESCENARIO CON INDICE ===
\copy (SELECT repeticion, fase, execution_ms, planning_ms, shared_hit, shared_read, temp_read, temp_written, uso_indice_candidato FROM piloto_c1_indice_55 ORDER BY repeticion) TO 'resultados/39_resultados_piloto_c1_con_indice_5_5.csv' WITH (FORMAT csv, HEADER true)

\echo
\echo === PILOTO CON INDICE FINALIZADO; CONSERVAR AMBOS CSV ===
