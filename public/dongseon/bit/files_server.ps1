# files_server.ps1 - dongseon patient-photo store on the clinic server (2026-11-15)
#
# Runs on the Bit server (DESKTOP-TCEAQMT, 192.168.0.250) as SYSTEM via scheduled task 'DongseonFiles'.
# Only reachable through Cloudflare Tunnel (cloudflared -> http://127.0.0.1:8787). Requests from any
# non-loopback address are refused, and every request must carry the shared key (header x-files-key)
# that the Cloudflare Worker holds as secret FILES_KEY.
#
#   GET    /health          -> {"ok":true,"ver":..,"freeGB":..,"canWrite":..}
#   PUT    /f/<path>        -> store file (atomic: temp file + move). 507 when the disk is too full.
#   GET    /f/<path>        -> file bytes
#   DELETE /f/<path>        -> moves the file to <root>\_trash\yyyyMMdd\ (never hard-deletes)
#
# Safety for the Bit server: process priority BelowNormal; writes stop when free space on the store
# drive drops under max(MinFreeGB, MinFreePct % of the drive), so the disk can never be filled.
# ASCII only on purpose (PowerShell 5.1 reads BOM-less files as ANSI).
param(
  [string]$Root = '',                                   # e.g. D:\dongseon_files (default: from config.json)
  [int]$Port = 8787,
  [string]$ConfigDir = 'C:\dongseon_files_srv',
  [string]$Prefix = ''                                  # test only (e.g. http://localhost:8787/); default http://+:<Port>/
)
$ErrorActionPreference = 'Stop'
$VER = 'fs1.1'

$cfgPath = Join-Path $ConfigDir 'config.json'
$keyPath = Join-Path $ConfigDir 'files.key'
$cfg = @{ MinFreeGB = 30; MinFreePct = 10; MaxMB = 20 }
if (Test-Path $cfgPath) {
  $j = Get-Content $cfgPath -Raw | ConvertFrom-Json
  foreach ($p in $j.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
}
if (-not $Root) { $Root = [string]$cfg.Root }
if (-not $Root) { throw "Root folder is not set (config.json Root)." }
if (-not (Test-Path $keyPath)) { throw "Key file missing: $keyPath" }
$KEY = (Get-Content $keyPath -TotalCount 1).Trim()
if ($KEY.Length -lt 32) { throw "Key too short." }

New-Item -ItemType Directory -Force -Path $Root, (Join-Path $Root '_logs'), (Join-Path $Root '_tmp'), (Join-Path $Root '_trash') | Out-Null
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

$LOG = Join-Path $Root '_logs'
function Log($msg) {
  $f = Join-Path $LOG ('files_' + (Get-Date -Format 'yyyyMM') + '.log')
  try { Add-Content -Path $f -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg) -Encoding UTF8 } catch {}
}
function DriveInfo {
  $d = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($Root))
  $free = [double]$d.AvailableFreeSpace; $tot = [double]$d.TotalSize
  $need = [Math]::Max([double]$cfg.MinFreeGB * 1GB, $tot * [double]$cfg.MinFreePct / 100)
  [pscustomobject]@{ freeGB = [Math]::Round($free / 1GB, 1); totalGB = [Math]::Round($tot / 1GB, 1); canWrite = ($free -gt $need); needGB = [Math]::Round($need / 1GB, 1) }
}
function KeyOk($given) {
  if (-not $given -or $given.Length -ne $KEY.Length) { return $false }
  $diff = 0; for ($i = 0; $i -lt $KEY.Length; $i++) { $diff = $diff -bor ([int][char]$given[$i] -bxor [int][char]$KEY[$i]) }
  return ($diff -eq 0)
}
$PATH_RE = '^(patient_photos|rx_captures)/[A-Za-z0-9_-]{1,40}/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$'
$CT = @{ jpg = 'image/jpeg'; jpeg = 'image/jpeg'; png = 'image/png'; webp = 'image/webp' }

function Send($ctx, [int]$code, $obj) {
  $b = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
  $ctx.Response.StatusCode = $code; $ctx.Response.ContentType = 'application/json; charset=utf-8'
  $ctx.Response.ContentLength64 = $b.Length; $ctx.Response.OutputStream.Write($b, 0, $b.Length)
}

