-- 03. LOGICA Y CONSULTAS
\set ON_ERROR_STOP on
\pset pager off

\echo '=== VALIDACION INICIAL ==='
SELECT current_database() AS base_actual;
SET search_path TO monitoreo_sismologico, public;

DO $$
DECLARE
    tabla TEXT;
    cantidad BIGINT;
    total BIGINT := 0;
BEGIN
    IF current_database() IN ('postgres', 'template0', 'template1') THEN
        RAISE EXCEPTION 'Seleccione una base de proyecto.';
    END IF;

    FOR tabla, cantidad IN
        SELECT nombre, esperado
        FROM (VALUES
            ('estacion_sismica', 15::BIGINT),
            ('sensor', 40),
            ('lectura_onda', 1190),
            ('evento_sismico', 24327),
            ('deteccion', 104),
            ('alerta', 29)
        ) AS t(nombre, esperado)
    LOOP
        IF to_regclass(format('monitoreo_sismologico.%I', tabla)) IS NULL THEN
            RAISE EXCEPTION 'Falta la tabla %.', tabla;
        END IF;
        EXECUTE format('SELECT COUNT(*) FROM monitoreo_sismologico.%I', tabla) INTO total;
        IF total <> cantidad THEN
            RAISE EXCEPTION 'La tabla % contiene % registros; se esperaban %.', tabla, total, cantidad;
        END IF;
    END LOOP;
    RAISE NOTICE 'OK: seis tablas y 25705 registros verificados.';
END;
$$;


\echo '=== VISTAS ==='
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

-- 1. Actividad y validez de lecturas para cada sensor.
-- LEFT JOIN conserva sensores que aun no tienen lecturas.
CREATE OR REPLACE VIEW vw_sensores_actividad AS
SELECT
    s.id_sensor,
    s.numero_serie,
    s.tipo,
    s.estado AS estado_sensor,
    s.frecuencia_muestreo,
    e.id_estacion,
    e.codigo AS codigo_estacion,
    e.nombre AS nombre_estacion,
    COALESCE(l.total_lecturas, 0) AS total_lecturas,
    COALESCE(l.lecturas_validas, 0) AS lecturas_validas,
    COALESCE(l.lecturas_invalidas, 0) AS lecturas_invalidas,
    l.primera_lectura,
    l.ultima_lectura
FROM sensor s
JOIN estacion_sismica e ON e.id_estacion = s.id_estacion
LEFT JOIN (
    SELECT
        id_sensor,
        COUNT(*) AS total_lecturas,
        COUNT(*) FILTER (WHERE es_valida IS TRUE) AS lecturas_validas,
        COUNT(*) FILTER (WHERE es_valida IS FALSE) AS lecturas_invalidas,
        MIN(fecha_hora) AS primera_lectura,
        MAX(fecha_hora) AS ultima_lectura
    FROM lectura_onda
    GROUP BY id_sensor
) l ON l.id_sensor = s.id_sensor;

-- 2. Cobertura y lecturas por estacion.
-- Se agregan sensores ya resumidos para no multiplicar lecturas por JOIN.
CREATE OR REPLACE VIEW vw_estaciones_resumen AS
SELECT
    e.id_estacion,
    e.codigo,
    e.nombre,
    e.departamento,
    e.estado AS estado_estacion,
    COUNT(sa.id_sensor) AS total_sensores,
    COUNT(sa.id_sensor) FILTER (
        WHERE LOWER(sa.estado_sensor) IN ('operativo', 'operativa')
    ) AS sensores_operativos,
    COALESCE(SUM(sa.total_lecturas), 0) AS total_lecturas,
    COALESCE(SUM(sa.lecturas_validas), 0) AS lecturas_validas,
    COALESCE(SUM(sa.lecturas_invalidas), 0) AS lecturas_invalidas
FROM estacion_sismica e
LEFT JOIN vw_sensores_actividad sa ON sa.id_estacion = e.id_estacion
GROUP BY e.id_estacion, e.codigo, e.nombre, e.departamento, e.estado;

