# ─────────────────────────────────────────────────────────────
#  비트플러스 감시 스크립트(+ DB 에이전트) 설치 (PC마다 1회) — 비트를 쓰는 그 Windows 계정으로 로그온한 상태에서 실행 (관리자 PowerShell 권장)
#
#    접수 PC(에이전트 포함): powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 접수1 -Agent -Priority 3 -Peers 192.168.0.44,192.168.0.57
#    접수 PC(감시만):        powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 접수2-2
#    진료실 PC:              powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 진료실1     (외래진료실 창의 처방 목록 → 슬립)
#
#  하는 일: C:\bitplus 에 스크립트 복사 → bitbot 비밀번호 입력받아 .secret 저장(현재 사용자만 읽기) →
#           TCP 9000 방화벽 허용(다른 접수 PC의 캐스트 수신; 진료실 PC에는 필요 없지만 무해) → 로그온 시 자동 시작 작업 등록 → 지금 시작
#  -Agent 를 붙이면 비트 DB 를 직접 읽는 에이전트(bit_db_agent.ps1)도 함께 설치한다:
#           dongseon_ro(SQL 읽기 전용) 비밀번호 입력 → bit_db_agent.sql.secret → TCP 9001 방화벽(다른 PC 가 이 에이전트의 상태를 묻는 포트) →
#           bitplus_peers.txt(-Peers: 다른 에이전트 PC IP 목록) → 작업 BitDbAgent 등록·시작. -Priority 가 큰 PC 가 전송 담당, 나머지는 대기.
#           같은 PC 의 감시 스크립트는 에이전트가 정상이면 캐스트로는 bitIntake 에 쓰지 않는다(bitplus_watcher_README.md 참고).
#  마지막에 이 PC의 IP를 출력한다 → 접수 PC라면 비트 환경설정 › 기타사항 › 전광판IP 세팅에 그 IP를 등록할 것. 진료실 PC는 등록 불필요.
#  ※ 작업은 지금 로그온한 사용자로 등록된다. 비트를 다른 Windows 계정으로 쓰면 그 계정으로 로그온해서 실행해야 창을 읽을 수 있다.
# ─────────────────────────────────────────────────────────────
param([Parameter(Mandatory = $true)][string]$Pc, [string]$Dest = 'C:\bitplus',
      [switch]$ResetPw,          # -ResetPw: 저장된 bitbot 비밀번호를 지우고 다시 입력받는다 (틀리게 넣었을 때)
      [switch]$Agent,            # -Agent: DB 에이전트(bit_db_agent.ps1)도 설치
      [int]$Priority = 1,        # 에이전트 우선순위(큰 수가 전송 담당). 접수1=3, 접수2=2, 접수3=1 처럼
      [string]$Peers = '',       # 다른 에이전트 PC IP (쉼표 구분). 감시 스크립트도 이 목록의 에이전트를 확인한다
      [switch]$ResetSqlPw)       # -ResetSqlPw: 저장된 dongseon_ro 비밀번호를 지우고 다시 입력받는다
