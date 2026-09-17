# ─────────────────────────────────────────────────────────────
#  DB 에이전트 한 번에 바로잡기 — 접수 PC 에서 관리자 PowerShell 로, 인수 없이:
#      powershell -ExecutionPolicy Bypass -File D:\bitplus\bitplus_fix_agent.ps1
#
#  이 PC 의 IP 로 어느 접수 PC 인지 스스로 알아내어(아래 $MAP) 우선순위·동료 목록을 정하고,
#  같은 폴더의 새 bit_db_agent.ps1(있으면 bitplus_watcher.ps1 도)을 C:\bitplus 에 복사한 뒤,
#  BitDbAgent 작업을 지우고 다시 만들고(인수 갱신), 남아 있는 옛 프로세스를 모두 끝내고, 새로 시작한 다음,
#  상태 포트(9001)에 직접 물어 "우선순위·이름이 기대와 같은가"를 확인해 PASS / FAIL 을 찍는다.
#  FAIL 이면 그 줄에 이유가 적혀 있다 — 그 화면을 그대로 찍어 오면 된다.
# ─────────────────────────────────────────────────────────────
param([string]$Pc = '', [string]$Dest = 'C:\bitplus', [switch]$Test)   # -Pc: IP 로 못 알아낼 때만 수동 지정. -Test: 바꾸지 않고 판정만
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
# 접수 PC 표 (2026-09-17). IP 가 바뀌면 여기만 고친다
$MAP = @{
  '192.168.0.16' = @{ pc = '접수1'; prio = 3 }
  '192.168.0.44' = @{ pc = '접수2'; prio = 2 }
  '192.168.0.57' = @{ pc = '접수3'; prio = 1 }
}
function Say($s, $c = 'Gray') { Write-Host $s -ForegroundColor $c }
$fail = @()

# ── 1. 이 PC 알아내기 ──
$ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress } | Where-Object { $_ -like '192.168.*' })
$me = $null; foreach ($ip in $ips) { if ($MAP.ContainsKey($ip)) { $me = $MAP[$ip]; $myIp = $ip } }
if (-not $me -and $Pc) { foreach ($k in $MAP.Keys) { if ($MAP[$k].pc -eq $Pc) { $me = $MAP[$k]; $myIp = $k } } }
if (-not $me) { Say "이 PC 의 IP($($ips -join ', '))가 접수 PC 표에 없습니다. -Pc 접수N 으로 지정하거나 스크립트의 `$MAP 을 고치세요." Red; exit 1 }
$peers = @($MAP.Keys | Where-Object { $_ -ne $myIp } | Sort-Object)
Say "== 이 PC: $($me.pc) ($myIp)  우선순위 $($me.prio)  동료 $($peers -join ', ') ==" Cyan
if ($Test) { Say "(-Test: 여기까지, 아무것도 바꾸지 않음)"; exit 0 }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Say "관리자 PowerShell 이 아닙니다 — 작업을 다시 만들 수 없어 여기서 멈춥니다(아무것도 바꾸지 않음). 시작 → PowerShell 오른쪽 클릭 → '관리자 권한으로 실행' 후 다시." Red; exit 1 }   # 2026-09-17: 비관리자로 계속 진행하면 옛 프로세스만 죽이고 작업은 못 만들어 에이전트가 빈 채로 남는다

