-- Proyecto Final - Seccion 5.2: auditoria de UNA base experimental.
-- Solo consultas SELECT. Ejecutar despues de completar el archivo 18.
\set ON_ERROR_STOP on
SET search_path TO monitoreo_sismologico, public;

WITH parametros AS (
SELECT * FROM (VALUES
    ('bd_sismologico_exp_1000',       1000,   5,  15,    100,     50,    750,    90,   40),
    ('bd_sismologico_exp_10000',     10000,  10,  30,   2000,    800,   7550,   300,  110),
    ('bd_sismologico_exp_100000',   100000,  25,  75,  24000,  12000,  74700,   900,  300),
    ('bd_sismologico_exp_1000000', 1000000, 100, 300, 120000,  24289, 875000, 3500, 1100)
) AS v(nombre,total,n_est,n_sen,n_evt,n_igp,n_lec,n_det,n_ale)
WHERE nombre = current_database()
), cantidades AS (
SELECT 'estacion_sismica' AS tabla, n_est AS esperado,
       (SELECT COUNT(*) FROM estacion_sismica) AS encontrado FROM parametros
UNION ALL SELECT 'sensor',n_sen,(SELECT COUNT(*) FROM sensor) FROM parametros
UNION ALL SELECT 'evento_sismico',n_evt,(SELECT COUNT(*) FROM evento_sismico) FROM parametros
UNION ALL SELECT 'lectura_onda',n_lec,(SELECT COUNT(*) FROM lectura_onda) FROM parametros
UNION ALL SELECT 'deteccion',n_det,(SELECT COUNT(*) FROM deteccion) FROM parametros
UNION ALL SELECT 'alerta',n_ale,(SELECT COUNT(*) FROM alerta) FROM parametros
)
SELECT tabla, esperado, encontrado,
       CASE WHEN esperado=encontrado THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM cantidades ORDER BY tabla;

SELECT (SELECT COUNT(*) FROM evento_sismico WHERE id_evento BETWEEN 200000000 AND 299999999) AS eventos_igp_reales,
       (SELECT COUNT(*) FROM evento_sismico WHERE estado_revision='simulado') AS eventos_ficticios,
       (SELECT COUNT(*) FROM deteccion WHERE id_evento BETWEEN 200000000 AND 299999999) AS detecciones_sobre_igp,
       (SELECT COUNT(*) FROM alerta WHERE id_evento BETWEEN 200000000 AND 299999999) AS alertas_sobre_igp;

SELECT 'estaciones_sin_sensor' AS control, COUNT(*) AS incumplimientos
FROM estacion_sismica e WHERE NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion=e.id_estacion)
UNION ALL
SELECT 'detecciones_sin_lectura_valida',COUNT(*) FROM deteccion d
WHERE NOT EXISTS (SELECT 1 FROM lectura_onda l WHERE l.id_sensor=d.id_sensor AND l.fecha_hora=d.hora_deteccion AND l.es_valida)
UNION ALL
SELECT 'alertas_anteriores_al_evento',COUNT(*) FROM alerta a JOIN evento_sismico e USING(id_evento)
WHERE a.fecha_hora_emision < e.fecha_hora_origen
UNION ALL
SELECT 'lecturas_validas_sensor_inoperativo',COUNT(*) FROM lectura_onda l JOIN sensor s USING(id_sensor)
WHERE l.es_valida AND LOWER(TRIM(s.estado)) <> 'operativo';

SELECT COUNT(*) AS triggers_implementados
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='monitoreo_sismologico' AND NOT t.tgisinternal;

SELECT current_database() AS base_experimental,
       pg_size_pretty(pg_database_size(current_database())) AS espacio_ocupado;

DO $$
DECLARE v_total BIGINT; v_esperado BIGINT; v_igp INTEGER;
BEGIN
    SELECT total,n_igp INTO v_esperado,v_igp
    FROM (VALUES
      ('bd_sismologico_exp_1000',1000,50),
      ('bd_sismologico_exp_10000',10000,800),
      ('bd_sismologico_exp_100000',100000,12000),
      ('bd_sismologico_exp_1000000',1000000,24289)
    ) AS p(nombre,total,n_igp)
    WHERE nombre=current_database();
    IF NOT FOUND THEN RAISE EXCEPTION 'No es una base experimental prevista'; END IF;
    SELECT (SELECT COUNT(*) FROM estacion_sismica)
         + (SELECT COUNT(*) FROM sensor)
         + (SELECT COUNT(*) FROM evento_sismico)
         + (SELECT COUNT(*) FROM lectura_onda)
         + (SELECT COUNT(*) FROM deteccion)
         + (SELECT COUNT(*) FROM alerta) INTO v_total;
    IF v_total <> v_esperado
       OR (SELECT COUNT(*) FROM evento_sismico WHERE id_evento BETWEEN 200000000 AND 299999999)<>v_igp
       OR (SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
           JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='monitoreo_sismologico' AND NOT t.tgisinternal)<>9
       OR EXISTS (SELECT 1 FROM estacion_sismica e
            WHERE NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion=e.id_estacion))
       OR EXISTS (SELECT 1 FROM deteccion d
            WHERE NOT EXISTS (SELECT 1 FROM lectura_onda l
                WHERE l.id_sensor=d.id_sensor AND l.fecha_hora=d.hora_deteccion AND l.es_valida))
       OR EXISTS (SELECT 1 FROM deteccion WHERE id_evento BETWEEN 200000000 AND 299999999)
       OR EXISTS (SELECT 1 FROM alerta WHERE id_evento BETWEEN 200000000 AND 299999999) THEN
        RAISE EXCEPTION 'REVISAR: escala, catalogo, triggers o integridad';
    END IF;
    RAISE NOTICE 'OK: base %, % filas, % eventos IGP reales y 9 triggers.',
       current_database(),v_total,v_igp;
END;
$$;
