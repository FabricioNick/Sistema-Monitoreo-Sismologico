# Sistema de Monitoreo Sismologico — guia temporal de estructura

**Este documento es provisional.** El README final se elaborara cuando el
repositorio GitHub, las figuras, los cuatro assets de respaldo y el enlace de
video esten listos.

## Entradas por etapa (SQL)

| Entrada | Uso | Efecto |
|---|---|---|
| `sql/01_estructura.sql` | Crea tablas y prueba restricciones | Modifica base principal nueva |
| `sql/02_datos.sql` | Carga inicial, IGP y simulacion | Inserta datos, UNA vez |
| `sql/03_logica_consultas.sql` | Vistas, procedimientos, triggers y consultas | Crea objetos y prueba funcionalidades |
| `sql/04_bases_experimentales.sql` | Genera 4 bases independientes | CREA/LLENA cuatro bases, UNA vez |
| `sql/05_planes_indices.sql` | Prueba planes e indices C1-C5 | Cambia indices de la base de 1M |
| `sql/06_mediciones.sql` | 20 comparaciones / 5 consultas | Cambia indices y exporta CSV, UNA vez |
| `sql/07_demostracion_video.sql` | Planes del millon para video | Transaccion con ROLLBACK |

Los scripts detallados se encuentran bajo `sql/modulos/` y conservan los
nombres numerados para trazabilidad. Los grupos ejecutan esos modulos mediante
`\ir`; no se ha concatenado SQL que contiene funciones, bloques COPY, pruebas
transaccionales y comandos psql, lo cual podria romper el orden y el estado.

**Seguridad:** las etapas 01-06 no son para re-ejecutarse sobre las bases con
las que ya se midio. Utilizar COPIAS NUEVAS o revisar manualmente las precondiciones.
No emplear en produccion.

**No se debe ejecutar todo sobre las bases de la computadora actual:** ya
contienen las 20 pruebas verificadas y los indices de C5. Este repositorio es
la version organizada para entrega y eventual reproduccion en un entorno limpio.

## Reproducir en un entorno limpio (orientativo)

- Requiere PostgreSQL 18, `psql` y el CSV IGP original en
  `sql/datos/igp_catalogo.csv`. El archivo no se incluye; se descarga desde la
  fuente oficial indicada en `sql/datos/ORIGEN_IGP.txt`.
- Abrir CMD, cambiar el directorio de trabajo a la carpeta `sql` del repositorio.
  Las instrucciones `\copy` operan sobre rutas relativas a ese directorio.
- Crear una base `bd_sismologico` limpia antes de la etapa 01.
- Ejecutar cada entrada por separado y en el orden indicado. En la etapa 06
  todos los indices obligatorios PK/UNIQUE permanecen intactos.

Ejemplo para una base nueva (NO usar sobre la que ya tienes):

```bat
cd /d "RUTA_DE_TU_REPOSITORIO\sql"
psql -h localhost -U postgres -d postgres -c "CREATE DATABASE bd_sismologico;"
psql -X -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -f 01_estructura.sql
psql -X -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -f 02_datos.sql
psql -X -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -f 03_logica_consultas.sql
```

Las otras etapas siguen el mismo formato `psql -f`, con los cambios de base
realizados por el propio script integrador.

## Carpetas

- `sql/modulos/`: fuentes SQL verificadas, clasificadas por funcion.
- `sql/experimentacion/`: un coordinador por consulta C1-C5, cuatro escalas cada uno.
- `sql/resultados/`: CSV producidos por las mediciones (pendientes de copiar
  desde el equipo original).
- `sql/Dumps/`: carpeta LOCAL; los `.dump` no se versionan en Git.
- `herramientas/`: exportacion, informacion del equipo y restauracion PowerShell.
- `MVP_Web_Sismologico/`: aplicacion web Node.js; ejecutar `npm install`, `npm start`
  y `npm test` para validar la API (en la carpeta del MVP).
- `informe/`: main.tex, PDF y graficos necesarios para compilacion.
- `evidencias/`: resumen de experimentos y anexos/figuras a completar.

## Pendientes para cerrar el repositorio

1. Copiar los CSV experimentales reales 38-58 desde la computadora original.
2. Subir los cuatro `.dump` como assets de una GitHub Release (no a Git normal).
3. Anadir al informe capturas de consultas, graficos y planes de ejecucion.
4. Grabar video y anadir SOLO su enlace de Google Drive.
5. Terminar el README definitivo y enlaces.

**Validacion:** el paquete se construyo a partir de los archivos existentes y
se comprobaron referencias internas y equivalencia del SQL del MVP. Los siete
integradores son nuevos y TODAVIA NO se han ejecutado en una instancia
PostgreSQL; no afirmar que el flujo integrado esta verificado en produccion.
