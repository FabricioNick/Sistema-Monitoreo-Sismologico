-- Proyecto Final - Seccion 5.3.1
-- C1: crear el indice secundario candidato sobre los datos experimentales.
-- Ejecutar SOLO en bd_sismologico_exp_1000000, tras guardar el plan base (21).
-- No cambia registros ni toca los indices obligatorios de integridad.
-- Si falla una instruccion dentro de BEGIN, ejecutar ROLLBACK antes de continuar.

\set ON_ERROR_STOP on
\pset pager off
BEGIN;
SET search_path TO monitoreo_sismologico, public;

DO $$
BEGIN
    IF current_database() <> 'bd_sismologico_exp_1000000' THEN
        RAISE EXCEPTION 'Base incorrecta: %. Se requiere bd_sismologico_exp_1000000.', current_database();
    END IF;

    IF (SELECT COUNT(*) FROM monitoreo_sismologico.evento_sismico) <> 120000 THEN
        RAISE EXCEPTION 'EVENTO_SISMICO no contiene las 120000 filas esperadas.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'monitoreo_sismologico'
          AND t.relname = 'evento_sismico'
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid = i.indexrelid
                AND c.contype IN ('p', 'u', 'x')
          )
    ) THEN
        RAISE EXCEPTION 'Hay indices secundarios en EVENTO_SISMICO. Revisar antes de continuar.';
    END IF;
END;
$$;

\echo
\echo === C1 - CREACION DEL INDICE SECUNDARIO PARCIAL ===
CREATE INDEX idx_ev_igp_m6_fecha
ON monitoreo_sismologico.evento_sismico (fecha_hora_origen)
INCLUDE (magnitud, profundidad_km)
WHERE id_evento BETWEEN 200000000 AND 299999999
  AND magnitud >= 6;

-- Actualizar las estadisticas del planificador despues de crear el indice.
ANALYZE monitoreo_sismologico.evento_sismico;

\echo
\echo === INDICES DE EVENTO_SISMICO DESPUES DE LA CREACION ===
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'monitoreo_sismologico'
  AND tablename = 'evento_sismico'
ORDER BY indexname;

\echo
\echo === TAMANO DEL INDICE CANDIDATO ===
SELECT pg_size_pretty(
    pg_relation_size('monitoreo_sismologico.idx_ev_igp_m6_fecha'::regclass)
) AS espacio_indice_c1;

COMMIT;
\echo
\echo === C1 - INDICE CREADO. CONTINUAR CON EL ARCHIVO 23 ===
