# 04_ejecutar_25_mediciones.ps1
# Proyecto final CS2041 - Ejecuta las 25 combinaciones de 06_mediciones.sql.
# Opcionalmente ejecuta solo las 10 combinaciones de C4 y C5.
# Ubicacion prevista: herramientas/04_ejecutar_25_mediciones.ps1
# NO modifica 06_mediciones.sql, los CSV publicados ni las bases originales.
# Requiere cinco bases bd_sismologico_prueba_exp_{100,1000,10000,100000,1000000}
# generadas y validadas por 04_bases_experimentales.sql.
# Cada comparacion: 2 calentamientos + 5 mediciones por escenario = 14 filas.
# Para comprobar rutas locales y listar las 25 combinaciones sin medir: .\04_ejecutar_25_mediciones.ps1 -SoloComprobar
# Para ejecutar solamente C4/C5 (10 combinaciones): .\04_ejecutar_25_mediciones.ps1 -SoloC4C5 -PedirClaveUnaVez

[CmdletBinding()]
param(
    [string]$PsqlPath = '',
    [string]$Servidor = 'localhost',
    [ValidateRange(1, 65535)][int]$Puerto = 5432,
    [string]$Usuario = 'postgres',
    [switch]$PedirClaveUnaVez,
    [switch]$SoloComprobar,
    [switch]$SoloC4C5,
    [switch]$Solo100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Encontrar-Psql {
    param([string]$RutaExplicita)
    if (-not [string]::IsNullOrWhiteSpace($RutaExplicita)) {
        if (-not (Test-Path -LiteralPath $RutaExplicita -PathType Leaf)) {
            throw "No existe psql.exe en la ruta indicada: $RutaExplicita"
        }
        return (Resolve-Path -LiteralPath $RutaExplicita).Path
    }
    $comando = Get-Command 'psql.exe' -ErrorAction SilentlyContinue
    if ($null -ne $comando) { return $comando.Source }
    $candidatos = @(
        'D:\Aplicaciones\PostgreSQL\18\bin\psql.exe',
        'D:\Aplicaciones\PostgreSQL\18\pgAdmin 4\runtime\psql.exe',
        'C:\Program Files\PostgreSQL\18\bin\psql.exe',
        'C:\Program Files\PostgreSQL\17\bin\psql.exe'
    )
    foreach ($candidato in $candidatos) {
        if (Test-Path -LiteralPath $candidato -PathType Leaf) { return $candidato }
    }
    throw 'No se encontro psql.exe. Use -PsqlPath "RUTA_COMPLETA_A_psql.exe".'
}

$raizProyecto = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$carpetaSql = Join-Path $raizProyecto 'sql'
$archivoSql = Join-Path $carpetaSql '06_mediciones.sql'
if (-not (Test-Path -LiteralPath $archivoSql -PathType Leaf)) {
    throw "No se encontro $archivoSql. Coloque este archivo .ps1 en herramientas/ del repositorio."
}

$psql = Encontrar-Psql -RutaExplicita $PsqlPath
[int[]]$escalas = @(100, 1000, 10000, 100000, 1000000)
if ($Solo100) { $escalas = @(100) }
[int[]]$consultas = @(1, 2, 3, 4, 5)
if ($SoloC4C5) { $consultas = @(4, 5) }
$totalEsperado = $consultas.Count * $escalas.Count

Write-Host ("=== PREPARACION: {0} COMPARACIONES DE RENDIMIENTO ===" -f $totalEsperado)
Write-Host "psql: $psql"
Write-Host "SQL: $archivoSql"
Write-Host "Conexion: $Servidor`:$Puerto, usuario $Usuario"
Write-Host ('Bases requeridas: ' + (($escalas | ForEach-Object { 'bd_sismologico_prueba_exp_' + $_ }) -join ', '))
Write-Host 'Los resultados existentes NO se sobrescribiran.'

if ($SoloComprobar) {
    foreach ($consulta in $consultas) {
        foreach ($escala in $escalas) {
            Write-Host ("PREVISTO: C{0} / {1} -> 06_C{0}_{1}.csv" -f $consulta, $escala)
        }
    }
    Write-Host 'Comprobacion de archivos terminada; no se ejecuto ninguna consulta.'
    exit 0
}

$marca = Get-Date -Format 'yyyyMMdd_HHmmss'
$carpetaEjecucion = Join-Path (Join-Path $carpetaSql 'ejecuciones') $marca
if (Test-Path -LiteralPath $carpetaEjecucion) {
    throw "Ya existe la carpeta de ejecucion: $carpetaEjecucion"
}
$carpetaSalidas = Join-Path $carpetaEjecucion 'resultados'
$carpetaLogs = Join-Path $carpetaEjecucion 'logs'
New-Item -ItemType Directory -Path $carpetaSalidas -Force | Out-Null
New-Item -ItemType Directory -Path $carpetaLogs -Force | Out-Null

$directorioAnterior = (Get-Location).Path
$ejecutadas = 0
$claveAnterior = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
try {
    if ($PedirClaveUnaVez) {
        $claveSegura = Read-Host -Prompt 'Clave de PostgreSQL (solo para esta ejecucion)' -AsSecureString
        $punteroClave = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($claveSegura)
        try {
            $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($punteroClave)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($punteroClave)
        }
    }
    # Importante: las rutas de \copy en 06_mediciones.sql son relativas a
    # la carpeta de trabajo de psql (resultados/06_C*.csv).
    Set-Location -LiteralPath $carpetaEjecucion
    foreach ($consulta in $consultas) {
        foreach ($escala in $escalas) {
            $db = "bd_sismologico_prueba_exp_$escala"
            $nombre = "06_C${consulta}_${escala}.csv"
            $csv = Join-Path $carpetaSalidas $nombre
            $log = Join-Path $carpetaLogs "06_C${consulta}_${escala}.log"
            Write-Host ("[{0}/{3}] C{1} - {2} registros: inicio" -f ($ejecutadas + 1), $consulta, $escala, $totalEsperado)

            # El servidor emite NOTICE por stderr; no debe confundirse con error.
            # El estado real lo determinan ON_ERROR_STOP y el codigo de salida.
            $manejoAnterior = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                & $psql -X -v ON_ERROR_STOP=1 -h $Servidor -p "$Puerto" -U $Usuario -d $db `
                    -v "consulta=$consulta" -v "escala=$escala" -f $archivoSql *> $log
                $codigoSalida = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $manejoAnterior
            }
            if ($codigoSalida -ne 0) {
                throw "Fallo C$consulta / $escala (codigo $codigoSalida). Revisar: $log"
            }
            if (-not (Test-Path -LiteralPath $csv -PathType Leaf)) {
                throw "No se genero el CSV esperado: $csv. Revisar: $log"
            }

            $filas = @(Import-Csv -LiteralPath $csv)
            $sin = @($filas | Where-Object { $_.escenario -eq 'sin_indice' })
            $con = @($filas | Where-Object { $_.escenario -eq 'con_indice' })
            $mediciones = @($filas | Where-Object { $_.fase -eq 'medicion' })
            $calentamientos = @($filas | Where-Object { $_.fase -eq 'calentamiento' })
            if ($filas.Count -ne 14 -or $sin.Count -ne 7 -or $con.Count -ne 7 -or
                $mediciones.Count -ne 10 -or $calentamientos.Count -ne 4) {
                throw "Conteos incorrectos en ${nombre}: filas=$($filas.Count), sin=$($sin.Count), con=$($con.Count)."
            }
            $ejecutadas++
            Write-Host "OK: $nombre (14 filas, 10 mediciones, 4 calentamientos)"
        }
    }
}
finally {
    Set-Location -LiteralPath $directorioAnterior
    [Environment]::SetEnvironmentVariable('PGPASSWORD', $claveAnterior, 'Process')
}

$csvGenerados = @(Get-ChildItem -LiteralPath $carpetaSalidas -Filter '06_C*.csv' -File)
if ($csvGenerados.Count -ne $totalEsperado -or $ejecutadas -ne $totalEsperado) {
    throw "Ejecucion incompleta: $ejecutadas procedimientos y $($csvGenerados.Count) CSV."
}
Write-Host ("=== FINALIZADO: {0}/{0} COMPARACIONES VALIDADAS ===" -f $totalEsperado)
Write-Host "CSV nuevos: $carpetaSalidas"
Write-Host "Registros de ejecucion: $carpetaLogs"
Write-Host 'Los CSV anteriores y las bases originales no se reemplazaron.'
