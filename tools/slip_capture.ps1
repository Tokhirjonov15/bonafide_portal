# ─────────────────────────────────────────────────────────────
#  슬립 캡처 (진료실 PC) — 2026-10-06
#  화면 위에 늘 떠 있는 작은 바. 비트 외래진료실 창의 '지금 환자'(차트번호·이름)를 보여 주고,
#  [캡처]를 누르면 화면이 어두워진다 → 팍스 화면 등에서 원하는 부분을 끌어서 고르면 그 부분을 잘라 그 환자의 오늘 슬립에 올린다.
#   · 사진: Firebase Storage  patient_photos/{차트번호}/slip_{id}.jpg  (환자 사진과 같은 저장소)
#   · 기록: bitNote/{날짜}_{차트번호} 의 shots 배열에 덧붙임 → 동선관리 슬립 화면·[창 띄우기]에 그 환자와 함께 뜬다
#  비트에는 아무것도 입력·클릭하지 않는다(창의 차트번호·이름만 읽음 — 감시 스크립트와 같은 방법).
#  로그인: 같은 폴더의 bitplus_watcher.secret(bitbot 비밀번호). 세션은 slip_capture.token 에 따로 둔다.
#  설치: slip_capture_install.ps1 (진료실 PC, 감시 스크립트가 설치된 뒤)
#  바 사용: 바를 끌어서 옮김 · 오른쪽 클릭 = 메뉴(위치 초기화 / 잠시 끄기) · 캡처 중 Esc 또는 오른쪽 클릭 = 취소
# ─────────────────────────────────────────────────────────────
#  환자 정하기: ① 비트 외래진료실 창에 지금 열린 환자(차트번호) ② 없으면 동선관리에서 이 진료실($Room)에 '진행' 중인 카드
#             캡처 화면 위에 누구 슬립으로 가는지 이름을 크게 보여 준다.
param([string]$Pc = $env:COMPUTERNAME,
      [string]$Room = '')   # 동선관리 방 이름(예: 진료실1). 비우면 PC 이름이 '진료실…'일 때 그 이름
$ErrorActionPreference = 'Continue'
$ApiKey    = 'AIzaSyDBj3z-Qj9DyT1ZgDNps1-Yp9ZBopeWr0w'
$ProjectId = 'bonafide-dongseon-108e2'
$Bucket    = 'bonafide-dongseon-108e2.firebasestorage.app'
$BotEmail  = 'uc8feac453b1a01cc028b072a@bonafide.app'   # 동선관리 계정 'bitbot'
$MaxSide   = 2400   # 잘라 낸 사진의 긴 변 최대(px) — 엑스레이 세부가 보이도록 넉넉히
$BoardDoc  = 'patientboard_v3/' + [Uri]::EscapeDataString('반듯한정형외과')   # 동선관리 보드 문서(카드: …/patients)
if (-not $Room -and $Pc -match '^진료실') { $Room = $Pc }
$SecretFile = Join-Path $PSScriptRoot 'bitplus_watcher.secret'
$TokenFile  = Join-Path $PSScriptRoot 'slip_capture.token'
$LogDir = Join-Path $env:LOCALAPPDATA 'bitplus_watcher'; New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'slip_capture.log'
$PosFile = Join-Path $LogDir 'slip_capture.pos'
function Log($m) { try { Add-Content $LogFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" -Encoding UTF8 } catch {} }
function NowIso() { return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }

# 한 번만 실행 (로그온 작업이 5분마다 다시 시작해도 이미 떠 있으면 그냥 끝난다)
$script:Mtx = New-Object System.Threading.Mutex($false, 'Local\BonafideSlipCapture')
if (-not $script:Mtx.WaitOne(0)) { exit }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace SlipCap -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr v);
[DllImport("user32.dll")] public static extern bool ReleaseCapture();
[DllImport("user32.dll")] public static extern System.IntPtr SendMessage(System.IntPtr h, int m, int w, int l);
'@
# 배율(125%·150%) 화면에서도 캡처 좌표가 실제 픽셀과 맞도록 — 모니터마다 배율이 달라도 맞게(모니터별 v2, Windows 10 1703+). 안 되면 예전 방식
$dpiOk = $false; try { $dpiOk = [SlipCap.U]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch {}
if (-not $dpiOk) { [void][SlipCap.U]::SetProcessDPIAware() }
[Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not (Test-Path $SecretFile)) { [Windows.Forms.MessageBox]::Show("비밀번호 파일이 없습니다:`n$SecretFile`n`n먼저 감시 스크립트(bitplus_install.ps1)를 설치하세요.", '슬립 캡처') | Out-Null; exit 1 }
$BotPassword = (Get-Content $SecretFile -Encoding UTF8 -TotalCount 1).Trim()

# ── 비트 외래진료실 창 읽기 (bitplus_watcher.ps1 에서 그대로 가져옴 — 고칠 때 함께 고친다) ──
Add-Type -Namespace BitW -Name U32 -UsingNamespace System.Collections.Generic, System.Text -MemberDefinition @'
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
// WM_GETTEXT 를 SendMessageTimeout 으로 보낸다: 비트 창의 UI 스레드가 멈춰 있어도(모달 대화상자 등) 감시 스크립트가 함께 멈추지 않도록 500ms 안에 응답 없으면 포기(SMTO_ABORTIFHUNG)
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
  if (SendMessageTimeout(h, 0x000E, IntPtr.Zero, IntPtr.Zero, 0x0002, 500, out res) == IntPtr.Zero) return "";  // WM_GETTEXTLENGTH
  int n = (int)res; if (n <= 0) return "";
  var sb = new StringBuilder(n + 2);
  if (SendMessageTimeout(h, 0x000D, (IntPtr)(n + 1), sb, 0x0002, 500, out res) == IntPtr.Zero) return "";  // WM_GETTEXT
  return sb.ToString();
}
public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
public static int Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return (int)p; }
'@

