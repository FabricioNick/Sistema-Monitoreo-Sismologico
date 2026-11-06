# MVP web — Monitoreo Sismológico y Alerta Temprana

Aplicación web para el extra de **+2 puntos** de CS2041 (sujeto a la evaluación del profesor). Conecta mediante Node.js y el controlador `pg` a la base PostgreSQL existente y ejecuta las **cinco consultas originales** del archivo `15_consultas_5_1.sql` sin modificar sus predicados.

## Requisitos

- Windows 11 y Node.js 22 o superior (tu instalación Node 24 es compatible).
- PostgreSQL 18 encendido y disponible en `127.0.0.1:5432`.
- La base `bd_sismologico_exp_1000000` o `bd_sismologico` con el esquema `monitoreo_sismologico` y sus seis tablas.
- Acceso local a npm para instalar una sola dependencia: `pg`.

## Instalación en Windows — CMD

1. Extrae el ZIP en tu carpeta `Proyecto_Final` (quedará `Proyecto_Final\MVP_Web_Sismologico`).
2. Abre **CMD** dentro de `MVP_Web_Sismologico`.
3. Ejecuta:

```cmd
copy .env.example .env
notepad .env
npm install
npm start
```

4. En `.env` reemplaza **solamente** `PGPASSWORD=REEMPLAZAR_CON_TU_CONTRASENA` por la contraseña local. No compartas ese archivo ni lo subas a GitHub. Guarda y cierra el Bloc de notas antes de `npm start`.
5. Abre `http://127.0.0.1:3000` en el navegador. Usa el selector lateral para ejecutar C1, C2, C3, C4 o C5.
6. Verifica el panel, la tabla, la búsqueda local, los encabezados ordenables y el botón para exportar CSV.

Para verificar automáticamente los resultados, **mantén `npm start` abierto** y ejecuta en una segunda ventana CMD:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "63_verificar_mvp_web.ps1"
```

El verificador comprueba que existan un millón de filas, 24 289 eventos IGP y que C1–C5 devuelvan el número de filas esperado. Si tu archivo `.env` apunta a una base diferente, el verificador avisará en lugar de aprobarla incorrectamente.

Puedes ejecutar las pruebas unitarias sin PostgreSQL mediante `npm test` (las respuestas del servidor se simulan únicamente en las pruebas automatizadas).

No ejecutes los archivos de optimización 21–58 para usar el MVP. El MVP consulta el estado real de la base ya creada. Si la conexión falla, comprueba `.env`, el servicio de PostgreSQL y el nombre de la base.

## API

- `GET /api/health`: confirma conexión y versión de PostgreSQL.
- `GET /api/overview`: suma filas de las seis tablas y cuenta eventos IGP/simulados por identificador.
- `GET /api/queries`: nombres y descripciones de las cinco consultas.
- `GET /api/queries/C1` ... `C5`: **SQL original**, resultados y tiempo total del servicio.

## Alcance y seguridad

- `PGPASSWORD` reside en el servidor local; **no** se envía al navegador.
- No se aceptan instrucciones SQL libres, nombres de tablas arbitrarios ni parámetros del usuario interpolados en SQL.
- Cada acceso a la base ocurre en una transacción `BEGIN READ ONLY` y `ROLLBACK` con `statement_timeout=30s`.
- Acceso HTTP limitado a `127.0.0.1`, para una demostración en el mismo equipo. No incluye inicio de sesión ni despliegue público.
- El filtrado y ordenamiento de tablas en pantalla ocurre en el navegador y no modifica PostgreSQL.
- `duration_ms` es el tiempo total medido en el servidor para el acceso a la consulta, **no es equivalente** al tiempo `Execution Time` de `EXPLAIN ANALYZE` ni reemplaza las mediciones del informe.

## Verificación sugerida para evaluación

1. Mostrar conexión exitosa y el total de **1 000 000** de filas.
2. Ejecutar las cinco consultas desde la barra lateral y comprobar que devuelven resultados.
3. Filtrar una tabla y exportar CSV.
4. Explicar la arquitectura navegador → Node HTTP/`pg` → PostgreSQL 18.
5. Mostrar que son consultas originales del proyecto y que el modo es solo lectura.

**Estado:** código generado y comprobado estáticamente. La ejecución contra tu PostgreSQL local está **pendiente de tus pruebas**; no presentar capturas o conexiones ficticias como evidencia.
