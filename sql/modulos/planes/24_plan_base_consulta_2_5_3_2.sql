-- Proyecto Final: Sistema de Monitoreo Sismologico y Alerta Temprana
-- Seccion 5.3.2: diagnostico BASE de la Consulta 2.
-- Ejecutar SOLO en bd_sismologico_exp_1000000 con psql.
-- Este script ELIMINA el indice secundario de la Consulta 1, ya evaluado,
-- para aislar la linea base de la Consulta 2. NO elimina datos ni llaves.
-- Los cuatro archivos .dump respaldados permanecen intactos.

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO monitoreo_sismologico, public;

-- Verificar la base y la ausencia de otros indices secundarios en
-- las dos tablas involucradas. Se admite unicamente el indice C1
-- que sera retirado a continuacion.
DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: %. Se requiere bd_sismologico_exp_1000000.', current_database();
    END IF;
    IF (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico) <> 120000
       OR (SELECT COUNT(*) FROM monitoreo_sismologico.estacion_sismica) <> 100 THEN
        RAISE EXCEPTION 'Cantidades distintas de la escala aprobada; revisar antes de medir.';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname IN ('estacion_sismica', 'evento_sismico')
          AND i.indexrelid <> COALESCE(
              to_regclass('monitoreo_sismologico.idx_ev_igp_m6_fecha')::oid, 0::oid)
          AND NOT EXISTS (
              SELECT 1
              FROM pg_constraint c
              WHERE c.conindid = i.indexrelid
                AND c.contype IN ('p', 'u', 'x')
          )
    ) THEN
        RAISE EXCEPTION 'Existen otros indices secundarios en las tablas de C2. Revisar antes de continuar.';
    END IF;
END;
$$;

\echo
\echo === C2 - RESTABLECIMIENTO DEL ESCENARIO SIN INDICES SECUNDARIOS ===
DROP INDEX IF EXISTS monitoreo_sismologico.idx_ev_igp_m6_fecha;

\echo
\echo === C2 - INDICES EXISTENTES EN LAS TABLAS DE LA CONSULTA ===
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename IN ('estacion_sismica', 'evento_sismico')
ORDER BY tablename, indexname;

-- Recalcular estadisticas sin cambiar filas de las tablas.
ANALYZE monitoreo_sismologico.estacion_sismica;
ANALYZE monitoreo_sismologico.evento_sismico;

\echo
\echo === C2 - PLAN REAL SIN INDICES SECUNDARIOS ===
-- Sentencia identica a la Consulta 2 del archivo 15_consultas_5_1.sql.
-- Ventana rectangular +/-1.5 grados: NO equivale a distancia geodesica.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
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
LIMIT 10;

\echo
\echo === C2 - DIAGNOSTICO TERMINADO: CONSERVAR EL PLAN COMPLETO ===
