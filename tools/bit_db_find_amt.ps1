<#
  비트 DB 에서 '총 본인부담' 금액이 들어 있는 칸 찾기 (2026-10-17) — 읽기만 한다(SELECT).
  동의서 화면의 '총금액'을 환자 부담금(비트 수납 창의 '총 본인부담', 수납대기 목록의 '수납금액')으로 바꾸려면
  그 값이 비트 DB 어느 표·칸에 있는지 알아야 해서, 한 환자의 금액으로 거꾸로 찾는다.

  접수 PC(비트 DB 에이전트가 깔린 PC, C:\bitplus 에 bit_db_agent.sql.secret 있음)에서:
    powershell -ExecutionPolicy Bypass -File bit_db_find_amt.ps1 -Mrn 20540 -Amount 299600
    (오늘이 아닌 날이면  -Day 20261016)

  하는 일: ① 그 날 그 차트번호의 접수번호(OcmNum) ② 접수번호 칸(…OcmNum)이 있는 모든 표의 숫자 칸 중 금액이 같은 칸
  결과는 화면과 같은 폴더의 bit_db_find_amt.txt 에 — 그 내용을 보내 주세요.
#>
param([Parameter(Mandatory = $true)][string]$Mrn, [Parameter(Mandatory = $true)][decimal]$Amount, [string]$Day = (Get-Date).ToString('yyyyMMdd'),
      [string]$SqlServer = '192.168.0.250', [string]$Database = 'drbitpack', [string]$SqlUser = 'dongseon_ro', [string]$Secret = 'C:\bitplus\bit_db_agent.sql.secret')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$out = Join-Path $PSScriptRoot 'bit_db_find_amt.txt'
$lines = New-Object System.Collections.ArrayList
function Say($s) { Write-Host $s; [void]$lines.Add([string]$s) }
if (-not (Test-Path $Secret)) { Write-Host "비밀번호 파일이 없습니다: $Secret — 비트 DB 에이전트가 깔린 접수 PC 에서 실행해 주세요" -ForegroundColor Red; exit 1 }
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
  Say "== 비트 DB 본인부담 칸 찾기 — 차트번호 $Mrn · 금액 $Amount · 날짜 $Day =="
  $ocm = Q "SELECT OcmNum AS k, RTRIM(OcmComStt) AS stt, RTRIM(OcmAcpDtm) AS acp FROM OcmInf WITH (NOLOCK) WHERE OcmChtNum = @m AND LEFT(OcmAcpDtm, 8) = @d" @{ '@m' = $Mrn; '@d' = $Day }
  if (-not $ocm.Rows.Count) { Say "그 날 이 차트번호의 접수가 없습니다."; return }
  foreach ($r in $ocm.Rows) { Say ("접수번호 [{0}] 상태 {1} 접수 {2}" -f $r.k, $r.stt, $r.acp) }
  $cols = Q @"
SELECT t.name AS tbl, c.name AS col, ty.name AS typ
FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.object_id IN (SELECT object_id FROM sys.columns WHERE name LIKE '%OcmNum')
  AND ty.name IN ('int','bigint','smallint','decimal','numeric','money','smallmoney','float','real')
ORDER BY t.name, c.column_id
"@ $null
  $keys = Q "SELECT t.name AS tbl, c.name AS col FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id WHERE c.name LIKE '%OcmNum'" $null
  $keyOf = @{}; foreach ($k in $keys.Rows) { if (-not $keyOf.ContainsKey($k.tbl)) { $keyOf[$k.tbl] = $k.col } }
  Say ("접수번호 칸이 있는 표 {0}개 · 숫자 칸 {1}개를 봅니다" -f $keyOf.Count, $cols.Rows.Count)
  $hit = 0
  foreach ($r in $ocm.Rows) {
    foreach ($c in $cols.Rows) {
      $kc = $keyOf[$c.tbl]; if (-not $kc) { continue }
      try {
        $t = Q ("SELECT COUNT(*) AS n FROM [{0}] WITH (NOLOCK) WHERE [{1}] = @k AND [{2}] = @a" -f $c.tbl, $kc, $c.col) @{ '@k' = $r.k; '@a' = $Amount }
        if ([int]$t.Rows[0].n -gt 0) { $hit++; Say ("★ 찾음: {0}.{1}  (접수번호 칸 {2}, {3}행)" -f $c.tbl, $c.col, $kc, $t.Rows[0].n) }
      } catch { }
    }
  }
  if (-not $hit) { Say "같은 금액이 든 칸을 못 찾았습니다 — 수납 전(계산 전)이면 금액이 아직 없을 수 있어요. 수납대기 목록에 수납금액이 보이는 환자로 다시 해 주세요." }
} finally { $cn.Close(); [IO.File]::WriteAllLines($out, $lines, (New-Object Text.UTF8Encoding $true)); Write-Host "`n결과 파일: $out" -ForegroundColor Green }
