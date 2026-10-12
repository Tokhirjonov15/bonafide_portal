@echo off
rem 진료 녹음 받아쓰기 설치 — 진료실 PC 에서 더블클릭 (2026-10-12)
chcp 65001 >nul
curl.exe -s -L -o "%TEMP%\rec_install.ps1" https://bonafide-portal.seoulgijibae.workers.dev/rec/rec_install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\rec_install.ps1"