function FindDoctorWindow() {   # '외래진료실 …' 제목의 최상위 창 (BITDoctorOrder.exe). 없으면 $null (접수 PC에서는 보통 없음)
  $proc = Get-Process -Name BITDoctorOrder -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $proc) { return $null }
  foreach ($h in [BitW.U32]::Tops()) { if ([BitW.U32]::Pid($h) -ne $proc.Id) { continue }
    if ((([BitW.U32]::Text($h)) -replace '\s', '') -like '외래진료실*') { return $h } }
  return $null
}
function Rrn7($t) { $m = [regex]::Match([string]$t, '^\s*(\d{6})-?(\d)'); if ($m.Success) { return $m.Groups[1].Value + '-' + $m.Groups[2].Value } else { return '' } }
function SexOf($t) { if ([string]$t -match '^\s*\(M/') { return '남' } elseif ([string]$t -match '^\s*\(F/') { return '여' } else { return '' } }
$script:DocCache = $null   # 외래진료실 컨트롤 핸들 캐시: @{ hwnd; mrn; name; note; memo } — 한 번 찾은 뒤에는 4개 칸만 읽는다 (수백 개 컨트롤을 매번 읽으면 비트가 바쁠 때 주기가 10초 넘게 늘어남)
function ReadDoctor($hwnd) {   # 차트번호(라벨 오른쪽 EDIT) · 수진자명(라벨 오른쪽 라벨) · 증상(가장 위쪽의 넓은 RichEdit) · 특이사항(증상 오른쪽 RichEdit) — 읽기 전용
  $c = $script:DocCache
  $okH = { param($h) ($null -eq $h) -or [BitW.U32]::IsWindow($h) }   # 없는 칸($null)은 통과, 있던 칸은 아직 살아 있어야
  if ($c -and $c.hwnd -eq [IntPtr]$hwnd -and [BitW.U32]::IsWindow($c.mrn) -and [BitW.U32]::IsWindow($c.note) -and (& $okH $c.memo) -and (& $okH $c.name) -and (& $okH $c.rrn) -and (& $okH $c.sex)) {
    # 빈 창(환자 없음)일 때 만든 캐시라 이름·성별·주민·특이사항 칸을 못 찾았으면, 환자가 올라온 뒤 몇 번 더 찾아본다(그래도 없으면 이 창 구성에는 그 칸이 없는 것)
    $missing = ($null -eq $c.name) -or ($null -eq $c.rrn) -or ($null -eq $c.sex) -or ($null -eq $c.memo)
    if ($missing -and $script:DocRetry -lt 5 -and ((([BitW.U32]::Text($c.mrn)) -replace '\D', '') -ne '')) { $script:DocRetry++; $script:DocCache = $null }
    else { return @{ mrn = (([BitW.U32]::Text($c.mrn)) -replace '\D', ''); name = $(if ($null -ne $c.name) { ([BitW.U32]::Text($c.name)).Trim() } else { '' })
              note = [BitW.U32]::Text($c.note); memo = $(if ($null -ne $c.memo) { [BitW.U32]::Text($c.memo) } else { '' })
              rrn7 = (Rrn7 $(if ($null -ne $c.rrn) { [BitW.U32]::Text($c.rrn) } else { '' })); sex = (SexOf $(if ($null -ne $c.sex) { [BitW.U32]::Text($c.sex) } else { '' })); found = $true } }
  }
  $script:DocCache = $null
  $els = @()
  foreach ($h in [BitW.U32]::Children([IntPtr]$hwnd)) {
    # WinForms 클래스명은 'WindowsForms10.<종류>.app…' 꼴 → 종류만 본다 (라벨=Window/STATIC, 차트번호=EDIT, 증상=RichEdit20W). 숨은 탭·패널의 컨트롤은 제외
    $cls = [BitW.U32]::Cls($h); if ($cls -notmatch '\.(Window|STATIC|EDIT|RichEdit\w*|RICHEDIT\w*)\.') { continue }
    if (-not [BitW.U32]::IsWindowVisible($h)) { continue }
    $r = New-Object BitW.U32+RECT; [void][BitW.U32]::GetWindowRect($h, [ref]$r)
    if (($r.R - $r.L) -le 0) { continue }
    $els += [pscustomobject]@{ hw = $h; x = $r.L; y = $r.T; w = ($r.R - $r.L); h = ($r.B - $r.T); cls = $cls; name = [BitW.U32]::Text($h) }
  }
  $lblMrn = $els | Where-Object { (($_.name -replace '\s', '') -eq '차트번호') -and $_.w -lt 120 } | Select-Object -First 1
  $lblName = $els | Where-Object { (($_.name -replace '\s', '') -eq '수진자명') -and $_.w -lt 120 } | Select-Object -First 1
  if (-not $lblMrn) { return $null }
  $mrnEl = $els | Where-Object { $_.cls -match 'EDIT' -and [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.x -ge ($lblMrn.x + $lblMrn.w - 8) -and $_.x -le ($lblMrn.x + $lblMrn.w + 60) } | Sort-Object x | Select-Object -First 1
  # 차트번호 줄의 라벨은 '수진자명' 오른쪽으로 이름(80px) → 성별/나이 '(M/26세…' (120px) → 주민번호 '######-#######' (115px) → '보험유형' 순으로 빈틈없이 붙어 있다.
  # 환자를 아직 안 불렀을 때는 텍스트가 비어 있으므로 텍스트가 아니라 자리(앞 라벨의 오른쪽 끝에 붙은 라벨)로 찾는다. 주민번호는 앞 7자리(YYMMDD-S)만 쓴다(카드가 없어도 슬립에 생년월일을 찍기 위함)
  $rowLbl = @($els | Where-Object { $_.cls -match '\.(Window|STATIC)\.' -and [Math]::Abs($_.y - $lblMrn.y) -le 10 } | Sort-Object x)
  $nextOf = { param($e) $rowLbl | Where-Object { $_.hw -ne $e.hw -and [Math]::Abs($_.x - ($e.x + $e.w)) -le 8 } | Sort-Object x | Select-Object -First 1 }
  $nameEl = $null; $sexEl = $null; $rrnEl = $null
  if ($lblName) {
    $nameEl = & $nextOf $lblName
    if ($nameEl) { $sexEl = & $nextOf $nameEl }
    if ($sexEl) { $rrnEl = & $nextOf $sexEl }
    # 텍스트가 있는데 모양이 다르면(창 구성이 다른 경우) 자리로 찾은 것을 버리고 텍스트로 다시 찾는다
    if ($nameEl -and (($nameEl.name -replace '\s', '') -in @('보험유형','특이사항','조합기호','증번호'))) { $nameEl = $null; $sexEl = $null; $rrnEl = $null }
    if ($sexEl -and $sexEl.name.Trim() -and $sexEl.name -notmatch '^\s*\((M|F)/') { $sexEl = $null }
    if ($rrnEl -and $rrnEl.name.Trim() -and $rrnEl.name -notmatch '^\s*\d{6}-') { $rrnEl = $null }
  }
  if (-not $nameEl -and $lblName) { $nameEl = $els | Where-Object { $_.hw -ne $lblName.hw -and [Math]::Abs($_.y - $lblName.y) -le 10 -and $_.x -ge ($lblName.x + $lblName.w - 8) -and $_.x -le ($lblName.x + $lblName.w + 60) -and $_.name.Trim() } | Sort-Object x | Select-Object -First 1 }
  if (-not $rrnEl) { $rrnEl = $els | Where-Object { [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.name -match '^\s*\d{6}-\d' } | Select-Object -First 1 }
  if (-not $sexEl) { $sexEl = $els | Where-Object { [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.name -match '^\s*\((M|F)/' } | Select-Object -First 1 }
  # 증상 칸: 차트번호 줄보다 아래에 있는 RichEdit 중 화면에서 가장 위(y 최소)이면서 폭 200 이상인 것 (주호소/현병력 소형 칸·특이사항·과거내역 칸 제외)
  $noteEl = $els | Where-Object { $_.cls -match 'RichEdit|RICHEDIT' -and $_.w -ge 200 -and $_.h -ge 60 -and $_.y -gt $lblMrn.y } | Sort-Object y, @{ Expression = { -($_.w * $_.h) } } | Select-Object -First 1
  # 특이사항 칸: 증상 칸 오른쪽(증상 오른 끝 근처부터 시작)에서 증상 칸 세로 범위 안에 있는 RichEdit (환자에게 따라다니는 메모 — 진료 뒤에 적힘)
  $memoEl = $null
  if ($noteEl) { $memoEl = $els | Where-Object { $_.cls -match 'RichEdit|RICHEDIT' -and $_ -ne $noteEl -and $_.w -ge 150 -and $_.h -ge 60 -and $_.x -ge ($noteEl.x + $noteEl.w - 20) -and $_.y -ge $noteEl.y -and $_.y -le ($noteEl.y + $noteEl.h + 120) } | Sort-Object x, y | Select-Object -First 1 }
  $mrn = if ($mrnEl) { ($mrnEl.name -replace '\D', '') } else { '' }
  if ($mrnEl -and $noteEl) {   # 다음 주기부터는 이 핸들들만 읽는다 (비트가 화면을 다시 만들면 IsWindow 가 false → 다시 탐색)
    $script:DocCache = @{ hwnd = [IntPtr]$hwnd; mrn = $mrnEl.hw; note = $noteEl.hw; name = $(if ($nameEl) { $nameEl.hw } else { $null }); memo = $(if ($memoEl) { $memoEl.hw } else { $null }); rrn = $(if ($rrnEl) { $rrnEl.hw } else { $null }); sex = $(if ($sexEl) { $sexEl.hw } else { $null }) }
    if ($nameEl -and $rrnEl -and $sexEl -and $memoEl) { $script:DocRetry = 0 }
  }
  return @{ mrn = $mrn; name = $(if ($nameEl) { $nameEl.name.Trim() } else { '' }); note = $(if ($noteEl) { $noteEl.name } else { '' }); memo = $(if ($memoEl) { $memoEl.name } else { '' }); rrn7 = (Rrn7 $(if ($rrnEl) { $rrnEl.name } else { '' })); sex = (SexOf $(if ($sexEl) { $sexEl.name } else { '' })); found = ($null -ne $noteEl) }
}

$script:DocRetry = 0

# ── Firebase 로그인 (감시 스크립트와 같은 방식: refresh 토큰 우선, 실패 뒤 바로 재시도하지 않음) ──
$script:Tok = $null; $script:TokExp = [DateTime]::MinValue; $script:Refresh = $null; $script:LoginFailAt = [DateTime]::MinValue
if (Test-Path $TokenFile) { try { $script:Refresh = (Get-Content $TokenFile -TotalCount 1 -ErrorAction Stop).Trim() } catch { $script:Refresh = $null } }
function SaveRefresh($rt) { try { if ($rt) { [IO.File]::WriteAllText($TokenFile, $rt, (New-Object Text.UTF8Encoding $false)) } } catch {} }
function FbToken() {
  if ($script:Tok -and (Get-Date) -lt $script:TokExp) { return $script:Tok }
  if ($script:Refresh) {
    try {
      $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://securetoken.googleapis.com/v1/token?key=$ApiKey" -ContentType 'application/x-www-form-urlencoded' -Body "grant_type=refresh_token&refresh_token=$($script:Refresh)"
      $script:Tok = $r.id_token; $script:Refresh = $r.refresh_token; $script:TokExp = (Get-Date).AddSeconds([int]$r.expires_in - 300); SaveRefresh $script:Refresh
      return $script:Tok
    } catch { Log "토큰 갱신 실패 → 비밀번호로 재로그인: $($_.Exception.Message)"; $script:Refresh = $null }
  }
  if (((Get-Date) - $script:LoginFailAt).TotalSeconds -lt 120) { throw "로그인 대기 중(최근 실패) — 2분 뒤 다시 시도하세요" }
  $body = @{ email = $BotEmail; password = $BotPassword; returnSecureToken = $true } | ConvertTo-Json -Compress
  try { $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$ApiKey" -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) }
  catch { $script:LoginFailAt = Get-Date; throw "로그인 실패: $($_.Exception.Message)" }
  $script:Tok = $r.idToken; $script:Refresh = $r.refreshToken; $script:TokExp = (Get-Date).AddSeconds([int]$r.expiresIn - 300); SaveRefresh $script:Refresh
  Log "Firebase 로그인 성공"
  return $script:Tok
}
function PmKey($mrn) { $k = ([string]$mrn).Trim() -replace '[^\w-]', '_'; if ($k) { return $k } else { return '_' } }   # 웹 pmKey 와 같게

# ── 올리기: Storage 에 사진 → bitNote 문서의 shots 배열에 덧붙임(없으면 문서 생성) ──
function UploadShot([byte[]]$bytes, $mrn, $name, $w, $h) {
  $tok = FbToken
  $id = 'sc' + (Get-Date).ToString('yyyyMMddHHmmssfff')
  $path = "patient_photos/$(PmKey $mrn)/slip_$id.jpg"
  $u = "https://firebasestorage.googleapis.com/v0/b/$Bucket/o?uploadType=media&name=" + [Uri]::EscapeDataString($path)
  Invoke-RestMethod -TimeoutSec 60 -Method Post -Uri $u -Headers @{ Authorization = "Bearer $tok" } -ContentType 'image/jpeg' -Body $bytes | Out-Null
  $day = (Get-Date).ToString('yyyy-MM-dd')
  $doc = "projects/$ProjectId/databases/(default)/documents/bitNote/${day}_$mrn"
  $shot = @{ mapValue = @{ fields = @{ id = @{ stringValue = $id }; path = @{ stringValue = $path }; at = @{ stringValue = (NowIso) }; pc = @{ stringValue = $Pc }
                                       w = @{ integerValue = "$w" }; h = @{ integerValue = "$h" } } } }
  $fields = @{ date = @{ stringValue = $day }; mrn = @{ stringValue = "$mrn" }; shotAt = @{ stringValue = (NowIso) } }
  $mask = @('date', 'mrn', 'shotAt')
  if ($name) { $fields['shotName'] = @{ stringValue = "$name" }; $mask += 'shotName' }   # 이름은 감시 스크립트의 name 칸을 건드리지 않게 따로
  $write = @{ update = @{ name = $doc; fields = $fields }; updateMask = @{ fieldPaths = $mask }
              updateTransforms = @(@{ fieldPath = 'shots'; appendMissingElements = @{ values = @($shot) } }) }
  $json = (@{ writes = @($write) } | ConvertTo-Json -Depth 30 -Compress)
  Invoke-RestMethod -TimeoutSec 30 -Method Post -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents:commit" -Headers @{ Authorization = "Bearer $tok" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
  Log "올림 $mrn $name ${w}x$h $path"
}

# ── 동선관리에서 이 진료실에 '진행' 중인 카드 (비트 창에 환자가 없을 때만, [캡처]를 누른 순간 한 번 읽는다) ──
function FsVal($v) { if ($null -eq $v) { return $null }; if ($null -ne $v.stringValue) { return $v.stringValue }; if ($null -ne $v.integerValue) { return [int]$v.integerValue }; if ($null -ne $v.booleanValue) { return [bool]$v.booleanValue }; return $null }
function BoardPatient() {
  if (-not $Room) { return $null }
  $tok = FbToken
  $r = Invoke-RestMethod -TimeoutSec 20 -Method Get -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$BoardDoc/patients?pageSize=300" -Headers @{ Authorization = "Bearer $tok" }
  $hits = @()
  foreach ($d in @($r.documents)) { if (-not $d) { continue }; $f = $d.fields
    if (FsVal $f.discharged) { continue }
    $route = @(); if ($f.route -and $f.route.arrayValue -and $f.route.arrayValue.values) { $route = @($f.route.arrayValue.values | ForEach-Object { $_.stringValue }) }
    if (-not $route.Count) { continue }
    $st = [int](FsVal $f.step); if ($st -lt 0) { $st = 0 }; if ($st -ge $route.Count) { $st = $route.Count - 1 }
    if ($route[$st] -ne $Room -or (FsVal $f.status) -ne '진행') { continue }
    $hits += [pscustomobject]@{ mrn = ([string](FsVal $f.mrn)).Trim(); name = [string](FsVal $f.name); since = [string](FsVal $f.statusSince) } }
  return ($hits | Sort-Object since -Descending | Select-Object -First 1)   # 둘 이상이면 가장 최근에 [진행]을 누른 환자
}

# ── 화면 전체를 찍고, 어둡게 덮은 창에서 끌어 고른 네모를 돌려준다 (취소 = $null) ──
function SelectRegion($who) {
  $vs = [Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object Drawing.Bitmap $vs.Width, $vs.Height
  $g0 = [Drawing.Graphics]::FromImage($bmp); $g0.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $bmp.Size); $g0.Dispose()
  $f = New-Object Windows.Forms.Form
  $f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.Bounds = $vs; $f.TopMost = $true; $f.ShowInTaskbar = $false; $f.KeyPreview = $true
  $f.Cursor = [Windows.Forms.Cursors]::Cross
  $f.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($f, $true, $null)
  $script:SelP0 = $null; $script:SelRect = $null; $script:SelOut = $null
  $dim = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(120, 0, 0, 0))
  $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 59, 130, 246)), 3
  $font = New-Object Drawing.Font 'Malgun Gothic', 16, ([Drawing.FontStyle]::Bold)
  $tagBg = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(220, 30, 64, 175))   # 누구 슬립인지 띠
  $f.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.DrawImage($bmp, 0, 0, $bmp.Width, $bmp.Height); $g.FillRectangle($dim, 0, 0, $s.Width, $s.Height)   # 크기를 픽셀로 못 박는다 — DrawImageUnscaled 는 배율(125%·150%) 화면에서 사진을 확대해 그렸다(2026-10-06)
    if ($script:SelRect) { $r = $script:SelRect; $g.DrawImage($bmp, $r, $r, [Drawing.GraphicsUnit]::Pixel); $g.DrawRectangle($pen, $r)
      $g.DrawString("$($r.Width) × $($r.Height)", $font, [Drawing.Brushes]::White, [float]$r.X, [float]([Math]::Max(0, $r.Y - 32))) }
    $g.FillRectangle($tagBg, 20, 20, 900, 44)
    $g.DrawString("→ $who  슬립에 올립니다  ·  끌어서 고르기  ·  Esc = 취소", $font, [Drawing.Brushes]::White, 30, 27) })
  $f.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Right') { $s.Close(); return }; $script:SelP0 = $e.Location })
  $f.Add_MouseMove({ param($s, $e) if ($null -eq $script:SelP0) { return }
    $x = [Math]::Min($script:SelP0.X, $e.X); $y = [Math]::Min($script:SelP0.Y, $e.Y)
    $script:SelRect = New-Object Drawing.Rectangle $x, $y, ([Math]::Abs($e.X - $script:SelP0.X)), ([Math]::Abs($e.Y - $script:SelP0.Y)); $s.Invalidate() })
  $f.Add_MouseUp({ param($s, $e) if ($script:SelRect -and $script:SelRect.Width -ge 10 -and $script:SelRect.Height -ge 10) { $script:SelOut = $script:SelRect; $s.Close() } else { $script:SelP0 = $null; $script:SelRect = $null; $s.Invalidate() } })
  $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $s.Close() } })
  [void]$f.ShowDialog(); $f.Dispose()
  if (-not $script:SelOut) { $bmp.Dispose(); return $null }
  $r = $script:SelOut
  $crop = $bmp.Clone($r, $bmp.PixelFormat); $bmp.Dispose()
  $sc = [Math]::Min(1.0, $MaxSide / [double][Math]::Max($r.Width, $r.Height))
  if ($sc -lt 1.0) { $nw = [int]($r.Width * $sc); $nh = [int]($r.Height * $sc); $rs = New-Object Drawing.Bitmap $nw, $nh
    $gr = [Drawing.Graphics]::FromImage($rs); $gr.InterpolationMode = 'HighQualityBicubic'; $gr.DrawImage($crop, 0, 0, $nw, $nh); $gr.Dispose(); $crop.Dispose(); $crop = $rs }
  $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
  $ep = New-Object Drawing.Imaging.EncoderParameters 1; $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), ([long]92)
  $ms = New-Object IO.MemoryStream; $crop.Save($ms, $codec, $ep)
  $out = @{ bytes = $ms.ToArray(); w = $crop.Width; h = $crop.Height }; $crop.Dispose(); $ms.Dispose()
  return $out
}

