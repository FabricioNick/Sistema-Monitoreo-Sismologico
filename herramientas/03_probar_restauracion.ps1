# CS2041 - Prueba no destructiva del .dump original de 1000 registros.
# CREA una base NUEVA. Nunca elimina ni modifica las cuatro bases experimentales.
$ErrorActionPreference = 'Stop'
$baseDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'sql'
$dump = Join-Path $baseDir 'Dumps\bd_sismologico_exp_1000.dump'
$check = Join-Path $baseDir 'modulos\verificacion\61_verificar_restauracion_1000.sql'
$destino = 'bd_sismologico_restauracion_1000'
$bin = 'D:\Aplicaciones\PostgreSQL\18\bin'
$runtime = 'D:\Aplicaciones\PostgreSQL\18\pgAdmin 4\runtime'
function Find-PgTool([string]$name) {
  foreach ($path in @((Join-Path $bin $name), (Join-Path $runtime $name))) {
    if (Test-Path -LiteralPath $path) { return $path }
  }
  throw "No se encontro $name en las rutas de PostgreSQL 18."
}
$psql = Find-PgTool 'psql.exe'
$createdb = Find-PgTool 'createdb.exe'
$pgRestore = Find-PgTool 'pg_restore.exe'
if (-not (Test-Path -LiteralPath $dump)) { throw "No se encontro el respaldo original: $dump" }
if (-not (Test-Path -LiteralPath $check)) { throw "No se encontro el archivo de verificacion: $check" }
Write-Host '=== A. COMPROBAR RESPALDO ORIGINAL SIN MODIFICARLO ==='
$hash = Get-FileHash -LiteralPath $dump -Algorithm SHA256
Write-Host "Archivo: $dump"
Write-Host "SHA256:  $($hash.Hash)"
& $pgRestore --list $dump | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'El archivo no pudo leerse como respaldo de PostgreSQL.' }
Write-Host 'OK: pg_restore reconoce el respaldo personalizado.'
# Solicitar la clave una sola vez; el terminal no mostrara los caracteres.
# PGPASSWORD se limita a este proceso y se limpia aunque falle la prueba.
$securePassword = Read-Host -Prompt 'Contrasena del usuario postgres (no se mostrara)' -AsSecureString
$bstr = [IntPtr]::Zero
try {
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
  if ($bstr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
  $securePassword.Dispose()
}
try {
  Write-Host '=== B. COMPROBAR QUE LA BASE DE PRUEBA NO EXISTA ==='
  $encontrada = (& $psql -X -q -t -A -v ON_ERROR_STOP=1 -h localhost -p 5432 -U postgres -d postgres -c "SELECT COUNT(*) FROM pg_database WHERE datname = '$destino';")
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar la existencia de la base de prueba.' }
  if (($encontrada | Out-String).Trim() -ne '0') {
    throw "La base $destino ya existe. No se hizo ningun cambio; no se sobrescribe ni se elimina automaticamente."
  }
  Write-Host '=== C. CREAR UNA BASE NUEVA PARA PROBAR EL RESTORE ==='
  & $createdb -h localhost -p 5432 -U postgres -T template0 -E UTF8 $destino
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la base de prueba. No se modificaron originales.' }
  Write-Host "OK: creada $destino"
  Write-Host '=== D. RESTAURAR EN UNA SOLA TRANSACCION ==='
  & $pgRestore --exit-on-error --single-transaction --no-owner --no-acl -h localhost -p 5432 -U postgres -d $destino $dump
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo pg_restore. Se conserva $destino para diagnostico. Las bases originales permanecen intactas."
  }
  Write-Host 'OK: pg_restore termino sin errores.'
  Write-Host '=== E. VERIFICAR RECUENTOS, IGP, TRIGGERS E INTEGRIDAD ==='
  & $psql -X -v ON_ERROR_STOP=1 -h localhost -p 5432 -U postgres -d $destino -f $check
  if ($LASTEXITCODE -ne 0) { throw 'La verificacion SQL fallo. Conservar la salida para revisar.' }
  Write-Host '=== OK: RESPALDO RESTAURADO Y VERIFICADO EN BASE INDEPENDIENTE ==='
  Write-Host "Base de prueba: $destino"
  Write-Host 'No se alteraron bd_sismologico_exp_1000, _10000, _100000 ni _1000000.'

} finally {
  # No dejar la contrasena en el entorno del proceso PowerShell.
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
