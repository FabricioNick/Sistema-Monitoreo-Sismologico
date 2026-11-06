-- Proyecto Final - Seccion 5.3.1
-- C1: diagnostico del plan CON indice secundario parcial.
-- Ejecutar SOLO en bd_sismologico_exp_1000000 DESPUES del archivo 22.
-- La consulta SQL es IDENTICA a la del diagnostico base (archivo 21).
-- No modifica ni elimina filas ni fuerza planes de ejecucion.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: %. Se requiere bd_sismologico_exp_1000000.', current_database();
    END IF;

    IF (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico) <> 120000 THEN
        RAISE EXCEPTION 'Cantidad inesperada en EVENTO_SISMICO; no se ejecuta el diagnostico.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class idx ON idx.oid = i.indexrelid
        JOIN pg_class tab ON tab.oid = i.indrelid
        JOIN pg_namespace ns ON ns.oid = tab.relnamespace
        WHERE ns.nspname = 'monitoreo_sismologico'
          AND tab.relname = 'evento_sismico'
          AND idx.relname = 'idx_ev_igp_m6_fecha'
          AND i.indisvalid
    ) THEN
        RAISE EXCEPTION 'No existe el indice candidato valido. Ejecutar primero el archivo 22.';
    END IF;
END;
$$;

\echo
\echo === C1 - INDICES DISPONIBLES ===
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename = 'evento_sismico'
ORDER BY indexname;

\echo
\echo === C1 - PLAN REAL CON INDICE SECUNDARIO ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
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
ORDER BY anio_utc;

\echo
\echo === C1 - COMPROBACION DE RESULTADOS TRAS CREAR EL INDICE ===
WITH resultado AS (
    SELECT EXTRACT(YEAR FROM ev.fecha_hora_origen)::INTEGER AS anio_utc,
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
)
SELECT COUNT(*) AS anios_con_resultados,
       SUM(cantidad_eventos) AS sismos_filtrados,
       CASE WHEN COUNT(*) = 15 AND SUM(cantidad_eventos) = 70
            THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM resultado;

\echo
\echo === C1 - DIAGNOSTICO COMPLETADO (UNA EJECUCION; NO ES PROMEDIO) ===