$L = New-Object System.Net.HttpListener
if (-not $Prefix) { $Prefix = "http://+:$Port/" }
$L.Prefixes.Add($Prefix)      # '+' so cloudflared's Host header (files.bonafide-portal.com) is accepted; non-loopback callers are refused below
$L.Start()
Log "start $VER root=$Root port=$Port"

while ($L.IsListening) {
  $ctx = $null
  try {
    $ctx = $L.GetContext()
    $req = $ctx.Request
    if (-not [System.Net.IPAddress]::IsLoopback($req.RemoteEndPoint.Address)) { Send $ctx 403 @{ ok = $false; error = 'local only' }; continue }
    if (-not (KeyOk $req.Headers['x-files-key'])) { Send $ctx 401 @{ ok = $false; error = 'key' }; continue }
    $p = $req.Url.AbsolutePath
    if ($p -eq '/health') {
      $d = DriveInfo
      Send $ctx 200 @{ ok = $true; ver = $VER; freeGB = $d.freeGB; totalGB = $d.totalGB; canWrite = $d.canWrite; needGB = $d.needGB }
      continue
    }
    if (-not $p.StartsWith('/f/')) { Send $ctx 404 @{ ok = $false; error = 'not found' }; continue }
    $rel = [Uri]::UnescapeDataString($p.Substring(3))
    if ($rel -notmatch $PATH_RE) { Send $ctx 400 @{ ok = $false; error = 'bad path' }; continue }
    $ext = [System.IO.Path]::GetExtension($rel).TrimStart('.').ToLower()
    $full = Join-Path $Root ($rel -replace '/', '\')
    $by = [string]$req.Headers['x-files-by']

    switch ($req.HttpMethod) {
      'PUT' {
        $d = DriveInfo
        if (-not $d.canWrite) { Log "REFUSE full free=$($d.freeGB)GB need=$($d.needGB)GB $rel"; Send $ctx 507 @{ ok = $false; error = 'disk full'; freeGB = $d.freeGB }; break }
        if ($req.ContentLength64 -le 0 -or $req.ContentLength64 -gt ([int64]$cfg.MaxMB * 1MB)) { Send $ctx 413 @{ ok = $false; error = 'size' }; break }
        $tmp = Join-Path (Join-Path $Root '_tmp') ([guid]::NewGuid().ToString('N') + '.part')
        $fs = [System.IO.File]::Create($tmp)
        try { $req.InputStream.CopyTo($fs) } finally { $fs.Close() }
        $len = (Get-Item $tmp).Length
        if ($len -ne $req.ContentLength64) { Remove-Item $tmp -Force; Send $ctx 400 @{ ok = $false; error = 'truncated' }; break }
        New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
        if (Test-Path $full) { Remove-Item $full -Force }
        Move-Item $tmp $full
        Log "PUT $rel $len by=$by"
        Send $ctx 200 @{ ok = $true; size = $len }
      }
      'GET' {
        if (-not (Test-Path $full)) { Send $ctx 404 @{ ok = $false; error = 'not found' }; break }
        $ctx.Response.ContentType = $CT[$ext]
        $fs = [System.IO.File]::OpenRead($full)
        try { $ctx.Response.ContentLength64 = $fs.Length; $fs.CopyTo($ctx.Response.OutputStream) } finally { $fs.Close() }
      }
      'DELETE' {
        if (-not (Test-Path $full)) { Send $ctx 404 @{ ok = $false; error = 'not found' }; break }
        $tdir = Join-Path (Join-Path $Root '_trash') (Get-Date -Format 'yyyyMMdd')
        New-Item -ItemType Directory -Force -Path $tdir | Out-Null
        Move-Item $full (Join-Path $tdir (($rel -replace '/', '__')))  -Force
        Log "DEL $rel by=$by"
        Send $ctx 200 @{ ok = $true }
      }
      default { Send $ctx 405 @{ ok = $false; error = 'method' } }
    }
  } catch {
    Log ("ERR " + $_.Exception.Message)
    try { if ($ctx) { Send $ctx 500 @{ ok = $false; error = 'server' } } } catch {}
  } finally {
    try { if ($ctx) { $ctx.Response.Close() } } catch {}
  }
}
