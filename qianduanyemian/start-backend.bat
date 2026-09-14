@echo off
chcp 65001 >nul
title ShenDi Backend - One-Click Start
echo ============================================
echo    ShenDi ZhiKong - One-Click Backend Start
echo ============================================
echo.

rem ===== Check Node.js =====
where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js not found. Please install Node.js and add it to PATH.
  pause
  exit /b 1
)

rem ===== Backend directory =====
set "BACKEND_DIR=D:\devecostudio-windows-6.0.2.660\devecostudio-windows-6.0.2.660\prj\backend"
if not exist "%BACKEND_DIR%\server.js" (
  echo [ERROR] Backend file not found: %BACKEND_DIR%\server.js
  pause
  exit /b 1
)

rem ===== Check if port 3000 is already in use =====
netstat -ano | findstr ":3000 " | findstr "LISTENING" >nul 2>nul
if not errorlevel 1 (
  echo [INFO] Backend is already running - port 3000 is listening.
  echo        You can use it directly, no need to start again.
  echo.
  pause
  exit /b 0
)

rem ===== Enter backend dir and start =====
pushd "%BACKEND_DIR%"
echo [START] Launching backend service ...
echo         HTTP API   : http://localhost:3000
echo         WebSocket  : ws://localhost:8080
echo         PC portal  : will open in your browser
echo.
start "" "D:\devecostudio-windows-6.0.2.660\devecostudio-windows-6.0.2.660\prj\qianduanyemian\index.html"

echo [RUN] Backend is running... Press Ctrl+C to stop. Keep this window open.
echo.
node server.js

echo.
echo [INFO] Backend stopped.
pause
