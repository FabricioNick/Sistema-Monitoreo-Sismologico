# Sistema de Monitoreo Sismológico y Alerta Temprana

**Proyecto final — CS2041 Base de Datos I · UTEC · 2026-2**

Base de datos relacional desarrollada en **PostgreSQL 18** para administrar estaciones sísmicas, sensores, lecturas, eventos, detecciones y alertas. Integra información del catálogo del **Instituto Geofísico del Perú (IGP)** con datos operativos simulados.

## Diseño e implementación

El modelo Entidad-Relación comprende cinco entidades principales y la relación muchos a muchos **DETECTA**, transformadas en seis tablas relacionales. La implementación incluye claves y restricciones de integridad, cinco vistas, seis procedimientos almacenados y nueve triggers.

## Consultas evaluadas

| Consulta | Objetivo |
|---|---|
| **C1** | Actividad sísmica anual del catálogo IGP |
| **C2** | Eventos del IGP en ventanas geográficas alrededor de estaciones |
| **C3** | Calidad de lecturas por estación |
| **C4** | Primera detección y primera alerta por evento simulado |
| **C5** | Sensores con lecturas y sin detecciones en el período de estudio |

## Experimentación

Se analizaron cinco volúmenes de datos: **100, 1 000, 10 000, 100 000 y 1 000 000 registros**, comparando cada consulta sin y con índices secundarios candidatos.

El experimento comprende **25 comparaciones**, **250 mediciones útiles** y **100 calentamientos**. Se observaron 20 mejoras, cuatro incrementos del tiempo y un caso sin cambio; PostgreSQL utilizó índices candidatos en 14 de las 25 comparaciones. En la escala de un millón de registros, las cinco consultas mostraron una reducción del tiempo medio.

Las mediciones, los planes de ejecución y los registros de las pruebas se conservan como evidencia reproducible.

## Archivos SQL

| Archivo | Contenido |
|---|---|
| [`01_estructura.sql`](sql/01_estructura.sql) | Esquema relacional y restricciones |
| [`02_datos.sql`](sql/02_datos.sql) | Carga del catálogo IGP y datos simulados |
| [`03_logica_consultas.sql`](sql/03_logica_consultas.sql) | Vistas, procedimientos, triggers y consultas C1–C5 |
| [`04_bases_experimentales.sql`](sql/04_bases_experimentales.sql) | Preparación de las escalas experimentales |
| [`05_planes_indices.sql`](sql/05_planes_indices.sql) | Índices candidatos y análisis de planes |
| [`06_mediciones.sql`](sql/06_mediciones.sql) | Medición de tiempos y verificaciones |
| [`07_verificacion_comparativa.sql`](sql/07_verificacion_comparativa.sql) | Verificación manual de las consultas sin y con índices |

## Informe, resultados y recursos

| Recurso | Acceso |
|---|---|
| Informe final | [Proyecto_Final.pdf](informe/Proyecto_Final.pdf) |
| Mediciones | [25 archivos CSV](resultados/mediciones/) |
| Resumen de resultados | [25 comparaciones](resultados/resumen_25_comparaciones.csv) |
| Planes de ejecución | [Archivos JSON](resultados/planes_json/) |
| Registros de ejecución | [Evidencias de implementación y experimentación](resultados/registros_ejecucion/) |
| Herramientas auxiliares | [Scripts de verificación y medición](herramientas/) |
| Respaldos experimentales | [Cuatro archivos `.dump` — v1.0.0](https://github.com/FabricioNick/Sistema-Monitoreo-Sismologico/releases/tag/v1.0.0) |
| MVP web | [Observatorio Sismológico](https://routing-writing-deprive.ngrok-free.dev/) |
| Videos de experimentación | [Carpeta de Google Drive](https://drive.google.com/drive/folders/1gb3Di7rx0eWwd05cC3xbw3DJxhjgS2t4?usp=sharing) |

## Datos

Se incorporaron **24 289 eventos sísmicos** del [Catálogo Sísmico desde 1960 al 2025 del IGP](https://www.datosabiertos.gob.pe/dataset/catalogo-sismico/resource/f9629081-0721-4101-a2c2-d0622e046f8b), disponibles en [`sql/datos/igp_catalogo.csv`](sql/datos/igp_catalogo.csv). Las estaciones, sensores, lecturas, detecciones y alertas de prueba proceden de simulación; no se atribuyen a la fuente oficial.

Los resultados de rendimiento corresponden a las condiciones y volúmenes medidos. El comportamiento por encima de un millón de registros se analiza teóricamente en el informe.
