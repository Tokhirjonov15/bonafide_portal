@echo off
REM guard: the scripts must be next to this file (run it from the USB bitplus folder, do not copy only the .bat)
if not exist "%~dp0bitplus_install.ps1" (echo. & echo  [STOP] bitplus_install.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
if not exist "%~dp0slip_capture_install.ps1" (echo. & echo  [STOP] slip_capture_install.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
if not exist "%~dp0bitplus_watcher.ps1" (echo. & echo  [STOP] bitplus_watcher.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
if not exist "%~dp0slip_capture.ps1" (echo. & echo  [STOP] slip_capture.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
cd /d "%~dp0"
echo.
echo  Clinic room PC install (watcher v3.7 + capture bar)
echo  Run with the DOCTOR Windows account. Do NOT use Run as administrator.
echo.
set /p N=Clinic room number (1-4):
echo.
echo  Does a DOCTOR write prescriptions on this PC?
echo    Y = yes (send slips from this PC)
echo    N = no, nurses only view Bit here (do NOT send slips)
set NN=
set /p RX=Y or N:
if /i "%RX%"=="N" set NN=-NoNote
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0bitplus_install.ps1' -Pc ([string][char]0xC9C4+[char]0xB8CC+[char]0xC2E4+'%N%') %NN%"
echo.
echo  ---- capture bar ----
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0slip_capture_install.ps1' -Pc ([string][char]0xC9C4+[char]0xB8CC+[char]0xC2E4+'%N%')"
echo.
pause
