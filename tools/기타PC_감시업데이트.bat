@echo off
REM guard: the scripts must be next to this file (run it from the USB bitplus folder, do not copy only the .bat)
if not exist "%~dp0bitplus_update_keepname.ps1" (echo. & echo  [STOP] bitplus_update_keepname.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
if not exist "%~dp0bitplus_install.ps1" (echo. & echo  [STOP] bitplus_install.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
if not exist "%~dp0bitplus_watcher.ps1" (echo. & echo  [STOP] bitplus_watcher.ps1 is not in this folder: %~dp0 & echo  Open the USB drive - bitplus folder and double-click this file there. & echo. & pause & exit /b 1)
cd /d "%~dp0"
echo.
echo  Watcher update (v3.7) - keeps this PC's name (reception, treatment, PT, C-Arm, consult PCs)
echo  Run with the SAME Windows account as before. Do NOT use Run as administrator.
echo.
echo  Does a DOCTOR write prescriptions on this PC?
echo    N = no (reception / treatment / PT / C-Arm ...)  -- usually N
echo    Y = yes (send slips from this PC)
echo    M = only Mounjaro / Wegovy prescriptions
set NN=-NoNote
set /p RX=N, Y or M:
if /i "%RX%"=="Y" set NN=
if /i "%RX%"=="M" set NN=-NoteGlp
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bitplus_update_keepname.ps1" %NN%
echo.
pause
