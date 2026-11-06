-- CS2041 - 4.2. Verificacion de la carga inicial, sin modificar datos.
SET search_path TO monitoreo_sismologico, public;
-- Total esperado: 232 filas (5+10+190+8+14+5).
SELECT 'estacion_sismica' AS tabla, 5 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=5 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM estacion_sismica WHERE id_estacion BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'sensor' AS tabla, 10 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=10 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM sensor WHERE id_sensor BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'lectura_onda' AS tabla, 190 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=190 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM lectura_onda WHERE id_lectura BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'evento_sismico' AS tabla, 8 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=8 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM evento_sismico WHERE id_evento BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'deteccion' AS tabla, 14 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=14 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM deteccion WHERE id_sensor BETWEEN 810000001 AND 810000999 AND id_evento BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'alerta' AS tabla, 5 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=5 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM alerta WHERE id_alerta BETWEEN 810000001 AND 810000999
ORDER BY tabla;


-- Pruebas de coherencia entre entidades y atributos.
SELECT 'estaciones_sin_sensores' AS control, COUNT(*) AS encontrados, 0 AS esperado
FROM estacion_sismica e
WHERE e.id_estacion BETWEEN 810000001 AND 810000999
AND NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion=e.id_estacion)
UNION ALL
SELECT 'lecturas_huerfanas', COUNT(*), 0
FROM lectura_onda l LEFT JOIN sensor s ON l.id_sensor=s.id_sensor
WHERE l.id_lectura BETWEEN 810000001 AND 810000999 AND s.id_sensor IS NULL
UNION ALL
SELECT 'detecciones_sin_lectura_valida', COUNT(*), 0
FROM deteccion d
WHERE d.id_sensor BETWEEN 810000001 AND 810000999
AND NOT EXISTS (SELECT 1 FROM lectura_onda l WHERE l.id_sensor=d.id_sensor AND l.fecha_hora=d.hora_deteccion AND l.es_valida)
UNION ALL
SELECT 'lecturas_validas_sensor_no_operativo', COUNT(*), 0
FROM lectura_onda l JOIN sensor s ON l.id_sensor=s.id_sensor
WHERE l.id_lectura BETWEEN 810000001 AND 810000999 AND l.es_valida AND s.estado <> 'operativo';

-- Casos diseñados para las consultas posteriores:
SELECT COUNT(*) FILTER (WHERE es_valida) AS lecturas_validas,
       COUNT(*) FILTER (WHERE NOT es_valida) AS lecturas_invalidas
FROM lectura_onda
WHERE id_lectura BETWEEN 810000001 AND 810000999;

SELECT e.id_evento, COUNT(DISTINCT d.id_sensor) AS sensores_que_detectaron,
       COUNT(DISTINCT a.id_alerta) AS alertas_emitidas
FROM evento_sismico e
LEFT JOIN deteccion d ON d.id_evento=e.id_evento
LEFT JOIN alerta a ON a.id_evento=e.id_evento
WHERE e.id_evento BETWEEN 810000001 AND 810000999
GROUP BY e.id_evento
ORDER BY e.id_evento;
