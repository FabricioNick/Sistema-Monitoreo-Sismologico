# Sistema de Monitoreo Sismológico y Alerta Temprana

**Proyecto final — CS2041 Base de Datos I · UTEC · 2026-2**

Proyecto académico de diseño, implementación y optimización de una base de datos relacional en **PostgreSQL 18** para estaciones sísmicas, sensores, eventos, lecturas, detecciones y alertas. Integra **24 289 eventos del catálogo del Instituto Geofísico del Perú (IGP)** y registros operativos sintéticos, cuya procedencia se distingue en el modelo y las consultas.

## Entregables

| Recurso | Contenido |
|---|---|
| [Informe final (PDF)](informe/Proyecto_Final.pdf) | Requisitos, modelos, implementación, consultas, experimentación y conclusiones |
| [SQL definitivos](sql/) | Siete integradores de implementación y experimentación |
| [Resultados experimentales](resultados/mediciones/) | 25 archivos CSV: cinco consultas por cinco escalas |
| [Resumen de las 25 comparaciones](resultados/resumen_25_comparaciones.csv) | Métricas consolidadas de rendimiento |
| [Planes de ejecución](resultados/planes_json/) | Planes JSON con y sin índices secundarios candidatos |
| [Registros de ejecución](resultados/registros_ejecucion/) | Salidas técnicas de implementación, planes, mediciones y demostración |
| [Herramientas](herramientas/) | Scripts de medición, respaldo y verificación |
| [Respaldos PostgreSQL — Release v1.0.0](https://github.com/FabricioNick/Sistema-Monitoreo-Sismologico/releases/tag/v1.0.0) | Cuatro archivos `.dump` de las escalas exigidas |
| [Videos de experimentación — Google Drive](https://drive.google.com/drive/folders/1gb3Di7rx0eWwd05cC3xbw3DJxhjgS2t4?usp=sharing) | Carpeta destinada a las grabaciones; comprobar disponibilidad después de su publicación |

## Consultas y experimentación

Se estudian cinco consultas SQL intermedias:

| Consulta | Objetivo |
|---|---|
| **C1** | Actividad sísmica anual registrada por el IGP |
| **C2** | Eventos del IGP en ventanas geográficas alrededor de estaciones |
| **C3** | Calidad de lecturas válidas e inválidas por estación |
| **C4** | Primera detección y primera alerta asociadas a eventos simulados |
| **C5** | Sensores con lecturas, pero sin detecciones en el periodo analizado |

Se trabajó con **cinco escalas** de 100, 1 000, 10 000, 100 000 y 1 000 000 de registros totales. Las cuatro últimas corresponden a las escalas solicitadas; la de 100 registros es adicional.

Para cada consulta y escala se compararon escenarios **sin índices secundarios candidatos** y **con índices secundarios candidatos disponibles**. Los índices de integridad, como los asociados a claves primarias y restricciones `UNIQUE`, se mantienen. La disponibilidad de un índice no implica que el planificador PostgreSQL lo utilice.

El experimento definitivo contiene **25 comparaciones, 250 mediciones útiles y 100 calentamientos**, documentados en los CSV y registros técnicos. Los tiempos de consulta evaluados en el informe no deben confundirse con los tiempos HTTP de una aplicación web.

## Archivos SQL

Los integradores completos están disponibles directamente en este repositorio:

1. [`01_estructura.sql`](sql/01_estructura.sql) — tablas y restricciones.
2. [`02_datos.sql`](sql/02_datos.sql) — carga inicial e incorporación del catálogo IGP.
3. [`03_logica_consultas.sql`](sql/03_logica_consultas.sql) — vistas, procedimientos, triggers y consultas C1–C5.
4. [`04_bases_experimentales.sql`](sql/04_bases_experimentales.sql) — preparación de las escalas de prueba.
5. [`05_planes_indices.sql`](sql/05_planes_indices.sql) — índices candidatos y planes de ejecución.
6. [`06_mediciones.sql`](sql/06_mediciones.sql) — calentamientos, mediciones y validaciones.
7. [`07_demostracion_video.sql`](sql/07_demostracion_video.sql) — ejecución demostrativa para la escala mayor.

Los scripts tienen prerrequisitos y deben ejecutarse sobre las bases correspondientes. **No se deben ejecutar indiscriminadamente sobre una base ya poblada.** El conjunto de mediciones y sus planes está disponible para consulta sin repetir el experimento.

El archivo [`sql/datos/igp_catalogo.csv`](sql/datos/igp_catalogo.csv) contiene los datos del catálogo IGP utilizados en la carga. Fuente: [repositorio de datos sísmicos del IGP](https://censis.igp.gob.pe/repositorio/datos-sismicos).

## MVP web — demostración temporal

Se desarrolló un **MVP web responsive** con Node.js y PostgreSQL que permite seleccionar y ejecutar las cinco consultas intermedias, visualizar tablas y gráficos, y exportar resultados a CSV. Se utiliza **localmente en la laptop de exposición**, con acceso externo mediante un túnel HTTPS de ngrok.

**Enlace de demostración:** [Observatorio Sismológico](https://routing-writing-deprive.ngrok-free.dev)

Este enlace **solo estará disponible cuando la laptop, PostgreSQL, el servidor Node.js y ngrok estén encendidos**, principalmente durante la exposición. El código del MVP se mantiene fuera de este repositorio, conforme al alcance de la demostración académica. La aplicación ejecuta consultas de solo lectura y no constituye un sistema operativo de alerta sísmica en producción.

## Respaldos y reproducibilidad

Los cuatro archivos PostgreSQL `.dump` están publicados **únicamente como adjuntos de [GitHub Releases v1.0.0](https://github.com/FabricioNick/Sistema-Monitoreo-Sismologico/releases/tag/v1.0.0)**, no duplicados en el historial de Git:

- `bd_sismologico_exp_1000.dump`
- `bd_sismologico_exp_10000.dump`
- `bd_sismologico_exp_100000.dump`
- `bd_sismologico_exp_1000000.dump`

Los respaldos se pueden inspeccionar mediante `pg_restore --list`; una restauración de prueba independiente constituye una comprobación adicional de integridad. El repositorio conserva los SQL, resultados experimentales y herramientas para facilitar la revisión del proyecto.

## Alcance

Los eventos oficiales proceden del IGP; los datos operativos simulados no representan detecciones ni alertas instrumentales reales. Las conclusiones de rendimiento corresponden a las escalas, al equipo y al protocolo de medición documentados en el informe. El estudio de escalas superiores al millón se presenta como discusión teórica, no como medición adicional.
