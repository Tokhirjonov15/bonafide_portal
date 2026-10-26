# ─────────────────────────────────────────────────────────────
#  진료 녹음 (원장님 진료실 PC) — 2026-10-25 요청
#  비트 외래진료실 창에 지금 불러온 환자(차트번호·이름)를 1.5초마다 읽어, 환자가 바뀌면(진료대기·진료보류에서 다른 환자를 더블클릭)
#  앞 환자 녹음을 끊어 외장하드에 저장하고 새 환자 녹음을 시작한다. 동선관리 화면이 없어도 된다.
#   · 2026-10-26: 동선관리에서 그 환자 카드가 이 진료실에 있을 때만 녹음한다(다른 방 환자 차트를 열어 보는 것은 녹음 안 함). 카드가 진료실을 나가면 끊는다
#   · 파일: '녹음 2026-10-25 홍길동 900101 진료실1 09시15분03초~09시20분10초.wav'  (16kHz 모노 — 1분 약 1.9MB)
#   · 녹음 중에는 이 PC 의 임시 폴더에 쌓고, 끊을 때 외장하드로 옮긴다. 외장하드가 빠져 있으면 C:\bitplus\녹음_임시 에 두었다가 꽂히면 옮긴다
#   · 받아쓰기: 같은 폴더를 보는 rec_transcribe.py(rec_install.bat 로 설치)가 옆에 .txt 를 만들면 동선관리 '녹음기록'(recText)에 올린다
#   · 녹음 엔진: Windows 기본 MCI(winmm) — 설치할 것 없음. 마이크 = Windows '기본 녹음 장치'
#   · 오른쪽 아래 알림 영역 아이콘: 빨강 = 녹음 중, 회색 = 대기. 오른쪽 클릭 → 폴더 열기 · 이번 환자 녹음 멈추기
#  비트에는 아무것도 입력·클릭하지 않는다(창의 글자만 읽음 — 캡처 바·감시 스크립트와 같은 방법).
#  설치: clinic_rec_install.ps1 (USB 의 '진료실PC_녹음설치.bat')
# ─────────────────────────────────────────────────────────────
param([string]$Pc = $env:COMPUTERNAME,
      [string]$Room = '',          # 파일 이름에 넣을 진료실(예: 진료실1). 비우면 PC 이름이 '진료실…'일 때 그 이름
      [string]$Dir = '',           # 녹음 폴더(외장하드). 비우면 같은 폴더의 clinic_rec.dir 에 적힌 곳
      [int]$MaxMin = 60,           # 한 환자 최대 녹음(분) — 넘으면 저장하고 그 환자는 더 녹음하지 않는다(점심시간에 창을 열어 둔 채 계속 녹음되지 않게)
      [int]$MinSec = 8,            # 이보다 짧은 녹음은 버린다(환자를 잘못 눌렀다 바로 바꾼 경우)
      [string]$SimFile = '',       # 시험용: 비트 창 대신 이 파일의 'mrn|이름|주민앞7' 한 줄을 지금 환자로 읽는다
      [string]$Stt = 'openai',     # 받아쓰기: openai = 저장하면 포털 서버(/api/dongseon/stt)로 보내 OpenAI 로 받아씀(1분 약 9원) · none = 안 함
      [string]$SttJob = '',        # (내부용) 이 녹음 파일 하나를 OpenAI 로 받아쓰고 끝 — 녹음 프로그램이 따로 띄운다(녹음·자르기가 멈추지 않게)
      [string]$Portal = 'https://bonafide-portal.seoulgijibae.workers.dev',
      [switch]$Test)               # 마이크 시험: 3초 녹음해서 소리 크기만 알려 주고 끝
