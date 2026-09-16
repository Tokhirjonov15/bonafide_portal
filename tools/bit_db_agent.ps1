# ─────────────────────────────────────────────────────────────
#  비트(Dr.BIT) DB 접수 감시 에이전트 v1.0 (반듯한정형외과 동선관리 연동)
#
#  비트 SQL Server(drbitpack)의 OcmInf(접수) 를 4초마다 읽기 전용 계정으로 SELECT 해서, 상태가 '접수 계열'로 처음 바뀐 순간을
#  동선관리 Firestore bitIntake/{날짜}_ocm{접수번호} 문서로 올린다. 문서 형식은 bitplus_watcher.ps1(캐스트 채널)과 같아서
#  동선관리 웹은 고치지 않아도 되고, 두 스크립트가 같은 문서에 merge 로 써도 충돌하지 않는다.
#  (파트너 병원 문서 기술문서_유차트_접수데이터_수집.md 의 decide 알고리즘을 따른다)
#
#  읽기만 한다: dongseon_ro 는 db_datareader + INSERT/UPDATE/DELETE/EXECUTE 거부. 이 스크립트는 실행 전에 SQL 문을 검사해 SELECT 한 문장만 허용한다.
#  주민번호는 앞 7자리(YYMMDD-S)만 만들어 보내고, 이름·주민번호는 로그에 남기지 않는다(차트번호만).
#
#  상태(OcmComStt) → 동선관리 command:
#    WN/NN/WC/WT/SN/SC/ST(접수·대기)        → 2 접수           registered=true (첫 접수 계열 진입 때 한 번)
#    HN/HC/HT(보류)                          → 13 보류
#    TN/FN/TC/FC/TT(진료 완료 = 수납 대기)   → 7 수납대기       (카드는 그대로, 뒤늦게 만들면 3층 수납에서 시작)
#    PN/PC/PT(수납 완료)                     → 8 수납완료       (동선관리가 카드를 3층 수납 경유로 내보냄)
#    수납 완료 뒤 다시 접수/진료 완료 계열   → 10 수납취소      (동선관리가 완료 목록에서 카드 복귀)
#    CN(접수 취소)                            → 3 접수취소       cancelled=true (동선관리가 6초 뒤 손대지 않은 카드 제거)
#    WR/NR/HR/TR/FR/PR/CR(예약만, 미도착)·O*/V*(입원) → 보내지 않음
#
#  실행:  powershell -ExecutionPolicy Bypass -File bit_db_agent.ps1 -DryRun          (전송 없이 로그만 — 처음엔 이걸로)
#         powershell -ExecutionPolicy Bypass -File bit_db_agent.ps1                  (실전)
#  비밀번호 파일(같은 폴더): bit_db_agent.sql.secret = dongseon_ro 비밀번호,  bit_db_agent.secret = 동선관리 bitbot 비밀번호(DryRun 이면 불필요)
#  상태 파일: %LOCALAPPDATA%\bit_db_agent\state.json — 오늘 이미 보낸 접수번호(재시작 때 중복 전송 방지). 로그: 같은 폴더 agent.log
# ─────────────────────────────────────────────────────────────
param(
  [string]$Pc = 'DB',                       # 동선관리 pill 에 표시될 이름
  [string]$SqlServer = '192.168.0.250',
  [string]$Database = 'drbitpack',
  [string]$SqlUser = 'dongseon_ro',
  [int]$PollSec = 4,                        # DB 조회 주기(초)
  [int]$HeartbeatSec = 300,                 # 하트비트 주기(초) — 동선관리 BIT_STALE_SEC=750 과 짝
  [int]$LeadMin = 5,                        # 접수 시각이 지금보다 이만큼 뒤면 아직 보내지 않음(사전 등록분)
  [switch]$DryRun,                          # Firestore 에 쓰지 않고 로그만
  [switch]$SendExistingOnStart,             # 시작 시 오늘 접수분을 전부 보냄(기본: 스냅샷만 찍고 보내지 않음)
  [int]$Cycles = 0,                         # 0 = 무한, N = N번 조회 뒤 종료(시험용)
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'bit_db_agent')
)
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$VER = 'db1.0'
# ── 동선관리 Firebase (공개 웹 키 — 비밀 아님. 비밀번호는 .secret 파일) ──
$ApiKey    = 'AIzaSyDBj3z-Qj9DyT1ZgDNps1-Yp9ZBopeWr0w'
$ProjectId = 'bonafide-dongseon-108e2'
$BotEmail  = 'uc8feac453b1a01cc028b072a@bonafide.app'   # 동선관리 계정 'bitbot'의 내부 이메일

