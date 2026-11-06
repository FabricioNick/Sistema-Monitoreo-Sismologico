-- 02. CARGA Y SIMULACION DE DATOS
-- CSV oficial: datos/igp_catalogo.csv (UTF-8, separador ;).
\set ON_ERROR_STOP on
\pset pager off

\echo '=== DATOS: BASE DE TRABAJO ==='
SELECT current_database() AS base_actual;
SET search_path TO monitoreo_sismologico, public;

-- Base con seis tablas y sin registros.
DO $$
DECLARE
    objeto TEXT;
    cantidad BIGINT;
BEGIN
    IF current_database() IN ('postgres', 'template0', 'template1') THEN
        RAISE EXCEPTION 'Seleccione una base de trabajo, no una base del sistema.';
    END IF;

    FOREACH objeto IN ARRAY ARRAY[
        'estacion_sismica', 'sensor', 'lectura_onda',
        'evento_sismico', 'deteccion', 'alerta'
    ] LOOP
        IF to_regclass(format('monitoreo_sismologico.%I', objeto)) IS NULL THEN
            RAISE EXCEPTION 'Falta la tabla % en monitoreo_sismologico.', objeto;
        END IF;
        EXECUTE format('SELECT COUNT(*) FROM monitoreo_sismologico.%I', objeto) INTO cantidad;
        IF cantidad <> 0 THEN
            RAISE EXCEPTION 'La tabla % tiene % filas. La carga requiere tablas vacias.', objeto, cantidad;
        END IF;
    END LOOP;
    RAISE NOTICE 'OK: seis tablas vacias.';
END;
$$;

BEGIN;
SET LOCAL search_path TO monitoreo_sismologico, public;


\echo '=== CARGA INICIAL ==='
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM estacion_sismica WHERE id_estacion BETWEEN 810000001 AND 810000999)
       OR EXISTS (SELECT 1 FROM sensor WHERE id_sensor BETWEEN 810000001 AND 810000999)
       OR EXISTS (SELECT 1 FROM lectura_onda WHERE id_lectura BETWEEN 810000001 AND 810000999)
       OR EXISTS (SELECT 1 FROM evento_sismico WHERE id_evento BETWEEN 810000001 AND 810000999)
       OR EXISTS (SELECT 1 FROM deteccion WHERE id_sensor BETWEEN 810000001 AND 810000999)
       OR EXISTS (SELECT 1 FROM alerta WHERE id_alerta BETWEEN 810000001 AND 810000999) THEN
        RAISE EXCEPTION 'La carga inicial ya existe. No repetir la importacion.';
    END IF;
END;
$$;

INSERT INTO estacion_sismica (id_estacion, codigo, nombre, latitud, longitud, altitud, departamento, provincia, distrito, fecha_instalacion, estado) VALUES
    (810000001, 'SIM42-EST-01', 'Estacion Simulada Costa Norte', -6.9, -79.7, 65, 'Lambayeque', 'Chiclayo', 'Chiclayo', '2023-03-15', 'operativa'),
    (810000002, 'SIM42-EST-02', 'Estacion Simulada Costa Centro', -12.05, -77.05, 130, 'Lima', 'Lima', 'Lima', '2023-03-15', 'operativa'),
    (810000003, 'SIM42-EST-03', 'Estacion Simulada Sierra Sur', -16.4, -71.5, 2350, 'Arequipa', 'Arequipa', 'Arequipa', '2023-03-15', 'operativa'),
    (810000004, 'SIM42-EST-04', 'Estacion Simulada Sierra Centro', -11.99, -75.1, 3250, 'Junin', 'Huancayo', 'Huancayo', '2023-03-15', 'operativa'),
    (810000005, 'SIM42-EST-05', 'Estacion Simulada Selva Alta', -9.5, -75.9, 1700, 'Huanuco', 'Huanuco', 'Huanuco', '2023-03-15', 'operativa');

INSERT INTO sensor (id_sensor, numero_serie, tipo, modelo, unidad_medida, frecuencia_muestreo, fecha_instalacion, fecha_ultimo_mantenimiento, estado, id_estacion) VALUES
    (810000001, 'SIM42-SEN-01', 'acelerometro', 'Modelo-SIM-2', 'm/s2', 50, '2024-06-01', NULL, 'operativo', 810000001),
    (810000002, 'SIM42-SEN-02', 'acelerometro', 'Modelo-SIM-3', 'm/s2', 100, '2024-06-01', NULL, 'operativo', 810000001),
    (810000003, 'SIM42-SEN-03', 'acelerometro', 'Modelo-SIM-1', 'm/s2', 50, '2024-06-01', NULL, 'operativo', 810000002),
    (810000004, 'SIM42-SEN-04', 'acelerometro', 'Modelo-SIM-2', 'm/s2', 100, '2024-06-01', '2026-09-12', 'operativo', 810000002),
    (810000005, 'SIM42-SEN-05', 'acelerometro', 'Modelo-SIM-3', 'm/s2', 50, '2024-06-01', NULL, 'operativo', 810000003),
    (810000006, 'SIM42-SEN-06', 'acelerometro', 'Modelo-SIM-1', 'm/s2', 100, '2024-06-01', NULL, 'operativo', 810000003),
    (810000007, 'SIM42-SEN-07', 'acelerometro', 'Modelo-SIM-2', 'm/s2', 50, '2024-06-01', '2026-09-12', 'operativo', 810000004),
    (810000008, 'SIM42-SEN-08', 'acelerometro', 'Modelo-SIM-3', 'm/s2', 100, '2024-06-01', NULL, 'operativo', 810000004),
    (810000009, 'SIM42-SEN-09', 'acelerometro', 'Modelo-SIM-1', 'm/s2', 50, '2024-06-01', NULL, 'mantenimiento', 810000005),
    (810000010, 'SIM42-SEN-10', 'acelerometro', 'Modelo-SIM-2', 'm/s2', 100, '2024-06-01', NULL, 'fuera_servicio', 810000005);

