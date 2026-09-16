<#
  비트(Dr.BIT / 유차트) SQL Server 점검 — 비트 DB 서버(192.168.0.250) 에서 관리자 PowerShell 로 실행
  ---------------------------------------------------------------------------------------------
  하는 일(기본은 읽기만):
    1) 이 컴퓨터의 SQL Server 인스턴스·서비스 상태·포트 확인
    2) Windows 인증으로 접속해 버전, 인증 모드(혼합/Windows 전용), 내 계정이 sysadmin 인지 확인
    3) DrBITPACK 데이터베이스와 OcmInf / PbsInf / UidMst / RsvInf / DtlMst 테이블이 있는지, 접수 상태 코드표(COMSTT) 출력
    4) 오늘 접수 건수와 최근 3건(이름은 가림)을 읽어 쿼리가 맞는지 확인
  선택:
    -CreateLogin        읽기 전용 로그인 dongseon_ro 를 만든다(db_datareader 만, 비밀번호는 실행 중 입력). sysadmin 이어야 함
    -TestLogin          방금 만든 로그인으로 실제 접속·SELECT 가 되는지 확인(비밀번호 입력)
  사용 예:
    powershell -ExecutionPolicy Bypass -File bit_db_check.ps1
    powershell -ExecutionPolicy Bypass -File bit_db_check.ps1 -CreateLogin
    powershell -ExecutionPolicy Bypass -File bit_db_check.ps1 -TestLogin
  절대 하지 않는 것: 비트 데이터에 쓰기·수정·삭제, 서비스 재시작, 설정 변경. 만드는 것은 읽기 전용 계정 하나뿐.
#>
param([string]$Server = 'localhost', [string]$Database = 'DrBITPACK', [string]$LoginName = 'dongseon_ro', [switch]$CreateLogin, [switch]$TestLogin)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
function Say($s) { Write-Host $s }
function Mask($n) { $s = [string]$n; if ($s.Length -ge 2) { return $s.Substring(0,1) + '○' + $s.Substring($s.Length-1) }; return $s }
function Q($cn, $sql) { $cmd = $cn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 15; $r = $cmd.ExecuteReader(); $t = New-Object Data.DataTable; $t.Load($r); $r.Close(); return $t }

Say "== 1. 이 컴퓨터의 SQL Server =="
$svcs = Get-Service | Where-Object { $_.Name -like 'MSSQL*' -or $_.Name -like 'SQLBrowser' -or $_.Name -like 'SQLAgent*' }
if (-not $svcs) { Say "  SQL Server 서비스가 이 컴퓨터에 없습니다 → 다른 컴퓨터가 DB 서버입니다(비트 환경설정 › DataBase Server 확인)." }
foreach ($s in $svcs) { Say ("  {0,-28} {1}" -f $s.Name, $s.Status) }
$inst = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction SilentlyContinue | ForEach-Object { $_.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { "$($_.Name) → $($_.Value)" } })
if ($inst) { Say ("  인스턴스: " + ($inst -join ', ')) }
$l = Get-NetTCPConnection -State Listen -LocalPort 1433 -ErrorAction SilentlyContinue | Select-Object -First 1
Say ("  1433 포트 수신: " + ($(if ($l) { "예 (PID $($l.OwningProcess))" } else { "아니오 — 다른 포트/동적 포트일 수 있음(SQL Server 구성 관리자에서 TCP/IP 포트 확인)" })))

