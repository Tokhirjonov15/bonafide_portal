# ─────────────────────────────────────────────────────────────
#  비트플러스 접수 감시 스크립트 v2 (반듯한정형외과 동선관리 연동)
#
#  두 채널을 합친다:
#   ① BITCast (TCP 9000) — 비트 환경설정 › 기타사항 › 전광판IP 세팅에 이 PC IP를 등록하면
#      모든 접수 PC의 비트가 접수/취소/호출 이벤트를 이 PC로 보낸다.
#      메시지: "Command|이름|진료실|분(0시 기준)|메모|담당의|이전방|접수번호|"
#      Command: 2=접수  3=접수취소  1=응급접수  0=예약접수  -1=환자호출  13=보류 (cLBITCastInfo.Enum_Command)
#      ※ 차트번호는 메시지에 없다 → ②의 인적정보 캐시로 채운다.
#   ② 접수 창 인적정보 패널(UIAutomation, 2초) — 조회된 환자의 차트번호·주민번호7·보험·메모 등을 캐시.
#      비트에는 아무것도 입력·클릭하지 않는다. 주민번호 뒷자리·전화·주소는 읽지 않는다.
#
#  Firestore:  bitIntake/{날짜}_ocm{접수번호}  ← 접수 이벤트(등록/취소).  같은 문서에 여러 PC가 merge 로 쓴다.
#              bitStatus/{PC}                 ← 하트비트
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
  [int]$HeartbeatSec = 30            # 하트비트 주기(초)
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
function Log($m) { $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"; Write-Host $line; try { Add-Content $LogFile $line -Encoding UTF8 } catch {} }
function TrimLog() { try { if ((Get-Item $LogFile -ErrorAction SilentlyContinue).Length -gt 2MB) { Get-Content $LogFile -Tail 2000 | Set-Content $LogFile -Encoding UTF8 } } catch {} }

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Cp949 = [System.Text.Encoding]::GetEncoding(949)

# ── Firebase 로그인 / Firestore REST ──
$script:Tok = $null; $script:TokExp = [DateTime]::MinValue; $script:Refresh = $null
function FbLogin() {
  $body = @{ email = $BotEmail; password = $BotPassword; returnSecureToken = $true } | ConvertTo-Json -Compress
  $r = Invoke-RestMethod -Method Post -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$ApiKey" -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  $script:Tok = $r.idToken; $script:Refresh = $r.refreshToken; $script:TokExp = (Get-Date).AddSeconds([int]$r.expiresIn - 300)
  Log "Firebase 로그인 성공"
}
function FbToken() {
  if ($script:Tok -and (Get-Date) -lt $script:TokExp) { return $script:Tok }
  if ($script:Refresh) {
    try {
      $r = Invoke-RestMethod -Method Post -Uri "https://securetoken.googleapis.com/v1/token?key=$ApiKey" -ContentType 'application/x-www-form-urlencoded' -Body "grant_type=refresh_token&refresh_token=$($script:Refresh)"
      $script:Tok = $r.id_token; $script:Refresh = $r.refresh_token; $script:TokExp = (Get-Date).AddSeconds([int]$r.expires_in - 300)
      return $script:Tok
    } catch { Log "토큰 갱신 실패 → 재로그인: $_" }
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
  try { $null = Invoke-RestMethod -Method Get -Uri "$DocBase/$path" -Headers @{ Authorization = "Bearer $(FbToken)" }; return $true }
  catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $false }; throw }
}
function FsPatch($path, $fields) {   # 지정한 필드만 갱신(merge). 없는 문서는 생성
  $mask = ($fields.Keys | ForEach-Object { 'updateMask.fieldPaths=' + [Uri]::EscapeDataString($_) }) -join '&'
  $body = @{ fields = (FsFields $fields) } | ConvertTo-Json -Depth 6 -Compress
  $null = Invoke-RestMethod -Method Patch -Uri "$DocBase/$path`?$mask" -Headers @{ Authorization = "Bearer $(FbToken)" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
}
function NowIso() { return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }
function Today { return (Get-Date).ToString('yyyy-MM-dd') }

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
function FindRxWindow($procId) {   # 원외처방 창(같은 프로세스의 별도 창) — 열려 있을 때만
  $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ProcessIdProperty), $procId
  $wins = [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
  foreach ($w in $wins) { $n = ([string]$w.Current.Name) -replace '\s', ''; if ($n -like '원외처방*') { return $w } }
  return $null
}
function ReadRx($win) {
  $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $els = @()
  foreach ($el in $all) {
    $c = $el.Current; $rc = $c.BoundingRectangle
    if ($rc.IsEmpty -or [double]::IsInfinity($rc.X)) { continue }
    $els += [pscustomobject]@{ x = [int]$rc.X; y = [int]$rc.Y; w = [int]$rc.Width; h = [int]$rc.Height; name = [string]$c.Name; cls = [string]$c.ClassName }
  }
  $lblMrn = $els | Where-Object { (($_.name -replace '\s', '') -eq '차트번호') } | Select-Object -First 1
  $lblMemo = $els | Where-Object { (($_.name -replace '\s', '') -eq '특이사항') } | Select-Object -First 1
  if (-not $lblMrn -or -not $lblMemo) { return $null }
  $edits = $els | Where-Object { $_.cls -match '\.EDIT\.|RichEdit|RICHEDIT' }
  $mrnEl = $edits | Where-Object { [Math]::Abs($_.y - $lblMrn.y) -le 10 -and $_.x -ge ($lblMrn.x + $lblMrn.w - 8) -and $_.x -le ($lblMrn.x + $lblMrn.w + 80) } | Sort-Object x | Select-Object -First 1
  $memoEl = $edits | Where-Object { $_.y -ge ($lblMemo.y + $lblMemo.h - 6) -and $_.y -le ($lblMemo.y + $lblMemo.h + 60) -and $_.x -le ($lblMemo.x + 40) -and ($_.x + $_.w) -ge $lblMemo.x } | Sort-Object y | Select-Object -First 1
  $mrn = if ($mrnEl) { ($mrnEl.name -replace '\D', '') } else { '' }
  $memo = if ($memoEl) { $memoEl.name.Trim() } else { '' }
  return @{ mrn = $mrn; memoRx = $memo; found = ($null -ne $memoEl) }
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
$CMD_NAMES = @{ 2 = '접수'; 3 = '접수취소'; 1 = '응급접수'; 0 = '예약접수'; -1 = '환자호출'; -3 = '지원호출'; 13 = '보류'; 4 = '재호출'; 15 = '진료실변경'; 10 = '수납취소'; 7 = '수납대기'; 8 = '수납완료'; 25 = '접수보류' }
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
$script:LookupByName = @{}     # 이름 → @{ rec; at }
$script:LookupByMrn = @{}
function CacheLookup($rec) {
  if (-not $rec.mrn -or -not $rec.name) { return }
  $e = @{ rec = $rec; at = (Get-Date) }
  $script:LookupByName[$rec.name] = $e; $script:LookupByMrn[$rec.mrn] = $e
}
function MatchLookup($name) {   # 최근 6시간 안에 이 PC에서 조회된 같은 이름의 환자
  $e = $script:LookupByName[$name]
  if ($e -and ((Get-Date) - $e.at).TotalHours -lt 6) { return $e.rec }
  return $null
}
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
      $fields.registered = $true; $fields.registeredAt = (NowIso); $fields.cancelled = $false; $fields.status = ''
      $fields.seenAt = (NowIso)
      $rec = MatchLookup $m.name
      if ($rec) { foreach ($k in 'mrn','rrn7','prevRoom','prevVisit','nextResv','guardian','firstVisit','relation','ins','chojae','memoToday','memoCont','memoRx') { if ($rec[$k]) { $fields[$k] = $rec[$k] } }; $fields.lookupPc = $Pc }
      elseif (-not $local) { Log "cast $cname 접수번호 $($m.ocmNum): 다른 PC($($m.fromIp))의 접수 — 인적정보 캐시 없음(이름만 전송)" }
      else { Log "cast $cname 접수번호 $($m.ocmNum): 인적정보 캐시 없음(이름만 전송)" }
    }
    3 {  # 접수취소
      $fields.cancelled = $true; $fields.cancelledAt = (NowIso)
    }
    default { $fields.event = $cname; $fields.eventAt = (NowIso) }   # 호출·보류 등: 기록만 (동선관리에서 추후 활용)
  }
  FsPatch "bitIntake/$docId" $fields
  Log "전송: $docId $cname (이름 $($m.name.Length)자, 진료실 $($m.room), 차트번호 $(if ($fields.mrn) { '있음' } else { '없음' }), from $($m.fromIp))"
}

