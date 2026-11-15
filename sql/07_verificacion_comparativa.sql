-- 07. VERIFICACION COMPARATIVA DE CONSULTAS C1-C5
-- PostgreSQL 18 | Proyecto final CS2041
-- Referencia de ejecucion MANUAL en pgAdmin 4.
-- No ejecuta bucles, SQL dinamico ni comparaciones automatizadas.
-- Las cinco consultas son las mismas que las evaluadas en SQL 05 y SQL 06.
-- La evidencia cuantitativa oficial permanece en resultados/mediciones.
--
-- Uso: conectarse a bd_sismologico_prueba_exp_1000000 y trabajar UNA
-- consulta a la vez. Ejecutar cada paso seleccionado con F5; seleccionar
-- solamente el SELECT del escenario y usar Explain Analyze (Shift+F7)
-- para visualizar el arbol grafico, el tiempo y los buffers.
-- No ejecutar el archivo completo de una sola vez.
--
-- IMPORTANTE: cada bloque C1-C5 abre una transaccion y termina con ROLLBACK.
-- Esto revierte los indices candidatos creados para la demostracion.
-- Tras cada ROLLBACK, confirmar la ausencia del indice si se desea.

-- VERIFICACION PREVIA (solo lectura)
SELECT current_database() AS base_seleccionada;

SELECT
    (SELECT COUNT(*) FROM monitoreo_sismologico.estacion_sismica) AS estaciones,
    (SELECT COUNT(*) FROM monitoreo_sismologico.sensor) AS sensores,
    (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico) AS eventos,
    (SELECT COUNT(*) FROM monitoreo_sismologico.lectura_onda) AS lecturas,
    (SELECT COUNT(*) FROM monitoreo_sismologico.deteccion) AS detecciones,
    (SELECT COUNT(*) FROM monitoreo_sismologico.alerta) AS alertas;
-- Esperado: 100, 300, 120000, 875000, 3500, 1100 (1 000 000 en total).

SELECT COUNT(*) AS indices_secundarios_existentes
FROM pg_index i
JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid
WHERE n.nspname = 'monitoreo_sismologico' AND c.oid IS NULL;
-- Esperado: 0. Si no es 0, revisar la base antes de continuar.


-- ============================================================
-- C1. ACTIVIDAD SISMICA ANUAL
-- ============================================================
-- Paso 1. Iniciar la transaccion y mostrar el resultado SIN indice candidato.
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

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

-- Para el arbol: seleccionar solamente el SELECT anterior y usar Shift+F7.
-- Paso 2. Crear el/los indice(s) candidato(s) de C1 y actualizar estadisticas.
CREATE INDEX idx_ev_igp_m6_fecha
ON monitoreo_sismologico.evento_sismico (fecha_hora_origen)
INCLUDE (magnitud, profundidad_km)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND magnitud >= 6;
ANALYZE monitoreo_sismologico.evento_sismico;

-- Paso 3. Volver a seleccionar y ejecutar el MISMO SELECT del paso 1.
-- Presionar F5 para las filas y Shift+F7 para el plan CON indices candidatos.
-- Comparar filas, operadores del plan, Execution Time y buffers.
-- Que exista un indice candidato no implica que el planificador lo use.
-- Paso 4. Revertir los indices candidatos antes de continuar.
ROLLBACK;


-- ============================================================
-- C2. VENTANAS GEOGRAFICAS
-- ============================================================
-- Paso 1. Iniciar la transaccion y mostrar el resultado SIN indice candidato.
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

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

-- Para el arbol: seleccionar solamente el SELECT anterior y usar Shift+F7.
-- Paso 2. Crear el/los indice(s) candidato(s) de C2 y actualizar estadisticas.
CREATE INDEX idx_ev_igp_geo_c2
ON monitoreo_sismologico.evento_sismico
    (latitud_epicentro, longitud_epicentro)
INCLUDE (magnitud)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND fecha_hora_origen >= TIMESTAMP '2000-01-01 00:00:00'
  AND fecha_hora_origen < TIMESTAMP '2026-01-01 00:00:00'
  AND magnitud >= 5;
ANALYZE monitoreo_sismologico.evento_sismico;

-- Paso 3. Volver a seleccionar y ejecutar el MISMO SELECT del paso 1.
-- Presionar F5 para las filas y Shift+F7 para el plan CON indices candidatos.
-- Comparar filas, operadores del plan, Execution Time y buffers.
-- Que exista un indice candidato no implica que el planificador lo use.
-- Paso 4. Revertir los indices candidatos antes de continuar.
ROLLBACK;


-- ============================================================
-- C3. CALIDAD DE LECTURAS
-- ============================================================
-- Paso 1. Iniciar la transaccion y mostrar el resultado SIN indice candidato.
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

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

-- Para el arbol: seleccionar solamente el SELECT anterior y usar Shift+F7.
-- Paso 2. Crear el/los indice(s) candidato(s) de C3 y actualizar estadisticas.
CREATE INDEX idx_lectura_sensor_fecha_c3
ON monitoreo_sismologico.lectura_onda (id_sensor, fecha_hora)
INCLUDE (es_valida);
ANALYZE monitoreo_sismologico.lectura_onda;

-- Paso 3. Volver a seleccionar y ejecutar el MISMO SELECT del paso 1.
-- Presionar F5 para las filas y Shift+F7 para el plan CON indices candidatos.
-- Comparar filas, operadores del plan, Execution Time y buffers.
-- Que exista un indice candidato no implica que el planificador lo use.
-- Paso 4. Revertir los indices candidatos antes de continuar.
ROLLBACK;


