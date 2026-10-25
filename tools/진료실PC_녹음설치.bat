@echo off
cd /d "%~dp0"
echo.
echo  Doctor PC: consultation recording (Bit outpatient window patient change = cut and save)
echo  Plug in the external drive first. Run with the DOCTOR Windows account. Do NOT use Run as administrator.
echo.
set /p N=Clinic room number (1-4): 
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0clinic_rec_install.ps1' -Pc ([string][char]0xC9C4+[char]0xB8CC+[char]0xC2E4+'%N%')"
echo.
pause
