# ─────────────────────────────────────────────────────────────
#  진료 녹음 설치 (원장님 진료실 PC, 1회) — 원장님이 쓰는 그 Windows 계정으로 로그온한 상태에서 (관리자 실행 아님)
#
#    powershell -ExecutionPolicy Bypass -File clinic_rec_install.ps1 -Pc 진료실1
#    (USB 의 '진료실PC_녹음설치.bat' 이 이 명령을 대신 실행한다)
#
#  하는 일: ① C:\bitplus 에 clinic_rec.ps1 복사 ② 녹음 폴더(외장하드) 고르기 ③ 마이크 3초 시험
#           ④ 로그온 시 자동 시작 작업 'ClinicRec' 등록(5분마다 확인 — 꺼져 있으면 다시 켬) → 지금 시작
#  받아쓰기: 기본은 OpenAI(저장하면 자동으로 포털 서버로 보내 받아씀 — 이 PC 에 설치할 것 없음). 이 PC 에서 무료로 하려면 rec_install.bat 으로 받아쓰기 프로그램을 따로 설치
# ─────────────────────────────────────────────────────────────
param([Parameter(Mandatory = $true)][string]$Pc, [string]$Dest = 'C:\bitplus', [string]$Folder = '', [switch]$NoTask)
$ErrorActionPreference = 'Stop'
$name = 'ClinicRec'
$src = Join-Path $PSScriptRoot 'clinic_rec.ps1'
if (-not (Test-Path $src)) { throw "clinic_rec.ps1 이 같은 폴더에 없습니다: $src" }
New-Item -ItemType Directory -Force $Dest | Out-Null
function Say($m) { Write-Host ''; Write-Host "▶ $m" -ForegroundColor Cyan }

Say '1/4 녹음 프로그램 복사'
if (-not $NoTask) {
  Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  # 떠 있는 녹음 프로그램은 창 닫기 신호로 끈다(녹음 중이면 저장하고 끝남) → 5초 뒤에도 남아 있으면 강제로
  $old = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'clinic_rec\.ps1' -and $_.CommandLine -notmatch 'clinic_rec_install' })
  foreach ($o in $old) { & taskkill.exe /PID $o.ProcessId | Out-Null }
  if ($old.Count) { Start-Sleep -Seconds 5; foreach ($o in $old) { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue } }
}
Copy-Item $src (Join-Path $Dest 'clinic_rec.ps1') -Force
Write-Host "   $Dest\clinic_rec.ps1"

Say '2/4 녹음 폴더(외장하드) 고르기'
$dirFile = Join-Path $Dest 'clinic_rec.dir'
if (-not $Folder) {
  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = '진료 녹음을 저장할 폴더 (외장하드) — 예전 어시 PC 에서 쓰던 녹음 폴더'
  $prev = ''
  if (Test-Path $dirFile) { $prev = ([string](Get-Content $dirFile -Encoding UTF8 -TotalCount 1)).Trim() }
  if (-not $prev) { $rt = Join-Path $env:LOCALAPPDATA 'rec_transcribe\folder.txt'; if (Test-Path $rt) { $prev = ([string](Get-Content $rt -Encoding UTF8 -TotalCount 1)).Trim() } }
  if ($prev -and (Test-Path -LiteralPath $prev)) { $dlg.SelectedPath = $prev }
  if ($dlg.ShowDialog() -ne 'OK') { Write-Host '폴더를 고르지 않아 멈춥니다. 외장하드를 꽂고 다시 실행해 주세요.' -ForegroundColor Red; exit 1 }
  $Folder = $dlg.SelectedPath
}
if (-not (Test-Path -LiteralPath $Folder)) { Write-Host "폴더가 없습니다: $Folder" -ForegroundColor Red; exit 1 }
[IO.File]::WriteAllText($dirFile, $Folder, (New-Object Text.UTF8Encoding $true))
# 쓰기 시험
$probe = Join-Path $Folder '녹음 쓰기 시험.tmp'
try { [IO.File]::WriteAllText($probe, 'ok'); Remove-Item -LiteralPath $probe -Force; Write-Host "   폴더: $Folder (쓰기 가능)" }
catch { Write-Host "그 폴더에 쓸 수 없습니다: $Folder — $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

Say '3/4 마이크 시험 (3초)'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $Dest 'clinic_rec.ps1') -Test
$micOk = ($LASTEXITCODE -eq 0)
if (-not $micOk) { Write-Host '   ※ 마이크를 확인한 뒤에도 설치는 계속합니다 — 마이크를 고치고 이 설치를 한 번 더 실행하면 다시 시험합니다.' -ForegroundColor Yellow }

if ($NoTask) { Write-Host ''; Write-Host '(시험 설치 — 자동 시작 작업은 등록하지 않음)' -ForegroundColor DarkGray; exit 0 }
Say '4/4 로그온 때 저절로 켜지게 등록하고 지금 켜기'
$args_ = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$Dest\clinic_rec.ps1`" -Pc `"$Pc`""
try {
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args_
  $trg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $trg2 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
  $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName $name -Action $act -Trigger @($trg, $trg2) -Settings $set -RunLevel Limited -Force -ErrorAction Stop | Out-Null
  Start-ScheduledTask -TaskName $name
  Write-Host "   작업 '$name' 등록 — 로그온 시 + 5분마다(꺼져 있으면 다시 켬)"
} catch {
  $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) "$name.vbs"
  $line = 'CreateObject("WScript.Shell").Run "powershell.exe ' + ($args_ -replace '"', '""') + '", 0, False'
  [IO.File]::WriteAllText($vbs, $line, [Text.Encoding]::Unicode)
  Write-Host "   작업 등록 실패($($_.Exception.Message)) → 시작 프로그램에 등록: $vbs" -ForegroundColor Yellow
  Start-Process wscript.exe -ArgumentList "`"$vbs`""
}
Write-Host ''
Write-Host '설치 끝!' -ForegroundColor Green
Write-Host '· 화면 오른쪽 아래 알림 영역(^ 를 누르면 보임)에 동그라미 아이콘: 회색 = 대기, 빨강 = 녹음 중'
Write-Host '· 외래진료실에서 환자를 불러 3초 뒤 녹음이 시작되고, 다른 환자를 부르면 앞 환자 녹음이 저장됩니다'
Write-Host "· 기록: $env:LOCALAPPDATA\bitplus_watcher\clinic_rec.log"
if (-not $micOk) { Write-Host '· 마이크 시험이 통과하지 않았습니다 — 위 안내대로 마이크를 확인해 주세요' -ForegroundColor Yellow }