INSERT INTO lectura_onda (id_lectura, id_sensor, fecha_hora, canal, valor, es_valida) VALUES
    (810000001, 810000001, '2026-10-26 16:22:03', 'X', 0.18, TRUE),
    (810000002, 810000002, '2026-10-26 16:22:06', 'X', 0.22, TRUE),
    (810000003, 810000003, '2026-10-26 16:22:09', 'X', 0.26, TRUE),
    (810000004, 810000004, '2026-10-28 00:29:12', 'X', 0.32, TRUE),
    (810000005, 810000005, '2026-10-28 00:29:15', 'X', 0.36, TRUE),
    (810000006, 810000002, '2026-10-29 08:36:06', 'X', 0.26, TRUE),
    (810000007, 810000006, '2026-10-29 08:36:18', 'X', 0.42, TRUE),
    (810000008, 810000003, '2026-10-30 16:43:09', 'X', 0.32, TRUE),
    (810000009, 810000007, '2026-10-30 16:43:21', 'X', 0.48, TRUE),
    (810000010, 810000004, '2026-11-01 00:50:12', 'X', 0.38, TRUE),
    (810000011, 810000008, '2026-11-01 00:50:24', 'X', 0.54, TRUE),
    (810000012, 810000005, '2026-11-02 08:57:15', 'X', 0.44, TRUE),
    (810000013, 810000001, '2026-11-03 17:04:03', 'X', 0.3, TRUE),
    (810000014, 810000006, '2026-11-03 17:04:18', 'X', 0.5, TRUE),
    (810000015, 810000001, '2026-10-25 02:00:00', 'X', -0.5198, FALSE),
    (810000016, 810000001, '2026-10-25 14:00:03', 'Y', 0.254, TRUE),
    (810000017, 810000001, '2026-10-26 02:00:06', 'Z', -0.4886, TRUE),
    (810000018, 810000001, '2026-10-26 14:00:09', 'X', 0.4804, TRUE),
    (810000019, 810000001, '2026-10-27 02:00:12', 'Y', -0.5624, TRUE),
    (810000020, 810000001, '2026-10-27 14:00:15', 'Z', 0.1608, TRUE),
    (810000021, 810000001, '2026-10-28 02:00:18', 'X', -0.4622, TRUE),
    (810000022, 810000001, '2026-10-28 14:00:21', 'Y', 0.5153, TRUE),
    (810000023, 810000001, '2026-10-29 02:00:24', 'Z', -0.4615, TRUE),
    (810000024, 810000001, '2026-10-29 14:00:27', 'X', 0.2279, FALSE),
    (810000025, 810000001, '2026-10-30 02:00:30', 'Y', 0.3469, TRUE),
    (810000026, 810000001, '2026-10-30 14:00:33', 'Z', -0.0614, TRUE),
    (810000027, 810000001, '2026-10-31 02:00:36', 'X', 0.4053, TRUE),
    (810000028, 810000001, '2026-10-31 14:00:39', 'Y', -0.4418, TRUE),
    (810000029, 810000001, '2026-11-01 02:00:42', 'Z', -0.6627, TRUE),
    (810000030, 810000001, '2026-11-01 14:00:45', 'X', -0.3244, TRUE),
    (810000031, 810000001, '2026-11-02 02:00:48', 'Y', 0.6333, TRUE),
    (810000032, 810000001, '2026-11-02 14:00:51', 'Z', 0.5195, TRUE),
    (810000033, 810000001, '2026-11-03 02:00:54', 'X', -0.0205, FALSE),
    (810000034, 810000001, '2026-11-03 14:00:57', 'Y', -0.6054, TRUE),
    (810000035, 810000001, '2026-11-04 02:01:00', 'Z', 0.0898, TRUE),
    (810000036, 810000001, '2026-11-04 14:01:03', 'X', 0.6385, TRUE),
    (810000037, 810000002, '2026-10-25 04:00:00', 'X', -0.0281, FALSE),
    (810000038, 810000002, '2026-10-25 16:00:03', 'Y', 0.4676, TRUE),
    (810000039, 810000002, '2026-10-26 04:00:06', 'Z', -0.1713, TRUE),
    (810000040, 810000002, '2026-10-26 16:00:09', 'X', -0.0032, TRUE),
    (810000041, 810000002, '2026-10-27 04:00:12', 'Y', 0.0654, TRUE),
    (810000042, 810000002, '2026-10-27 16:00:15', 'Z', 0.6742, TRUE),
    (810000043, 810000002, '2026-10-28 04:00:18', 'X', -0.6346, TRUE),
    (810000044, 810000002, '2026-10-28 16:00:21', 'Y', 0.6047, TRUE),
    (810000045, 810000002, '2026-10-29 04:00:24', 'Z', 0.0232, TRUE),
    (810000046, 810000002, '2026-10-29 16:00:27', 'X', 0.3426, FALSE),
    (810000047, 810000002, '2026-10-30 04:00:30', 'Y', 0.558, TRUE),
    (810000048, 810000002, '2026-10-30 16:00:33', 'Z', -0.0431, TRUE),
    (810000049, 810000002, '2026-10-31 04:00:36', 'X', -0.6243, TRUE),
    (810000050, 810000002, '2026-10-31 16:00:39', 'Y', -0.0733, TRUE),
    (810000051, 810000002, '2026-11-01 04:00:42', 'Z', 0.173, TRUE),
    (810000052, 810000002, '2026-11-01 16:00:45', 'X', 0.4654, TRUE),
    (810000053, 810000002, '2026-11-02 04:00:48', 'Y', -0.5216, TRUE),
    (810000054, 810000002, '2026-11-02 16:00:51', 'Z', -0.3784, TRUE),
    (810000055, 810000002, '2026-11-03 04:00:54', 'X', 0.4895, FALSE),
    (810000056, 810000002, '2026-11-03 16:00:57', 'Y', -0.6581, TRUE),
    (810000057, 810000002, '2026-11-04 04:01:00', 'Z', 0.1554, TRUE),
    (810000058, 810000002, '2026-11-04 16:01:03', 'X', 0.4247, TRUE),
    (810000059, 810000003, '2026-10-25 06:00:00', 'X', 0.6769, FALSE),
    (810000060, 810000003, '2026-10-25 18:00:03', 'Y', -0.6232, TRUE),
    (810000061, 810000003, '2026-10-26 06:00:06', 'Z', 0.3131, TRUE),
    (810000062, 810000003, '2026-10-26 18:00:09', 'X', -0.4169, TRUE),
    (810000063, 810000003, '2026-10-27 06:00:12', 'Y', -0.6012, TRUE),
    (810000064, 810000003, '2026-10-27 18:00:15', 'Z', -0.1383, TRUE),
    (810000065, 810000003, '2026-10-28 06:00:18', 'X', 0.3527, TRUE),
    (810000066, 810000003, '2026-10-28 18:00:21', 'Y', -0.6422, TRUE),
    (810000067, 810000003, '2026-10-29 06:00:24', 'Z', -0.0764, TRUE),
    (810000068, 810000003, '2026-10-29 18:00:27', 'X', 0.2685, FALSE),
    (810000069, 810000003, '2026-10-30 06:00:30', 'Y', 0.025, TRUE),
    (810000070, 810000003, '2026-10-30 18:00:33', 'Z', 0.2436, TRUE),
    (810000071, 810000003, '2026-10-31 06:00:36', 'X', 0.6003, TRUE),
    (810000072, 810000003, '2026-10-31 18:00:39', 'Y', -0.2409, TRUE),
    (810000073, 810000003, '2026-11-01 06:00:42', 'Z', 0.2552, TRUE),
    (810000074, 810000003, '2026-11-01 18:00:45', 'X', 0.4439, TRUE),
    (810000075, 810000003, '2026-11-02 06:00:48', 'Y', -0.139, TRUE),
    (810000076, 810000003, '2026-11-02 18:00:51', 'Z', 0.1981, TRUE),
    (810000077, 810000003, '2026-11-03 06:00:54', 'X', -0.581, FALSE),
    (810000078, 810000003, '2026-11-03 18:00:57', 'Y', 0.4671, TRUE),
    (810000079, 810000003, '2026-11-04 06:01:00', 'Z', 0.1697, TRUE),
    (810000080, 810000003, '2026-11-04 18:01:03', 'X', 0.2891, TRUE),
    (810000081, 810000004, '2026-10-25 08:00:00', 'X', -0.5985, FALSE),
    (810000082, 810000004, '2026-10-25 20:00:03', 'Y', -0.0932, TRUE),
    (810000083, 810000004, '2026-10-26 08:00:06', 'Z', 0.5727, TRUE),
    (810000084, 810000004, '2026-10-26 20:00:09', 'X', -0.4985, TRUE),
    (810000085, 810000004, '2026-10-27 08:00:12', 'Y', 0.1143, TRUE),
    (810000086, 810000004, '2026-10-27 20:00:15', 'Z', -0.0463, TRUE),
    (810000087, 810000004, '2026-10-28 08:00:18', 'X', -0.5224, TRUE),
    (810000088, 810000004, '2026-10-28 20:00:21', 'Y', 0.6983, TRUE),
    (810000089, 810000004, '2026-10-29 08:00:24', 'Z', -0.6352, TRUE),
    (810000090, 810000004, '2026-10-29 20:00:27', 'X', 0.5609, FALSE),
    (810000091, 810000004, '2026-10-30 08:00:30', 'Y', -0.5025, TRUE),
    (810000092, 810000004, '2026-10-30 20:00:33', 'Z', -0.2209, TRUE),
    (810000093, 810000004, '2026-10-31 08:00:36', 'X', -0.6856, TRUE),
    (810000094, 810000004, '2026-10-31 20:00:39', 'Y', -0.1531, TRUE),
    (810000095, 810000004, '2026-11-01 08:00:42', 'Z', 0.4692, TRUE),
    (810000096, 810000004, '2026-11-01 20:00:45', 'X', -0.0101, TRUE),
    (810000097, 810000004, '2026-11-02 08:00:48', 'Y', 0.3083, TRUE),
    (810000098, 810000004, '2026-11-02 20:00:51', 'Z', -0.1846, TRUE),
    (810000099, 810000004, '2026-11-03 08:00:54', 'X', -0.539, FALSE),
    (810000100, 810000004, '2026-11-03 20:00:57', 'Y', 0.3753, TRUE),
    (810000101, 810000004, '2026-11-04 08:01:00', 'Z', -0.3566, TRUE),
    (810000102, 810000004, '2026-11-04 20:01:03', 'X', -0.0015, TRUE),
    (810000103, 810000005, '2026-10-25 10:00:00', 'X', 0.1325, FALSE),
    (810000104, 810000005, '2026-10-25 22:00:03', 'Y', -0.6839, TRUE),
    (810000105, 810000005, '2026-10-26 10:00:06', 'Z', -0.52, TRUE),
    (810000106, 810000005, '2026-10-26 22:00:09', 'X', 0.1401, TRUE),
    (810000107, 810000005, '2026-10-27 10:00:12', 'Y', 0.5514, TRUE),
    (810000108, 810000005, '2026-10-27 22:00:15', 'Z', -0.4811, TRUE),
    (810000109, 810000005, '2026-10-28 10:00:18', 'X', 0.2344, TRUE),
    (810000110, 810000005, '2026-10-28 22:00:21', 'Y', -0.0496, TRUE),
    (810000111, 810000005, '2026-10-29 10:00:24', 'Z', 0.4348, TRUE),
    (810000112, 810000005, '2026-10-29 22:00:27', 'X', 0.065, FALSE),
    (810000113, 810000005, '2026-10-30 10:00:30', 'Y', -0.3129, TRUE),
    (810000114, 810000005, '2026-10-30 22:00:33', 'Z', -0.3321, TRUE),
    (810000115, 810000005, '2026-10-31 10:00:36', 'X', 0.2575, TRUE),
    (810000116, 810000005, '2026-10-31 22:00:39', 'Y', -0.1241, TRUE),
    (810000117, 810000005, '2026-11-01 10:00:42', 'Z', 0.6445, TRUE),
    (810000118, 810000005, '2026-11-01 22:00:45', 'X', -0.4053, TRUE),
    (810000119, 810000005, '2026-11-02 10:00:48', 'Y', 0.3246, TRUE),
    (810000120, 810000005, '2026-11-02 22:00:51', 'Z', -0.5748, TRUE),
    (810000121, 810000005, '2026-11-03 10:00:54', 'X', -0.6522, FALSE),
    (810000122, 810000005, '2026-11-03 22:00:57', 'Y', 0.0033, TRUE),
    (810000123, 810000005, '2026-11-04 10:01:00', 'Z', -0.102, TRUE),
    (810000124, 810000005, '2026-11-04 22:01:03', 'X', 0.3942, TRUE),
    (810000125, 810000006, '2026-10-25 12:00:00', 'X', 0.0924, FALSE),
    (810000126, 810000006, '2026-10-26 00:00:03', 'Y', 0.5115, TRUE),
    (810000127, 810000006, '2026-10-26 12:00:06', 'Z', 0.1725, TRUE),
    (810000128, 810000006, '2026-10-27 00:00:09', 'X', -0.0742, TRUE),
    (810000129, 810000006, '2026-10-27 12:00:12', 'Y', 0.0264, TRUE),
    (810000130, 810000006, '2026-10-28 00:00:15', 'Z', 0.0625, TRUE),
    (810000131, 810000006, '2026-10-28 12:00:18', 'X', 0.4732, TRUE),
    (810000132, 810000006, '2026-10-29 00:00:21', 'Y', -0.6773, TRUE),
    (810000133, 810000006, '2026-10-29 12:00:24', 'Z', -0.3799, TRUE),
    (810000134, 810000006, '2026-10-30 00:00:27', 'X', 0.1736, FALSE),
    (810000135, 810000006, '2026-10-30 12:00:30', 'Y', 0.6712, TRUE),
    (810000136, 810000006, '2026-10-31 00:00:33', 'Z', 0.0415, TRUE),
    (810000137, 810000006, '2026-10-31 12:00:36', 'X', 0.379, TRUE),
    (810000138, 810000006, '2026-11-01 00:00:39', 'Y', 0.3164, TRUE),
    (810000139, 810000006, '2026-11-01 12:00:42', 'Z', -0.5086, TRUE),
    (810000140, 810000006, '2026-11-02 00:00:45', 'X', -0.3274, TRUE),
    (810000141, 810000006, '2026-11-02 12:00:48', 'Y', 0.6818, TRUE),
    (810000142, 810000006, '2026-11-03 00:00:51', 'Z', -0.3537, TRUE),
    (810000143, 810000006, '2026-11-03 12:00:54', 'X', -0.2317, FALSE),
    (810000144, 810000006, '2026-11-04 00:00:57', 'Y', 0.532, TRUE),
    (810000145, 810000006, '2026-11-04 12:01:00', 'Z', 0.1948, TRUE),
    (810000146, 810000006, '2026-11-05 00:01:03', 'X', 0.1959, TRUE),
    (810000147, 810000007, '2026-10-25 14:00:00', 'X', 0.5015, FALSE),
    (810000148, 810000007, '2026-10-26 02:00:03', 'Y', 0.1314, TRUE),
    (810000149, 810000007, '2026-10-26 14:00:06', 'Z', -0.4236, TRUE),
    (810000150, 810000007, '2026-10-27 02:00:09', 'X', -0.2342, TRUE),
    (810000151, 810000007, '2026-10-27 14:00:12', 'Y', -0.1644, TRUE),
    (810000152, 810000007, '2026-10-28 02:00:15', 'Z', 0.0052, TRUE),
    (810000153, 810000007, '2026-10-28 14:00:18', 'X', -0.36, TRUE),
    (810000154, 810000007, '2026-10-29 02:00:21', 'Y', -0.4459, TRUE),
    (810000155, 810000007, '2026-10-29 14:00:24', 'Z', -0.2547, TRUE),
    (810000156, 810000007, '2026-10-30 02:00:27', 'X', -0.317, FALSE),
    (810000157, 810000007, '2026-10-30 14:00:30', 'Y', -0.0104, TRUE),
    (810000158, 810000007, '2026-10-31 02:00:33', 'Z', 0.5708, TRUE),
    (810000159, 810000007, '2026-10-31 14:00:36', 'X', -0.2835, TRUE),
    (810000160, 810000007, '2026-11-01 02:00:39', 'Y', 0.4389, TRUE),
    (810000161, 810000007, '2026-11-01 14:00:42', 'Z', -0.5705, TRUE),
    (810000162, 810000007, '2026-11-02 02:00:45', 'X', -0.345, TRUE),
    (810000163, 810000007, '2026-11-02 14:00:48', 'Y', -0.2703, TRUE),
    (810000164, 810000007, '2026-11-03 02:00:51', 'Z', 0.1181, TRUE),
    (810000165, 810000007, '2026-11-03 14:00:54', 'X', 0.3142, FALSE),
    (810000166, 810000007, '2026-11-04 02:00:57', 'Y', 0.3343, TRUE),
    (810000167, 810000007, '2026-11-04 14:01:00', 'Z', -0.0707, TRUE),
    (810000168, 810000007, '2026-11-05 02:01:03', 'X', -0.1328, TRUE),
    (810000169, 810000008, '2026-10-25 16:00:00', 'X', -0.5984, FALSE),
    (810000170, 810000008, '2026-10-26 04:00:03', 'Y', -0.1302, TRUE),
    (810000171, 810000008, '2026-10-26 16:00:06', 'Z', 0.1942, TRUE),
    (810000172, 810000008, '2026-10-27 04:00:09', 'X', 0.0142, TRUE),
    (810000173, 810000008, '2026-10-27 16:00:12', 'Y', -0.1908, TRUE),
    (810000174, 810000008, '2026-10-28 04:00:15', 'Z', 0.357, TRUE),
    (810000175, 810000008, '2026-10-28 16:00:18', 'X', 0.4735, TRUE),
    (810000176, 810000008, '2026-10-29 04:00:21', 'Y', 0.4169, TRUE),
    (810000177, 810000008, '2026-10-29 16:00:24', 'Z', -0.0853, TRUE),
    (810000178, 810000008, '2026-10-30 04:00:27', 'X', -0.0498, FALSE),
    (810000179, 810000008, '2026-10-30 16:00:30', 'Y', -0.3445, TRUE),
    (810000180, 810000008, '2026-10-31 04:00:33', 'Z', -0.1446, TRUE),
    (810000181, 810000008, '2026-10-31 16:00:36', 'X', -0.265, TRUE),
    (810000182, 810000008, '2026-11-01 04:00:39', 'Y', 0.3159, TRUE),
    (810000183, 810000008, '2026-11-01 16:00:42', 'Z', 0.515, TRUE),
    (810000184, 810000008, '2026-11-02 04:00:45', 'X', -0.3058, TRUE),
    (810000185, 810000008, '2026-11-02 16:00:48', 'Y', -0.2683, TRUE),
    (810000186, 810000008, '2026-11-03 04:00:51', 'Z', 0.1938, TRUE),
    (810000187, 810000008, '2026-11-03 16:00:54', 'X', -0.4002, FALSE),
    (810000188, 810000008, '2026-11-04 04:00:57', 'Y', 0.3507, TRUE),
    (810000189, 810000008, '2026-11-04 16:01:00', 'Z', 0.6698, TRUE),
    (810000190, 810000008, '2026-11-05 04:01:03', 'X', -0.4935, TRUE);

