-- Proyecto Final - Seccion 5.2: generador determinista para UNA base experimental.
-- Debe ejecutarse dentro de una de las cuatro bd_sismologico_exp_*.
-- Ejecutar una sola vez por base. No se conecta ni altera bd_sismologico.
-- El catalogo IGP se importa desde igp_catalogo.csv (CSV UTF-8, separador ;).
-- Antes de ejecutar, guardar en esta carpeta los archivos 01 y 13.
\set ON_ERROR_STOP on

-- El identificador de base determina el volumen y la distribucion exacta.
-- El primer paso comprueba el destino, antes de crear objetos.
DO $$
BEGIN
    IF current_database() NOT IN (
        'bd_sismologico_exp_1000', 'bd_sismologico_exp_10000',
        'bd_sismologico_exp_100000', 'bd_sismologico_exp_1000000'
    ) THEN
        RAISE EXCEPTION 'Base incorrecta: %. No se modifica la base principal.', current_database();
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'monitoreo_sismologico'
          AND table_name = 'evento_sismico'
    ) THEN
        RAISE EXCEPTION 'La base % ya tiene tablas. No volver a generar sin auditar.', current_database();
    END IF;
END;
$$;

-- Reutiliza exactamente el DDL de las seis relaciones y sus restricciones.
\ir ../esquema/01_creacion_tablas.sql

BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

-- Suma de las seis columnas de cada fila = volumen solicitado.
-- igp: eventos verdaderos del CSV; el resto de eventos son ficticios.
CREATE TEMP TABLE exp_parametros_52 ON COMMIT DROP AS
SELECT *
FROM (VALUES
    ('bd_sismologico_exp_1000',       1000,   5,  15,    100,     50,    750,    90,   40),
    ('bd_sismologico_exp_10000',     10000,  10,  30,   2000,    800,   7550,   300,  110),
    ('bd_sismologico_exp_100000',   100000,  25,  75,  24000,  12000,  74700,   900,  300),
    ('bd_sismologico_exp_1000000', 1000000, 100, 300, 120000,  24289, 875000,  3500, 1100)
) AS v(nombre, total, n_est, n_sen, n_evt, n_igp, n_lec, n_det, n_ale)
WHERE nombre = current_database();

DO $$
DECLARE p RECORD;
BEGIN
    SELECT * INTO p FROM exp_parametros_52;
    IF NOT FOUND OR p.n_est+p.n_sen+p.n_evt+p.n_lec+p.n_det+p.n_ale <> p.total
       OR p.n_evt-p.n_igp < 40
       OR p.n_det > (p.n_sen/2) * 30
       OR ((p.n_det-1)/(p.n_sen/2))*p.n_sen
            + ((p.n_det-1)%(p.n_sen/2)) >= p.n_lec THEN
        RAISE EXCEPTION 'Configuracion de escala inconsistente para %', current_database();
    END IF;
    RAISE NOTICE 'Iniciando % registros en %', p.total, current_database();
END;
$$;

-- Funciones deterministas que permiten reproducir claves y tiempos de prueba.
CREATE FUNCTION exp_id_estacion(p_g INTEGER) RETURNS INTEGER
LANGUAGE SQL IMMUTABLE AS $$
    SELECT CASE WHEN p_g < 5 THEN 810000001+p_g
                WHEN p_g < 15 THEN 820300001+p_g-5
                ELSE 830000001+p_g-15 END;
$$;
CREATE FUNCTION exp_id_sensor(p_g INTEGER) RETURNS INTEGER
LANGUAGE SQL IMMUTABLE AS $$
    SELECT CASE WHEN p_g < 10 THEN 810000001+p_g
                WHEN p_g < 40 THEN 820300001+p_g-10
                ELSE 830000001+p_g-40 END;
$$;
CREATE FUNCTION exp_id_evento(p_g INTEGER) RETURNS INTEGER
LANGUAGE SQL IMMUTABLE AS $$
    SELECT CASE WHEN p_g < 8 THEN 810000001+p_g
                WHEN p_g < 38 THEN 820300001+p_g-8
                ELSE 830000001+p_g-38 END;
$$;
CREATE FUNCTION exp_origen_evento(p_g INTEGER) RETURNS TIMESTAMP
LANGUAGE SQL IMMUTABLE AS $$
    SELECT TIMESTAMP '2026-08-01 00:00:00'
         + (p_g % 30) * INTERVAL '1 day'
         + (p_g / 30) * INTERVAL '1 second';
