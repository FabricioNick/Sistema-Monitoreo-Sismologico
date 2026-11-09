@echo off
setlocal
cd /d "%~dp0"
if not exist ".env" (
  echo No se encontro .env.
  echo Copia .env.example a .env y configura la conexion local a PostgreSQL.
  pause
  exit /b 1
)
where node >nul 2>&1
if errorlevel 1 (
  echo Node.js no esta disponible en PATH.
  pause
  exit /b 1
)
if not exist "node_modules\pg\package.json" (
  echo Instalando dependencias necesarias...
  call npm install
  if errorlevel 1 (
    echo No fue posible instalar las dependencias.
    pause
    exit /b 1
  )
)
echo Iniciando MVP en una ventana de terminal...
start "Servidor MVP Sismologico" cmd /k "npm start"
timeout /t 3 /nobreak >nul
start "" "http://127.0.0.1:3000"
exit /b 0