INSERT INTO evento_sismico (id_evento, fecha_hora_origen, latitud_epicentro, longitud_epicentro, profundidad_km, magnitud, tipo_magnitud, intensidad_maxima, referencia_geografica, estado_revision) VALUES
    (810000001, '2026-10-26 16:22:00', -15.95, -75.45, 16, 3.02, 'Mw', NULL, 'SIMULACION: epicentro no verificado', 'preliminar'),
    (810000002, '2026-10-28 00:29:00', -15.1, -74.4, 22, 3.34, 'Mw', NULL, 'SIMULACION: epicentro no verificado', 'preliminar'),
    (810000003, '2026-10-29 08:36:00', -14.25, -73.35, 28, 3.66, 'Mw', NULL, 'SIMULACION: epicentro no verificado', 'preliminar'),
    (810000004, '2026-10-30 16:43:00', -13.4, -76.5, 34, 3.98, 'Mw', NULL, 'SIMULACION: epicentro no verificado', 'preliminar'),
    (810000005, '2026-11-01 00:50:00', -12.55, -75.45, 40, 4.3, 'Mw', NULL, 'SIMULACION: epicentro no verificado', 'preliminar'),
    (810000006, '2026-11-02 08:57:00', -11.7, -74.4, 46, 4.62, 'Mw', NULL, 'SIMULACION: epicentro no verificado', 'preliminar'),
    (810000007, '2026-11-03 17:04:00', -10.85, -73.35, 52, 4.94, 'Mw', NULL, 'SIMULACION: epicentro no verificado', 'preliminar'),
    (810000008, '2026-11-05 01:11:00', -10.0, -76.5, 58, 5.26, 'Mw', NULL, 'SIMULACION: epicentro no verificado', 'preliminar');

