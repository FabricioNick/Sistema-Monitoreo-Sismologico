-- CS2041 - Hito 2 - Seccion 4.2: verificar importacion del catalogo IGP.
-- Ejecutar despues de que 05_importacion_igp_4_2.sql termine en COMMIT.
SET search_path TO monitoreo_sismologico, public;

-- Los 232 registros sinteticos iniciales no deben desaparecer.
SELECT 'estacion_sismica' AS tabla, COUNT(*) AS encontrados, 5 AS minimo_inicial
FROM estacion_sismica
UNION ALL SELECT 'sensor', COUNT(*), 10 FROM sensor
UNION ALL SELECT 'lectura_onda', COUNT(*), 190 FROM lectura_onda
UNION ALL SELECT 'deteccion', COUNT(*), 14 FROM deteccion
UNION ALL SELECT 'alerta', COUNT(*), 5 FROM alerta
ORDER BY tabla;

-- Eventos sinteticos originales y nuevos eventos del IGP.
SELECT
    COUNT(*) FILTER (WHERE id_evento BETWEEN 810000001 AND 810000008) AS eventos_sinteticos,
    COUNT(*) FILTER (WHERE id_evento BETWEEN 200000000 AND 299999999) AS eventos_igp,
    COUNT(*) AS eventos_totales
FROM evento_sismico;

-- Los registros reales deben preservar las restricciones de dominio.
SELECT
    COUNT(*) FILTER (
        WHERE latitud_epicentro NOT BETWEEN -90 AND 90
           OR longitud_epicentro NOT BETWEEN -180 AND 180
           OR profundidad_km < 0
    ) AS valores_fuera_de_rango,
    COUNT(*) FILTER (
        WHERE tipo_magnitud IS NOT NULL
           OR intensidad_maxima IS NOT NULL
           OR referencia_geografica IS NOT NULL
    ) AS registros_con_datos_no_informados_rellenados
FROM evento_sismico
WHERE id_evento BETWEEN 200000000 AND 299999999;

-- Alcance temporal y magnitudes del catalogo efectivamente importado.
SELECT
    MIN(fecha_hora_origen) AS primer_evento_igp_utc,
    MAX(fecha_hora_origen) AS ultimo_evento_igp_utc,
    MIN(magnitud) AS magnitud_minima,
    MAX(magnitud) AS magnitud_maxima
FROM evento_sismico
WHERE id_evento BETWEEN 200000000 AND 299999999;

-- Cinco eventos de ejemplo para contrastar con el CSV del IGP.
SELECT id_evento, fecha_hora_origen, latitud_epicentro,
       longitud_epicentro, profundidad_km, magnitud, estado_revision
FROM evento_sismico
WHERE id_evento BETWEEN 200000000 AND 299999999
ORDER BY id_evento
LIMIT 5;
