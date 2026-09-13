# ─────────────────────────────────────────────────────────────
#  비트플러스 접수 감시 스크립트 v3 (반듯한정형외과 동선관리 연동)
#
#  세 채널을 합친다 (①②는 접수 PC, ③은 진료실 PC — 같은 스크립트가 열린 창을 보고 스스로 판단한다):
#   ① BITCast (TCP 9000) — 비트 환경설정 › 기타사항 › 전광판IP 세팅에 이 PC IP를 등록하면
#      모든 접수 PC의 비트가 접수/취소/호출 이벤트를 이 PC로 보낸다.
#      메시지: "Command|이름|진료실|분(0시 기준)|메모|담당의|이전방|접수번호|"
#      Command: 2=접수  3=접수취소  1/0=응급·예약접수  -1=환자호출  7=수납대기  8=수납완료  13=보류 … ($CMD_NAMES, cLBITCastInfo.Enum_Command)
#      ※ 접수 수정·보류는 '접수취소 → 접수' 쌍으로 온다 → 동선관리가 6초 유예 후 여전히 취소일 때만 카드를 지운다.
#      ※ 차트번호는 메시지에 없다 → ②의 인적정보 캐시로 채운다.
#   ② 접수 창 인적정보 패널(UIAutomation, 2초) — 조회된 환자의 차트번호·주민번호7·보험·메모 등을 캐시.
#      비트에는 아무것도 입력·클릭하지 않는다. 주민번호 뒷자리·전화·주소는 읽지 않는다.
#   ③ 외래진료실 창(BITDoctorOrder, Win32, 2초) — 진료실 PC에서 의사가 '증상' 칸 맨 아래에 적는 약·주사 목록과 '특이사항' 칸을 읽는다.
#      맨 아래에서 위로 올라가며 처음 만나는 'med' 로 시작하는 줄($RX_HEAD)부터 끝까지를 원문 그대로 보낸다. 해석(아래에 neuropathic pain 이 있어야 처방,
#      med 줄의 g/gp/@/(prone) 표시)은 동선관리가 한다 → 원내 표기 규칙이 바뀌어도 PC 재설치 없이 웹만 고치면 된다. 전체 진료 기록은 보내지 않는다. 특이사항은 동선관리가 환자 명단의 특이사항(영구)에 덧붙인다 — 진료 뒤에 적혀도 다음 내원 때 보임.
#      2번 연속 같은 값일 때만 전송, 바뀌면 다시 전송.
#
#  Firestore:  bitIntake/{날짜}_ocm{접수번호}  ← 접수 이벤트(등록/취소).  같은 문서에 여러 PC가 merge 로 쓴다.
#              bitNote/{날짜}_{차트번호}       ← 진료실 처방 목록(슬립용). 동선관리 '슬립 화면'이 차트번호로 카드와 연결한다.
#              bitLookup/{날짜}_{차트번호}     ← 접수 창에서 조회된 인적정보(어느 PC든). 동선관리가 차트번호 없는 캐스트 카드를 이름으로 뒤늦게 채운다.
#              bitStatus/{PC}                 ← 하트비트 (bitOpen=접수 창, doctorOpen=외래진료실 창)
#  동선관리는 registered=true 문서를 확인 없이 3층 대기실 카드로 만든다.
#
#  설치: 1) C:\bitplus\bitplus_watcher.ps1 로 복사  2) 같은 폴더 bitplus_watcher.secret 첫 줄에 bitbot 비밀번호
#        3) powershell -ExecutionPolicy Bypass -File C:\bitplus\bitplus_watcher.ps1 -Pc 접수1
#        4) 비트 환경설정 › 기타사항 › 전광판IP 세팅에 이 PC IP 등록 (구분: 접수BitCast)
# ─────────────────────────────────────────────────────────────
param(
  [string]$Pc = $env:COMPUTERNAME,   # 동선관리에 표시될 이 PC 이름 (예: 접수1)
  [int]$CastPort = 9000,             # BITCast PORT_NUM (BITCast.dll 고정값)
  [int]$PollSec = 2,                 # 인적정보 화면 읽기 주기(초)
  [int]$HeartbeatSec = 60            # 하트비트 주기(초) — 30→60: PC 5대 기준 하루 쓰기 14,400→7,200회 (Firestore 무료 한도 20,000/일 보호)
)
$ErrorActionPreference = 'Continue'
# ── 동선관리 Firebase (공개 웹 키 — 비밀 아님. 비밀번호는 .secret 파일) ──
$ApiKey    = 'AIzaSyDBj3z-Qj9DyT1ZgDNps1-Yp9ZBopeWr0w'
$ProjectId = 'bonafide-dongseon-108e2'
$BotEmail  = 'uc8feac453b1a01cc028b072a@bonafide.app'   # 동선관리 계정 'bitbot'의 내부 이메일
$SecretFile = Join-Path $PSScriptRoot 'bitplus_watcher.secret'
if (-not (Test-Path $SecretFile)) { Write-Host "비밀번호 파일이 없습니다: $SecretFile  (첫 줄에 bitbot 비밀번호)"; exit 1 }
$BotPassword = (Get-Content $SecretFile -Encoding UTF8 -TotalCount 1).Trim()
$LogDir = Join-Path $env:LOCALAPPDATA 'bitplus_watcher'; New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'watcher.log'
$script:StartedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz'); $script:LastErr = ''; $script:LastErrAt = ''; $script:CycMax = 0   # 하트비트에 실어 보내는 자가 진단 (원격에서 로그 없이 상태 파악)
function Log($m) { $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"; Write-Host $line; try { Add-Content $LogFile $line -Encoding UTF8 } catch {}
  if ($m -match '오류|실패|못 찾음') { $script:LastErr = $m; $script:LastErrAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') } }
function LogTail($n = 5) { try { return ((Get-Content $LogFile -Tail $n -Encoding UTF8 -ErrorAction Stop) -join "`n") } catch { return '' } }
function TrimLog() { try { if ((Get-Item $LogFile -ErrorAction SilentlyContinue).Length -gt 2MB) { Get-Content $LogFile -Tail 2000 | Set-Content $LogFile -Encoding UTF8 } } catch {} }

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
# Win32 창 열거/텍스트 읽기 (원외처방 창용). 비트는 원외처방 창을 닫아도 화면 밖(-32000,-32000)에 세워 두는데, 그 상태에서는 UIAutomation 이
# 자식 요소를 주지 않으므로 EnumChildWindows + WM_GETTEXT 로 읽는다 (읽기 전용 — 아무것도 보내거나 바꾸지 않음)
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
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Cp949 = [System.Text.Encoding]::GetEncoding(949)

# ── Firebase 로그인 / Firestore REST ──
$script:Tok = $null; $script:TokExp = [DateTime]::MinValue; $script:Refresh = $null
# 세션 유지: 로그인에 성공하면 refresh 토큰을 옆 파일에 저장해 두고, 재시작 때는 비밀번호 로그인 대신 토큰 갱신으로 이어간다.
# (비밀번호 로그인은 실패가 잦으면 병원 IP 전체가 차단되지만, 토큰 갱신은 그 차단과 무관) → 재시작·재설치가 차단 상태에서도 바로 살아난다
$TokenFile = Join-Path $PSScriptRoot 'bitplus_watcher.token'
function SaveRefresh($rt) { try { if ($rt) { [IO.File]::WriteAllText($TokenFile, $rt, (New-Object Text.UTF8Encoding $false)); icacls $TokenFile /inheritance:r /grant:r "$($env:USERNAME):M" | Out-Null } } catch {} }
if (Test-Path $TokenFile) { try { $script:Refresh = (Get-Content $TokenFile -TotalCount 1 -ErrorAction Stop).Trim() } catch { $script:Refresh = $null } }
$script:LoginFailAt = [DateTime]::MinValue; $script:LoginBackoff = 60
function FbLogin() {
  # 실패 뒤에는 바로 재시도하지 않는다 — Firebase 는 실패가 잦으면 그 공인 IP(병원 전체)의 로그인을 잠시 차단하고, 차단 중 시도는 차단을 연장한다.
  # 차단(TOO_MANY_ATTEMPTS) → 10분, 비밀번호 오류 → 5분(사람이 고쳐야 함), 그 외(네트워크 등) → 60초
  if (((Get-Date) - $script:LoginFailAt).TotalSeconds -lt $script:LoginBackoff) { throw "Firebase 로그인 대기 중(최근 실패, $([int]($script:LoginBackoff - ((Get-Date) - $script:LoginFailAt).TotalSeconds))초 후 재시도)" }
  $body = @{ email = $BotEmail; password = $BotPassword; returnSecureToken = $true } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$ApiKey" -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  } catch {
    $script:LoginFailAt = Get-Date
    $code = ''; try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $code = ((($sr.ReadToEnd() | ConvertFrom-Json).error.message) -split ' ')[0] } catch {}
    $script:LoginBackoff = 60
    $hint = switch -Wildcard ($code) {
      'INVALID_LOGIN_CREDENTIALS' { $script:LoginBackoff = 300; "bitbot 비밀번호가 틀림 → 설치 스크립트를 -ResetPw 로 다시 실행해 비밀번호 재입력 (5분마다 재시도)" }
      'INVALID_PASSWORD'          { $script:LoginBackoff = 300; "bitbot 비밀번호가 틀림 → 설치 스크립트를 -ResetPw 로 다시 실행해 비밀번호 재입력 (5분마다 재시도)" }
      'TOO_MANY_ATTEMPTS*'        { $script:LoginBackoff = 600; "실패가 잦아 Firebase 가 이 병원 IP를 잠시 차단함(비밀번호 문제 아닐 수 있음) → 10분 뒤 자동 재시도, 아무것도 안 해도 됨" }
      'EMAIL_NOT_FOUND'           { $script:LoginBackoff = 600; "bitbot 계정이 없음 → 동선관리 계정 관리에서 bitbot 생성" }
      default                     { "" }
    }
    throw "Firebase 로그인 실패 [$code] $hint"
  }
  $script:Tok = $r.idToken; $script:Refresh = $r.refreshToken; $script:TokExp = (Get-Date).AddSeconds([int]$r.expiresIn - 300)
  SaveRefresh $script:Refresh
  Log "Firebase 로그인 성공"
}
function FbToken() {
  if ($script:Tok -and (Get-Date) -lt $script:TokExp) { return $script:Tok }
  if ($script:Refresh) {
    try {
      $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://securetoken.googleapis.com/v1/token?key=$ApiKey" -ContentType 'application/x-www-form-urlencoded' -Body "grant_type=refresh_token&refresh_token=$($script:Refresh)"
      $script:Tok = $r.id_token; $script:Refresh = $r.refresh_token; $script:TokExp = (Get-Date).AddSeconds([int]$r.expires_in - 300)
      SaveRefresh $script:Refresh
      return $script:Tok
    } catch { Log "토큰 갱신 실패 → 비밀번호로 재로그인: $($_.Exception.Message)"; $script:Refresh = $null; try { Remove-Item $TokenFile -Force -ErrorAction SilentlyContinue } catch {} }
  }
  FbLogin; return $script:Tok
}
$DocBase = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents"
function FsFields($h) {   # 해시테이블 → Firestore 필드 표현 (문자열/불리언/정수)
  $f = @{}
  foreach ($k in $h.Keys) { $v = $h[$k]
    if ($v -is [bool]) { $f[$k] = @{ booleanValue = $v } }
    elseif ($v -is [int] -or $v -is [long]) { $f[$k] = @{ integerValue = [string]$v } }
    else { $f[$k] = @{ stringValue = [string]$v } } }
  return $f
}
function FsExists($path) {
  try { $null = Invoke-RestMethod -TimeoutSec 20 -Method Get -Uri "$DocBase/$path" -Headers @{ Authorization = "Bearer $(FbToken)" }; return $true }
  catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $false }; throw }
}
function FsPatch($path, $fields) {   # 지정한 필드만 갱신(merge). 없는 문서는 생성
  $mask = ($fields.Keys | ForEach-Object { 'updateMask.fieldPaths=' + [Uri]::EscapeDataString($_) }) -join '&'
  $body = @{ fields = (FsFields $fields) } | ConvertTo-Json -Depth 6 -Compress
  $null = Invoke-RestMethod -TimeoutSec 20 -Method Patch -Uri "$DocBase/$path`?$mask" -Headers @{ Authorization = "Bearer $(FbToken)" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
}
function NowIso() { return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }
function Today { return (Get-Date).ToString('yyyy-MM-dd') }
function FsFindDocByMrn($mrn) {   # 오늘 접수 문서 중 차트번호가 같은 것의 id (다른 PC에서 접수돼 이 PC가 문서 id 를 모를 때)
  $q = @{ structuredQuery = @{ from = @(@{ collectionId = 'bitIntake' }); limit = 5
          where = @{ compositeFilter = @{ op = 'AND'; filters = @(
            @{ fieldFilter = @{ field = @{ fieldPath = 'date' }; op = 'EQUAL'; value = @{ stringValue = (Today) } } },
            @{ fieldFilter = @{ field = @{ fieldPath = 'mrn' }; op = 'EQUAL'; value = @{ stringValue = [string]$mrn } } }) } } } } | ConvertTo-Json -Depth 12 -Compress
  $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "$DocBase`:runQuery" -Headers @{ Authorization = "Bearer $(FbToken)" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($q))
  $ids = @($r | Where-Object { $_.document } | ForEach-Object { ($_.document.name -split '/')[-1] })
  if ($ids.Count) { return ($ids | Sort-Object | Select-Object -Last 1) }   # 같은 환자가 오늘 두 번 접수됐으면 접수번호가 큰 쪽
  return $null
}

# ── ① 비트플러스 접수 창 인적정보 읽기 (UIAutomation) ──
function FindBitWindow() {   # '접수' 제목의 최상위 창 핸들 (원외처방 등 다른 창이 앞에 와도 접수 창을 고른다)
  $proc = Get-Process -Name BITRegistrations -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $proc) { return $null }
  $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ProcessIdProperty), $proc.Id
  $wins = [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
  foreach ($w in $wins) { if ((([string]$w.Current.Name) -replace '\s', '') -eq '접수') { return @{ proc = $proc; el = $w } } }
  if ($proc.MainWindowHandle -ne 0) { return @{ proc = $proc; el = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle) } }
  return $null
}
function FindRxWindow($procId) {   # 원외처방 창 HWND — 한 번 열리면 닫아도 화면 밖에 남아 있으므로(마지막에 연 환자) 계속 읽힌다
  foreach ($h in [BitW.U32]::Tops()) { if ([BitW.U32]::Pid($h) -ne $procId) { continue }
    $t = ([BitW.U32]::Text($h)) -replace '\s', ''; if ($t -like '원외처방*') { return $h } }
  return $null
}
function ReadRx($hwnd) {   # 차트번호 칸(라벨 오른쪽) + 특이사항 칸(라벨 아래 RichEdit) — Win32 좌표/텍스트
  $els = @()
  foreach ($h in [BitW.U32]::Children([IntPtr]$hwnd)) {
    $cls = [BitW.U32]::Cls($h); if ($cls -notmatch 'STATIC|EDIT|RichEdit|RICHEDIT') { continue }
    $r = New-Object BitW.U32+RECT; [void][BitW.U32]::GetWindowRect($h, [ref]$r)
    $els += [pscustomobject]@{ x = $r.L; y = $r.T; w = ($r.R - $r.L); h = ($r.B - $r.T); cls = $cls; name = [BitW.U32]::Text($h) }
  }
  $lblMrn = $els | Where-Object { $_.cls -match 'STATIC' -and (($_.name -replace '\s', '') -eq '차트번호') } | Select-Object -First 1
  $lblMemo = $els | Where-Object { $_.cls -match 'STATIC' -and (($_.name -replace '\s', '') -eq '특이사항') } | Select-Object -First 1
  if (-not $lblMrn -or -not $lblMemo) { return $null }
  $edits = $els | Where-Object { $_.cls -match 'EDIT|RichEdit|RICHEDIT' }
  $mrnEl = $edits | Where-Object { [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.x -ge ($lblMrn.x + $lblMrn.w - 8) -and $_.x -le ($lblMrn.x + $lblMrn.w + 80) } | Sort-Object x | Select-Object -First 1
  $memoEl = $edits | Where-Object { $_.y -ge ($lblMemo.y + $lblMemo.h - 6) -and $_.y -le ($lblMemo.y + $lblMemo.h + 60) -and $_.x -le ($lblMemo.x + 40) -and ($_.x + $_.w) -ge $lblMemo.x } | Sort-Object y | Select-Object -First 1
  $mrn = if ($mrnEl) { ($mrnEl.name -replace '\D', '') } else { '' }
  $memo = if ($memoEl) { $memoEl.name.Trim() } else { '' }
  return @{ mrn = $mrn; memoRx = $memo; found = ($null -ne $memoEl) }
}
# ── ③ 외래진료실 창(진료실 PC) — 증상 칸 맨 아래의 약·주사 목록 ──
$RX_HEAD = '^\s*med\b'   # 처방 블록 머리글(줄 시작, 대소문자 무시). 이 줄부터 끝까지 원문을 보내고 해석은 동선관리가 한다
$RX_MAX_LINES = 20         # 안전 상한(머리글부터 세어 앞쪽 유지)
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
    return @{ mrn = (([BitW.U32]::Text($c.mrn)) -replace '\D', ''); name = $(if ($null -ne $c.name) { ([BitW.U32]::Text($c.name)).Trim() } else { '' })
              note = [BitW.U32]::Text($c.note); memo = $(if ($null -ne $c.memo) { [BitW.U32]::Text($c.memo) } else { '' })
              rrn7 = (Rrn7 $(if ($null -ne $c.rrn) { [BitW.U32]::Text($c.rrn) } else { '' })); sex = (SexOf $(if ($null -ne $c.sex) { [BitW.U32]::Text($c.sex) } else { '' })); found = $true }
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
  $nameEl = $null
$1  # 주민번호 앞 7자리(YYMMDD-S)와 성별: 차트번호 줄의 '######-#' 꼴 라벨과 '(M/…' '(F/…' 라벨 — 뒷자리는 쓰지 않는다(카드가 없어도 슬립에 생년월일을 찍기 위함)
  $rrnEl = $els | Where-Object { [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.name -match '^\s*\d{6}-\d' } | Select-Object -First 1
  $sexEl = $els | Where-Object { [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.name -match '^\s*\((M|F)/' } | Select-Object -First 1
  # 증상 칸: 차트번호 줄보다 아래에 있는 RichEdit 중 화면에서 가장 위(y 최소)이면서 폭 200 이상인 것 (주호소/현병력 소형 칸·특이사항·과거내역 칸 제외)
  $noteEl = $els | Where-Object { $_.cls -match 'RichEdit|RICHEDIT' -and $_.w -ge 200 -and $_.h -ge 60 -and $_.y -gt $lblMrn.y } | Sort-Object y, @{ Expression = { -($_.w * $_.h) } } | Select-Object -First 1
  # 특이사항 칸: 증상 칸 오른쪽(증상 오른 끝 근처부터 시작)에서 증상 칸 세로 범위 안에 있는 RichEdit (환자에게 따라다니는 메모 — 진료 뒤에 적힘)
  $memoEl = $null
  if ($noteEl) { $memoEl = $els | Where-Object { $_.cls -match 'RichEdit|RICHEDIT' -and $_ -ne $noteEl -and $_.w -ge 150 -and $_.h -ge 60 -and $_.x -ge ($noteEl.x + $noteEl.w - 20) -and $_.y -ge $noteEl.y -and $_.y -le ($noteEl.y + $noteEl.h + 120) } | Sort-Object x, y | Select-Object -First 1 }
  $mrn = if ($mrnEl) { ($mrnEl.name -replace '\D', '') } else { '' }
  if ($mrnEl -and $noteEl) {   # 다음 주기부터는 이 핸들들만 읽는다 (비트가 화면을 다시 만들면 IsWindow 가 false → 다시 탐색)
    $script:DocCache = @{ hwnd = [IntPtr]$hwnd; mrn = $mrnEl.hw; note = $noteEl.hw; name = $(if ($nameEl) { $nameEl.hw } else { $null }); memo = $(if ($memoEl) { $memoEl.hw } else { $null }); rrn = $(if ($rrnEl) { $rrnEl.hw } else { $null }); sex = $(if ($sexEl) { $sexEl.hw } else { $null }) }
  }
  return @{ mrn = $mrn; name = $(if ($nameEl) { $nameEl.name.Trim() } else { '' }); note = $(if ($noteEl) { $noteEl.name } else { '' }); memo = $(if ($memoEl) { $memoEl.name } else { '' }); rrn7 = (Rrn7 $(if ($rrnEl) { $rrnEl.name } else { '' })); sex = (SexOf $(if ($sexEl) { $sexEl.name } else { '' })); found = ($null -ne $noteEl) }
}
function CleanMemo($text) {   # 특이사항: 비트가 넣는 빈 표시 줄('+', '-', '.')과 빈 줄을 빼고 나머지 줄만 (없으면 '')
  $out = @(); foreach ($l in (($text -replace "`r`n", "`n") -split "[`r`n]")) { $t = $l.Trim(); if ($t -and $t -notmatch '^[\s+\-_.·ㆍ,~*]*$') { $out += ($t -replace '\s{2,}', ' ') } }
  return ($out -join "`n")
}
function ExtractRx($text) {   # 증상 전체 → 맨 아래 처방 블록(마지막 'med' 줄부터 끝까지, 빈 줄 제외, 원문 그대로). 'med' 줄이 없으면 처방 없음
  $lines = @(($text -replace "`r`n", "`n") -split "[`r`n]" | ForEach-Object { $_.TrimEnd() })
  $end = $lines.Count - 1; while ($end -ge 0 -and -not $lines[$end].Trim()) { $end-- }
  if ($end -lt 0) { return @{ lines = @(); marker = $false } }
  $start = -1; for ($i = $end; $i -ge 0; $i--) { if ($lines[$i] -match $RX_HEAD) { $start = $i; break } }
  if ($start -lt 0) { return @{ lines = @(); marker = $false } }
  $out = @(); for ($i = $start; $i -le $end; $i++) { if ($lines[$i].Trim()) { $out += ($lines[$i].Trim() -replace '\s{2,}', ' ') } }
  if ($out.Count -gt $RX_MAX_LINES) { $out = @($out[0..($RX_MAX_LINES - 1)]) }
  return @{ lines = $out; marker = $true }
}

$LABELS = @{   # 화면 라벨(공백 제거) → 필드 키
  '차트번호(F1)(엔터)' = 'mrn'; '수진자명(F1)' = 'name'; '주민번호' = 'rrn'; '전진료실' = 'prevRoomDoc'; '전진료일' = 'prevVisit'
  '다음예약일' = 'nextResv'; '가입자성명' = 'guardian'; '최초내원일' = 'firstVisit'; '관계' = 'relation'; '보험유형' = 'ins'
  '초/재진' = 'chojae'; '접수메모(당일)' = 'memoToday'; '접수메모(연속)' = 'memoCont'
}
function ReadPanel($rootEl) {
  $all = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  # 주의: PowerShell 변수명은 대소문자를 구분하지 않으므로 $labels 를 쓰면 $LABELS(해시)가 가려진다 → $found
  $found = @(); $vals = @()
  foreach ($el in $all) {
    $c = $el.Current; $rc = $c.BoundingRectangle
    if ($rc.IsEmpty -or [double]::IsInfinity($rc.X)) { continue }
    $cls = [string]$c.ClassName; $nm = [string]$c.Name
    $o = [pscustomobject]@{ x = [int]$rc.X; y = [int]$rc.Y; w = [int]$rc.Width; h = [int]$rc.Height; name = $nm; cls = $cls }
    if ($cls -match '\.STATIC\.') { $key = ($nm -replace '\s', ''); if ($LABELS.ContainsKey($key)) { $found += [pscustomobject]@{ key = $LABELS[$key]; el = $o } } }
    elseif ($cls -match '\.EDIT\.|\.COMBOBOX\.') { $vals += $o }
  }
  if (-not $found.Count) { return $null }
  $rec = @{}
  foreach ($L in $found) {
    $lx = $L.el.x + $L.el.w; $ly = $L.el.y
    $cand = $vals | Where-Object { [Math]::Abs($_.y - $ly) -le 8 -and $_.x -ge ($lx - 8) -and $_.x -le ($lx + 60) } | Sort-Object x | Select-Object -First 1
    $rec[$L.key] = if ($cand) { ($cand.name -replace "\s+$", '') } else { '' }
  }
  return $rec
}
function Normalize($rec) {
  $out = [ordered]@{}
  $out.mrn = (([string]$rec.mrn) -replace '\D', '')
  $out.name = ([string]$rec.name).Trim()
  $m = [regex]::Match([string]$rec.rrn, '^(\d{6})-?(\d)')           # 생년월일 6자리 + 성별 1자리만 — 나머지는 읽지 않음
  $out.rrn7 = if ($m.Success) { $m.Groups[1].Value + '-' + $m.Groups[2].Value } else { '' }
  $pr = ([string]$rec.prevRoomDoc).Trim(); $parts = $pr -split '/', 2
  $out.prevRoom = $parts[0].Trim(); $out.doctor = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
  foreach ($k in 'prevVisit','nextResv','guardian','firstVisit','relation','ins','chojae','memoToday','memoCont') { $out[$k] = ([string]$rec[$k]).Trim() }
  $out.memoRx = ''
  return $out
}
function Hash($o) { return (($o.Keys | ForEach-Object { "$_=$($o[$_])" }) -join '|') }

# ── ② BITCast TCP 수신 ──
function CastParse($text, $fromIp) {
  # "2|테스트1|1진료실|672||김현우||    193428|"  → Command|Patname|Room|Hour|Memo|Dtrname|Beforeroom|OcmNum  (cLBITCastInfo.PatientData)
  $f = $text.TrimEnd("`r", "`n", "`0") -split '\|'
  if ($f.Count -lt 8) { return $null }
  $cmd = 0; if (-not [int]::TryParse($f[0].Trim(), [ref]$cmd)) { return $null }
  $ocm = ($f[7] -replace '\D', '')
  if (-not $ocm) { return $null }
  $hour = 0; [void][int]::TryParse($f[3].Trim(), [ref]$hour)
  return [ordered]@{ command = $cmd; name = $f[1].Trim(); room = $f[2].Trim(); hourMin = $hour; memo = $f[4].Trim(); doctor = $f[5].Trim(); beforeRoom = $f[6].Trim(); ocmNum = $ocm; fromIp = $fromIp }
}
# cLBITCastInfo.Enum_Command 전체 (0/1 은 Enum_Command 와 Enum_Command_New 에서 예약/응급이 뒤바뀌어 있어 둘 다 '접수'로 취급)
# 관찰: 접수 수정·보류 때 비트는 같은 접수번호로 '접수취소(3) → 접수(2)'를 1초 안에 연달아 보낸다. 진료실 PC는 5(보류재호출)·11(초기화접수)·7·8 을 보낸다.
$CMD_NAMES = @{ -3 = '지원호출'; -2 = '임시'; -1 = '환자호출'; 0 = '예약·응급접수'; 1 = '예약·응급접수'; 2 = '접수'; 3 = '접수취소'; 4 = '재호출'; 5 = '보류재호출'; 6 = '초기화'
                7 = '수납대기'; 8 = '수납완료'; 9 = '진료건너뜀'; 10 = '수납취소'; 11 = '초기화접수'; 12 = '초기화응급'; 13 = '보류'; 14 = '보류건너뜀'; 15 = '진료실변경'
                18 = '사전예약'; 21 = '진료중변경'; 22 = '보류지원'; 23 = '보류취소'; 24 = '초기화보류'; 25 = '접수보류' }
function CastDrain($listener) {   # 대기 중인 접속을 모두 받아 메시지 목록으로 (각 접속 = 메시지 1개, 짧음)
  $msgs = @()
  while ($listener.Pending()) {
    $cli = $null
    try {
      $cli = $listener.AcceptTcpClient(); $cli.ReceiveTimeout = 800
      $ip = ($cli.Client.RemoteEndPoint.ToString() -split ':')[0]
      $st = $cli.GetStream(); $ms = New-Object System.IO.MemoryStream; $buf = New-Object byte[] 4096
      $t0 = Get-Date
      while (((Get-Date) - $t0).TotalMilliseconds -lt 800) {
        if ($st.DataAvailable) { $r = $st.Read($buf, 0, $buf.Length); if ($r -le 0) { break }; $ms.Write($buf, 0, $r) }
        elseif ($ms.Length -gt 0) { Start-Sleep -Milliseconds 40; if (-not $st.DataAvailable) { break } }
        else { Start-Sleep -Milliseconds 40; if ($cli.Client.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $cli.Client.Available -eq 0) { break } }
      }
      $bytes = $ms.ToArray()
      if ($bytes.Length -gt 0) { $msgs += [pscustomobject]@{ ip = $ip; text = $Cp949.GetString($bytes) } }
    } catch { Log "cast 수신 오류: $($_.Exception.Message)" }
    finally { if ($cli) { try { $cli.Close() } catch {} } }
  }
  return $msgs
}

# ── 캐시: 인적정보 조회 (이름/차트번호 → 상세) — 캐스트 메시지에 차트번호가 없으므로 이름으로 매칭 ──
$script:LookupByName = @{}     # 이름 → @( @{ rec; at } … ) 차트번호별 최근 조회 (동명이인 구분용)
$script:CastDocByName = @{}    # 이름 → 오늘 이 이름으로 보낸 캐스트 문서 id (접수 뒤에 인적정보·원외처방 특이사항이 바뀌면 그 문서를 보충)
$script:SentHash = @{}         # 문서 id → 마지막으로 보낸 인적정보 해시
$script:SentMrn = @{}          # 문서 id → 보낸 차트번호 (한 번 보낸 차트번호는 다른 환자 조회로 바뀌지 않는다)
$script:DocByMrn = @{}         # 차트번호 → 오늘 문서 id (원외처방 특이사항을 패널과 무관하게 바로 보충할 때)
$script:RxSent = @{}; $script:RxNoDoc = @{}; $script:RxLast = ''; $script:RxCount = 0   # 원외처방 특이사항 전송 상태
$script:NoteSent = @{}; $script:NoteLast = ''; $script:NoteCount = 0; $script:NoteRev = @{}   # ③ 진료실 처방 목록 전송 상태 (차트번호 → 보낸 목록 / 갱신 횟수)
$script:LookupSent = @{}       # 차트번호 → bitLookup 으로 보낸 인적정보 해시 (조회 내용이 바뀔 때만 다시 씀)
$LOOKUP_KEYS = 'mrn','rrn7','prevRoom','prevVisit','nextResv','guardian','firstVisit','relation','ins','chojae','memoToday','memoCont','memoRx'
$LOOKUP_HOURS = 6              # 조회 캐시 유효 시간
$DUP_MIN = 15                  # 같은 이름·다른 차트번호가 이 시간 안에 함께 조회됐으면 동명이인으로 보고 차트번호를 붙이지 않는다
function CacheLookup($rec) {
  if (-not $rec.mrn -or -not $rec.name) { return }
  $list = @($script:LookupByName[$rec.name] | Where-Object { $_ -and $_.rec.mrn -ne $rec.mrn })
  $list += @{ rec = $rec; at = (Get-Date) }
  $script:LookupByName[$rec.name] = $list
}
function LookupState($name) {   # 최근 6시간 안에 이 PC에서 조회된 같은 이름의 환자 → @{ rec; dup }. 동명이인이 15분 안에 함께 조회됐으면 rec=$null, dup=$true
  $now = Get-Date
  $c = @($script:LookupByName[$name] | Where-Object { $_ -and ($now - $_.at).TotalHours -lt $LOOKUP_HOURS } | Sort-Object { $_.at } -Descending)
  if (-not $c.Count) { return @{ rec = $null; dup = $false } }
  if ($c.Count -ge 2 -and ($now - $c[1].at).TotalMinutes -lt $DUP_MIN) { return @{ rec = $null; dup = $true; count = $c.Count } }
  return @{ rec = $c[0].rec; dup = $false }
}
function MatchLookup($name) { return (LookupState $name).rec }
$script:MyIps = @()
try { $script:MyIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress }) } catch {}