$$;
CREATE FUNCTION exp_hora_lectura(p_g INTEGER, p_sensores INTEGER) RETURNS TIMESTAMP
LANGUAGE SQL IMMUTABLE AS $$
    SELECT TIMESTAMP '2026-08-01 00:00:00'
         + ((p_g / p_sensores) % 30) * INTERVAL '1 day'
         + (p_g % p_sensores) * INTERVAL '1 second'
         + (p_g / (p_sensores * 30)) * INTERVAL '10 minutes';
$$;

-- La fuente oficial se lee sin modificar sus ocho campos originales.
CREATE TEMP TABLE exp_igp_fuente_52 (
    id TEXT, fecha_utc TEXT, hora_utc TEXT,
    latitud TEXT, longitud TEXT, profundidad TEXT,
    magnitud TEXT, fecha_corte TEXT
) ON COMMIT DROP;

\copy exp_igp_fuente_52 (id, fecha_utc, hora_utc, latitud, longitud, profundidad, magnitud, fecha_corte) FROM 'datos/igp_catalogo.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'UTF8')

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM exp_igp_fuente_52) <> 24289 THEN
        RAISE EXCEPTION 'El CSV oficial debe contener 24289 filas; se cancela esta version del experimento.';
    END IF;
END;
$$;

-- La muestra IGP es un subconjunto REAL, no eventos sinteticos rotulados IGP.
-- Se priorizan sismos de magnitud >= 6 de 2010-2025 y casos posteriores a 2000
-- para que las consultas 1 y 2 tengan casos incluso en la base de 1000 filas.
WITH fuente AS (
    SELECT
        BTRIM(id)::INTEGER AS id_fuente,
        MAKE_TIMESTAMP(
            SUBSTRING(BTRIM(fecha_utc) FROM 1 FOR 4)::INTEGER,
            SUBSTRING(BTRIM(fecha_utc) FROM 5 FOR 2)::INTEGER,
            SUBSTRING(BTRIM(fecha_utc) FROM 7 FOR 2)::INTEGER,
            SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 1 FOR 2)::INTEGER,
            SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 3 FOR 2)::INTEGER,
            SUBSTRING(LPAD(BTRIM(hora_utc), 6, '0') FROM 5 FOR 2)::INTEGER
        ) AS fecha,
        BTRIM(latitud)::NUMERIC AS lat,
        BTRIM(longitud)::NUMERIC AS lon,
        BTRIM(profundidad)::NUMERIC AS prof,
        BTRIM(magnitud)::NUMERIC AS mag
    FROM exp_igp_fuente_52
), muestra AS (
    SELECT fuente.*,
       ROW_NUMBER() OVER (
         ORDER BY CASE
             WHEN fecha >= '2010-01-01' AND fecha < '2026-01-01' AND mag >= 6 THEN 0
             WHEN fecha >= '2000-01-01' AND fecha < '2026-01-01' AND mag >= 5 THEN 1
             ELSE 2
         END, md5(id_fuente::TEXT)
       ) AS orden
    FROM fuente
)
INSERT INTO evento_sismico (
    id_evento, fecha_hora_origen, latitud_epicentro,
    longitud_epicentro, profundidad_km, magnitud,
    tipo_magnitud, intensidad_maxima, referencia_geografica, estado_revision
)
SELECT 200000000 + i.id_fuente, i.fecha, i.lat, i.lon,
       i.prof, i.mag, NULL, NULL, NULL, 'pendiente_revision'
FROM muestra i CROSS JOIN exp_parametros_52 p
WHERE i.orden <= p.n_igp;

