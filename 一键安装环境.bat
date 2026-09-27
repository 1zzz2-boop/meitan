@echo off
chcp 65001 >nul
title Coal Mine Guard - One-Click Environment Installer

REM ============================================================
REM Coal Mine Guard One-Click Installer
REM Installs all runtime environments and starts services.
REM Run this once per machine. Works on Windows 10/11 x64.
REM ============================================================

set "ROOT=%~dp0"
set "NODE_HOME=D:\nodejs"
set "PY_HOME=D:\yolo312"
set "VENV_HOME=D:\yolo312\venv"
set "MOS_HOME=D:\mosquitto"
set "BACKEND=%ROOT%backend"
set "YOLO_PKG=%ROOT%yolo_detection_project\yolo_detection_project"
set "INSTALLER=%ROOT%installer"
set "PG_HOST=localhost"
set "PG_PORT=5432"
set "PG_DB=coal_mine_guard"
set "PG_USER=coal_app"
set "PG_PASS=coal_app_pass_2026"
set "PG_SUPER_PASS=postgres123"
set "MQTT_USER=coal_bridge"
set "MQTT_PASS=DeepMine#mqtt2026"
set "LOG=%ROOT%install.log"

if not exist "%INSTALLER%" mkdir "%INSTALLER%"

echo ============================================================
echo   Coal Mine Guard - One-Click Installer
echo   Log: %LOG%
echo ============================================================
echo.

REM ------- admin self-elevate for service install / firewall -------
net session >nul 2>&1 || (
    echo [!] Need admin privileges, re-launching...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo [%date% %time%] Installer started > "%LOG%"

REM ==================== 1. NODE.JS ====================
echo [1/8] Checking Node.js...
where node >nul 2>&1
if %ERRORLEVEL%==0 (
    echo      Node.js already installed:
    node -v
    npm -v
    goto :done_node
)

echo      Node.js not found, installing portable version...
set "NODE_ZIP=%INSTALLER%\node-v24.16.0-win-x64.zip"
if not exist "%NODE_ZIP%" (
    echo      Downloading from nodejs.org...
    curl -L -o "%NODE_ZIP%" "https://nodejs.org/dist/v24.16.0/node-v24.16.0-win-x64.zip"
    if errorlevel 1 (
        echo [FAIL] Download failed. Put node-v24.16.0-win-x64.zip into installer\ then re-run.
        goto :fail
    )
)
echo      Extracting to %NODE_HOME%...
if exist "%NODE_HOME%" rmdir /s /q "%NODE_HOME%"
powershell -Command "Expand-Archive -Path '%NODE_ZIP%' -DestinationPath 'D:\' -Force"
if not exist "%NODE_HOME%\" (
    REM nodejs.org zip has a top-level dir; try to rename
    for /d %%i in ("D:\node-v*-win-x64") do (
        if not exist "%NODE_HOME%" ren "%%i" "nodejs"
    )
)
set "PATH=%NODE_HOME%;%NODE_HOME%\npm;%PATH%"
REM persist PATH for current user (HKCU so no admin needed)
powershell -Command "[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';%NODE_HOME%', 'User')"
echo      Node.js installed:
node -v
npm -v
>> "%LOG%" echo Node.js installed
:done_node
echo.

REM ==================== 2. PM2 ====================
echo [2/8] Checking pm2...
where pm2 >nul 2>&1
if %ERRORLEVEL%==0 (
    echo      pm2 already installed:
    pm2 -v
    goto :done_pm2
)
echo      Installing pm2 globally...
call npm install -g pm2 2>>"%LOG%"
echo      pm2 installed:
pm2 -v
:done_pm2
echo.

