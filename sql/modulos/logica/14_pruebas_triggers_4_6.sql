-- Proyecto Final - Seccion 4.6 - Pruebas de triggers
-- Ejecutar con psql DESPUES de 13_triggers_4_6.sql.
-- Todo el escenario de prueba termina con ROLLBACK.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

-- 0. Validar el estado previo y los IDs reservados.
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM estacion_sismica) <> 15
       OR (SELECT COUNT(*) FROM sensor) <> 40
       OR (SELECT COUNT(*) FROM evento_sismico) <> 24327
       OR (SELECT COUNT(*) FROM lectura_onda) <> 1190
       OR (SELECT COUNT(*) FROM deteccion) <> 104
       OR (SELECT COUNT(*) FROM alerta) <> 29 THEN
        RAISE EXCEPTION 'Los recuentos iniciales no coinciden con los 25705 registros verificados';
    END IF;

    IF EXISTS (SELECT 1 FROM estacion_sismica WHERE id_estacion BETWEEN 930460001 AND 930460099)
       OR EXISTS (SELECT 1 FROM sensor WHERE id_sensor BETWEEN 930460001 AND 930460099)
       OR EXISTS (SELECT 1 FROM evento_sismico WHERE id_evento = 930460001)
       OR EXISTS (SELECT 1 FROM lectura_onda WHERE id_lectura BETWEEN 930460000001 AND 930460000099)
       OR EXISTS (SELECT 1 FROM deteccion WHERE id_evento = 930460001)
       OR EXISTS (SELECT 1 FROM alerta WHERE id_alerta = 930460001) THEN
        RAISE EXCEPTION 'Rango de IDs reservado para los triggers ya ocupado';
    END IF;
END;
$$;

-- 1. Escenario positivo: inserciones SQL directas (sin CALL).
INSERT INTO estacion_sismica (
    id_estacion, codigo, nombre, latitud, longitud, fecha_instalacion, estado
) VALUES
    (930460001, 'TEST46-EST-A', 'Estacion temporal A', -12.05, -77.04,
     DATE '2026-07-01', 'operativa'),
    (930460002, 'TEST46-EST-B', 'Estacion temporal B', -12.06, -77.05,
     DATE '2026-07-01', 'operativa');

INSERT INTO sensor (
    id_sensor, numero_serie, tipo, unidad_medida, frecuencia_muestreo,
    fecha_instalacion, estado, id_estacion
) VALUES
    (930460001, 'TEST46-SEN-A', 'acelerometro', 'm/s2', 50,
     DATE '2026-07-01', 'operativo', 930460001),
    (930460002, 'TEST46-SEN-B', 'acelerometro', 'm/s2', 50,
     DATE '2026-07-01', 'operativo', 930460002);

INSERT INTO evento_sismico (
    id_evento, fecha_hora_origen, latitud_epicentro,
    longitud_epicentro, profundidad_km, magnitud, estado_revision
) VALUES (
    930460001, TIMESTAMP '2026-08-02 00:00:00',
    -12.08, -77.05, 28, 4.2, 'simulado'
);

INSERT INTO lectura_onda (
    id_lectura, id_sensor, fecha_hora, canal, valor, es_valida
) VALUES (
    930460000001, 930460001, TIMESTAMP '2026-08-02 00:00:10', 'X', 0.18, TRUE
);

INSERT INTO deteccion (
    id_sensor, id_evento, hora_deteccion, aceleracion_maxima, calidad
) VALUES (
    930460001, 930460001, TIMESTAMP '2026-08-02 00:00:10', 0.18, 'alta'
);

INSERT INTO alerta (
    id_alerta, id_evento, fecha_hora_emision, nivel, mensaje,
    magnitud_estimada, estado
) VALUES (
    930460001, 930460001, TIMESTAMP '2026-08-02 00:01:30',
    'preventiva', 'Alerta de prueba no destinada a difusion', 4.2, 'simulada'
);

-- Las lecturas validas existentes no cambian si el sensor pasa a mantenimiento.
UPDATE sensor SET estado = 'mantenimiento' WHERE id_sensor = 930460001;
INSERT INTO lectura_onda (
    id_lectura, id_sensor, fecha_hora, canal, valor, es_valida
) VALUES (
    930460000002, 930460001, TIMESTAMP '2026-08-02 00:00:11', 'X', 0.20, FALSE
);

-- 2. Nueve rechazos esperados: se capturan en subtransacciones.
DO $$
DECLARE
    v_rechazos INTEGER := 0;
