# Proyecto Final / Seccion 5.4 / Plataforma de pruebas.
# Consulta las caracteristicas del equipo Windows. No modifica configuraciones.
$ErrorActionPreference = 'Stop'

try {
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  $equipo = Get-CimInstance Win32_ComputerSystem
  $sistema = Get-CimInstance Win32_OperatingSystem

  Write-Output '=== 5.4 - EQUIPO UTILIZADO PARA LAS PRUEBAS ==='
  Write-Output ('Procesador: ' + $cpu.Name.Trim())
  Write-Output ('Nucleos fisicos: ' + $cpu.NumberOfCores)
  Write-Output ('Procesadores logicos: ' + $cpu.NumberOfLogicalProcessors)
  Write-Output ('Memoria RAM instalada (GiB): ' + [math]::Round($equipo.TotalPhysicalMemory / 1GB, 2))
  Write-Output ('Sistema operativo: ' + $sistema.Caption.Trim())
  Write-Output ('Version de Windows: ' + $sistema.Version)
  Write-Output ('Arquitectura: ' + $sistema.OSArchitecture)
  Write-Output '=== FIN DEL DIAGNOSTICO. NO SE MODIFICO NADA ==='
}
catch {
  Write-Error ('No fue posible consultar el equipo: ' + $_.Exception.Message)
  exit 1
}
