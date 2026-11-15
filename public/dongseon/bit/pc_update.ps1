# pc_update.ps1 - one-time update of the Bit watcher (v3.9+) and DB agent (db2.8+) on a clinic PC (2026-11-15)
#
# Both versions update THEMSELVES from the site afterwards, so this is the last manual round.
# Run on each PC as the Windows user that uses Bit (normal PowerShell is enough; the tasks are per-user):
#   [Net.ServicePointManager]::SecurityProtocol='Tls12'; iex (irm https://bonafide-portal.seoulgijibae.workers.dev/dongseon/bit/update.txt)
#
# Finds the installed files through the scheduled tasks BitPlusWatcher / BitDbAgent (or the Startup .vbs fallback),
# downloads the published version, checks sha256 + syntax + version marker, keeps the old file as .bak,
# restarts, and confirms from the log that the new version started. Secrets / settings / task arguments are untouched.
# ASCII only on purpose (PowerShell 5.1 reads BOM-less files as ANSI).
param(
  [string]$Base = 'https://bonafide-portal.seoulgijibae.workers.dev/dongseon/bit/',
  [string]$TaskSuffix = '',                 # test only: look for tasks BitPlusWatcher<suffix> / BitDbAgent<suffix>
  [string]$LogRoot = $env:LOCALAPPDATA      # test only
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$BASE = $Base.TrimEnd('/') + '/'
$fails = 0
function OK($m)  { Write-Host "  [OK]   $m" -ForegroundColor Green }
function BAD($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fails++ }
function INFO($m){ Write-Host "  $m" }

$items = @(
  @{ name = 'Watcher';  task = "BitPlusWatcher$TaskSuffix"; file = 'bitplus_watcher.ps1'; json = 'watcher.json'; re = "\`$MyVer = '([^']+)'"; log = (Join-Path $LogRoot 'bitplus_watcher\watcher.log'); must = $true },
  @{ name = 'DB agent'; task = "BitDbAgent$TaskSuffix";     file = 'bit_db_agent.ps1';    json = 'agent.json';   re = "\`$VER = '([^']+)'";   log = (Join-Path $LogRoot 'bit_db_agent\agent.log');     must = $false }
)

function FindInstalled($it) {
  $t = Get-ScheduledTask -TaskName $it.task -ErrorAction SilentlyContinue
  if ($t) {
    $a = [string]($t.Actions | Select-Object -First 1).Arguments
    $m = [regex]::Match($a, '-File\s+"([^"]+)"'); if (-not $m.Success) { $m = [regex]::Match($a, '-File\s+(\S+)') }
    if ($m.Success -and (Test-Path $m.Groups[1].Value)) { return @{ path = $m.Groups[1].Value; how = 'task' } }
  }
  $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) "$($it.task).vbs"
  if (Test-Path $vbs) {
    $v = [IO.File]::ReadAllText($vbs)
    $m = [regex]::Match($v, '-File\s+""([^"]+)""')
    if ($m.Success -and (Test-Path $m.Groups[1].Value)) { return @{ path = $m.Groups[1].Value; how = 'vbs'; vbs = $vbs } }
  }
  return $null
}
function KillScript($path) {   # only the instance running THIS installed file (full path)
  $pat = '-File\s+"?' + [regex]::Escape($path)
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $pat } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
  Start-Sleep -Milliseconds 800
}
function StartedWith($log, $ver, $since) {
  if (-not (Test-Path $log)) { return $false }
  foreach ($l in (Get-Content $log -Tail 15 -Encoding UTF8)) {
    if ($l.Length -ge 19 -and $l.Contains($ver)) {
      try { if ([DateTime]::ParseExact($l.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', $null) -ge $since) { return $true } } catch {}
    }
  }
  return $false
}

Write-Host ""
Write-Host "Bit watcher / DB agent update - PC user: $env:USERNAME on $env:COMPUTERNAME" -ForegroundColor Cyan
foreach ($it in $items) {
  Write-Host ""
  Write-Host "== $($it.name)" -ForegroundColor Cyan
  $ins = FindInstalled $it
  if (-not $ins) {
    if ($it.must) { BAD "not installed for this Windows user (task $($it.task) not found) - log on as the Bit user and run again" }
    else { INFO "(not on this PC - skipped)" }
    continue
  }
  $path = $ins.path
  $cur = ''; $mm = [regex]::Match([IO.File]::ReadAllText($path), $it.re); if ($mm.Success) { $cur = $mm.Groups[1].Value }
  try { $j = Invoke-RestMethod -TimeoutSec 20 -Uri ($BASE + $it.json + '?t=' + [DateTime]::Now.Ticks) } catch { BAD "cannot reach the site: $($_.Exception.Message)"; continue }
  INFO "installed: $path  ($cur)   site: $($j.ver)"
  if ($cur -ne $j.ver) {
    $tmp = "$path.new"
    try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri ($BASE + $it.file + '?v=' + $j.ver) -OutFile $tmp } catch { BAD "download failed: $($_.Exception.Message)"; continue }
    $hash = (Get-FileHash $tmp -Algorithm SHA256).Hash
    if ($hash -ne ([string]$j.sha256).ToUpper()) { Remove-Item $tmp -Force; BAD "checksum mismatch - not changed"; continue }
    $txt = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8); $pe = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($txt, [ref]$null, [ref]$pe)
    $vm = [regex]::Match($txt, $it.re)
    if ($pe.Count -or -not $vm.Success -or $vm.Groups[1].Value -ne $j.ver) { Remove-Item $tmp -Force; BAD "downloaded file is not valid - not changed"; continue }
    KillScript $path
    Copy-Item $path "$path.bak" -Force
    Move-Item $tmp $path -Force
    OK "file replaced ($cur -> $($j.ver)), old copy: $path.bak"
  } else { OK "file already $($j.ver)" }

  # (re)start and confirm the new version is the one running
  $since = (Get-Date).AddSeconds(-1)
  if (-not (StartedWith $it.log $j.ver ((Get-Date).AddMinutes(-60))) -or $cur -ne $j.ver) {
    KillScript $path
    $since = (Get-Date).AddSeconds(-1)
    try {
      if ($ins.how -eq 'task') { Start-ScheduledTask -TaskName $it.task } else { Start-Process wscript.exe -ArgumentList "`"$($ins.vbs)`"" }
    } catch { BAD "could not start: $($_.Exception.Message)"; continue }
    $ok = $false; for ($i = 0; $i -lt 20 -and -not $ok; $i++) { Start-Sleep 1; $ok = StartedWith $it.log $j.ver $since }
    if ($ok) { OK "running $($j.ver) (updates itself from now on)" } else { BAD "did not start with $($j.ver) - check $($it.log)" }
  } else { OK "already running $($j.ver)" }
}
Write-Host ""
if ($fails -eq 0) { Write-Host "PASS" -ForegroundColor Green } else { Write-Host "FAIL ($fails) - send a photo of this window" -ForegroundColor Red }