REM ==================== 3. BACKEND NODE_MODULES ====================
echo [3/8] Installing backend dependencies...
cd /d "%BACKEND%"
if exist "node_modules" (
    echo      node_modules already exists, verifying...
    node -e "require('express'); require('pg'); require('mqtt'); require('ws'); console.log('deps OK')" 2>>"%LOG%"
    if %ERRORLEVEL%==0 (
        echo      Dependencies verified.
        goto :done_deps
    )
    echo      Some deps missing, re-installing...
)
echo      Running npm install (this may take a minute)...
call npm install --no-audit --no-fund 2>>"%LOG%"
if errorlevel 1 (
    echo [WARN] npm install had warnings (see install.log). Trying npm ci...
    call npm install --legacy-peer-deps 2>>"%LOG%"
)
echo      Backend dependencies installed.
:done_deps
echo.

REM ==================== 4. POSTGRESQL ====================
echo [4/8] Checking PostgreSQL...
where psql >nul 2>&1
if %ERRORLEVEL%==0 goto :done_pg

REM also check if PG installed in a known location
if exist "E:\jindieAI\sqlapp\bin\psql.exe" (
    echo      Found existing PG in E:\jindieAI\sqlapp, adding to PATH...
    set "PATH=E:\jindieAI\sqlapp\bin;%PATH%"
    powershell -Command "[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';E:\jindieAI\sqlapp\bin', 'User')"
    goto :done_pg
)

REM attempt silent install via official exe
set "PG_EXE=%INSTALLER%\postgresql-12.19-windows-x64.exe"
if not exist "%PG_EXE%" (
    echo      Postgres 12 installer not in installer\, downloading...
    curl -L -o "%PG_EXE%" "https://get.enterprisedb.com/postgresql/postgresql-12.19-windows-x64.exe"
)
echo      Installing PostgreSQL 12 (silent)...
"%PG_EXE%" --mode unattended ^
    --superpassword "%PG_SUPER_PASS%" ^
    --prefix "C:\Program Files\PostgreSQL\12" ^
    --datadir "C:\Program Files\PostgreSQL\12\data" ^
    --enable_acltoggle 0 ^
    --servicename postgresql-x64-12 ^
    --port %PG_PORT% ^
    --locale "Chinese (Simplified), China" 2>>"%LOG%"
if errorlevel 1 (
    echo [WARN] PG silent install may have failed. Check install.log, install manually if needed.
) else (
    set "PATH=C:\Program Files\PostgreSQL\12\bin;%PATH%"
    powershell -Command "[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';C:\Program Files\PostgreSQL\12\bin', 'User')"
)

:done_pg
REM ---- init DB ----
echo      Initializing database (if needed)...
set "PGPASSWORD=%PG_SUPER_PASS%"
psql -h %PG_HOST% -p %PG_PORT% -U postgres -c "SELECT 1 FROM pg_database WHERE datname='%PG_DB%'" 2>nul | findstr "1" >nul
if errorlevel 1 (
    echo      Creating database %PG_DB%...
    createdb -h %PG_HOST% -p %PG_PORT% -U postgres -E UTF8 %PG_DB% 2>>"%LOG%"
)
psql -h %PG_HOST% -p %PG_PORT% -U postgres -c "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='%PG_USER%') THEN CREATE ROLE %PG_USER% LOGIN PASSWORD '%PG_PASS%'; ELSE ALTER ROLE %PG_USER% WITH LOGIN PASSWORD '%PG_PASS%'; END IF; END $$;" 2>>"%LOG%"
psql -h %PG_HOST% -p %PG_PORT% -U postgres -d %PG_DB% -c "GRANT ALL ON SCHEMA public TO %PG_USER%;" 2>>"%LOG%"
echo      Running schema.sql...
psql -h %PG_HOST% -p %PG_PORT% -U postgres -d %PG_DB% -f "%ROOT%sjk\schema.sql" 2>>"%LOG%"
echo      PostgreSQL ready.
echo.

