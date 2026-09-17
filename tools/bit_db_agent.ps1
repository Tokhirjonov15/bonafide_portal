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
#    PN/PC/PT(수납 완료)                     → 8 수납완료       (동선관리가 카드를 3층 수납으로 옮기고 '비트 수납완료' 초록 표시 — 내보내기는 직원이 확인)
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
  [int]$RecentMin = 30,                     # 시작 스냅샷이라도 이 시간 안에 접수된 환자는 보낸다(아침에 PC 가 켜지기 전 접수된 환자가 빠지지 않도록, 2026-09-17). 0 = 끔
  [int]$ResvDays = 7,                       # 진료 예약(RsvInf)을 오늘부터 며칠치 올릴지 → bitResv/{날짜}. 0 = 예약 연동 끔
  [int]$ResvEvery = 2,                      # 예약은 몇 주기마다 읽을지(2 = 8초). 바뀐 날짜의 문서만 다시 쓴다
  [switch]$ResvAlways,                      # 대기(standby)여도 예약 문서는 쓴다 — 담당 PC 의 에이전트가 예약 기능이 없는 옛 버전인 동안 임시로(관리 PC 용)
  [switch]$DryRun,                          # Firestore 에 쓰지 않고 로그만
  [switch]$SendExistingOnStart,             # 시작 시 오늘 접수분을 전부 보냄(기본: 스냅샷만 찍고 보내지 않음)
  [int]$Cycles = 0,                         # 0 = 무한, N = N번 조회 뒤 종료(시험용)
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'bit_db_agent'),
  [int]$Priority = 1,                       # 여러 PC 에서 함께 돌 때 우선순위(큰 수가 우선). 가장 높은 '정상' 에이전트만 Firestore 에 쓰고 나머지는 대기(상태만 따라감)
  [int]$HealthPort = 9001,                  # 감시 스크립트·다른 에이전트가 "살아 있나"를 묻는 TCP 포트(LAN 전용, Firestore 비용 없음). 0 = 끔
  [string]$PeersFile = (Join-Path $PSScriptRoot 'bitplus_peers.txt'),   # 다른 에이전트 PC IP 목록(한 줄에 하나, # 뒤는 주석). 없으면 단독 운영
  [int]$PeerPort = 0                        # 동료 에이전트의 상태 포트(0 = HealthPort 와 같음). 한 PC 에서 두 인스턴스로 시험할 때만 다르게
)
if ($PeerPort -le 0) { $PeerPort = $HealthPort }
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
# 로그는 큐에 넣고 파일에 몰아서 쓴다: 다른 프로그램(tail -f 등)이 로그 파일을 잡고 있어 쓰기가 실패하면 줄을 버리지 않고 다음에 다시 쓴다 (2026-09-16 실제로 30분간 로그가 비었던 사고)
$script:LogQ = New-Object System.Collections.Generic.List[string]
function Log($m) { $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"; Write-Host $line
  $script:LogQ.Add($line); if ($script:LogQ.Count -gt 500) { $script:LogQ.RemoveRange(0, $script:LogQ.Count - 500) }
  try { $fs = [IO.File]::Open($LogFile, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite); $sw = New-Object IO.StreamWriter($fs, (New-Object Text.UTF8Encoding $false))
        foreach ($l in $script:LogQ) { $sw.WriteLine($l) }; $sw.Close(); $script:LogQ.Clear() } catch {}
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
  if (-not (Test-Path $SecretFile) -and (Test-Path (Join-Path $PSScriptRoot 'bitplus_watcher.secret'))) { $SecretFile = Join-Path $PSScriptRoot 'bitplus_watcher.secret' }   # 감시 스크립트와 같은 폴더(C:\bitplus)면 그 bitbot 비밀번호를 같이 쓴다
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
function FsVal($v) {   # PowerShell 값 → Firestore 값 (문자열/불리언/정수/배열/맵 — 예약 문서의 items 배열용)
  if ($null -eq $v) { return @{ nullValue = $null } }
  if ($v -is [bool]) { return @{ booleanValue = $v } }
  if ($v -is [int] -or $v -is [long]) { return @{ integerValue = [string]$v } }
  if ($v -is [System.Collections.IDictionary]) { $m = @{}; foreach ($k in $v.Keys) { $m[[string]$k] = FsVal $v[$k] }; return @{ mapValue = @{ fields = $m } } }
  if (($v -is [System.Collections.IEnumerable]) -and -not ($v -is [string])) { return @{ arrayValue = @{ values = @(foreach ($x in $v) { FsVal $x }) } } }
  return @{ stringValue = [string]$v }
}
function FsFields($h) { $f = @{}; foreach ($k in $h.Keys) { $f[$k] = FsVal $h[$k] }; return $f }
function FsPatch($path, $fields) {   # 지정한 필드만 갱신(merge). 없는 문서는 생성. 배열 필드는 통째로 바뀐다
  $mask = ($fields.Keys | ForEach-Object { 'updateMask.fieldPaths=' + [Uri]::EscapeDataString($_) }) -join '&'
  $body = @{ fields = (FsFields $fields) } | ConvertTo-Json -Depth 14 -Compress
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
       RTRIM(o.OcmAcpDtm) AS recv, RTRIM(u.UidNam) AS dr, RTRIM(o.OcmDepCod) AS dep, RTRIM(r.RsvDtm) AS rsvdtm,
       RTRIM(o.OcmRefCmt) AS memo1, RTRIM(p.PbsRefCmt) AS memo2, CAST(m.PbsSpcCmt AS nvarchar(max)) AS memo3, o.OcmInsCod AS ins, o.OcmInsSeq AS insseq,
       COALESCE(NULLIF(RTRIM(p.PbsCelPhn),''), RTRIM(p.PbsPhnNum)) AS tel
FROM OcmInf o WITH (NOLOCK)
LEFT JOIN PbsInf p WITH (NOLOCK) ON p.PbsChtNum = o.OcmChtNum
LEFT JOIN UidMst u WITH (NOLOCK) ON u.UidCod = o.OcmDtrCod
LEFT JOIN RsvInf r WITH (NOLOCK) ON r.RsvOcmNum = o.OcmNum
LEFT JOIN PbsCmtInf m WITH (NOLOCK) ON m.PbsChtNum = o.OcmChtNum
WHERE LEFT(o.OcmAcpDtm, 8) = '{0}'
ORDER BY o.OcmAcpDtm, o.OcmNum
"@

# ── 상태 코드 분류 (DtlMst COMSTT, 2026-09-16 실측 36개) ──
$ACTIVE   = @('WN','NN','WC','WT','SN','SC','ST','HN','HC','HT','WH','TN','FN','TC','FC','TT','PN','PC','PT')   # 접수 계열(원내에 왔거나 왔다 간 환자)
$RETAIN   = @('HN','HC','HT','WH')                  # 보류 (WH 는 COMSTT 표에 없지만 2026-09-16 실데이터에 나옴 — 접수 보류로 취급)
$SKIP     = @('WR','NR','HR','TR','FR','PR','CR','SR')   # 예약만(미도착)·예약 취소 — 보내지 않음. O*/V* 입원도 보내지 않음
$script:UnknownStt = @{}
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
# 메모·보험 (2026-09-17): 접수메모(당일)=OcmInf.OcmRefCmt, 접수메모(연속)=PbsInf.PbsRefCmt, 특이사항=PbsCmtInf.PbsSpcCmt — 감시 스크립트가 접수 창 인적정보에서 읽던 것과 같은 항목.
# 비트의 빈 칸 표시('-', '.', '+')는 메모가 아니다. OcmBilCmt 는 의사 처방 메모라 보내지 않는다.
function CleanMemo($t) { $s = ([string]$t).Trim(); if ($s -match '^[\s+\-_.·ㆍ,~*]*$') { return '' }; return $s }
$INS_NAME = @{ 11 = '일반'; 21 = '자보-청구분'; 31 = '국민건강보험'; 38 = '공상'; 41 = '산재-공단분'; 51 = '보호1종'; 52 = '보호2종'; 54 = '행여' }   # DtlMst INSINF 코드 → 동선관리 보험 선택지(f_ins) 이름
function InsName($cod) { $n = 0; if ([int]::TryParse([string]$cod, [ref]$n) -and $INS_NAME.ContainsKey($n)) { return $INS_NAME[$n] }; return '' }
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
  if (-not $script:IsLeader) { Log "대기 중 — 생략(전송 담당: $($script:LeaderInfo)): $docId $what"; return }   # 상태는 보낸 것으로 기록 → 담당이 되는 순간부터 새 변화만 보낸다
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
    if (-not $isActive -and -not ($CANCEL -contains $stt) -and -not ($SKIP -contains $stt) -and $stt -notmatch '^[OV]' -and -not $script:UnknownStt.ContainsKey($stt)) {
      $script:UnknownStt[$stt] = 1; Log "알 수 없는 상태 코드 '$stt' (ocm$k) — 보내지 않음. 필요하면 `$ACTIVE/`$SKIP 에 추가"   # 한 코드당 한 번만
    }
    if ($first -and -not $SendExistingOnStart) {   # 시작 스냅샷: 이미 접수된 건은 보낸 것으로 간주(재시작 때 오늘 접수분을 다시 올리지 않기 위해)
      # 예외: 최근 $RecentMin 분 안에 접수됐고 아직 수납 전이면 보낸다 — 아침에 에이전트가 켜지기 전 접수된 환자가 빠지지 않도록. 같은 문서 id 로 merge 되므로 이미 카드가 있으면 동선관리가 무시한다
      $hm0 = HourMinOf $r.recv
      $recent = ($RecentMin -gt 0 -and $isActive -and $hm0 -ge 0 -and ($nowMin - $hm0) -ge (-$LeadMin) -and ($nowMin - $hm0) -le $RecentMin -and -not ($PAID -contains $stt))
      if (-not $recent) { if ($isActive) { $st.sent[$k] = (CmdOf $stt $null) }; $st.seen[$k] = $stt; continue }
      $script:SnapRecent++
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
        $m1 = CleanMemo $r.memo1; if ($m1) { $f.memoToday = $m1 }; $m2 = CleanMemo $r.memo2; if ($m2) { $f.memoCont = $m2 }; $m3 = CleanMemo $r.memo3; if ($m3) { $f.memoRx = $m3 }
        $insN = InsName $r.ins; if ($insN) { $f.ins = $insN }
        $tel = (([string]$r.tel) -replace '\D', ''); if ($tel.Length -ge 9) { $f.tel = $tel }   # 휴대폰(없으면 전화) 숫자만 — 카드의 전화 칸(문자 발송용). 2026-09-17 사용자 결정으로 추가
        $fv = DateOf $r.newdte; if ($fv) { $f.firstVisit = $fv }
        $rv = DtmOf $r.rsvdtm; if ($rv -and $rv.StartsWith((Today))) { $f.nextResv = $rv }
        if ($f.rrn7 -eq '') { $f.Remove('rrn7') }
        try { Send "$(Today)_ocm$k" $f "$($CMD_NAMES[$cmd]) $tag"; $st.sent[$k] = $cmd } catch { Log "전송 오류 ocm${k}: $($_.Exception.Message)" }
      }
      elseif ($prev -ne $stt) {   # 이미 보낸 접수의 상태 변화: 수납대기/수납완료/수납취소/보류/취소 후 재접수
        $cmd = CmdOf $stt $prev
        if ($cmd -ne $st.sent[$k] -or ($CANCEL -contains $prev)) {
          $f = $base + @{ command = [int]$cmd; commandName = $CMD_NAMES[$cmd]; event = $CMD_NAMES[$cmd]; eventAt = (NowIso); cancelled = $false }
          $m1 = CleanMemo $r.memo1; if ($m1) { $f.memoToday = $m1 }; $m2 = CleanMemo $r.memo2; if ($m2) { $f.memoCont = $m2 }; $m3 = CleanMemo $r.memo3; if ($m3) { $f.memoRx = $m3 }   # 접수 뒤에 적힌 메모도 상태가 바뀔 때 따라간다
          $insN = InsName $r.ins; if ($insN) { $f.ins = $insN }
          $tel = (([string]$r.tel) -replace '\D', ''); if ($tel.Length -ge 9) { $f.tel = $tel }
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
           cycMaxMs = [int]$script:CycMax; logTail = (LogTail 5); src = 'db'; sqlServer = $SqlServer
           priority = [int]$Priority; leader = [bool]$script:IsLeader; leaderInfo = [string]$script:LeaderInfo; peers = ($Peers -join ',') }
  if ($DryRun) { Log "DRY 하트비트: sqlOk=$sqlOk"; return }
  FsPatchNested "bitStatus/_all" $Pc $hb
}

# ── 상태 포트 / 다른 에이전트와의 우선순위 (LAN 만 사용, Firestore 비용 없음) ──
#  · 이 에이전트는 TCP $HealthPort 에 "OK <우선순위> <PC> <leader|standby>" 한 줄로 답한다 — 단, 최근 30초 안에 DB 를 성공적으로 읽었을 때만. 아니면 "DOWN".
#  · 감시 스크립트(bitplus_watcher.ps1)는 캐스트가 오면 이 포트에 물어 보고, 정상인 에이전트가 있으면 bitIntake 에 쓰지 않는다.
#  · 여러 PC 에 에이전트가 있으면(bitplus_peers.txt) 매 주기 서로 물어 보고, 우선순위가 가장 높은 정상 에이전트만 전송한다. 그 PC 가 꺼지면 4~8초 안에 다음 순위가 이어받는다.
$script:LastDbOk = [DateTime]::MinValue; $script:IsLeader = $true; $script:LeaderInfo = ''; $script:SnapRecent = 0
$MyIps = @(); try { $MyIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress }) } catch {}
$Peers = @()
if (Test-Path $PeersFile) { $Peers = @(Get-Content $PeersFile -Encoding UTF8 | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and ($PeerPort -ne $HealthPort -or (($MyIps -notcontains $_) -and $_ -ne '127.0.0.1')) } | Select-Object -Unique) }   # 자기 자신은 뺀다(시험용 PeerPort 가 다르면 포함)
function DbHealthy() { return (((Get-Date) - $script:LastDbOk).TotalSeconds -lt 30) }
$health = $null
if ($HealthPort -gt 0) {
  try { $health = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Any), $HealthPort; $health.Start() }
  catch { Log "TCP $HealthPort 열기 실패(다른 프로그램이 사용 중?): $($_.Exception.Message) — 다른 PC 가 이 에이전트를 확인할 수 없음"; $health = $null }
}
function HealthDrain() {   # 대기 중인 접속마다 한 줄 답하고 끊는다
  if (-not $health) { return }
  while ($health.Pending()) { $cli = $null
    try { $cli = $health.AcceptTcpClient(); $cli.SendTimeout = 500
      # 5번째 칸: 내가 아는 동료 IP 목록 — 묻는 쪽이 이를 합쳐 목록이 불완전해도(설치 때 -Peers 를 빠뜨려도) 서로를 알게 된다(전송 담당이 둘이 되는 일 방지)
      $line = if (DbHealthy) { "OK $Priority $Pc $(if ($script:IsLeader) { 'leader' } else { 'standby' })" } else { "DOWN $Priority $Pc db" }
      $line += ' ' + ((@($Peers) + @($MyIps | Where-Object { $_ -like '192.168.*' -or $_ -like '10.*' })) -join ',')
      $b = [Text.Encoding]::UTF8.GetBytes($line + "`n"); $cli.GetStream().Write($b, 0, $b.Length) }
    catch {} finally { if ($cli) { try { $cli.Close() } catch {} } } }
}
function ProbePeer($ip) {   # 300ms 안에 연결·응답이 없으면 죽은 것으로 본다. 반환 @{ ok; prio; pc } 또는 $null
  $cli = New-Object System.Net.Sockets.TcpClient
  try { $ar = $cli.BeginConnect($ip, $PeerPort, $null, $null); if (-not $ar.AsyncWaitHandle.WaitOne(300)) { return $null }; $cli.EndConnect($ar)
    $cli.ReceiveTimeout = 500; $line = (New-Object IO.StreamReader($cli.GetStream())).ReadLine(); if (-not $line) { return $null }
    $f = $line -split ' '; $pr = 0; [void][int]::TryParse($f[1], [ref]$pr)
    $known = @(); if ($f.Count -gt 4) { $known = @($f[4] -split ',' | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) }
    return @{ ok = ($f[0] -eq 'OK'); prio = $pr; pc = $(if ($f.Count -gt 2) { $f[2] } else { '' }); known = $known } }
  catch { return $null } finally { try { $cli.Close() } catch {} }
}
function ElectLeader() {   # 나보다 우선순위가 높은(같으면 PC 이름이 앞선) 정상 에이전트가 하나라도 있으면 대기. 동료가 알려 준 IP 는 내 목록에 합친다
  $lead = $true; $who = ''; $learned = @()
  foreach ($ip in @($Peers)) { $p = ProbePeer $ip
    if (-not $p) { continue }
    foreach ($k in $p.known) { if (($Peers -notcontains $k) -and ($MyIps -notcontains $k) -and $k -ne '127.0.0.1' -and ($learned -notcontains $k)) { $learned += $k } }
    if ($p.ok -and ($p.prio -gt $Priority -or ($p.prio -eq $Priority -and [string]::CompareOrdinal($p.pc, $Pc) -lt 0))) { $lead = $false; $who = "$($p.pc)@$ip(우선순위 $($p.prio))" } }
  if ($learned.Count) { $script:Peers = @($Peers) + $learned; Log "동료 목록에 추가(다른 에이전트가 알려 줌): $($learned -join ', ') → $($script:Peers -join ', ')" }
  if ($lead -ne $script:IsLeader) { Log $(if ($lead) { "→ 전송 담당(leader): 더 높은 우선순위의 정상 에이전트 없음" } else { "→ 대기(standby): $who 가 전송 담당" }); if ($lead) { $script:RsvHash = @{} } }   # 담당이 되면 예약 문서를 전부 다시 쓴다
  $script:IsLeader = $lead; $script:LeaderInfo = $who
}
function IdleWait($ms) {   # 다음 주기까지 기다리는 동안에도 상태 포트에는 바로 답한다(감시 스크립트가 300ms 만 기다리므로)
  $end = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $end) { HealthDrain; Start-Sleep -Milliseconds 150 }
}

