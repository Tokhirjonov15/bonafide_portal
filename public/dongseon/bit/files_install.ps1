# files_install.ps1 - install the dongseon photo store on the Bit server (2026-11-15)
#
# Run ONCE on the Bit server (DESKTOP-TCEAQMT / 192.168.0.250) in an ADMIN PowerShell, after clinic hours:
#   [Net.ServicePointManager]::SecurityProtocol='Tls12'; iex (irm https://bonafide-portal.seoulgijibae.workers.dev/dongseon/bit/files-setup.txt)
#
# What it does (each step prints OK / FAIL; nothing touches Bit or SQL Server):
#   1. (optional) 'dongseon' Windows account: new password, password never expires, (optional) Administrators
#   2. picks the store drive: not the SQL data drive (F:), most free space; you confirm the letter
#   3. <drive>:\dongseon_files (only SYSTEM + Administrators can read it) + C:\dongseon_files_srv (program, key)
#   4. scheduled task 'DongseonFiles' (SYSTEM, at startup + every 10 min keep-alive, BelowNormal priority)
#   5. local self-test: write / read / delete a test file
#   6. Cloudflare Tunnel service (cloudflared) with the token you paste from the Cloudflare dashboard
#   7. prints the key for the Worker secret FILES_KEY (also copied to the clipboard)
# Re-running is safe: the existing key and files are kept.
# ASCII only on purpose (PowerShell 5.1 reads BOM-less files as ANSI).
param([string]$Src = $PSScriptRoot, [string]$Drive = '', [switch]$SkipAccount, [switch]$SkipTunnel, [switch]$ShowKey)   # -ShowKey: print the key (default: clipboard only, so it does not end up in screenshots or pasted logs)
$ErrorActionPreference = 'Stop'
$SRV = 'C:\dongseon_files_srv'
$PORT = 8787
$PUBLIC = 'https://files.bonafide-portal.com'
$SQL_DRIVE = 'F'          # drbitpack.mdf lives on F:\data (checked 2026-11-15) - never store photos there
$fails = 0
function OK($m)   { Write-Host "  [OK]   $m" -ForegroundColor Green }
function BAD($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fails++ }
function INFO($m) { Write-Host "  $m" }
function STEP($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }
# On the Bit server the PATH of a fresh account has no Windows folders (2026-11-25: 'powershell' and 'icacls' were not found).
# Fix it for THIS process only - the server's own PATH setting is not touched.
$env:Path = (Join-Path $env:SystemRoot 'System32') + ';' + $env:SystemRoot + ';' + (Join-Path $env:SystemRoot 'System32\Wbem') + ';' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0') + ';' + $env:Path
function Ask($q, $def) { $a = Read-Host "$q [$def]"; if ([string]::IsNullOrWhiteSpace($a)) { $def } else { $a.Trim() } }
function Lock($dir) { & icacls $dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "FAIL: PowerShell'ni 'Run as administrator' bilan oching." -ForegroundColor Red; return }
Write-Host "dongseon photo store installer - PC: $env:COMPUTERNAME" -ForegroundColor Cyan
if ($env:COMPUTERNAME -ne 'DESKTOP-TCEAQMT') {
  if ((Ask "Bu Bit serveri (DESKTOP-TCEAQMT) emas. Baribir davom etilsinmi? y/n" 'n') -ne 'y') { return }
}
if (-not (Test-Path (Join-Path $Src 'files_server.ps1'))) { Write-Host "FAIL: files_server.ps1 topilmadi ($Src)" -ForegroundColor Red; return }