Say "== 2. Windows 인증 접속 =="
$cn = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Database=master;Integrated Security=True;Connect Timeout=8;ApplicationIntent=ReadOnly")
try { $cn.Open() } catch {
  Say ("  실패: " + $_.Exception.Message)
  Say "  → 인스턴스 이름이 있으면 -Server 'localhost\인스턴스이름' 으로 다시 실행. 그래도 안 되면 이 Windows 계정에 SQL 접근 권한이 없는 것 → 4번 항목 참고."
  exit 1
}
$v = (Q $cn "SELECT @@VERSION AS v").Rows[0].v; Say ("  버전: " + ($v -split "`n")[0].Trim())
$mixed = (Q $cn "SELECT CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS int) AS x").Rows[0].x
Say ("  인증 모드: " + $(if ($mixed -eq 0) { "혼합 모드(SQL 로그인 가능) ✔" } else { "Windows 인증 전용 — SQL 로그인(dongseon_ro)은 만들 수 없음 → 4번 항목의 Windows 계정 방식으로" }))
$isSa = (Q $cn "SELECT IS_SRVROLEMEMBER('sysadmin') AS x").Rows[0].x
$who = (Q $cn "SELECT SUSER_SNAME() AS x").Rows[0].x
Say ("  접속 계정: $who · sysadmin: " + $(if ($isSa -eq 1) { "예 ✔ (읽기 전용 로그인을 직접 만들 수 있음)" } else { "아니오 — 로그인을 만들 권한이 없음. sa 또는 다른 sysadmin 계정이 필요" }))
$dbs = (Q $cn "SELECT name FROM sys.databases ORDER BY name").Rows | ForEach-Object { $_.name }
Say ("  데이터베이스: " + ($dbs -join ', '))
if ($dbs -notcontains $Database) { Say "  ※ $Database 가 없습니다. 위 목록에서 비트 DB 이름을 찾아 -Database 로 지정하세요."; $cn.Close(); exit 1 }

Say "== 3. $Database 구조 확인(읽기만) =="
$cn.ChangeDatabase($Database)
$tabs = (Q $cn "SELECT name FROM sys.tables WHERE name IN ('OcmInf','PbsInf','UidMst','RsvInf','DtlMst') ORDER BY name").Rows | ForEach-Object { $_.name }
Say ("  필요한 테이블: " + ($tabs -join ', ') + $(if ($tabs.Count -eq 5) { " ✔ (5/5)" } else { " — 일부 없음(비트 버전 차이). 있는 테이블: " + ((Q $cn "SELECT COUNT(*) AS n FROM sys.tables").Rows[0].n) + "개" }))
if ($tabs -contains 'DtlMst') {
  $codes = Q $cn "SELECT RTRIM(DtlCod) AS c, RTRIM(DtlNam) AS n FROM DtlMst WITH (NOLOCK) WHERE DtlTblCod='COMSTT' ORDER BY DtlCod"
  Say ("  접수 상태 코드(COMSTT) " + $codes.Rows.Count + "개: " + (($codes.Rows | ForEach-Object { "$($_.c)=$($_.n)" }) -join ', '))
}
if ($tabs -contains 'OcmInf') {
  $today = (Get-Date).ToString('yyyyMMdd')
  $n = (Q $cn "SELECT COUNT(*) AS n FROM OcmInf WITH (NOLOCK) WHERE LEFT(OcmAcpDtm,8)='$today'").Rows[0].n
  Say "  오늘 접수 행: $n 건"
  $sql = @"
SELECT TOP 3 RTRIM(o.OcmNum) AS k, RTRIM(o.OcmComStt) AS stt, p.PbsPatNam AS name, RTRIM(o.OcmChtNum) AS mrn, o.OcmAcpDtm AS recv, u.UidNam AS dr,
       CASE WHEN r.RsvOcmNum IS NULL THEN 'N' ELSE 'Y' END AS rsv
FROM OcmInf o WITH (NOLOCK)
LEFT JOIN PbsInf p WITH (NOLOCK) ON p.PbsChtNum = o.OcmChtNum
LEFT JOIN UidMst u WITH (NOLOCK) ON u.UidCod = o.OcmDtrCod
LEFT JOIN RsvInf r WITH (NOLOCK) ON r.RsvOcmNum = o.OcmNum
WHERE LEFT(o.OcmAcpDtm,8)='$today' ORDER BY o.OcmAcpDtm DESC
"@
  $rows = Q $cn $sql
  foreach ($r in $rows.Rows) { Say ("    {0} {1} {2} mrn={3} recv={4} dr={5} rsv={6}" -f $r.k, $r.stt, (Mask $r.name), $r.mrn, $r.recv, $r.dr, $r.rsv) }
  Say "  ✔ 파트너 병원 문서의 조회 쿼리가 이 DB 에서도 그대로 동작합니다."
}

