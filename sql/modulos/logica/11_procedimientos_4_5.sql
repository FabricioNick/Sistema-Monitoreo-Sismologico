-- Proyecto Final - Sistema de Monitoreo Sismologico y Alerta Temprana
-- Seccion 4.5 - Procedimientos almacenados (PostgreSQL 18)
-- Ejecutar con psql en bd_sismologico. No altera los registros existentes.
-- Se puede ejecutar nuevamente con CREATE OR REPLACE PROCEDURE.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

-- P1. Registrar conjuntamente una estacion y su primer sensor.
-- Evita dejar una estacion sin sensores durante el alta por esta interfaz.
CREATE OR REPLACE PROCEDURE sp_registrar_estacion_sensor(
    IN p_id_estacion INTEGER,
    IN p_codigo VARCHAR,
    IN p_nombre VARCHAR,
    IN p_latitud NUMERIC,
    IN p_longitud NUMERIC,
    IN p_estado_estacion VARCHAR,
    IN p_id_sensor INTEGER,
    IN p_numero_serie VARCHAR,
    IN p_tipo_sensor VARCHAR,
    IN p_unidad_medida VARCHAR,
    IN p_frecuencia_muestreo NUMERIC,
    IN p_fecha_instalacion DATE,
    IN p_estado_sensor VARCHAR
)
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
BEGIN
    IF NULLIF(BTRIM(p_codigo), '') IS NULL
       OR NULLIF(BTRIM(p_nombre), '') IS NULL
       OR NULLIF(BTRIM(p_numero_serie), '') IS NULL
       OR NULLIF(BTRIM(p_tipo_sensor), '') IS NULL
       OR NULLIF(BTRIM(p_unidad_medida), '') IS NULL
       OR NULLIF(BTRIM(p_estado_estacion), '') IS NULL
       OR NULLIF(BTRIM(p_estado_sensor), '') IS NULL THEN
        RAISE EXCEPTION 'Los textos obligatorios de estacion y sensor no pueden estar vacios';
    END IF;

    INSERT INTO estacion_sismica (
        id_estacion, codigo, nombre, latitud, longitud,
        fecha_instalacion, estado
    ) VALUES (
        p_id_estacion, p_codigo, p_nombre, p_latitud, p_longitud,
        p_fecha_instalacion, p_estado_estacion
    );

    INSERT INTO sensor (
        id_sensor, numero_serie, tipo, unidad_medida,
        frecuencia_muestreo, fecha_instalacion, estado, id_estacion
    ) VALUES (
        p_id_sensor, p_numero_serie, p_tipo_sensor, p_unidad_medida,
        p_frecuencia_muestreo, p_fecha_instalacion,
        p_estado_sensor, p_id_estacion
    );
END;
$$;

-- P2. Registrar un evento sismico, sin fabricar atributos opcionales.
CREATE OR REPLACE PROCEDURE sp_registrar_evento(
    IN p_id_evento INTEGER,
    IN p_fecha_hora_origen TIMESTAMP,
    IN p_latitud_epicentro NUMERIC,
    IN p_longitud_epicentro NUMERIC,
    IN p_profundidad_km NUMERIC,
    IN p_magnitud NUMERIC,
    IN p_estado_revision VARCHAR
)
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
BEGIN
    IF NULLIF(BTRIM(p_estado_revision), '') IS NULL THEN
        RAISE EXCEPTION 'El estado de revision es obligatorio';
    END IF;

    INSERT INTO evento_sismico (
        id_evento, fecha_hora_origen, latitud_epicentro,
        longitud_epicentro, profundidad_km, magnitud, estado_revision
    ) VALUES (
        p_id_evento, p_fecha_hora_origen, p_latitud_epicentro,
        p_longitud_epicentro, p_profundidad_km, p_magnitud, p_estado_revision
    );
END;
$$;

-- P3. Registrar una lectura. Solo admite nuevas lecturas validas
-- cuando el sensor se encuentra operativo en ese instante.
-- FOR SHARE evita un cambio concurrente de estado durante esta comprobacion.
CREATE OR REPLACE PROCEDURE sp_registrar_lectura(
    IN p_id_lectura BIGINT,
    IN p_id_sensor INTEGER,
    IN p_fecha_hora TIMESTAMP,
    IN p_canal VARCHAR,
    IN p_valor NUMERIC,
    IN p_es_valida BOOLEAN
)
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
DECLARE
    v_estado VARCHAR(40);
BEGIN
    SELECT LOWER(BTRIM(estado)) INTO v_estado
    FROM sensor
    WHERE id_sensor = p_id_sensor
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el sensor %', p_id_sensor;
    END IF;

    IF p_es_valida IS TRUE AND v_estado <> 'operativo' THEN
        RAISE EXCEPTION 'El sensor % no esta operativo; no puede registrar una nueva lectura valida', p_id_sensor;
    END IF;

    IF NULLIF(BTRIM(p_canal), '') IS NULL THEN
        RAISE EXCEPTION 'El canal de lectura no puede estar vacio';
    END IF;

    INSERT INTO lectura_onda (
        id_lectura, id_sensor, fecha_hora, canal, valor, es_valida
    ) VALUES (
        p_id_lectura, p_id_sensor, p_fecha_hora,
        p_canal, p_valor, p_es_valida
    );
