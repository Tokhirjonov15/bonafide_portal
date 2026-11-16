<#
  슬립이 비트 저장 기록과 다를 때 원인 확인 (2026-11-15 임현주 9045: 처방을 고쳤는데 슬립에 반영 안 됨) — 읽기만 한다(SELECT, 로그 읽기).
  비트 DB 에이전트가 깔린 접수 PC(C:\bitplus\bit_db_agent.sql.secret 있음)에서 접수PC_슬립확인.bat 을 두 번 클릭 → 차트번호 입력.
  보여 주는 것: ① 오늘 그 환자 접수 ② 비트에 저장된 차팅(EmrInf) 줄과 저장 시각(EmrUpdDtm) ③ 이 PC 에이전트 버전·담당 여부·그 차트번호 로그
  결과는 같은 폴더의 bit_db_note_check.txt — 그 화면(또는 파일)을 보내 주세요.
#>
param([string]$Mrn = '', [string]$Day = '',
      [string]$SqlServer = '192.168.0.250', [string]$Database = 'drbitpack', [string]$SqlUser = 'dongseon_ro', [string]$Secret = 'C:\bitplus\bit_db_agent.sql.secret')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
while (($Mrn -replace '\D', '') -eq '') { $Mrn = Read-Host '차트번호 (숫자만)' }
$Mrn = $Mrn -replace '\D', ''
if (-not $Day) { $Day = Read-Host '날짜 (오늘이면 그냥 엔터, 다른 날이면 예: 20261115)' }
$D = if (($Day -replace '\D', '').Length -eq 8) { $Day -replace '\D', '' } else { (Get-Date).ToString('yyyyMMdd') }
$out = Join-Path $PSScriptRoot 'bit_db_note_check.txt'
$lines = New-Object System.Collections.ArrayList
function Say($s) { Write-Host $s; [void]$lines.Add([string]$s) }
try {
  Say "== 슬립 확인 — 차트번호 $Mrn · 날짜 $D · PC $env:COMPUTERNAME · $(Get-Date -Format 'HH:mm:ss') =="
  # ③ 이 PC 에이전트
  $agent = 'C:\bitplus\bit_db_agent.ps1'
  if (Test-Path $agent) { $vm = Select-String -Path $agent -Pattern "^\`$VER = '([^']+)'" | Select-Object -First 1
    Say ("에이전트 파일 버전: {0}" -f $(if ($vm) { $vm.Matches[0].Groups[1].Value } else { '?' })) } else { Say "에이전트 파일 없음: $agent" }
  try { $t = Get-ScheduledTask BitDbAgent -ErrorAction Stop; Say ("작업 BitDbAgent: {0} · {1}" -f $t.State, $t.Actions[0].Arguments) } catch { Say "작업 BitDbAgent 없음" }
  try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 9001); $s = $c.GetStream(); $s.ReadTimeout = 2000
    $buf = New-Object byte[] 256; $n = $s.Read($buf, 0, 256); $c.Close(); Say ("상태 포트 9001: {0}" -f ([Text.Encoding]::UTF8.GetString($buf, 0, $n).Trim())) } catch { Say "상태 포트 9001 응답 없음" }
  $alog = Join-Path $env:LOCALAPPDATA 'bit_db_agent\agent.log'
  if (Test-Path $alog) {
    $hit = @(Get-Content $alog -Encoding UTF8 -Tail 20000 | Where-Object { $_ -match "^$($D.Substring(0,4))-$($D.Substring(4,2))-$($D.Substring(6,2))" -and $_ -match "\b$Mrn\b" } | Select-Object -Last 15)
    Say ("에이전트 로그 중 차트번호 $Mrn 줄 {0}개:" -f $hit.Count); $hit | ForEach-Object { Say "   $_" }
    Say "에이전트 로그 마지막 5줄:"; Get-Content $alog -Encoding UTF8 -Tail 5 | ForEach-Object { Say "   $_" }
  } else { Say "에이전트 로그 없음: $alog" }
  # ①② 비트 DB
  if (-not (Test-Path $Secret)) { Say "비밀번호 파일이 없습니다: $Secret — 비트 DB 에이전트가 깔린 접수 PC 에서 실행해 주세요"; return }
  $pw = (Get-Content $Secret -Encoding UTF8 -TotalCount 1).Trim()
  $cn = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$Database;User ID=$SqlUser;Password=$pw;Connect Timeout=8;ApplicationIntent=ReadOnly")
  $cn.Open()
  try {
    function Q($sql, $params) {
      $c = $cn.CreateCommand(); $c.CommandTimeout = 15
      $c.CommandText = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SET LOCK_TIMEOUT 3000"; [void]$c.ExecuteNonQuery()
      $c.CommandText = $sql; foreach ($k in $params.Keys) { [void]$c.Parameters.AddWithValue($k, $params[$k]) }
      $r = $c.ExecuteReader(); $t = New-Object Data.DataTable; $t.Load($r); $r.Close(); return ,$t }
    $p = @{ '@m' = $Mrn; '@m0' = $Mrn.PadLeft(8, '0'); '@d' = $D }
    $ocm = Q "SELECT RTRIM(OcmNum) AS k, RTRIM(OcmComStt) AS stt, RTRIM(OcmAcpDtm) AS acp FROM OcmInf WITH (NOLOCK) WHERE LTRIM(RTRIM(OcmChtNum)) IN (@m, @m0) AND LEFT(OcmAcpDtm, 8) = @d" $p
    Say ("오늘 접수 {0}건:" -f $ocm.Rows.Count); foreach ($r in $ocm.Rows) { Say ("   접수번호 {0} · 상태 {1} · 접수 {2}" -f $r.k, $r.stt, $r.acp) }
    $emr = Q @"
SELECT RTRIM(e.EmrOcmNum) AS k, e.EmrShtSeq AS seq, RTRIM(e.EmrUpdDtm) AS upd, RTRIM(e.EmrShtTyp) AS typ, RTRIM(e.EmrShtCod) AS cod, LEFT(CAST(e.EmrShtVal AS nvarchar(max)), 150) AS v
FROM EmrInf e WITH (NOLOCK) JOIN OcmInf m WITH (NOLOCK) ON m.OcmNum = e.EmrOcmNum
WHERE e.EmrOcmDte = @d AND LTRIM(RTRIM(m.OcmChtNum)) IN (@m, @m0)
ORDER BY e.EmrOcmNum, e.EmrShtTyp, e.EmrShtCod, e.EmrShtSeq
"@ $p
    Say ("비트 저장 기록(EmrInf) {0}줄 — [접수번호 · 종류 · 순서 · 저장시각] 내용:" -f $emr.Rows.Count)
    foreach ($r in $emr.Rows) { Say ("   [{0} · {1}/{2} · {3} · {4}] {5}" -f $r.k, $r.typ, $r.cod, $r.seq, $r.upd, (([string]$r.v) -replace '\s+', ' ')) }
    # 처방 항목(OdrInf) — 지운 줄(C)도 함께: 엑스레이 오더가 언제 들어오고 지워졌는지 (2026-11-16 박재현 4562 x-ray 알림 안 감)
    $odr = Q @"
SELECT RTRIM(o.OdrOcmNum) AS k, o.OdrSeq AS seq, RTRIM(o.OdrCod) AS cod, LEFT(RTRIM(o.OdrCodNam), 40) AS nam, RTRIM(o.OdrDtm) AS dtm, RTRIM(o.OdrDelFlg) AS del
FROM OdrInf o WITH (NOLOCK) JOIN OcmInf m WITH (NOLOCK) ON m.OcmNum = o.OdrOcmNum
WHERE LEFT(m.OcmAcpDtm, 8) = @d AND LTRIM(RTRIM(m.OcmChtNum)) IN (@m, @m0)
ORDER BY o.OdrOcmNum, o.OdrSeq
"@ $p
    Say ("비트 처방 항목(OdrInf) {0}줄 — [접수번호 · 순서 · 입력시각 · 지움표시] 코드 명칭:" -f $odr.Rows.Count)
    foreach ($r in $odr.Rows) { Say ("   [{0} · {1} · {2} · {3}] {4}  {5}" -f $r.k, $r.seq, $r.dtm, $(if ($r.del -eq 'C') { '지움' } else { '-' }), $r.cod, $r.nam) }
  } finally { $cn.Close() }
} catch { Say "오류: $($_.Exception.Message)" }
finally { [IO.File]::WriteAllLines($out, $lines, (New-Object Text.UTF8Encoding $true)); Write-Host "`n결과 파일: $out" -ForegroundColor Green }
