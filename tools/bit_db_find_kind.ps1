<#
  비트 DB 에서 처방 구분(@투약·@주사·@물리치료·@Xray …)이 들어 있는 칸 찾기 (2026-11-01) — 읽기만 한다(SELECT).
  동의서 처방내역에서 먹는 약(@투약)을 일수로·맨 아래로 보여 주려면, 비트가 그 구분을 DB 어느 칸에 두는지 알아야 한다.
  지금 에이전트는 처방의 코드·이름·수량·횟수·일수·금액만 보낸다.

  접수 PC(비트 DB 에이전트가 깔린 PC, C:\bitplus 에 bit_db_agent.sql.secret 있음)에서:
    접수PC_처방구분찾기.bat 을 두 번 클릭 → 오늘 약 처방이 있는 환자의 차트번호
    (또는 powershell -ExecutionPolicy Bypass -File bit_db_find_kind.ps1 -Mrn 33581)

  하는 일: ① 오늘 그 차트번호의 처방 줄(OdrInf)을 모든 칸과 함께 보여 준다 ② 처방코드가 들어 있는 코드표(…Mst)의 짧은 칸들도.
  결과는 같은 폴더의 bit_db_find_kind.txt 에 — 그 내용을 보내 주세요.
#>
param([string]$Mrn = '', [string]$Day = '',
      [string]$SqlServer = '192.168.0.250', [string]$Database = 'drbitpack', [string]$SqlUser = 'dongseon_ro', [string]$Secret = 'C:\bitplus\bit_db_agent.sql.secret')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
while (($Mrn -replace '\D', '') -eq '') { $Mrn = Read-Host '차트번호 (숫자만 — 오늘 약 처방이 있는 환자)' }
$Mrn = $Mrn -replace '\D', ''
$D = if ($Day) { $Day -replace '\D', '' } else { (Get-Date).ToString('yyyyMMdd') }
$out = Join-Path $PSScriptRoot 'bit_db_find_kind.txt'
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
# 한 줄의 칸들을 '칸=값' 으로 — 빈 칸·긴 글(40자 넘음)은 뺀다
function RowTxt($row, $skip) { $p = @(); foreach ($col in $row.Table.Columns) { if ($skip -contains $col.ColumnName) { continue }
    $v = $row[$col]; if ($v -is [DBNull]) { continue }; $s = ([string]$v).Trim(); if ($s -eq '' -or $s.Length -gt 40) { continue }; $p += "$($col.ColumnName)=$s" }; return ($p -join ' | ') }
try {
  Say "== 비트 DB 처방 구분 칸 찾기 — 차트번호 $Mrn · 날짜 $D · PC $env:COMPUTERNAME =="
  $odr = Q @"
SELECT o.* FROM OdrInf o WITH (NOLOCK) JOIN OcmInf m WITH (NOLOCK) ON m.OcmNum = o.OdrOcmNum
WHERE LTRIM(RTRIM(m.OcmChtNum)) IN (@m, @m0) AND LEFT(m.OcmAcpDtm, 8) = @d AND o.OdrDelFlg <> 'C'
ORDER BY o.OdrOcmNum, o.OdrSeq
"@ @{ '@m' = $Mrn; '@m0' = $Mrn.PadLeft(8, '0'); '@d' = $D }
  if (-not $odr.Rows.Count) { Say "이 날 이 차트번호의 처방이 없습니다 — 차트번호·날짜를 확인해 주세요."; return }
  Say ("`n== ① 처방 줄 {0}개 (OdrInf 의 모든 칸) ==" -f $odr.Rows.Count)
  foreach ($r in $odr.Rows) { Say ("[{0}] {1}" -f ([string]$r.OdrCodNam).Trim(), (RowTxt $r @('OdrCodNam'))) }
  # ② 처방코드 코드표 — 이름이 …Mst 인 표 중 …Cod 칸에 이 처방코드가 있는 것 (코드마다 표별 첫 줄)
  $cand = Q @"
SELECT t.name AS tbl, c.name AS col FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name LIKE '%Mst' AND c.name LIKE '%Cod' AND ty.name IN ('char','varchar','nchar','nvarchar') AND c.max_length BETWEEN 4 AND 40
ORDER BY t.name, c.column_id
"@ $null
  Say ("`n== ② 코드표(…Mst) 에서 처방코드 찾기 — 후보 칸 {0}개 ==" -f $cand.Rows.Count)
  $codes = @($odr.Rows | ForEach-Object { ([string]$_.OdrCod).Trim() } | Where-Object { $_ } | Select-Object -Unique)
  foreach ($cod in $codes) {
    $nm = (@($odr.Rows | Where-Object { ([string]$_.OdrCod).Trim() -eq $cod })[0].OdrCodNam -as [string]).Trim()
    Say "`n-- $cod  $nm"
    foreach ($c in $cand.Rows) {
      try { $t = Q ("SELECT TOP 1 * FROM [{0}] WITH (NOLOCK) WHERE LTRIM(RTRIM([{1}])) = @c" -f $c.tbl, $c.col) @{ '@c' = $cod }
        if ($t.Rows.Count) { Say ("   {0}.{1}: {2}" -f $c.tbl, $c.col, (RowTxt $t.Rows[0] @())) } } catch { }
    }
  }
} finally { $cn.Close(); [IO.File]::WriteAllLines($out, $lines, (New-Object Text.UTF8Encoding $true)); Write-Host "`n결과 파일: $out" -ForegroundColor Green }
