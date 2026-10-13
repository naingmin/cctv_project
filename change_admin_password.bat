@echo off
rem Change the admin password for the CCTV system.
rem Double-click this file, then type a new password when prompted.
rem
rem It calls the Python that has the project's libraries installed.
rem (Plain "python" in a terminal can point at a different Python
rem  on this PC, which fails with "No module named ...".)

set PYTHON=C:\ProgramData\anaconda3\python.exe
set USER=%1
if "%USER%"=="" set USER=admin

cd /d "%~dp0backend"
"%PYTHON%" -m scripts.set_password %USER%

echo.
pause
