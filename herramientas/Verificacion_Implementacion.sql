-- VERIFICACION DE LA IMPLEMENTACION — CAPITULO 4
-- Solo lectura. Ejecutar en bd_sismologico (NO en bases experimentales).
-- Comprobar resultados antes de incorporar nuevas capturas o cifras al informe.
\set ON_ERROR_STOP on
\pset pager off
\echo '================= VERIFICACION DE IMPLEMENTACION ================='
SELECT current_database() AS base_verificada, current_user AS usuario, version() AS version_postgresql;
BEGIN READ ONLY;
SET LOCAL search_path TO monitoreo_sismologico, public;

\echo '[1] Filas por relacion, luego total'
SELECT tabla, filas FROM (
  SELECT 'ESTACION_SISMICA' AS tabla, COUNT(*) AS filas FROM estacion_sismica
  UNION ALL SELECT 'SENSOR', COUNT(*) FROM sensor
  UNION ALL SELECT 'LECTURA_ONDA', COUNT(*) FROM lectura_onda
  UNION ALL SELECT 'EVENTO_SISMICO', COUNT(*) FROM evento_sismico
  UNION ALL SELECT 'DETECCION', COUNT(*) FROM deteccion
  UNION ALL SELECT 'ALERTA', COUNT(*) FROM alerta
) c ORDER BY tabla;
SELECT
 (SELECT COUNT(*) FROM estacion_sismica)
+(SELECT COUNT(*) FROM sensor)
+(SELECT COUNT(*) FROM lectura_onda)
+(SELECT COUNT(*) FROM evento_sismico)
+(SELECT COUNT(*) FROM deteccion)
+(SELECT COUNT(*) FROM alerta) AS registros_totales;

\echo '[2] Inventario de restricciones declarativas'
SELECT CASE con.contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY'
 WHEN 'u' THEN 'UNIQUE' WHEN 'c' THEN 'CHECK'
 WHEN 'n' THEN 'NOT NULL' ELSE con.contype::TEXT END AS tipo,
 COUNT(*) AS cantidad
FROM pg_constraint con
JOIN pg_class c ON c.oid=con.conrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='monitoreo_sismologico' AND con.contype IN ('p','f','u','c','n')
GROUP BY con.contype ORDER BY tipo;
SELECT COUNT(*) AS columnas_not_null
FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='monitoreo_sismologico' AND c.relkind IN ('r','p')
 AND a.attnum>0 AND NOT a.attisdropped AND a.attnotnull;

\echo '[3] Inventario de vistas, procedimientos y disparadores'
SELECT 'vistas' AS objeto, COUNT(*) AS cantidad FROM pg_views WHERE schemaname='monitoreo_sismologico'
UNION ALL
SELECT 'procedimientos', COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='monitoreo_sismologico' AND p.prokind='p'
UNION ALL
SELECT 'disparadores', COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='monitoreo_sismologico' AND NOT t.tgisinternal;
SELECT t.tgname AS disparador, t.tgdeferrable AS diferible,
 t.tginitdeferred AS inicialmente_diferido,
 t.tgenabled AS estado
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='monitoreo_sismologico' AND NOT t.tgisinternal
ORDER BY t.tgname;

\echo '[4] Procedencia oficial, datos simulados y validacion de lecturas'
SELECT
 COUNT(*) FILTER (WHERE id_evento BETWEEN 200000000 AND 299999999) AS eventos_igp,
 COUNT(*) FILTER (WHERE id_evento BETWEEN 810000001 AND 810000008
                   OR id_evento BETWEEN 820300001 AND 820300030) AS eventos_sinteticos,
 COUNT(*) AS total_eventos
FROM evento_sismico;
SELECT COUNT(*) FILTER (WHERE es_valida) AS lecturas_validas,
 COUNT(*) FILTER (WHERE NOT es_valida) AS lecturas_invalidas,
 COUNT(*) AS total_lecturas FROM lectura_onda;

\echo '[5] Pruebas de consistencia sin modificar datos'
SELECT
 (SELECT COUNT(*) FROM estacion_sismica es WHERE NOT EXISTS
  (SELECT 1 FROM sensor s WHERE s.id_estacion=es.id_estacion)) AS estaciones_sin_sensor,
 (SELECT COUNT(*) FROM deteccion d WHERE NOT EXISTS
  (SELECT 1 FROM lectura_onda l WHERE l.id_sensor=d.id_sensor
   AND l.fecha_hora=d.hora_deteccion AND l.es_valida)) AS detecciones_sin_lectura_valida,
 (SELECT COUNT(*) FROM alerta a JOIN evento_sismico e ON e.id_evento=a.id_evento
   WHERE a.fecha_hora_emision < e.fecha_hora_origen) AS alertas_antes_del_origen;

\echo '[6] Cardinalidad de las cinco vistas'
SELECT 'vw_sensores_actividad' AS vista, COUNT(*) AS filas FROM vw_sensores_actividad
UNION ALL SELECT 'vw_estaciones_resumen', COUNT(*) FROM vw_estaciones_resumen
UNION ALL SELECT 'vw_eventos_seguimiento', COUNT(*) FROM vw_eventos_seguimiento
UNION ALL SELECT 'vw_alertas_detalle', COUNT(*) FROM vw_alertas_detalle
UNION ALL SELECT 'vw_igp_resumen_mensual', COUNT(*) FROM vw_igp_resumen_mensual;

COMMIT;
\echo 'Fin de la verificacion: no se modifico ninguna tabla.'