INSERT INTO deteccion (id_sensor, id_evento, hora_deteccion, aceleracion_maxima, calidad) VALUES
    (810000001, 810000001, '2026-10-26 16:22:03', 0.18, 'alta'),
    (810000002, 810000001, '2026-10-26 16:22:06', 0.22, 'alta'),
    (810000003, 810000001, '2026-10-26 16:22:09', 0.26, 'alta'),
    (810000004, 810000002, '2026-10-28 00:29:12', 0.32, 'alta'),
    (810000005, 810000002, '2026-10-28 00:29:15', 0.36, 'alta'),
    (810000002, 810000003, '2026-10-29 08:36:06', 0.26, 'alta'),
    (810000006, 810000003, '2026-10-29 08:36:18', 0.42, 'alta'),
    (810000003, 810000004, '2026-10-30 16:43:09', 0.32, 'alta'),
    (810000007, 810000004, '2026-10-30 16:43:21', 0.48, 'alta'),
    (810000004, 810000005, '2026-11-01 00:50:12', 0.38, 'alta'),
    (810000008, 810000005, '2026-11-01 00:50:24', 0.54, 'alta'),
    (810000005, 810000006, '2026-11-02 08:57:15', 0.44, 'alta'),
    (810000001, 810000007, '2026-11-03 17:04:03', 0.3, 'alta'),
    (810000006, 810000007, '2026-11-03 17:04:18', 0.5, 'alta');