# ── 메인 루프 ──
Log "시작 v2: PC=$Pc  cast TCP $CastPort  패널 주기=${PollSec}s  내 IP=$($script:MyIps -join ',')"
try { FbLogin } catch { Log "Firebase 로그인 실패: $_ (30초 후 재시도)"; Start-Sleep 30 }
$listener = $null
try { $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Any), $CastPort; $listener.Start(); Log "BITCast 수신 대기: TCP $CastPort" }
catch { Log "TCP $CastPort 열기 실패(다른 프로그램이 사용 중?): $($_.Exception.Message) — 캐스트 없이 패널만 감시"; $listener = $null }
$stableHash = ''; $stableCount = 0
$lastPanel = [DateTime]::MinValue; $lastBeat = [DateTime]::MinValue; $lastOpen = $null
$recent = @{}          # 중복 캐스트 억제: key → 시각 (전광판IP + 캐스트IP 가 같으면 같은 메시지가 2번 온다)
$rxWarned = $false; $rxCache = @{}
$sentDay = (Today)
while ($true) {
  try {
    if ($sentDay -ne (Today)) { $sentDay = (Today); $script:LookupByName = @{}; $script:LookupByMrn = @{}; $recent = @{}; $rxCache = @{}; TrimLog }
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
      if (((Get-Date) - $lastBeat).TotalSeconds -ge $HeartbeatSec -or $open -ne $lastOpen) {
        try { FsPatch "bitStatus/$([Uri]::EscapeDataString($Pc))" @{ pc = $Pc; lastSeen = (NowIso); bitOpen = $open; cast = ($null -ne $listener); ip = ($script:MyIps -join ',') }; $lastBeat = Get-Date; $lastOpen = $open } catch { Log "하트비트 실패: $_" }
      }
      if ($open) {
        try {
          $rw = FindRxWindow $bw.proc.Id
          if ($rw) { $rx = ReadRx $rw
            if ($rx -and -not $rx.found -and -not $rxWarned) { Log "원외처방 창은 찾았지만 특이사항 칸을 못 찾음"; $rxWarned = $true }
            if ($rx -and $rx.mrn -and $rx.memoRx) { $rxCache[$rx.mrn] = $rx.memoRx } }
        } catch { Log "원외처방 읽기 오류: $($_.Exception.Message)" }
        $raw = ReadPanel $bw.el
        if ($raw) {
          $rec = Normalize $raw
          if ($rec.mrn -and $rxCache.ContainsKey($rec.mrn)) { $rec.memoRx = $rxCache[$rec.mrn] }
          $h = Hash $rec
          if ($h -eq $stableHash) { $stableCount++ } else { $stableHash = $h; $stableCount = 1 }
          if ($stableCount -eq 2 -and $rec.mrn -and $rec.name) { CacheLookup $rec }   # 2번 연속 같은 값(입력 중 아님)일 때 캐시
        }
      }
    }
  } catch { Log "오류: $($_.Exception.Message)"; Start-Sleep 5 }
  Start-Sleep -Milliseconds 500
}
