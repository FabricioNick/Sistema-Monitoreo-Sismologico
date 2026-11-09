# MVP web — Monitoreo Sismológico

Aplicación local de consulta para el proyecto **CS2041 — Base de Datos I**. El servidor utiliza Node.js y el controlador `pg` para conectar con PostgreSQL y ejecutar las cinco consultas C1–C5 en modo de solo lectura.

## Requisitos

- Node.js 22 o superior y npm.
- PostgreSQL 18 con la base experimental y el esquema `monitoreo_sismologico` ya preparados.
- Configuración local de conexión mediante un archivo `.env` no versionado.

## Instalación

Desde la carpeta `MVP_Web_Sismologico` del repositorio, ejecutar:

```cmd
copy .env.example .env
notepad .env
npm ci
npm start
```

En `.env`, configurar la conexión a PostgreSQL, especialmente `PGPASSWORD` y `PGDATABASE`, con los valores del entorno local. **No publicar el archivo `.env` ni las credenciales.**

Abrir `http://127.0.0.1:3000` en el navegador. En Windows también puede utilizarse `INICIAR_MVP.cmd` si la instalación y la conexión ya están configuradas.

## Funcionalidades

- Pantalla de bienvenida y panel de monitoreo.
- Resumen de registros consultado directamente desde PostgreSQL.
- Ejecución de las consultas C1, C2, C3, C4 y C5.
- Resultados tabulares, búsqueda, ordenamiento y exportación CSV.
- Visualizaciones informativas y diseño adaptable a diferentes pantallas.

La animación de la señal sísmica es **decorativa**, no una transmisión instrumental en tiempo real.

## API

| Endpoint | Función |
|---|---|
| `GET /api/health` | Estado de la conexión |
| `GET /api/overview` | Recuentos generales |
| `GET /api/queries` | Catálogo de consultas |
| `GET /api/queries/C1` a `C5` | Ejecución de las cinco consultas originales |

La implementación SQL de referencia se conserva en [`SQL_ORIGINAL_15_consultas_5_1.sql`](SQL_ORIGINAL_15_consultas_5_1.sql) y en los integradores de [`../sql/`](../sql/).

## Pruebas

Para ejecutar las pruebas automatizadas del servidor:

```cmd
npm test
```

Para comprobar la conexión y las cinco consultas sobre una base experimental de un millón de registros, iniciar el servidor y ejecutar en otra consola:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "63_verificar_mvp_web.ps1"
```

Esta segunda comprobación está diseñada específicamente para la base experimental de un millón de registros y valida sus recuentos esperados; no es una prueba genérica para todas las bases.

## Seguridad y alcance

La contraseña permanece en el servidor local. Las operaciones de consulta utilizan transacciones de solo lectura; la interfaz no admite SQL arbitrario enviado por el navegador. La aplicación se ejecuta localmente y no constituye un servicio público de alerta temprana.

Los tiempos HTTP del MVP no son directamente comparables con `Execution Time` de `EXPLAIN ANALYZE` utilizado en el informe experimental.