# ── 진료 예약(RsvInf) → bitResv/{날짜} (2026-09-17) ──
#  접수 PC 가 비트 예약관리에서 예약을 넣거나 시각을 옮기거나 취소하면 RsvInf 가 바로 바뀐다. 오늘~ResvDays 일치를 ResvEvery 주기마다 읽어
#  날짜별 해시가 바뀐 날만 문서를 다시 쓴다(items 배열 통째로). 담당(leader)만 쓴다. bitResv/_summary 에는 날짜별 건수만(동선관리 상단 7일 띠).
#  항목: k(접수번호) t(HH:MM) room(진료실 이름) dr mrn name birth sex div(R/X/Z) sts(OS/OC) ostt(OcmInf 상태: WR 미도착, WN·TN·PN… 도착, CN 취소) acp(도착 HH:MM) memo by naver
$RSV_QUERY = @"
SELECT RTRIM(r.RsvOcmNum) AS k, RTRIM(r.RsvDtm) AS dtm, RTRIM(r.RsvSts) AS sts, RTRIM(r.RsvDivTyp) AS div, RTRIM(r.RsvDepCod) AS dep, RTRIM(r.RsvUidCod) AS uid,
       RTRIM(r.RsvRefCmt) AS memo, COALESCE(NULLIF(RTRIM(r.RsvChtNum),''), RTRIM(o.OcmChtNum)) AS mrn, RTRIM(p.PbsPatNam) AS name, RTRIM(p.PbsBirDte) AS bir, RTRIM(p.PbsSexTyp) AS sex,
       RTRIM(u.UidNam) AS dr, RTRIM(o.OcmComStt) AS ostt, RTRIM(o.OcmAcpDtm) AS acp,
       COALESCE(NULLIF(RTRIM(p.PbsCelPhn),''), RTRIM(p.PbsPhnNum)) AS tel