function HandleCast($m) {
  $cname = if ($CMD_NAMES.ContainsKey($m.command)) { $CMD_NAMES[$m.command] } else { "cmd$($m.command)" }
  $docId = "$(Today)_ocm$($m.ocmNum)"
  $local = ($script:MyIps -contains $m.fromIp)
  $fields = @{ pc = $Pc; castIp = $m.fromIp; lastSeenAt = (NowIso); date = (Today); ocmNum = $m.ocmNum; command = [int]$m.command; commandName = $cname
               name = $m.name; room = $m.room; doctor = $m.doctor; castMemo = $m.memo; hourMin = [int]$m.hourMin; beforeRoom = $m.beforeRoom }
  switch ($m.command) {
    { $_ -in 2, 1, 0 } {   # 접수(일반/응급/예약) → 등록
      # 예약(0/1)인데 시각이 지금보다 30분 넘게 뒤면 아직 오지 않은 예약 등록으로 보고 등록하지 않는다 (관찰상 예약 등록은 캐스트가 없지만 안전장치)
      $nowMin = (Get-Date).Hour * 60 + (Get-Date).Minute
      if ($m.command -ne 2 -and ($m.hourMin - $nowMin) -gt 30) {
        $fields.event = "$cname(미도착)"; $fields.eventAt = (NowIso)
        Log "cast $cname 접수번호 $($m.ocmNum): 예약 시각 $([int]($m.hourMin / 60)):$('{0:00}' -f ($m.hourMin % 60)) 이 미래 → 등록하지 않음(기록만)"
        break
      }
      # status 는 건드리지 않는다: 여러 PC가 같은 문서에 쓰므로, 동선관리가 먼저 '자동접수'로 바꾼 뒤 늦게 도착한 쓰기가 되돌리면 안 됨
      $fields.registered = $true; $fields.registeredAt = (NowIso); $fields.cancelled = $false
      $fields.seenAt = (NowIso)
      $ls = LookupState $m.name
      $script:CastDocByName[$m.name] = $docId
      if ($ls.dup) { $fields.nameDup = $true; Log "cast $cname 접수번호 $($m.ocmNum): 동명이인 주의 — 같은 이름 차트번호 $($ls.count)개가 $DUP_MIN 분 안에 조회됨 → 차트번호 없이 전송(직원 확인)" }
      elseif ($ls.rec) { foreach ($k in $LOOKUP_KEYS) { if ($ls.rec[$k]) { $fields[$k] = $ls.rec[$k] } }; $fields.lookupPc = $Pc; $script:SentHash[$docId] = (Hash $ls.rec); $script:SentMrn[$docId] = $ls.rec.mrn; $script:DocByMrn[$ls.rec.mrn] = $docId }
      elseif (-not $local) { Log "cast $cname 접수번호 $($m.ocmNum): 다른 PC($($m.fromIp))의 접수 — 인적정보 캐시 없음(이름만 전송)" }
      else { Log "cast $cname 접수번호 $($m.ocmNum): 인적정보 캐시 없음(이름만 전송)" }
    }
    3 {  # 접수취소
      $fields.cancelled = $true; $fields.cancelledAt = (NowIso)
    }
    default {   # 호출·보류·사전예약·수납대기 등: 기록. 접수취소 뒤에 이런 캐스트가 오면 환자가 살아 있다는 뜻 → 취소 해제
      # (예약 환자: 예약접수(0/1) → 3초 뒤 접수취소(3) → 사전예약(18)/진료중변경(21) 순으로 온다. 이 취소는 진짜 취소가 아님)
      $fields.event = $cname; $fields.eventAt = (NowIso)
      if ($m.command -notin 8, 10) { $fields.cancelled = $false }
    }
  }
  FsPatch "bitIntake/$docId" $fields
  Log "전송: $docId $cname (이름 $($m.name.Length)자, 진료실 $($m.room), 차트번호 $(if ($fields.mrn) { '있음' } else { '없음' }), from $($m.fromIp))"
}

