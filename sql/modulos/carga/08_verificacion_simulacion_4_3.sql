-- CS2041 - Seccion 4.3: verificacion de la simulacion en PostgreSQL.
-- Solo lectura, no crea ni modifica datos. Ejecutar desde psql o pgAdmin.

SET search_path TO monitoreo_sismologico, public;

-- 1. Cantidades totales tras la simulacion (incluyen datos del IGP).
WITH cantidades AS (
    SELECT 'estacion_sismica'::TEXT AS tabla, COUNT(*) AS encontrados, 15::BIGINT AS esperado FROM estacion_sismica
    UNION ALL SELECT 'sensor', COUNT(*), 40 FROM sensor
    UNION ALL SELECT 'lectura_onda', COUNT(*), 1190 FROM lectura_onda
    UNION ALL SELECT 'evento_sismico', COUNT(*), 24327 FROM evento_sismico
    UNION ALL SELECT 'deteccion', COUNT(*), 104 FROM deteccion
    UNION ALL SELECT 'alerta', COUNT(*), 29 FROM alerta
)
SELECT tabla, esperado, encontrados,
       CASE WHEN encontrados = esperado THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM cantidades
ORDER BY tabla;

-- 2. Confirmacion de la identidad de los eventos oficiales.
SELECT
    (SELECT COUNT(*) FROM evento_sismico
     WHERE id_evento BETWEEN 200000000 AND 299999999) AS eventos_igp,
    (SELECT COUNT(*) FROM evento_sismico
     WHERE id_evento BETWEEN 810000001 AND 810000008) AS eventos_simulados_iniciales,
    (SELECT COUNT(*) FROM evento_sismico
     WHERE id_evento BETWEEN 820300001 AND 820300030) AS eventos_simulados_nuevos,
    (SELECT COUNT(*) FROM deteccion
     WHERE id_evento BETWEEN 200000000 AND 299999999) AS detecciones_sobre_igp,
    (SELECT COUNT(*) FROM alerta
     WHERE id_evento BETWEEN 200000000 AND 299999999) AS alertas_sobre_igp;

-- 3. Recuento de cada clase de dato nuevo, dentro de su rango reservado.
SELECT 'estaciones' AS clase, COUNT(*) AS generados FROM estacion_sismica
WHERE id_estacion BETWEEN 820300001 AND 820300010
UNION ALL SELECT 'sensores', COUNT(*) FROM sensor WHERE id_sensor BETWEEN 820300001 AND 820300030
UNION ALL SELECT 'eventos', COUNT(*) FROM evento_sismico WHERE id_evento BETWEEN 820300001 AND 820300030
UNION ALL SELECT 'lecturas', COUNT(*) FROM lectura_onda WHERE id_lectura BETWEEN 820300000001 AND 820300001000
UNION ALL SELECT 'detecciones', COUNT(*) FROM deteccion WHERE id_evento BETWEEN 820300001 AND 820300030
UNION ALL SELECT 'alertas', COUNT(*) FROM alerta WHERE id_alerta BETWEEN 820300001 AND 820300024
ORDER BY clase;

-- 4. Reglas de consistencia para el lote simulado.
SELECT 'estaciones_sin_sensor' AS control, COUNT(*) AS encontrados, 0 AS esperado
FROM estacion_sismica e
WHERE e.id_estacion BETWEEN 820300001 AND 820300010
  AND NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion = e.id_estacion)
UNION ALL
SELECT 'lecturas_sin_sensor', COUNT(*), 0
FROM lectura_onda l
LEFT JOIN sensor s ON s.id_sensor = l.id_sensor
WHERE l.id_lectura BETWEEN 820300000001 AND 820300001000
  AND s.id_sensor IS NULL
UNION ALL
SELECT 'lecturas_validas_sensor_no_operativo', COUNT(*), 0
FROM lectura_onda l
JOIN sensor s ON s.id_sensor = l.id_sensor
WHERE l.id_lectura BETWEEN 820300000001 AND 820300001000
  AND l.es_valida AND s.estado <> 'operativo'
UNION ALL
SELECT 'detecciones_sin_lectura_valida', COUNT(*), 0
FROM deteccion d
WHERE d.id_evento BETWEEN 820300001 AND 820300030
  AND NOT EXISTS (
      SELECT 1 FROM lectura_onda l
      WHERE l.id_sensor = d.id_sensor
        AND l.fecha_hora = d.hora_deteccion
        AND l.es_valida
  )
UNION ALL
SELECT 'alertas_anteriores_al_evento', COUNT(*), 0
FROM alerta a
JOIN evento_sismico e ON e.id_evento = a.id_evento
WHERE a.id_alerta BETWEEN 820300001 AND 820300024
  AND a.fecha_hora_emision < e.fecha_hora_origen
ORDER BY control;

-- 5. Estadisticas de los datos simulados; no son resultados de rendimiento.
SELECT
    COUNT(*) AS nuevas_lecturas,
    COUNT(*) FILTER (WHERE es_valida) AS validas,
    COUNT(*) FILTER (WHERE NOT es_valida) AS invalidas,
    MIN(fecha_hora) AS primera_lectura,
    MAX(fecha_hora) AS ultima_lectura
FROM lectura_onda
WHERE id_lectura BETWEEN 820300000001 AND 820300001000;

-- 6. Total final esperado: 24521 registros anteriores + 1184 generados = 25705.
SELECT
    (SELECT COUNT(*) FROM estacion_sismica)
    + (SELECT COUNT(*) FROM sensor)
    + (SELECT COUNT(*) FROM lectura_onda)
    + (SELECT COUNT(*) FROM evento_sismico)
    + (SELECT COUNT(*) FROM deteccion)
    + (SELECT COUNT(*) FROM alerta) AS registros_totales,
    25705 AS esperado;