-- 3. Seguimiento de eventos con recuentos independientes.
CREATE OR REPLACE VIEW vw_eventos_seguimiento AS
SELECT
    ev.id_evento,
    CASE
        WHEN ev.id_evento BETWEEN 200000000 AND 299999999 THEN 'igp'
        WHEN ev.id_evento BETWEEN 810000001 AND 810000008
          OR ev.id_evento BETWEEN 820300001 AND 820300030 THEN 'simulado'
        ELSE 'sin_clasificar'
    END AS procedencia,
    ev.fecha_hora_origen,
    ev.latitud_epicentro,
    ev.longitud_epicentro,
    ev.profundidad_km,
    ev.magnitud,
    ev.estado_revision,
    COALESCE(d.total_detecciones, 0) AS total_detecciones,
    COALESCE(a.total_alertas, 0) AS total_alertas,
    COALESCE(d.total_detecciones, 0) > 0 AS tiene_deteccion,
    COALESCE(a.total_alertas, 0) > 0 AS tiene_alerta
FROM evento_sismico ev
LEFT JOIN (
    SELECT id_evento, COUNT(*) AS total_detecciones
    FROM deteccion
    GROUP BY id_evento
) d ON d.id_evento = ev.id_evento
LEFT JOIN (
    SELECT id_evento, COUNT(*) AS total_alertas
    FROM alerta
    GROUP BY id_evento
) a ON a.id_evento = ev.id_evento;

-- 4. Detalle de alertas y tiempo transcurrido desde el origen.
-- La resta de TIMESTAMP produce un INTERVAL (no segundos numericos).
CREATE OR REPLACE VIEW vw_alertas_detalle AS
SELECT
    a.id_alerta,
    a.id_evento,
    ev.procedencia,
    ev.fecha_hora_origen,
    a.fecha_hora_emision,
    a.fecha_hora_emision - ev.fecha_hora_origen AS tiempo_desde_origen,
    ev.magnitud AS magnitud_evento,
    a.magnitud_estimada,
    a.nivel,
    a.estado AS estado_alerta,
    a.mensaje,
    ev.total_detecciones AS sensores_detectores
FROM alerta a
JOIN vw_eventos_seguimiento ev ON ev.id_evento = a.id_evento;

-- 5. Resumen mensual exclusivo del catalogo oficial importado del IGP.
-- TIMESTAMP se interpreta como UTC porque esa fue la zona de la fuente.
CREATE OR REPLACE VIEW vw_igp_resumen_mensual AS
SELECT
    DATE_TRUNC('month', fecha_hora_origen)::DATE AS mes_utc,
    COUNT(*) AS total_eventos,
    COUNT(*) FILTER (WHERE magnitud >= 6) AS eventos_magnitud_6_mas,
    MIN(magnitud) AS magnitud_minima,
    MAX(magnitud) AS magnitud_maxima,
    AVG(magnitud) AS magnitud_promedio,
    AVG(profundidad_km) AS profundidad_promedio_km
FROM evento_sismico
WHERE id_evento BETWEEN 200000000 AND 299999999
GROUP BY DATE_TRUNC('month', fecha_hora_origen)::DATE;


SELECT table_name AS vista
FROM information_schema.views
WHERE table_schema = 'monitoreo_sismologico'
  AND table_name IN (
      'vw_sensores_actividad',
      'vw_estaciones_resumen',
      'vw_eventos_seguimiento',
      'vw_alertas_detalle',
      'vw_igp_resumen_mensual'
  )
ORDER BY table_name;

COMMIT;


\echo '=== VERIFICACION DE VISTAS ==='
SET search_path TO monitoreo_sismologico, public;

-- A. Existencia y cardinalidad de cuatro vistas de detalle.
WITH recuentos AS (
    SELECT 'vw_alertas_detalle'::TEXT AS vista, 29::BIGINT AS esperado,
           (SELECT COUNT(*) FROM vw_alertas_detalle) AS encontrado
    UNION ALL
    SELECT 'vw_estaciones_resumen', 15,
           (SELECT COUNT(*) FROM vw_estaciones_resumen)
    UNION ALL
    SELECT 'vw_eventos_seguimiento', 24327,
           (SELECT COUNT(*) FROM vw_eventos_seguimiento)
    UNION ALL
    SELECT 'vw_sensores_actividad', 40,
           (SELECT COUNT(*) FROM vw_sensores_actividad)
)
SELECT vista, esperado, encontrado,
       CASE WHEN encontrado = esperado THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM recuentos
