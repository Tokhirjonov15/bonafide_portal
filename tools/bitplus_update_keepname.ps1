<#
  감시 프로그램(bitplus_watcher)만 새 버전으로 — PC 이름은 그대로 (2026-10-28)
  진료실PC_설치.bat 는 이름을 '진료실N' 으로 정하므로 접수·처치·PT·C-Arm·상담실 PC 에는 쓸 수 없다.
  이 PC 에 이미 등록된 BitPlusWatcher 작업의 -Pc 값을 읽어 같은 이름으로 다시 설치한다(없으면 묻는다).
    -NoNote : 외래진료실 처방 칸을 슬립으로 보내지 않음(처방을 내지 않는 PC — 접수·처치·PT 등)
    -NoteGlp: 마운자로·위고비 처방만
#>
param([switch]$NoNote, [switch]$NoteGlp, [string]$Dest = 'C:\bitplus')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$pc = ''
try { $ta = [string](Get-ScheduledTask -TaskName BitPlusWatcher -ErrorAction Stop).Actions[0].Arguments
      $m = [regex]::Match($ta, '-Pc\s+"?([^"\s]+)"?'); if ($m.Success) { $pc = $m.Groups[1].Value } } catch {}
if ($pc) { Write-Host "이 PC 의 동선관리 이름: $pc  (그대로 씁니다)" -ForegroundColor Cyan }
else {
  Write-Host "이 PC 에 등록된 감시 작업을 찾지 못했습니다 — 동선관리 [PC 설치 상태]에 보이는 이름을 그대로 넣어 주세요 (예: 처치, PT2, 접수1)" -ForegroundColor Yellow
  while (-not $pc.Trim()) { $pc = Read-Host 'PC 이름' }; $pc = $pc.Trim() }
$opt = @{ Pc = $pc; Dest = $Dest }
if ($NoNote) { $opt.NoNote = $true } elseif ($NoteGlp) { $opt.NoteGlp = $true }
& (Join-Path $PSScriptRoot 'bitplus_install.ps1') @opt