# ---- 1. dongseon account ---------------------------------------------------------------
if (-not $SkipAccount) {
  STEP "1. 'dongseon' Windows hisobi"
  $u = Get-LocalUser -Name 'dongseon' -ErrorAction SilentlyContinue
  if (-not $u) { INFO "'dongseon' hisobi yo'q - o'tkazib yuborildi" }
  else {
    if ((Ask "dongseon parolini yangilaysizmi? y/n" 'y') -eq 'y') {
      $p1 = Read-Host "  Yangi parol" -AsSecureString
      $p2 = Read-Host "  Yangi parol (yana)" -AsSecureString
      $s1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
      $s2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
      if ($s1 -ne $s2 -or -not $s1) { BAD "parollar bir xil emas - parol o'zgarmadi" }
      else { try { Set-LocalUser -Name 'dongseon' -Password $p1; OK "parol yangilandi" } catch { BAD ("parol: " + $_.Exception.Message) } }
      $s1 = $null; $s2 = $null
    }
    try { Set-LocalUser -Name 'dongseon' -PasswordNeverExpires $true; OK "parol muddati endi tugamaydi" } catch { BAD ("never expires: " + $_.Exception.Message) }
    try { Enable-LocalUser -Name 'dongseon' } catch {}
    $isAdm = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*\dongseon' }).Count -gt 0
    if ($isAdm) { OK "dongseon allaqachon Administrators guruhida" }
    elseif ((Ask "dongseon Administrators guruhiga qo'shilsinmi (keyingi ishlarni dev PC dan RDP bilan qilish uchun)? y/n" 'n') -eq 'y') {
      try { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'dongseon'; OK "dongseon -> Administrators" } catch { BAD ("admin: " + $_.Exception.Message) }
    }
  }
}

