'use strict';
// Consultas copiadas literalmente de 15_consultas_5_1.sql (sin comandos de psql).
const QUERY_SQL = Object.freeze({
  "C1": "SELECT\n    EXTRACT(YEAR FROM ev.fecha_hora_origen)::INTEGER AS anio_utc,\n    COUNT(*) AS cantidad_eventos,\n    ROUND(AVG(ev.magnitud), 2) AS magnitud_promedio,\n    MAX(ev.magnitud) AS magnitud_maxima,\n    ROUND(AVG(ev.profundidad_km), 2) AS profundidad_promedio_km\nFROM evento_sismico ev\nWHERE ev.id_evento BETWEEN 200000000 AND 299999999\n  AND ev.fecha_hora_origen >= TIMESTAMP '2010-01-01 00:00:00'\n  AND ev.fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'\n  AND ev.magnitud >= 6\nGROUP BY EXTRACT(YEAR FROM ev.fecha_hora_origen)::INTEGER\nHAVING COUNT(*) >= 1\nORDER BY anio_utc;",
  "C2": "SELECT\n    e.id_estacion,\n    e.codigo AS codigo_estacion,\n    e.nombre AS nombre_estacion,\n    COUNT(*) AS eventos_en_ventana,\n    ROUND(AVG(ev.magnitud), 2) AS magnitud_promedio,\n    MAX(ev.magnitud) AS magnitud_maxima\nFROM estacion_sismica e\nJOIN evento_sismico ev\n  ON ev.latitud_epicentro BETWEEN e.latitud - 1.5 AND e.latitud + 1.5\n AND ev.longitud_epicentro BETWEEN e.longitud - 1.5 AND e.longitud + 1.5\nWHERE ev.id_evento BETWEEN 200000000 AND 299999999\n  AND ev.fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00'\n  AND ev.fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'\n  AND ev.magnitud >= 5\nGROUP BY e.id_estacion, e.codigo, e.nombre\nHAVING COUNT(*) >= 1\nORDER BY eventos_en_ventana DESC, e.id_estacion\nLIMIT 10;",
  "C3": "SELECT\n    e.id_estacion,\n    e.codigo AS codigo_estacion,\n    COUNT(DISTINCT s.id_sensor) AS sensores_con_lecturas,\n    COUNT(*) AS total_lecturas,\n    COUNT(*) FILTER (WHERE l.es_valida) AS lecturas_validas,\n    COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,\n    ROUND(100.0 * COUNT(*) FILTER (WHERE NOT l.es_valida)\n          / NULLIF(COUNT(*), 0), 2) AS porcentaje_invalidas\nFROM estacion_sismica e\nJOIN sensor s ON s.id_estacion = e.id_estacion\nJOIN lectura_onda l ON l.id_sensor = s.id_sensor\nWHERE l.fecha_hora >= TIMESTAMP '2026-08-01 00:00:00'\n  AND l.fecha_hora < TIMESTAMP '2026-12-01 00:00:00'\nGROUP BY e.id_estacion, e.codigo\nHAVING COUNT(*) >= 10\nORDER BY porcentaje_invalidas DESC, total_lecturas DESC, e.id_estacion;",
  "C4": "WITH detecciones_resumen AS (\n    SELECT id_evento, COUNT(*) AS total_detecciones,\n           MIN(hora_deteccion) AS primera_deteccion\n    FROM deteccion\n    GROUP BY id_evento\n), alertas_resumen AS (\n    SELECT id_evento, COUNT(*) AS total_alertas,\n           MIN(fecha_hora_emision) AS primera_alerta\n    FROM alerta\n    GROUP BY id_evento\n)\nSELECT\n    ev.id_evento,\n    ev.fecha_hora_origen,\n    ev.magnitud,\n    COALESCE(d.total_detecciones, 0) AS total_detecciones,\n    COALESCE(a.total_alertas, 0) AS total_alertas,\n    ROUND(EXTRACT(EPOCH FROM (d.primera_deteccion - ev.fecha_hora_origen))::NUMERIC, 2)\n        AS segundos_primera_deteccion,\n    ROUND(EXTRACT(EPOCH FROM (a.primera_alerta - ev.fecha_hora_origen))::NUMERIC, 2)\n        AS segundos_primera_alerta\nFROM evento_sismico ev\nLEFT JOIN detecciones_resumen d ON d.id_evento = ev.id_evento\nLEFT JOIN alertas_resumen a ON a.id_evento = ev.id_evento\nWHERE (ev.id_evento BETWEEN 810000001 AND 810000008\n    OR ev.id_evento BETWEEN 820300001 AND 820300030)\n  AND (COALESCE(d.total_detecciones, 0) > 0\n    OR COALESCE(a.total_alertas, 0) > 0)\nORDER BY ev.fecha_hora_origen DESC, ev.id_evento\nLIMIT 15;",
  "C5": "SELECT\n    s.id_sensor,\n    s.numero_serie,\n    e.codigo AS codigo_estacion,\n    s.estado AS estado_sensor,\n    COUNT(*) AS lecturas_periodo,\n    COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,\n    MAX(l.fecha_hora) AS ultima_lectura\nFROM sensor s\nJOIN estacion_sismica e ON e.id_estacion = s.id_estacion\nJOIN lectura_onda l ON l.id_sensor = s.id_sensor\nWHERE l.fecha_hora >= TIMESTAMP '2026-08-01 00:00:00'\n  AND l.fecha_hora < TIMESTAMP '2026-09-01 00:00:00'\n  AND NOT EXISTS (\n      SELECT 1\n      FROM deteccion d\n      WHERE d.id_sensor = s.id_sensor\n        AND d.hora_deteccion >= TIMESTAMP '2026-08-01 00:00:00'\n        AND d.hora_deteccion < TIMESTAMP '2026-09-01 00:00:00'\n  )\nGROUP BY s.id_sensor, s.numero_serie, e.codigo, s.estado\nHAVING COUNT(*) >= 20\nORDER BY lecturas_invalidas DESC, lecturas_periodo DESC, s.id_sensor\nLIMIT 15;"
});
const QUERIES = Object.freeze({
  "C1": {
    "id": "C1",
    "name": "Actividad sísmica anual",
    "description": "Sismos del IGP con magnitud ≥ 6 entre 2010 y 2025."
  },
  "C2": {
    "id": "C2",
    "name": "Ventanas geográficas",
    "description": "Eventos del IGP en ventanas de ±1,5° alrededor de estaciones."
  },
  "C3": {
    "id": "C3",
    "name": "Calidad de lecturas",
    "description": "Lecturas válidas e inválidas agrupadas por estación."
  },
  "C4": {
    "id": "C4",
    "name": "Primera detección y alerta",
    "description": "Tiempos de respuesta sobre los eventos simulados del experimento."
  },
  "C5": {
    "id": "C5",
    "name": "Sensores sin detecciones",
    "description": "Sensores con lecturas de agosto de 2026 y sin detecciones en ese período."
  }
});
module.exports = { QUERY_SQL, QUERIES };
