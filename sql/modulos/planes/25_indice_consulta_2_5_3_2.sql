-- Proyecto Final - 5.3.2 / Consulta 2: indice candidato.
-- Ejecutar SOLO en bd_sismologico_exp_1000000, despues del archivo 24.
-- No borra filas, tablas, llaves, triggers ni modifica los dumps.
-- Se conserva una firma del resultado ANTES de crear el indice.

\set ON_ERROR_STOP on
\pset pager off
BEGIN;
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Conectar primero a bd_sismologico_exp_1000000.';
    END IF;
    IF (SELECT COUNT(*) FROM evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM estacion_sismica) <> 100 THEN
        RAISE EXCEPTION 'Cantidad inesperada de eventos o estaciones.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid=i.indrelid
        JOIN pg_namespace n ON n.oid=t.relnamespace
        WHERE n.nspname='monitoreo_sismologico'
          AND t.relname IN ('evento_sismico','estacion_sismica')
          AND NOT EXISTS (
            SELECT 1 FROM pg_constraint c
            WHERE c.conindid=i.indexrelid AND c.contype IN ('p','u','x')
          )
    ) THEN
        RAISE EXCEPTION 'Se detectaron indices secundarios no esperados. Ejecutar antes archivo 24.';
    END IF;
END;
$$;

\echo
\echo === C2 - FIRMA DEL RESULTADO ORIGINAL ANTES DEL INDICE ===
WITH resultado_consulta AS (
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
)
SELECT
    COUNT(*) AS filas_resultado,
    COALESCE(SUM(eventos_en_ventana),0) AS coincidencias_en_top10,
    MD5(COALESCE(STRING_AGG(TO_JSONB(r)::text, '|' ORDER BY eventos_en_ventana DESC, id_estacion),'')) AS firma
FROM resultado_consulta r
\gset c2_base_
\echo Filas: :c2_base_filas_resultado
\echo Coincidencias en top 10: :c2_base_coincidencias_en_top10
\echo Firma base: :c2_base_firma

\echo
\echo === C2 - INDICE PARCIAL PARA VENTANAS GEOGRAFICAS ===
-- El predicado replica los filtros constantes de la consulta.
-- La clave (latitud, longitud) permite evaluar los rangos dinamicos
-- por estacion; INCLUDE aporta magnitud para AVG y MAX.
CREATE INDEX idx_ev_igp_geo_c2
ON monitoreo_sismologico.evento_sismico
    (latitud_epicentro, longitud_epicentro)
INCLUDE (magnitud)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00'
  AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND magnitud >= 5;

ANALYZE monitoreo_sismologico.evento_sismico;

\echo
\echo === C2 - INDICES ACTUALES EN EVENTO_SISMICO ===
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='monitoreo_sismologico' AND tablename='evento_sismico'
ORDER BY indexname;

\echo
\echo === C2 - ESPACIO OCUPADO POR EL NUEVO INDICE ===
SELECT pg_size_pretty(
    pg_relation_size('monitoreo_sismologico.idx_ev_igp_geo_c2'::regclass)
) AS espacio_indice_c2;

COMMIT;
\echo
\echo === C2 - INDICE CREADO. CONTINUAR CON EL ARCHIVO 26 ===
