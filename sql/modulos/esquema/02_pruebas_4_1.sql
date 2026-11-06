-- PRUEBAS DE LA SECCION 4.1 (no dejan datos permanentes)
-- Ejecutar SOLO despues de 01_creacion_tablas.sql.
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

INSERT INTO estacion_sismica (
    id_estacion, codigo, nombre, latitud, longitud, estado
) VALUES (900000001, 'TEST-EST-01', 'Estacion de prueba', -12.1, -77.1, 'operativa');

INSERT INTO sensor (
    id_sensor, numero_serie, tipo, unidad_medida, frecuencia_muestreo,
    fecha_instalacion, estado, id_estacion
) VALUES (900000001, 'TEST-SEN-01', 'acelerometro', 'm/s2', 100,
          DATE '2026-01-01', 'operativo', 900000001);

INSERT INTO lectura_onda (
    id_lectura, id_sensor, fecha_hora, canal, valor, es_valida
) VALUES (900000001, 900000001, TIMESTAMP '2026-01-02 00:00:00', 'X', 0.25, TRUE);

INSERT INTO evento_sismico (
    id_evento, fecha_hora_origen, latitud_epicentro,
    longitud_epicentro, profundidad_km, magnitud, estado_revision
) VALUES (900000001, TIMESTAMP '2026-01-02 00:00:00',
          -12.2, -77.2, 10, -0.5, 'preliminar');

INSERT INTO deteccion (
    id_sensor, id_evento, hora_deteccion, aceleracion_maxima, calidad
) VALUES (900000001, 900000001, TIMESTAMP '2026-01-02 00:00:01', 0.25, 'alta');

INSERT INTO alerta (
    id_alerta, id_evento, fecha_hora_emision,
    nivel, mensaje, magnitud_estimada, estado
) VALUES (900000001, 900000001, TIMESTAMP '2026-01-02 00:00:05',
          'informativo', 'Prueba de alerta', -0.5, 'emitida');

-- Comprobar las seis tablas (deben devolver 1 cada una)
SELECT 'estacion_sismica' AS tabla, COUNT(*) AS registros
FROM estacion_sismica WHERE id_estacion = 900000001
UNION ALL
SELECT 'sensor', COUNT(*) FROM sensor WHERE id_sensor = 900000001
UNION ALL
SELECT 'lectura_onda', COUNT(*) FROM lectura_onda WHERE id_lectura = 900000001
UNION ALL
SELECT 'evento_sismico', COUNT(*) FROM evento_sismico WHERE id_evento = 900000001
UNION ALL
SELECT 'deteccion', COUNT(*) FROM deteccion
WHERE id_sensor = 900000001 AND id_evento = 900000001
UNION ALL
SELECT 'alerta', COUNT(*) FROM alerta WHERE id_alerta = 900000001;

-- El bloque comprueba varias restricciones sin abortar toda la prueba.
DO $$
BEGIN
    BEGIN
        INSERT INTO estacion_sismica (
            id_estacion, codigo, nombre, latitud, longitud, estado
        ) VALUES (900000002, 'TEST-EST-02', 'Error latitud', -95, -77, 'operativa');
        RAISE EXCEPTION 'FALLO: no se rechazo la latitud invalida';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: latitud fuera de rango rechazada';
    END;

    BEGIN
        INSERT INTO sensor (
            id_sensor, numero_serie, tipo, unidad_medida, frecuencia_muestreo,
            fecha_instalacion, estado, id_estacion
        ) VALUES (900000002, 'TEST-SEN-02', 'acelerometro', 'm/s2', 0,
                  DATE '2026-01-01', 'operativo', 900000001);
        RAISE EXCEPTION 'FALLO: no se rechazo frecuencia 0';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: frecuencia 0 rechazada';
    END;

    BEGIN
        INSERT INTO lectura_onda (
            id_lectura, id_sensor, fecha_hora, canal, valor, es_valida
        ) VALUES (900000002, 900000001,
                  TIMESTAMP '2026-01-02 00:00:00', 'X', 0.4, TRUE);
        RAISE EXCEPTION 'FALLO: se admitio lectura duplicada';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'OK: duplicado sensor-fecha-canal rechazado';
    END;

    BEGIN
        INSERT INTO alerta (
            id_alerta, id_evento, fecha_hora_emision,
            nivel, mensaje, estado
        ) VALUES (900000002, 900000002,
                  TIMESTAMP '2026-01-02 00:00:05', 'informativo',
                  'Evento inexistente', 'emitida');
        RAISE EXCEPTION 'FALLO: se admitio un evento inexistente';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK: referencia inexistente rechazada';
    END;

    BEGIN
        INSERT INTO deteccion (
            id_sensor, id_evento, hora_deteccion, aceleracion_maxima
        ) VALUES (900000001, 900000001,
                  TIMESTAMP '2026-01-02 00:00:02', 0.5);
        RAISE EXCEPTION 'FALLO: se admitio deteccion duplicada';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'OK: llave primaria compuesta comprobada';
    END;
END;
$$;

ROLLBACK;
-- Debe mostrarse ROLLBACK; no se conservan las filas TEST-.