ORDER BY vista;

-- B. Sumas derivadas: no se deben multiplicar filas al combinar relaciones.
SELECT
    (SELECT SUM(total_sensores) FROM vw_estaciones_resumen) AS sensores_por_estacion,
    (SELECT SUM(total_lecturas) FROM vw_estaciones_resumen) AS lecturas_por_estacion,
    (SELECT SUM(lecturas_validas) FROM vw_sensores_actividad) AS lecturas_validas,
    (SELECT SUM(lecturas_invalidas) FROM vw_sensores_actividad) AS lecturas_invalidas,
    (SELECT SUM(total_detecciones) FROM vw_eventos_seguimiento) AS detecciones_por_evento,
    (SELECT SUM(total_alertas) FROM vw_eventos_seguimiento) AS alertas_por_evento;

-- Esperado: 40, 1190, 1113, 77, 104, 29.

-- C. Procedencia tecnica del evento y detecciones/alertas asociadas.
SELECT procedencia, COUNT(*) AS eventos,
       SUM(total_detecciones) AS detecciones,
       SUM(total_alertas) AS alertas
FROM vw_eventos_seguimiento
GROUP BY procedencia
ORDER BY procedencia;

-- Esperado: 'igp' 24289 / 0 / 0; 'simulado' 38 / 104 / 29.

-- D. Resumen mensual, sin asumir una cifra fija de meses con eventos.
SELECT COUNT(*) AS meses_con_eventos,
       SUM(total_eventos) AS eventos_igp,
       MIN(mes_utc) AS primer_mes_utc,
       MAX(mes_utc) AS ultimo_mes_utc
FROM vw_igp_resumen_mensual;

-- Esperado: 24289 eventos; primer mes 1960-01-01, ultimo 2025-12-01.

-- E. Cinco alertas como ejemplo. Las vistas no garantizan orden por si solas.
SELECT id_alerta, id_evento, procedencia, nivel,
       fecha_hora_emision, tiempo_desde_origen, sensores_detectores
FROM vw_alertas_detalle
ORDER BY fecha_hora_emision, id_alerta
LIMIT 5;

-- F. Verificacion estricta; si algo difiere se obtiene ERROR (sin borrar datos).
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM information_schema.views
        WHERE table_schema = 'monitoreo_sismologico'
          AND table_name IN (
              'vw_sensores_actividad', 'vw_estaciones_resumen',
              'vw_eventos_seguimiento', 'vw_alertas_detalle',
              'vw_igp_resumen_mensual'
          )) <> 5
       OR ((SELECT COUNT(*) FROM estacion_sismica)
           + (SELECT COUNT(*) FROM sensor)
           + (SELECT COUNT(*) FROM lectura_onda)
           + (SELECT COUNT(*) FROM evento_sismico)
           + (SELECT COUNT(*) FROM deteccion)
           + (SELECT COUNT(*) FROM alerta)) <> 25705
       OR (SELECT COUNT(*) FROM vw_sensores_actividad) <> 40
       OR (SELECT COUNT(*) FROM vw_estaciones_resumen) <> 15
       OR (SELECT COUNT(*) FROM vw_eventos_seguimiento) <> 24327
       OR (SELECT COUNT(*) FROM vw_alertas_detalle) <> 29
       OR (SELECT COALESCE(SUM(total_eventos), 0) FROM vw_igp_resumen_mensual) <> 24289
       OR (SELECT COALESCE(SUM(total_sensores), 0) FROM vw_estaciones_resumen) <> 40
       OR (SELECT COALESCE(SUM(total_lecturas), 0) FROM vw_estaciones_resumen) <> 1190
       OR (SELECT COALESCE(SUM(lecturas_validas), 0) FROM vw_sensores_actividad) <> 1113
       OR (SELECT COALESCE(SUM(lecturas_invalidas), 0) FROM vw_sensores_actividad) <> 77
       OR (SELECT COALESCE(SUM(total_detecciones), 0) FROM vw_eventos_seguimiento) <> 104
       OR (SELECT COALESCE(SUM(total_alertas), 0) FROM vw_eventos_seguimiento) <> 29
       OR (SELECT COUNT(*) FROM vw_eventos_seguimiento WHERE procedencia = 'igp') <> 24289
       OR (SELECT COUNT(*) FROM vw_eventos_seguimiento WHERE procedencia = 'simulado') <> 38
       OR EXISTS (SELECT 1 FROM vw_eventos_seguimiento WHERE procedencia = 'sin_clasificar')
       OR EXISTS (SELECT 1 FROM vw_eventos_seguimiento
                  WHERE procedencia = 'igp' AND (total_detecciones <> 0 OR total_alertas <> 0))
       OR (SELECT MIN(mes_utc) FROM vw_igp_resumen_mensual) <> DATE '1960-01-01'
       OR (SELECT MAX(mes_utc) FROM vw_igp_resumen_mensual) <> DATE '2025-12-01' THEN
        RAISE EXCEPTION 'REVISAR: alguna vista o total derivado no coincide con los datos auditados.';
    END IF;
    RAISE NOTICE 'OK: 5 vistas, 25705 registros base y controles derivados consistentes.';
