-- Proyecto Final - Sistema de Monitoreo Sismologico y Alerta Temprana
-- Seccion 4.6 - Triggers y restricciones de integridad operativa
-- PostgreSQL 18. Ejecutar con psql en bd_sismologico.
-- No inserta, modifica ni borra registros de las seis tablas base.
\set ON_ERROR_STOP on
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
