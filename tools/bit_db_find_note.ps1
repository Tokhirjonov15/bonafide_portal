<#
  비트 DB 에서 '저장된 진료 기록(증상 칸 — med 줄·처방 문구)'이 들어 있는 칸 찾기 (2026-11-01) — 읽기만 한다(SELECT).
  슬립은 진료실 PC 감시 프로그램이 외래진료실 화면에서 읽은 글이라, 원장님이 다른 PC(Sono·C-Arm 방 등 처방을 보내지 않는 PC)에서
  기록을 고치면 슬립이 옛 내용으로 남는다(2026-11-01 최하은 32753: 슬립 10:47 내용 ≠ 외래진료기록부).
  비트 DB 의 저장된 기록을 접수 PC 에이전트가 읽어 오면 어느 PC 에서 고쳐도 슬립이 맞게 된다 — 그 칸을 찾는다.

  접수 PC(비트 DB 에이전트가 깔린 PC, C:\bitplus 에 bit_db_agent.sql.secret 있음)에서:
    접수PC_진료기록찾기.bat 을 두 번 클릭 → 오늘 진료 기록에 med 를 적은 환자의 차트번호, 그 기록에 있는 낱말(예: 1wfu)
  결과는 같은 폴더의 bit_db_find_note.txt 에 — 그 내용을 보내 주세요(찾은 칸마다 앞 120자만 적는다).
#>
param([string]$Mrn = '', [string]$Word = '', [string]$Day = '',
      [string]$SqlServer = '192.168.0.250', [string]$Database = 'drbitpack', [string]$SqlUser = 'dongseon_ro', [string]$Secret = 'C:\bitplus\bit_db_agent.sql.secret')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
while (($Mrn -replace '\D', '') -eq '') { $Mrn = Read-Host '차트번호 (숫자만 — 오늘 진료 기록에 med 를 적은 환자)' }
$Mrn = $Mrn -replace '\D', ''
while (-not $Word.Trim()) { $Word = Read-Host '그 기록에 있는 낱말 (예: 1wfu, neuropathic)' }
$Word = $Word.Trim()
$D = if ($Day) { $Day -replace '\D', '' } else { (Get-Date).ToString('yyyyMMdd') }
$out = Join-Path $PSScriptRoot 'bit_db_find_note.txt'
$lines = New-Object System.Collections.ArrayList
function Say($s) { Write-Host $s; [void]$lines.Add([string]$s) }
if (-not (Test-Path $Secret)) { $m = "비밀번호 파일이 없습니다: $Secret — 이 PC 에는 비트 DB 에이전트가 없습니다. 비트 DB 에이전트가 깔린 접수 PC 에서 실행해 주세요"
  Write-Host $m -ForegroundColor Red; try { [IO.File]::WriteAllLines($out, @("== $(Get-Date -Format 'yyyy-MM-dd HH:mm') $env:COMPUTERNAME", $m), (New-Object Text.UTF8Encoding $true)) } catch {}; exit 1 }
$pw = (Get-Content $Secret -Encoding UTF8 -TotalCount 1).Trim()
$cn = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$Database;User ID=$SqlUser;Password=$pw;Connect Timeout=8;ApplicationIntent=ReadOnly")
$cn.Open()
function Q($sql, $params) {   # SELECT 만
  if ($sql -notmatch '^\s*SELECT\b' -or $sql -match '\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|EXEC|EXECUTE|GRANT|REVOKE|INTO)\b') { throw "SELECT 만 허용: $sql" }
  $c = $cn.CreateCommand(); $c.CommandTimeout = 15
  $c.CommandText = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SET LOCK_TIMEOUT 3000"; [void]$c.ExecuteNonQuery()
  $c.CommandText = $sql; if ($params) { foreach ($k in $params.Keys) { [void]$c.Parameters.AddWithValue($k, $params[$k]) } }
  $r = $c.ExecuteReader(); $t = New-Object Data.DataTable; $t.Load($r); $r.Close(); return ,$t }