END;
$$;


\echo '=== PROCEDIMIENTOS ==='
-- Se puede ejecutar nuevamente con CREATE OR REPLACE PROCEDURE.
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


\echo '=== PRUEBAS DE PROCEDIMIENTOS ==='
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

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


\echo '=== TRIGGERS ==='
-- PostgreSQL 18. Ejecutar con psql en bd_sismologico.
-- No inserta, modifica ni borra registros de las seis tablas base.
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

-- T1. Una lectura nueva o reasignada solo puede marcarse valida
-- si su sensor se encuentra operativo. No se invalidan lecturas
-- historicas cuando el estado del sensor cambia posteriormente.
CREATE OR REPLACE FUNCTION fn_trg_lectura_operativa()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
DECLARE
    v_estado TEXT;
BEGIN
    IF NEW.es_valida IS TRUE THEN
        SELECT LOWER(BTRIM(estado)) INTO v_estado
        FROM sensor
        WHERE id_sensor = NEW.id_sensor
        FOR SHARE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'TRG: el sensor % no existe', NEW.id_sensor;
        END IF;

        IF v_estado IS DISTINCT FROM 'operativo' THEN
            RAISE EXCEPTION 'TRG: el sensor % no esta operativo para nuevas lecturas validas', NEW.id_sensor;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_lectura_operativa
BEFORE INSERT OR UPDATE OF id_sensor, fecha_hora, es_valida
ON lectura_onda
FOR EACH ROW
EXECUTE FUNCTION fn_trg_lectura_operativa();

-- T2. Al actualizar o eliminar una lectura que sustentaba una
-- deteccion, debe quedar otra lectura valida con igual sensor y hora.
-- El identificador de lectura no forma parte de DETECCION.
CREATE OR REPLACE FUNCTION fn_trg_proteger_sustento()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
BEGIN
    IF OLD.es_valida IS NOT TRUE THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.es_valida IS TRUE
           AND NEW.id_sensor = OLD.id_sensor
           AND NEW.fecha_hora = OLD.fecha_hora THEN
            RETURN NEW;
        END IF;
    END IF;

    -- Bloquea la deteccion mientras se comprueba su sustento.
    PERFORM 1
    FROM deteccion
    WHERE id_sensor = OLD.id_sensor
      AND hora_deteccion = OLD.fecha_hora
    FOR SHARE;

    IF FOUND AND NOT EXISTS (
        SELECT 1
        FROM lectura_onda
        WHERE id_sensor = OLD.id_sensor
          AND fecha_hora = OLD.fecha_hora
          AND es_valida IS TRUE
          AND id_lectura <> OLD.id_lectura
    ) THEN
        RAISE EXCEPTION 'TRG: la lectura % es el ultimo sustento valido de una deteccion', OLD.id_lectura;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_proteger_sustento_lectura
