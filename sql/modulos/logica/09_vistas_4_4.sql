-- Proyecto Final - Sistema de Monitoreo Sismologico y Alerta Temprana
-- Seccion 4.4 - Vistas de consulta en PostgreSQL 18
-- No se agregan, modifican ni eliminan registros de las seis tablas.
-- Puede ejecutarse nuevamente: conserva los nombres y tipos de las columnas.
-- Ejecutar en psql conectado a bd_sismologico.

\set ON_ERROR_STOP on
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
-- Los rangos tecnicos de ID distinguen el CSV IGP de los lotes simulados.
-- Es una convencion de importacion, NO un atributo nativo del catalogo.
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

-- Las cantidades se verifican por separado en 10_verificacion_vistas_4_4.sql.
-- Este script solo define vistas; los conteos no condicionan su creacion.

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