if ($CreateLogin) {
  Say "== 5. 읽기 전용 로그인 만들기 =="
  if ($mixed -ne 0) { Say "  혼합 모드가 아니라 SQL 로그인을 만들 수 없습니다(4번 참고)."; $cn.Close(); exit 1 }
  if ($isSa -ne 1) { Say "  sysadmin 이 아니라 만들 수 없습니다."; $cn.Close(); exit 1 }
  $pw = Read-Host -AsSecureString "  $LoginName 비밀번호(12자 이상, 영문+숫자+기호)"
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($pw))
  if ($plain.Length -lt 12 -or $plain -match "'") { Say "  비밀번호는 12자 이상, 작은따옴표(') 없이."; exit 1 }
  $exists = (Q $cn "SELECT COUNT(*) AS n FROM sys.server_principals WHERE name='$LoginName'").Rows[0].n
  $cmd = $cn.CreateCommand()
  if ($exists -eq 0) { $cmd.CommandText = "CREATE LOGIN [$LoginName] WITH PASSWORD = N'$plain', CHECK_POLICY = OFF"; $null = $cmd.ExecuteNonQuery(); Say "  로그인 생성" } else { Say "  로그인은 이미 있음(그대로 둠)" }
  $cmd.CommandText = "IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='$LoginName') CREATE USER [$LoginName] FOR LOGIN [$LoginName]"; $null = $cmd.ExecuteNonQuery()
  $cmd.CommandText = "ALTER ROLE db_datareader ADD MEMBER [$LoginName]"; $null = $cmd.ExecuteNonQuery()
  $cmd.CommandText = "DENY INSERT, UPDATE, DELETE, EXECUTE TO [$LoginName]"; $null = $cmd.ExecuteNonQuery()   # 읽기 외 권한은 명시적으로 막음(이중 안전)
  Say "  ✔ ${LoginName}: ${Database} 에서 SELECT 만 가능(db_datareader + INSERT/UPDATE/DELETE/EXECUTE 거부). 비밀번호는 안전한 곳에 보관하세요."
}
$cn.Close()

if ($TestLogin) {
  Say "== 6. $LoginName 로 접속 시험 =="
  $pw = Read-Host -AsSecureString "  $LoginName 비밀번호"
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($pw))
  $c2 = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Database=$Database;User ID=$LoginName;Password=$plain;Connect Timeout=8")
  $c2.Open()
  $n = (Q $c2 "SELECT COUNT(*) AS n FROM OcmInf WITH (NOLOCK)").Rows[0].n; Say "  SELECT OK — OcmInf 전체 $n 행"
  try { $x = $c2.CreateCommand(); $x.CommandText = "CREATE TABLE dbo.__dongseon_probe (a int)"; $null = $x.ExecuteNonQuery(); Say "  !! 쓰기가 허용됨 — 권한을 다시 확인하세요"; $x.CommandText = "DROP TABLE dbo.__dongseon_probe"; $null = $x.ExecuteNonQuery() }
  catch { Say "  쓰기 시도 거부됨 ✔ (읽기 전용 확인)" }
  $c2.Close()
}
Say ""
Say "== 4. 참고: Windows 인증 전용이거나 sysadmin 이 아닐 때 =="
Say "  · SQL Server 구성에서 혼합 모드로 바꾸려면 서비스 재시작이 필요합니다 → 진료 시간 밖에, 비트 담당자와 상의해서."
Say "  · 대안: 에이전트를 이 서버에서 Windows 계정으로 실행하고 그 계정을 DrBITPACK 의 db_datareader 로 매핑(로그인 비밀번호 불필요)."
Say "  · 어느 쪽이든 필요한 것은 '읽기 전용' 뿐입니다. 비트 데이터는 바꾸지 않습니다."