BEFORE UPDATE OF id_sensor, fecha_hora, es_valida OR DELETE
ON lectura_onda
FOR EACH ROW
EXECUTE FUNCTION fn_trg_proteger_sustento();

-- T3. Las detecciones directas deben tener hora >= origen y
-- una lectura valida del mismo sensor y hora exacta.
CREATE OR REPLACE FUNCTION fn_trg_deteccion_valida()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
DECLARE
    v_origen TIMESTAMP;
BEGIN
    SELECT fecha_hora_origen INTO v_origen
    FROM evento_sismico
    WHERE id_evento = NEW.id_evento
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TRG: el evento % no existe', NEW.id_evento;
    END IF;
    IF NEW.hora_deteccion < v_origen THEN
        RAISE EXCEPTION 'TRG: deteccion anterior al origen del evento %', NEW.id_evento;
    END IF;

    PERFORM 1
    FROM lectura_onda
    WHERE id_sensor = NEW.id_sensor
      AND fecha_hora = NEW.hora_deteccion
      AND es_valida IS TRUE
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TRG: deteccion sin lectura valida del sensor % en la hora indicada', NEW.id_sensor;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_deteccion_valida
BEFORE INSERT OR UPDATE OF id_sensor, id_evento, hora_deteccion
ON deteccion
FOR EACH ROW
EXECUTE FUNCTION fn_trg_deteccion_valida();

-- T4. No se emiten alertas anteriores al origen de su evento.
CREATE OR REPLACE FUNCTION fn_trg_alerta_temporal()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
DECLARE
    v_origen TIMESTAMP;
BEGIN
    SELECT fecha_hora_origen INTO v_origen
    FROM evento_sismico
    WHERE id_evento = NEW.id_evento
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TRG: el evento % no existe', NEW.id_evento;
    END IF;
    IF NEW.fecha_hora_emision < v_origen THEN
        RAISE EXCEPTION 'TRG: alerta anterior al origen del evento %', NEW.id_evento;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_alerta_temporal
BEFORE INSERT OR UPDATE OF id_evento, fecha_hora_emision
ON alerta
FOR EACH ROW
EXECUTE FUNCTION fn_trg_alerta_temporal();

-- T5. Una revision del origen no puede dejar detecciones ni
-- alertas ya asociadas con una hora anterior al nuevo origen.
CREATE OR REPLACE FUNCTION fn_trg_revisar_origen_evento()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
BEGIN
    IF NEW.fecha_hora_origen IS DISTINCT FROM OLD.fecha_hora_origen THEN
        IF EXISTS (
            SELECT 1 FROM deteccion
            WHERE id_evento = OLD.id_evento
              AND hora_deteccion < NEW.fecha_hora_origen
        ) OR EXISTS (
            SELECT 1 FROM alerta
            WHERE id_evento = OLD.id_evento
              AND fecha_hora_emision < NEW.fecha_hora_origen
        ) THEN
            RAISE EXCEPTION 'TRG: el nuevo origen del evento % invalida detecciones o alertas existentes', OLD.id_evento;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_revisar_origen_evento
BEFORE UPDATE OF fecha_hora_origen
ON evento_sismico
FOR EACH ROW
EXECUTE FUNCTION fn_trg_revisar_origen_evento();

-- T6. Serializa traslados y bajas de sensores de una estacion
-- mediante un bloqueo sobre la fila de su estacion de origen.
CREATE OR REPLACE FUNCTION fn_trg_bloquear_estacion_origen()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM 1 FROM estacion_sismica
        WHERE id_estacion = OLD.id_estacion
        FOR UPDATE;
        RETURN OLD;
    END IF;
    IF OLD.id_estacion IS DISTINCT FROM NEW.id_estacion THEN
        PERFORM 1 FROM estacion_sismica
        WHERE id_estacion = OLD.id_estacion
        FOR UPDATE;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_bloquear_estacion_origen
