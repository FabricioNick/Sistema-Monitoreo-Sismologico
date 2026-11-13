# Sistema de Monitoreo Sismológico y Alerta Temprana

Proyecto final de **Base de Datos I (CS2041)** — UTEC, 2026-2.

Implementación de una base de datos relacional en PostgreSQL para el registro y consulta de estaciones sísmicas, sensores, eventos, lecturas, detecciones y alertas. El proyecto integra datos del catálogo oficial del Instituto Geofísico del Perú (IGP) y datos operativos simulados, diferenciando su procedencia.

## Documentación y entregables

| Recurso | Contenido |
|---|---|
| [Informe final (PDF)](informe/Proyecto_Final.pdf) | Modelos, implementación, consultas, metodología, resultados, análisis y anexos |
| [SQL](sql/) | Scripts de estructura, carga, vistas, procedimientos, triggers, consultas y experimentación |
| [Resultados CSV](sql/resultados/) | Mediciones experimentales, consolidado de las veinte comparaciones y exportación del MVP |
| [MVP web](MVP_Web_Sismologico/) | Aplicación local de solo lectura que ejecuta las cinco consultas SQL |
| [Herramientas](herramientas/) | Utilidades para exportación, diagnóstico y restauración de respaldos |
| [Respaldos experimentales](https://github.com/FabricioNick/Sistema-Monitoreo-Sismologico/releases/tag/v1.0.0) | Cuatro archivos `.dump` correspondientes a las cuatro escalas |
| [Demostración audiovisual](https://drive.google.com/drive/folders/1gb3Di7rx0eWwd05cC3xbw3DJxhjgS2t4?usp=sharing) | Carpeta de Drive destinada a la comparación experimental sobre un millón de registros |

Las evidencias gráficas, tablas de resultados y planes de ejecución están en el informe PDF. En `sql/resultados/` se conservan el resumen histórico `59_resumen_global_5_6.csv` (serie principal), `C5_resultados_mvp.csv` (exportación del prototipo) y los CSV `06_C*.csv` (segunda ejecución experimental). Las series de medición son distintas y no se combinan.

## Experimento de optimización

Se estudiaron cinco consultas no triviales (C1–C5) sobre cuatro escalas: **1 000, 10 000, 100 000 y 1 000 000 de registros**, comparando los escenarios sin y con índices secundarios.

- **C1:** actividad sísmica anual.
- **C2:** eventos en ventanas geográficas.
- **C3:** calidad de las lecturas por estación.
- **C4:** primera detección y primera alerta por evento.
- **C5:** sensores con lecturas y sin detecciones.

La evaluación contempla índices seleccionados por consulta, planes de ejecución y mediciones repetidas. El informe diferencia las mejoras observadas de los escenarios en los que los índices no se utilizaron o no redujeron el tiempo de ejecución.

## Implementación SQL

Los archivos de entrada se encuentran en [`sql/`](sql/):

| Archivo | Propósito |
|---|---|
| `01_estructura.sql` | Tablas y restricciones |
| `02_datos.sql` | Carga de información y verificaciones |
| `03_logica_consultas.sql` | Vistas, procedimientos, triggers y consultas |
| `04_bases_experimentales.sql` | Escalas experimentales |
| `05_planes_indices.sql` | Planes de ejecución e índices candidatos |
| `06_mediciones.sql` | Medición de rendimiento |
| `07_demostracion_video.sql` | Comparación demostrativa de C1–C5 en la escala mayor |

Los integradores requieren PostgreSQL y `psql`; algunos presuponen datos e índices previamente preparados. No son scripts de inicialización idempotentes para ejecutar indiscriminadamente en una base ya poblada.

## Aplicación web

El [MVP web](MVP_Web_Sismologico/README.md) usa Node.js y `pg` para ejecutar C1–C5 sobre PostgreSQL en modo de solo lectura. Incluye resultados tabulares, filtros y exportación CSV. La configuración privada de conexión se mantiene fuera del control de versiones.

## Fuentes de datos y alcance

- [Catálogo sísmico del IGP](https://censis.igp.gob.pe/repositorio/datos-sismicos)
- [Documentación de PostgreSQL](https://www.postgresql.org/docs/)

Los datos sintéticos no deben interpretarse como observaciones instrumentales reales. Las conclusiones de rendimiento se limitan a los datos, al equipo y al protocolo de experimentación documentados en el informe.

## Evidencia de reproducibilidad

- [CSV historicos de mediciones](sql/resultados/historicos/): 21 archivos originales que respaldan las 20 comparaciones de la serie principal.
- [Verificacion de implementacion](herramientas/Verificacion_Implementacion.sql) y [salida de PostgreSQL](sql/resultados/Salida_Verificacion_Implementacion.txt): recuentos, objetos e integridad comprobados.
- Las mediciones `06_C*.csv` corresponden a una segunda serie experimental independiente.
