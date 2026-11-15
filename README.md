# Sistema de Monitoreo Sismológico y Alerta Temprana

**Proyecto final — CS2041 Base de Datos I · UTEC · 2026-2**

Diseño e implementación de una base de datos relacional en **PostgreSQL 18** para estaciones sísmicas, sensores, lecturas, eventos, detecciones y alertas. El proyecto utiliza el catálogo sísmico del **Instituto Geofísico del Perú (IGP)** y datos operativos simulados, cuya procedencia se distingue en las consultas y resultados.

## Entregables

| Recurso | Acceso |
|---|---|
| Informe del proyecto | [PDF](informe/Proyecto_Final.pdf) |
| Scripts SQL definitivos | [Siete integradores](sql/) |
| Mediciones experimentales | [25 archivos CSV](resultados/mediciones/) |
| Resumen de resultados | [Comparación de las 25 pruebas](resultados/resumen_25_comparaciones.csv) |
| Planes de ejecución | [Planes JSON](resultados/planes_json/) |
| Registros de ejecución | [Evidencias de implementación y experimentación](resultados/registros_ejecucion/) |
| Herramientas | [Scripts de verificación y medición](herramientas/) |
| Bases experimentales | [Cuatro respaldos `.dump` — Release v1.0.0](https://github.com/FabricioNick/Sistema-Monitoreo-Sismologico/releases/tag/v1.0.0) |
| MVP web | [Observatorio Sismológico — acceso temporal](https://routing-writing-deprive.ngrok-free.dev) |
| Videos de experimentación | [Carpeta de Google Drive](https://drive.google.com/drive/folders/1gb3Di7rx0eWwd05cC3xbw3DJxhjgS2t4?usp=sharing) |

## Consultas y experimentación

| Consulta | Objetivo |
|---|---|
| **C1** | Actividad sísmica anual del catálogo IGP |
| **C2** | Eventos del IGP en ventanas geográficas alrededor de estaciones |
| **C3** | Calidad de lecturas por estación |
| **C4** | Primera detección y primera alerta por evento simulado |
| **C5** | Sensores con lecturas y sin detecciones en el período de estudio |

Se comparan cinco escalas de **100, 1 000, 10 000, 100 000 y 1 000 000 registros**; las cuatro últimas son las obligatorias y la primera es adicional. Para cada consulta se contrastan ejecuciones **sin y con índices secundarios candidatos**.

El conjunto definitivo incluye **25 comparaciones**, **250 mediciones útiles** y **100 calentamientos**, documentados en sus respectivos CSV, planes y registros. La selección efectiva de índices depende del planificador de PostgreSQL.

## Integradores SQL

1. [`01_estructura.sql`](sql/01_estructura.sql) — modelo relacional, claves y restricciones.
2. [`02_datos.sql`](sql/02_datos.sql) — carga inicial, catálogo IGP y datos simulados.
3. [`03_logica_consultas.sql`](sql/03_logica_consultas.sql) — vistas, procedimientos, triggers y consultas C1–C5.
4. [`04_bases_experimentales.sql`](sql/04_bases_experimentales.sql) — escalas experimentales.
5. [`05_planes_indices.sql`](sql/05_planes_indices.sql) — índices candidatos y planes.
6. [`06_mediciones.sql`](sql/06_mediciones.sql) — mediciones y verificaciones.
7. [`07_verificacion_comparativa.sql`](sql/07_verificacion_comparativa.sql) — consultas e índices para comparar manualmente los planes en pgAdmin.

## Catálogo de datos y respaldos

- **Archivo empleado:** [`igp_catalogo.csv`](sql/datos/igp_catalogo.csv), con 24 289 registros del catálogo IGP.
- **Fuente:** [Catálogo Sísmico desde 1960 al 2025 — IGP, Plataforma Nacional de Datos Abiertos](https://www.datosabiertos.gob.pe/dataset/catalogo-sismico/resource/f9629081-0721-4101-a2c2-d0622e046f8b).
- **Respaldos:** [`bd_sismologico_exp_1000.dump`, `bd_sismologico_exp_10000.dump`, `bd_sismologico_exp_100000.dump` y `bd_sismologico_exp_1000000.dump`](https://github.com/FabricioNick/Sistema-Monitoreo-Sismologico/releases/tag/v1.0.0), publicados en Releases.

## MVP web y videos

El **MVP web** permite ejecutar C1–C5 en modo de solo lectura, consultar resultados en tablas y gráficos, y exportar CSV. Se ejecuta localmente con **Node.js y PostgreSQL**, con acceso mediante **ngrok** durante la exposición. El código de la aplicación permanece fuera de este repositorio, de acuerdo con el alcance de la demostración académica.

**Enlace temporal:** [Abrir Observatorio Sismológico](https://routing-writing-deprive.ngrok-free.dev). Solo funciona mientras el servidor local y el túnel estén activos.

**Evidencia audiovisual:** [Carpeta de Google Drive](https://drive.google.com/drive/folders/1gb3Di7rx0eWwd05cC3xbw3DJxhjgS2t4?usp=sharing). Se contemplan cinco videos independientes, uno por consulta C1–C5, con ejecución manual en **pgAdmin 4** y comparación de planes **sin y con índices candidatos** sobre la base de **1 000 000 registros**.

## Alcance

Las detecciones y alertas simuladas no se atribuyen al catálogo oficial del IGP. Las conclusiones de rendimiento corresponden a las escalas y condiciones medidas; el comportamiento por encima de un millón de registros se aborda como análisis teórico.
