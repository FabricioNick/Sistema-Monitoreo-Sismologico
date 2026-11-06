-- Proyecto Final - Seccion 4.5 - Pruebas transaccionales de procedimientos
-- Ejecutar con psql SOLO despues de 11_procedimientos_4_5.sql.
-- El ROLLBACK final preserva los 25 705 registros existentes.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

-- 0. Comprobar el punto de partida y reservar IDs para esta prueba.
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM estacion_sismica) <> 15
       OR (SELECT COUNT(*) FROM sensor) <> 40
       OR (SELECT COUNT(*) FROM evento_sismico) <> 24327
       OR (SELECT COUNT(*) FROM lectura_onda) <> 1190
       OR (SELECT COUNT(*) FROM deteccion) <> 104
       OR (SELECT COUNT(*) FROM alerta) <> 29 THEN
        RAISE EXCEPTION 'Los recuentos de la base no coinciden con la auditoria anterior';
    END IF;

    IF EXISTS (SELECT 1 FROM estacion_sismica WHERE id_estacion = 930450001)
       OR EXISTS (SELECT 1 FROM sensor WHERE id_sensor = 930450001)
       OR EXISTS (SELECT 1 FROM evento_sismico WHERE id_evento = 930450001)
       OR EXISTS (SELECT 1 FROM lectura_onda WHERE id_lectura BETWEEN 930450000001 AND 930450000003)
       OR EXISTS (SELECT 1 FROM deteccion WHERE id_evento = 930450001)
       OR EXISTS (SELECT 1 FROM alerta WHERE id_alerta = 930450001) THEN
        RAISE EXCEPTION 'El rango de IDs reservado para las pruebas ya esta ocupado';
    END IF;
END;
$$;

-- 1. Altas validas: estacion + sensor, evento, lectura, deteccion y alerta.
CALL sp_registrar_estacion_sensor(
    930450001, 'TEST45-EST-01', 'Estacion de prueba transaccional',
    -12.05, -77.04, 'operativa',
    930450001, 'TEST45-SEN-01', 'acelerometro', 'm/s2', 50,
    DATE '2026-07-01', 'operativo'
);

CALL sp_registrar_evento(
    930450001, TIMESTAMP '2026-08-02 00:00:00',
    -12.08, -77.05, 28, 4.2, 'simulado'
);

CALL sp_registrar_lectura(
    930450000001, 930450001, TIMESTAMP '2026-08-02 00:00:10',
    'X', 0.18, TRUE
);

CALL sp_registrar_deteccion(
    930450001, 930450001, TIMESTAMP '2026-08-02 00:00:10',
    0.18, 'alta'
);

CALL sp_emitir_alerta(
    930450001, 930450001, TIMESTAMP '2026-08-02 00:01:30',
    'preventiva', 'Alerta de prueba, no destinada a difusion', 4.2, 'simulada'
);

CALL sp_actualizar_estado_sensor(
    930450001, 'mantenimiento', DATE '2026-08-05'
);

-- 2. Verificaciones negativas. Cada bloque con EXCEPTION se revierte
-- parcialmente sin comprometer la transaccion principal.
DO $$
DECLARE
    v_rechazos INTEGER := 0;