INSERT INTO alerta (id_alerta, id_evento, fecha_hora_emision, nivel, mensaje, magnitud_estimada, estado) VALUES
    ('810000001', 810000001, '2026-10-26 16:23:05', 'informativa', 'SIMULACION: alerta sin difusion real', 3.02, 'registrada'),
    ('810000002', 810000002, '2026-10-28 00:30:05', 'informativa', 'SIMULACION: alerta sin difusion real', 3.34, 'registrada'),
    ('810000003', 810000003, '2026-10-29 08:37:05', 'informativa', 'SIMULACION: alerta sin difusion real', 3.66, 'registrada'),
    ('810000004', 810000005, '2026-11-01 00:51:05', 'informativa', 'SIMULACION: alerta sin difusion real', 4.3, 'registrada'),
    ('810000005', 810000007, '2026-11-03 17:05:05', 'informativa', 'SIMULACION: alerta sin difusion real', 4.94, 'registrada');

DO $$
DECLARE
    control RECORD;
    encontrado BIGINT;
BEGIN
    FOR control IN
        SELECT * FROM (VALUES
            ('estacion_sismica', 5, 'id_estacion'),
            ('sensor', 10, 'id_sensor'),
            ('lectura_onda', 190, 'id_lectura'),
            ('evento_sismico', 8, 'id_evento'),
            ('alerta', 5, 'id_alerta')
        ) AS e(tabla, esperado, columna)
    LOOP
        EXECUTE format('SELECT COUNT(*) FROM %I WHERE %I BETWEEN 810000001 AND 810000999',
                       control.tabla, control.columna) INTO encontrado;
        IF encontrado <> control.esperado THEN
            RAISE EXCEPTION 'Cantidad incorrecta en %: esperaba %, hay %',
                            control.tabla, control.esperado, encontrado;
        END IF;
    END LOOP;

    SELECT COUNT(*) INTO encontrado FROM deteccion
    WHERE id_sensor BETWEEN 810000001 AND 810000999
      AND id_evento BETWEEN 810000001 AND 810000999;
    IF encontrado <> 14 THEN
        RAISE EXCEPTION 'Cantidad incorrecta en deteccion: esperaba 14, hay %', encontrado;
    END IF;

    RAISE NOTICE 'OK: 232 registros sintéticos verificados antes del COMMIT';
END;
$$;


\echo '=== CONTROL DE CARGA INICIAL ==='
SELECT 'estacion_sismica' AS tabla, 5 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=5 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM estacion_sismica WHERE id_estacion BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'sensor' AS tabla, 10 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=10 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM sensor WHERE id_sensor BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'lectura_onda' AS tabla, 190 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=190 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM lectura_onda WHERE id_lectura BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'evento_sismico' AS tabla, 8 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=8 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM evento_sismico WHERE id_evento BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'deteccion' AS tabla, 14 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=14 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM deteccion WHERE id_sensor BETWEEN 810000001 AND 810000999 AND id_evento BETWEEN 810000001 AND 810000999
UNION ALL
SELECT 'alerta' AS tabla, 5 AS esperado, COUNT(*) AS encontrado, CASE WHEN COUNT(*)=5 THEN 'OK' ELSE 'REVISAR' END AS resultado FROM alerta WHERE id_alerta BETWEEN 810000001 AND 810000999
ORDER BY tabla;


