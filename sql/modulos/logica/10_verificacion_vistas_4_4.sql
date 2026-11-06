-- Proyecto Final - Seccion 4.4 - Verificacion de las cinco vistas
-- No modifica datos. Ejecutar despues del COMMIT del archivo 09.

\set ON_ERROR_STOP on
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
