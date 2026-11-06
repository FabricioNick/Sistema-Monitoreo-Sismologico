-- CS2041 - Hito 2 - Seccion 4.2: importacion del catalogo sismico IGP (1960-2025).
-- Ejecutar desde psql con \i, NO desde Query Tool de pgAdmin.
-- Fuente: https://www.datosabiertos.gob.pe/dataset/catalogo-sismico/resource/f9629081-0721-4101-a2c2-d0622e046f8b
-- Antes: descargar el CSV oficial como igp_catalogo.csv a la carpeta SQL.
-- El archivo IGP usa punto y coma como separador: ID;FECHA_UTC;HORA_UTC;...
-- FECHA_CORTE se conserva durante la carga temporal, pero no es parte del modelo.
-- Los timestamps sin zona horaria de EVENTO_SISMICO se interpretan como UTC.
-- Este script no borra, altera ni recrea las seis tablas del proyecto.

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

CREATE TEMP TABLE igp_catalogo_42 (
    id TEXT,
    fecha_utc TEXT,
    hora_utc TEXT,
    latitud TEXT,
    longitud TEXT,
    profundidad TEXT,
    magnitud TEXT,
    fecha_corte TEXT
) ON COMMIT DROP;

-- IMPORTANTE: el delimitador del catalogo del IGP es ';', no ','.
-- La primera fila contiene los nombres de las columnas (HEADER true).
\copy igp_catalogo_42 (id, fecha_utc, hora_utc, latitud, longitud, profundidad, magnitud, fecha_corte) FROM 'datos/igp_catalogo.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'UTF8')

-- Comprobar formatos antes de convertir tipos de datos.
DO $$
DECLARE
    total_fuente BIGINT;
    filas_incorrectas BIGINT;
BEGIN
    SELECT COUNT(*) INTO total_fuente FROM igp_catalogo_42;
    IF total_fuente = 0 THEN
        RAISE EXCEPTION 'El archivo IGP no contiene registros.';
    END IF;

    SELECT COUNT(*) INTO filas_incorrectas
    FROM igp_catalogo_42
    WHERE COALESCE(BTRIM(id), '') !~ '^[0-9]{1,8}$'
       OR COALESCE(BTRIM(fecha_utc), '') !~ '^[0-9]{8}$'
       OR COALESCE(BTRIM(hora_utc), '') !~ '^[0-9]{1,6}$'
       OR COALESCE(BTRIM(latitud), '') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
       OR COALESCE(BTRIM(longitud), '') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
       OR COALESCE(BTRIM(profundidad), '') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
       OR COALESCE(BTRIM(magnitud), '') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$';

    IF filas_incorrectas > 0 THEN
        RAISE EXCEPTION 'Hay % filas con datos obligatorios vacios o formatos invalidos. No se importo ningun evento.', filas_incorrectas;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM igp_catalogo_42
        GROUP BY BTRIM(id)::INTEGER
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'El archivo IGP contiene ID repetidos. No se importo ningun evento.';
    END IF;

    SELECT COUNT(*) INTO filas_incorrectas
    FROM igp_catalogo_42
    WHERE BTRIM(latitud)::NUMERIC NOT BETWEEN -90 AND 90
       OR BTRIM(longitud)::NUMERIC NOT BETWEEN -180 AND 180
       OR BTRIM(profundidad)::NUMERIC < 0
       OR SUBSTRING(BTRIM(fecha_utc) FROM 5 FOR 2)::INTEGER NOT BETWEEN 1 AND 12
       OR SUBSTRING(BTRIM(fecha_utc) FROM 7 FOR 2)::INTEGER NOT BETWEEN 1 AND 31
       OR SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 1 FOR 2)::INTEGER NOT BETWEEN 0 AND 23
       OR SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 3 FOR 2)::INTEGER NOT BETWEEN 0 AND 59
       OR SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 5 FOR 2)::INTEGER NOT BETWEEN 0 AND 59;

    IF filas_incorrectas > 0 THEN
        RAISE EXCEPTION 'Hay % filas con fechas, horas, ubicaciones o profundidades fuera de rango. No se importo ningun evento.', filas_incorrectas;
    END IF;

    RAISE NOTICE 'Filas del CSV oficial IGP leidas: %', total_fuente;
END;
$$;

-- Se reserva la franja 200000000-299999999 para los eventos oficiales IGP.
-- Se conserva la identidad del registro fuente mediante 200000000 + ID del CSV.
-- No se inventan tipo de magnitud, intensidad ni referencia geografica.
-- pendiente_revision es un estado INTERNO del proyecto, no informado por IGP.
INSERT INTO evento_sismico (
    id_evento,
    fecha_hora_origen,
    latitud_epicentro,
    longitud_epicentro,
    profundidad_km,
    magnitud,
    tipo_magnitud,
    intensidad_maxima,
    referencia_geografica,
    estado_revision
)
SELECT
    200000000 + BTRIM(id)::INTEGER,
    MAKE_TIMESTAMP(
        SUBSTRING(BTRIM(fecha_utc) FROM 1 FOR 4)::INTEGER,
        SUBSTRING(BTRIM(fecha_utc) FROM 5 FOR 2)::INTEGER,
        SUBSTRING(BTRIM(fecha_utc) FROM 7 FOR 2)::INTEGER,
        SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 1 FOR 2)::INTEGER,
        SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 3 FOR 2)::INTEGER,
        SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 5 FOR 2)::INTEGER
    ),
    BTRIM(latitud)::NUMERIC,
    BTRIM(longitud)::NUMERIC,
    BTRIM(profundidad)::NUMERIC,
    BTRIM(magnitud)::NUMERIC,
    NULL,
    NULL,
    NULL,
    'pendiente_revision'
FROM igp_catalogo_42
ORDER BY BTRIM(id)::INTEGER
ON CONFLICT (id_evento) DO NOTHING;

-- Verificaciones previas a confirmar la transaccion.
DO $$
DECLARE
    total_fuente BIGINT;
    total_en_bd BIGINT;
    sinteticos BIGINT;
BEGIN
    SELECT COUNT(*) INTO total_fuente FROM igp_catalogo_42;
    SELECT COUNT(*) INTO total_en_bd
    FROM evento_sismico e
    JOIN igp_catalogo_42 c ON e.id_evento = 200000000 + BTRIM(c.id)::INTEGER;
    SELECT COUNT(*) INTO sinteticos
    FROM evento_sismico
    WHERE id_evento BETWEEN 810000001 AND 810000008;

    IF total_en_bd <> total_fuente THEN
        RAISE EXCEPTION 'Se encontraron % eventos IGP en la BD, pero hay % filas en el CSV. No se confirma la transaccion.', total_en_bd, total_fuente;
    END IF;
    IF sinteticos <> 8 THEN
        RAISE EXCEPTION 'Los 8 eventos sinteticos anteriores no estan completos. No se confirma la transaccion.';
    END IF;

    RAISE NOTICE 'OK: % eventos del archivo IGP y % eventos sinteticos conservados.', total_en_bd, sinteticos;
END;
$$;

SELECT
    (SELECT COUNT(*) FROM igp_catalogo_42) AS filas_igp_en_csv,
    (SELECT COUNT(*) FROM evento_sismico WHERE id_evento BETWEEN 200000000 AND 299999999) AS eventos_igp_en_bd,
    (SELECT COUNT(*) FROM evento_sismico WHERE id_evento BETWEEN 810000001 AND 810000008) AS eventos_sinteticos;

COMMIT;