SELECT 'estaciones_sin_sensores' AS control, COUNT(*) AS encontrados, 0 AS esperado
FROM estacion_sismica e
WHERE e.id_estacion BETWEEN 810000001 AND 810000999
AND NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion=e.id_estacion)
UNION ALL
SELECT 'lecturas_huerfanas', COUNT(*), 0
FROM lectura_onda l LEFT JOIN sensor s ON l.id_sensor=s.id_sensor
WHERE l.id_lectura BETWEEN 810000001 AND 810000999 AND s.id_sensor IS NULL
UNION ALL
SELECT 'detecciones_sin_lectura_valida', COUNT(*), 0
FROM deteccion d
WHERE d.id_sensor BETWEEN 810000001 AND 810000999
AND NOT EXISTS (SELECT 1 FROM lectura_onda l WHERE l.id_sensor=d.id_sensor AND l.fecha_hora=d.hora_deteccion AND l.es_valida)
UNION ALL
SELECT 'lecturas_validas_sensor_no_operativo', COUNT(*), 0
FROM lectura_onda l JOIN sensor s ON l.id_sensor=s.id_sensor
WHERE l.id_lectura BETWEEN 810000001 AND 810000999 AND l.es_valida AND s.estado <> 'operativo';

SELECT COUNT(*) FILTER (WHERE es_valida) AS lecturas_validas,
       COUNT(*) FILTER (WHERE NOT es_valida) AS lecturas_invalidas
FROM lectura_onda
WHERE id_lectura BETWEEN 810000001 AND 810000999;

SELECT e.id_evento, COUNT(DISTINCT d.id_sensor) AS sensores_que_detectaron,
       COUNT(DISTINCT a.id_alerta) AS alertas_emitidas
FROM evento_sismico e
LEFT JOIN deteccion d ON d.id_evento=e.id_evento
LEFT JOIN alerta a ON a.id_evento=e.id_evento
WHERE e.id_evento BETWEEN 810000001 AND 810000999
GROUP BY e.id_evento
ORDER BY e.id_evento;


\echo '=== IMPORTACION DEL CATALOGO IGP ==='
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

\copy igp_catalogo_42 (id, fecha_utc, hora_utc, latitud, longitud, profundidad, magnitud, fecha_corte) FROM 'datos/igp_catalogo.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'UTF8')

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


\echo '=== CONTROL DEL CATALOGO IGP ==='
SELECT 'estacion_sismica' AS tabla, COUNT(*) AS encontrados, 5 AS minimo_inicial
FROM estacion_sismica
UNION ALL SELECT 'sensor', COUNT(*), 10 FROM sensor
UNION ALL SELECT 'lectura_onda', COUNT(*), 190 FROM lectura_onda
UNION ALL SELECT 'deteccion', COUNT(*), 14 FROM deteccion
UNION ALL SELECT 'alerta', COUNT(*), 5 FROM alerta
ORDER BY tabla;

SELECT
    COUNT(*) FILTER (WHERE id_evento BETWEEN 810000001 AND 810000008) AS eventos_sinteticos,
    COUNT(*) FILTER (WHERE id_evento BETWEEN 200000000 AND 299999999) AS eventos_igp,
    COUNT(*) AS eventos_totales
FROM evento_sismico;

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

SELECT
    MIN(fecha_hora_origen) AS primer_evento_igp_utc,
    MAX(fecha_hora_origen) AS ultimo_evento_igp_utc,
    MIN(magnitud) AS magnitud_minima,
    MAX(magnitud) AS magnitud_maxima
FROM evento_sismico
WHERE id_evento BETWEEN 200000000 AND 299999999;

SELECT id_evento, fecha_hora_origen, latitud_epicentro,
       longitud_epicentro, profundidad_km, magnitud, estado_revision
FROM evento_sismico
WHERE id_evento BETWEEN 200000000 AND 299999999
ORDER BY id_evento
LIMIT 5;


\echo '=== SIMULACION COMPLEMENTARIA ==='
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM evento_sismico
        WHERE id_evento BETWEEN 200000000 AND 299999999) <> 24289
       OR (SELECT COUNT(*) FROM evento_sismico
        WHERE id_evento BETWEEN 810000001 AND 810000008) <> 8
       OR (SELECT COUNT(*) FROM estacion_sismica
        WHERE id_estacion BETWEEN 810000001 AND 810000005) <> 5
       OR (SELECT COUNT(*) FROM sensor
        WHERE id_sensor BETWEEN 810000001 AND 810000010) <> 10
       OR (SELECT COUNT(*) FROM lectura_onda
        WHERE id_lectura BETWEEN 810000001 AND 810000190) <> 190
       OR (SELECT COUNT(*) FROM deteccion
        WHERE id_evento BETWEEN 810000001 AND 810000008) <> 14
       OR (SELECT COUNT(*) FROM alerta
        WHERE id_alerta BETWEEN 810000001 AND 810000005) <> 5 THEN
        RAISE EXCEPTION 'La carga inicial o los eventos IGP no coinciden con lo esperado.';
    END IF;

    IF EXISTS (SELECT 1 FROM estacion_sismica
               WHERE id_estacion BETWEEN 820300001 AND 820300010)
       OR EXISTS (SELECT 1 FROM sensor
               WHERE id_sensor BETWEEN 820300001 AND 820300030)
       OR EXISTS (SELECT 1 FROM evento_sismico
               WHERE id_evento BETWEEN 820300001 AND 820300030)
       OR EXISTS (SELECT 1 FROM lectura_onda
               WHERE id_lectura BETWEEN 820300000001 AND 820300001000)
       OR EXISTS (SELECT 1 FROM deteccion
               WHERE id_sensor BETWEEN 820300001 AND 820300030)
       OR EXISTS (SELECT 1 FROM alerta
               WHERE id_alerta BETWEEN 820300001 AND 820300024) THEN
        RAISE EXCEPTION 'La simulacion ya contiene registros. No repetir la carga.';
    END IF;
END;
$$;

INSERT INTO estacion_sismica (
    id_estacion, codigo, nombre, latitud, longitud, altitud,
    departamento, provincia, distrito, fecha_instalacion, estado
)
SELECT
    820300001 + g,
    'SIM43-EST-' || LPAD((g + 1)::TEXT, 2, '0'),
    'Estacion simulada de prueba ' || LPAD((g + 1)::TEXT, 2, '0'),
    -5.5::NUMERIC - g * 1.1::NUMERIC,
    -78.4::NUMERIC + g * 0.21::NUMERIC,
    100::NUMERIC + g * 85::NUMERIC,
    NULL, NULL, NULL, DATE '2024-01-01', 'operativa'
