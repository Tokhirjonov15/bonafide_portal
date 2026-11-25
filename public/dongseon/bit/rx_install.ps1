# rx_install.ps1 - turn THIS PC into the "prescription check" PC (2026-11-25)
#
# Installs the capture bar (slip_capture.ps1, c1.3+) next to the Bit watcher and switches on its
# [request doctor's check] button (flag file rx_approve.on). The bar is registered to run with the
# highest privileges, because the Bit outpatient program on this PC runs as administrator and a
# normal-privilege program cannot press its buttons (needed later for "approve -> save automatically").
#
# Run ONCE on that PC, as the Windows user that uses Bit, in an ADMIN PowerShell:
#   [Net.ServicePointManager]::SecurityProtocol='Tls12'; iex (irm https://bonafide-portal.seoulgijibae.workers.dev/dongseon/bit/rx-setup.txt)
#
# If the Bit watcher is installed on this PC its password file is reused; otherwise the dongseon 'bitbot' password is asked once (checked by signing in).
# Re-running is safe. To switch the button off again: delete rx_approve.on in the install folder and restart the bar.
# Nothing in Bit is clicked or changed by this installer.
# ASCII only on purpose (PowerShell 5.1 reads BOM-less downloads as ANSI).
param(
  [string]$Base = 'https://bonafide-portal.seoulgijibae.workers.dev/dongseon/bit/',
  [string]$Dir = ''                      # install folder; default: where the watcher is installed, else C:\bitplus
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$BASE = $Base.TrimEnd('/') + '/'
$fails = 0
function OK($m)  { Write-Host "  [OK]   $m" -ForegroundColor Green }
function BAD($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fails++ }
function INFO($m){ Write-Host "  $m" }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "FAIL: open PowerShell with 'Run as administrator' and run again." -ForegroundColor Red; return }
Write-Host "Prescription-check PC setup - PC: $env:COMPUTERNAME  user: $env:USERNAME" -ForegroundColor Cyan

# ---- 1. where is the watcher installed ----
function WatcherDir() {
  $t = Get-ScheduledTask -TaskName 'BitPlusWatcher' -ErrorAction SilentlyContinue
  if ($t) {
    $a = [string]($t.Actions | Select-Object -First 1).Arguments
    $m = [regex]::Match($a, '-File\s+"([^"]+)"'); if (-not $m.Success) { $m = [regex]::Match($a, '-File\s+(\S+)') }
    if ($m.Success -and (Test-Path $m.Groups[1].Value)) { return (Split-Path $m.Groups[1].Value) }
  }
  $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'BitPlusWatcher.vbs'
  if (Test-Path $vbs) {
    $m = [regex]::Match([IO.File]::ReadAllText($vbs), '-File\s+""([^"]+)""')
    if ($m.Success -and (Test-Path $m.Groups[1].Value)) { return (Split-Path $m.Groups[1].Value) }
  }
  if (Test-Path 'C:\bitplus\bitplus_watcher.secret') { return 'C:\bitplus' }
  return ''
}
if (-not $Dir) { $Dir = WatcherDir }
if (-not $Dir) { $Dir = 'C:\bitplus'; INFO "the Bit watcher is not installed here - using $Dir" }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$secret = Join-Path $Dir 'bitplus_watcher.secret'
if (-not (Test-Path $secret)) {
  # no watcher on this PC: ask for the dongseon 'bitbot' password once, check it by signing in, then save it like the watcher installer does
  INFO "bitbot paroli kerak (dongseon 'bitbot' hisobi). Yozayotganda ekranda ko'rinmaydi."
  $okPw = $false
  for ($try = 0; $try -lt 3 -and -not $okPw; $try++) {
    $pw = Read-Host -AsSecureString '  bitbot paroli'
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($pw))
    if (-not $plain.Trim()) { INFO 'bo`sh - qayta kiriting'; continue }
    try {
      $body = @{ email = 'uc8feac453b1a01cc028b072a@bonafide.app'; password = $plain; returnSecureToken = $true } | ConvertTo-Json -Compress
      $null = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=AIzaSyDBj3z-Qj9DyT1ZgDNps1-Yp9ZBopeWr0w' -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
      [IO.File]::WriteAllText($secret, $plain, (New-Object Text.UTF8Encoding $false))
      & icacls $secret /inheritance:r /grant:r "$($env:USERNAME):M" '*S-1-5-32-544:F' | Out-Null
      $okPw = $true; OK 'bitbot paroli to`g`ri - saqlandi'
    } catch { INFO 'parol noto`g`ri yoki internet yo`q - qayta urinib ko`ring' }
    $plain = $null
  }
  if (-not $okPw) { BAD 'bitbot paroli tasdiqlanmadi'; return }
} else { OK 'password file found (shared with the watcher)' }
OK "install folder: $Dir"

