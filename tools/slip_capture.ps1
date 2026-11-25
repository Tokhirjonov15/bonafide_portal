# ─────────────────────────────────────────────────────────────
#  슬립 캡처 (진료실 PC) — 2026-10-06
#  화면 위에 늘 떠 있는 작은 바. 비트 외래진료실 창의 '지금 환자'(차트번호·이름)를 보여 주고,
#  [캡처]를 누르면 화면이 어두워진다 → 팍스 화면 등에서 원하는 부분을 끌어서 고르면 그 부분을 잘라 그 환자의 오늘 슬립에 올린다.
#   · 사진: Firebase Storage  patient_photos/{차트번호}/slip_{id}.jpg  (환자 사진과 같은 저장소)
#   · 기록: bitNote/{날짜}_{차트번호} 의 shots 배열에 덧붙임 → 동선관리 슬립 화면·[창 띄우기]에 그 환자와 함께 뜬다
#  비트에는 아무것도 입력·클릭하지 않는다(창의 차트번호·이름만 읽음 — 감시 스크립트와 같은 방법).
#  로그인: 같은 폴더의 bitplus_watcher.secret(bitbot 비밀번호). 세션은 slip_capture.token 에 따로 둔다.
#  설치: slip_capture_install.ps1 (진료실 PC, 감시 스크립트가 설치된 뒤)
#  2026-10-13: 버튼 둘 — [주사 캡처](예전 [캡처], 슬립으로) · [PT 캡처](4층으로: shots 에 kind='pt' → 4층 예약 스케줄 위 알림 + 4층 카드 색)
#  2026-11-17: [진료 캡처](kind='rec') — 진료실 이미지 기록용. 슬립·4층에는 안 가고 [지난 캡처]·동선관리 환자 정보 창에만 따로 남는다
#  2026-11-17 c1.2: [진료 캡처]는 이 PC 에도 jpg 로 남긴다 — C:\진료캡처\{차트번호}_{이름}\{날짜_시각}.jpg (안 되면 내 문서\진료캡처). 오른쪽 클릭 메뉴 = 폴더 열기
#  2026-11-25 c1.3: [원장님 확인 요청] — 같은 폴더에 rx_approve.on 파일이 있는 PC(처방 확인용 PC)에서만 보인다.
#     간호가 비트 외래진료실에서 처방을 바꾸고(저장 전) 누르면 그 창 사진을 원장님께 보낸다 → 동선관리 [처방 확인]에서 [승인] → 바에 '승인' 표시.
#     기록: (보드)/rxReq/{id}  { status: 대기 → 승인 | 취소 }.  사진: 병원 서버 rx_captures/{날짜}/{id}.jpg (서버가 안 되면 Firebase patient_photos/{차트번호}/rxq_{id}.jpg)
#  2026-11-25 c1.4: 원장님은 동선관리를 쓰지 않는다 → 원장님 진료실 PC 의 이 바에서 확인한다. 같은 폴더에 rx_doctor.on 이 있는 PC 는
#     7초마다 '대기' 요청을 읽어, 새 요청이 오면 그 사진을 창으로 띄운다(일하던 창의 입력을 뺏지 않는다). [확인] → status '승인'. 닫아 두었으면 바의 [처방 확인 N]으로 다시 연다.
#  이 파일은 감시 스크립트(v4.0~)가 사이트의 capture.json 을 보고 스스로 바꿔 준다(진료실 PC 재설치 없이)
#  바 사용: 바를 끌어서 옮김 · 오른쪽 클릭 = 메뉴(위치 초기화 / 진료 캡처 폴더 열기 / 잠시 끄기) · 캡처 중 Esc 또는 오른쪽 클릭 = 취소
# ─────────────────────────────────────────────────────────────
#  환자 정하기: ① 비트 외래진료실 창에 지금 열린 환자(차트번호) ② 없으면 동선관리에서 이 진료실($Room)에 '진행' 중인 카드
#             캡처 화면 위에 누구 슬립으로 가는지 이름을 크게 보여 준다.
param([string]$Pc = $env:COMPUTERNAME,
      [string]$Room = '')   # 동선관리 방 이름(예: 진료실1). 비우면 PC 이름이 '진료실…'일 때 그 이름