FROM RsvInf r WITH (NOLOCK)
LEFT JOIN OcmInf o WITH (NOLOCK) ON o.OcmNum = r.RsvOcmNum
LEFT JOIN PbsInf p WITH (NOLOCK) ON p.PbsChtNum = COALESCE(NULLIF(RTRIM(r.RsvChtNum),''), o.OcmChtNum)
LEFT JOIN UidMst u WITH (NOLOCK) ON u.UidCod = r.RsvDtrCod
WHERE LEFT(r.RsvDtm, 8) BETWEEN '{0}' AND '{1}'
ORDER BY r.RsvDtm, r.RsvOcmNum
"@
$script:RsvHash = @{}; $script:DepName = @{}
function LoadDepNames() { try { foreach ($r in (SqlRows "SELECT RTRIM(DepCod) AS c, RTRIM(DepKorNam) AS n FROM DepMst WITH (NOLOCK)").Rows) { $script:DepName[[string]$r.c] = [string]$r.n } } catch { Log "진료과 이름표 읽기 오류: $($_.Exception.Message)" } }
function PollResv() {
  if ($ResvDays -le 0) { return }
  $d0 = (Get-Date).ToString('yyyyMMdd'); $d1 = (Get-Date).AddDays($ResvDays).ToString('yyyyMMdd')
  $rows = SqlRows ($RSV_QUERY -f $d0, $d1)
  $byDay = @{}; for ($i = 0; $i -le $ResvDays; $i++) { $byDay[(Get-Date).AddDays($i).ToString('yyyy-MM-dd')] = New-Object System.Collections.ArrayList }
  foreach ($r in $rows.Rows) {
    $dtm = [string]$r.dtm; if ($dtm.Length -lt 12) { continue }
    $day = $dtm.Substring(0, 4) + '-' + $dtm.Substring(4, 2) + '-' + $dtm.Substring(6, 2); if (-not $byDay.ContainsKey($day)) { continue }
    $memo = ([string]$r.memo).Trim(); $dep = ([string]$r.dep).Trim()
    $mrnRaw = ([string]$r.mrn).Trim(); $mrn = $mrnRaw   # 공백만 떼고 그대로 — 'Res_3457' 같은 가짜 차트에서 숫자만 남기면 실제 환자 번호와 겹친다(2026-09-17)
    $nm = ([string]$r.name).Trim(); $sts = ([string]$r.sts).Trim(); $ostt = ([string]$r.ostt).Trim()
    # 접수 PC 가 시간대를 막을 때 쓰는 가짜 환자 '예약금지'(차트 Res_NNNN): 살아 있는 것만 block 으로 보내고(마감·휴진 표시), 취소된 것은 풀린 자리라 보내지 않는다
    $isBlock = ($nm -eq '예약금지' -or $mrnRaw -like 'Res_*')
    if ($isBlock -and ($sts -eq 'OC' -or $ostt -eq 'CN')) { continue }
    $it = [ordered]@{ k = ([string]$r.k -replace '\D', ''); t = $dtm.Substring(8, 2) + ':' + $dtm.Substring(10, 2); room = $(if ($script:DepName.ContainsKey($dep)) { $script:DepName[$dep] } else { $dep })
                      dr = ([string]$r.dr).Trim(); mrn = $mrn; name = $nm; birth = (DateOf $r.bir); sex = ([string]$r.sex).Trim()
                      div = ([string]$r.div).Trim(); sts = $sts; ostt = $ostt; acp = ''; memo = $memo; by = ([string]$r.uid).Trim()
                      naver = ($memo -match '네이버|naver'); block = [bool]$isBlock; tel = (([string]$r.tel) -replace '\D', '') }
    if ($isBlock) { $it.name = '예약금지'; $it.birth = ''; $it.sex = ''; $it.tel = '' }
    $a = [string]$r.acp; if ($it.ostt -and $it.ostt -ne 'WR' -and $it.ostt -ne 'CN' -and $a.Length -ge 12 -and $a.Substring(0, 8) -eq $dtm.Substring(0, 8)) { $it.acp = $a.Substring(8, 2) + ':' + $a.Substring(10, 2) }
    [void]$byDay[$day].Add($it)
  }
  $changed = @()
  foreach ($day in ($byDay.Keys | Sort-Object)) {
    $h = (($byDay[$day] | ForEach-Object { "$($_.k)|$($_.t)|$($_.room)|$($_.mrn)|$($_.sts)|$($_.ostt)|$($_.acp)|$($_.memo)|$($_.div)|$($_.dr)" }) -join "`n")
    if ($script:RsvHash[$day] -eq $h) { continue }
    if ($DryRun) { Log "DRY 예약 문서: $day $($byDay[$day].Count)건"; $script:RsvHash[$day] = $h; $changed += $day; continue }
    if (-not $script:IsLeader -and -not $ResvAlways) { $script:RsvHash[$day] = $h; continue }   # 대기 중엔 쓰지 않고 해시만 따라감(담당이 되면 해시를 비워 전부 다시 씀)
    try {
      FsPatch "bitResv/$day" @{ date = $day; updatedAt = (NowIso); pc = $Pc; src = 'db'; count = [int]$byDay[$day].Count; items = @($byDay[$day]) }
      $script:RsvHash[$day] = $h; $changed += $day
      Log "예약 문서: $day $($byDay[$day].Count)건 (취소 $(@($byDay[$day] | Where-Object { $_.sts -eq 'OC' }).Count))"
    } catch { Log "예약 문서 전송 오류 ${day}: $($_.Exception.Message)" }
  }
  if ($changed.Count -and -not $DryRun -and ($script:IsLeader -or $ResvAlways)) {   # 날짜별 요약(건수만) — 화면 상단 7일 띠용, 문서 1개
    $days = @{}; foreach ($day in $byDay.Keys) { $L = @($byDay[$day] | Where-Object { -not $_.block }); $days[$day] = @{ n = [int]@($L | Where-Object { $_.sts -ne 'OC' }).Count; canc = [int]@($L | Where-Object { $_.sts -eq 'OC' }).Count; arrived = [int]@($L | Where-Object { $_.acp }).Count; naver = [int]@($L | Where-Object { $_.naver -and $_.sts -ne 'OC' }).Count } }   # 예약금지(block)는 건수에서 뺀다
    try { FsPatch "bitResv/_summary" @{ updatedAt = (NowIso); pc = $Pc; days = $days } } catch { Log "예약 요약 전송 오류: $($_.Exception.Message)" }
  }
}