# ── 2. 파일 ──
New-Item -ItemType Directory -Force $Dest | Out-Null
$src = Join-Path $PSScriptRoot 'bit_db_agent.ps1'
if (Test-Path $src) { Copy-Item $src (Join-Path $Dest 'bit_db_agent.ps1') -Force; Say "① 에이전트 복사: $src → $Dest ($((Get-Item $src).Length)B)" }
elseif (Test-Path (Join-Path $Dest 'bit_db_agent.ps1')) { Say "① 같은 폴더에 새 bit_db_agent.ps1 이 없어 $Dest 의 기존 파일을 그대로 씀" Yellow }
else { Say "① bit_db_agent.ps1 이 $PSScriptRoot 에도 $Dest 에도 없습니다" Red; exit 1 }
$wsrc = Join-Path $PSScriptRoot 'bitplus_watcher.ps1'
$watcherUpdated = $false
if (Test-Path $wsrc) { $cur = Join-Path $Dest 'bitplus_watcher.ps1'; if (-not (Test-Path $cur) -or (Get-FileHash $wsrc).Hash -ne (Get-FileHash $cur).Hash) { Copy-Item $wsrc $cur -Force; $watcherUpdated = $true; Say "   감시 스크립트도 갱신(내용이 달라서)" } }
foreach ($f in 'bitplus_watcher.secret', 'bit_db_agent.sql.secret') { if (-not (Test-Path (Join-Path $Dest $f))) { Say "   !! 비밀번호 파일 없음: $Dest\$f — bitplus_install.ps1 -Pc $($me.pc) -Agent 로 먼저 설치" Red; $fail += "비밀번호 파일 $f 없음" } }
[IO.File]::WriteAllText((Join-Path $Dest 'bitplus_peers.txt'), ("# DB 에이전트가 있는 다른 PC (bitplus_fix_agent.ps1 이 씀)`r`n" + ($peers -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
Say "② 동료 목록: $Dest\bitplus_peers.txt = $($peers -join ', ')"

# ── 3. 방화벽 ──
if ($isAdmin) {
  if (-not (Get-NetFirewallRule -DisplayName 'BitPlus DB Agent (TCP 9001)' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName 'BitPlus DB Agent (TCP 9001)' -Direction Inbound -Protocol TCP -LocalPort 9001 -Action Allow -Profile Any -RemoteAddress LocalSubnet | Out-Null; Say "③ 방화벽 9001 추가" } else { Say "③ 방화벽 9001 있음" }
}

# ── 4. 작업 다시 만들기 + 옛 프로세스 정리 + 시작 ──
function KillAgents() {
  $pat = '-File\s+"?[^"\s]*bit_db_agent\.ps1'
  $ps = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $pat })
  foreach ($p in $ps) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
  return $ps.Count
}
Stop-ScheduledTask -TaskName BitDbAgent -ErrorAction SilentlyContinue
$n = KillAgents; Start-Sleep 1; $n2 = KillAgents
Say "④ 옛 에이전트 프로세스 종료: $($n + $n2)개"
$args_ = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Dest\bit_db_agent.ps1`" -Pc `"DB-$($me.pc)`" -Priority $($me.prio)"
try {
  Unregister-ScheduledTask -TaskName BitDbAgent -Confirm:$false -ErrorAction SilentlyContinue
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args_
  $trg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $trg2 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
  $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName BitDbAgent -Action $act -Trigger @($trg, $trg2) -Settings $set -RunLevel Limited -Force -ErrorAction Stop | Out-Null
  $got = (Get-ScheduledTask BitDbAgent).Actions.Arguments
  if ($got -ne $args_) { Say "   !! 작업 인수가 기대와 다름: $got" Red; $fail += '작업 인수 불일치' } else { Say "   작업 BitDbAgent 다시 등록: $args_" }
  Start-ScheduledTask -TaskName BitDbAgent
} catch { Say "   !! 작업 등록 실패: $($_.Exception.Message)" Red; $fail += "작업 등록 실패: $($_.Exception.Message)" }
# 시작 프로그램 폴더에 옛 대체 항목이 있으면 제거(작업과 이중 실행 방지)
$vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'BitDbAgent.vbs'; if (Test-Path $vbs) { Remove-Item $vbs -Force -ErrorAction SilentlyContinue; Say "   시작 프로그램의 BitDbAgent.vbs 제거(작업으로 대체)" }
if ($watcherUpdated) {
  Stop-ScheduledTask -TaskName BitPlusWatcher -ErrorAction SilentlyContinue
  $pat = '-File\s+"?[^"\s]*bitplus_watcher\.ps1'
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $pat } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep 1; Start-ScheduledTask -TaskName BitPlusWatcher -ErrorAction SilentlyContinue; Say "   감시 스크립트 재시작"
}

# ── 5. 확인: 상태 포트에 직접 묻기 ──
Say "⑤ 확인 중(최대 25초)…"
$ans = ''; $deadline = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline) {
  Start-Sleep 2
  $cli = New-Object Net.Sockets.TcpClient
  try { $ar = $cli.BeginConnect('127.0.0.1', 9001, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(500)) { $cli.EndConnect($ar); $cli.ReceiveTimeout = 1500; $ans = (New-Object IO.StreamReader($cli.GetStream())).ReadLine(); if ($ans -and $ans.StartsWith('OK')) { break } } } catch {} finally { try { $cli.Close() } catch {} }
  # 'DOWN' 은 아직 첫 DB 조회가 끝나지 않은 것일 수 있으므로 시간 안에는 계속 다시 묻는다
}
$expect = "OK $($me.prio) DB-$($me.pc) "
$log = Join-Path $env:LOCALAPPDATA 'bit_db_agent\agent.log'
if (-not $ans) { $fail += '상태 포트(9001)가 답하지 않음 — 에이전트가 시작되지 않았거나 포트를 못 열음' }
elseif (-not $ans.StartsWith($expect)) { $fail += "상태 응답이 기대와 다름: '$ans' (기대: '$expect…')" }
elseif (($ans -split ' ').Count -lt 5) { $fail += "옛 버전 에이전트가 답함(동료 목록 칸 없음): '$ans' — 새 bit_db_agent.ps1 이 같은 폴더에 있었는지 확인" }
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'bit_db_agent\.ps1' })
if ($procs.Count -ne 1) { $fail += "에이전트 프로세스가 $($procs.Count)개 (1개여야 함)" }
Say ""
if ($fail.Count) { Say "FAIL — $($me.pc): $($fail -join ' / ')" Red } else { Say "PASS — $($me.pc): $ans" Green }
Say "   최근 로그:"; if (Test-Path $log) { Get-Content $log -Tail 4 -Encoding UTF8 | ForEach-Object { Say "   $_" } }
Say "   (동선관리 pill: 'DB-$($me.pc)' 초록. 전송 담당은 접수1 이어야 하며, 접수2·3 로그에는 '→ 대기(standby): DB-접수1@…' 가 찍힌다)"