$ErrorActionPreference = 'Continue'
$ApiKey    = 'AIzaSyDBj3z-Qj9DyT1ZgDNps1-Yp9ZBopeWr0w'
$ProjectId = 'bonafide-dongseon-108e2'
$BotEmail  = 'uc8feac453b1a01cc028b072a@bonafide.app'   # 동선관리 계정 'bitbot' (받아쓴 글 올리기용)
$BoardDoc  = 'patientboard_v3/' + [Uri]::EscapeDataString('반듯한정형외과')
if (-not $Room -and $Pc -match '^진료실') { $Room = $Pc }
$DirFile    = Join-Path $PSScriptRoot 'clinic_rec.dir'
$SecretFile = Join-Path $PSScriptRoot 'bitplus_watcher.secret'
$TokenFile  = Join-Path $PSScriptRoot 'clinic_rec.token'
$Hold       = Join-Path $PSScriptRoot '녹음_임시'          # 외장하드가 없을 때 잠시 두는 곳
$LogDir  = Join-Path $env:LOCALAPPDATA 'bitplus_watcher'; New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'clinic_rec.log'
$Work    = Join-Path $LogDir 'clinic_rec_work'; New-Item -ItemType Directory -Force $Work | Out-Null   # 녹음 중 임시 파일(영문 경로)
$QueueFile = Join-Path $LogDir 'clinic_rec_queue.json'      # 받아쓴 글을 올릴 녹음 목록
if (-not $Dir -and (Test-Path $DirFile)) { $Dir = ([string](Get-Content $DirFile -Encoding UTF8 -TotalCount 1)).Trim() }
function Log($m) { try { Add-Content $LogFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" -Encoding UTF8 } catch {} }
function NowIso() { return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }
function Iso($d) { return ([DateTime]$d).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }

# ── 녹음 엔진 (MCI waveaudio) ──
Add-Type -Namespace ClinicRec -Name Mci -MemberDefinition @'
[DllImport("winmm.dll", CharSet=CharSet.Unicode)] public static extern int mciSendString(string cmd, System.Text.StringBuilder ret, int len, System.IntPtr cb);
[DllImport("winmm.dll", CharSet=CharSet.Unicode)] public static extern bool mciGetErrorString(int err, System.Text.StringBuilder buf, int len);
[DllImport("winmm.dll")] public static extern int waveInGetNumDevs();
'@
function Mci($cmd) { $sb = New-Object Text.StringBuilder 256; $e = [ClinicRec.Mci]::mciSendString($cmd, $sb, 256, [IntPtr]::Zero)
  if ($e) { $eb = New-Object Text.StringBuilder 256; [void][ClinicRec.Mci]::mciGetErrorString($e, $eb, 256); throw "MCI '$($cmd.Split(' ')[0])' 오류 ${e}: $($eb.ToString())" }
  return $sb.ToString() }
function MciQuiet($cmd) { try { [void](Mci $cmd) } catch {} }
function WavPeak($path) {   # 16비트 PCM 의 가장 큰 소리(0~100%) — 마이크 시험용
  $b = [IO.File]::ReadAllBytes($path); $max = 0
  for ($i = 44; $i -lt $b.Length - 1; $i += 2) { $v = [Math]::Abs([int][BitConverter]::ToInt16($b, $i)); if ($v -gt $max) { $max = $v } }
  return [Math]::Round($max * 100 / 32768, 1) }

if ($Test) {
  $n = [ClinicRec.Mci]::waveInGetNumDevs()
  if ($n -lt 1) { Write-Host '마이크(녹음 장치)가 없습니다 — 마이크를 꽂고 다시 시험하세요.' -ForegroundColor Red; exit 2 }
  $t = Join-Path $Work 'mic_test.wav'
  try { MciQuiet 'close crTest'; [void](Mci 'open new type waveaudio alias crTest'); [void](Mci 'set crTest bitspersample 16 samplespersec 16000 channels 1 bytespersec 32000 alignment 2')
    Write-Host '3초 동안 말해 보세요…' -ForegroundColor Cyan; [void](Mci 'record crTest'); Start-Sleep -Seconds 3; [void](Mci 'stop crTest'); [void](Mci "save crTest `"$t`""); MciQuiet 'close crTest'
    $pk = WavPeak $t; $kb = [Math]::Round((Get-Item $t).Length / 1024)
    if ($pk -lt 1) { Write-Host "녹음은 되지만 소리가 거의 없습니다(최대 $pk%) — Windows 설정 → 개인 정보 → 마이크 → '데스크톱 앱이 마이크에 액세스' 켜기, 소리 설정의 기본 녹음 장치를 확인하세요." -ForegroundColor Yellow; exit 3 }
    Write-Host "마이크 정상 — 소리 최대 $pk% ($kb KB)" -ForegroundColor Green; exit 0 }
  catch { MciQuiet 'close crTest'; Write-Host "녹음 시험 실패: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
}

# 한 번만 실행 (로그온 작업이 5분마다 다시 시작해도 이미 떠 있으면 그냥 끝난다)
if (-not $SttJob) {
  $script:Mtx = New-Object System.Threading.Mutex($false, 'Local\BonafideClinicRec')
  if (-not $script:Mtx.WaitOne(0)) { exit }
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$BotPassword = ''; if (Test-Path $SecretFile) { $BotPassword = ([string](Get-Content $SecretFile -Encoding UTF8 -TotalCount 1)).Trim() }

# ── 비트 외래진료실 창 읽기 (slip_capture.ps1 · bitplus_watcher.ps1 과 같은 방법 — 고칠 때 함께 고친다) ──
Add-Type -Namespace BitW -Name U32 -UsingNamespace System.Collections.Generic, System.Text -MemberDefinition @'
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, StringBuilder s, uint flags, uint timeout, out IntPtr res);
[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr res);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
public static List<IntPtr> Tops() { var l = new List<IntPtr>(); EnumWindows((h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
public static List<IntPtr> Children(IntPtr p) { var l = new List<IntPtr>(); EnumChildWindows(p, (h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
public static string Text(IntPtr h) {
  IntPtr res;
  if (SendMessageTimeout(h, 0x000E, IntPtr.Zero, IntPtr.Zero, 0x0002, 500, out res) == IntPtr.Zero) return "";
  int n = (int)res; if (n <= 0) return "";
  var sb = new StringBuilder(n + 2);
  if (SendMessageTimeout(h, 0x000D, (IntPtr)(n + 1), sb, 0x0002, 500, out res) == IntPtr.Zero) return "";
  return sb.ToString();
}
public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
public static int Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return (int)p; }
'@
function FindDoctorWindow() {
  $proc = Get-Process -Name BITDoctorOrder -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $proc) { return $null }
  foreach ($h in [BitW.U32]::Tops()) { if ([BitW.U32]::Pid($h) -ne $proc.Id) { continue }
    if ((([BitW.U32]::Text($h)) -replace '\s', '') -like '외래진료실*') { return $h } }
  return $null
}
function Rrn7($t) { $m = [regex]::Match([string]$t, '^\s*(\d{6})-?(\d)'); if ($m.Success) { return $m.Groups[1].Value + '-' + $m.Groups[2].Value } else { return '' } }
$script:DocCache = $null; $script:DocRetry = 0
function ReadDoctor($hwnd) {   # 차트번호 · 수진자명 · 주민번호 앞 7자리만 (증상·메모는 읽지 않는다)
  $c = $script:DocCache
  $okH = { param($h) ($null -eq $h) -or [BitW.U32]::IsWindow($h) }
  if ($c -and $c.hwnd -eq [IntPtr]$hwnd -and [BitW.U32]::IsWindow($c.mrn) -and (& $okH $c.name) -and (& $okH $c.rrn)) {
    $missing = ($null -eq $c.name) -or ($null -eq $c.rrn)
    if ($missing -and $script:DocRetry -lt 5 -and ((([BitW.U32]::Text($c.mrn)) -replace '\D', '') -ne '')) { $script:DocRetry++; $script:DocCache = $null }
    else { return @{ mrn = (([BitW.U32]::Text($c.mrn)) -replace '\D', ''); name = $(if ($null -ne $c.name) { ([BitW.U32]::Text($c.name)).Trim() } else { '' })
                     rrn7 = (Rrn7 $(if ($null -ne $c.rrn) { [BitW.U32]::Text($c.rrn) } else { '' })); hasName = ($null -ne $c.name) } }
  }
  $script:DocCache = $null
  $els = @()
  foreach ($h in [BitW.U32]::Children([IntPtr]$hwnd)) {
    $cls = [BitW.U32]::Cls($h); if ($cls -notmatch '\.(Window|STATIC|EDIT)\.') { continue }
    if (-not [BitW.U32]::IsWindowVisible($h)) { continue }
    $r = New-Object BitW.U32+RECT; [void][BitW.U32]::GetWindowRect($h, [ref]$r)
    if (($r.R - $r.L) -le 0) { continue }
    $els += [pscustomobject]@{ hw = $h; x = $r.L; y = $r.T; w = ($r.R - $r.L); h = ($r.B - $r.T); cls = $cls; name = [BitW.U32]::Text($h) }
  }
  $lblMrn = $els | Where-Object { (($_.name -replace '\s', '') -eq '차트번호') -and $_.w -lt 120 } | Select-Object -First 1
  $lblName = $els | Where-Object { (($_.name -replace '\s', '') -eq '수진자명') -and $_.w -lt 120 } | Select-Object -First 1
  if (-not $lblMrn) { return $null }
  $mrnEl = $els | Where-Object { $_.cls -match 'EDIT' -and [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.x -ge ($lblMrn.x + $lblMrn.w - 8) -and $_.x -le ($lblMrn.x + $lblMrn.w + 60) } | Sort-Object x | Select-Object -First 1
  $rowLbl = @($els | Where-Object { $_.cls -match '\.(Window|STATIC)\.' -and [Math]::Abs($_.y - $lblMrn.y) -le 10 } | Sort-Object x)
  $nextOf = { param($e) $rowLbl | Where-Object { $_.hw -ne $e.hw -and [Math]::Abs($_.x - ($e.x + $e.w)) -le 8 } | Sort-Object x | Select-Object -First 1 }
  $nameEl = $null; $sexEl = $null; $rrnEl = $null
  if ($lblName) {
    $nameEl = & $nextOf $lblName
    if ($nameEl) { $sexEl = & $nextOf $nameEl }
    if ($sexEl) { $rrnEl = & $nextOf $sexEl }
    if ($nameEl -and (($nameEl.name -replace '\s', '') -in @('보험유형','특이사항','조합기호','증번호'))) { $nameEl = $null; $sexEl = $null; $rrnEl = $null }
    if ($sexEl -and $sexEl.name.Trim() -and $sexEl.name -notmatch '^\s*\((M|F)/') { $sexEl = $null }
    if ($rrnEl -and $rrnEl.name.Trim() -and $rrnEl.name -notmatch '^\s*\d{6}-') { $rrnEl = $null }
  }
  if (-not $nameEl -and $lblName) { $nameEl = $els | Where-Object { $_.hw -ne $lblName.hw -and [Math]::Abs($_.y - $lblName.y) -le 10 -and $_.x -ge ($lblName.x + $lblName.w - 8) -and $_.x -le ($lblName.x + $lblName.w + 60) -and $_.name.Trim() } | Sort-Object x | Select-Object -First 1 }
  if (-not $rrnEl) { $rrnEl = $els | Where-Object { [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.name -match '^\s*\d{6}-\d' } | Select-Object -First 1 }
  $mrn = if ($mrnEl) { ($mrnEl.name -replace '\D', '') } else { '' }
  if ($mrnEl) {
    $script:DocCache = @{ hwnd = [IntPtr]$hwnd; mrn = $mrnEl.hw; name = $(if ($nameEl) { $nameEl.hw } else { $null }); rrn = $(if ($rrnEl) { $rrnEl.hw } else { $null }) }
    if ($nameEl -and $rrnEl) { $script:DocRetry = 0 }
  }
  return @{ mrn = $mrn; name = $(if ($nameEl) { $nameEl.name.Trim() } else { '' }); rrn7 = (Rrn7 $(if ($rrnEl) { $rrnEl.name } else { '' })); hasName = ($null -ne $nameEl) }
}
# 지금 환자: @{ mrn; name; rrn7 } — 환자 없음/창 없음이면 mrn ''.
#  차트번호 칸에 번호를 치는 중(이름이 아직 안 바뀜)은 환자로 보지 않는다: 이름 칸이 있는 창이면 이름(또는 주민번호)이 있어야 환자
function CurrentPatient() {
  if ($SimFile) { $l = ''; try { $l = ([string](Get-Content $SimFile -Encoding UTF8 -TotalCount 1)).Trim() } catch {}
    $a = $l -split '\|'; return @{ mrn = ([string]$a[0] -replace '\D', ''); name = [string]$a[1]; rrn7 = [string]$a[2] } }
  $h = FindDoctorWindow; if (-not $h) { return @{ mrn = ''; name = ''; rrn7 = '' } }
  $d = ReadDoctor $h; if (-not $d -or -not $d.mrn) { return @{ mrn = ''; name = ''; rrn7 = '' } }
  if ($d.hasName -and -not $d.name -and -not $d.rrn7) { return @{ mrn = ''; name = ''; rrn7 = ''; typing = $true } }
  return @{ mrn = $d.mrn; name = $d.name; rrn7 = $d.rrn7 }
}

# ── Firebase (받아쓴 글 올리기 — 감시 스크립트 계정. 비밀번호 파일이 없으면 녹음만 한다) ──
$script:Tok = $null; $script:TokExp = [DateTime]::MinValue; $script:Refresh = $null; $script:LoginFailAt = [DateTime]::MinValue
if (Test-Path $TokenFile) { try { $script:Refresh = (Get-Content $TokenFile -TotalCount 1 -ErrorAction Stop).Trim() } catch { $script:Refresh = $null } }
function FbToken() {
  if ($script:Tok -and (Get-Date) -lt $script:TokExp) { return $script:Tok }
  if ($script:Refresh) {
    try { $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://securetoken.googleapis.com/v1/token?key=$ApiKey" -ContentType 'application/x-www-form-urlencoded' -Body "grant_type=refresh_token&refresh_token=$($script:Refresh)"
      $script:Tok = $r.id_token; $script:Refresh = $r.refresh_token; $script:TokExp = (Get-Date).AddSeconds([int]$r.expires_in - 300)
      try { [IO.File]::WriteAllText($TokenFile, $script:Refresh, (New-Object Text.UTF8Encoding $false)) } catch {}; return $script:Tok }
    catch { Log "토큰 갱신 실패 → 비밀번호로: $($_.Exception.Message)"; $script:Refresh = $null } }
  if (-not $BotPassword) { throw '비밀번호 파일 없음(받아쓴 글은 올리지 않음)' }
  if (((Get-Date) - $script:LoginFailAt).TotalSeconds -lt 300) { throw '로그인 대기 중(최근 실패)' }
  $body = @{ email = $BotEmail; password = $BotPassword; returnSecureToken = $true } | ConvertTo-Json -Compress
  try { $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$ApiKey" -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) }
  catch { $script:LoginFailAt = Get-Date; throw "로그인 실패: $($_.Exception.Message)" }
  $script:Tok = $r.idToken; $script:Refresh = $r.refreshToken; $script:TokExp = (Get-Date).AddSeconds([int]$r.expiresIn - 300)
  try { [IO.File]::WriteAllText($TokenFile, $script:Refresh, (New-Object Text.UTF8Encoding $false)) } catch {}
  return $script:Tok
}
function FsStr($v) { return @{ stringValue = [string]$v } }
function PutRecText($docId, $fields) {   # recText/{docId} 문서 쓰기(덮어쓰기) — 동선관리 브라우저 녹음과 같은 모양
  $f = @{}; foreach ($k in $fields.Keys) { $v = $fields[$k]; if ($v -is [int] -or $v -is [long]) { $f[$k] = @{ integerValue = [string]$v } } else { $f[$k] = FsStr $v } }
  $body = @{ fields = $f } | ConvertTo-Json -Depth 6 -Compress
  $u = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$BoardDoc/recText/$([Uri]::EscapeDataString($docId))"
  Invoke-RestMethod -TimeoutSec 30 -Method Patch -Uri $u -Headers @{ Authorization = "Bearer $(FbToken)" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
}

# ── OpenAI 받아쓰기 (따로 띄운 프로세스에서 파일 하나씩) ──
#  WAV 를 10분(약 19MB)씩 잘라 서버로 보낸다(OpenAI 는 25MB 까지) → '<녹음>.openai.txt' 를 옆에 쓰고 recText/<녹음>__openai 에 올린다
#  실패하면 '<녹음>.openai.err' 에 횟수 — 3번 실패하면 그 파일은 건너뛴다
function WavParts($path, $maxSec) {
  $b = [IO.File]::ReadAllBytes($path)
  $i = 12; $fmt = $null; $data = -1; $len = 0
  while ($i -lt $b.Length - 8) { $id = [Text.Encoding]::ASCII.GetString($b, $i, 4); $sz = [BitConverter]::ToInt32($b, $i + 4)
    if ($id -eq 'fmt ') { $fmt = $i } elseif ($id -eq 'data') { $data = $i + 8; $len = [Math]::Min($sz, $b.Length - $data); break }
    $i += 8 + $sz + ($sz % 2) }
  if (-not $fmt -or $data -lt 0) { throw 'WAV 형식을 읽지 못했습니다' }
  $rate = [BitConverter]::ToInt32($b, $fmt + 16); $align = [BitConverter]::ToInt16($b, $fmt + 20); if ($rate -le 0) { $rate = 32000 }; if ($align -le 0) { $align = 2 }
  $step = [int]([Math]::Floor($rate * $maxSec / $align) * $align)
  $parts = @()
  for ($o = 0; $o -lt $len; $o += $step) {
    $n = [Math]::Min($step, $len - $o); $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([int]16); $w.Write($b, $fmt + 8, 16); $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$n); $w.Write($b, $data + $o, $n); $w.Flush()
    $parts += , $ms.ToArray(); $w.Dispose() }
  return , $parts
}
function RunStt($wav) {
  $fileName = Split-Path $wav -Leaf; $base = $wav -replace '\.wav$', ''
  $meta = @(QueueGet | Where-Object { $_ -and $_.file -eq $fileName }) | Select-Object -First 1
  try {
    $parts = WavParts $wav 600; $texts = @(); $k = 0
    foreach ($p in $parts) { $k++
      $r = Invoke-RestMethod -TimeoutSec 600 -Method Post -Uri "$Portal/api/dongseon/stt" -Headers @{ Authorization = "Bearer $(FbToken)"; 'x-provider' = 'openai' } -ContentType 'audio/wav' -Body $p
      $t = ([string]$r.text).Trim(); if ($parts.Count -gt 1) { $t = "[$(($k - 1) * 10)분부터] " + $t }; if ($t) { $texts += $t } }
    $text = ($texts -join "`r`n"); if (-not $text) { $text = '(받아쓴 말이 없습니다)' }
    [IO.File]::WriteAllText("$base.openai.txt", $text, (New-Object Text.UTF8Encoding $true))
    Remove-Item -LiteralPath "$base.openai.err" -Force -ErrorAction SilentlyContinue
    Log "OpenAI 받아쓰기: $fileName ($($parts.Count)조각, $($text.Length)자)"
    if ($meta) {
      try { PutRecText ((RecDocId $fileName) + '__openai') ([ordered]@{ mrn = [string]$meta.mrn; pid = ''; name = [string]$meta.name; room = [string]$meta.room; startedAt = [string]$meta.at; endAt = [string]$meta.endAt
          date = ([string]$meta.at).Substring(0, 10); file = $fileName; text = $(if ($text.Length -gt 200000) { $text.Substring(0, 200000) } else { $text }); src = 'openai'; dur = [int]$meta.dur; at = (NowIso); by = "녹음($Pc)" })
        Log "OpenAI 받아쓴 글 올림: $fileName" }
      catch { Log "OpenAI 받아쓴 글 올리기 실패 $fileName : $($_.Exception.Message) (글은 외장하드 .openai.txt 에 있음)" } }
  } catch {
    $n = 0; try { $n = [int]([string](Get-Content -LiteralPath "$base.openai.err" -TotalCount 1 -ErrorAction Stop)) } catch {}
    try { [IO.File]::WriteAllText("$base.openai.err", [string]($n + 1)) } catch {}
    $msg = $_.Exception.Message; try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $msg += ' ' + $sr.ReadToEnd() } catch {}
    Log "OpenAI 받아쓰기 실패($($n + 1)번째) $fileName : $msg"
  }
}
# 녹음 프로그램 쪽: 30초마다 받아쓸 녹음이 있으면(한 번에 하나) 따로 띄운다
$script:SttProc = $null
function SttNext() {
  if ($Stt -ne 'openai' -or -not ($BotPassword -or $script:Refresh)) { return }
  if ($script:SttProc -and -not $script:SttProc.HasExited) { return }
  foreach ($x in @(QueueGet | Where-Object { $_ })) {
    $wav = $null; foreach ($fd in @($Dir, $Hold)) { if (-not $fd) { continue }; $p = Join-Path $fd $x.file; if (Test-Path -LiteralPath $p) { $wav = $p; break } }
    if (-not $wav) { continue }
    $base = $wav -replace '\.wav$', ''
    if (Test-Path -LiteralPath "$base.openai.txt") { continue }
    $n = 0; try { $n = [int]([string](Get-Content -LiteralPath "$base.openai.err" -TotalCount 1 -ErrorAction Stop)) } catch {}
    if ($n -ge 3) { continue }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-Pc', "`"$Pc`"", '-SttJob', "`"$wav`"")
    if ($Dir) { $a += @('-Dir', "`"$Dir`"") }
    try { $script:SttProc = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden -PassThru } catch { Log "받아쓰기 시작 실패: $($_.Exception.Message)" }
    return
  }
}
function SttDone($x) {   # 대기 목록에서 빼도 되는가: OpenAI 를 쓰면 .openai.txt 가 생겼거나 3번 실패
  if ($Stt -ne 'openai') { return $true }
  foreach ($fd in @($Dir, $Hold)) { if (-not $fd) { continue }; $b = Join-Path $fd ($x.file -replace '\.wav$', '')
    if (Test-Path -LiteralPath "$b.openai.txt") { return $true }
    try { if ([int]([string](Get-Content -LiteralPath "$b.openai.err" -TotalCount 1 -ErrorAction Stop)) -ge 3) { return $true } } catch {} }
  return $false
}

# ── 동선관리에서 이 환자가 지금 이 진료실에 있는가 (2026-10-26) ──
#  비트 창만 보면 원장님이 다른 방 환자(Sono·처치실·엑스레이 결과)의 차트를 열어도 그 환자로 녹음했다(10-25~26 녹음 27건 중 16건).
#  동선관리 카드의 지금 방(route[step])이 이 진료실일 때만 녹음한다. 확인할 수 없으면(로그인·네트워크) 예전처럼 비트 창만 따른다.
#  돌려주는 값: 방 이름 · '' (동선에 없음) · $null (확인 못 함). 같은 환자는 5초 동안 다시 묻지 않는다
$script:BoardAt = @{}; $script:BoardRoom = @{}; $script:BoardErrAt = [DateTime]::MinValue
function BoardRoomOf($mrn) {
  if (-not $mrn -or -not $Room) { return $null }
  if ($script:BoardAt.ContainsKey($mrn) -and ((Get-Date) - $script:BoardAt[$mrn]).TotalSeconds -lt 5) { return $script:BoardRoom[$mrn] }
  if (((Get-Date) - $script:BoardErrAt).TotalSeconds -lt 60) { return $null }   # 방금 실패 — 1분 동안은 묻지 않는다
  try {
    $q = @{ structuredQuery = @{ from = @(@{ collectionId = 'patients' }); where = @{ fieldFilter = @{ field = @{ fieldPath = 'mrn' }; op = 'EQUAL'; value = @{ stringValue = [string]$mrn } } }; limit = 5 } } | ConvertTo-Json -Depth 10 -Compress
    $u = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$($BoardDoc):runQuery"
    $wr = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Method Post -Uri $u -Headers @{ Authorization = "Bearer $(FbToken)" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($q))
    $res = [Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray()) | ConvertFrom-Json
    $rm = ''
    foreach ($x in @($res)) { if (-not $x.document) { continue }; $f = $x.document.fields
      $route = @(@($f.route.arrayValue.values) | ForEach-Object { [string]$_.stringValue }); $st = [int]$f.step.integerValue
      if ($route.Count -gt $st) { $rm = $route[$st]; if ($rm -eq $Room) { break } } }
    $script:BoardAt[$mrn] = Get-Date; $script:BoardRoom[$mrn] = $rm; return $rm
  } catch { $script:BoardErrAt = Get-Date; Log "동선 확인 실패(비트 창만 따름): $($_.Exception.Message)"; return $null }
}
function InRoomOnBoard($mrn) { $r = BoardRoomOf $mrn; return ($null -eq $r -or $r -eq $Room) }

# ── 녹음 ──
$script:Cur = $null         # 녹음 중: @{ mrn; name; rrn7; start(DateTime); tmp }
$script:StopKey = ''         # 이 차트번호는 (최대 시간·직접 멈춤으로) 다시 녹음하지 않는다 — 다른 환자로 바뀌면 풀림
$script:LastErr = ''
function Hms($d) { return "{0:00}시{1:00}분{2:00}초" -f $d.Hour, $d.Minute, $d.Second }
function SafeName($s) { return (([string]$s) -replace '[\\/:*?"<>|]', '').Trim() }
function RecFolder() { if ($Dir -and (Test-Path -LiteralPath $Dir)) { return $Dir }; New-Item -ItemType Directory -Force $Hold | Out-Null; return $Hold }
function StartRec($p) {
  $tmp = Join-Path $Work ("cur_" + (Get-Date).ToString('yyyyMMddHHmmss') + '.wav')
  MciQuiet 'close crRec'
  try { [void](Mci 'open new type waveaudio alias crRec'); [void](Mci 'set crRec bitspersample 16 samplespersec 16000 channels 1 bytespersec 32000 alignment 2'); [void](Mci 'record crRec') }
  catch { MciQuiet 'close crRec'; $script:LastErr = $_.Exception.Message; Log "녹음 시작 실패 $($p.mrn): $($script:LastErr)"; SetIcon; return }
  $script:LastErr = ''
  $script:Cur = @{ mrn = $p.mrn; name = $p.name; rrn7 = $p.rrn7; start = (Get-Date); tmp = $tmp }
  Log "녹음 시작: $($p.name) ($($p.mrn))"; SetIcon
}
function StopRec($why) {
  $c = $script:Cur; if (-not $c) { return }; $script:Cur = $null
  $end = Get-Date; $sec = [int]($end - $c.start).TotalSeconds
  try { [void](Mci 'stop crRec') } catch { Log "멈춤 오류: $($_.Exception.Message)" }
  if ($sec -lt $MinSec) { MciQuiet 'close crRec'; Log "짧아서 버림($sec 초): $($c.name) ($($c.mrn)) · $why"; SetIcon; return }
  try { [void](Mci "save crRec `"$($c.tmp)`"") } catch { MciQuiet 'close crRec'; $script:LastErr = $_.Exception.Message; Log "저장 실패 $($c.mrn): $($script:LastErr)"; SetIcon; return }
  MciQuiet 'close crRec'
  $b6 = ([string]$c.rrn7 -replace '\D', ''); if ($b6.Length -gt 6) { $b6 = $b6.Substring(0, 6) }
  $nm = SafeName $(if ($c.name) { $c.name } else { "차트$($c.mrn)" })
  $base = "녹음 $($c.start.ToString('yyyy-MM-dd')) $nm$(if ($b6) { ' ' + $b6 }) $(SafeName $Room) $(Hms $c.start)~$(Hms $end)" -replace '\s+', ' '
  $folder = RecFolder; $dest = Join-Path $folder "$base.wav"; $i = 2
  while (Test-Path -LiteralPath $dest) { $dest = Join-Path $folder "$base ($i).wav"; $i++ }
  try { Move-Item -LiteralPath $c.tmp -Destination $dest -Force -ErrorAction Stop } catch { $script:LastErr = "옮기기 실패: $($_.Exception.Message)"; Log "$($script:LastErr) — 임시 파일은 $($c.tmp) 에 남음"; SetIcon; return }
  $kb = [Math]::Round((Get-Item -LiteralPath $dest).Length / 1024)
  Log "저장: $dest ($sec 초, $kb KB) · $why$(if ($folder -eq $Hold) { ' — 외장하드 없음, 임시 폴더' })"
  QueueAdd @{ file = (Split-Path $dest -Leaf); mrn = $c.mrn; name = $c.name; room = $Room; at = (Iso $c.start); endAt = (Iso $end); dur = $sec }
  SetIcon
}
# 외장하드가 다시 꽂히면 임시 폴더의 녹음을 옮긴다
function MoveHeld() {
  if (-not ($Dir -and (Test-Path -LiteralPath $Dir)) -or -not (Test-Path $Hold)) { return }
  Get-ChildItem -LiteralPath $Hold -Filter '*.wav' -ErrorAction SilentlyContinue | ForEach-Object {
    try { Move-Item -LiteralPath $_.FullName -Destination (Join-Path $Dir $_.Name) -ErrorAction Stop; Log "임시 폴더 → 외장하드: $($_.Name)" } catch { Log "임시 폴더 옮기기 실패 $($_.Name): $($_.Exception.Message)" } }
}

# ── 받아쓴 글 올리기: 녹음 옆에 같은 이름의 .txt 가 생기면 recText 에 (3일 지나면 포기) ──
function QueueGet() { try { if (Test-Path $QueueFile) { return @((Get-Content $QueueFile -Raw -Encoding UTF8 | ConvertFrom-Json)) } } catch {}; return @() }
function QueueSet($L) { try { ConvertTo-Json -InputObject @($L) -Depth 4 -Compress | Set-Content $QueueFile -Encoding UTF8 } catch {} }
function QueueAdd($x) { $L = @(QueueGet | Where-Object { $_ -and $_.file -ne $x.file }); $L += [pscustomobject]$x; QueueSet $L }
function RecDocId($file) { return (($file -replace '\.(wav|webm)$', '') -replace '[\/#?\[\]*]', '_').Substring(0, [Math]::Min(140, ($file -replace '\.(wav|webm)$', '').Length)) }
function PushTexts() {
  $L = @(QueueGet | Where-Object { $_ }); if (-not $L.Count) { return }
  $canUp = [bool]($BotPassword -or $script:Refresh)
  if (-not $canUp -and -not $script:NoPwLogged) { $script:NoPwLogged = $true; Log "비밀번호 파일이 없어 받아쓴 글은 동선관리에 올리지 않습니다(녹음·.txt 는 외장하드에 그대로): $SecretFile" }
  $keep = @(); $changed = $false
  for ($i = 0; $i -lt $L.Count; $i++) { $x = $L[$i]
    $old = $false; try { $old = ((Get-Date) - [DateTime]::Parse($x.at)).TotalDays -ge 3 } catch { $old = $true }
    if ($old) { $changed = $true; continue }   # 3일 지나면 목록에서 뺀다(파일은 외장하드에 그대로)
    if (-not $x.localDone -and $canUp) {   # 이 PC 받아쓰기(rec_transcribe.py)가 만든 '<녹음>.txt'
      $txt = $null
      foreach ($fd in @($Dir, $Hold)) { if (-not $fd) { continue }; $p = Join-Path $fd (($x.file -replace '\.wav$', '') + '.txt'); if (Test-Path -LiteralPath $p) { $txt = $p; break } }
      if ($txt) {
        try {
          $text = [IO.File]::ReadAllText($txt, [Text.Encoding]::UTF8).Trim(); if ($text.Length -gt 200000) { $text = $text.Substring(0, 200000) }
          PutRecText (RecDocId $x.file) ([ordered]@{ mrn = [string]$x.mrn; pid = ''; name = [string]$x.name; room = [string]$x.room; startedAt = [string]$x.at; endAt = [string]$x.endAt
            date = ([string]$x.at).Substring(0, 10); file = [string]$x.file; text = $text; src = 'local'; dur = [int]$x.dur; at = (NowIso); by = "녹음($Pc)" })
          Log "받아쓴 글 올림: $($x.file) ($($text.Length)자)"; $x | Add-Member -NotePropertyName localDone -NotePropertyValue $true -Force; $changed = $true }
        catch { Log "받아쓴 글 올리기 실패 $($x.file): $($_.Exception.Message)"; $keep += @($L[$i..($L.Count - 1)]); $changed = $true; break } }   # 인터넷·로그인 문제면 이것과 남은 것 모두 다음에 다시
    }
    if ($x.localDone -and (SttDone $x)) { $changed = $true; continue }   # 다 끝남
    $keep += $x
  }
  if ($changed) { QueueSet $keep }
}
if ($SttJob) { RunStt $SttJob; exit }   # (내부용) OpenAI 받아쓰기만 하고 끝 — 아래 화면·녹음은 띄우지 않는다

# ── 알림 영역 아이콘 ──
function DotIcon($r, $g, $b) { $bm = New-Object Drawing.Bitmap 16, 16; $gr = [Drawing.Graphics]::FromImage($bm); $gr.SmoothingMode = 'AntiAlias'
  $gr.Clear([Drawing.Color]::Transparent); $gr.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb($r, $g, $b))), 2, 2, 12, 12); $gr.Dispose()
  return [Drawing.Icon]::FromHandle($bm.GetHicon()) }
$IcoRec = DotIcon 220 38 38; $IcoIdle = DotIcon 148 163 184; $IcoWarn = DotIcon 245 158 11
$tray = New-Object Windows.Forms.NotifyIcon; $tray.Visible = $true
function SetIcon() {
  $hdd = ($Dir -and (Test-Path -LiteralPath $Dir))
  if ($script:Cur) { $m = [int]((Get-Date) - $script:Cur.start).TotalMinutes; $tray.Icon = $IcoRec; $t = "녹음 중 · $($script:Cur.name) · ${m}분" }
  elseif ($script:LastErr) { $tray.Icon = $IcoWarn; $t = "녹음 오류 · $($script:LastErr)" }
  elseif (-not $hdd) { $tray.Icon = $IcoWarn; $t = '녹음 대기 · 외장하드 없음(임시 폴더에 저장)' }
  else { $tray.Icon = $IcoIdle; $t = '진료 녹음 대기 · 외래진료실에 환자를 부르면 녹음' }
  if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }; $tray.Text = $t
}
$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('녹음 폴더 열기', $null, { $f = RecFolder; Start-Process explorer.exe "`"$f`"" })
[void]$menu.Items.Add('이번 환자 녹음 멈추기 (다음 환자부터 다시 녹음)', $null, { if ($script:Cur) { $script:StopKey = $script:Cur.mrn; StopRec '직접 멈춤' } })
[void]$menu.Items.Add('기록 보기', $null, { Start-Process notepad.exe "`"$LogFile`"" })
$tray.ContextMenuStrip = $menu

# ── 1.5초마다: 지금 환자 확인 → 바뀌었으면 끊고 새로 ──
#  흔들림 막기: 새 환자는 2번 연속(3초), '환자 없음'은 4번 연속(6초) 같은 값이어야 따른다
$script:Cand = ''; $script:CandN = 0; $script:CandP = $null; $script:Tick = 0
$script:WaitLog = ''; $script:OutN = 0   # 동선에서 이 진료실이 아니라 녹음을 기다리는 차트번호(기록 한 번만) · 녹음 중 동선에서 나간 횟수
function Poll() {
  $script:Tick++
  $p = $null; try { $p = CurrentPatient } catch { Log "창 읽기 오류: $($_.Exception.Message)"; return }
  $key = [string]$p.mrn
  # 차트번호 칸에 다른 번호를 치는 중(번호만 바뀌고 이름은 그대로) — 같은 환자로 본다. 다른 환자를 불러오면 이름도 바뀐다
  if ($script:Cur -and $key -and $key -ne $script:Cur.mrn -and $p.name -and $script:Cur.name -and $p.name -eq $script:Cur.name) { $key = $script:Cur.mrn }
  if ($key -eq $script:Cand) { $script:CandN++ } else { $script:Cand = $key; $script:CandN = 1 }
  $script:CandP = $p
  if ($script:Cur -and $key -eq $script:Cur.mrn -and -not $script:Cur.name -and $p.name) { $script:Cur.name = $p.name; $script:Cur.rrn7 = $p.rrn7 }   # 이름이 늦게 뜬 경우
  $need = if ($key) { 2 } else { 4 }
  if ($script:CandN -ge $need) {
    if ($script:StopKey -and $key -ne $script:StopKey) { $script:StopKey = '' }
    $curKey = if ($script:Cur) { $script:Cur.mrn } else { '' }
    if ($key -ne $curKey) {
      if ($script:Cur) { StopRec $(if ($key) { "환자 바뀜 → $($p.name) ($key)" } else { '외래진료실 환자 없음' }) }
      if ($key -and $key -ne $script:StopKey) {
        if (InRoomOnBoard $key) { $script:WaitLog = ''; $script:OutN = 0; StartRec $p }
        elseif ($script:WaitLog -ne $key) { $script:WaitLog = $key; Log "녹음 안 함: $($p.name) ($key) — 동선관리에서 지금 $Room 이 아님($($script:BoardRoom[$key])). 카드가 $Room 로 오면 시작" }
      }
    }
  }
  # 녹음 중 동선관리에서 이 진료실을 나갔으면(10초 간격 2번 연속) 끊는다 — 비트 창에 차트가 남아 있어도
  if ($script:Cur -and $script:Tick % 7 -eq 0) {
    if (InRoomOnBoard $script:Cur.mrn) { $script:OutN = 0 }
    elseif (++$script:OutN -ge 2) { $script:OutN = 0; $script:WaitLog = $script:Cur.mrn; StopRec "동선관리에서 $Room 을 나감($($script:BoardRoom[$script:Cur.mrn]))" }
  }
  if ($script:Cur -and ((Get-Date) - $script:Cur.start).TotalMinutes -ge $MaxMin) { $script:StopKey = $script:Cur.mrn; StopRec "최대 ${MaxMin}분" }
  if ($script:Tick % 4 -eq 0) { SetIcon }
  if ($script:Tick % 20 -eq 0) { try { MoveHeld } catch {}; try { PushTexts } catch { Log "글 올리기 오류: $($_.Exception.Message)" }; try { SttNext } catch { Log "받아쓰기 오류: $($_.Exception.Message)" } }   # 30초마다
}

# 숨은 창: 로그오프·종료 때 녹음 중이면 저장하고 끝낸다
$form = New-Object Windows.Forms.Form
$form.ShowInTaskbar = $false; $form.WindowState = 'Minimized'; $form.FormBorderStyle = 'FixedToolWindow'; $form.Opacity = 0; $form.Size = New-Object Drawing.Size 1, 1
$form.Add_Shown({ $form.Hide() })
$form.Add_FormClosing({ try { StopRec '프로그램 종료(로그오프·종료)' } catch {}; try { $tray.Visible = $false; $tray.Dispose() } catch {} })
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1500; $timer.Add_Tick({ try { Poll } catch { Log "주기 오류: $($_.Exception.Message)" } }); $timer.Start()
Log "시작: PC=$Pc 진료실=$Room 폴더=$(if ($Dir) { $Dir } else { '(없음 — 임시 폴더)' }) 최대 ${MaxMin}분$(if ($SimFile) { ' [시험: ' + $SimFile + ']' })"
if (-not $Dir) { Log '녹음 폴더가 정해지지 않았습니다 — clinic_rec_install.ps1 로 외장하드 폴더를 고르세요' }
SetIcon
[Windows.Forms.Application]::Run($form)
try { StopRec '끝' } catch {}
Log '종료'
