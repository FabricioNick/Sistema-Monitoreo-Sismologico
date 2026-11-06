-- Proyecto Final CS2041: prueba de un respaldo restaurado.
-- SOLO LECTURA. Abortara si se ejecuta sobre una base distinta de la copia nueva.
\set ON_ERROR_STOP on
\pset pager off
\echo '=== VERIFICACION DE COPIA RESTAURADA (1000 REGISTROS) ==='
DO $audit$
BEGIN
  IF current_database() <> 'bd_sismologico_restauracion_1000' THEN
    RAISE EXCEPTION 'Base incorrecta: %. La auditoria solo puede ejecutarse en la copia de restauracion.', current_database();
  END IF;
END
$audit$;

SET search_path TO monitoreo_sismologico, public;

\echo '=== TABLAS Y RECUENTOS ==='
WITH esperados(tabla, esperado) AS (
  VALUES ('estacion_sismica',5::bigint), ('sensor',15::bigint),
         ('evento_sismico',100::bigint), ('lectura_onda',750::bigint),
         ('deteccion',90::bigint), ('alerta',40::bigint)
), observados(tabla, encontrado) AS (
  SELECT 'estacion_sismica',count(*) FROM estacion_sismica
  UNION ALL SELECT 'sensor',count(*) FROM sensor
  UNION ALL SELECT 'evento_sismico',count(*) FROM evento_sismico
  UNION ALL SELECT 'lectura_onda',count(*) FROM lectura_onda
  UNION ALL SELECT 'deteccion',count(*) FROM deteccion
  UNION ALL SELECT 'alerta',count(*) FROM alerta
)
SELECT e.tabla, e.esperado, o.encontrado,
       CASE WHEN e.esperado=o.encontrado THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM esperados e JOIN observados o USING (tabla) ORDER BY e.tabla;

\echo '=== PROCEDENCIA Y TRIGGERS ==='
SELECT (SELECT count(*) FROM evento_sismico WHERE id_evento BETWEEN 200000000 AND 299999999) AS eventos_igp,
       (SELECT count(*) FROM evento_sismico WHERE estado_revision='simulado') AS eventos_simulados,
       (SELECT count(*) FROM deteccion WHERE id_evento BETWEEN 200000000 AND 299999999) AS detecciones_sobre_igp,
       (SELECT count(*) FROM alerta WHERE id_evento BETWEEN 200000000 AND 299999999) AS alertas_sobre_igp;
SELECT count(*) AS triggers_implementados FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='monitoreo_sismologico' AND NOT t.tgisinternal;

\echo '=== CONTROLES DE INTEGRIDAD ==='
SELECT 'estaciones_sin_sensor' AS control,count(*) AS incumplimientos
FROM estacion_sismica e WHERE NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion=e.id_estacion)
UNION ALL SELECT 'detecciones_sin_lectura_valida',count(*) FROM deteccion d
WHERE NOT EXISTS (SELECT 1 FROM lectura_onda l WHERE l.id_sensor=d.id_sensor AND l.fecha_hora=d.hora_deteccion AND l.es_valida)
UNION ALL SELECT 'alertas_anteriores_al_evento',count(*) FROM alerta a JOIN evento_sismico ev USING(id_evento)
WHERE a.fecha_hora_emision < ev.fecha_hora_origen
UNION ALL SELECT 'lecturas_validas_sensor_inoperativo',count(*) FROM lectura_onda l JOIN sensor s USING(id_sensor)
WHERE l.es_valida AND lower(trim(s.estado)) <> 'operativo';

\echo '=== CERTIFICACION DE LA RESTAURACION ==='
DO $audit$
DECLARE v_total bigint; v_igp bigint; v_sim bigint; v_triggers bigint; v_incumplimientos bigint;
BEGIN
  IF current_database() <> 'bd_sismologico_restauracion_1000' THEN
    RAISE EXCEPTION 'No se permite auditar otra base: %',current_database();
  END IF;
  SELECT (SELECT count(*) FROM estacion_sismica)+(SELECT count(*) FROM sensor)+
         (SELECT count(*) FROM evento_sismico)+(SELECT count(*) FROM lectura_onda)+
         (SELECT count(*) FROM deteccion)+(SELECT count(*) FROM alerta) INTO v_total;
  SELECT count(*) INTO v_igp FROM evento_sismico WHERE id_evento BETWEEN 200000000 AND 299999999;
  SELECT count(*) INTO v_sim FROM evento_sismico WHERE estado_revision='simulado';
  SELECT count(*) INTO v_triggers FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='monitoreo_sismologico' AND NOT t.tgisinternal;
  SELECT (SELECT count(*) FROM estacion_sismica e WHERE NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion=e.id_estacion)) +
         (SELECT count(*) FROM deteccion d WHERE NOT EXISTS (SELECT 1 FROM lectura_onda l WHERE l.id_sensor=d.id_sensor AND l.fecha_hora=d.hora_deteccion AND l.es_valida)) +
         (SELECT count(*) FROM alerta a JOIN evento_sismico e USING(id_evento) WHERE a.fecha_hora_emision < e.fecha_hora_origen) +
         (SELECT count(*) FROM lectura_onda l JOIN sensor s USING(id_sensor) WHERE l.es_valida AND lower(trim(s.estado)) <> 'operativo') +
         (SELECT count(*) FROM deteccion WHERE id_evento BETWEEN 200000000 AND 299999999) +
         (SELECT count(*) FROM alerta WHERE id_evento BETWEEN 200000000 AND 299999999)
    INTO v_incumplimientos;
  IF v_total<>1000 OR v_igp<>50 OR v_sim<>50 OR v_triggers<>9 OR v_incumplimientos<>0
     OR (SELECT count(*) FROM estacion_sismica)<>5
     OR (SELECT count(*) FROM sensor)<>15
     OR (SELECT count(*) FROM evento_sismico)<>100
     OR (SELECT count(*) FROM lectura_onda)<>750
     OR (SELECT count(*) FROM deteccion)<>90
     OR (SELECT count(*) FROM alerta)<>40 THEN
     RAISE EXCEPTION 'REVISAR: restauracion no coincide (total=%, IGP=%, simulados=%, triggers=%, incumplimientos=%).',
       v_total,v_igp,v_sim,v_triggers,v_incumplimientos;
  END IF;
  RAISE NOTICE 'OK: respaldo restaurado y verificado, 1000 registros, 50 IGP, 50 simulados, 9 triggers, cero incumplimientos.';
END
$audit$;

SELECT current_database() AS base_restaurada,
       pg_size_pretty(pg_database_size(current_database())) AS tamano_actual;
\echo '=== FIN: COPIA RESTAURADA VERIFICADA, ORIGINALES INTACTOS ==='
