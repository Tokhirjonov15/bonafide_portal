# ─────────────────────────────────────────────────────────────
#  비트플러스 접수 감시 스크립트 (반듯한정형외과 동선관리 연동)
#
#  하는 일: 비트플러스 '접수' 창의 인적정보 패널(차트번호·이름·가입자·최초내원일·보험·메모 등)을
#           2초마다 읽어, 선택된 환자가 바뀌면 동선관리 Firebase(bitIntake 컬렉션)에 올린다.
#           동선관리 화면에 '비트 접수 대기' 줄로 나타나고, 직원이 [접수]를 눌러야 환자가 만들어진다.
#  안 하는 일: 비트플러스에 아무것도 입력·클릭하지 않는다. 주민번호 뒷자리·전화·주소는 읽지 않는다.
#
#  설치: 1) 이 파일을 C:\bitplus\bitplus_watcher.ps1 로 복사
#        2) 같은 폴더에 bitplus_watcher.secret 파일을 만들고 첫 줄에 동선관리 'bitbot' 계정 비밀번호를 적는다
#        3) 실행:  powershell -ExecutionPolicy Bypass -File C:\bitplus\bitplus_watcher.ps1 -Pc 접수1
#        4) 작업 스케줄러에 '로그온 시' 실행으로 등록하면 재부팅 후 자동 시작 (README 참고)
# ─────────────────────────────────────────────────────────────
param(
  [string]$Pc = $env:COMPUTERNAME,   # 동선관리에 표시될 이 PC 이름 (예: 접수1)
  [int]$PollSec = 2,                  # 화면 읽기 주기(초)
  [int]$HeartbeatSec = 30             # 하트비트 주기(초)
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
function FsFields($h) {   # 해시테이블 → Firestore 필드 표현 (문자열/불리언만 사용)
  $f = @{}
  foreach ($k in $h.Keys) { $v = $h[$k]; if ($v -is [bool]) { $f[$k] = @{ booleanValue = $v } } else { $f[$k] = @{ stringValue = [string]$v } } }
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

# ── 비트플러스 접수 창 읽기 ──
function FindBit() {   # 접수 프로세스 (MainWindowHandle, Id)
  return Get-Process -Name BITRegistrations -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}
# ── 원외처방 창(같은 프로세스의 별도 창)의 특이사항 — 열려 있을 때만 읽는다 ──
function FindRxWindow($procId) {
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
function ReadPanel($hwnd) {
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  # 주의: PowerShell 변수명은 대소문자를 구분하지 않으므로 $labels 를 쓰면 위의 $LABELS(해시)가 가려져 ContainsKey 가 실패한다 → $found 로 명명
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
  $out.memoRx = ''   # 원외처방 창의 특이사항 (있을 때만 채움)
  return $out
}
function Hash($o) { return (($o.Keys | ForEach-Object { "$_=$($o[$_])" }) -join '|') }

# ── 메인 루프 ──
Log "시작: PC=$Pc  주기=${PollSec}s"
try { FbLogin } catch { Log "Firebase 로그인 실패: $_ (30초 후 재시도)"; Start-Sleep 30 }
$lastHash = ''; $stableHash = ''; $stableCount = 0
$sent = @{}            # 오늘 보낸 것: mrn → hash
$rxCache = @{}         # 원외처방 창에서 읽은 특이사항: mrn → 텍스트 (오늘)
$rxSent = @{}          # 문서에 이미 보낸 원외처방 특이사항: mrn → 텍스트
$rxWarned = $false
$sentDay = (Today)
$lastBeat = [DateTime]::MinValue; $lastOpen = $null
while ($true) {
  try {
    if ($sentDay -ne (Today)) { $sent = @{}; $rxCache = @{}; $rxSent = @{}; $sentDay = (Today); TrimLog }
    $proc = FindBit
    $open = ($null -ne $proc)
    $hwnd = if ($open) { $proc.MainWindowHandle } else { [IntPtr]::Zero }
    # 하트비트
    if (((Get-Date) - $lastBeat).TotalSeconds -ge $HeartbeatSec -or $open -ne $lastOpen) {
      try { FsPatch "bitStatus/$([Uri]::EscapeDataString($Pc))" @{ pc = $Pc; lastSeen = (NowIso); bitOpen = $open }; $lastBeat = Get-Date; $lastOpen = $open } catch { Log "하트비트 실패: $_" }
    }
    if (-not $open) { Start-Sleep 5; continue }
    # 원외처방 창이 열려 있으면 그 환자의 특이사항을 읽어 둔다 (이미 보낸 환자면 문서에 바로 보충)
    try {
      $rw = FindRxWindow $proc.Id
      if ($rw) {
        $rx = ReadRx $rw
        if ($rx -and -not $rx.found -and -not $rxWarned) { Log "원외처방 창은 찾았지만 특이사항 칸을 못 찾음 (라벨 배치 확인 필요)"; $rxWarned = $true }
        if ($rx -and $rx.mrn -and $rx.memoRx) {
          $rxCache[$rx.mrn] = $rx.memoRx
          if ($sent.ContainsKey($rx.mrn) -and $rxSent[$rx.mrn] -ne $rx.memoRx) {
            FsPatch "bitIntake/$((Today))_$($rx.mrn)" @{ memoRx = $rx.memoRx; lastSeenAt = (NowIso) }
            $rxSent[$rx.mrn] = $rx.memoRx; Log "원외처방 특이사항 보충: $($rx.mrn)"
          }
        }
      }
    } catch { Log "원외처방 읽기 오류: $($_.Exception.Message)" }
    $raw = ReadPanel $hwnd
    if ($raw) {
      $rec = Normalize $raw
      if ($rec.mrn -and $rxCache.ContainsKey($rec.mrn)) { $rec.memoRx = $rxCache[$rec.mrn] }
      $h = Hash $rec
      if ($h -eq $stableHash) { $stableCount++ } else { $stableHash = $h; $stableCount = 1 }
      # 2번 연속 같은 값(입력 중이 아님) + 차트번호·이름 있음 + 오늘 아직 안 보낸 내용
      if ($stableCount -ge 2 -and $rec.mrn -and $rec.name -and $sent[$rec.mrn] -ne $h) {
        $docId = "$(Today)_$($rec.mrn)"
        $fields = @{}
        foreach ($k in $rec.Keys) { $fields[$k] = $rec[$k] }
        $fields.pc = $Pc; $fields.lastSeenAt = (NowIso); $fields.date = (Today)
        if (-not (FsExists "bitIntake/$docId")) { $fields.seenAt = (NowIso); $fields.status = '' }   # 첫 등록 때만 seenAt·status
        FsPatch "bitIntake/$docId" $fields
        $sent[$rec.mrn] = $h; if ($rec.memoRx) { $rxSent[$rec.mrn] = $rec.memoRx }
        Log "전송: $docId (이름 $($rec.name.Length)자, 최초내원 $($rec.firstVisit))"
      }
    }
  } catch { Log "오류: $($_.Exception.Message)"; Start-Sleep 5 }
  Start-Sleep $PollSec
}