REM ==================== 5. MOSQUITTO ====================
echo [5/8] Checking Mosquitto...
if exist "%MOS_HOME%\mosquitto.exe" goto :done_mos
echo      Mosquitto not found at %MOS_HOME%.
set "MOS_ZIP=%INSTALLER%\mosquitto-2.0.18-windows.zip"
if exist "%MOS_ZIP%" (
    echo      Extracting from %MOS_ZIP%...
    powershell -Command "Expand-Archive -Path '%MOS_ZIP%' -DestinationPath 'D:\' -Force"
) else (
    echo      Downloading Mosquitto...
    curl -L -o "%MOS_ZIP%" "https://mosquitto.org/files/binary/win64/mosquitto-2.0.18-windows.zip"
    if errorlevel 1 (
        echo [WARN] Mosquitto download failed. Put mosquitto-2.0.18-windows.zip into installer\ then re-run.
        goto :skip_mos
    )
    powershell -Command "Expand-Archive -Path '%MOS_ZIP%' -DestinationPath 'D:\' -Force"
)
:done_mos
echo      Setting up Mosquitto config, certs, password...
if not exist "%MOS_HOME%\certs" mkdir "%MOS_HOME%\certs"
if not exist "%MOS_HOME%\passwd" mkdir "%MOS_HOME%\passwd"
if not exist "%MOS_HOME%\mqtt-broker.conf" (
    >"%MOS_HOME%\mqtt-broker.conf" echo allow_anonymous false
    >>"%MOS_HOME%\mqtt-broker.conf" echo password_file %MOS_HOME%\passwd\mqtt-passwd
    >>"%MOS_HOME%\mqtt-broker.conf" echo listener 1883 0.0.0.0
    >>"%MOS_HOME%\mqtt-broker.conf" echo listener 8883 0.0.0.0
    >>"%MOS_HOME%\mqtt-broker.conf" echo cafile %MOS_HOME%\certs\ca.crt
    >>"%MOS_HOME%\mqtt-broker.conf" echo certfile %MOS_HOME%\certs\server.crt
    >>"%MOS_HOME%\mqtt-broker.conf" echo keyfile %MOS_HOME%\certs\server.key
    >>"%MOS_HOME%\mqtt-broker.conf" echo persistence false
    >>"%MOS_HOME%\mqtt-broker.conf" echo log_type error
    >>"%MOS_HOME%\mqtt-broker.conf" echo log_type warning
    >>"%MOS_HOME%\mqtt-broker.conf" echo log_type information
)
REM ---- generate self-signed certs if missing ----
if not exist "%MOS_HOME%\certs\ca.crt" (
    echo      Generating self-signed TLS certs (openssl)...
    where openssl >nul 2>&1
    if %ERRORLEVEL%==0 (
        cd /d "%MOS_HOME%\certs"
        openssl genrsa -out ca.key 2048 2>>"%LOG%"
        openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt -subj "/CN=coal-mqtt-ca" 2>>"%LOG%"
        openssl genrsa -out server.key 2048 2>>"%LOG%"
        openssl req -new -key server.key -out server.csr -subj "/CN=localhost" 2>>"%LOG%"
        openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 3650 -sha256 2>>"%LOG%"
    ) else (
        echo [WARN] openssl not found; skipping TLS cert generation. Broker will run on 1883 (plaintext) only.
        echo        Install Git for Windows or OpenSSL, then re-run.
    )
)
REM ---- set password file ----
if not exist "%MOS_HOME%\passwd\mqtt-passwd" (
    echo      Creating MQTT password hash...
    "%MOS_HOME%\mosquitto_passwd.exe" -c -b "%MOS_HOME%\passwd\mqtt-passwd" %MQTT_USER% "%MQTT_PASS%" 2>>"%LOG%"
)
REM ---- register windows service ----
sc query mosquitto >nul 2>&1
if %ERRORLEVEL%==0 (
    echo      Mosquitto service already registered.
) else (
    echo      Registering Mosquitto as Windows service (Automatic)...
    sc create mosquitto binPath= "\"%MOS_HOME%\mosquitto.exe\" -c \"%MOS_HOME%\mqtt-broker.conf\" -n mosquitto" start= auto DisplayName= "Mosquitto MQTT Broker" 2>>"%LOG%"
    sc description mosquitto "Coal Mine Guard MQTT Broker (TLS)" 2>>"%LOG%"
    sc failure mosquitto reset= 86400 actions= restart/5000/restart/10000/restart/30000 2>>"%LOG%"
)
echo      Starting Mosquitto service...
net start mosquitto >nul 2>&1
if errorlevel 1 (
    echo [WARN] Could not start Mosquitto service. Check its path and port availability.
) else (
    echo      Mosquitto running on 1883 + 8883.
)
:skip_mos
echo.

