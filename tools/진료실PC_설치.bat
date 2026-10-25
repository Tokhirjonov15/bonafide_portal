@echo off
REM guard: the scripts must be next to this file (run it from the USB bitplus folder, do not copy only the .bat)
if not exist "%~dp0bitplus_install.ps1" (echo. & echo  [STOP] bitplus_install.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
if not exist "%~dp0slip_capture_install.ps1" (echo. & echo  [STOP] slip_capture_install.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
if not exist "%~dp0bitplus_watcher.ps1" (echo. & echo  [STOP] bitplus_watcher.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
if not exist "%~dp0slip_capture.ps1" (echo. & echo  [STOP] slip_capture.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
cd /d "%~dp0"
echo.
echo  Clinic room PC install (watcher v3.6 + capture bar)
echo  Run with the DOCTOR Windows account. Do NOT use Run as administrator.
echo.
set /p N=Clinic room number (1-4): 
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0bitplus_install.ps1' -Pc ([string][char]0xC9C4+[char]0xB8CC+[char]0xC2E4+'%N%')"
echo.
echo  ---- capture bar ----
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0slip_capture_install.ps1' -Pc ([string][char]0xC9C4+[char]0xB8CC+[char]0xC2E4+'%N%')"
echo.
pause