BEGIN
    -- Caso 1: el sensor en mantenimiento no genera otra lectura valida.
    BEGIN
        INSERT INTO lectura_onda (id_lectura, id_sensor, fecha_hora, canal, valor, es_valida)
        VALUES (930460000003, 930460001, TIMESTAMP '2026-08-02 00:00:12', 'X', 0.25, TRUE);
        RAISE EXCEPTION 'No se rechazo la lectura valida del sensor en mantenimiento';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: el sensor % no esta operativo%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    -- Caso 2: deteccion sin lectura valida a esa hora.
    BEGIN
        INSERT INTO deteccion (id_sensor, id_evento, hora_deteccion, aceleracion_maxima, calidad)
        VALUES (930460002, 930460001, TIMESTAMP '2026-08-02 00:00:13', 0.19, 'media');
        RAISE EXCEPTION 'No se rechazo la deteccion sin lectura';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: deteccion sin lectura valida%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    -- Caso 3: alerta anterior al origen del evento.
    BEGIN
        INSERT INTO alerta (id_alerta, id_evento, fecha_hora_emision, nivel, mensaje, estado)
        VALUES (930460002, 930460001, TIMESTAMP '2026-08-01 23:59:59',
                'informativa', 'Alerta de prueba incorrecta', 'simulada');
        RAISE EXCEPTION 'No se rechazo la alerta anterior al origen';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: alerta anterior al origen%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    -- Caso 4: no se puede invalidar el unico sustento de una deteccion.
    BEGIN
        UPDATE lectura_onda SET es_valida = FALSE WHERE id_lectura = 930460000001;
        RAISE EXCEPTION 'No se rechazo la invalidacion de lectura sustentadora';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: la lectura % es el ultimo sustento%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    -- Caso 5: tampoco se puede borrar ese unico sustento.
    BEGIN
        DELETE FROM lectura_onda WHERE id_lectura = 930460000001;
        RAISE EXCEPTION 'No se rechazo el borrado de lectura sustentadora';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: la lectura % es el ultimo sustento%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    -- Caso 6: una correccion de origen no debe invalidar detecciones previas.
    BEGIN
        UPDATE evento_sismico
        SET fecha_hora_origen = TIMESTAMP '2026-08-02 00:00:11'
        WHERE id_evento = 930460001;
        RAISE EXCEPTION 'No se rechazo el cambio inconsistente de origen';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: el nuevo origen%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    -- Caso 7: una nueva estacion no puede quedar sin sensores al validar.
    BEGIN
        INSERT INTO estacion_sismica (
            id_estacion, codigo, nombre, latitud, longitud, estado
        ) VALUES (930460099, 'TEST46-SOLA', 'Estacion sin sensor', -12, -77, 'operativa');
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'No se rechazo la estacion sin sensor';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: la estacion % debe conservar%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    -- Caso 8: no se puede eliminar el unico sensor de una estacion.
    BEGIN
        DELETE FROM sensor WHERE id_sensor = 930460002;
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'No se rechazo la baja del ultimo sensor';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: la estacion % debe conservar%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    -- Caso 9: tampoco puede trasladarse el unico sensor de una estacion.
    BEGIN
        UPDATE sensor SET id_estacion = 930460001 WHERE id_sensor = 930460002;
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'No se rechazo el traslado del ultimo sensor';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'TRG: la estacion % debe conservar%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;

    IF v_rechazos <> 9 THEN
        RAISE EXCEPTION 'Se esperaban 9 rechazos, pero se comprobaron %', v_rechazos;
    END IF;

    IF (SELECT COUNT(*) FROM estacion_sismica WHERE id_estacion BETWEEN 930460001 AND 930460099) <> 2
       OR (SELECT COUNT(*) FROM sensor WHERE id_sensor BETWEEN 930460001 AND 930460099) <> 2
       OR (SELECT COUNT(*) FROM evento_sismico WHERE id_evento = 930460001) <> 1
       OR (SELECT COUNT(*) FROM lectura_onda WHERE id_lectura BETWEEN 930460000001 AND 930460000099) <> 2
       OR (SELECT COUNT(*) FROM lectura_onda WHERE id_lectura = 930460000001 AND es_valida) <> 1
       OR (SELECT COUNT(*) FROM deteccion WHERE id_evento = 930460001) <> 1
       OR (SELECT COUNT(*) FROM alerta WHERE id_alerta = 930460001) <> 1 THEN
        RAISE EXCEPTION 'Resultados positivos o reversiones parciales inconsistentes';
    END IF;

    RAISE NOTICE 'OK: 9 triggers, 9 rechazos esperados y lecturas historicas preservadas.';
END;
$$;

SELECT 'estaciones_prueba' AS control, COUNT(*) AS resultado
FROM estacion_sismica WHERE id_estacion BETWEEN 930460001 AND 930460099
UNION ALL SELECT 'sensores_prueba', COUNT(*) FROM sensor WHERE id_sensor BETWEEN 930460001 AND 930460099
UNION ALL SELECT 'eventos_prueba', COUNT(*) FROM evento_sismico WHERE id_evento = 930460001
UNION ALL SELECT 'lecturas_prueba', COUNT(*) FROM lectura_onda WHERE id_lectura BETWEEN 930460000001 AND 930460000099
UNION ALL SELECT 'detecciones_prueba', COUNT(*) FROM deteccion WHERE id_evento = 930460001
UNION ALL SELECT 'alertas_prueba', COUNT(*) FROM alerta WHERE id_alerta = 930460001
ORDER BY control;

ROLLBACK;

-- Confirmar que todos los IDs reservados siguen libres tras las pruebas.
SELECT 'estaciones_prueba' AS control, COUNT(*) AS restantes
FROM monitoreo_sismologico.estacion_sismica WHERE id_estacion BETWEEN 930460001 AND 930460099
UNION ALL SELECT 'sensores_prueba', COUNT(*) FROM monitoreo_sismologico.sensor WHERE id_sensor BETWEEN 930460001 AND 930460099
UNION ALL SELECT 'eventos_prueba', COUNT(*) FROM monitoreo_sismologico.evento_sismico WHERE id_evento = 930460001
UNION ALL SELECT 'lecturas_prueba', COUNT(*) FROM monitoreo_sismologico.lectura_onda WHERE id_lectura BETWEEN 930460000001 AND 930460000099
UNION ALL SELECT 'detecciones_prueba', COUNT(*) FROM monitoreo_sismologico.deteccion WHERE id_evento = 930460001
UNION ALL SELECT 'alertas_prueba', COUNT(*) FROM monitoreo_sismologico.alerta WHERE id_alerta = 930460001
ORDER BY control;

SELECT SUM(registros) AS registros_totales, 25705 AS esperado
FROM (
    SELECT COUNT(*) AS registros FROM monitoreo_sismologico.estacion_sismica
    UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.sensor
    UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico
    UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda
    UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.deteccion
    UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.alerta
) r;
