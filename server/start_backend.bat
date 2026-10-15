@echo off
rem ============================================================
rem  Starts the CCTV backend API (FastAPI).
rem
rem  Runs automatically at Windows startup via Task Scheduler
rem  (task name: "CCTV Backend"). You can also double-click
rem  this file to restart the server manually.
rem
rem  Output is appended to server\logs\backend.log
rem ============================================================
setlocal

set PYTHON=C:\Users\user\Desktop\cctv_project\backend\.venv\Scripts\python.exe
set PROJECT=C:\Users\user\Desktop\cctv_project

if not exist "%PROJECT%\server\logs" mkdir "%PROJECT%\server\logs"

cd /d "%PROJECT%\backend"

rem --host 0.0.0.0: reachable on the office LAN.
rem After the HTTPS cut-over this becomes 127.0.0.1 so only
rem the local reverse proxy (Caddy) can reach it.
"%PYTHON%" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 >> "%PROJECT%\server\logs\backend.log" 2>&1