# ---- 2. drive ----------------------------------------------------------------------------
STEP "2. Disk tanlash"
$disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object FreeSpace -Descending
foreach ($d in $disks) {
  $tag = ''; if ($d.DeviceID -eq "$($SQL_DRIVE):") { $tag = '  <- Bit SQL bazasi (ishlatilmaydi)' } elseif ($d.DeviceID -eq $env:SystemDrive) { $tag = '  <- Windows' }
  INFO ("{0}  bo'sh {1,7:N0} GB / jami {2,7:N0} GB{3}" -f $d.DeviceID, ($d.FreeSpace / 1GB), ($d.Size / 1GB), $tag)
}
$existing = ''; if (Test-Path "$SRV\config.json") { try { $existing = [string](Get-Content "$SRV\config.json" -Raw | ConvertFrom-Json).Root } catch {} }
if ($existing) { $def = $existing.Substring(0, 1) }
else {
  $cand = $disks | Where-Object { $_.DeviceID -ne "$($SQL_DRIVE):" -and $_.DeviceID -ne $env:SystemDrive } | Select-Object -First 1
  if (-not $cand) { $cand = $disks | Where-Object { $_.DeviceID -ne "$($SQL_DRIVE):" } | Select-Object -First 1 }
  $def = if ($cand) { $cand.DeviceID.Substring(0, 1) } else { 'C' }
}
if (-not $Drive) { $Drive = Ask "Rasmlar qaysi diskka saqlansin? (harf)" $def }
$Drive = $Drive.Trim().TrimEnd(':', '\').ToUpper()
if ($Drive -eq $SQL_DRIVE) {
  if ((Ask "$($Drive): da Bit SQL bazasi turibdi. Rostdan ham shu disk? (tavsiya etilmaydi) y/n" 'n') -ne 'y') { Write-Host "To'xtatildi." ; return }
}
if (-not (Test-Path "$($Drive):\")) { Write-Host "FAIL: $($Drive): disk yo'q" -ForegroundColor Red; return }
$ROOT = "$($Drive):\dongseon_files"
OK "saqlash joyi: $ROOT"

# ---- 3. folders, program, key -------------------------------------------------------------
STEP "3. Papkalar, dastur, kalit"
New-Item -ItemType Directory -Force -Path $ROOT, $SRV | Out-Null
Lock $ROOT; Lock $SRV
$task = Get-ScheduledTask -TaskName 'DongseonFiles' -ErrorAction SilentlyContinue
if ($task) { try { Stop-ScheduledTask -TaskName 'DongseonFiles' } catch {} }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*files_server.ps1*' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
Start-Sleep 1
$busy = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue
if ($busy) {
  $pids = ($busy | Select-Object -ExpandProperty OwningProcess -Unique) -join ','
  BAD "port $PORT boshqa dastur band qilgan (PID $pids) - to'xtatildi"; return
}
Copy-Item (Join-Path $Src 'files_server.ps1') "$SRV\files_server.ps1" -Force
@{ Root = $ROOT; MinFreeGB = 30; MinFreePct = 10; MaxMB = 20 } | ConvertTo-Json | Set-Content "$SRV\config.json" -Encoding ASCII
if (-not (Test-Path "$SRV\files.key")) {
  $b = New-Object byte[] 36; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  $k = [Convert]::ToBase64String($b).Replace('+', 'A').Replace('/', 'B').Replace('=', '')
  Set-Content "$SRV\files.key" $k -Encoding ASCII
  OK "yangi kalit yaratildi"
} else { OK "mavjud kalit saqlab qolindi" }
$KEY = (Get-Content "$SRV\files.key" -TotalCount 1).Trim()
OK "dastur: $SRV\files_server.ps1"

# ---- 4. scheduled task ---------------------------------------------------------------------
STEP "4. Avtomatik ishga tushish (DongseonFiles)"
$PSEXE = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'   # full path: on the Bit server 'powershell' is not on the system PATH (2026-11-25) - the task could not start, so the file server never answered
$act = New-ScheduledTaskAction -Execute $PSEXE -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$SRV\files_server.ps1`""
$t1 = New-ScheduledTaskTrigger -AtStartup
$t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10)
$set = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$pri = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'DongseonFiles' -Action $act -Trigger $t1, $t2 -Settings $set -Principal $pri -Force | Out-Null
Start-ScheduledTask -TaskName 'DongseonFiles'
OK "vazifa ro'yxatdan o'tdi va ishga tushdi"

# ---- 5. local self-test --------------------------------------------------------------------
STEP "5. Lokal tekshiruv"
$H = @{ 'x-files-key' = $KEY }
$up = $false
for ($i = 0; $i -lt 45 -and -not $up; $i++) { Start-Sleep 1; try { $hr = Invoke-RestMethod "http://127.0.0.1:$PORT/health" -Headers $H -TimeoutSec 3; $up = $true } catch { $lastErr = $_.Exception.Message } }
if (-not $up) {
  BAD "fayl server javob bermadi (log: $ROOT\_logs)"
  INFO ("oxirgi xato: " + $lastErr)
  try { $ti = Get-ScheduledTaskInfo -TaskName 'DongseonFiles'; INFO ("vazifa: holat=" + (Get-ScheduledTask -TaskName 'DongseonFiles').State + " natija=0x" + ('{0:X}' -f $ti.LastTaskResult)) } catch {}
  $lis = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue; INFO ("port $PORT tinglanyaptimi: " + [bool]$lis)
  $lf = Get-ChildItem "$ROOT\_logs" -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if ($lf) { INFO "log oxiri:"; Get-Content $lf.FullName -Tail 8 | ForEach-Object { INFO "  $_" } } else { INFO "log fayl yo'q (server umuman ishga tushmagan)" }
  $ef = Join-Path $SRV 'last_error.txt'; if (Test-Path $ef) { INFO 'ishga tushish xatosi:'; Get-Content $ef -Tail 3 | ForEach-Object { INFO "  $_" } }
}
else {
  OK ("server ishlayapti: {0}, bo'sh {1} GB, yozish {2}" -f $hr.ver, $hr.freeGB, $(if ($hr.canWrite) { 'mumkin' } else { 'TO`XTATILGAN (disk to`la)' }))
  if (-not $hr.canWrite) { BAD "diskda bo'sh joy kam (kerak > $($hr.needGB) GB)" }
  try {
    $bytes = [byte[]](1..2048 | ForEach-Object { $_ % 251 })
    $tp = "patient_photos/_selftest/t$(Get-Date -Format 'HHmmss').jpg"
    Invoke-RestMethod "http://127.0.0.1:$PORT/f/$tp" -Method Put -Headers $H -Body $bytes -ContentType 'image/jpeg' -TimeoutSec 10 | Out-Null
    $g = Invoke-WebRequest "http://127.0.0.1:$PORT/f/$tp" -Headers $H -UseBasicParsing -TimeoutSec 10
    if ($g.RawContentLength -ne $bytes.Length) { throw "o'qilgan hajm farq qiladi" }
    Invoke-RestMethod "http://127.0.0.1:$PORT/f/$tp" -Method Delete -Headers $H -TimeoutSec 10 | Out-Null
    Get-ChildItem "$ROOT\_trash" -Recurse -Filter 'patient_photos___selftest__*' -ErrorAction SilentlyContinue | Remove-Item -Force
    Remove-Item "$ROOT\patient_photos\_selftest" -Recurse -Force -ErrorAction SilentlyContinue
    OK "yozish / o'qish / o'chirish ishlaydi"
  } catch { BAD ("self-test: " + $_.Exception.Message) }
  try { Invoke-RestMethod "http://127.0.0.1:$PORT/health" -TimeoutSec 3 | Out-Null; BAD "kalitsiz so'rov qabul qilindi!" } catch { OK "kalitsiz so'rov rad etiladi" }
}

# ---- 6. Cloudflare Tunnel -------------------------------------------------------------------
if (-not $SkipTunnel) {
  STEP "6. Cloudflare Tunnel"
  $svc = Get-Service -Name 'Cloudflared' -ErrorAction SilentlyContinue
  if ($svc -and $svc.Status -eq 'Running') { OK "cloudflared service allaqachon ishlayapti" }
  else {
    $exe = "$SRV\cloudflared.exe"
    if (-not (Test-Path $exe)) {
      try {
        [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
        Invoke-WebRequest 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile $exe -UseBasicParsing
        OK "cloudflared yuklab olindi"
      } catch { BAD ("cloudflared yuklab bo'lmadi: " + $_.Exception.Message) }
    }
    if (Test-Path $exe) {
      $tok = Read-Host "  Cloudflare dashboard'dagi tunnel token'ini qo'ying (bo'sh = o'tkazib yuborish)"
      $tok = ($tok -replace '^.*service install\s+', '').Trim()
      if ($tok) {
        if ($svc) { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & $exe service uninstall 2>&1 | Out-Null } catch {} finally { $ErrorActionPreference = $eap }; Start-Sleep 2 }
        # cloudflared writes its normal progress lines to stderr; with ErrorActionPreference=Stop, PowerShell 5.1 turns the first line into a fatal error (2026-11-25)
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & $exe service install $tok 2>&1 | ForEach-Object { INFO "$_" } } finally { $ErrorActionPreference = $eap }
        Start-Sleep 5
        $svc = Get-Service -Name 'Cloudflared' -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { OK "cloudflared service ishlayapti" } else { BAD "cloudflared service ishga tushmadi" }
      } else { INFO "tunnel o'tkazib yuborildi - keyin qayta ishga tushirsangiz bo'ladi" }
    }
  }
  try {
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $r = Invoke-RestMethod "$PUBLIC/health" -Headers $H -TimeoutSec 15
    if ($r.ok) { OK "$PUBLIC tashqaridan ishlayapti" } else { BAD "$PUBLIC javobi g'alati" }
  } catch { INFO "[KUTILMOQDA] $PUBLIC hali ishlamayapti - dashboard'da Public Hostname (files -> http://127.0.0.1:$PORT) qo'shilganini tekshiring" }
}

# ---- 7. key for the Worker -----------------------------------------------------------------
STEP "7. Worker uchun kalit (FILES_KEY)"
$clip = $false; try { Set-Clipboard -Value $KEY; $clip = $true } catch {}
if ($clip) { INFO "kalit clipboard'ga nusxalandi - ekranda ko'rsatilmaydi (boshi: $($KEY.Substring(0, 4))...)" }
if ($ShowKey -or -not $clip) { Write-Host ""; Write-Host "  $KEY" -ForegroundColor Yellow; Write-Host ""; INFO "kalitni rasmga olmang va hech kimga yubormang" }
INFO "Dev PC'da:  npx wrangler secret put FILES_KEY   (Ctrl+V bilan qo'ying - RDP clipboard'i dev PC'ga o'tadi)"
INFO "            npx wrangler secret put FILES_URL   ($PUBLIC)"
Write-Host ""
if ($fails -eq 0) { Write-Host "PASS - hammasi joyida" -ForegroundColor Green } else { Write-Host "FAIL - $fails ta muammo, yuqoridagi [FAIL] qatorlarini yuboring" -ForegroundColor Red }