New-Item -ItemType Directory -Force $StateDir | Out-Null
$LogFile = Join-Path $StateDir 'agent.log'; $StateFile = Join-Path $StateDir 'state.json'
$script:StartedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz'); $script:LastErr = ''; $script:LastErrAt = ''; $script:CycMax = 0
function Log($m) { $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"; Write-Host $line; try { Add-Content $LogFile $line -Encoding UTF8 } catch {}
  if ($m -match '오류|실패') { $script:LastErr = $m; $script:LastErrAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') } }
function LogTail($n = 5) { try { return ((Get-Content $LogFile -Tail $n -Encoding UTF8 -ErrorAction Stop) -join "`n") } catch { return '' } }
function TrimLog() { try { if ((Get-Item $LogFile -ErrorAction SilentlyContinue).Length -gt 2MB) { Get-Content $LogFile -Tail 2000 | Set-Content $LogFile -Encoding UTF8 } } catch {} }
function NowIso() { return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }
function Today { return (Get-Date).ToString('yyyy-MM-dd') }

# ── 비밀번호 ──
$SqlSecretFile = Join-Path $PSScriptRoot 'bit_db_agent.sql.secret'
if (-not (Test-Path $SqlSecretFile) -and (Test-Path (Join-Path $HOME '.bit_db.secret'))) { $SqlSecretFile = Join-Path $HOME '.bit_db.secret' }
if (-not (Test-Path $SqlSecretFile)) { Log "SQL 비밀번호 파일이 없습니다: $SqlSecretFile (첫 줄에 $SqlUser 비밀번호)"; exit 1 }
$SqlPassword = (Get-Content $SqlSecretFile -Encoding UTF8 -TotalCount 1).Trim()
$BotPassword = ''
if (-not $DryRun) {
  $SecretFile = Join-Path $PSScriptRoot 'bit_db_agent.secret'
  if (-not (Test-Path $SecretFile)) { Log "bitbot 비밀번호 파일이 없습니다: $SecretFile (첫 줄에 bitbot 비밀번호). 전송 없이 시험하려면 -DryRun"; exit 1 }
  $BotPassword = (Get-Content $SecretFile -Encoding UTF8 -TotalCount 1).Trim()
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ── Firebase 로그인 / Firestore REST (bitplus_watcher.ps1 과 동일) ──
$script:Tok = $null; $script:TokExp = [DateTime]::MinValue; $script:Refresh = $null
$TokenFile = Join-Path $PSScriptRoot 'bit_db_agent.token'
function SaveRefresh($rt) { try { if ($rt) { [IO.File]::WriteAllText($TokenFile, $rt, (New-Object Text.UTF8Encoding $false)); icacls $TokenFile /inheritance:r /grant:r "$($env:USERNAME):M" | Out-Null } } catch {} }
if (Test-Path $TokenFile) { try { $script:Refresh = (Get-Content $TokenFile -TotalCount 1 -ErrorAction Stop).Trim() } catch { $script:Refresh = $null } }
$script:LoginFailAt = [DateTime]::MinValue; $script:LoginBackoff = 60
function FbLogin() {
  if (((Get-Date) - $script:LoginFailAt).TotalSeconds -lt $script:LoginBackoff) { throw "Firebase 로그인 대기 중(최근 실패, $([int]($script:LoginBackoff - ((Get-Date) - $script:LoginFailAt).TotalSeconds))초 후 재시도)" }
  $body = @{ email = $BotEmail; password = $BotPassword; returnSecureToken = $true } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -TimeoutSec 20 -Method Post -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$ApiKey" -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  } catch {
    $script:LoginFailAt = Get-Date
    $code = ''; try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $code = ((($sr.ReadToEnd() | ConvertFrom-Json).error.message) -split ' ')[0] } catch {}
    $script:LoginBackoff = 60
    $hint = switch -Wildcard ($code) {
      'INVALID_LOGIN_CREDENTIALS' { $script:LoginBackoff = 300; "bitbot 비밀번호가 틀림 → bit_db_agent.secret 확인 (5분마다 재시도)" }
      'INVALID_PASSWORD'          { $script:LoginBackoff = 300; "bitbot 비밀번호가 틀림 → bit_db_agent.secret 확인 (5분마다 재시도)" }
      'TOO_MANY_ATTEMPTS*'        { $script:LoginBackoff = 600; "실패가 잦아 Firebase 가 이 병원 IP를 잠시 차단함 → 10분 뒤 자동 재시도" }
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
function FsFields($h) {
  $f = @{}
  foreach ($k in $h.Keys) { $v = $h[$k]
    if ($v -is [bool]) { $f[$k] = @{ booleanValue = $v } }
    elseif ($v -is [int] -or $v -is [long]) { $f[$k] = @{ integerValue = [string]$v } }
    else { $f[$k] = @{ stringValue = [string]$v } } }
  return $f
}
function FsPatch($path, $fields) {   # 지정한 필드만 갱신(merge). 없는 문서는 생성
  $mask = ($fields.Keys | ForEach-Object { 'updateMask.fieldPaths=' + [Uri]::EscapeDataString($_) }) -join '&'
  $body = @{ fields = (FsFields $fields) } | ConvertTo-Json -Depth 6 -Compress
  $null = Invoke-RestMethod -TimeoutSec 20 -Method Patch -Uri "$DocBase/$path`?$mask" -Headers @{ Authorization = "Bearer $(FbToken)" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
}
function FsPatchNested($path, $key, $fields) {   # bitStatus/_all 의 'PC이름' 맵 필드만 갱신
  $mask = 'updateMask.fieldPaths=' + [Uri]::EscapeDataString('`' + $key + '`')
  $body = @{ fields = @{ $key = @{ mapValue = @{ fields = (FsFields $fields) } } } } | ConvertTo-Json -Depth 8 -Compress
  $null = Invoke-RestMethod -TimeoutSec 20 -Method Patch -Uri "$DocBase/$path`?$mask" -Headers @{ Authorization = "Bearer $(FbToken)" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
}

# ── SQL (읽기 전용) ──
function AssertReadonlySql($sql) {
  $u = $sql.ToUpperInvariant().Trim()
  if (-not $u.StartsWith('SELECT')) { throw "읽기 전용 검사 실패: SELECT 로 시작하지 않음" }
  if ($sql.Contains(';')) { throw "읽기 전용 검사 실패: 문장 구분자(;)" }
  if ($u -match '\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|EXEC|EXECUTE|GRANT|REVOKE|INTO|BULK|OPENROWSET|XP_\w+|SP_\w+)\b') { throw "읽기 전용 검사 실패: 금지 단어 $($Matches[1])" }
}
function SqlRows($sql) {   # 폴링마다 열고 닫음(연결 유지 안 함). NOLOCK + READ UNCOMMITTED + LOCK_TIMEOUT 3초 → 비트 작업을 기다리게 하지 않음
  AssertReadonlySql $sql
  $cn = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$Database;User ID=$SqlUser;Password=$SqlPassword;Connect Timeout=8;ApplicationIntent=ReadOnly")
  try {
    $cn.Open(); $c = $cn.CreateCommand(); $c.CommandTimeout = 10
    $c.CommandText = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SET LOCK_TIMEOUT 3000"; [void]$c.ExecuteNonQuery()
    $c.CommandText = $sql; $r = $c.ExecuteReader(); $t = New-Object Data.DataTable; $t.Load($r); $r.Close(); return ,$t
  } finally { $cn.Close() }
}
# 오늘 접수분 전체(하루 수십~수백 행). OcmNum 은 char(10) 앞 공백 패딩 → 숫자만 남김. 예약 환자는 예약 시점에 이미 행이 있고(WR) 도착하면 같은 행이 WN 으로 바뀌며 OcmAcpDtm 이 실제 도착 시각으로 갱신된다.
$QUERY = @"
SELECT RTRIM(o.OcmNum) AS k, RTRIM(o.OcmComStt) AS stt, RTRIM(p.PbsPatNam) AS name, RTRIM(o.OcmChtNum) AS mrn,
       RTRIM(p.PbsResNum) AS rrn, RTRIM(p.PbsBirDte) AS bir, RTRIM(p.PbsSexTyp) AS sex, RTRIM(p.PbsNewDte) AS newdte,
       RTRIM(o.OcmAcpDtm) AS recv, RTRIM(u.UidNam) AS dr, RTRIM(o.OcmDepCod) AS dep, RTRIM(r.RsvDtm) AS rsvdtm
FROM OcmInf o WITH (NOLOCK)
LEFT JOIN PbsInf p WITH (NOLOCK) ON p.PbsChtNum = o.OcmChtNum
LEFT JOIN UidMst u WITH (NOLOCK) ON u.UidCod = o.OcmDtrCod
LEFT JOIN RsvInf r WITH (NOLOCK) ON r.RsvOcmNum = o.OcmNum
WHERE LEFT(o.OcmAcpDtm, 8) = '{0}'
ORDER BY o.OcmAcpDtm, o.OcmNum
"@

# ── 상태 코드 분류 (DtlMst COMSTT, 2026-09-16 실측 36개) ──
$ACTIVE   = @('WN','NN','WC','WT','SN','SC','ST','HN','HC','HT','TN','FN','TC','FC','TT','PN','PC','PT')   # 접수 계열(원내에 왔거나 왔다 간 환자)
$RETAIN   = @('HN','HC','HT')                       # 보류
$DONEWAIT = @('TN','FN','TC','FC','TT')             # 진료 완료 = 수납 대기
$PAID     = @('PN','PC','PT')                       # 수납 완료
$CANCEL   = @('CN')
$CMD_NAMES = @{ 2 = '접수'; 3 = '접수취소'; 7 = '수납대기'; 8 = '수납완료'; 10 = '수납취소'; 13 = '보류' }
function CmdOf($stt, $prev) {
  if ($PAID -contains $stt) { return 8 }
  if ($prev -and ($PAID -contains $prev) -and ($ACTIVE -contains $stt)) { return 10 }   # 수납 완료였다가 되돌아감 = 수납취소
  if ($DONEWAIT -contains $stt) { return 7 }
  if ($RETAIN -contains $stt) { return 13 }
  return 2
}
function Rrn7($rrn, $bir, $sex) {   # 주민번호 13자리 → 'YYMMDD-S' (앞 7자리만). 없으면 생년월일+성별로 만든다. 뒷자리는 절대 만들지 않음
  $s = [string]$rrn -replace '\D', ''
  if ($s.Length -ge 7) { return $s.Substring(0, 6) + '-' + $s.Substring(6, 1) }
  $b = [string]$bir -replace '\D', ''
  if ($b.Length -eq 8) {
    $sx = ([string]$sex).Trim().ToUpperInvariant(); $m = ($sx -in 'M','1','3','남'); $f = ($sx -in 'F','2','4','여')
    if ($m -or $f) { $d = if ($b.Substring(0, 2) -eq '19') { if ($m) { '1' } else { '2' } } else { if ($m) { '3' } else { '4' } }; return $b.Substring(2, 6) + '-' + $d }
  }
  return ''
}
function HourMinOf($dtm) { $s = [string]$dtm; if ($s.Length -ge 12) { return [int]$s.Substring(8, 2) * 60 + [int]$s.Substring(10, 2) }; return -1 }
function DtmOf($dtm) { $s = [string]$dtm; if ($s.Length -ge 12) { return $s.Substring(0, 4) + '-' + $s.Substring(4, 2) + '-' + $s.Substring(6, 2) + ' ' + $s.Substring(8, 2) + ':' + $s.Substring(10, 2) }; return '' }
function DateOf($d) { $s = [string]$d; if ($s.Length -ge 8) { return $s.Substring(0, 4) + '-' + $s.Substring(4, 2) + '-' + $s.Substring(6, 2) }; return '' }

# ── 상태 파일: { date, seen: {접수번호: 상태}, sent: {접수번호: 마지막 command} } ──
function LoadState() {
  try { if (Test-Path $StateFile) { $j = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($j.date -eq (Today)) { $seen = @{}; $sent = @{}
        foreach ($p in $j.seen.PSObject.Properties) { $seen[$p.Name] = [string]$p.Value }
        foreach ($p in $j.sent.PSObject.Properties) { $sent[$p.Name] = [int]$p.Value }
        return @{ date = $j.date; seen = $seen; sent = $sent; fresh = $false } } } } catch { Log "상태 파일 읽기 오류(새로 시작): $($_.Exception.Message)" }
  return @{ date = (Today); seen = @{}; sent = @{}; fresh = $true }
}
function SaveState($st) { try { @{ date = $st.date; seen = $st.seen; sent = $st.sent } | ConvertTo-Json -Compress -Depth 4 | Set-Content $StateFile -Encoding UTF8 } catch { Log "상태 파일 저장 오류: $($_.Exception.Message)" } }

function Send($docId, $fields, $what) {
  if ($DryRun) { Log "DRY 전송: $docId $what"; return }
  FsPatch "bitIntake/$docId" $fields
  Log "전송: $docId $what"
}

# ── 한 번의 폴링: 오늘 행 전체를 읽고 decide ──
function Poll($st, $first) {
  $today8 = (Get-Date).ToString('yyyyMMdd')
  $rows = SqlRows ($QUERY -f $today8)
  $now = Get-Date; $nowMin = $now.Hour * 60 + $now.Minute
  $done = @{}; $n = 0
  foreach ($r in $rows.Rows) {
    $k = ([string]$r.k -replace '\D', ''); if (-not $k -or $done.ContainsKey($k)) { continue }; $done[$k] = 1; $n++   # OcmNum 은 char(10) 앞 공백 패딩('    182357') → 숫자만. 캐스트 채널(bitplus_watcher)과 같은 문서 id 가 된다. RsvInf 조인으로 같은 접수가 두 줄이면 첫 줄만
    $stt = [string]$r.stt; $prev = $st.seen[$k]
    $isActive = ($ACTIVE -contains $stt)
    if ($first -and -not $SendExistingOnStart) {   # 시작 스냅샷: 이미 접수된 건은 보낸 것으로 간주(재시작 때 오늘 접수분을 다시 올리지 않기 위해)
      if ($isActive) { $st.sent[$k] = (CmdOf $stt $null) }
      $st.seen[$k] = $stt; continue
    }
    $mrn = ([string]$r.mrn -replace '\D', ''); if (-not $mrn) { $mrn = ([string]$r.mrn).Trim() }
    $name = ([string]$r.name).Trim()
    $hm = HourMinOf $r.recv
    $tag = "(이름 $($name.Length)자, 차트번호 $(if ($mrn) { '있음' } else { '없음' }), $stt$(if ($prev -and $prev -ne $stt) { " ← $prev" }), 접수 $([Math]::Floor($hm / 60)):$('{0:00}' -f ($hm % 60)))"
    $base = @{ pc = $Pc; src = 'db'; date = (Today); ocmNum = $k; stt = $stt; lastSeenAt = (NowIso) }
    if ($isActive) {
      if (-not $st.sent.ContainsKey($k)) {
        if ($hm -gt $nowMin + $LeadMin) { if ($prev -ne $stt) { Log "보류(사전 등록, 접수 시각이 미래): ocm$k $tag" }; $st.seen[$k] = $stt; continue }   # 그 시각이 되면 보냄
        $cmd = CmdOf $stt $null
        $f = $base + @{ name = $name; mrn = $mrn; rrn7 = (Rrn7 $r.rrn $r.bir $r.sex); doctor = ([string]$r.dr).Trim(); dep = ([string]$r.dep).Trim(); hourMin = $hm
                        command = [int]$cmd; commandName = $CMD_NAMES[$cmd]; registered = $true; registeredAt = (NowIso); cancelled = $false; seenAt = (NowIso) }
        $fv = DateOf $r.newdte; if ($fv) { $f.firstVisit = $fv }
        $rv = DtmOf $r.rsvdtm; if ($rv -and $rv.StartsWith((Today))) { $f.nextResv = $rv }
        if ($f.rrn7 -eq '') { $f.Remove('rrn7') }
        try { Send "$(Today)_ocm$k" $f "$($CMD_NAMES[$cmd]) $tag"; $st.sent[$k] = $cmd } catch { Log "전송 오류 ocm${k}: $($_.Exception.Message)" }
      }
      elseif ($prev -ne $stt) {   # 이미 보낸 접수의 상태 변화: 수납대기/수납완료/수납취소/보류/취소 후 재접수
        $cmd = CmdOf $stt $prev
        if ($cmd -ne $st.sent[$k] -or ($CANCEL -contains $prev)) {
          $f = $base + @{ command = [int]$cmd; commandName = $CMD_NAMES[$cmd]; event = $CMD_NAMES[$cmd]; eventAt = (NowIso); cancelled = $false }
          if ($CANCEL -contains $prev) { $f.registered = $true; $f.registeredAt = (NowIso); $f.seenAt = (NowIso) }   # 취소 뒤 재접수 → 동선관리가 다시 자동 생성
          try { Send "$(Today)_ocm$k" $f "$($CMD_NAMES[$cmd]) $tag"; $st.sent[$k] = $cmd } catch { Log "전송 오류 ocm${k}: $($_.Exception.Message)" }
        }
      }
    }
    elseif (($CANCEL -contains $stt) -and $st.sent.ContainsKey($k) -and $prev -ne $stt) {
      $f = $base + @{ command = 3; commandName = '접수취소'; cancelled = $true; cancelledAt = (NowIso) }
      try { Send "$(Today)_ocm$k" $f "접수취소 $tag"; $st.sent[$k] = 3 } catch { Log "전송 오류 ocm${k}: $($_.Exception.Message)" }
    }
    $st.seen[$k] = $stt
  }
  return $n
}

# ── 하트비트 (bitStatus/_all 의 $Pc 필드) — bitOpen = DB 연결 정상 ──
function Heartbeat($sqlOk) {
  $ips = @(); try { $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' } | ForEach-Object { $_.IPAddress }) } catch {}
  $hb = @{ pc = $Pc; lastSeen = (NowIso); bitOpen = [bool]$sqlOk; doctorOpen = $false; cast = $false; ip = ($ips -join ','); ver = $VER; startedAt = $script:StartedAt
           uptimeSec = [int]((Get-Date) - [DateTime]::Parse($script:StartedAt)).TotalSeconds; procId = [int]$PID; lastErr = $script:LastErr; lastErrAt = $script:LastErrAt
           cycMaxMs = [int]$script:CycMax; logTail = (LogTail 5); src = 'db'; sqlServer = $SqlServer }
  if ($DryRun) { Log "DRY 하트비트: sqlOk=$sqlOk"; return }
  FsPatchNested "bitStatus/_all" $Pc $hb
}

# ── 메인 ──
Log "비트 DB 감시 $VER 시작: PC=$Pc  SQL=$SqlServer/$Database ($SqlUser)  주기 ${PollSec}s  $(if ($DryRun) { '[DRY RUN — 전송 없음]' })$(if ($SendExistingOnStart) { '[시작 시 기존 접수 전송]' })"
AssertReadonlySql ($QUERY -f '20000101'); Log "SQL 읽기 전용 검사 통과"
if (-not $DryRun) { try { $null = FbToken } catch { Log $_.Exception.Message } }
$st = LoadState; $first = $st.fresh
if (-not $first) { Log "상태 파일 복원: 오늘 본 접수 $($st.seen.Count)건, 보낸 접수 $($st.sent.Count)건 (스냅샷 없이 이어감)" }
$lastBeat = [DateTime]::MinValue; $sqlOk = $null; $cyc = 0
while ($true) {
  $cycStart = Get-Date
  if ($st.date -ne (Today)) { Log "날짜 변경 → 상태 초기화"; $st = @{ date = (Today); seen = @{}; sent = @{}; fresh = $true }; $first = $true; TrimLog }
  try {
    $n = Poll $st $first
    if ($first) { Log "시작 스냅샷: 오늘 행 $n 건, 접수 계열 $($st.sent.Count)건$(if ($SendExistingOnStart) { ' 전송' } else { ' (보내지 않음)' })"; $first = $false }
    SaveState $st
    if ($sqlOk -ne $true) { if ($sqlOk -eq $false) { Log "DB 연결 회복" }; $sqlOk = $true; $lastBeat = [DateTime]::MinValue }
  } catch {
    if ($sqlOk -ne $false) { Log "DB 조회 오류: $($_.Exception.Message)"; $sqlOk = $false; $lastBeat = [DateTime]::MinValue }
  }
  if (((Get-Date) - $lastBeat).TotalSeconds -ge $HeartbeatSec) {
    try { Heartbeat $sqlOk; $lastBeat = Get-Date; $script:CycMax = 0 } catch { Log "하트비트 실패: $($_.Exception.Message)"; $lastBeat = Get-Date }
  }
  $ms = [int]((Get-Date) - $cycStart).TotalMilliseconds; if ($ms -gt $script:CycMax) { $script:CycMax = $ms }
  $cyc++; if ($Cycles -gt 0 -and $cyc -ge $Cycles) { Log "시험 종료 ($Cycles 회)"; break }
  Start-Sleep -Milliseconds ([Math]::Max(500, $PollSec * 1000 - $ms))
}
