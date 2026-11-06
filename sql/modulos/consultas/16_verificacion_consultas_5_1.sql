-- Proyecto Final - Seccion 5.1: verificacion de las cinco consultas.
-- Ejecutar tras 15_consultas_5_1.sql en bd_sismologico con psql.
-- No crea indices ni modifica registros permanentes.
-- La tabla temporal se elimina mediante ROLLBACK.

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

CREATE TEMP TABLE control_consultas_51 ON COMMIT DROP AS
SELECT 1 AS numero, 'Historico IGP por anio'::TEXT AS consulta,
       (SELECT COUNT(*) FROM (
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
       ) AS resultado) AS filas_obtenidas
UNION ALL
SELECT 2 AS numero, 'Ventanas geograficas de estaciones'::TEXT AS consulta,
       (SELECT COUNT(*) FROM (
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
       ) AS resultado) AS filas_obtenidas
UNION ALL
SELECT 3 AS numero, 'Calidad de lecturas por estacion'::TEXT AS consulta,
       (SELECT COUNT(*) FROM (
      SELECT
          e.id_estacion,
          e.codigo AS codigo_estacion,
          COUNT(DISTINCT s.id_sensor) AS sensores_con_lecturas,
          COUNT(*) AS total_lecturas,
          COUNT(*) FILTER (WHERE l.es_valida) AS lecturas_validas,
          COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
          ROUND(100.0 * COUNT(*) FILTER (WHERE NOT l.es_valida)
                / NULLIF(COUNT(*), 0), 2) AS porcentaje_invalidas
      FROM estacion_sismica e
      JOIN sensor s ON s.id_estacion = e.id_estacion
      JOIN lectura_onda l ON l.id_sensor = s.id_sensor
      WHERE l.fecha_hora >= TIMESTAMP '2026-08-01 00:00:00'
        AND l.fecha_hora < TIMESTAMP '2026-12-01 00:00:00'
      GROUP BY e.id_estacion, e.codigo
      HAVING COUNT(*) >= 10
      ORDER BY porcentaje_invalidas DESC, total_lecturas DESC, e.id_estacion
       ) AS resultado) AS filas_obtenidas
UNION ALL
SELECT 4 AS numero, 'Latencia de deteccion y alerta'::TEXT AS consulta,
       (SELECT COUNT(*) FROM (
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
      )
      SELECT
          ev.id_evento,
          ev.fecha_hora_origen,
          ev.magnitud,
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
       ) AS resultado) AS filas_obtenidas
UNION ALL
SELECT 5 AS numero, 'Sensores sin deteccion en agosto'::TEXT AS consulta,
       (SELECT COUNT(*) FROM (
      SELECT
          s.id_sensor,
          s.numero_serie,
          e.codigo AS codigo_estacion,
          s.estado AS estado_sensor,
          COUNT(*) AS lecturas_periodo,
          COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
          MAX(l.fecha_hora) AS ultima_lectura
      FROM sensor s
      JOIN estacion_sismica e ON e.id_estacion = s.id_estacion
      JOIN lectura_onda l ON l.id_sensor = s.id_sensor
      WHERE l.fecha_hora >= TIMESTAMP '2026-08-01 00:00:00'
        AND l.fecha_hora < TIMESTAMP '2026-09-01 00:00:00'
        AND NOT EXISTS (
            SELECT 1
            FROM deteccion d
            WHERE d.id_sensor = s.id_sensor
              AND d.hora_deteccion >= TIMESTAMP '2026-08-01 00:00:00'
              AND d.hora_deteccion < TIMESTAMP '2026-09-01 00:00:00'
        )
      GROUP BY s.id_sensor, s.numero_serie, e.codigo, s.estado
      HAVING COUNT(*) >= 20
      ORDER BY lecturas_invalidas DESC, lecturas_periodo DESC, s.id_sensor
      LIMIT 15
       ) AS resultado) AS filas_obtenidas;

SELECT numero, consulta, filas_obtenidas,
       CASE WHEN filas_obtenidas > 0 THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM control_consultas_51
ORDER BY numero;

SELECT tabla, encontrados, esperado,
       CASE WHEN encontrados = esperado THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM (
    SELECT 'estacion_sismica'::TEXT AS tabla, (SELECT COUNT(*) FROM estacion_sismica) AS encontrados, 15::BIGINT AS esperado
    UNION ALL SELECT 'sensor', (SELECT COUNT(*) FROM sensor), 40
    UNION ALL SELECT 'lectura_onda', (SELECT COUNT(*) FROM lectura_onda), 1190
    UNION ALL SELECT 'evento_sismico', (SELECT COUNT(*) FROM evento_sismico), 24327
    UNION ALL SELECT 'deteccion', (SELECT COUNT(*) FROM deteccion), 104
    UNION ALL SELECT 'alerta', (SELECT COUNT(*) FROM alerta), 29
) AS cantidades
ORDER BY tabla;

DO $$
DECLARE
    numero_consultas INTEGER;
    consultas_vacias INTEGER;
    registros_base BIGINT;
    eventos_igp BIGINT;
BEGIN
    SELECT COUNT(*), COUNT(*) FILTER (WHERE filas_obtenidas = 0)
      INTO numero_consultas, consultas_vacias
      FROM control_consultas_51;

    SELECT (SELECT COUNT(*) FROM estacion_sismica)
         + (SELECT COUNT(*) FROM sensor)
         + (SELECT COUNT(*) FROM lectura_onda)
         + (SELECT COUNT(*) FROM evento_sismico)
         + (SELECT COUNT(*) FROM deteccion)
         + (SELECT COUNT(*) FROM alerta)
      INTO registros_base;

    SELECT COUNT(*) INTO eventos_igp
    FROM evento_sismico
    WHERE id_evento BETWEEN 200000000 AND 299999999;

    IF numero_consultas <> 5 OR consultas_vacias <> 0
       OR registros_base <> 25705 OR eventos_igp <> 24289 THEN
        RAISE EXCEPTION 'Fallo en verificacion 5.1: consultas=%, vacias=%, registros=%, IGP=%',
            numero_consultas, consultas_vacias, registros_base, eventos_igp;
    END IF;

    RAISE NOTICE 'OK: 5 consultas devolvieron filas; 25705 registros y 24289 eventos IGP conservados.';
END;
$$;

ROLLBACK;