BEGIN
    -- Nueva lectura valida con sensor en mantenimiento: rechazo esperado.
    BEGIN
        CALL sp_registrar_lectura(
            930450000002, 930450001, TIMESTAMP '2026-08-02 00:00:11',
            'X', 0.20, TRUE
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'El sensor % no esta operativo%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;
    IF v_rechazos <> 1 THEN
        RAISE EXCEPTION 'No se rechazo la lectura valida de un sensor en mantenimiento';
    END IF;

    -- Deteccion sin lectura valida en la hora: rechazo esperado.
    BEGIN
        CALL sp_registrar_deteccion(
            930450001, 930450001, TIMESTAMP '2026-08-02 00:00:12',
            0.3, 'media'
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'No existe lectura valida%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;
    IF v_rechazos <> 2 THEN
        RAISE EXCEPTION 'No se rechazo la deteccion sin lectura valida';
    END IF;

    -- Segunda deteccion del mismo par sensor-evento: rechazo por PK.
    BEGIN
        CALL sp_registrar_deteccion(
            930450001, 930450001, TIMESTAMP '2026-08-02 00:00:10',
            0.18, 'alta'
        );
    EXCEPTION WHEN unique_violation THEN
        v_rechazos := v_rechazos + 1;
    END;
    IF v_rechazos <> 3 THEN
        RAISE EXCEPTION 'No se rechazo la deteccion duplicada';
    END IF;

    -- Emision de alerta anterior al evento: rechazo esperado.
    BEGIN
        CALL sp_emitir_alerta(
            930450002, 930450001, TIMESTAMP '2026-08-01 23:59:59',
            'informativa', 'Alerta no valida', NULL, 'simulada'
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE 'La alerta no puede emitirse antes%' THEN RAISE; END IF;
        v_rechazos := v_rechazos + 1;
    END;
    IF v_rechazos <> 4 THEN
        RAISE EXCEPTION 'No se rechazo la alerta anterior al evento';
    END IF;

    -- Fecha de mantenimiento anterior a instalacion: rechazo por CHECK.
    BEGIN
        CALL sp_actualizar_estado_sensor(
            930450001, 'mantenimiento', DATE '2026-06-01'
        );
    EXCEPTION WHEN check_violation THEN
        v_rechazos := v_rechazos + 1;
    END;
    IF v_rechazos <> 5 THEN
        RAISE EXCEPTION 'No se rechazo el mantenimiento anterior a la instalacion';
    END IF;

    -- Lecturas invalidas se pueden conservar en estado de mantenimiento.
    CALL sp_registrar_lectura(
        930450000003, 930450001, TIMESTAMP '2026-08-02 00:00:13',
        'X', 0.22, FALSE
    );

    IF (SELECT COUNT(*) FROM estacion_sismica WHERE id_estacion = 930450001) <> 1
       OR (SELECT COUNT(*) FROM sensor WHERE id_sensor = 930450001 AND estado = 'mantenimiento') <> 1
       OR (SELECT COUNT(*) FROM evento_sismico WHERE id_evento = 930450001) <> 1
       OR (SELECT COUNT(*) FROM lectura_onda WHERE id_lectura BETWEEN 930450000001 AND 930450000003) <> 2
       OR (SELECT COUNT(*) FROM deteccion WHERE id_sensor = 930450001 AND id_evento = 930450001) <> 1
       OR (SELECT COUNT(*) FROM alerta WHERE id_alerta = 930450001) <> 1 THEN
        RAISE EXCEPTION 'La prueba positiva o el control de rechazos no coincide';
    END IF;

    RAISE NOTICE 'OK: 6 procedimientos operativos, 5 rechazos esperados y lecturas historicas conservadas.';
END;
$$;

SELECT 'estaciones_prueba' AS control, COUNT(*) AS resultado
FROM estacion_sismica WHERE id_estacion = 930450001
UNION ALL SELECT 'sensores_prueba', COUNT(*) FROM sensor WHERE id_sensor = 930450001
UNION ALL SELECT 'eventos_prueba', COUNT(*) FROM evento_sismico WHERE id_evento = 930450001
UNION ALL SELECT 'lecturas_prueba', COUNT(*) FROM lectura_onda WHERE id_lectura BETWEEN 930450000001 AND 930450000003
UNION ALL SELECT 'detecciones_prueba', COUNT(*) FROM deteccion WHERE id_evento = 930450001
UNION ALL SELECT 'alertas_prueba', COUNT(*) FROM alerta WHERE id_alerta = 930450001
ORDER BY control;

ROLLBACK;

-- Comprobar que la prueba no haya dejado registros persistidos.
SELECT 'estaciones_prueba' AS control, COUNT(*) AS restantes
FROM monitoreo_sismologico.estacion_sismica WHERE id_estacion = 930450001
UNION ALL SELECT 'sensores_prueba', COUNT(*) FROM monitoreo_sismologico.sensor WHERE id_sensor = 930450001
UNION ALL SELECT 'eventos_prueba', COUNT(*) FROM monitoreo_sismologico.evento_sismico WHERE id_evento = 930450001
UNION ALL SELECT 'lecturas_prueba', COUNT(*) FROM monitoreo_sismologico.lectura_onda WHERE id_lectura BETWEEN 930450000001 AND 930450000003
UNION ALL SELECT 'detecciones_prueba', COUNT(*) FROM monitoreo_sismologico.deteccion WHERE id_evento = 930450001
UNION ALL SELECT 'alertas_prueba', COUNT(*) FROM monitoreo_sismologico.alerta WHERE id_alerta = 930450001
ORDER BY control;