FROM generate_series(0, 9) AS serie(g);

INSERT INTO sensor (
    id_sensor, numero_serie, tipo, modelo, unidad_medida,
    frecuencia_muestreo, fecha_instalacion, fecha_ultimo_mantenimiento,
    estado, id_estacion
)
SELECT
    820300001 + g,
    'SIM43-SEN-' || LPAD((g + 1)::TEXT, 2, '0'),
    'acelerometro', 'SIM-43', 'm/s2',
    CASE WHEN g % 2 = 0 THEN 50 ELSE 100 END,
    DATE '2025-01-01', NULL,
    'operativo', 820300001 + (g / 3)
FROM generate_series(0, 29) AS serie(g);

INSERT INTO evento_sismico (
    id_evento, fecha_hora_origen, latitud_epicentro,
    longitud_epicentro, profundidad_km, magnitud,
    tipo_magnitud, intensidad_maxima, referencia_geografica,
    estado_revision
)
SELECT
    820300001 + g,
    TIMESTAMP '2026-08-01 00:00:00' + g * INTERVAL '1 day',
    -8::NUMERIC - g * 0.15::NUMERIC,
    -77.5::NUMERIC + g * 0.10::NUMERIC,
    5::NUMERIC + g,
    3.4::NUMERIC + (g % 15) * 0.1::NUMERIC,
    NULL, NULL, NULL, 'simulado'
FROM generate_series(0, 29) AS serie(g);

INSERT INTO lectura_onda (
    id_lectura, id_sensor, fecha_hora, canal, valor, es_valida
)
SELECT
    820300000001::BIGINT + g,
    820300001 + (g % 30),
    TIMESTAMP '2026-08-01 00:00:00'
        + ((g / 30) % 30) * INTERVAL '1 day'
        + (g % 30) * INTERVAL '1 second'
        + (g / 900) * INTERVAL '1 hour',
    CASE g % 3 WHEN 0 THEN 'X' WHEN 1 THEN 'Y' ELSE 'Z' END,
    (((g * 37) % 401) - 200)::NUMERIC / 1000,
    (g % 30 < 3 OR g % 17 <> 0)
FROM generate_series(0, 999) AS serie(g);

INSERT INTO deteccion (
    id_sensor, id_evento, hora_deteccion, aceleracion_maxima, calidad
)
SELECT
    820300001 + s,
    820300001 + e,
    TIMESTAMP '2026-08-01 00:00:00'
        + e * INTERVAL '1 day' + s * INTERVAL '1 second',
    (e + s + 1)::NUMERIC / 100,
    CASE WHEN (e + s) % 2 = 0 THEN 'alta' ELSE 'media' END
FROM generate_series(0, 29) AS eventos(e)
CROSS JOIN generate_series(0, 2) AS sensores(s);

INSERT INTO alerta (
    id_alerta, id_evento, fecha_hora_emision,
    nivel, mensaje, magnitud_estimada, estado
)
SELECT
    820300001 + g,
    820300001 + g,
    TIMESTAMP '2026-08-01 00:00:00'
        + g * INTERVAL '1 day' + INTERVAL '90 seconds',
    CASE WHEN g % 2 = 0 THEN 'preventiva' ELSE 'informativa' END,
    'Alerta de prueba para el evento simulado ' || (820300001 + g)::TEXT,
    3.4::NUMERIC + (g % 15) * 0.1::NUMERIC,
    'simulada'
FROM generate_series(0, 23) AS serie(g);

DO $$
DECLARE
    numero_incorrecto INTEGER;
BEGIN
    IF (SELECT COUNT(*) FROM estacion_sismica
        WHERE id_estacion BETWEEN 820300001 AND 820300010) <> 10
       OR (SELECT COUNT(*) FROM sensor
        WHERE id_sensor BETWEEN 820300001 AND 820300030) <> 30
       OR (SELECT COUNT(*) FROM evento_sismico
        WHERE id_evento BETWEEN 820300001 AND 820300030) <> 30
       OR (SELECT COUNT(*) FROM lectura_onda
        WHERE id_lectura BETWEEN 820300000001 AND 820300001000) <> 1000
       OR (SELECT COUNT(*) FROM deteccion
        WHERE id_evento BETWEEN 820300001 AND 820300030) <> 90
       OR (SELECT COUNT(*) FROM alerta
        WHERE id_alerta BETWEEN 820300001 AND 820300024) <> 24 THEN
        RAISE EXCEPTION 'Los recuentos de los datos simulados no coinciden. Se cancela.';
    END IF;

    SELECT COUNT(*) INTO numero_incorrecto
    FROM deteccion d
    WHERE d.id_evento BETWEEN 820300001 AND 820300030
      AND NOT EXISTS (
          SELECT 1 FROM lectura_onda l
          WHERE l.id_sensor = d.id_sensor
            AND l.fecha_hora = d.hora_deteccion
            AND l.es_valida
      );
    IF numero_incorrecto <> 0 THEN
        RAISE EXCEPTION 'Hay % detecciones sin lectura valida vinculable.', numero_incorrecto;
    END IF;

    IF EXISTS (SELECT 1 FROM deteccion
               WHERE id_evento BETWEEN 200000000 AND 299999999)
       OR EXISTS (SELECT 1 FROM alerta
               WHERE id_evento BETWEEN 200000000 AND 299999999) THEN
        RAISE EXCEPTION 'Se encontraron detecciones o alertas de eventos IGP. Verificar antes de confirmar.';
    END IF;
    RAISE NOTICE 'OK: 1184 registros simulados generados y verificados antes de COMMIT.';
END;
$$;

SELECT 'estaciones' AS tipo, 10 AS generados
UNION ALL SELECT 'sensores', 30
UNION ALL SELECT 'eventos', 30
UNION ALL SELECT 'lecturas', 1000
UNION ALL SELECT 'detecciones', 90
UNION ALL SELECT 'alertas', 24;


\echo '=== CONTROL DE SIMULACION ==='
WITH cantidades AS (
    SELECT 'estacion_sismica'::TEXT AS tabla, COUNT(*) AS encontrados, 15::BIGINT AS esperado FROM estacion_sismica
    UNION ALL SELECT 'sensor', COUNT(*), 40 FROM sensor
    UNION ALL SELECT 'lectura_onda', COUNT(*), 1190 FROM lectura_onda
    UNION ALL SELECT 'evento_sismico', COUNT(*), 24327 FROM evento_sismico
    UNION ALL SELECT 'deteccion', COUNT(*), 104 FROM deteccion
    UNION ALL SELECT 'alerta', COUNT(*), 29 FROM alerta
)
SELECT tabla, esperado, encontrados,
       CASE WHEN encontrados = esperado THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM cantidades
