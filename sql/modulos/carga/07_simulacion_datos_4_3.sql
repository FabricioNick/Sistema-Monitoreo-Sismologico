-- CS2041 - Seccion 4.3: simulacion reproducible de datos faltantes.
-- Ejecutar con psql: \i '.../07_simulacion_datos_4_3.sql'
-- PRECONDICION: carga inicial y catalogo IGP confirmados en PostgreSQL.
-- NO elimina ni modifica registros anteriores ni agrega indices.
-- Los nuevos IDs comienzan en 820300001 y se reservan a la simulacion.
-- No se agregan detecciones ni alertas a los eventos oficiales del IGP.
-- Ejecutar una sola vez. Si ocurre un error, hacer ROLLBACK antes de reintentar.

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

-- 0. Comprobar datos base y ausencia de una simulacion anterior.
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM evento_sismico
        WHERE id_evento BETWEEN 200000000 AND 299999999) <> 24289
       OR (SELECT COUNT(*) FROM evento_sismico
        WHERE id_evento BETWEEN 810000001 AND 810000008) <> 8
       OR (SELECT COUNT(*) FROM estacion_sismica
        WHERE id_estacion BETWEEN 810000001 AND 810000005) <> 5
       OR (SELECT COUNT(*) FROM sensor
        WHERE id_sensor BETWEEN 810000001 AND 810000010) <> 10
       OR (SELECT COUNT(*) FROM lectura_onda
        WHERE id_lectura BETWEEN 810000001 AND 810000190) <> 190
       OR (SELECT COUNT(*) FROM deteccion
        WHERE id_evento BETWEEN 810000001 AND 810000008) <> 14
       OR (SELECT COUNT(*) FROM alerta
        WHERE id_alerta BETWEEN 810000001 AND 810000005) <> 5 THEN
        RAISE EXCEPTION 'La carga base no coincide con la verificada en 4.2. No se generan datos.';
    END IF;

    IF EXISTS (SELECT 1 FROM estacion_sismica
               WHERE id_estacion BETWEEN 820300001 AND 820300010)
       OR EXISTS (SELECT 1 FROM sensor
               WHERE id_sensor BETWEEN 820300001 AND 820300030)
       OR EXISTS (SELECT 1 FROM evento_sismico
               WHERE id_evento BETWEEN 820300001 AND 820300030)
       OR EXISTS (SELECT 1 FROM lectura_onda
               WHERE id_lectura BETWEEN 820300000001 AND 820300001000)
       OR EXISTS (SELECT 1 FROM deteccion
               WHERE id_sensor BETWEEN 820300001 AND 820300030)
       OR EXISTS (SELECT 1 FROM alerta
               WHERE id_alerta BETWEEN 820300001 AND 820300024) THEN
        RAISE EXCEPTION 'Ya hay identificadores reservados para 4.3. No repetir esta carga.';
    END IF;
END;
$$;

-- 1. Diez estaciones ficticias (ninguna pretende representar al IGP).
INSERT INTO estacion_sismica (
    id_estacion, codigo, nombre, latitud, longitud, altitud,
    departamento, provincia, distrito, fecha_instalacion, estado
)
SELECT
    820300001 + g,
    'SIM43-EST-' || LPAD((g + 1)::TEXT, 2, '0'),
    'Estacion simulada de prueba ' || LPAD((g + 1)::TEXT, 2, '0'),
    -5.5::NUMERIC - g * 1.1::NUMERIC,
    -78.4::NUMERIC + g * 0.21::NUMERIC,
    100::NUMERIC + g * 85::NUMERIC,
    NULL, NULL, NULL, DATE '2024-01-01', 'operativa'
FROM generate_series(0, 9) AS serie(g);

-- 2. Treinta sensores ficticios: tres por estacion, todos operativos.
INSERT INTO sensor (
    id_sensor, numero_serie, tipo, modelo, unidad_medida,
    frecuencia_muestreo, fecha_instalacion, fecha_ultimo_mantenimiento,
    estado, id_estacion
)
SELECT
    820300001 + g,
    'SIM43-SEN-' || LPAD((g + 1)::TEXT, 2, '0'),
    'acelerometro', 'SIM-43', 'm/s2',
    CASE WHEN g % 2 = 0 THEN 50 ELSE 100 END,
    DATE '2025-01-01', NULL,
    'operativo', 820300001 + (g / 3)
FROM generate_series(0, 29) AS serie(g);

-- 3. Treinta eventos ficticios independientes del catalogo del IGP.
INSERT INTO evento_sismico (
    id_evento, fecha_hora_origen, latitud_epicentro,
    longitud_epicentro, profundidad_km, magnitud,
    tipo_magnitud, intensidad_maxima, referencia_geografica,
    estado_revision
)
SELECT
    820300001 + g,
    TIMESTAMP '2026-08-01 00:00:00' + g * INTERVAL '1 day',
    -8::NUMERIC - g * 0.15::NUMERIC,
    -77.5::NUMERIC + g * 0.10::NUMERIC,
    5::NUMERIC + g,
    3.4::NUMERIC + (g % 15) * 0.1::NUMERIC,
    NULL, NULL, NULL, 'simulado'
FROM generate_series(0, 29) AS serie(g);

