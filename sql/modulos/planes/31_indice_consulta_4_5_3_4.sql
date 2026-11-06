-- Proyecto Final - Seccion 5.3.4 - Consulta 4.
-- Indices candidatos para MIN(fecha) y COUNT(*) por evento.
-- Ejecutar exclusivamente en bd_sismologico_exp_1000000 despues del archivo 30.
-- El archivo 32 debe ejecutarse EN LA MISMA SESION de psql.
-- No modifica registros, llaves primarias, triggers o archivos .dump.

\set ON_ERROR_STOP on
\pset pager off
BEGIN;
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Conectese primero a bd_sismologico_exp_1000000.';
    END IF;
    IF (SELECT COUNT(*) FROM evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM deteccion) <> 3500
       OR (SELECT COUNT(*) FROM alerta) <> 1100 THEN
        RAISE EXCEPTION 'La distribucion no coincide con la base experimental verificada.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname IN ('evento_sismico', 'deteccion', 'alerta')
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid = i.indexrelid AND c.contype IN ('p','u','x')
          )
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios en las tablas de la Consulta 4; revise el escenario base.';
    END IF;
END;
$$;

\echo
\echo === C4 - CONFIGURACION SIN CAMBIOS ===
SHOW work_mem;
SHOW enable_seqscan;
SHOW enable_indexscan;
SHOW enable_indexonlyscan;

\echo
\echo === C4 - FIRMA DEL RESULTADO BASE ===
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
), resultado_consulta AS (
    SELECT
        ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
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
)
SELECT COUNT(*) AS filas_resultado,
       COALESCE(SUM(total_detecciones), 0) AS detecciones_top15,
       COALESCE(SUM(total_alertas), 0) AS alertas_top15,
       MD5(COALESCE(STRING_AGG(TO_JSONB(r)::text, '|'
           ORDER BY r.fecha_hora_origen DESC, r.id_evento), '')) AS firma
FROM resultado_consulta r
\gset c4_base_
\echo Filas base: :c4_base_filas_resultado
\echo Detecciones en top 15: :c4_base_detecciones_top15
\echo Alertas en top 15: :c4_base_alertas_top15
\echo Firma base: :c4_base_firma

\echo
\echo === C4 - CREACION DE DOS INDICES CANDIDATOS ===
-- Las dos claves comienzan por id_evento, que se emplea en el GROUP BY.
-- La segunda columna aporta el orden temporal requerido por MIN.
-- No se incluyen columnas adicionales: COUNT(*) no las necesita.
CREATE INDEX idx_det_evento_hora_c4
    ON monitoreo_sismologico.deteccion (id_evento, hora_deteccion);
CREATE INDEX idx_alerta_evento_hora_c4
    ON monitoreo_sismologico.alerta (id_evento, fecha_hora_emision);

ANALYZE monitoreo_sismologico.deteccion;
ANALYZE monitoreo_sismologico.alerta;

\echo
\echo === C4 - INDICES ACTUALES DE DETECCION Y ALERTA ===
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename IN ('deteccion', 'alerta')
ORDER BY tablename, indexname;

\echo
\echo === C4 - ESPACIO OCUPADO POR LOS INDICES CANDIDATOS ===
SELECT 'deteccion' AS tabla,
       pg_size_pretty(pg_relation_size('monitoreo_sismologico.idx_det_evento_hora_c4'::regclass)) AS tamano
UNION ALL
SELECT 'alerta',
       pg_size_pretty(pg_relation_size('monitoreo_sismologico.idx_alerta_evento_hora_c4'::regclass));

COMMIT;
\echo
\echo === C4 - CREACION FINALIZADA; CONTINUAR CON EL ARCHIVO 32 EN ESTA SESION ===
