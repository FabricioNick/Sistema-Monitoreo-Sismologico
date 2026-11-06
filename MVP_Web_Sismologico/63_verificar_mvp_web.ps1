$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:3000'
Write-Host '=== MVP - PRUEBA DE CONEXION Y CONSULTAS ORIGINALES ==='
try {
    $health = Invoke-RestMethod "$base/api/health" -TimeoutSec 12
    if (-not $health.ok) { throw 'El endpoint de salud no confirmo la conexion.' }
    Write-Host "OK: conectado a $($health.database), PostgreSQL $($health.version)"
    $data = Invoke-RestMethod "$base/api/overview" -TimeoutSec 12
    if ($data.total -ne 1000000 -or $data.provenance.eventos_igp -ne 24289) {
        throw "La base no coincide con el experimento de un millon: total=$($data.total), IGP=$($data.provenance.eventos_igp)"
    }
    Write-Host 'OK: 1000000 filas, 24289 eventos del IGP.'
    $expected = @{ C1 = 15; C2 = 10; C3 = 100; C4 = 15; C5 = 15 }
    foreach ($id in @('C1','C2','C3','C4','C5')) {
        $result = Invoke-RestMethod "$base/api/queries/$id" -TimeoutSec 60
        if ($result.count -ne $expected[$id]) { throw "${id}: filas=$($result.count), esperado=$($expected[$id])" }
        Write-Host "OK: $id, $($result.count) filas, $($result.duration_ms) ms (respuesta del servidor)."
    }
    Write-Host '=== OK: LAS CINCO CONSULTAS WEB FUNCIONAN CON POSTGRESQL ==='
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host 'Comprueba que npm start siga abierto y que el archivo .env sea correcto.'
    exit 1
}
