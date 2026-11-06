# Proyecto Final - Seccion 5.2. Ejecutar SOLAMENTE despues de verificar 4 bases.
# Genera cuatro copias integrales, una por base experimental PostgreSQL.
$ErrorActionPreference = 'Stop'
$runtime = 'D:\Aplicaciones\PostgreSQL\18\pgAdmin 4\runtime'
$bin = 'D:\Aplicaciones\PostgreSQL\18\bin'
$dumpTool = Join-Path $bin 'pg_dump.exe'
if (-not (Test-Path $dumpTool)) { $dumpTool = Join-Path $runtime 'pg_dump.exe' }
if (-not (Test-Path $dumpTool)) { throw 'No se encontro pg_dump.exe en las rutas esperadas.' }
$psqlTool = Join-Path $bin 'psql.exe'
if (-not (Test-Path $psqlTool)) { $psqlTool = Join-Path $runtime 'psql.exe' }
if (-not (Test-Path $psqlTool)) { throw 'No se encontro psql.exe en las rutas esperadas.' }
$destino = Join-Path (Split-Path $PSScriptRoot -Parent) 'sql\Dumps'
New-Item -ItemType Directory -Force -Path $destino | Out-Null

foreach ($n in @(1000, 10000, 100000, 1000000)) {
  $db = "bd_sismologico_exp_$n"
  $query = "SELECT (SELECT count(*) FROM monitoreo_sismologico.estacion_sismica)+(SELECT count(*) FROM monitoreo_sismologico.sensor)+(SELECT count(*) FROM monitoreo_sismologico.evento_sismico)+(SELECT count(*) FROM monitoreo_sismologico.lectura_onda)+(SELECT count(*) FROM monitoreo_sismologico.deteccion)+(SELECT count(*) FROM monitoreo_sismologico.alerta);"
  $enBase = & $psqlTool -X -q -t -A -v ON_ERROR_STOP=1 -h localhost -p 5432 -U postgres -d $db -c $query
  if ($LASTEXITCODE -ne 0) { throw "No pudo verificarse $db. No exportar." }
  if (($enBase | Select-Object -Last 1).Trim() -ne "$n") { throw "El recuento de $db no coincide con $n. No exportar." }
  $archivo = Join-Path $destino "$db.dump"
  & $dumpTool -h localhost -p 5432 -U postgres -d $db -Fc -f $archivo
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $archivo)) { throw "Fallo al exportar $db" }
  Write-Host "OK: $archivo"
}