ORDER BY tabla;

SELECT
    (SELECT COUNT(*) FROM evento_sismico
     WHERE id_evento BETWEEN 200000000 AND 299999999) AS eventos_igp,
    (SELECT COUNT(*) FROM evento_sismico
     WHERE id_evento BETWEEN 810000001 AND 810000008) AS eventos_simulados_iniciales,
    (SELECT COUNT(*) FROM evento_sismico
     WHERE id_evento BETWEEN 820300001 AND 820300030) AS eventos_simulados_nuevos,
    (SELECT COUNT(*) FROM deteccion
     WHERE id_evento BETWEEN 200000000 AND 299999999) AS detecciones_sobre_igp,
    (SELECT COUNT(*) FROM alerta
     WHERE id_evento BETWEEN 200000000 AND 299999999) AS alertas_sobre_igp;

SELECT 'estaciones' AS clase, COUNT(*) AS generados FROM estacion_sismica
WHERE id_estacion BETWEEN 820300001 AND 820300010
UNION ALL SELECT 'sensores', COUNT(*) FROM sensor WHERE id_sensor BETWEEN 820300001 AND 820300030
UNION ALL SELECT 'eventos', COUNT(*) FROM evento_sismico WHERE id_evento BETWEEN 820300001 AND 820300030
UNION ALL SELECT 'lecturas', COUNT(*) FROM lectura_onda WHERE id_lectura BETWEEN 820300000001 AND 820300001000
UNION ALL SELECT 'detecciones', COUNT(*) FROM deteccion WHERE id_evento BETWEEN 820300001 AND 820300030
UNION ALL SELECT 'alertas', COUNT(*) FROM alerta WHERE id_alerta BETWEEN 820300001 AND 820300024
ORDER BY clase;

SELECT 'estaciones_sin_sensor' AS control, COUNT(*) AS encontrados, 0 AS esperado
FROM estacion_sismica e
WHERE e.id_estacion BETWEEN 820300001 AND 820300010
  AND NOT EXISTS (SELECT 1 FROM sensor s WHERE s.id_estacion = e.id_estacion)
UNION ALL
SELECT 'lecturas_sin_sensor', COUNT(*), 0
FROM lectura_onda l
LEFT JOIN sensor s ON s.id_sensor = l.id_sensor
WHERE l.id_lectura BETWEEN 820300000001 AND 820300001000
  AND s.id_sensor IS NULL
UNION ALL
SELECT 'lecturas_validas_sensor_no_operativo', COUNT(*), 0
FROM lectura_onda l
JOIN sensor s ON s.id_sensor = l.id_sensor
WHERE l.id_lectura BETWEEN 820300000001 AND 820300001000
  AND l.es_valida AND s.estado <> 'operativo'
UNION ALL
SELECT 'detecciones_sin_lectura_valida', COUNT(*), 0
FROM deteccion d
WHERE d.id_evento BETWEEN 820300001 AND 820300030
  AND NOT EXISTS (
      SELECT 1 FROM lectura_onda l
      WHERE l.id_sensor = d.id_sensor
        AND l.fecha_hora = d.hora_deteccion
        AND l.es_valida
  )
UNION ALL
SELECT 'alertas_anteriores_al_evento', COUNT(*), 0
FROM alerta a
JOIN evento_sismico e ON e.id_evento = a.id_evento
WHERE a.id_alerta BETWEEN 820300001 AND 820300024
  AND a.fecha_hora_emision < e.fecha_hora_origen
ORDER BY control;

SELECT
    COUNT(*) AS nuevas_lecturas,
    COUNT(*) FILTER (WHERE es_valida) AS validas,
    COUNT(*) FILTER (WHERE NOT es_valida) AS invalidas,
    MIN(fecha_hora) AS primera_lectura,
    MAX(fecha_hora) AS ultima_lectura
FROM lectura_onda
WHERE id_lectura BETWEEN 820300000001 AND 820300001000;

SELECT
    (SELECT COUNT(*) FROM estacion_sismica)
    + (SELECT COUNT(*) FROM sensor)
    + (SELECT COUNT(*) FROM lectura_onda)
    + (SELECT COUNT(*) FROM evento_sismico)
    + (SELECT COUNT(*) FROM deteccion)
    + (SELECT COUNT(*) FROM alerta) AS registros_totales,
    25705 AS esperado;

\echo '=== RESULTADOS FINALES ==='
WITH conteos AS (
    SELECT 'estacion_sismica'::TEXT AS tabla, COUNT(*) AS obtenido, 15::BIGINT AS esperado FROM estacion_sismica
    UNION ALL SELECT 'sensor', COUNT(*), 40 FROM sensor
    UNION ALL SELECT 'lectura_onda', COUNT(*), 1190 FROM lectura_onda
    UNION ALL SELECT 'evento_sismico', COUNT(*), 24327 FROM evento_sismico
    UNION ALL SELECT 'deteccion', COUNT(*), 104 FROM deteccion
    UNION ALL SELECT 'alerta', COUNT(*), 29 FROM alerta
)
SELECT tabla, esperado, obtenido,
       CASE WHEN esperado = obtenido THEN 'OK' ELSE 'REVISAR' END AS estado
FROM conteos
ORDER BY tabla;

DO $$
DECLARE
    total BIGINT;
    oficiales BIGINT;
BEGIN
    SELECT
        (SELECT COUNT(*) FROM estacion_sismica)
        + (SELECT COUNT(*) FROM sensor)
        + (SELECT COUNT(*) FROM lectura_onda)
        + (SELECT COUNT(*) FROM evento_sismico)
        + (SELECT COUNT(*) FROM deteccion)
        + (SELECT COUNT(*) FROM alerta)
    INTO total;
    SELECT COUNT(*) INTO oficiales
    FROM evento_sismico
    WHERE id_evento BETWEEN 200000000 AND 299999999;
    IF total <> 25705 OR oficiales <> 24289 THEN
        RAISE EXCEPTION 'Recuentos incorrectos: total % (esperado 25705), IGP % (esperado 24289).', total, oficiales;
    END IF;
    RAISE NOTICE 'OK: 25705 registros, de los cuales 24289 son eventos oficiales IGP.';
END;
$$;

COMMIT;
\echo '=== ETAPA 2 FINALIZADA ==='
