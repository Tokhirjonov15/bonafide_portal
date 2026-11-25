# rx_doctor.ps1 - switch on the "prescription check" alert on a DOCTOR's PC (2026-11-25)
#
# The doctor does not use the dongseon board. On a PC where the capture bar is already installed
# (examination-room PCs), this creates the flag file rx_doctor.on next to the bar, updates the bar to the
# published version (c1.4+) and restarts it. After that, when a nurse sends a check request, a window with
# the picture of the changed prescription opens on this PC with a [confirm] button.
#
# Run once on the doctor's PC, as the Windows user that uses Bit:
#   [Net.ServicePointManager]::SecurityProtocol='Tls12'; iex (irm https://bonafide-portal.seoulgijibae.workers.dev/dongseon/bit/rx-doctor.txt)
# (If the bar on that PC runs with administrator rights - the prescription-check PC - use an ADMIN PowerShell.)
# To switch it off: delete rx_doctor.on in the bar's folder; the bar picks that up at its next start.
# Nothing in Bit is clicked or changed. ASCII only on purpose (PowerShell 5.1 reads BOM-less downloads as ANSI).
param([string]$Base = 'https://bonafide-portal.seoulgijibae.workers.dev/dongseon/bit/')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$BASE = $Base.TrimEnd('/') + '/'
$fails = 0
function OK($m)  { Write-Host "  [OK]   $m" -ForegroundColor Green }
function BAD($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fails++ }
function INFO($m){ Write-Host "  $m" }
Write-Host "Doctor-side prescription check - PC: $env:COMPUTERNAME  user: $env:USERNAME" -ForegroundColor Cyan

# ---- 1. where is the capture bar installed ----
$me = ''; $how = ''
$t = Get-ScheduledTask -TaskName 'SlipCapture' -ErrorAction SilentlyContinue
if ($t) {
  $a = [string]($t.Actions | Select-Object -First 1).Arguments
  $m = [regex]::Match($a, '-File\s+"([^"]+)"'); if (-not $m.Success) { $m = [regex]::Match($a, '-File\s+(\S+)') }
  if ($m.Success -and (Test-Path $m.Groups[1].Value)) { $me = $m.Groups[1].Value; $how = 'task' }
}
$vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'SlipCapture.vbs'
if (-not $me -and (Test-Path $vbs)) {
  $m = [regex]::Match([IO.File]::ReadAllText($vbs), '-File\s+""([^"]+)""')
  if ($m.Success -and (Test-Path $m.Groups[1].Value)) { $me = $m.Groups[1].Value; $how = 'vbs' }
}
if (-not $me -and (Test-Path 'C:\bitplus\slip_capture.ps1')) { $me = 'C:\bitplus\slip_capture.ps1'; $how = 'file' }
if (-not $me) { BAD "the capture bar is not installed on this PC (no SlipCapture task). Install the capture bar first."; return }
$dir = Split-Path $me
OK "capture bar: $me"

# ---- 2. download the published bar and verify it ----
$j = Invoke-RestMethod -TimeoutSec 20 -Uri ($BASE + 'capture.json?t=' + [DateTime]::Now.Ticks)
$tmp = Join-Path $dir 'slip_capture.new'
try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri ($BASE + 'slip_capture.ps1?v=' + $j.ver + '&t=' + [DateTime]::Now.Ticks) -OutFile $tmp }
catch { BAD ("cannot write into $dir (" + $_.Exception.Message + ") - if the bar runs as administrator, use an ADMIN PowerShell"); return }
if ((Get-FileHash $tmp -Algorithm SHA256).Hash -ne ([string]$j.sha256).ToUpper()) { Remove-Item $tmp -Force; BAD "downloaded capture bar does not match its checksum - try again in a minute"; return }
$txt = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8); $pe = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($txt, [ref]$null, [ref]$pe)
if ($pe.Count) { Remove-Item $tmp -Force; BAD "downloaded capture bar has a syntax error"; return }
if ($txt -notmatch 'rx_doctor\.on') { Remove-Item $tmp -Force; BAD "published capture bar ($($j.ver)) is too old - it has no doctor alert"; return }
OK "capture bar $($j.ver) downloaded and verified"

# ---- 3. stop the running bar, replace the file, create the flag ----
$pat = '-File\s+"?' + [regex]::Escape($me)
$left = 0
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $pat } |
  ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { $left++ } }
if ($left) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue; BAD "the running bar could not be stopped (it runs as administrator) - run this again in an ADMIN PowerShell"; return }
Start-Sleep -Milliseconds 800
Copy-Item $me "$me.bak" -Force -ErrorAction SilentlyContinue
Move-Item $tmp $me -Force
Set-Content -Path (Join-Path $dir 'rx_doctor.on') -Value ("on " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -Encoding ASCII
OK "bar updated, doctor alert switched on (rx_doctor.on)"

# ---- 4. start it again and confirm from its log ----
$log = Join-Path $env:LOCALAPPDATA 'bitplus_watcher\slip_capture.log'
$since = Get-Date
if ($how -eq 'task') { Start-ScheduledTask -TaskName 'SlipCapture' }
elseif ($how -eq 'vbs') { Start-Process wscript.exe -ArgumentList "`"$vbs`"" }
else { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$me`"" }
$up = $false
for ($i = 0; $i -lt 20 -and -not $up; $i++) {
  Start-Sleep 1
  if (Test-Path $log) { foreach ($l in (Get-Content $log -Tail 8 -Encoding UTF8)) {
    if ($l.Length -ge 19 -and $l.Contains([string]$j.ver)) { try { if ([DateTime]::ParseExact($l.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', $null) -ge $since.AddSeconds(-2)) { $up = $true } } catch {} } } }
}
if ($up) { OK "capture bar $($j.ver) is running - the bar now has a grey button at the right of the capture buttons" }
else { BAD "the bar did not report a start within 20 s (log: $log)"; if (Test-Path $log) { Get-Content $log -Tail 5 -Encoding UTF8 | ForEach-Object { INFO "  $_" } } }

Write-Host ""
if ($fails -eq 0) { Write-Host "PASS - prescription check requests will now pop up on this PC" -ForegroundColor Green } else { Write-Host "FAIL - $fails problem(s); send the [FAIL] lines to the developer" -ForegroundColor Red }
