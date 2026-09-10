# ─────────────────────────────────────────────────────────────
#  비트플러스 감시 스크립트 설치 (접수 PC·진료실 PC마다 1회) — 비트를 쓰는 그 Windows 계정으로 로그온한 상태에서 실행 (관리자 PowerShell 권장)
#
#    접수 PC:   powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 접수1
#    진료실 PC: powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 진료실1     (외래진료실 창의 처방 목록 → 슬립)
#
#  하는 일: C:\bitplus 에 스크립트 복사 → bitbot 비밀번호 입력받아 .secret 저장(현재 사용자만 읽기) →
#           TCP 9000 방화벽 허용(다른 접수 PC의 캐스트 수신; 진료실 PC에는 필요 없지만 무해) → 로그온 시 자동 시작 작업 등록 → 지금 시작
#  마지막에 이 PC의 IP를 출력한다 → 접수 PC라면 비트 환경설정 › 기타사항 › 전광판IP 세팅에 그 IP를 등록할 것. 진료실 PC는 등록 불필요.
#  ※ 작업은 지금 로그온한 사용자로 등록된다. 비트를 다른 Windows 계정으로 쓰면 그 계정으로 로그온해서 실행해야 창을 읽을 수 있다.
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

# 로그온 시 자동 시작 (관리자 아니어도 현재 사용자 작업으로 등록됨). 실행 시간 제한 없음(schtasks 기본 72시간 제한 회피), 죽으면 1분 뒤 재시작
$args_ = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Dest\bitplus_watcher.ps1`" -Pc $Pc"
try {
  Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { try { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -like '*bitplus_watcher.ps1*' } catch { $false } } | Stop-Process -Force -ErrorAction SilentlyContinue   # 이전 수동 실행분 정리
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args_
  $trg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName 'BitPlusWatcher' -Action $act -Trigger $trg -Settings $set -RunLevel Limited -Force -ErrorAction Stop | Out-Null
  Write-Host "④ 로그온 시 자동 시작 작업 등록: BitPlusWatcher (-Pc $Pc)"
  Start-ScheduledTask -TaskName 'BitPlusWatcher'
} catch {
  # 작업 스케줄러가 막혀 있으면 시작 프로그램 폴더의 .vbs 로 대체(창 없이 실행)
  $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'BitPlusWatcher.vbs'
  $line = 'CreateObject("WScript.Shell").Run "powershell.exe ' + ($args_ -replace '"', '""') + '", 0, False'
  [IO.File]::WriteAllText($vbs, $line, [Text.Encoding]::Unicode)
  Write-Host "④ 작업 등록 실패($($_.Exception.Message)) → 시작 프로그램에 등록: $vbs" -ForegroundColor Yellow
  Start-Process wscript.exe -ArgumentList "`"$vbs`""
}
Start-Sleep 6
$log = Join-Path $env:LOCALAPPDATA 'bitplus_watcher\watcher.log'
Write-Host "⑤ 시작됨 — 최근 로그:"; if (Test-Path $log) { Get-Content $log -Tail 4 | ForEach-Object { "   $_" } }

$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } | ForEach-Object { $_.IPAddress }
Write-Host ""
if (Get-Process -Name BITDoctorOrder -ErrorAction SilentlyContinue) {
  Write-Host "▶ 외래진료실 창이 열려 있음 → 진료실 PC로 동작합니다. 전광판IP 등록은 필요 없습니다." -ForegroundColor Cyan
  Write-Host "  확인: 환자를 조회한 상태에서 로그에 '처방 전송: 차트번호 …' 가 찍히고, 동선관리 상단 pill 에 '$Pc' 가 초록으로 뜨면 정상."
} else {
  Write-Host "▶ 비트 환경설정 › 기타사항 › 전광판IP 세팅에 등록할 이 PC IP: $($ips -join ', ')  (구분: 접수BitCast)" -ForegroundColor Cyan
  Write-Host "  ※ 이 IP가 바뀌지 않도록 고정 IP(또는 공유기 예약)로 설정하세요. (진료실 PC라면 비트 외래진료실을 연 뒤 다시 실행하지 않아도 됨 — 감시 스크립트가 창을 보면 스스로 읽기 시작)"
}
Write-Host "  중지: Stop-ScheduledTask BitPlusWatcher   삭제: Unregister-ScheduledTask BitPlusWatcher -Confirm:`$false   로그: $log"