$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function ReadSecret($prompt, $file) {   # 비밀번호를 입력받아 파일에 저장(현재 사용자만 접근)
  Write-Host "   ※ 한/영 상태를 확인하고 입력하세요. 입력 중 글자는 보이지 않습니다." -ForegroundColor DarkGray
  $pw = Read-Host -AsSecureString $prompt
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($pw))
  if (-not $plain.Trim()) { throw "비밀번호가 비어 있습니다." }
  [IO.File]::WriteAllText($file, $plain, (New-Object Text.UTF8Encoding $false))
  icacls $file /inheritance:r /grant:r "$($env:USERNAME):M" | Out-Null   # 현재 사용자만 읽기·수정·삭제 (R 만 주면 본인도 못 지움)
  return $plain.Length
}
function RemoveSecret($file) { if (Test-Path $file) { icacls $file /grant "$($env:USERNAME):F" | Out-Null; Remove-Item $file -Force } }
function KillScript($name) {   # '-File …<name>' 로 실행된 PowerShell 만 종료 (파일명이 우연히 들어간 다른 창·편집기·이 설치 창은 건드리지 않음)
  Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { if ($_.Id -eq $PID) { return $false }; try { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match ('-File\s+"?[^"\s]*' + [regex]::Escape($name)) } catch { $false } } | Stop-Process -Force -ErrorAction SilentlyContinue
}
function RegisterTask($name, $args_, $log) {   # 로그온 시 자동 시작(관리자 아니어도 현재 사용자 작업). 실행 시간 제한 없음, 죽으면 1분 뒤 재시작, 5분마다 생존 확인
  try {
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args_
    $trg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $trg2 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
    $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $name -Action $act -Trigger @($trg, $trg2) -Settings $set -RunLevel Limited -Force -ErrorAction Stop | Out-Null
    Write-Host "   자동 시작 작업 등록: $name — 로그온 시 + 5분마다 생존 확인(죽어 있으면 재시작)"
    Start-ScheduledTask -TaskName $name
  } catch {
    # 작업 스케줄러가 막혀 있으면 시작 프로그램 폴더의 .vbs 로 대체(창 없이 실행)
    $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) "$name.vbs"
    $line = 'CreateObject("WScript.Shell").Run "powershell.exe ' + ($args_ -replace '"', '""') + '", 0, False'
    [IO.File]::WriteAllText($vbs, $line, [Text.Encoding]::Unicode)
    Write-Host "   작업 등록 실패($($_.Exception.Message)) → 시작 프로그램에 등록: $vbs" -ForegroundColor Yellow
    Start-Process wscript.exe -ArgumentList "`"$vbs`""
  }
}

# ── ① 감시 스크립트 ──
$src = Join-Path $PSScriptRoot 'bitplus_watcher.ps1'
if (-not (Test-Path $src)) { throw "bitplus_watcher.ps1 이 같은 폴더에 없습니다: $src" }
New-Item -ItemType Directory -Force $Dest | Out-Null
Copy-Item $src (Join-Path $Dest 'bitplus_watcher.ps1') -Force
Write-Host "① 스크립트 복사: $Dest\bitplus_watcher.ps1"

$secret = Join-Path $Dest 'bitplus_watcher.secret'
if ($ResetPw) { RemoveSecret $secret; Write-Host "② 기존 bitbot 비밀번호 파일 삭제(-ResetPw)" }
if (-not (Test-Path $secret)) { $n = ReadSecret "동선관리 bitbot 계정 비밀번호" $secret; Write-Host "② bitbot 비밀번호 파일 저장(현재 사용자만 접근): $secret  ($n자)" }
else { Write-Host "② bitbot 비밀번호 파일 이미 있음: $secret  (다시 입력하려면 -ResetPw)" }

# 다른 에이전트 PC 목록 — 감시 스크립트(에이전트 확인)와 에이전트(우선순위)가 함께 읽는다
$peersFile = Join-Path $Dest 'bitplus_peers.txt'
if ($Peers.Trim()) {
  $list = @($Peers -split '[,\s]+' | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
  [IO.File]::WriteAllText($peersFile, ("# DB 에이전트가 있는 PC 의 IP (한 줄에 하나). 감시 스크립트는 이 중 하나라도 정상이면 캐스트로 bitIntake 에 쓰지 않는다`r`n" + ($list -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
  Write-Host "   에이전트 PC 목록 저장: $peersFile  ($($list -join ', '))"
} elseif (Test-Path $peersFile) { Write-Host "   에이전트 PC 목록 이미 있음: $peersFile  ($((@(Get-Content $peersFile | Where-Object { $_ -match '^\d' })) -join ', '))" }

if ($isAdmin) {
  if (-not (Get-NetFirewallRule -DisplayName 'BitPlus Watcher (TCP 9000)' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'BitPlus Watcher (TCP 9000)' -Direction Inbound -Protocol TCP -LocalPort 9000 -Action Allow -Profile Any -RemoteAddress LocalSubnet | Out-Null
  }
  Write-Host "③ 방화벽: TCP 9000 인바운드(같은 네트워크) 허용"
} else { Write-Host "③ (관리자 아님) 방화벽 규칙은 건너뜀 — 다른 PC의 캐스트가 안 오면 관리자 PowerShell에서 다시 실행" -ForegroundColor Yellow }

KillScript 'bitplus_watcher.ps1'   # 이전 수동 실행분 정리
Write-Host "④ 감시 스크립트:"
RegisterTask 'BitPlusWatcher' "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Dest\bitplus_watcher.ps1`" -Pc $Pc" (Join-Path $env:LOCALAPPDATA 'bitplus_watcher\watcher.log')

# ── ⑤ DB 에이전트 (-Agent) ──
if ($Agent) {
  $asrc = Join-Path $PSScriptRoot 'bit_db_agent.ps1'
  if (-not (Test-Path $asrc)) { throw "bit_db_agent.ps1 이 같은 폴더에 없습니다: $asrc" }
  Copy-Item $asrc (Join-Path $Dest 'bit_db_agent.ps1') -Force
  Write-Host "⑤ DB 에이전트 복사: $Dest\bit_db_agent.ps1  (bitbot 비밀번호는 감시 스크립트의 .secret 을 같이 씀)"
  $sqlSecret = Join-Path $Dest 'bit_db_agent.sql.secret'
  if ($ResetSqlPw) { RemoveSecret $sqlSecret; Write-Host "   기존 dongseon_ro 비밀번호 파일 삭제(-ResetSqlPw)" }
  if (-not (Test-Path $sqlSecret)) { $n = ReadSecret "비트 DB 읽기 전용 계정 dongseon_ro 비밀번호" $sqlSecret; Write-Host "   dongseon_ro 비밀번호 파일 저장: $sqlSecret  ($n자)" }
  else { Write-Host "   dongseon_ro 비밀번호 파일 이미 있음: $sqlSecret  (다시 입력하려면 -ResetSqlPw)" }
  if ($isAdmin) {
    if (-not (Get-NetFirewallRule -DisplayName 'BitPlus DB Agent (TCP 9001)' -ErrorAction SilentlyContinue)) {
      New-NetFirewallRule -DisplayName 'BitPlus DB Agent (TCP 9001)' -Direction Inbound -Protocol TCP -LocalPort 9001 -Action Allow -Profile Any -RemoteAddress LocalSubnet | Out-Null
    }
    Write-Host "   방화벽: TCP 9001 인바운드(같은 네트워크) 허용 — 다른 PC 가 이 에이전트의 상태를 묻는 포트"
  } else { Write-Host "   (관리자 아님) 9001 방화벽 규칙은 건너뜀 — 다른 PC 의 감시 스크립트가 이 에이전트를 못 보면 관리자 PowerShell 에서 다시 실행" -ForegroundColor Yellow }
  KillScript 'bit_db_agent.ps1'
  RegisterTask 'BitDbAgent' "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Dest\bit_db_agent.ps1`" -Pc `"DB-$Pc`" -Priority $Priority" (Join-Path $env:LOCALAPPDATA 'bit_db_agent\agent.log')
} elseif (Get-ScheduledTask BitDbAgent -ErrorAction SilentlyContinue) {
  Write-Host "⑤ (이 PC 에 DB 에이전트 작업이 이미 있음 — 스크립트를 갱신하려면 -Agent 를 붙여 실행)" -ForegroundColor DarkGray
}

Start-Sleep 6
$log = Join-Path $env:LOCALAPPDATA 'bitplus_watcher\watcher.log'
$tail = @(); if (Test-Path $log) { $tail = @(Get-Content $log -Tail 4) }
Write-Host "⑥ 감시 스크립트 시작됨 — 최근 로그:"; $tail | ForEach-Object { "   $_" }
if ($Agent) { $alog = Join-Path $env:LOCALAPPDATA 'bit_db_agent\agent.log'; if (Test-Path $alog) { Write-Host "   DB 에이전트 최근 로그:"; Get-Content $alog -Tail 4 | ForEach-Object { "   $_" } } }
if ($tail -match 'TOO_MANY_ATTEMPTS') {
  Write-Host ""
  Write-Host "⚠ Firebase 가 이 병원 IP의 로그인을 잠시 차단 중입니다(다른 PC의 잦은 실패 때문). 비밀번호 문제가 아닐 수 있습니다." -ForegroundColor Yellow
  Write-Host "  아무것도 안 해도 됩니다 — 감시 스크립트가 10분마다 다시 시도해 차단이 풀리면 스스로 연결됩니다. 비밀번호가 틀린 PC 가 있다면 그쪽을 -ResetPw 로 고치세요." -ForegroundColor Yellow
} elseif ($tail -match '로그인 실패') {
  Write-Host ""
  Write-Host "✖ Firebase 로그인 실패 — bitbot 비밀번호가 틀렸을 가능성이 큽니다." -ForegroundColor Red
  Write-Host "  고치기: 이 설치 스크립트를 -ResetPw 를 붙여 다시 실행하고 비밀번호를 다시 입력하세요:  bitplus_install.ps1 -Pc $Pc -ResetPw" -ForegroundColor Red
}

$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' } | ForEach-Object { $_.IPAddress }
Write-Host ""
Write-Host "▶ 이 PC IP: $($ips -join ', ')" -ForegroundColor Cyan
Write-Host "  · 접수 PC(환자접수를 하는 PC)라면 → 비트 환경설정 › 기타사항 › 전광판IP 세팅에 이 IP 등록 (구분: 접수BitCast). IP는 고정(또는 공유기 예약)으로."
Write-Host "  · 진료실 PC(외래진료실에서 처방만 적는 PC)라면 → 등록 불필요. 감시 스크립트는 열린 창(접수/외래진료실)을 보고 스스로 읽습니다."
if (Get-Process -Name BITDoctorOrder -ErrorAction SilentlyContinue) { Write-Host "  (지금 외래진료실 창이 열려 있음 → 처방 목록도 읽습니다)" }
Write-Host "  확인: 동선관리 상단 pill 에 '$Pc'$(if ($Agent) { " 와 'DB-$Pc'" }) 가 초록으로 뜨면 정상. 접수 PC는 환자 조회 시 로그에 '조회 기록', 접수 시 '전송: …' 또는 'DB 에이전트 정상 → 생략'."
Write-Host "  중지: Stop-ScheduledTask BitPlusWatcher$(if ($Agent) { ' / BitDbAgent' })   삭제: Unregister-ScheduledTask BitPlusWatcher -Confirm:`$false   로그: $log"
