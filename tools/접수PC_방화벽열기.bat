@echo off
REM 2026-10-28: DB agents on the reception PCs could not see each other (TCP 9001 blocked), so all of them became "sender".
REM This opens ONLY ports 9000/9001 for the local network. It asks for administrator permission once (click Yes).
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo  Asking for administrator permission... click YES.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo.
echo  Opening TCP 9001 (DB agent) and 9000 (watcher) for the local network only...
powershell -NoProfile -ExecutionPolicy Bypass -Command "foreach($r in @(@{n='BitPlus DB Agent (TCP 9001)';p=9001},@{n='BitPlus Watcher (TCP 9000)';p=9000})){ if(-not (Get-NetFirewallRule -DisplayName $r.n -ErrorAction SilentlyContinue)){ New-NetFirewallRule -DisplayName $r.n -Direction Inbound -Protocol TCP -LocalPort $r.p -Action Allow -Profile Any -RemoteAddress LocalSubnet | Out-Null; 'added  ' + $r.n } else { 'exists ' + $r.n } }"
echo.
echo  Done. Within 1-2 minutes only ONE reception PC should show "sender" in Dongseon [PC install status].
echo.
pause
