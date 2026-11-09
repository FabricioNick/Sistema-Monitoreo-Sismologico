# Sistema de Monitoreo Sismológico y Alerta Temprana

**CS2041 · Base de Datos I · UTEC · 2026-2**

Proyecto de base de datos relacional en PostgreSQL 18 para estaciones sísmicas, sensores, eventos, lecturas, detecciones y alertas. Combina un catálogo de 24 289 eventos oficiales del IGP con información operativa sintética, identificando su procedencia.

## Contenido

- `informe/`: informe LaTeX, PDF y figuras de evidencia.
- `sql/`: siete integradores y módulos SQL de estructura, carga, lógica, experimentación y demostración.
- `MVP_Web_Sismologico/`: prototipo web Node.js con acceso de solo lectura.
- `evidencias/`: resultados, planes y material de verificación.
- [Respaldos experimentales (v1.0.0)](https://github.com/FabricioNick/Sistema-Monitoreo-Sismologico/releases/tag/v1.0.0): cuatro archivos `.dump` de 1 000, 10 000, 100 000 y 1 000 000 registros.
- [Evidencia audiovisual — Google Drive](https://drive.google.com/drive/folders/1gb3Di7rx0eWwd05cC3xbw3DJxhjgS2t4?usp=sharing): comparación de consultas en la escala de un millón de registros con y sin índices.

## Integradores SQL

| Integrador | Función |
|---|---|
| `01_estructura.sql` | Esquema, tablas y restricciones |
| `02_datos.sql` | Carga del IGP y datos de simulación |
| `03_logica_consultas.sql` | Vistas, procedimientos, triggers y consultas C1–C5 |
| `04_bases_experimentales.sql` | Cuatro escalas de datos |
| `05_planes_indices.sql` | Análisis de planes e índices |
| `06_mediciones.sql` | Mediciones experimentales y controles de resultados |
| `07_demostracion_video.sql` | Ejecución ilustrativa en la escala de un millón |

Los integradores se utilizan con `psql` y tienen condiciones de ejecución específicas. Su orden numérico no significa que deban aplicarse en una base ya poblada sin revisar el estado de los datos y los índices. El integrador `07` utiliza el estado experimental C5 de la base de un millón y revierte los cambios temporales de índices con `ROLLBACK`.

## Consultas y resultados

Las cinco consultas evalúan actividad sísmica anual (C1), ventanas geográficas (C2), calidad de lecturas (C3), detecciones y alertas (C4), y sensores con lecturas sin detecciones (C5). Las comparaciones se realizaron en cuatro escalas, con dos calentamientos y cinco mediciones por escenario. Los índices no mejoraron todas las consultas; el informe documenta tanto los beneficios como los resultados desfavorables.

## Prototipo web

El MVP emplea Node.js, PostgreSQL y el controlador `pg`. El archivo `.env` se configura localmente y no debe publicarse. La interfaz permite ejecutar C1–C5 en modo de solo lectura, visualizar resultados y exportar CSV. Consulte las instrucciones de `MVP_Web_Sismologico/README.md` y el apartado correspondiente del informe.

## Fuentes

- [Catálogo de datos sísmicos del IGP](https://censis.igp.gob.pe/repositorio/datos-sismicos)
- [Documentación oficial de PostgreSQL](https://www.postgresql.org/docs/)

Los registros sintéticos de prueba no representan observaciones instrumentales reales. Los tiempos medidos pertenecen al entorno y al protocolo descritos en el informe.
