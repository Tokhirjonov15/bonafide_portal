# ─────────────────────────────────────────────────────────────
#  비트플러스 감시 스크립트 설치 (접수 PC마다 1회) — 관리자 PowerShell에서 실행
#
#    powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 접수1
#
#  하는 일: C:\bitplus 에 스크립트 복사 → bitbot 비밀번호 입력받아 .secret 저장(현재 사용자만 읽기) →
#           TCP 9000 방화벽 허용(다른 접수 PC의 캐스트 수신) → 로그온 시 자동 시작 작업 등록 → 지금 시작
#  마지막에 이 PC의 IP를 출력한다 → 비트 환경설정 › 기타사항 › 전광판IP 세팅에 그 IP를 등록할 것.
# ─────────────────────────────────────────────────────────────
param([Parameter(Mandatory = $true)][string]$Pc, [string]$Dest = 'C:\bitplus')
$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$src = Join-Path $PSScriptRoot 'bitplus_watcher.ps1'
if (-not (Test-Path $src)) { throw "bitplus_watcher.ps1 이 같은 폴더에 없습니다: $src" }
New-Item -ItemType Directory -Force $Dest | Out-Null
Copy-Item $src (Join-Path $Dest 'bitplus_watcher.ps1') -Force
Write-Host "① 스크립트 복사: $Dest\bitplus_watcher.ps1"

$secret = Join-Path $Dest 'bitplus_watcher.secret'
if (-not (Test-Path $secret)) {
  $pw = Read-Host -AsSecureString "동선관리 bitbot 계정 비밀번호"
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($pw))
  [IO.File]::WriteAllText($secret, $plain, (New-Object Text.UTF8Encoding $false))
  icacls $secret /inheritance:r /grant:r "$($env:USERNAME):R" | Out-Null
  Write-Host "② 비밀번호 파일 저장(현재 사용자만 읽기): $secret"
} else { Write-Host "② 비밀번호 파일 이미 있음: $secret" }

if ($isAdmin) {
  if (-not (Get-NetFirewallRule -DisplayName 'BitPlus Watcher (TCP 9000)' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'BitPlus Watcher (TCP 9000)' -Direction Inbound -Protocol TCP -LocalPort 9000 -Action Allow -Profile Any -RemoteAddress LocalSubnet | Out-Null
  }
  Write-Host "③ 방화벽: TCP 9000 인바운드(같은 네트워크) 허용"
} else { Write-Host "③ (관리자 아님) 방화벽 규칙은 건너뜀 — 다른 PC의 캐스트가 안 오면 관리자 PowerShell에서 다시 실행" -ForegroundColor Yellow }

$tr = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Dest\bitplus_watcher.ps1`" -Pc $Pc"
schtasks /Create /TN 'BitPlusWatcher' /SC ONLOGON /RL LIMITED /TR $tr /F | Out-Null
Write-Host "④ 로그온 시 자동 시작 작업 등록: BitPlusWatcher (-Pc $Pc)"
schtasks /Run /TN 'BitPlusWatcher' | Out-Null
Start-Sleep 6
$log = Join-Path $env:LOCALAPPDATA 'bitplus_watcher\watcher.log'
Write-Host "⑤ 시작됨 — 최근 로그:"; if (Test-Path $log) { Get-Content $log -Tail 4 | ForEach-Object { "   $_" } }

$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } | ForEach-Object { $_.IPAddress }
Write-Host ""
Write-Host "▶ 비트 환경설정 › 기타사항 › 전광판IP 세팅에 등록할 이 PC IP: $($ips -join ', ')  (구분: 접수BitCast)" -ForegroundColor Cyan
Write-Host "  ※ 이 IP가 바뀌지 않도록 고정 IP(또는 공유기 예약)로 설정하세요."
Write-Host "  중지: schtasks /End /TN BitPlusWatcher   삭제: schtasks /Delete /TN BitPlusWatcher /F   로그: $log"