BEFORE UPDATE OF id_estacion OR DELETE
ON sensor
FOR EACH ROW
EXECUTE FUNCTION fn_trg_bloquear_estacion_origen();

-- T7. Participacion minima: cada estacion existente posee
-- al menos un sensor al verificar restricciones diferidas.
-- Asi se admite INSERT estacion seguido de INSERT sensor
-- en la misma transaccion, pero se rechaza dejarla vacia.
CREATE OR REPLACE FUNCTION fn_trg_estacion_con_sensor()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = monitoreo_sismologico, pg_temp
AS $$
DECLARE
    v_id_estacion INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'estacion_sismica' THEN
        v_id_estacion := NEW.id_estacion;
    ELSE
        v_id_estacion := OLD.id_estacion;
        IF TG_OP = 'UPDATE' THEN
            IF OLD.id_estacion IS NOT DISTINCT FROM NEW.id_estacion THEN
                RETURN NULL;
            END IF;
        END IF;
    END IF;

    -- La estacion puede haber sido eliminada en esta misma transaccion.
    IF EXISTS (
        SELECT 1 FROM estacion_sismica WHERE id_estacion = v_id_estacion
    ) AND NOT EXISTS (
        SELECT 1 FROM sensor WHERE id_estacion = v_id_estacion
    ) THEN
        RAISE EXCEPTION 'TRG: la estacion % debe conservar al menos un sensor', v_id_estacion;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS ct_estacion_sensor_alta ON estacion_sismica;
CREATE CONSTRAINT TRIGGER ct_estacion_sensor_alta
AFTER INSERT ON estacion_sismica
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION fn_trg_estacion_con_sensor();

DROP TRIGGER IF EXISTS ct_estacion_sensor_baja ON sensor;
CREATE CONSTRAINT TRIGGER ct_estacion_sensor_baja
AFTER DELETE ON sensor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION fn_trg_estacion_con_sensor();

DROP TRIGGER IF EXISTS ct_estacion_sensor_traslado ON sensor;
CREATE CONSTRAINT TRIGGER ct_estacion_sensor_traslado
AFTER UPDATE OF id_estacion ON sensor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION fn_trg_estacion_con_sensor();

-- Verificacion estructural previa: datos ya existentes.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM estacion_sismica e
        WHERE NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion = e.id_estacion)
    ) OR EXISTS (
        SELECT 1 FROM deteccion d
        JOIN evento_sismico e USING (id_evento)
        WHERE d.hora_deteccion < e.fecha_hora_origen
           OR NOT EXISTS (
               SELECT 1 FROM lectura_onda l
               WHERE l.id_sensor = d.id_sensor
                 AND l.fecha_hora = d.hora_deteccion
                 AND l.es_valida IS TRUE
           )
    ) OR EXISTS (
        SELECT 1 FROM alerta a
        JOIN evento_sismico e USING (id_evento)
        WHERE a.fecha_hora_emision < e.fecha_hora_origen
    ) THEN
        RAISE EXCEPTION 'Existen datos previos incompatibles con las reglas de los triggers';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND NOT t.tgisinternal
          AND t.tgname IN (
              'trg_lectura_operativa', 'trg_proteger_sustento_lectura',
              'trg_deteccion_valida', 'trg_alerta_temporal',
              'trg_revisar_origen_evento', 'trg_bloquear_estacion_origen',
              'ct_estacion_sensor_alta', 'ct_estacion_sensor_baja',
              'ct_estacion_sensor_traslado'
          )
    ) <> 9 THEN
        RAISE EXCEPTION 'No se encontraron los 9 triggers previstos';
    END IF;

    RAISE NOTICE 'OK: 9 triggers instalados; datos previos compatibles.';
END;
$$;