# ── 바 ──
$script:CurMrn = ''; $script:CurName = ''; $script:HoldUntil = [DateTime]::MinValue
$bar = New-Object Windows.Forms.Form
$bar.FormBorderStyle = 'None'; $bar.TopMost = $true; $bar.ShowInTaskbar = $false; $bar.StartPosition = 'Manual'
$bar.Size = New-Object Drawing.Size 360, 38; $bar.BackColor = [Drawing.Color]::FromArgb(30, 41, 59); $bar.Opacity = 0.96
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$bar.Location = New-Object Drawing.Point ([int]($wa.Left + ($wa.Width - 360) / 2)), $wa.Top
try { if (Test-Path $PosFile) { $p = (Get-Content $PosFile -TotalCount 1) -split ','; $pt = New-Object Drawing.Point ([int]$p[0]), ([int]$p[1])
    if ([Windows.Forms.SystemInformation]::VirtualScreen.Contains($pt)) { $bar.Location = $pt } } } catch {}
$btn = New-Object Windows.Forms.Button
$btn.Text = '캡처'; $btn.Font = New-Object Drawing.Font 'Malgun Gothic', 10, ([Drawing.FontStyle]::Bold)
$btn.FlatStyle = 'Flat'; $btn.FlatAppearance.BorderSize = 0; $btn.BackColor = [Drawing.Color]::FromArgb(59, 130, 246); $btn.ForeColor = [Drawing.Color]::White
$btn.Location = New-Object Drawing.Point 4, 4; $btn.Size = New-Object Drawing.Size 78, 30; $btn.Cursor = [Windows.Forms.Cursors]::Hand
$lbl = New-Object Windows.Forms.Label
$lbl.Font = New-Object Drawing.Font 'Malgun Gothic', 10; $lbl.ForeColor = [Drawing.Color]::White; $lbl.AutoSize = $false; $lbl.TextAlign = 'MiddleLeft'
$lbl.Location = New-Object Drawing.Point 88, 4; $lbl.Size = New-Object Drawing.Size 266, 30; $lbl.Text = '비트 외래진료실 확인 중…'
$bar.Controls.AddRange(@($btn, $lbl))
$drag = { param($s, $e) if ($e.Button -eq 'Left') { [void][SlipCap.U]::ReleaseCapture(); [void][SlipCap.U]::SendMessage($bar.Handle, 0xA1, 2, 0); try { "$($bar.Left),$($bar.Top)" | Set-Content $PosFile } catch {} } }   # 끌어서 옮기기
$bar.Add_MouseDown($drag); $lbl.Add_MouseDown($drag)
$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('위치 초기화 (화면 위 가운데)', $null, { $bar.Location = New-Object Drawing.Point ([int]($wa.Left + ($wa.Width - 360) / 2)), $wa.Top; try { Remove-Item $PosFile -ErrorAction SilentlyContinue } catch {} })
[void]$menu.Items.Add('잠시 끄기 (5분 안에 다시 켜짐)', $null, { $bar.Close() })
$bar.ContextMenuStrip = $menu; $lbl.ContextMenuStrip = $menu

