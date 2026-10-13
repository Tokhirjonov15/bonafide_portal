# ─────────────────────────────────────────────────────────────
#  슬립 캡처 설치 (진료실 PC마다 1회) — 원장님이 쓰는 그 Windows 계정으로 로그온한 상태에서 실행
#
#    powershell -ExecutionPolicy Bypass -File slip_capture_install.ps1 -Pc 진료실1
#
#  하는 일: C:\bitplus 에 slip_capture.ps1 복사 → bitbot 비밀번호 파일 확인(감시 스크립트 설치 때 만든 것, 없으면 입력받음) →
#           로그온 시 자동 시작 작업 'SlipCapture' 등록(5분마다 확인 — 꺼져 있으면 다시 켬) → 지금 시작
#  화면 위 가운데에 작은 바가 뜬다: [주사 캡처]·[PT 캡처] + 비트 외래진료실의 지금 환자 이름·차트번호.
# ─────────────────────────────────────────────────────────────
param([Parameter(Mandatory = $true)][string]$Pc, [string]$Dest = 'C:\bitplus', [switch]$ResetPw)
$ErrorActionPreference = 'Stop'
$name = 'SlipCapture'
$src = Join-Path $PSScriptRoot 'slip_capture.ps1'
if (-not (Test-Path $src)) { throw "slip_capture.ps1 이 같은 폴더에 없습니다: $src" }
New-Item -ItemType Directory -Force $Dest | Out-Null

# 이미 떠 있으면 끈다(새 파일로 다시 시작하도록)
Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'slip_capture\.ps1' -and $_.CommandLine -notmatch 'slip_capture_install' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 600
Copy-Item $src (Join-Path $Dest 'slip_capture.ps1') -Force
Write-Host "① 스크립트 복사: $Dest\slip_capture.ps1"

$secret = Join-Path $Dest 'bitplus_watcher.secret'
if ($ResetPw -and (Test-Path $secret)) { icacls $secret /grant "$($env:USERNAME):F" | Out-Null; Remove-Item $secret -Force; Remove-Item (Join-Path $Dest 'slip_capture.token') -Force -ErrorAction SilentlyContinue }
if (-not (Test-Path $secret)) {
  Write-Host "   ※ 한/영 상태를 확인하고 입력하세요. 입력 중 글자는 보이지 않습니다." -ForegroundColor DarkGray
  $pw = Read-Host -AsSecureString "bitbot 비밀번호"
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($pw))
  if (-not $plain.Trim()) { throw "비밀번호가 비어 있습니다." }
  [IO.File]::WriteAllText($secret, $plain, (New-Object Text.UTF8Encoding $false))
  icacls $secret /inheritance:r /grant:r "$($env:USERNAME):M" | Out-Null
  Write-Host "② 비밀번호 저장: $secret"
} else { Write-Host "② 비밀번호 파일 있음(감시 스크립트와 같이 씀): $secret" }

$args_ = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$Dest\slip_capture.ps1`" -Pc `"$Pc`""
try {
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args_
  $trg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $trg2 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
  $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName $name -Action $act -Trigger @($trg, $trg2) -Settings $set -RunLevel Limited -Force -ErrorAction Stop | Out-Null
  Write-Host "③ 자동 시작 작업 등록: $name — 로그온 시 + 5분마다(꺼져 있으면 다시 켬)"
  Start-ScheduledTask -TaskName $name
} catch {
  $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) "$name.vbs"
  $line = 'CreateObject("WScript.Shell").Run "powershell.exe ' + ($args_ -replace '"', '""') + '", 0, False'
  [IO.File]::WriteAllText($vbs, $line, [Text.Encoding]::Unicode)
  Write-Host "③ 작업 등록 실패($($_.Exception.Message)) → 시작 프로그램에 등록: $vbs" -ForegroundColor Yellow
  Start-Process wscript.exe -ArgumentList "`"$vbs`""
}
Write-Host ""
Write-Host "완료 — 화면 위 가운데에 [캡처] 바가 뜹니다. 안 뜨면 로그: $env:LOCALAPPDATA\bitplus_watcher\slip_capture.log" -ForegroundColor Green