-- ============================================================
-- C4. SEGUIMIENTO DE DETECCIONES Y ALERTAS POR FECHA
-- ============================================================
-- Paso 1. Iniciar la transaccion y mostrar el resultado SIN indice candidato.
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

SELECT ev.id_evento, ev.fecha_hora_origen, ev.magnitud,
       d.total_detecciones, a.total_alertas,
       ROUND(EXTRACT(EPOCH FROM
           (d.primera_deteccion - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_deteccion,
       ROUND(EXTRACT(EPOCH FROM
           (a.primera_alerta - ev.fecha_hora_origen))::NUMERIC, 2)
           AS segundos_primera_alerta
FROM evento_sismico ev
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_detecciones,
           MIN(hora_deteccion) AS primera_deteccion
    FROM deteccion d
    WHERE d.id_evento = ev.id_evento
) d ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*)::INTEGER AS total_alertas,
           MIN(fecha_hora_emision) AS primera_alerta
    FROM alerta a
    WHERE a.id_evento = ev.id_evento
) a ON TRUE
WHERE ev.estado_revision = 'simulado'
  AND ev.fecha_hora_origen >= TIMESTAMP '2026-08-05 00:00:00'
  AND ev.fecha_hora_origen < TIMESTAMP '2026-08-06 00:00:00'
  AND (d.total_detecciones > 0 OR a.total_alertas > 0)
ORDER BY ev.fecha_hora_origen DESC, ev.id_evento
LIMIT 15;

-- Para el arbol: seleccionar solamente el SELECT anterior y usar Shift+F7.
-- Paso 2. Crear el/los indice(s) candidato(s) de C4 y actualizar estadisticas.
CREATE INDEX idx_evento_fecha_c4
    ON monitoreo_sismologico.evento_sismico (fecha_hora_origen) INCLUDE (magnitud, estado_revision);
CREATE INDEX idx_deteccion_evento_hora_c4
    ON monitoreo_sismologico.deteccion (id_evento, hora_deteccion);
CREATE INDEX idx_alerta_evento_hora_c4
    ON monitoreo_sismologico.alerta (id_evento, fecha_hora_emision);
ANALYZE monitoreo_sismologico.evento_sismico;
ANALYZE monitoreo_sismologico.deteccion;
ANALYZE monitoreo_sismologico.alerta;

-- Paso 3. Volver a seleccionar y ejecutar el MISMO SELECT del paso 1.
-- Presionar F5 para las filas y Shift+F7 para el plan CON indices candidatos.
-- Comparar filas, operadores del plan, Execution Time y buffers.
-- Que exista un indice candidato no implica que el planificador lo use.
-- Paso 4. Revertir los indices candidatos antes de continuar.
ROLLBACK;


-- ============================================================
-- C5. SENSORES SIN DETECCIONES EN UNA VENTANA DE LECTURAS
-- ============================================================
-- Paso 1. Iniciar la transaccion y mostrar el resultado SIN indice candidato.
BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;

SELECT s.id_sensor, s.numero_serie, e.codigo AS codigo_estacion,
       COUNT(*) AS lecturas_periodo,
       COUNT(*) FILTER (WHERE NOT l.es_valida) AS lecturas_invalidas,
       ROUND(AVG(ABS(l.valor)), 6) AS amplitud_media_absoluta,
       MAX(l.fecha_hora) AS ultima_lectura
FROM lectura_onda l
JOIN sensor s ON s.id_sensor = l.id_sensor
JOIN estacion_sismica e ON e.id_estacion = s.id_estacion
WHERE l.fecha_hora >= TIMESTAMP '2026-08-05 00:00:00'
  AND l.fecha_hora < TIMESTAMP '2026-08-06 00:00:00'
  AND NOT EXISTS (
      SELECT 1 FROM deteccion d
      WHERE d.id_sensor = s.id_sensor
        AND d.hora_deteccion >= TIMESTAMP '2026-08-05 00:00:00'
        AND d.hora_deteccion < TIMESTAMP '2026-08-06 00:00:00'
  )
GROUP BY s.id_sensor, s.numero_serie, e.codigo
HAVING COUNT(*) >= 1
ORDER BY lecturas_invalidas DESC,
         lecturas_periodo DESC, s.id_sensor
LIMIT 15;

-- Para el arbol: seleccionar solamente el SELECT anterior y usar Shift+F7.
-- Paso 2. Crear el/los indice(s) candidato(s) de C5 y actualizar estadisticas.
CREATE INDEX idx_lectura_fecha_sensor_c5
    ON monitoreo_sismologico.lectura_onda (fecha_hora, id_sensor) INCLUDE (es_valida, valor);
CREATE INDEX idx_deteccion_sensor_hora_c5
    ON monitoreo_sismologico.deteccion (id_sensor, hora_deteccion);
ANALYZE monitoreo_sismologico.lectura_onda;
ANALYZE monitoreo_sismologico.deteccion;

-- Paso 3. Volver a seleccionar y ejecutar el MISMO SELECT del paso 1.
-- Presionar F5 para las filas y Shift+F7 para el plan CON indices candidatos.
-- Comparar filas, operadores del plan, Execution Time y buffers.
-- Que exista un indice candidato no implica que el planificador lo use.
-- Paso 4. Revertir los indices candidatos antes de continuar.
ROLLBACK;