-- 4. Mil lecturas, distribuidas entre 30 sensores y 30 eventos simulados.
-- La fecha coincide con el evento de la misma tanda, mas segundos por sensor.
-- Los ultimos 100 registros repiten cuatro tandas, pero una hora despues:
-- asi (sensor, fecha_hora, canal) no se duplica.
-- El valor puede ser negativo: una lectura es una senal con signo.
-- Para los tres primeros sensores de cada tanda la lectura siempre es valida.
INSERT INTO lectura_onda (
    id_lectura, id_sensor, fecha_hora, canal, valor, es_valida
)
SELECT
    820300000001::BIGINT + g,
    820300001 + (g % 30),
    TIMESTAMP '2026-08-01 00:00:00'
        + ((g / 30) % 30) * INTERVAL '1 day'
        + (g % 30) * INTERVAL '1 second'
        + (g / 900) * INTERVAL '1 hour',
    CASE g % 3 WHEN 0 THEN 'X' WHEN 1 THEN 'Y' ELSE 'Z' END,
    (((g * 37) % 401) - 200)::NUMERIC / 1000,
    (g % 30 < 3 OR g % 17 <> 0)
FROM generate_series(0, 999) AS serie(g);

-- 5. Noventa detecciones: tres sensores por cada evento ficticio.
-- Cada par corresponde a una lectura valida con la misma hora y sensor.
INSERT INTO deteccion (
    id_sensor, id_evento, hora_deteccion, aceleracion_maxima, calidad
)
SELECT
    820300001 + s,
    820300001 + e,
    TIMESTAMP '2026-08-01 00:00:00'
        + e * INTERVAL '1 day' + s * INTERVAL '1 second',
    (e + s + 1)::NUMERIC / 100,
    CASE WHEN (e + s) % 2 = 0 THEN 'alta' ELSE 'media' END
FROM generate_series(0, 29) AS eventos(e)
CROSS JOIN generate_series(0, 2) AS sensores(s);

-- 6. Veinticuatro alertas: seis eventos ficticios quedan sin alerta.
INSERT INTO alerta (
    id_alerta, id_evento, fecha_hora_emision,
    nivel, mensaje, magnitud_estimada, estado
)
SELECT
    820300001 + g,
    820300001 + g,
    TIMESTAMP '2026-08-01 00:00:00'
        + g * INTERVAL '1 day' + INTERVAL '90 seconds',
    CASE WHEN g % 2 = 0 THEN 'preventiva' ELSE 'informativa' END,
    'Alerta de prueba para el evento simulado ' || (820300001 + g)::TEXT,
    3.4::NUMERIC + (g % 15) * 0.1::NUMERIC,
    'simulada'
FROM generate_series(0, 23) AS serie(g);

-- 7. Asegurar los seis recuentos y comprobar que no se simulo sobre el IGP.
DO $$
DECLARE
    numero_incorrecto INTEGER;
BEGIN
    IF (SELECT COUNT(*) FROM estacion_sismica
        WHERE id_estacion BETWEEN 820300001 AND 820300010) <> 10
       OR (SELECT COUNT(*) FROM sensor
        WHERE id_sensor BETWEEN 820300001 AND 820300030) <> 30
       OR (SELECT COUNT(*) FROM evento_sismico
        WHERE id_evento BETWEEN 820300001 AND 820300030) <> 30
       OR (SELECT COUNT(*) FROM lectura_onda
        WHERE id_lectura BETWEEN 820300000001 AND 820300001000) <> 1000
       OR (SELECT COUNT(*) FROM deteccion
        WHERE id_evento BETWEEN 820300001 AND 820300030) <> 90
       OR (SELECT COUNT(*) FROM alerta
        WHERE id_alerta BETWEEN 820300001 AND 820300024) <> 24 THEN
        RAISE EXCEPTION 'Los recuentos de los datos simulados no coinciden. Se cancela.';
    END IF;

    SELECT COUNT(*) INTO numero_incorrecto
    FROM deteccion d
    WHERE d.id_evento BETWEEN 820300001 AND 820300030
      AND NOT EXISTS (
          SELECT 1 FROM lectura_onda l
          WHERE l.id_sensor = d.id_sensor
            AND l.fecha_hora = d.hora_deteccion
            AND l.es_valida
      );
    IF numero_incorrecto <> 0 THEN
        RAISE EXCEPTION 'Hay % detecciones sin lectura valida vinculable.', numero_incorrecto;
    END IF;

    IF EXISTS (SELECT 1 FROM deteccion
               WHERE id_evento BETWEEN 200000000 AND 299999999)
       OR EXISTS (SELECT 1 FROM alerta
               WHERE id_evento BETWEEN 200000000 AND 299999999) THEN
        RAISE EXCEPTION 'Se encontraron detecciones o alertas de eventos IGP. Verificar antes de confirmar.';
    END IF;
    RAISE NOTICE 'OK: 1184 registros simulados generados y verificados antes de COMMIT.';
END;
$$;

SELECT 'estaciones' AS tipo, 10 AS generados
UNION ALL SELECT 'sensores', 30
UNION ALL SELECT 'eventos', 30
UNION ALL SELECT 'lecturas', 1000
UNION ALL SELECT 'detecciones', 90
UNION ALL SELECT 'alertas', 24;

COMMIT;