try {
  Say "== 비트 DB 진료 기록 칸 찾기 — 차트번호 $Mrn · 낱말 '$Word' · 날짜 $D · PC $env:COMPUTERNAME =="
  $ocm = Q "SELECT OcmNum AS k, RTRIM(OcmComStt) AS stt, RTRIM(OcmAcpDtm) AS acp FROM OcmInf WITH (NOLOCK) WHERE LTRIM(RTRIM(OcmChtNum)) IN (@m, @m0) AND LEFT(OcmAcpDtm, 8) = @d" @{ '@m' = $Mrn; '@m0' = $Mrn.PadLeft(8, '0'); '@d' = $D }
  if (-not $ocm.Rows.Count) { Say "이 날 이 차트번호의 접수가 없습니다 — 차트번호를 확인해 주세요."; return }
  foreach ($r in $ocm.Rows) { Say ("접수번호 [{0}] 상태 {1} 접수 {2}" -f $r.k, $r.stt, $r.acp) }
  # 글자 칸(긴 글 포함) — 접수번호 칸(…OcmNum) 또는 차트번호 칸(…ChtNum)이 있는 표
  $cols = Q @"
SELECT t.name AS tbl, c.name AS col, ty.name AS typ,
  (SELECT TOP 1 k.name FROM sys.columns k WHERE k.object_id = t.object_id AND k.name LIKE '%OcmNum') AS ko,
  (SELECT TOP 1 k.name FROM sys.columns k WHERE k.object_id = t.object_id AND k.name LIKE '%ChtNum') AS kc
FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE (t.object_id IN (SELECT object_id FROM sys.columns WHERE name LIKE '%OcmNum') OR t.object_id IN (SELECT object_id FROM sys.columns WHERE name LIKE '%ChtNum'))
  AND ty.name IN ('char','varchar','nchar','nvarchar','text','ntext') AND (c.max_length = -1 OR c.max_length >= 40 OR ty.name IN ('text','ntext'))
ORDER BY t.name, c.column_id
"@ $null
  Say ("글자 칸 {0}개를 봅니다" -f $cols.Rows.Count)
  $hit = 0
  foreach ($c in $cols.Rows) {
    $v = if ($c.typ -in 'text','ntext') { "CAST([{0}] AS nvarchar(max))" -f $c.col } else { "[{0}]" -f $c.col }
    try {
      if ($c.ko -isnot [DBNull] -and $c.ko) {
        foreach ($r in $ocm.Rows) {
          $t = Q ("SELECT TOP 3 LEFT({2}, 120) AS s, LEN({2}) AS n FROM [{0}] WITH (NOLOCK) WHERE [{1}] = @k AND {2} LIKE @w" -f $c.tbl, $c.ko, $v) @{ '@k' = $r.k; '@w' = "%$Word%" }
          foreach ($x in $t.Rows) { $hit++; Say ("★ {0}.{1} [{2}] 접수 {3} · {4}자 : {5}" -f $c.tbl, $c.col, $c.typ, $r.k, $x.n, (([string]$x.s) -replace '\s+', ' ')) } }
      } elseif ($c.kc -isnot [DBNull] -and $c.kc) {
        $t = Q ("SELECT TOP 3 LEFT({2}, 120) AS s, LEN({2}) AS n FROM [{0}] WITH (NOLOCK) WHERE LTRIM(RTRIM([{1}])) IN (@m, @m0) AND {2} LIKE @w" -f $c.tbl, $c.kc, $v) @{ '@m' = $Mrn; '@m0' = $Mrn.PadLeft(8, '0'); '@w' = "%$Word%" }
        foreach ($x in $t.Rows) { $hit++; Say ("☆ {0}.{1} [{2}] (차트번호 표) · {3}자 : {4}" -f $c.tbl, $c.col, $c.typ, $x.n, (([string]$x.s) -replace '\s+', ' ')) }
      }
    } catch { }
  }
  if (-not $hit) { Say "그 낱말이 든 칸을 못 찾았습니다 — 오늘 기록에 실제로 있는 낱말(대소문자·띄어쓰기 그대로)로 다시 해 주세요." }
} finally { $cn.Close(); [IO.File]::WriteAllLines($out, $lines, (New-Object Text.UTF8Encoding $true)); Write-Host "`n결과 파일: $out" -ForegroundColor Green }