# ---- 2. download the capture bar and verify it ----
$j = Invoke-RestMethod -TimeoutSec 20 -Uri ($BASE + 'capture.json?t=' + [DateTime]::Now.Ticks)
$tmp = Join-Path $Dir 'slip_capture.new'
Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri ($BASE + 'slip_capture.ps1?v=' + $j.ver + '&t=' + [DateTime]::Now.Ticks) -OutFile $tmp
if ((Get-FileHash $tmp -Algorithm SHA256).Hash -ne ([string]$j.sha256).ToUpper()) { Remove-Item $tmp -Force; BAD "downloaded capture bar does not match its checksum - try again in a minute"; return }
$txt = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8); $pe = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($txt, [ref]$null, [ref]$pe)
if ($pe.Count) { Remove-Item $tmp -Force; BAD "downloaded capture bar has a syntax error"; return }
if ($txt -notmatch 'rx_approve\.on') { Remove-Item $tmp -Force; BAD "published capture bar ($($j.ver)) is too old - it has no doctor-check button"; return }
OK "capture bar $($j.ver) downloaded and verified"

# ---- 3. stop the running bar, put the new file and the flag in place ----
$me = Join-Path $Dir 'slip_capture.ps1'
Stop-ScheduledTask -TaskName 'SlipCapture' -ErrorAction SilentlyContinue
$pat = '-File\s+"?' + [regex]::Escape($me)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $pat } |
  ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
Start-Sleep -Milliseconds 800
if (Test-Path $me) { Copy-Item $me "$me.bak" -Force -ErrorAction SilentlyContinue }
Move-Item $tmp $me -Force
Set-Content -Path (Join-Path $Dir 'rx_approve.on') -Value ("on " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -Encoding ASCII
OK "capture bar installed, doctor-check button switched on (rx_approve.on)"

# ---- 4. scheduled task: at logon + every 5 min, highest privileges, this user ----
$who = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$arg = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$me`""
try {
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
  $t1 = New-ScheduledTaskTrigger -AtLogOn -User $who
  $t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
  $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  $pri = New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName 'SlipCapture' -Action $act -Trigger @($t1, $t2) -Settings $set -Principal $pri -Force | Out-Null
  $old = Join-Path ([Environment]::GetFolderPath('Startup')) 'SlipCapture.vbs'
  if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
  OK "task SlipCapture registered for $who (highest privileges)"
} catch { BAD ("task: " + $_.Exception.Message); return }

# ---- 5. start it and confirm from its log ----
$log = Join-Path $env:LOCALAPPDATA 'bitplus_watcher\slip_capture.log'
$since = Get-Date
Start-ScheduledTask -TaskName 'SlipCapture'
$up = $false
for ($i = 0; $i -lt 20 -and -not $up; $i++) {
  Start-Sleep 1
  if (Test-Path $log) { foreach ($l in (Get-Content $log -Tail 8 -Encoding UTF8)) {
    if ($l.Length -ge 19 -and $l.Contains([string]$j.ver)) { try { if ([DateTime]::ParseExact($l.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', $null) -ge $since.AddSeconds(-2)) { $up = $true } } catch {} } } }
}
if ($up) { OK "capture bar $($j.ver) is running - look at the top of the screen: there is an orange button on the bar" }
else { BAD "the bar did not report a start within 20 s (log: $log)"; if (Test-Path $log) { Get-Content $log -Tail 5 -Encoding UTF8 | ForEach-Object { INFO "  $_" } } }

Write-Host ""
if ($fails -eq 0) { Write-Host "PASS - this PC is now the prescription-check PC" -ForegroundColor Green } else { Write-Host "FAIL - $fails problem(s); send the [FAIL] lines to the developer" -ForegroundColor Red }
