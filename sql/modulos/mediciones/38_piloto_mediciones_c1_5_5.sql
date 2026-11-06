-- Proyecto Final / 5.5 / Piloto de mediciones repetidas
-- C1, 1000 registros, escenario SIN indices secundarios.
-- Dos calentamientos y cinco mediciones: tiempos de EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON).
-- El script NO cambia datos ni crea indices; solo una tabla temporal de resultados.
-- No ejecutar desde Query Tool; utilizar psql en la misma sesion.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $pre$
DECLARE v_total BIGINT;
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000' THEN
        RAISE EXCEPTION 'Debe conectarse a bd_sismologico_exp_1000.';
    END IF;
    SELECT (SELECT COUNT(*) FROM estacion_sismica) +
           (SELECT COUNT(*) FROM sensor) +
           (SELECT COUNT(*) FROM evento_sismico) +
           (SELECT COUNT(*) FROM lectura_onda) +
           (SELECT COUNT(*) FROM deteccion) +
           (SELECT COUNT(*) FROM alerta) INTO v_total;
    IF v_total <> 1000 THEN
        RAISE EXCEPTION 'Volumen inesperado: % registros', v_total;
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
        RAISE EXCEPTION 'Se detectaron indices secundarios: no se puede medir el escenario base.';
    END IF;
    RAISE NOTICE 'OK: 1000 registros e indices secundarios ausentes.';
END;
$pre$;

CREATE TEMP TABLE IF NOT EXISTS piloto_c1_55 (
    repeticion INTEGER PRIMARY KEY,
    fase TEXT NOT NULL,
    execution_ms NUMERIC NOT NULL,
    planning_ms NUMERIC NOT NULL,
    shared_hit BIGINT NOT NULL,
    shared_read BIGINT NOT NULL,
    temp_read BIGINT NOT NULL,
    temp_written BIGINT NOT NULL
) ON COMMIT PRESERVE ROWS;
TRUNCATE piloto_c1_55;

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
        INSERT INTO piloto_c1_55 (
            repeticion, fase, execution_ms, planning_ms,
            shared_hit, shared_read, temp_read, temp_written
        ) VALUES (
            v_iter,
            CASE WHEN v_iter <= 2 THEN 'calentamiento' ELSE 'medicion' END,
            (v_plan->0->>'Execution Time')::NUMERIC,
            (v_plan->0->>'Planning Time')::NUMERIC,
            COALESCE((v_root->>'Shared Hit Blocks')::BIGINT, 0),
            COALESCE((v_root->>'Shared Read Blocks')::BIGINT, 0),
            COALESCE((v_root->>'Temp Read Blocks')::BIGINT, 0),
            COALESCE((v_root->>'Temp Written Blocks')::BIGINT, 0)
        );
    END LOOP;
END;
$run$;

\echo
\echo === 5.5 - C1 / 1000 FILAS / SIN INDICES SECUNDARIOS ===
SELECT * FROM piloto_c1_55 ORDER BY repeticion;

\echo
\echo === RESUMEN SOLO CINCO MEDICIONES (SIN LOS CALENTAMIENTOS) ===
SELECT COUNT(*) AS mediciones,
       ROUND(AVG(execution_ms), 4) AS media_ms,
       ROUND(STDDEV_SAMP(execution_ms), 4) AS desviacion_ms,
       ROUND(MIN(execution_ms), 4) AS minimo_ms,
       ROUND(MAX(execution_ms), 4) AS maximo_ms,
       ROUND(AVG(shared_hit), 2) AS promedio_hit,
       ROUND(AVG(shared_read), 2) AS promedio_read
FROM piloto_c1_55 WHERE fase = 'medicion';

\echo
\echo === EXPORTAR CSV AL DIRECTORIO SQL ===
\copy (SELECT repeticion, fase, execution_ms, planning_ms, shared_hit, shared_read, temp_read, temp_written FROM piloto_c1_55 ORDER BY repeticion) TO 'resultados/38_resultados_piloto_c1_5_5.csv' WITH (FORMAT csv, HEADER true)

\echo
\echo === PILOTO FINALIZADO: COPIAR RESULTADO Y NO VOLVER A EJECUTAR SI YA FUE REGISTRADO ===
