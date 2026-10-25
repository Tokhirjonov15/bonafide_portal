@echo off
REM guard: the scripts must be next to this file (run it from the USB bitplus folder, do not copy only the .bat)
if not exist "%~dp0bit_db_find_amt.ps1" (echo. & echo  [STOP] bit_db_find_amt.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bit_db_find_amt.ps1"
echo.
pause
