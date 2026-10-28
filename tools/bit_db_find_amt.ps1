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
param([string]$Mrn = '', [string]$Amount = '', [string]$Day = '',
      [string]$SqlServer = '192.168.0.250', [string]$Database = 'drbitpack', [string]$SqlUser = 'dongseon_ro', [string]$Secret = 'C:\bitplus\bit_db_agent.sql.secret')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
# 2026-10-25: 명령어를 치다 틀리는 일이 없게 — 인수 없이 두 번 클릭(접수PC_본인부담찾기.bat)하면 여기서 묻는다. 숫자가 아니면 다시 묻는다
while (($Mrn -replace '\D', '') -eq '') { $Mrn = Read-Host '차트번호 (숫자만)' }
$Mrn = $Mrn -replace '\D', ''
while (($Amount -replace '\D', '') -eq '') { $Amount = Read-Host '수납금액 (숫자만, 쉼표 없이 — 예: 299600)' }
$Amount = [decimal]($Amount -replace '\D', '')
# 날짜를 안 주면 오늘부터 14일 전까지 그 차트번호의 접수를 모두 본다(예전 날짜 예시로 해도 찾게)
$Days = if ($Day) { @(($Day -replace '\D', '')) } else { @(0..14 | ForEach-Object { (Get-Date).AddDays(-$_).ToString('yyyyMMdd') }) }
$out = Join-Path $PSScriptRoot 'bit_db_find_amt.txt'
$lines = New-Object System.Collections.ArrayList
function Say($s) { Write-Host $s; [void]$lines.Add([string]$s) }
if (-not (Test-Path $Secret)) { $m = "비밀번호 파일이 없습니다: $Secret — 이 PC 에는 비트 DB 에이전트가 없습니다. '접수PC_에이전트업데이트.bat' 을 한 접수 PC 에서 실행해 주세요"
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
  Say "== 비트 DB 본인부담 칸 찾기 — 차트번호 $Mrn · 금액 $Amount · 날짜 $($Days[-1])~$($Days[0]) · PC $env:COMPUTERNAME =="
  # 차트번호 칸은 앞에 공백·0 이 채워져 있을 수 있다 → 앞뒤 공백을 떼고 숫자로 비교
  $ocm = New-Object Data.DataTable
  foreach ($d in $Days) { $t = Q "SELECT OcmNum AS k, RTRIM(OcmComStt) AS stt, RTRIM(OcmAcpDtm) AS acp FROM OcmInf WITH (NOLOCK) WHERE LTRIM(RTRIM(OcmChtNum)) IN (@m, @m0) AND LEFT(OcmAcpDtm, 8) = @d" @{ '@m' = $Mrn; '@m0' = $Mrn.PadLeft(8, '0'); '@d' = $d }; $ocm.Merge($t) }
  if (-not $ocm.Rows.Count) { Say "최근 15일 동안 이 차트번호의 접수가 없습니다 — 차트번호를 확인해 주세요."; return }
  foreach ($r in $ocm.Rows) { Say ("접수번호 [{0}] 상태 {1} 접수 {2}" -f $r.k, $r.stt, $r.acp) }
  # v2 (2026-10-28): 취소(CN 등 C*·*R)된 접수는 빼고 본다 — 지난번 결과는 대부분 취소 접수였다
  $live = @($ocm.Rows | Where-Object { $_.stt -notmatch '^C|R$' }); if (-not $live.Count) { $live = @($ocm.Rows) }
  Say ("살아 있는 접수 {0}건만 봅니다" -f $live.Count)
  # v2: 비트는 금액을 글자 칸(char/varchar)에 넣기도 한다(처방 금액이 그랬다) → 숫자 칸 + 20자 이하 글자 칸 모두
  $cols = Q @"
SELECT t.name AS tbl, c.name AS col, ty.name AS typ
FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.object_id IN (SELECT object_id FROM sys.columns WHERE name LIKE '%OcmNum')
  AND (ty.name IN ('int','bigint','smallint','decimal','numeric','money','smallmoney','float','real') OR (ty.name IN ('char','varchar','nchar','nvarchar') AND c.max_length BETWEEN 1 AND 40))
ORDER BY t.name, c.column_id
"@ $null
  $keys = Q "SELECT t.name AS tbl, c.name AS col FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id WHERE c.name LIKE '%OcmNum'" $null
  $keyOf = @{}; foreach ($k in $keys.Rows) { if (-not $keyOf.ContainsKey($k.tbl)) { $keyOf[$k.tbl] = $k.col } }
  Say ("접수번호 칸이 있는 표 {0}개 · 숫자·글자 칸 {1}개를 봅니다 (같은 값 / 줄 합계)" -f $keyOf.Count, $cols.Rows.Count)
  $hit = 0; $as = [string][int64]$Amount
  foreach ($r in $live) {
    foreach ($c in $cols.Rows) {
      $kc = $keyOf[$c.tbl]; if (-not $kc -or $c.col -eq $kc) { continue }
      $isTxt = $c.typ -in 'char','varchar','nchar','nvarchar'
      $val = if ($isTxt) { "TRY_CAST(NULLIF(REPLACE(LTRIM(RTRIM([{0}])), ',', ''), '') AS decimal(18,2))" -f $c.col } else { "CAST([{0}] AS decimal(18,2))" -f $c.col }
      try {
        $t = Q ("SELECT SUM(CASE WHEN {2} = @a THEN 1 ELSE 0 END) AS n, SUM({2}) AS s, COUNT(*) AS rows FROM [{0}] WITH (NOLOCK) WHERE [{1}] = @k" -f $c.tbl, $kc, $val) @{ '@k' = $r.k; '@a' = $Amount }
        $row = $t.Rows[0]
        if ($row.n -isnot [DBNull] -and [int]$row.n -gt 0) { $hit++; Say ("★ 찾음(같은 값): {0}.{1} [{4}]  접수 {5} · 접수번호 칸 {2}, {3}행" -f $c.tbl, $c.col, $kc, $row.n, $c.typ, $r.k) }
        elseif ($row.s -isnot [DBNull] -and [int]$row.rows -gt 1 -and [decimal]$row.s -eq $Amount) { $hit++; Say ("☆ 찾음(줄 합계): {0}.{1} [{4}]  접수 {5} · {3}줄 합계 = {6}" -f $c.tbl, $c.col, $kc, $row.rows, $c.typ, $r.k, $as) }
      } catch { }
    }
  }
  # v2: 접수번호 칸이 없는 수납(영수증) 표 — 차트번호 칸(…ChtNum)이 있는 표에서 같은 값
  $cht = Q @"
SELECT t.name AS tbl, c.name AS col, ty.name AS typ, (SELECT TOP 1 k.name FROM sys.columns k WHERE k.object_id = t.object_id AND k.name LIKE '%ChtNum') AS kc
FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.object_id IN (SELECT object_id FROM sys.columns WHERE name LIKE '%ChtNum') AND t.object_id NOT IN (SELECT object_id FROM sys.columns WHERE name LIKE '%OcmNum')
  AND (ty.name IN ('int','bigint','smallint','decimal','numeric','money','smallmoney','float','real') OR (ty.name IN ('char','varchar','nchar','nvarchar') AND c.max_length BETWEEN 1 AND 40))
"@ $null
  Say ("차트번호 칸만 있는 표의 칸 {0}개도 봅니다" -f $cht.Rows.Count)
  foreach ($c in $cht.Rows) {
    if ($c.col -eq $c.kc) { continue }
    $isTxt = $c.typ -in 'char','varchar','nchar','nvarchar'
    $val = if ($isTxt) { "TRY_CAST(NULLIF(REPLACE(LTRIM(RTRIM([{0}])), ',', ''), '') AS decimal(18,2))" -f $c.col } else { "CAST([{0}] AS decimal(18,2))" -f $c.col }
    try {
      $t = Q ("SELECT COUNT(*) AS n FROM [{0}] WITH (NOLOCK) WHERE LTRIM(RTRIM([{1}])) IN (@m, @m0) AND {2} = @a" -f $c.tbl, $c.kc, $val) @{ '@m' = $Mrn; '@m0' = $Mrn.PadLeft(8, '0'); '@a' = $Amount }
      if ([int]$t.Rows[0].n -gt 0) { $hit++; Say ("★ 찾음(차트번호 표): {0}.{1} [{2}]  {3}행" -f $c.tbl, $c.col, $c.typ, $t.Rows[0].n) }
    } catch { }
  }
  if (-not $hit) { Say "같은 금액이 든 칸을 못 찾았습니다 — ① 수납이 끝난(수납완료) 실제 환자 ② 비트 수납 창의 '총 본인부담' 금액 그대로(쉼표 없이)로 다시 해 주세요. 테스트 환자는 금액이 없을 수 있어요." }
} finally { $cn.Close(); [IO.File]::WriteAllLines($out, $lines, (New-Object Text.UTF8Encoding $true)); Write-Host "`n결과 파일: $out" -ForegroundColor Green }