# ── 메인 ──
Log "비트 DB 감시 $VER 시작: PC=$Pc  SQL=$SqlServer/$Database ($SqlUser)  주기 ${PollSec}s  우선순위 $Priority  동료 $(if ($Peers.Count) { $Peers -join ',' } else { '없음' })  상태포트 $(if ($health) { $HealthPort } else { '없음' })  $(if ($DryRun) { '[DRY RUN — 전송 없음]' })$(if ($SendExistingOnStart) { '[시작 시 기존 접수 전송]' })"
AssertReadonlySql ($QUERY -f '20000101'); Log "SQL 읽기 전용 검사 통과"
if (-not $DryRun) { try { $null = FbToken } catch { Log $_.Exception.Message } }
$st = LoadState; $first = $st.fresh
if (-not $first) { Log "상태 파일 복원: 오늘 본 접수 $($st.seen.Count)건, 보낸 접수 $($st.sent.Count)건 (스냅샷 없이 이어감)" }
$lastBeat = [DateTime]::MinValue; $sqlOk = $null; $cyc = 0
while ($true) {
  $cycStart = Get-Date
  if ($st.date -ne (Today)) { Log "날짜 변경 → 상태 초기화"; $st = @{ date = (Today); seen = @{}; sent = @{}; fresh = $true }; $first = $true; TrimLog }
  HealthDrain
  if ($Peers.Count) { ElectLeader }   # 다른 에이전트가 있으면 매 주기 우선순위 확인(LAN, 수 ms)
  try {
    $n = Poll $st $first
    $script:LastDbOk = Get-Date
    if ($ResvDays -gt 0 -and ($ResvEvery -le 1 -or ($cyc % $ResvEvery) -eq 0)) { if (-not $script:DepName.Count) { LoadDepNames }; try { PollResv } catch { Log "예약 조회 오류: $($_.Exception.Message)" } }
    if ($first) { Log "시작 스냅샷: 오늘 행 $n 건, 접수 계열 $($st.sent.Count)건$(if ($SendExistingOnStart) { ' 전송' } else { " (보내지 않음, 최근 ${RecentMin}분 접수 $($script:SnapRecent)건은 전송)" })"; $first = $false; $script:SnapRecent = 0 }
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
  IdleWait ([Math]::Max(500, $PollSec * 1000 - $ms))
}