function SetStatus($text, $color, $sec) { $lbl.Text = $text; $lbl.ForeColor = $color; $script:HoldUntil = (Get-Date).AddSeconds($sec) }
function ReadPatient() {
  if ((Get-Date) -lt $script:HoldUntil) { return }
  $mrn = ''; $name = ''
  try { $h = FindDoctorWindow; if ($h) { $d = ReadDoctor $h; if ($d) { $mrn = [string]$d.mrn; $name = [string]$d.name } } } catch { Log "창 읽기 오류: $($_.Exception.Message)" }
  $script:CurMrn = $mrn; $script:CurName = $name
  $btn.Enabled = [bool]$mrn -or [bool]$Room
  if ($mrn) { $lbl.ForeColor = [Drawing.Color]::White; $lbl.Text = "$name  ·  $mrn" }
  elseif ($Room) { $lbl.ForeColor = [Drawing.Color]::FromArgb(148, 163, 184); $lbl.Text = "비트 환자 없음 → $Room 진행 환자로" }
  else { $lbl.ForeColor = [Drawing.Color]::FromArgb(148, 163, 184); $lbl.Text = '비트 외래진료실에 환자 없음' }
}
$btn.Add_Click({
  $mrn = $script:CurMrn; $name = $script:CurName; $src = '비트'
  if (-not $mrn) {   # 비트 창에 환자가 없으면 동선관리에서 이 진료실의 [진행] 카드
    if (-not $Room) { return }
    SetStatus "동선관리에서 $Room 진행 환자 찾는 중…" ([Drawing.Color]::FromArgb(253, 224, 71)) 30; [Windows.Forms.Application]::DoEvents()
    $bp = $null; try { $bp = BoardPatient } catch { Log "동선관리 읽기 실패: $($_.Exception.Message)" }
    if (-not $bp) { SetStatus "✖ $Room 에 진행 중인 환자가 없습니다" ([Drawing.Color]::FromArgb(252, 165, 165)) 6; return }
    if (-not $bp.mrn) { SetStatus "✖ $($bp.name) 카드에 차트번호가 없습니다" ([Drawing.Color]::FromArgb(252, 165, 165)) 6; return }
    $mrn = $bp.mrn; $name = $bp.name; $src = '동선관리'
    $script:HoldUntil = [DateTime]::MinValue
  }
  $bar.Hide(); [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 250
  $shot = $null
  try { $shot = SelectRegion "$name ($mrn)" } catch { Log "캡처 오류: $($_.Exception.Message)" }
  $bar.Show(); $bar.TopMost = $true
  if (-not $shot) { return }
  SetStatus "올리는 중…  $name" ([Drawing.Color]::FromArgb(253, 224, 71)) 60; [Windows.Forms.Application]::DoEvents()
  try { UploadShot $shot.bytes $mrn $name $shot.w $shot.h; Log "환자 출처: $src"; SetStatus "✔ 슬립에 올림  ·  $name" ([Drawing.Color]::FromArgb(134, 239, 172)) 4 }
  catch { $m = $_.Exception.Message; Log "올리기 실패 $mrn : $m"; SetStatus "✖ 올리기 실패 — 다시 눌러 주세요" ([Drawing.Color]::FromArgb(252, 165, 165)) 8
    [Windows.Forms.MessageBox]::Show("슬립에 올리지 못했습니다.`n`n$m`n`n로그: $LogFile", '슬립 캡처') | Out-Null }
})
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1500; $timer.Add_Tick({ ReadPatient }); $timer.Start()
$bar.Add_Shown({ ReadPatient })
Log "시작 ($Pc)"
[Windows.Forms.Application]::Run($bar)
Log "종료"