REM ==================== 6. FIREWALL RULES ====================
echo [6/8] Configuring Windows Firewall...
for %%p in (1883 8883 3000 8080) do (
    netsh advfirewall firewall show rule name="CMG-TCP-%%p" >nul 2>&1 || (
        netsh advfirewall firewall add rule name="CMG-TCP-%%p" dir=in action=allow protocol=TCP localport=%%p profile=any 2>>"%LOG%"
    )
)
netsh advfirewall firewall show rule name="CMG-UDP-8890" >nul 2>&1 || (
    netsh advfirewall firewall add rule name="CMG-UDP-8890" dir=in action=allow protocol=UDP localport=8890 profile=any 2>>"%LOG%"
)
echo      Firewall rules added: TCP 1883,8883,3000,8080 / UDP 8890
echo.

REM ==================== 7. PYTHON + YOLO VENV ====================
echo [7/8] Installing Python 3.12.8 + YOLO env...
REM detect python.exe in either flat or subdir layout
if exist "%PY_HOME%\python\python.exe" (
    set "PY_BIN=%PY_HOME%\python\python.exe"
    set "PY_DIR=%PY_HOME%\python"
    echo      Found Python (subdir layout) at %PY_BIN%:
    "%PY_BIN%" --version
    goto :done_py
)
if exist "%PY_HOME%\python.exe" (
    set "PY_BIN=%PY_HOME%\python.exe"
    set "PY_DIR=%PY_HOME%"
    echo      Found Python (flat layout) at %PY_BIN%:
    "%PY_BIN%" --version
    goto :done_py
)
echo      Python not found. Running silent installer...
set "PY_INST=%YOLO_PKG%\One-Click Environment Configuration\python-3.12.8-amd64.exe"
if not exist "%PY_INST%" set "PY_INST=%INSTALLER%\python-3.12.8-amd64.exe"
if not exist "%PY_INST%" (
    echo      Downloading Python 3.12.8 from python.org...
    curl -L -o "%INSTALLER%\python-3.12.8-amd64.exe" "https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe"
    set "PY_INST=%INSTALLER%\python-3.12.8-amd64.exe"
)
"%PY_INST%" /passive InstallAllUsers=0 Include_test=0 Include_launcher=0 Shortcuts=0 PrependPath=0 Include_doc=0 TargetDir=%PY_HOME%\python 2>>"%LOG%"
set "PY_BIN=%PY_HOME%\python\python.exe"
set "PY_DIR=%PY_HOME%\python"
echo      Python installed:
"%PY_BIN%" --version
:done_py

if exist "%VENV_HOME%\Scripts\python.exe" (
    echo      YOLO venv already exists, verifying...
    "%VENV_HOME%\Scripts\python.exe" -c "import cv2, paho.mqtt, numpy, onnx; print('venv OK')" >nul 2>&1 || (
        echo      Rebuilding venv...
        rmdir /s /q "%VENV_HOME%"
        "%PY_BIN%" -m venv "%VENV_HOME%"
    )
) else (
    echo      Creating YOLO venv at %VENV_HOME%...
    "%PY_BIN%" -m venv "%VENV_HOME%"
)