-- Estaciones y sensores exclusivamente de SIMULACION.
-- Estacion 0 coincide con la ubicacion de un evento real muestreado
-- para poder ejercer la consulta geografica (no es una estacion IGP).
INSERT INTO estacion_sismica (
    id_estacion, codigo, nombre, latitud, longitud, altitud,
    departamento, provincia, distrito, fecha_instalacion, estado
)
SELECT
    exp_id_estacion(g),
    'EXP52-EST-' || LPAD((g+1)::TEXT, 4, '0'),
    'Estacion experimental simulada ' || (g+1),
    CASE WHEN g=0 THEN (
        SELECT latitud_epicentro FROM evento_sismico
        WHERE id_evento BETWEEN 200000000 AND 299999999
        ORDER BY magnitud DESC, id_evento LIMIT 1
    ) ELSE (-5.5 - g*0.11)::NUMERIC END,
    CASE WHEN g=0 THEN (
        SELECT longitud_epicentro FROM evento_sismico
        WHERE id_evento BETWEEN 200000000 AND 299999999
        ORDER BY magnitud DESC, id_evento LIMIT 1
    ) ELSE (-78.4 + g*0.03)::NUMERIC END,
    100 + g*15, NULL, NULL, NULL, DATE '2024-01-01', 'operativa'
FROM exp_parametros_52 p CROSS JOIN LATERAL generate_series(0,p.n_est-1) AS gs(g);

INSERT INTO sensor (
    id_sensor, numero_serie, tipo, modelo, unidad_medida,
    frecuencia_muestreo, fecha_instalacion, fecha_ultimo_mantenimiento,
    estado, id_estacion
)
SELECT exp_id_sensor(g),
       'EXP52-SEN-' || LPAD((g+1)::TEXT, 4, '0'),
       'acelerometro', 'SIM-52', 'm/s2',
       CASE WHEN g%2=0 THEN 50 ELSE 100 END,
       DATE '2025-01-01', NULL, 'operativo', exp_id_estacion(g/3)
FROM exp_parametros_52 p CROSS JOIN LATERAL generate_series(0,p.n_sen-1) AS gs(g);

-- Eventos simulados: fuera del intervalo de identificadores oficiales.
INSERT INTO evento_sismico (
    id_evento, fecha_hora_origen, latitud_epicentro, longitud_epicentro,
    profundidad_km, magnitud, tipo_magnitud,
    intensidad_maxima, referencia_geografica, estado_revision
)
SELECT exp_id_evento(g), exp_origen_evento(g),
       (-8-(g%120)*0.07)::NUMERIC, (-77+(g%100)*0.04)::NUMERIC,
       5+(g%500), (3.4+(g%40)*0.1)::NUMERIC,
       NULL, NULL, NULL, 'simulado'
FROM exp_parametros_52 p
CROSS JOIN LATERAL generate_series(0,p.n_evt-p.n_igp-1) AS gs(g);

-- Lecturas: signo permitido, fechas reproducibles, unicidad por sensor/fecha/canal.
-- Las lecturas de la mitad activa de sensores son siempre validas.
-- La otra mitad conserva algunas lecturas invalidas para el analisis de calidad.
INSERT INTO lectura_onda (
    id_lectura, id_sensor, fecha_hora, canal, valor, es_valida
)
SELECT 900000000001::BIGINT + g,
       exp_id_sensor(g % p.n_sen), exp_hora_lectura(g, p.n_sen),
       CASE g%3 WHEN 0 THEN 'X' WHEN 1 THEN 'Y' ELSE 'Z' END,
       (((g*37::BIGINT)%401)-200)::NUMERIC / 1000,
       (g % p.n_sen < p.n_sen/2 OR g % 17 <> 0)
FROM exp_parametros_52 p
CROSS JOIN LATERAL generate_series(0,p.n_lec-1) AS gs(g);

-- Detecciones: horas exactamente iguales a lecturas validas existentes.
-- Se usa solo la primera mitad de sensores: la otra queda sin detecciones.
-- Cada deteccion apunta a una lectura valida real (indice q).
-- n_det < (30 * piso(n_sen/2)): las parejas no se repiten.
INSERT INTO deteccion (
    id_sensor, id_evento, hora_deteccion, aceleracion_maxima, calidad
)
SELECT exp_id_sensor(g % (p.n_sen/2)),
       exp_id_evento((g / (p.n_sen/2)) % 30),
       exp_hora_lectura(
           (g/(p.n_sen/2))*p.n_sen + (g%(p.n_sen/2)), p.n_sen),
       ((g%80)+1)::NUMERIC / 100, 'alta'
FROM exp_parametros_52 p
CROSS JOIN LATERAL generate_series(0,p.n_det-1) AS gs(g);

