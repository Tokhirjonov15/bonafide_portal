@echo off
rem === Portal demo lokal server (public papkasidan) ===
cd /d "%~dp0public"
start "" http://localhost:8080/
python -m http.server 8080 2>nul || py -m http.server 8080