echo      Upgrading pip in venv...
"%VENV_HOME%\Scripts\python.exe" -m pip install --upgrade pip -q 2>>"%LOG%"
echo      Installing YOLO offline dependencies (excluding torch)...
set "YOLO_OFF=%YOLO_PKG%\One-Click Environment Configuration\YOLO12_pip\pip_offline_packages"
set "YOLO_REQ=%YOLO_PKG%\req_now.txt"
if not exist "%YOLO_REQ%" (
    REM fallback: use filtered version on the fly
    "%VENV_HOME%\Scripts\pip.exe" install --no-index --find-links="%YOLO_OFF%" ^
        numpy==1.26.4 opencv-python==4.9.0.80 scipy psutil py-cpuinfo ^
        labelme==6.3.0 pyqt5==5.15.11 pillow matplotlib onnx onnxruntime ^
        tqdm pyyaml requests paho-mqtt==2.1.0 lap onnxslim -q 2>>"%LOG%"
) else (
    "%VENV_HOME%\Scripts\pip.exe" install --no-index --find-links="%YOLO_OFF%" -r "%YOLO_REQ%" -q 2>>"%LOG%"
)
echo      Installing torch (CPU offline, CUDA optional)...
if exist "%YOLO_OFF%\torch-2.6.0-cp312-cp312-win_amd64.whl" (
    "%VENV_HOME%\Scripts\pip.exe" install --no-index --find-links="%YOLO_OFF%" torch==2.6.0 torchvision==0.21.0 -q 2>>"%LOG%"
    echo      CPU torch installed from offline wheel.
) else (
    echo      Offline torch not found, skipping. Run pip install torch torchvision with internet later.
)
echo      Installing ultralytics (YOLO framework)...
"%VENV_HOME%\Scripts\pip.exe" install --no-index --find-links="%YOLO_OFF%" ultralytics==8.3.241 ultralytics-thop==2.0.19 -q 2>>"%LOG%"
echo      YOLO env ready.
echo.

REM ==================== 8. START BACKEND ====================
echo [8/8] Starting backend services...
cd /d "%BACKEND%"
if exist "logs" mkdir logs
set "PGPASSWORD=%PG_PASS%"
REM Override .env values with our installed paths
echo. > ".env.local"
echo DB_HOST=%PG_HOST% >> ".env.local"
echo DB_PORT=%PG_PORT% >> ".env.local"
echo DB_DATABASE=%PG_DB% >> ".env.local"
echo DB_USER=%PG_USER% >> ".env.local"
echo DB_PASSWORD=%PG_PASS% >> ".env.local"
echo MQTT_URL=mqtts://localhost:8883 >> ".env.local"
echo MQTT_USER=%MQTT_USER% >> ".env.local"
echo MQTT_PASS=%MQTT_PASS% >> ".env.local"
echo MQTT_CA_FILE=%MOS_HOME%\certs\ca.crt >> ".env.local"
echo UDP_HOST=0.0.0.0 >> ".env.local"
echo UDP_PORT=8890 >> ".env.local"
echo PORT=3000 >> ".env.local"
echo WS_PORT=8080 >> ".env.local"

echo      pm2 starting coal-backend...
call pm2 delete coal-backend >nul 2>&1
call pm2 delete coal-backup >nul 2>&1
call pm2 start ecosystem.config.js 2>>"%LOG%"
call pm2 save 2>>"%LOG%"
echo      pm2 status:
call pm2 status
echo.

REM ==================== DONE ====================
echo ============================================================
echo   ALL DONE. Summary:
echo ============================================================
echo   Node.js   : %NODE_HOME%   (node -v / npm -v)
echo   PostgreSQL: %PG_HOST%:%PG_PORT%  db=%PG_DB%  user=%PG_USER%
echo   Mosquitto : %MOS_HOME%  (service: mosquitto, TLS on 8883, plain on 1883)
echo   Python    : %PY_HOME%  venv=%VENV_HOME%
echo   YOLO pkg  : %YOLO_PKG%
echo   Backend   : pm2 coal-backend  (HTTP 3000, WS 8080)
echo   Firewall  : TCP 1883,8883,3000,8080  UDP 8890
echo   Log       : %LOG%
echo ============================================================
echo   Useful commands:
echo     pm2 logs coal-backend       # view backend logs
echo     pm2 status                  # all pm2 processes
echo     net start mosquitto         # start/stop MQTT
echo     "%VENV_HOME%\Scripts\python.exe" your_yolo_script.py
echo ============================================================
pause
exit /b 0

:fail
echo.
echo [FAIL] Installer aborted. See %LOG% for details.
pause
exit /b 1