SELECT c.relname AS tabla, t.tgname AS trigger,
       CASE WHEN t.tgdeferrable THEN 'DIFERIDO' ELSE 'INMEDIATO' END AS control
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'monitoreo_sismologico'
  AND NOT t.tgisinternal
  AND t.tgname IN (
      'trg_lectura_operativa', 'trg_proteger_sustento_lectura',
      'trg_deteccion_valida', 'trg_alerta_temporal',
      'trg_revisar_origen_evento', 'trg_bloquear_estacion_origen',
      'ct_estacion_sensor_alta', 'ct_estacion_sensor_baja',
      'ct_estacion_sensor_traslado'
  )
ORDER BY tabla, trigger;

COMMIT;


\echo '=== PRUEBAS DE TRIGGERS ==='
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

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


\echo '=== CONSULTAS C1-C5 ==='
-- 5.1 - Cinco consultas SQL intermedias para la experimentacion

SET search_path TO monitoreo_sismologico, public;

\echo
\echo CONSULTA 1. Sismos IGP de magnitud >= 6, por anio (2010-2025)
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
ORDER BY anio_utc;

\echo
\echo CONSULTA 2. Sismos IGP cercanos por ventana rectangular a estaciones
-- Ventana de +/- 1.5 grados latitud/longitud; NO es una distancia geodesica.
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
LIMIT 10;

\echo
\echo CONSULTA 3. Calidad de lecturas por estacion (agosto-noviembre 2026)
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
ORDER BY porcentaje_invalidas DESC, total_lecturas DESC, e.id_estacion;

\echo
\echo CONSULTA 4. Tiempo a primera deteccion y primera alerta en eventos simulados
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
LIMIT 15;

\echo
\echo CONSULTA 5. Sensores con lecturas pero sin detecciones en agosto de 2026
-- Sin detecciones no equivale por si solo a sensor defectuoso.
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
LIMIT 15;


\echo '=== VERIFICACION DE CONSULTAS ==='
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

\echo '=== COMPROBACION FINAL ==='
DO $$
DECLARE
    v_vistas INTEGER;
    v_procedimientos INTEGER;
    v_triggers INTEGER;
    v_registros BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_vistas
    FROM pg_views
    WHERE schemaname = 'monitoreo_sismologico'
      AND viewname IN (
        'vw_sensores_actividad', 'vw_estaciones_resumen',
        'vw_eventos_seguimiento', 'vw_alertas_detalle', 'vw_igp_resumen_mensual'
      );

    SELECT COUNT(*) INTO v_procedimientos
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'monitoreo_sismologico' AND p.prokind = 'p'
      AND p.proname IN (
        'sp_registrar_estacion_sensor', 'sp_registrar_evento',
        'sp_registrar_lectura', 'sp_registrar_deteccion',
        'sp_emitir_alerta', 'sp_actualizar_estado_sensor'
      );

    SELECT COUNT(*) INTO v_triggers
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'monitoreo_sismologico'
      AND NOT t.tgisinternal
      AND t.tgname IN (
        'trg_lectura_operativa', 'trg_proteger_sustento_lectura',
        'trg_deteccion_valida', 'trg_alerta_temporal',
        'trg_revisar_origen_evento', 'trg_bloquear_estacion_origen',
        'ct_estacion_sensor_alta', 'ct_estacion_sensor_baja',
        'ct_estacion_sensor_traslado'
      );

    SELECT SUM(registros) INTO v_registros
    FROM (
        SELECT COUNT(*) AS registros FROM monitoreo_sismologico.estacion_sismica
        UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.sensor
        UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda
        UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico
        UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.deteccion
        UNION ALL SELECT COUNT(*) FROM monitoreo_sismologico.alerta
    ) AS conteos;

    IF ROW(v_vistas, v_procedimientos, v_triggers, v_registros)
       IS DISTINCT FROM ROW(5, 6, 9, 25705::BIGINT) THEN
        RAISE EXCEPTION 'Control final incorrecto: vistas %, procedimientos %, triggers %, registros %',
            v_vistas, v_procedimientos, v_triggers, v_registros;
    END IF;
    RAISE NOTICE 'OK: 5 vistas, 6 procedimientos, 9 triggers y 25705 registros.';
END;
$$;
\echo '=== ETAPA 3 FINALIZADA ==='