-- Alertas de prueba; no se atribuyen a sismos oficiales.
INSERT INTO alerta (
    id_alerta, id_evento, fecha_hora_emision,
    nivel, mensaje, magnitud_estimada, estado
)
SELECT CASE WHEN g<5 THEN 810000001+g
            WHEN g<29 THEN 820300001+g-5
            ELSE 830000001+g-29 END,
       exp_id_evento(g), exp_origen_evento(g) + INTERVAL '90 seconds',
       CASE WHEN g%2=0 THEN 'preventiva' ELSE 'informativa' END,
       'Alerta experimental para evento simulado ' || exp_id_evento(g),
       3.4+(g%40)*0.1, 'simulada'
FROM exp_parametros_52 p
CROSS JOIN LATERAL generate_series(0,p.n_ale-1) AS gs(g);

-- Ninguna fila invalida puede confirmarse si falla alguno de estos controles.
DO $$
DECLARE p RECORD; v_total BIGINT;
BEGIN
    SELECT * INTO p FROM exp_parametros_52;
    SELECT (SELECT COUNT(*) FROM estacion_sismica)
         + (SELECT COUNT(*) FROM sensor)
         + (SELECT COUNT(*) FROM evento_sismico)
         + (SELECT COUNT(*) FROM lectura_onda)
         + (SELECT COUNT(*) FROM deteccion)
         + (SELECT COUNT(*) FROM alerta)
    INTO v_total;
    IF v_total <> p.total OR
       (SELECT COUNT(*) FROM evento_sismico WHERE id_evento BETWEEN 200000000 AND 299999999) <> p.n_igp OR
       (SELECT COUNT(*) FROM evento_sismico WHERE estado_revision='simulado') <> p.n_evt-p.n_igp OR
       EXISTS (SELECT 1 FROM deteccion WHERE id_evento BETWEEN 200000000 AND 299999999) OR
       EXISTS (SELECT 1 FROM alerta WHERE id_evento BETWEEN 200000000 AND 299999999) OR
       EXISTS (
          SELECT 1 FROM deteccion d
          WHERE NOT EXISTS (
              SELECT 1 FROM lectura_onda l
              WHERE l.id_sensor=d.id_sensor AND l.fecha_hora=d.hora_deteccion AND l.es_valida
          )
       ) OR
       EXISTS (
          SELECT 1 FROM estacion_sismica e
          WHERE NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion=e.id_estacion)
       ) THEN
       RAISE EXCEPTION 'Fallaron controles de integridad para la escala %', p.total;
    END IF;
    RAISE NOTICE 'OK: % registros generados; IGP=% y simulados=%; integridad compatible.',
       p.total, p.n_igp, p.n_evt-p.n_igp;
END;
$$;

SELECT 'estacion_sismica' AS tabla, COUNT(*) AS filas FROM estacion_sismica
UNION ALL SELECT 'sensor',COUNT(*) FROM sensor
UNION ALL SELECT 'evento_sismico',COUNT(*) FROM evento_sismico
UNION ALL SELECT 'lectura_onda',COUNT(*) FROM lectura_onda
UNION ALL SELECT 'deteccion',COUNT(*) FROM deteccion
UNION ALL SELECT 'alerta',COUNT(*) FROM alerta
ORDER BY tabla;
COMMIT;

-- Se instalan los mismos triggers de integridad solo DESPUES de la carga masiva;
-- asi el costo de generacion no contamina el benchmark de consultas SELECT.
\ir ../logica/13_triggers_4_6.sql

-- Estadisticas para el optimizador; no es una medicion de rendimiento.
ANALYZE monitoreo_sismologico.estacion_sismica;
ANALYZE monitoreo_sismologico.sensor;
ANALYZE monitoreo_sismologico.evento_sismico;
ANALYZE monitoreo_sismologico.lectura_onda;
ANALYZE monitoreo_sismologico.deteccion;
ANALYZE monitoreo_sismologico.alerta;

SELECT current_database() AS base_experimental,
       (SELECT COUNT(*) FROM monitoreo_sismologico.estacion_sismica)
     + (SELECT COUNT(*) FROM monitoreo_sismologico.sensor)
     + (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico)
     + (SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda)
     + (SELECT COUNT(*) FROM monitoreo_sismologico.deteccion)
     + (SELECT COUNT(*) FROM monitoreo_sismologico.alerta) AS registros_totales;