END;
$$;

-- P4. Registrar una deteccion sustentada por una lectura valida.
-- Se exige coincidencia de sensor y hora; el modelo no posee id_lectura
-- en DETECCION, por lo que este control es procedimental y no una FK.
CREATE OR REPLACE PROCEDURE sp_registrar_deteccion(
    IN p_id_sensor INTEGER,
    IN p_id_evento INTEGER,
    IN p_hora_deteccion TIMESTAMP,
    IN p_aceleracion_maxima NUMERIC,
    IN p_calidad VARCHAR
)
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
DECLARE
    v_fecha_origen TIMESTAMP;
BEGIN
    SELECT fecha_hora_origen INTO v_fecha_origen
    FROM evento_sismico
    WHERE id_evento = p_id_evento
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el evento %', p_id_evento;
    END IF;

    IF p_hora_deteccion < v_fecha_origen THEN
        RAISE EXCEPTION 'La deteccion no puede anteceder al origen del evento %', p_id_evento;
    END IF;

    PERFORM 1
    FROM lectura_onda
    WHERE id_sensor = p_id_sensor
      AND fecha_hora = p_hora_deteccion
      AND es_valida IS TRUE
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe lectura valida para el sensor % en la hora indicada', p_id_sensor;
    END IF;

    INSERT INTO deteccion (
        id_sensor, id_evento, hora_deteccion, aceleracion_maxima, calidad
    ) VALUES (
        p_id_sensor, p_id_evento, p_hora_deteccion,
        p_aceleracion_maxima, p_calidad
    );
END;
$$;

-- P5. Emitir una alerta para un evento existente.
-- No exige una deteccion: el modelo permite alertas para un evento
-- sin imponer un numero minimo de detecciones.
CREATE OR REPLACE PROCEDURE sp_emitir_alerta(
    IN p_id_alerta INTEGER,
    IN p_id_evento INTEGER,
    IN p_fecha_hora_emision TIMESTAMP,
    IN p_nivel VARCHAR,
    IN p_mensaje TEXT,
    IN p_magnitud_estimada NUMERIC,
    IN p_estado VARCHAR
)
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
DECLARE
    v_fecha_origen TIMESTAMP;
BEGIN
    SELECT fecha_hora_origen INTO v_fecha_origen
    FROM evento_sismico
    WHERE id_evento = p_id_evento
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el evento %', p_id_evento;
    END IF;

    IF p_fecha_hora_emision < v_fecha_origen THEN
        RAISE EXCEPTION 'La alerta no puede emitirse antes del origen del evento %', p_id_evento;
    END IF;

    IF NULLIF(BTRIM(p_nivel), '') IS NULL
       OR NULLIF(BTRIM(p_mensaje), '') IS NULL
       OR NULLIF(BTRIM(p_estado), '') IS NULL THEN
        RAISE EXCEPTION 'Nivel, mensaje y estado de alerta son obligatorios';
    END IF;

    INSERT INTO alerta (
        id_alerta, id_evento, fecha_hora_emision,
        nivel, mensaje, magnitud_estimada, estado
    ) VALUES (
        p_id_alerta, p_id_evento, p_fecha_hora_emision,
        p_nivel, p_mensaje, p_magnitud_estimada, p_estado
    );
END;
$$;

-- P6. Actualizar estado y ultimo mantenimiento de un sensor.
-- NULL en la fecha elimina la ultima fecha (no implica nuevo mantenimiento).
-- El CHECK existente valida que no sea anterior a la instalacion.
CREATE OR REPLACE PROCEDURE sp_actualizar_estado_sensor(
    IN p_id_sensor INTEGER,
    IN p_estado VARCHAR,
    IN p_fecha_ultimo_mantenimiento DATE
)
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
BEGIN
    IF NULLIF(BTRIM(p_estado), '') IS NULL THEN
        RAISE EXCEPTION 'El estado del sensor es obligatorio';
    END IF;

    UPDATE sensor
    SET estado = p_estado,
        fecha_ultimo_mantenimiento = p_fecha_ultimo_mantenimiento
    WHERE id_sensor = p_id_sensor;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el sensor %', p_id_sensor;
    END IF;
END;
$$;

SELECT proname AS procedimiento
FROM pg_proc
WHERE pronamespace = 'monitoreo_sismologico'::regnamespace
  AND prokind = 'p'
  AND proname IN (
      'sp_registrar_estacion_sensor',
      'sp_registrar_evento',
      'sp_registrar_lectura',
      'sp_registrar_deteccion',
      'sp_emitir_alerta',
      'sp_actualizar_estado_sensor'
  )
ORDER BY proname;

COMMIT;
