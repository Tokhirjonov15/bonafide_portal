# 진료 녹음 받아쓰기 설치 (2026-10-12) — 진료실 PC 에서 rec_install.bat 이 이 파일을 내려받아 실행한다.
# 하는 일: ① 파이썬 확인(없으면 설치) ② 전용 폴더에 faster-whisper 설치 ③ 녹음 폴더(외장하드) 고르기
#          ④ 받아쓰기 모델 내려받기(약 1.6GB, 처음 한 번) ⑤ 로그인할 때 저절로 켜지게 등록하고 지금 켜기
$ErrorActionPreference = 'Stop'
$Base = 'https://bonafide-portal.seoulgijibae.workers.dev/rec'
$App  = Join-Path $env:LOCALAPPDATA 'rec_transcribe'
$Venv = Join-Path $App 'venv'
New-Item -ItemType Directory -Force $App | Out-Null
function Say($m) { Write-Host ''; Write-Host "▶ $m" -ForegroundColor Cyan }

Say '1/5 파이썬 확인'
$py = $null
foreach ($c in @('py -3.12', 'py -3', 'python')) {
  try { $v = & cmd /c "$c --version 2>&1"; if ($v -match 'Python 3\.(9|1[0-3])') { $py = $c; break } } catch {}
}
if (-not $py) {
  Say '파이썬이 없어 설치합니다 (몇 분 걸립니다)'
  $inst = Join-Path $env:TEMP 'python-3.12.7-amd64.exe'
  Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe' -OutFile $inst -UseBasicParsing
  Start-Process $inst -ArgumentList '/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_test=0' -Wait
  $py = 'py -3.12'
}
Write-Host "  파이썬: $py"

Say '2/5 받아쓰기 프로그램 설치 (faster-whisper)'
if (-not (Test-Path (Join-Path $Venv 'Scripts\python.exe'))) { & cmd /c "$py -m venv `"$Venv`"" }
$VPy  = Join-Path $Venv 'Scripts\python.exe'
$VPyw = Join-Path $Venv 'Scripts\pythonw.exe'
& $VPy -m pip install --upgrade pip --quiet
& $VPy -m pip install --upgrade 'faster-whisper>=1.1' 'av<16' --quiet   # av 16 이상은 faster-whisper 와 맞지 않는다 (2026-10-12 시험)
Invoke-WebRequest "$Base/rec_transcribe.py" -OutFile (Join-Path $App 'rec_transcribe.py') -UseBasicParsing
$Script = Join-Path $App 'rec_transcribe.py'

Say '3/5 녹음 폴더 고르기 — 동선관리 [녹음]에서 고른 외장하드 폴더와 같은 곳을 고르세요'
Add-Type -AssemblyName System.Windows.Forms
$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
$dlg.Description = '진료 녹음이 저장되는 폴더 (동선관리 [녹음]에서 고른 외장하드 폴더)'
$cfg = Join-Path $App 'folder.txt'
if (Test-Path $cfg) { $dlg.SelectedPath = (Get-Content $cfg -Encoding UTF8 -TotalCount 1) }
if ($dlg.ShowDialog() -ne 'OK') { Write-Host '폴더를 고르지 않아 멈춥니다. 다시 실행해 주세요.' -ForegroundColor Red; exit 1 }
$Dir = $dlg.SelectedPath
Set-Content $cfg $Dir -Encoding UTF8
Write-Host "  폴더: $Dir"

Say '4/5 받아쓰기 모델 내려받기 (약 1.6GB — 인터넷 속도에 따라 몇 분)'
& $VPy $Script --warmup

Say '5/5 로그인할 때 저절로 켜지게 등록하고 지금 켜기'
$name = '진료녹음 받아쓰기'
Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe'" | Where-Object { $_.CommandLine -like '*rec_transcribe.py*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
$act  = New-ScheduledTaskAction -Execute $VPyw -Argument "`"$Script`" --dir `"$Dir`"" -WorkingDirectory $App
$trg  = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$set  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $name -Action $act -Trigger $trg -Settings $set -Description '동선관리 진료 녹음(.webm)을 글(.txt)로 바꾼다 — rec_transcribe.py' | Out-Null
Start-ScheduledTask -TaskName $name

Write-Host ''
Write-Host '설치 끝!' -ForegroundColor Green
Write-Host '확인: 동선관리 [녹음] → [5초 시험 녹음] 을 하고 2~3분 뒤 녹음 폴더에 "녹음 시험.txt" 가 생기면 성공입니다.'
Write-Host "기록: $App\log.txt"
Read-Host '엔터를 누르면 닫힙니다'