$ErrorActionPreference = 'Continue'
$CapVer = 'c1.4'   # c1.4: 원장님 PC 알림 창 [확인] (rx_doctor.on 이 있는 PC 만, 2026-11-25). c1.3: [원장님 확인 요청] (rx_approve.on 이 있는 PC 만, 2026-11-25). c1.1: [진료 캡처] (2026-11-17). c1.2: 진료 캡처를 이 PC 의 C:\진료캡처 에도 파일로 저장. 감시 스크립트가 capture.json 의 sha256 과 다르면 이 파일을 바꾼다
$ApiKey    ='AIzaSyDBj3z-Qj9DyT1ZgDNps1-Yp9ZBopeWr0w'
$ProjectId = 'bonafide-dongseon-108e2'
$Bucket    = 'bonafide-dongseon-108e2.firebasestorage.app'
$BotEmail  = 'uc8feac453b1a01cc028b072a@bonafide.app'   # 동선관리 계정 'bitbot'
$MaxSide   = 2400   # 잘라 낸 사진의 긴 변 최대(px) — 엑스레이 세부가 보이도록 넉넉히
$BoardDoc  = 'patientboard_v3/' + [Uri]::EscapeDataString('반듯한정형외과')   # 동선관리 보드 문서(카드: …/patients)
if (-not $Room -and $Pc -match '^진료실') { $Room = $Pc }
$RxDoc = Test-Path (Join-Path $PSScriptRoot 'rx_doctor.on')   # 원장님 PC: 처방 확인 요청이 오면 알림 창을 띄우고 [확인]을 받는다
$RxOn = Test-Path (Join-Path $PSScriptRoot 'rx_approve.on')   # 처방 확인 요청 단추를 쓰는 PC (설치 때 이 파일을 만든다)
$SiteBase = 'https://bonafide-portal.seoulgijibae.workers.dev'
$SecretFile = Join-Path $PSScriptRoot 'bitplus_watcher.secret'
$TokenFile  = Join-Path $PSScriptRoot 'slip_capture.token'
$LogDir = Join-Path $env:LOCALAPPDATA 'bitplus_watcher'; New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'slip_capture.log'
$PosFile = Join-Path $LogDir 'slip_capture.pos'
$RxFile = Join-Path $LogDir 'rx_pending.txt'   # 대기 중인 처방 확인 요청 id — 바가 다시 떠도 이어서 기다린다
function Log($m) { try { Add-Content $LogFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" -Encoding UTF8 } catch {} }
function NowIso() { return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }

# 한 번만 실행 (로그온 작업이 5분마다 다시 시작해도 이미 떠 있으면 그냥 끝난다)
$script:Mtx = New-Object System.Threading.Mutex($false, 'Local\BonafideSlipCapture')
$own = $false; try { $own = $script:Mtx.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $own = $true }   # 설치가 옛 바를 강제로 끄면 잠금이 '버려진' 상태 — 넘겨받는다
if (-not $own) { exit }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace SlipCap -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr v);
[DllImport("user32.dll")] public static extern bool ReleaseCapture();
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
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

# ── 진료 캡처 → 이 PC 에 파일로 (2026-11-17 진료실 요청: '진료실 컴퓨터에 파일로 저장되게') ──
function LocalCapRoot() {
  foreach ($d in @('C:\진료캡처', (Join-Path ([Environment]::GetFolderPath('MyDocuments')) '진료캡처'))) {
    try { New-Item -ItemType Directory -Force $d -ErrorAction Stop | Out-Null; return $d } catch {}
  }
  return $null
}
function SaveLocalShot([byte[]]$bytes, $mrn, $name) {
  $root = LocalCapRoot; if (-not $root) { throw '저장 폴더를 만들 수 없습니다' }
  $bad = [IO.Path]::GetInvalidFileNameChars()
  $who = (("$mrn" + $(if ($name) { "_$name" } else { '' })).ToCharArray() | ForEach-Object { if ($bad -contains $_) { '_' } else { $_ } }) -join ''
  $dir = Join-Path $root $who.Trim(); New-Item -ItemType Directory -Force $dir | Out-Null
  $f = Join-Path $dir ((Get-Date).ToString('yyyy-MM-dd_HHmmss') + '.jpg')
  $i = 2; while (Test-Path $f) { $f = Join-Path $dir ((Get-Date).ToString('yyyy-MM-dd_HHmmss') + "_$i.jpg"); $i++ }
  [IO.File]::WriteAllBytes($f, $bytes)
  Log "PC 저장 $f"
  return $f
}

# ── 올리기: Storage 에 사진 → bitNote 문서의 shots 배열에 덧붙임(없으면 문서 생성) ──
function UploadShot([byte[]]$bytes, $mrn, $name, $w, $h, $kind = 'inj') {
  $tok = FbToken
  $id = 'sc' + (Get-Date).ToString('yyyyMMddHHmmssfff')
  $path = "patient_photos/$(PmKey $mrn)/slip_$id.jpg"
  $u = "https://firebasestorage.googleapis.com/v0/b/$Bucket/o?uploadType=media&name=" + [Uri]::EscapeDataString($path)
  Invoke-RestMethod -TimeoutSec 60 -Method Post -Uri $u -Headers @{ Authorization = "Bearer $tok" } -ContentType 'image/jpeg' -Body $bytes | Out-Null
  $day = (Get-Date).ToString('yyyy-MM-dd')
  $doc = "projects/$ProjectId/databases/(default)/documents/bitNote/${day}_$mrn"
  $shot = @{ mapValue = @{ fields = @{ id = @{ stringValue = $id }; path = @{ stringValue = $path }; at = @{ stringValue = (NowIso) }; pc = @{ stringValue = $Pc }
                                       w = @{ integerValue = "$w" }; h = @{ integerValue = "$h" }; kind = @{ stringValue = "$kind" } } } }
  $fields = @{ date = @{ stringValue = $day }; mrn = @{ stringValue = "$mrn" }; shotAt = @{ stringValue = (NowIso) } }
  $mask = @('date', 'mrn', 'shotAt')
  if ($name) { $fields['shotName'] = @{ stringValue = "$name" }; $mask += 'shotName' }   # 이름은 감시 스크립트의 name 칸을 건드리지 않게 따로
  $write = @{ update = @{ name = $doc; fields = $fields }; updateMask = @{ fieldPaths = $mask }
              updateTransforms = @(@{ fieldPath = 'shots'; appendMissingElements = @{ values = @($shot) } }) }
  $json = (@{ writes = @($write) } | ConvertTo-Json -Depth 30 -Compress)
  Invoke-RestMethod -TimeoutSec 30 -Method Post -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents:commit" -Headers @{ Authorization = "Bearer $tok" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
  Log "올림($kind) $mrn $name ${w}x$h $path"
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
function SelectRegion($who, $where = '슬립에 올립니다') {
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
    $g.DrawString("→ $who  $where  ·  끌어서 고르기  ·  Esc = 취소", $font, [Drawing.Brushes]::White, 30, 27) })
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

# ── 처방 확인 요청 (2026-11-25, rx_approve.on 이 있는 PC 만) ──
#  비트 외래진료실 창 전체를 찍어 올리고 (보드)/rxReq/{id} 에 '대기'로 적는다. 원장님이 동선관리에서 [승인]하면 status 가 '승인'으로 바뀐다(3초마다 확인).
#  기다리는 동안 다른 환자를 열면 요청을 취소한다(바꾼 처방이 화면에서 사라지므로). 비트에는 아무것도 누르지 않는다.
function ShotWindow($hwnd) {
  $r = New-Object BitW.U32+RECT; if (-not [BitW.U32]::GetWindowRect([IntPtr]$hwnd, [ref]$r)) { throw '비트 창 위치를 읽지 못했습니다' }
  $vs = [Windows.Forms.SystemInformation]::VirtualScreen
  $rc = [Drawing.Rectangle]::Intersect((New-Object Drawing.Rectangle $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T)), $vs)
  if ($rc.Width -lt 400 -or $rc.Height -lt 300) { throw '비트 외래진료실 창이 화면에 보이지 않습니다 (최소화되어 있으면 다시 띄워 주세요)' }
  $bmp = New-Object Drawing.Bitmap $rc.Width, $rc.Height
  $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($rc.Left, $rc.Top, 0, 0, $bmp.Size); $g.Dispose()
  $sc = [Math]::Min(1.0, $MaxSide / [double][Math]::Max($bmp.Width, $bmp.Height))
  if ($sc -lt 1.0) { $nw = [int]($bmp.Width * $sc); $nh = [int]($bmp.Height * $sc); $rs = New-Object Drawing.Bitmap $nw, $nh
    $gr = [Drawing.Graphics]::FromImage($rs); $gr.InterpolationMode = 'HighQualityBicubic'; $gr.DrawImage($bmp, 0, 0, $nw, $nh); $gr.Dispose(); $bmp.Dispose(); $bmp = $rs }
  $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
  $ep = New-Object Drawing.Imaging.EncoderParameters 1; $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), ([long]88)
  $ms = New-Object IO.MemoryStream; $bmp.Save($ms, $codec, $ep)
  $out = @{ bytes = $ms.ToArray(); w = $bmp.Width; h = $bmp.Height }; $bmp.Dispose(); $ms.Dispose()
  return $out
}
function BitInFront($hwnd) {   # 지금 맨 앞 창이 비트(BITDoctorOrder)인가 — 다른 프로그램이 비트를 가리고 있으면 사진에 그 프로그램이 찍힌다
  try { $fg = [SlipCap.U]::GetForegroundWindow(); if ($fg -eq [IntPtr]::Zero) { return $true }
    $p1 = [uint32]0; [void][SlipCap.U]::GetWindowThreadProcessId($fg, [ref]$p1); return (([int]$p1 -eq [BitW.U32]::Pid([IntPtr]$hwnd)) -or ([int]$p1 -eq $PID)) } catch { return $true }
}
function RxUpload([byte[]]$bytes, $id, $mrn) {   # 병원 서버(Worker → 터널) 먼저, 안 되면 Firebase
  $tok = FbToken; $day = (Get-Date).ToString('yyyy-MM-dd'); $p = "rx_captures/$day/$id.jpg"
  try { $r = Invoke-RestMethod -TimeoutSec 25 -Method Put -Uri "$SiteBase/api/dongseon/files/$p" -Headers @{ Authorization = "Bearer $tok" } -ContentType 'image/jpeg' -Body $bytes
    if ($r.ok) { return @{ path = $p; srv = $true } } } catch { Log "병원 서버 저장 안 됨 → Firebase 로: $($_.Exception.Message)" }
  $p2 = "patient_photos/$(PmKey $mrn)/rxq_$id.jpg"
  $u = "https://firebasestorage.googleapis.com/v0/b/$Bucket/o?uploadType=media&name=" + [Uri]::EscapeDataString($p2)
  Invoke-RestMethod -TimeoutSec 60 -Method Post -Uri $u -Headers @{ Authorization = "Bearer $tok" } -ContentType 'image/jpeg' -Body $bytes | Out-Null
  return @{ path = $p2; srv = $false }
}
function RxSet($id, $h) {   # (보드)/rxReq/{id} 에 $h 의 칸만 쓴다
  $tok = FbToken; $f = @{}
  foreach ($k in @($h.Keys)) { $v = $h[$k]; if ($v -is [bool]) { $f[$k] = @{ booleanValue = $v } } elseif ($v -is [int]) { $f[$k] = @{ integerValue = "$v" } } else { $f[$k] = @{ stringValue = "$v" } } }
  $doc = "projects/$ProjectId/databases/(default)/documents/$([Uri]::UnescapeDataString($BoardDoc))/rxReq/$id"
  $json = (@{ writes = @(@{ update = @{ name = $doc; fields = $f }; updateMask = @{ fieldPaths = @($h.Keys) } }) } | ConvertTo-Json -Depth 30 -Compress)
  Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents:commit" -Headers @{ Authorization = "Bearer $tok" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
}
function RxGet($id) { $tok = FbToken
  return (Invoke-RestMethod -TimeoutSec 6 -Method Get -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$BoardDoc/rxReq/$id" -Headers @{ Authorization = "Bearer $tok" }).fields }
$script:Rx = $null   # 대기 중인 요청: @{ id; mrn; name; at; miss; pollAt; logAt }
function RxKeep() { try { if ($script:Rx) { "$($script:Rx.id)|$($script:Rx.mrn)|$($script:Rx.name)" | Set-Content $RxFile -Encoding UTF8 } else { Remove-Item $RxFile -ErrorAction SilentlyContinue } } catch {} }
function RxEnd($text, $color, $sec) { $script:Rx = $null; RxKeep; RxButton; SetStatus $text $color $sec }
function RxButton() { if (-not $btnRx) { return }
  if ($script:Rx) { $btnRx.Text = '요청 취소'; $btnRx.BackColor = [Drawing.Color]::FromArgb(100, 116, 139) } else { $btnRx.Text = '원장님 확인 요청'; $btnRx.BackColor = [Drawing.Color]::FromArgb(234, 88, 12) } }
function DoRxRequest() {
  if ($script:Rx) {   # 대기 중에 다시 누르면 취소
    if ([Windows.Forms.MessageBox]::Show("$($script:Rx.name) ($($script:Rx.mrn)) 의 원장님 확인 요청을 취소할까요?", '처방 확인 요청', 'YesNo', 'Question') -ne 'Yes') { return }
    $id = $script:Rx.id; try { RxSet $id @{ status = '취소'; endAt = (NowIso); endWhy = '간호가 취소' } } catch { Log "요청 취소 기록 실패 $id : $($_.Exception.Message)" }
    Log "처방 확인 요청 취소 $id"; RxEnd '요청을 취소했습니다' ([Drawing.Color]::FromArgb(253, 224, 71)) 4; return }
  $h = FindDoctorWindow; $d = $null; if ($h) { try { $d = ReadDoctor $h } catch {} }
  $mrn = if ($d) { [string]$d.mrn } else { '' }; $name = if ($d) { [string]$d.name } else { '' }
  if (-not $h -or -not $mrn) { SetStatus '✖ 비트 외래진료실에 환자를 먼저 열어 주세요' ([Drawing.Color]::FromArgb(252, 165, 165)) 6; return }
  $script:Capturing = $true; $bar.Hide(); [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 350
  $shot = $null; $err = ''
  try { if (-not (BitInFront $h)) { throw '비트 외래진료실 창을 맨 앞에 두고 다시 눌러 주세요' }; $shot = ShotWindow $h } catch { $err = $_.Exception.Message; Log "처방 확인 사진 오류: $err" }
  $bar.Show(); $bar.TopMost = $true; $script:Capturing = $false
  if (-not $shot) { SetStatus "✖ $err" ([Drawing.Color]::FromArgb(252, 165, 165)) 8; return }
  SetStatus "원장님께 보내는 중…  $name" ([Drawing.Color]::FromArgb(253, 224, 71)) 60; [Windows.Forms.Application]::DoEvents()
  $id = 'rq' + (Get-Date).ToString('yyyyMMddHHmmssfff')
  try {
    $up = RxUpload $shot.bytes $id $mrn
    RxSet $id @{ id = $id; date = (Get-Date).ToString('yyyy-MM-dd'); at = (NowIso); mrn = $mrn; name = $name; pc = $Pc; status = '대기'; path = $up.path; srv = [bool]$up.srv; w = [int]$shot.w; h = [int]$shot.h }
  } catch { $m = $_.Exception.Message; Log "처방 확인 요청 실패 $mrn : $m"; SetStatus '✖ 보내지 못했습니다 — 다시 눌러 주세요' ([Drawing.Color]::FromArgb(252, 165, 165)) 8
    [Windows.Forms.MessageBox]::Show("원장님께 보내지 못했습니다.`n`n$m`n`n로그: $LogFile", '처방 확인 요청') | Out-Null; return }
  Log "처방 확인 요청 $id $mrn $name $($shot.w)x$($shot.h) $($up.path)"
  $script:Rx = @{ id = $id; mrn = $mrn; name = $name; at = (Get-Date); miss = 0; pollAt = (Get-Date); logAt = (Get-Date) }; RxKeep; RxButton
  $script:HoldUntil = [DateTime]::MinValue
}
function RxTick() {   # 1.5초마다(타이머). 대기 중일 때만 일한다
  $x = $script:Rx; if (-not $x -or $script:Capturing) { return }
  # ① 화면의 환자가 바뀌었나 (두 번 연속 다르면 — 비트가 화면을 다시 그리는 순간의 빈 값은 넘어간다)
  $cur = ''; try { $h = FindDoctorWindow; if ($h) { $d = ReadDoctor $h; if ($d) { $cur = [string]$d.mrn } } } catch {}
  if ($cur -ne $x.mrn) { $x.miss++ } else { $x.miss = 0 }
  if ($x.miss -ge 2) {
    try { RxSet $x.id @{ status = '취소'; endAt = (NowIso); endWhy = $(if ($cur) { '다른 환자를 열었음' } else { '비트 환자 화면이 닫혔음' }) } } catch { Log "요청 취소 기록 실패 $($x.id): $($_.Exception.Message)" }
    Log "처방 확인 요청 자동 취소 $($x.id) (화면 환자 '$cur')"
    RxEnd "✖ $($x.name) 화면이 바뀌어 요청이 취소됐습니다" ([Drawing.Color]::FromArgb(252, 165, 165)) 12; try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}; return }
  $min = [int]((Get-Date) - $x.at).TotalMinutes
  if ((Get-Date) -ge $script:HoldUntil) { $lbl.ForeColor = [Drawing.Color]::FromArgb(253, 224, 71); $lbl.Text = "원장님 확인 대기 중$(if ($min -ge 1) { " ${min}분" })  ·  $($x.name)" }
  if (((Get-Date) - $x.logAt).TotalSeconds -ge 60) { $x.logAt = Get-Date; Log "처방 확인 대기 중 $($x.id) ${min}분" }   # 로그가 계속 쓰이면 감시 스크립트가 대기 중에 바를 바꿔 끄지 않는다
  # ② 3초마다 원장님 답 확인
  if (((Get-Date) - $x.pollAt).TotalSeconds -lt 3) { return }; $x.pollAt = Get-Date
  $st = ''; $by = ''; try { $f = RxGet $x.id; $st = [string](FsVal $f.status); $by = [string](FsVal $f.approvedBy) } catch { return }
  if ($st -eq '승인') { Log "처방 확인 승인 $($x.id) ($by)"
    RxEnd "✔ 원장님 승인  ·  $($x.name)  — 비트 [저장]을 눌러 주세요" ([Drawing.Color]::FromArgb(134, 239, 172)) 90; try { [System.Media.SystemSounds]::Asterisk.Play() } catch {} }
  elseif ($st -and $st -ne '대기') { Log "처방 확인 요청 끝 $($x.id) ($st)"; RxEnd "요청이 닫혔습니다 ($st)  ·  $($x.name)" ([Drawing.Color]::FromArgb(253, 224, 71)) 10 }
}
function RxResume() {   # 바가 다시 떴을 때: 대기 중이던 요청이 아직 '대기'면 이어서 기다린다
  try { if (-not (Test-Path $RxFile)) { return }; $p = ((Get-Content $RxFile -Encoding UTF8 -TotalCount 1) -split '\|'); if ($p.Count -lt 2 -or -not $p[0]) { return }
    $f = RxGet $p[0]; if ([string](FsVal $f.status) -ne '대기') { Remove-Item $RxFile -ErrorAction SilentlyContinue; return }
    $t = Get-Date; try { $t = [DateTime]::Parse([string](FsVal $f.at)) } catch {}
    $script:Rx = @{ id = $p[0]; mrn = $p[1]; name = $(if ($p.Count -ge 3) { $p[2] } else { '' }); at = $t; miss = 0; pollAt = (Get-Date); logAt = (Get-Date) }; RxButton; Log "처방 확인 요청 이어서 대기 $($p[0])"
  } catch { Log "대기 요청 다시 읽기 실패: $($_.Exception.Message)" }
}

# ── 원장님 쪽: 처방 확인 요청 알림 (2026-11-25 c1.4, rx_doctor.on 이 있는 PC 만) ──
#  창은 입력을 뺏지 않고 뜬다(ShowWithoutActivation) — 원장님이 비트에 글을 쓰는 중에 Enter 가 [확인]으로 들어가지 않게. 늘 위(WS_EX_TOPMOST).
if ($RxDoc) { Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition 'public class RxPopForm : System.Windows.Forms.Form { protected override bool ShowWithoutActivation { get { return true; } } protected override System.Windows.Forms.CreateParams CreateParams { get { System.Windows.Forms.CreateParams p = base.CreateParams; p.ExStyle |= 0x8; return p; } } }' }
$script:RxPend = @(); $script:RxPop = @{}; $script:RxSeen = @{}; $script:RxDocAt = [DateTime]::MinValue
function RxPending() {   # 오늘의 '대기' 요청 (먼저 온 것부터). 부르는 쪽에서 @( ) 로 감싼다
  $tok = FbToken; $day = (Get-Date).ToString('yyyy-MM-dd')
  $q = @{ structuredQuery = @{ from = @(@{ collectionId = 'rxReq' }); where = @{ fieldFilter = @{ field = @{ fieldPath = 'status' }; op = 'EQUAL'; value = @{ stringValue = '대기' } } } } } | ConvertTo-Json -Depth 10 -Compress
  $r = Invoke-RestMethod -TimeoutSec 6 -Method Post -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/${BoardDoc}:runQuery" -Headers @{ Authorization = "Bearer $tok" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($q))
  $out = @()
  foreach ($row in @($r)) { if (-not $row.document) { continue }; $f = $row.document.fields; if ([string](FsVal $f.date) -ne $day) { continue }
    $out += [pscustomobject]@{ id = [string](FsVal $f.id); mrn = [string](FsVal $f.mrn); name = [string](FsVal $f.name); pc = [string](FsVal $f.pc); at = [string](FsVal $f.at); path = [string](FsVal $f.path); srv = [bool](FsVal $f.srv) } }
  return @($out | Where-Object { $_.id } | Sort-Object at)
}
function RxPhoto($r) {   # 사진 바이트: 병원 서버(srv) 또는 Firebase
  if (-not $r.srv) { return (ShotImage $r.path) }
  if ($script:ImgCache[$r.path]) { return $script:ImgCache[$r.path] }
  $wc = New-Object Net.WebClient; $wc.Headers.Add('Authorization', "Bearer $(FbToken)")
  try { $b = $wc.DownloadData("$SiteBase/api/dongseon/files/$($r.path)") } finally { $wc.Dispose() }
  $script:ImgCache[$r.path] = $b; return $b
}
function RxApprove($r) {   # '대기'일 때만 '승인'으로 (읽은 뒤 바뀌었으면 실패 — updateTime 조건)
  $tok = FbToken; $H = @{ Authorization = "Bearer $tok" }
  $d = Invoke-RestMethod -TimeoutSec 10 -Method Get -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$BoardDoc/rxReq/$($r.id)" -Headers $H
  $st = [string](FsVal $d.fields.status); if ($st -ne '대기') { throw "이미 '$st' 상태입니다" }
  $w = @{ update = @{ name = [string]$d.name; fields = @{ status = @{ stringValue = '승인' }; approvedBy = @{ stringValue = "원장님 ($Pc)" }; approvedAt = @{ stringValue = (NowIso) } } }
          updateMask = @{ fieldPaths = @('status', 'approvedBy', 'approvedAt') }; currentDocument = @{ updateTime = [string]$d.updateTime } }
  Invoke-RestMethod -TimeoutSec 15 -Method Post -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents:commit" -Headers $H -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes((@{ writes = @($w) } | ConvertTo-Json -Depth 30 -Compress))) | Out-Null
}
function RxShowPop($r) {
  if ($script:RxPop[$r.id]) { return }
  $f = New-Object RxPopForm; $f.Tag = $r.id
  $tm = ''; try { $tm = ([DateTime]::Parse($r.at)).ToString('HH:mm') } catch {}
  $f.Text = "처방 확인 요청 — $($r.name) ($($r.mrn))"; $f.StartPosition = 'Manual'; $f.ShowInTaskbar = $true; $f.BackColor = [Drawing.Color]::FromArgb(15, 23, 42)
  $wa2 = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $fw = [int]($wa2.Width * 0.84); $fh = [int]($wa2.Height * 0.86)
  $f.Size = New-Object Drawing.Size $fw, $fh; $f.Location = New-Object Drawing.Point ([int]($wa2.Left + ($wa2.Width - $fw) / 2)), ([int]($wa2.Top + ($wa2.Height - $fh) / 2 + 20))
  $pb = New-Object Windows.Forms.PictureBox; $pb.Dock = 'Fill'; $pb.SizeMode = 'Zoom'; $pb.BackColor = [Drawing.Color]::FromArgb(15, 23, 42); $pb.Cursor = [Windows.Forms.Cursors]::Hand; $pb.Tag = $r
  $bot = New-Object Windows.Forms.Panel; $bot.Size = New-Object Drawing.Size $fw, 70; $bot.Dock = 'Bottom';   # 폭을 먼저 정한다 — 오른쪽에 붙인(Anchor) 단추가 제자리에 오도록
  $bot.BackColor = [Drawing.Color]::FromArgb(30, 41, 59)
  $info = New-Object Windows.Forms.Label; $info.Font = New-Object Drawing.Font 'Malgun Gothic', 15, ([Drawing.FontStyle]::Bold); $info.ForeColor = [Drawing.Color]::White; $info.AutoSize = $false
  $info.Location = New-Object Drawing.Point 16, 8; $info.Size = New-Object Drawing.Size ($fw - 420), 54; $info.TextAlign = 'MiddleLeft'
  $info.Text = "$($r.name)  ·  $($r.mrn)     $tm 요청 ($($r.pc))`n간호가 바꾼 처방입니다 (아직 저장 전). 사진을 두 번 누르면 크게 봅니다."
  $info.Font = New-Object Drawing.Font 'Malgun Gothic', 11
  $ok = New-Object Windows.Forms.Button; $ok.Text = '확인'; $ok.Font = New-Object Drawing.Font 'Malgun Gothic', 16, ([Drawing.FontStyle]::Bold); $ok.FlatStyle = 'Flat'; $ok.FlatAppearance.BorderSize = 0
  $ok.BackColor = [Drawing.Color]::FromArgb(22, 163, 74); $ok.ForeColor = [Drawing.Color]::White; $ok.Size = New-Object Drawing.Size 220, 50; $ok.Location = New-Object Drawing.Point ($fw - 260), 10; $ok.Anchor = 'Top, Right'; $ok.Cursor = [Windows.Forms.Cursors]::Hand; $ok.Tag = $r; $ok.TabStop = $false
  $later = New-Object Windows.Forms.Button; $later.Text = '나중에'; $later.Font = New-Object Drawing.Font 'Malgun Gothic', 11; $later.FlatStyle = 'Flat'; $later.ForeColor = [Drawing.Color]::FromArgb(203, 213, 225)
  $later.Size = New-Object Drawing.Size 110, 50; $later.Location = New-Object Drawing.Point ($fw - 380), 10; $later.Anchor = 'Top, Right'; $later.TabStop = $false
  $bot.Controls.AddRange(@($info, $later, $ok)); $f.Controls.AddRange(@($pb, $bot))
  try { $b = RxPhoto $r; $ms = New-Object IO.MemoryStream (, $b); $pb.Image = [Drawing.Image]::FromStream($ms) }
  catch { Log "처방 확인 사진 받기 실패 $($r.path): $($_.Exception.Message)"; $info.Text = "$($r.name)  ·  $($r.mrn)     $tm 요청 ($($r.pc))`n사진을 받지 못했습니다: $($_.Exception.Message)" }
  $ok.Add_Click({ $r = $this.Tag; $frm = $this.FindForm(); $this.Enabled = $false; $frm.Cursor = [Windows.Forms.Cursors]::WaitCursor
    try { RxApprove $r; Log "처방 확인 [확인] $($r.id) $($r.mrn) $($r.name)"; $frm.Close(); SetStatus "✔ 확인했습니다  ·  $($r.name)" ([Drawing.Color]::FromArgb(134, 239, 172)) 5 }
    catch { $frm.Cursor = [Windows.Forms.Cursors]::Default; $this.Enabled = $true; Log "처방 확인 [확인] 실패 $($r.id): $($_.Exception.Message)"; [Windows.Forms.MessageBox]::Show($frm, "확인하지 못했습니다.`n`n$($_.Exception.Message)", '처방 확인') | Out-Null } })
  $later.Add_Click({ $this.FindForm().Close() })
  $pb.Add_DoubleClick({ $r = $this.Tag; try { $tmp = Join-Path $env:TEMP ("rxreq_" + ($r.id -replace '[^\w-]', '_') + '.jpg'); [IO.File]::WriteAllBytes($tmp, (RxPhoto $r)); Start-Process $tmp } catch { Log "사진 보기 열기 실패: $($_.Exception.Message)" } })
  $f.Add_FormClosed({ $id = [string]$this.Tag; $script:RxPop.Remove($id); foreach ($c in $this.Controls) { if ($c -is [Windows.Forms.PictureBox] -and $c.Image) { $c.Image.Dispose() } } })
  $script:RxPop[$r.id] = $f; $f.Show()
  try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}
  Log "처방 확인 요청 알림 창 $($r.id) $($r.mrn) $($r.name)"
}
function RxDocButton() { if (-not $btnRxDoc) { return }; $n = @($script:RxPend).Count
  if ($n) { $btnRxDoc.Text = "처방 확인 $n"; $btnRxDoc.BackColor = [Drawing.Color]::FromArgb(220, 38, 38) } else { $btnRxDoc.Text = '처방 확인'; $btnRxDoc.BackColor = [Drawing.Color]::FromArgb(71, 85, 105) } }
function RxDocTick() {   # 타이머(1.5초)에서 부른다. 비트가 떠 있으면 7초마다, 아니면 60초마다 읽는다(읽기 수를 아낀다)
  if ($script:Capturing) { return }
  $gap = if (Get-Process -Name BITDoctorOrder -ErrorAction SilentlyContinue) { 7 } else { 60 }
  if (((Get-Date) - $script:RxDocAt).TotalSeconds -lt $gap) { return }; $script:RxDocAt = Get-Date
  $P = @(); try { $P = @(RxPending) } catch { Log "처방 확인 요청 읽기 오류: $($_.Exception.Message)"; return }
  $script:RxPend = $P; $ids = @{}
  foreach ($r in $P) { $ids[$r.id] = 1; if (-not $script:RxSeen[$r.id]) { $script:RxSeen[$r.id] = 1; try { RxShowPop $r } catch { Log "처방 확인 알림 창 오류 $($r.id): $($_.Exception.Message)" } } }
  foreach ($id in @($script:RxPop.Keys)) { if (-not $ids[$id]) { try { $script:RxPop[$id].Close() } catch {} } }   # 간호가 취소했거나 이미 확인된 요청의 창은 닫는다
  RxDocButton
}
function RxDocOpen() {   # 바의 [처방 확인 N] — 닫아 둔 요청을 다시 연다
  $script:RxDocAt = [DateTime]::MinValue; $P = @(); try { $P = @(RxPending) } catch { SetStatus '✖ 요청을 읽지 못했습니다' ([Drawing.Color]::FromArgb(252, 165, 165)) 5; return }
  $script:RxPend = $P; RxDocButton
  if (-not $P.Count) { SetStatus '기다리는 처방 확인 요청이 없습니다' ([Drawing.Color]::FromArgb(253, 224, 71)) 4; return }
  foreach ($r in $P) { $script:RxSeen[$r.id] = 1; try { RxShowPop $r; if ($script:RxPop[$r.id]) { $script:RxPop[$r.id].Activate() } } catch { Log "처방 확인 알림 창 오류 $($r.id): $($_.Exception.Message)" } }
}

# ── 바 ──
$script:CurMrn = ''; $script:CurName = ''; $script:HoldUntil = [DateTime]::MinValue
$bar = New-Object Windows.Forms.Form
$bar.FormBorderStyle = 'None'; $bar.TopMost = $true; $bar.ShowInTaskbar = $false; $bar.StartPosition = 'Manual'
$RxX1 = $(if ($RxOn) { 138 } else { 0 }); $RxX2 = $(if ($RxDoc) { 112 } else { 0 })   # 처방 확인 단추들이 차지하는 폭
$BarW = 628 + $RxX1 + $RxX2; $bar.Size = New-Object Drawing.Size $BarW, 38; $bar.BackColor = [Drawing.Color]::FromArgb(30, 41, 59); $bar.Opacity = 0.96
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$bar.Location = New-Object Drawing.Point ([int]($wa.Left + ($wa.Width - $BarW) / 2)), $wa.Top
try { if (Test-Path $PosFile) { $p = (Get-Content $PosFile -TotalCount 1) -split ','; $pt = New-Object Drawing.Point ([int]$p[0]), ([int]$p[1])
    if ([Windows.Forms.SystemInformation]::VirtualScreen.Contains($pt)) { $bar.Location = $pt } } } catch {}
function CapButton($text, $x, $r, $g, $b) { $o = New-Object Windows.Forms.Button
  $o.Text = $text; $o.Font = New-Object Drawing.Font 'Malgun Gothic', 10, ([Drawing.FontStyle]::Bold)
  $o.FlatStyle = 'Flat'; $o.FlatAppearance.BorderSize = 0; $o.BackColor = [Drawing.Color]::FromArgb($r, $g, $b); $o.ForeColor = [Drawing.Color]::White
  $o.Location = New-Object Drawing.Point $x, 4; $o.Size = New-Object Drawing.Size 84, 30; $o.Cursor = [Windows.Forms.Cursors]::Hand; return $o }
$btn = CapButton '주사 캡처' 4 59 130 246     # 파랑 — 슬립(주사)으로
$btnPt = CapButton 'PT 캡처' 92 13 148 136    # 청록 — 4층으로 (2026-10-13)
$btnRec = CapButton '진료 캡처' 180 124 58 237  # 보라 — 진료 기록용, 슬립·4층에 안 감 (2026-11-17)
$btnPast = CapButton '지난 캡처' 268 71 85 105  # 회색 — 이 환자의 예전 캡처 보기 (2026-10-20)
$lbl = New-Object Windows.Forms.Label
$lbl.Font = New-Object Drawing.Font 'Malgun Gothic', 10; $lbl.ForeColor = [Drawing.Color]::White; $lbl.AutoSize = $false; $lbl.TextAlign = 'MiddleLeft'
$lbl.Location = New-Object Drawing.Point (358 + $RxX1 + $RxX2), 4; $lbl.Size = New-Object Drawing.Size 266, 30; $lbl.Text = '비트 외래진료실 확인 중…'
$bar.Controls.AddRange(@($btn, $btnPt, $btnRec, $btnPast, $lbl))
$btnRxDoc = $null
if ($RxDoc) { $btnRxDoc = CapButton '처방 확인' (356 + $RxX1) 71 85 105; $btnRxDoc.Size = New-Object Drawing.Size 108, 30; $bar.Controls.Add($btnRxDoc); $btnRxDoc.Add_Click({ RxDocOpen }) }   # 원장님 PC 만 — 요청이 있으면 빨강 + 건수 (2026-11-25)
$btnRx = $null
if ($RxOn) { $btnRx = CapButton '원장님 확인 요청' 356 234 88 12; $btnRx.Size = New-Object Drawing.Size 134, 30; $bar.Controls.Add($btnRx); $btnRx.Add_Click({ DoRxRequest }) }   # 주황 — 처방 확인용 PC 만 (2026-11-25)
$drag = { param($s, $e) if ($e.Button -eq 'Left') { [void][SlipCap.U]::ReleaseCapture(); [void][SlipCap.U]::SendMessage($bar.Handle, 0xA1, 2, 0); try { "$($bar.Left),$($bar.Top)" | Set-Content $PosFile } catch {} } }   # 끌어서 옮기기
$bar.Add_MouseDown($drag); $lbl.Add_MouseDown($drag)
$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('위치 초기화 (화면 위 가운데)', $null, { $bar.Location = New-Object Drawing.Point ([int]($wa.Left + ($wa.Width - $BarW) / 2)), $wa.Top; try { Remove-Item $PosFile -ErrorAction SilentlyContinue } catch {} })
[void]$menu.Items.Add('진료 캡처 폴더 열기', $null, { $d = LocalCapRoot; if ($d) { Start-Process explorer.exe $d } })
[void]$menu.Items.Add('잠시 끄기 (5분 안에 다시 켜짐)', $null, { $bar.Close() })
$bar.ContextMenuStrip = $menu; $lbl.ContextMenuStrip = $menu

function SetStatus($text, $color, $sec) { $lbl.Text = $text; $lbl.ForeColor = $color; $script:HoldUntil = (Get-Date).AddSeconds($sec) }
# ── 자동차보험 급여 도수 가능 팝업 (2026-10-30) ──
#  접수 PC 의 DB 에이전트(db2.1)가 bitRx/_jabo 에 오늘 대상 환자(자보 첫 내원 14일 이상 + 기본물리치료 4일 이상, 조건 만족 뒤 3번 내원)를 적는다.
#  비트 외래진료실에서 그 환자를 열면 한 번 띄운다(이 PC 에서 하루 한 번 — 껐다 켜도 다시 안 뜨게 파일에 기억)
$JaboShownFile = Join-Path $LogDir 'jabo_shown.txt'
$script:Jabo = @{}; $script:JaboAt = [DateTime]::MinValue; $script:JaboShown = @{}
try { if (Test-Path $JaboShownFile) { $d0 = (Get-Date).ToString('yyyy-MM-dd'); foreach ($l in (Get-Content $JaboShownFile -Encoding UTF8)) { if ($l -like "$d0|*") { $script:JaboShown[$l] = 1 } } } } catch {}
function JaboLoad() {
  if (((Get-Date) - $script:JaboAt).TotalSeconds -lt 60) { return }
  $script:JaboAt = Get-Date
  try {
    $r = Invoke-RestMethod -TimeoutSec 5 -Method Get -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/bitRx/_jabo" -Headers @{ Authorization = "Bearer $(FbToken)" }
    $J = @{}
    if ((FsVal $r.fields.day) -eq (Get-Date).ToString('yyyy-MM-dd') -and $r.fields.pts.mapValue.fields) {
      foreach ($p in $r.fields.pts.mapValue.fields.PSObject.Properties) { $f = $p.Value.mapValue.fields
        $J[[string]$p.Name] = @{ n = [int](FsVal $f.n); first = [string](FsVal $f.first); pt = [int](FsVal $f.pt); days = [int](FsVal $f.days) } } }
    $script:Jabo = $J
  } catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { $script:Jabo = @{} } else { Log "자보 도수 목록 읽기 오류: $($_.Exception.Message)" } }
}
function JaboPopup($mrn, $name) {
  $key = (Get-Date).ToString('yyyy-MM-dd') + '|' + $mrn
  if ($script:JaboShown.ContainsKey($key)) { return }
  JaboLoad
  $e = $script:Jabo[([string]$mrn).TrimStart('0')]; if (-not $e) { return }   # 에이전트가 앞 0 을 떼고 적는다
  $script:JaboShown[$key] = 1; try { Add-Content $JaboShownFile $key -Encoding UTF8 } catch {}
  Log "자보 도수 팝업 $mrn ($($e.n)/3)"
  $f = New-Object Windows.Forms.Form
  $f.Text = '자동차보험 급여 도수'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true; $f.ShowInTaskbar = $true
  $f.StartPosition = 'CenterScreen'; $f.ClientSize = New-Object Drawing.Size 520, 230; $f.BackColor = [Drawing.Color]::White
  $t = New-Object Windows.Forms.Label; $t.Font = New-Object Drawing.Font 'Malgun Gothic', 17, ([Drawing.FontStyle]::Bold); $t.ForeColor = [Drawing.Color]::FromArgb(4, 120, 87)
  $t.Location = New-Object Drawing.Point 20, 18; $t.Size = New-Object Drawing.Size 480, 70; $t.Text = "이 환자는 급여 도수가`n가능한 환자입니다"
  $s = New-Object Windows.Forms.Label; $s.Font = New-Object Drawing.Font 'Malgun Gothic', 11; $s.ForeColor = [Drawing.Color]::FromArgb(51, 65, 85)
  $s.Location = New-Object Drawing.Point 22, 96; $s.Size = New-Object Drawing.Size 480, 80
  $s.Text = "$name  ·  $mrn`n자보 첫 내원 $($e.first) ($($e.days)일 전)  ·  기본물리치료 $($e.pt)회`n안내 $($e.n)번째 / 3번 (조건을 만족한 뒤 3번의 내원 동안 뜹니다)"
  $ok = New-Object Windows.Forms.Button; $ok.Text = '확인'; $ok.Font = New-Object Drawing.Font 'Malgun Gothic', 11, ([Drawing.FontStyle]::Bold)
  $ok.Location = New-Object Drawing.Point 400, 182; $ok.Size = New-Object Drawing.Size 100, 36; $ok.FlatStyle = 'Flat'; $ok.BackColor = [Drawing.Color]::FromArgb(16, 185, 129); $ok.ForeColor = [Drawing.Color]::White
  $ok.Add_Click({ $f.Close() }); $f.AcceptButton = $ok
  $f.Controls.AddRange(@($t, $s, $ok))
  $f.Add_FormClosed({ $f.Dispose() })
  $f.Show(); $f.Activate()   # 모달이 아니라 바·비트 작업을 막지 않는다
}
function ReadPatient() {
  if ((Get-Date) -lt $script:HoldUntil) { return }
  $mrn = ''; $name = ''
  try { $h = FindDoctorWindow; if ($h) { $d = ReadDoctor $h; if ($d) { $mrn = [string]$d.mrn; $name = [string]$d.name } } } catch { Log "창 읽기 오류: $($_.Exception.Message)" }
  if ($mrn -and $mrn -ne $script:CurMrn) { try { JaboPopup $mrn $name } catch { Log "자보 도수 팝업 오류: $($_.Exception.Message)" } }
  $script:CurMrn = $mrn; $script:CurName = $name
  if ($btnRx) { $btnRx.Enabled = [bool]$mrn -or [bool]$script:Rx }
  $btn.Enabled = [bool]$mrn -or [bool]$Room; $btnPt.Enabled = $btn.Enabled; $btnRec.Enabled = $btn.Enabled; $btnPast.Enabled = $btn.Enabled
  if ($script:Rx) { return }   # 대기 중 글은 RxTick 이 쓴다
  if ($mrn) { $lbl.ForeColor = [Drawing.Color]::White; $lbl.Text = "$name  ·  $mrn" }
  elseif ($Room) { $lbl.ForeColor = [Drawing.Color]::FromArgb(148, 163, 184); $lbl.Text = "비트 환자 없음 → $Room 진행 환자로" }
  else { $lbl.ForeColor = [Drawing.Color]::FromArgb(148, 163, 184); $lbl.Text = '비트 외래진료실에 환자 없음' }
}
function DoCapture($kind) {
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
  $script:Capturing = $true; $bar.Hide(); [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 250
  $shot = $null
  $where = if ($kind -eq 'pt') { 'PT(4층)으로 보냅니다' } elseif ($kind -eq 'rec') { '진료 기록으로 남깁니다' } else { '주사 슬립에 올립니다' }
  try { $shot = SelectRegion "$name ($mrn)" $where } catch { Log "캡처 오류: $($_.Exception.Message)" }
  $bar.Show(); $bar.TopMost = $true; $script:Capturing = $false
  if (-not $shot) { return }
  SetStatus "올리는 중…  $name" ([Drawing.Color]::FromArgb(253, 224, 71)) 60; [Windows.Forms.Application]::DoEvents()
  $done = if ($kind -eq 'pt') { '4층으로 보냄' } elseif ($kind -eq 'rec') { '진료 기록 저장' } else { '슬립에 올림' }
  if ($kind -eq 'rec') {   # 올리기 전에 PC 에 먼저 — 인터넷이 안 돼도 파일은 남는다
    try { [void](SaveLocalShot $shot.bytes $mrn $name); $done = '진료 기록 저장 (PC 에도)' } catch { Log "PC 저장 실패 $mrn : $($_.Exception.Message)"; $done = '진료 기록 저장 (PC 저장 실패)' }
  }
  try { UploadShot $shot.bytes $mrn $name $shot.w $shot.h $kind; Log "환자 출처: $src"; SetStatus "✔ $done  ·  $name" ([Drawing.Color]::FromArgb(134, 239, 172)) 4 }
  catch { $m = $_.Exception.Message; Log "올리기 실패 $mrn : $m"; SetStatus "✖ 올리기 실패 — 다시 눌러 주세요" ([Drawing.Color]::FromArgb(252, 165, 165)) 8
    [Windows.Forms.MessageBox]::Show("슬립에 올리지 못했습니다.`n`n$m`n`n로그: $LogFile", '슬립 캡처') | Out-Null }
}
# ── 지난 캡처 보기 (2026-10-20 요청: 원장님이 동선관리를 안 쓰셔서 진료실에서 바로) ──
#  지금 환자(비트 창 → 없으면 이 진료실 진행 카드)의 캡처를 모두: 영구 목록 slipShots/{차트번호} + 아직 모이지 않은 최근 bitNote 의 shots.
#  지운 캡처(hidden)는 뺀다. 왼쪽 목록에서 고르면 오른쪽에 크게, 사진을 두 번 누르면 Windows 사진 보기로(확대용)
function FsArr($v) { if ($v -and $v.arrayValue -and $v.arrayValue.values) { return @($v.arrayValue.values) }; return @() }
function ShotOf($v, $date) { $f = $v.mapValue.fields; if (-not $f) { return $null }
  $p = [string](FsVal $f.path); if (-not $p) { return $null }
  $id = [string](FsVal $f.id); if (-not $id) { $id = $p }
  $k = [string](FsVal $f.kind); if (-not $k) { $k = 'inj' }
  $d = [string](FsVal $f.date); if (-not $d) { $d = $date }
  return [pscustomobject]@{ id = $id; path = $p; at = [string](FsVal $f.at); kind = $k; date = $d } }
# 2026-10-23: 부르는 쪽에서 @( ) 로 감싼다 — 1장이면 PowerShell 5.1 이 배열을 낱개로 풀어 .Count 가 비어 '올린 캡처가 없습니다'로 나왔다(33371)
function PastShots($mrn) {
  $tok = FbToken; $H = @{ Authorization = "Bearer $tok" }; $all = @{}; $hidden = @{}; $script:PastErr = ''
  try { $d = Invoke-RestMethod -TimeoutSec 20 -Method Get -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents/$BoardDoc/slipShots/$([Uri]::EscapeDataString($mrn))" -Headers $H
    foreach ($v in (FsArr $d.fields.shots)) { $s = ShotOf $v ''; if ($s) { if ($all[$s.id] -and $all[$s.id].kind -eq 'pt') { $s.kind = 'pt' }; $all[$s.id] = $s } }
    foreach ($v in (FsArr $d.fields.hidden)) { $hidden[[string]$v.stringValue] = 1 } }
  catch { if ("$($_.Exception.Message)" -notmatch '404') { Log "지난 캡처 목록 읽기 실패: $($_.Exception.Message)"; $script:PastErr = $_.Exception.Message } }
  try { $q = @{ structuredQuery = @{ from = @(@{ collectionId = 'bitNote' }); where = @{ fieldFilter = @{ field = @{ fieldPath = 'mrn' }; op = 'EQUAL'; value = @{ stringValue = "$mrn" } } } } } | ConvertTo-Json -Depth 10 -Compress
    $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents:runQuery" -Headers $H -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($q))
    foreach ($row in @($r)) { if (-not $row.document) { continue }; $f = $row.document.fields
      foreach ($v in (FsArr $f.shots)) { $s = ShotOf $v ([string](FsVal $f.date)); if ($s -and -not $all[$s.id]) { $all[$s.id] = $s } }
      foreach ($v in (FsArr $f.capHidden)) { $hidden[[string]$v.stringValue] = 1 } } }   # 이 바에서 지운 것 (2026-10-29)
  catch { Log "최근 캡처 읽기 실패: $($_.Exception.Message)"; if (-not $script:PastErr) { $script:PastErr = $_.Exception.Message } }
  return @($all.Values | Where-Object { -not $hidden[$_.id] } | Sort-Object at -Descending)
}
# ── 캡처 지우기 (2026-10-29 요청: 진료실에서 잘못 캡처한 것을 바로) — 사진 파일은 남기고 목록에서만 숨긴다(동선관리 슬립 ✕ 와 같은 결과)
#  ① 오늘 캡처: 그 날 bitNote 문서의 capHidden 에 넣는다 → 슬립·환자 정보 창에서 바로 사라짐(동선관리가 환자별 목록에도 옮겨 적음)
#  ② 환자별 영구 목록 slipShots/{차트번호}.hidden 에도 넣는다 → 다음 내원 때 '지난 캡처'에도 안 뜸
function HideShot($mrn, $s) {
  $tok = FbToken; $H = @{ Authorization = "Bearer $tok" }
  $base = "projects/$ProjectId/databases/(default)/documents"; $board = [Uri]::UnescapeDataString($BoardDoc)
  $cu = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents:commit"
  $idv = @{ stringValue = [string]$s.id }; $okAny = $false; $err = ''
  $day = (Get-Date).ToString('yyyy-MM-dd'); $sday = ''; try { $sday = ([DateTime]::Parse($s.at)).ToString('yyyy-MM-dd') } catch { $sday = [string]$s.date }
  if ($sday -eq $day) {
    $w = @{ update = @{ name = "$base/bitNote/${day}_$mrn"; fields = @{} }; updateMask = @{ fieldPaths = @() }; currentDocument = @{ exists = $true }
            updateTransforms = @(@{ fieldPath = 'capHidden'; appendMissingElements = @{ values = @($idv) } }) }
    try { Invoke-RestMethod -TimeoutSec 30 -Method Post -Uri $cu -Headers $H -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes((@{ writes = @($w) } | ConvertTo-Json -Depth 30 -Compress))) | Out-Null; $okAny = $true }
    catch { $err = $_.Exception.Message; Log "오늘 캡처 지우기 실패 $mrn $($s.id): $err" } }
  $w2 = @{ update = @{ name = "$base/$board/slipShots/$mrn"; fields = @{ mrn = @{ stringValue = "$mrn" } } }; updateMask = @{ fieldPaths = @('mrn') }
           updateTransforms = @(@{ fieldPath = 'hidden'; appendMissingElements = @{ values = @($idv) } }) }
  try { Invoke-RestMethod -TimeoutSec 30 -Method Post -Uri $cu -Headers $H -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes((@{ writes = @($w2) } | ConvertTo-Json -Depth 30 -Compress))) | Out-Null; $okAny = $true }
  catch { $e2 = $_.Exception.Message; Log "캡처 목록 지우기 실패 $mrn $($s.id): $e2"; if (-not $err) { $err = $e2 } }
  if (-not $okAny) { throw $err }
  Log "캡처 지움 $mrn $($s.id) ($sday)"
}
$script:ImgCache = @{}
function ShotImage($path) {
  if ($script:ImgCache[$path]) { return $script:ImgCache[$path] }
  $tok = FbToken
  $u = "https://firebasestorage.googleapis.com/v0/b/$Bucket/o/$([Uri]::EscapeDataString($path))?alt=media"
  $wc = New-Object Net.WebClient; $wc.Headers.Add('Authorization', "Bearer $tok")
  try { $bytes = $wc.DownloadData($u) } finally { $wc.Dispose() }
  $script:ImgCache[$path] = $bytes; return $bytes
}
function ShowPast() {
  $mrn = $script:CurMrn; $name = $script:CurName
  if (-not $mrn) {
    if (-not $Room) { SetStatus "✖ 비트 외래진료실에 환자를 먼저 불러 주세요" ([Drawing.Color]::FromArgb(252, 165, 165)) 6; return }
    SetStatus "동선관리에서 $Room 진행 환자 찾는 중…" ([Drawing.Color]::FromArgb(253, 224, 71)) 30; [Windows.Forms.Application]::DoEvents()
    $bp = $null; try { $bp = BoardPatient } catch { Log "동선관리 읽기 실패: $($_.Exception.Message)" }
    $script:HoldUntil = [DateTime]::MinValue
    if (-not $bp -or -not $bp.mrn) { SetStatus "✖ 비트 외래진료실에 환자를 먼저 불러 주세요" ([Drawing.Color]::FromArgb(252, 165, 165)) 6; return }
    $mrn = $bp.mrn; $name = $bp.name }
  SetStatus "지난 캡처 불러오는 중…  $name" ([Drawing.Color]::FromArgb(253, 224, 71)) 30; [Windows.Forms.Application]::DoEvents()
  $L = @(); try { $L = @(PastShots $mrn) } catch { $script:HoldUntil = [DateTime]::MinValue; [Windows.Forms.MessageBox]::Show("캡처 목록을 읽지 못했습니다.`n`n$($_.Exception.Message)", '지난 캡처') | Out-Null; return }
  $script:HoldUntil = [DateTime]::MinValue
  if (-not $L.Count -and $script:PastErr) { [Windows.Forms.MessageBox]::Show("캡처 목록을 읽지 못했습니다.`n`n$($script:PastErr)`n`n로그: $LogFile", '지난 캡처') | Out-Null; return }
  if (-not $L.Count) { SetStatus "$name — 올린 캡처가 없습니다" ([Drawing.Color]::FromArgb(253, 224, 71)) 5; return }
  $f = New-Object Windows.Forms.Form
  $f.Text = "지난 캡처 — $name ($mrn) · $($L.Count)장"; $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.KeyPreview = $true
  $wa2 = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $f.Size = New-Object Drawing.Size ([int]($wa2.Width * 0.8)), ([int]($wa2.Height * 0.85))
  $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $s.Close() } })
  $lb = New-Object Windows.Forms.ListBox; $lb.Dock = 'Left'; $lb.Width = 250; $lb.Font = New-Object Drawing.Font 'Malgun Gothic', 11; $lb.IntegralHeight = $false
  $pb = New-Object Windows.Forms.PictureBox; $pb.Dock = 'Fill'; $pb.SizeMode = 'Zoom'; $pb.BackColor = [Drawing.Color]::FromArgb(17, 24, 39); $pb.Cursor = [Windows.Forms.Cursors]::Hand
  $tip = New-Object Windows.Forms.Label; $tip.Dock = 'Bottom'; $tip.Height = 26; $tip.TextAlign = 'MiddleCenter'; $tip.Font = New-Object Drawing.Font 'Malgun Gothic', 9.5
  $tip.Text = '사진을 두 번 누르면 크게(사진 보기)  ·  잘못 찍은 것은 왼쪽 아래 [지우기]  ·  Esc = 닫기'
  $del = New-Object Windows.Forms.Button; $del.Dock = 'Bottom'; $del.Height = 40; $del.Text = '✕  선택한 캡처 지우기'; $del.Font = New-Object Drawing.Font 'Malgun Gothic', 11, ([Drawing.FontStyle]::Bold)
  $del.FlatStyle = 'Flat'; $del.BackColor = [Drawing.Color]::FromArgb(220, 38, 38); $del.ForeColor = [Drawing.Color]::White; $del.Cursor = [Windows.Forms.Cursors]::Hand
  $lp = New-Object Windows.Forms.Panel; $lp.Dock = 'Left'; $lp.Width = 250; $lb.Dock = 'Fill'; $lp.Controls.AddRange(@($lb, $del))
  $script:PastMrn = $mrn
  foreach ($s in $L) { $t = $s.at; try { $t = ([DateTime]::Parse($s.at)).ToString('yyyy-MM-dd  HH:mm') } catch { if (-not $t) { $t = $s.date } }
    $kindTxt = if ($s.kind -eq 'pt') { 'PT' } elseif ($s.kind -eq 'rec') { '진료' } else { '주사' }
    [void]$lb.Items.Add("$t   [$kindTxt]") }
  $script:PastL = $L; $script:PastPb = $pb; $script:PastLb = $lb   # 이벤트 안에서는 함수의 지역 변수가 안 보일 수 있어 script: 로
  $lb.Add_SelectedIndexChanged({ $i = $this.SelectedIndex; if ($i -lt 0) { return }; $s = $script:PastL[$i]
    $this.FindForm().Cursor = [Windows.Forms.Cursors]::WaitCursor
    try { $b = ShotImage $s.path; $ms = New-Object IO.MemoryStream (, $b); $old = $script:PastPb.Image; $script:PastPb.Image = [Drawing.Image]::FromStream($ms); if ($old) { $old.Dispose() } }
    catch { Log "캡처 사진 받기 실패 $($s.path): $($_.Exception.Message)"; [Windows.Forms.MessageBox]::Show("사진을 받지 못했습니다.`n`n$($_.Exception.Message)", '지난 캡처') | Out-Null }
    finally { $this.FindForm().Cursor = [Windows.Forms.Cursors]::Default } })
  $pb.Add_DoubleClick({ $i = $script:PastLb.SelectedIndex; if ($i -lt 0) { return }; $s = $script:PastL[$i]
    try { $tmp = Join-Path $env:TEMP ("slipcap_" + ($s.id -replace '[^\w-]', '_') + '.jpg'); [IO.File]::WriteAllBytes($tmp, (ShotImage $s.path)); Start-Process $tmp } catch { Log "사진 보기 열기 실패: $($_.Exception.Message)" } })
  $del.Add_Click({ $i = $script:PastLb.SelectedIndex; if ($i -lt 0) { return }; $s = $script:PastL[$i]; $frm = $this.FindForm()
    $q = "이 캡처를 지울까요?`n`n$($script:PastLb.Items[$i])`n`n슬립·환자 정보 창·지난 캡처에서 모두 사라집니다."
    if ([Windows.Forms.MessageBox]::Show($frm, $q, '캡처 지우기', 'YesNo', 'Warning') -ne 'Yes') { return }
    $frm.Cursor = [Windows.Forms.Cursors]::WaitCursor
    try { HideShot $script:PastMrn $s }
    catch { $frm.Cursor = [Windows.Forms.Cursors]::Default; [Windows.Forms.MessageBox]::Show($frm, "지우지 못했습니다.`n`n$($_.Exception.Message)`n`n동선관리 슬립 화면의 [✕ 지우기]로 지워 주세요.", '캡처 지우기') | Out-Null; return }
    $frm.Cursor = [Windows.Forms.Cursors]::Default
    $script:PastL = @($script:PastL | Where-Object { $_.id -ne $s.id }); $script:PastLb.Items.RemoveAt($i)
    if (-not $script:PastL.Count) { $frm.Close(); SetStatus "✔ 캡처를 지웠습니다 (남은 캡처 없음)" ([Drawing.Color]::FromArgb(134, 239, 172)) 4; return }
    $frm.Text = ($frm.Text -replace '· \d+장$', "· $($script:PastL.Count)장")
    $script:PastLb.SelectedIndex = [Math]::Min($i, $script:PastL.Count - 1) })
  $f.Controls.AddRange(@($pb, $tip, $lp))
  $f.Add_Shown({ $script:PastLb.SelectedIndex = 0 })
  $f.Add_FormClosed({ if ($script:PastPb.Image) { $script:PastPb.Image.Dispose() } })
  SetStatus "$name — 지난 캡처 $($L.Count)장" ([Drawing.Color]::FromArgb(134, 239, 172)) 3
  [void]$f.ShowDialog()
}
$btn.Add_Click({ DoCapture 'inj' })
$btnPt.Add_Click({ DoCapture 'pt' })
$btnRec.Add_Click({ DoCapture 'rec' })
$btnPast.Add_Click({ ShowPast })
# 바가 안 보이게 된 경우 되살리기 (2026-10-25: 진료실 캡처 바가 갑자기 사라짐) — 모니터를 끄거나 해상도·배치가 바뀌어 바가 화면 밖에 남았거나,
#  캡처 중 오류로 숨겨진 채 남았을 때. 1.5초마다: 어느 화면에도 걸치지 않으면 화면 위 가운데로, 숨겨져 있으면 다시 보이게
$script:Capturing = $false
function EnsureBarVisible() {
  if ($script:Capturing) { return }
  try {
    $on = $false; foreach ($sc in [Windows.Forms.Screen]::AllScreens) { if ($sc.WorkingArea.IntersectsWith($bar.Bounds)) { $on = $true; break } }
    if (-not $on) { $wa0 = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $bar.Location = New-Object Drawing.Point ([int]($wa0.Left + ($wa0.Width - $BarW) / 2)), $wa0.Top
      try { Remove-Item $PosFile -ErrorAction SilentlyContinue } catch {}; Log "바가 화면 밖에 있어 위 가운데로 옮김" }
    if (-not $bar.Visible) { $bar.Show(); Log "숨겨진 바를 다시 보이게 함" }
    if ($bar.WindowState -ne 'Normal') { $bar.WindowState = 'Normal' }
    $bar.TopMost = $true
  } catch { Log "바 표시 확인 오류: $($_.Exception.Message)" }
}
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1500; $timer.Add_Tick({ EnsureBarVisible; ReadPatient; if ($RxOn) { try { RxTick } catch { Log "처방 확인 대기 오류: $($_.Exception.Message)" } }; if ($RxDoc) { try { RxDocTick } catch { Log "처방 확인 알림 오류: $($_.Exception.Message)" } } }); $timer.Start()
$bar.Add_Shown({ if ($RxOn) { RxResume }; ReadPatient })
Log "시작 $CapVer ($Pc)"
[Windows.Forms.Application]::Run($bar)
Log "종료"