# ── 메인 루프 ──
Log "시작 v3: PC=$Pc  cast TCP $CastPort  패널 주기=${PollSec}s  처방 머리글=$RX_HEAD  내 IP=$($script:MyIps -join ',')"
try { $hadRt = [bool]$script:Refresh; $null = FbToken; if ($hadRt -and $script:Tok) { Log "저장된 세션(토큰)으로 시작 — 비밀번호 로그인 생략" } } catch { Log "$_"; Start-Sleep 30 }
$listener = $null
try { $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Any), $CastPort; $listener.Start(); Log "BITCast 수신 대기: TCP $CastPort" }
catch { Log "TCP $CastPort 열기 실패(다른 프로그램이 사용 중?): $($_.Exception.Message) — 캐스트 없이 패널만 감시"; $listener = $null }
$stableHash = ''; $stableCount = 0
$lastPanel = [DateTime]::MinValue; $lastBeat = [DateTime]::MinValue; $lastOpen = $null; $lastDocOpen = $null
$recent = @{}          # 중복 캐스트 억제: key → 시각 (전광판IP + 캐스트IP 가 같으면 같은 메시지가 2번 온다)
$rxWarned = $false; $rxCache = @{}; $noteWarned = $false
$sentDay = (Today)
while ($true) {
  $cycStart = Get-Date
  try {
    if ($sentDay -ne (Today)) { $sentDay = (Today); $script:LookupByName = @{}; $script:CastDocByName = @{}; $script:SentHash = @{}; $script:SentMrn = @{}; $script:DocByMrn = @{}; $script:RxSent = @{}; $script:RxNoDoc = @{}; $script:NoteSent = @{}; $script:NoteRev = @{}; $script:LookupSent = @{}; $recent = @{}; $rxCache = @{}; TrimLog }
    # ── ② 캐스트 수신 (0.5초 간격) ──
    if ($listener) {
      foreach ($raw in (CastDrain $listener)) {
        $m = CastParse $raw.text $raw.ip
        if (-not $m) { Log "cast 해석 불가(len $($raw.text.Length)) from $($raw.ip)"; continue }
        $key = "$($m.command)|$($m.ocmNum)|$($m.name)"
        $now = Get-Date
        if ($recent.ContainsKey($key) -and ($now - $recent[$key]).TotalSeconds -lt 8) { continue }
        $recent[$key] = $now
        try { HandleCast $m } catch { Log "cast 처리 오류: $($_.Exception.Message)" }
      }
      foreach ($k in @($recent.Keys)) { if (((Get-Date) - $recent[$k]).TotalMinutes -gt 30) { $recent.Remove($k) } }
    }
    # ── ① 인적정보 패널 (PollSec 간격) + 하트비트 ──
    if (((Get-Date) - $lastPanel).TotalSeconds -ge $PollSec) {
      $lastPanel = Get-Date
      $bw = FindBitWindow
      $open = ($null -ne $bw)
      $dw = $null; try { $dw = FindDoctorWindow } catch { Log "외래진료실 창 찾기 오류: $($_.Exception.Message)" }
      $docOpen = ($null -ne $dw)
      if (((Get-Date) - $lastBeat).TotalSeconds -ge $HeartbeatSec -or $open -ne $lastOpen -or $docOpen -ne $lastDocOpen) {
        # 자가 진단 필드: ver·시작 시각·가동 시간·PID·마지막 오류·이번 구간 최장 주기·로그 끝 5줄 (이름은 로그에 없음) — 동선관리 pill 툴팁과 원격 점검용
        $hb = @{ pc = $Pc; lastSeen = (NowIso); bitOpen = $open; doctorOpen = $docOpen; cast = ($null -ne $listener); ip = ($script:MyIps -join ',')
                 ver = 'v3'; startedAt = $script:StartedAt; uptimeSec = [int]((Get-Date) - [DateTime]::Parse($script:StartedAt)).TotalSeconds; procId = [int]$PID
                 lastErr = $script:LastErr; lastErrAt = $script:LastErrAt; cycMaxMs = [int]$script:CycMax; logTail = (LogTail 5) }
        try { FsPatch "bitStatus/$([Uri]::EscapeDataString($Pc))" $hb; $lastBeat = Get-Date; $lastOpen = $open; $lastDocOpen = $docOpen; $script:CycMax = 0 }
        catch { Log "하트비트 실패: $($_.Exception.Message)"; $lastBeat = Get-Date; $lastOpen = $open; $lastDocOpen = $docOpen }   # 실패해도 30초 뒤에 다시(2초마다 재시도해 로그·로그인 시도를 쏟지 않도록)
      }
      # ── ③ 외래진료실 증상 칸 맨 아래 처방 목록 (진료실 PC) ──
      if ($docOpen) {
        try {
          $dr = ReadDoctor $dw
          if ($dr -and -not $dr.found -and -not $noteWarned) { Log "외래진료실 창은 찾았지만 증상 칸을 못 찾음"; $noteWarned = $true }
          if ($dr -and $dr.mrn) {
            $ex = if ($dr.note.Trim()) { ExtractRx $dr.note } else { @{ lines = @(); marker = $false } }
            $rxText = ($ex.lines -join "`n")
            $memo = CleanMemo $dr.memo
            if ($rxText -or $memo) {
              $nk = "$($dr.mrn)|$rxText|$memo"
              if ($nk -eq $script:NoteLast) { $script:NoteCount++ } else { $script:NoteLast = $nk; $script:NoteCount = 1 }
              if ($script:NoteCount -eq 2 -and $script:NoteSent[$dr.mrn] -ne "$rxText|$memo") {   # 2번 연속 같은 값(입력 중 아님)이고 아직 보내지 않은 내용
                # rev = 오늘 이 PC에서 이 환자 문서를 보낸 횟수. 비트가 지난 진료의 문구를 미리 채워 두므로 1회차는 '이전 처방'일 수 있다 → 동선관리가 갱신 횟수·시각을 보여 준다
                $rev = [int]$script:NoteRev[$dr.mrn] + 1; $script:NoteRev[$dr.mrn] = $rev
                $nf = @{ date = (Today); mrn = $dr.mrn; name = $dr.name; pc = $Pc; rx = $rxText; rxMarker = [bool]$ex.marker; rxLines = [int]$ex.lines.Count; memo = $memo; rrn7 = $dr.rrn7; sex = $dr.sex; rev = $rev; updatedAt = (NowIso) }
                if ($rev -eq 1) { $nf.firstAt = (NowIso) }
                FsPatch "bitNote/$(Today)_$($dr.mrn)" $nf
                $script:NoteSent[$dr.mrn] = "$rxText|$memo"
                Log "처방 전송: 차트번호 $($dr.mrn) ($($ex.lines.Count)줄, med 줄 $(if ($ex.marker) { '있음' } else { '없음' }), 주민앞자리 $(if ($dr.rrn7) { '있음' } else { '없음' }), 특이사항 $(if ($memo) { '있음' } else { '없음' }), ${rev}회차)"
              }
            }
          }
        } catch { Log "외래진료실 읽기 오류: $($_.Exception.Message)" }
      }
      if ($open) {
        try {
          $rw = FindRxWindow $bw.proc.Id
          if ($rw) { $rx = ReadRx $rw
            if ($rx -and -not $rx.found -and -not $rxWarned) { Log "원외처방 창은 찾았지만 특이사항 칸을 못 찾음"; $rxWarned = $true }
            if ($rx -and $rx.mrn -and $rx.memoRx) {
              $rxCache[$rx.mrn] = $rx.memoRx
              # 원외처방 특이사항은 진료가 끝난 뒤(수납 무렵) 입력·열람되므로 패널에 그 환자가 떠 있지 않아도 차트번호로 오늘 문서를 찾아 바로 보충.
              # 2번 연속 같은 값(입력 중 아님)이고 아직 보내지 않은 내용일 때만.
              $rk = "$($rx.mrn)|$($rx.memoRx)"
              if ($rk -eq $script:RxLast) { $script:RxCount++ } else { $script:RxLast = $rk; $script:RxCount = 1 }
              if ($script:RxCount -eq 2 -and $script:RxSent[$rx.mrn] -ne $rx.memoRx) {
                $d = $script:DocByMrn[$rx.mrn]
                if (-not $d -and -not ($script:RxNoDoc[$rx.mrn] -and ((Get-Date) - $script:RxNoDoc[$rx.mrn]).TotalMinutes -lt 5)) {
                  $d = FsFindDocByMrn $rx.mrn
                  if ($d) { $script:DocByMrn[$rx.mrn] = $d } else { $script:RxNoDoc[$rx.mrn] = Get-Date; Log "원외처방 특이사항: 차트번호 $($rx.mrn) 의 오늘 접수 문서 없음(5분 뒤 재확인)" }
                }
                if ($d) { FsPatch "bitIntake/$d" @{ memoRx = $rx.memoRx; rxPc = $Pc; lastSeenAt = (NowIso) }; $script:RxSent[$rx.mrn] = $rx.memoRx; Log "보충: $d 원외처방 특이사항 (차트번호 $($rx.mrn))" }
              }
            } }
        } catch { Log "원외처방 읽기 오류: $($_.Exception.Message)" }
        $raw = ReadPanel $bw.el
        if ($raw) {
          $rec = Normalize $raw
          if ($rec.mrn -and $rxCache.ContainsKey($rec.mrn)) { $rec.memoRx = $rxCache[$rec.mrn] }
          $h = Hash $rec
          if ($h -eq $stableHash) { $stableCount++ } else { $stableHash = $h; $stableCount = 1 }
          if ($stableCount -eq 2 -and $rec.mrn -and $rec.name) {   # 2번 연속 같은 값(입력 중 아님)일 때 캐시
            CacheLookup $rec
            # 조회된 인적정보를 bitLookup/{날짜}_{차트번호} 에도 남긴다 — 아래의 이름→캐스트 문서 매칭은 이 스크립트 메모리에만 있어서
            # 스크립트가 재시작되거나 접수가 다른 PC에서 됐으면 놓친다. 동선관리가 이 문서로 차트번호 없는 캐스트 카드를 이름으로 뒤늦게 채운다(오늘 그 이름이 하나일 때만)
            try {
              if ($script:LookupSent[$rec.mrn] -ne $h) {
                $lf = @{ date = (Today); pc = $Pc; at = (NowIso); name = $rec.name; doctor = $rec.doctor }
                foreach ($k in $LOOKUP_KEYS) { if ($rec[$k]) { $lf[$k] = $rec[$k] } }
                FsPatch "bitLookup/$(Today)_$($rec.mrn)" $lf; $script:LookupSent[$rec.mrn] = $h
                Log "조회 기록: 차트번호 $($rec.mrn) (이름 $($rec.name.Length)자) → bitLookup"
              }
            } catch { Log "조회 기록 실패: $($_.Exception.Message)" }
            # 이미 접수(캐스트)된 환자의 인적정보·원외처방 특이사항이 그 뒤에 읽히거나 바뀌면 → 보낸 문서를 보충(merge)
            $d = $script:CastDocByName[$rec.name]
            if ($d -and $script:SentHash[$d] -ne $h) {
              $sent = $script:SentMrn[$d]
              if ($sent -and $sent -ne $rec.mrn) { Log "보충 건너뜀: $d 는 이미 다른 차트번호로 전송됨(동명이인 조회)"; $script:SentHash[$d] = $h }
              elseif (-not $sent -and (LookupState $rec.name).dup) { Log "보충 보류: $d 동명이인 후보가 여럿(직원 확인)"; $script:SentHash[$d] = $h }
              else {
                $f = @{ lookupPc = $Pc; lastSeenAt = (NowIso); nameDup = $false }
                foreach ($k in $LOOKUP_KEYS) { if ($rec[$k]) { $f[$k] = $rec[$k] } }
                FsPatch "bitIntake/$d" $f; $script:SentHash[$d] = $h; $script:SentMrn[$d] = $rec.mrn; $script:DocByMrn[$rec.mrn] = $d
                Log "보충: $d 인적정보 (차트번호 있음, 연속메모 $(if ($rec.memoCont) { '있음' } else { '없음' }), 원외처방 특이사항 $(if ($rec.memoRx) { '있음' } else { '없음' }))"
              }
            }
          }
        }
      }
    }
  } catch { Log "오류: $($_.Exception.Message)"; Start-Sleep 5 }
  # 한 주기가 오래 걸리면(창 읽기·네트워크 지연) 하트비트가 늦어져 pill 이 회색이 된다 → 원인 추적용 기록
  $cycMs = [int]((Get-Date) - $cycStart).TotalMilliseconds; if ($cycMs -gt $script:CycMax) { $script:CycMax = $cycMs }
  if ($cycMs -gt 10000) { Log "느린 주기: ${cycMs}ms (창 읽기 또는 네트워크 지연)" }
  Start-Sleep -Milliseconds 500
}
