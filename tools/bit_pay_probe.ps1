<#
  비트 '수납내역' 창 읽기 테스트 (2026-11-15) — 읽기만 한다(아무것도 누르거나 입력하지 않음).
  동의서 금액을 비트 수납 창의 금액(총 본인부담 · 현금/카드/계좌 칸)과 똑같이 맞추려고,
  그 창의 칸들을 프로그램이 읽을 수 있는지, 어느 칸이 어느 금액인지 알아낸다.

  사용: 비트에서 아무 환자의 수납 창(수납내역 — 카드·현금 칸이 있는 창)을 열어 둔 채 접수PC_수납창읽기.bat 을 두 번 클릭.
        10초 안에 수납 창이 화면에 보이게만 해 두면 된다(클릭할 필요 없음).
  결과: 같은 폴더의 bit_pay_probe.txt — 그 내용을 보내 주세요.
#>
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$out = Join-Path $PSScriptRoot 'bit_pay_probe.txt'
Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class PW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> Tops() { var l = new List<IntPtr>(); EnumWindows((h, x) => { if (IsWindowVisible(h)) l.Add(h); return true; }, IntPtr.Zero); return l; }
  public static List<IntPtr> Children(IntPtr p) { var l = new List<IntPtr>(); EnumChildWindows(p, (h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
  public static string Text(IntPtr h) { IntPtr res;
    if (SendMessageTimeout(h, 0x000E, IntPtr.Zero, IntPtr.Zero, 0x0002, 500, out res) == IntPtr.Zero) return "";
    int n = (int)res; if (n <= 0) return ""; if (n > 4000) n = 4000; var sb = new StringBuilder(n + 2);
    if (SendMessageTimeout(h, 0x000D, (IntPtr)(n + 1), sb, 0x0002, 500, out res) == IntPtr.Zero) return ""; return sb.ToString(); }
  public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
}
'@
$lines = New-Object System.Collections.ArrayList
function Say($s) { Write-Host $s; [void]$lines.Add([string]$s) }
for ($i = 10; $i -gt 0; $i--) { Write-Host "비트 수납 창이 화면에 보이게 해 두세요... $i"; Start-Sleep 1 }
try {
  Say "== 비트 수납 창 읽기 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') · PC $env:COMPUTERNAME =="
  $found = 0
  foreach ($h in [PW]::Tops()) {
    $pid0 = [uint32]0; [void][PW]::GetWindowThreadProcessId($h, [ref]$pid0)
    $pn = ''; try { $pn = (Get-Process -Id $pid0 -ErrorAction Stop).ProcessName } catch {}
    $kids = [PW]::Children($h)
    $txts = @($kids | ForEach-Object { [PW]::Text($_) })
    $title = [PW]::Text($h)
    # v2: 비트 프로그램(BIT…)의 보이는 창은 모두, 그 밖에는 제목·글에 '차트번호' 가 있는 창 — v1 은 '수납' 글자까지 요구해 수납 창을 건너뛰었다
    $all = ($title + ' ' + ($txts -join ' '))
    if (-not ($pn -match '^BIT' -or $all -match '차트번호')) { continue }
    $found++
    $r = New-Object PW+RECT; [void][PW]::GetWindowRect($h, [ref]$r)
    Say ""
    Say ("### 창 [{0}] 프로그램 {1} · 클래스 {2} · 위치 {3},{4} 크기 {5}x{6} · 자식 {7}개" -f $title, $pn, [PW]::Cls($h), $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T), $kids.Count)
    Say "x,y(창 기준) | 폭x높이 | 클래스 | 글"
    foreach ($k in $kids) {
      $kr = New-Object PW+RECT; [void][PW]::GetWindowRect($k, [ref]$kr)
      $t = ([PW]::Text($k)) -replace "`r?`n", ' / '; if ($t.Length -gt 120) { $t = $t.Substring(0, 120) + '…' }
      Say ("{0},{1} | {2}x{3} | {4} | {5}" -f ($kr.L - $r.L), ($kr.T - $r.T), ($kr.R - $kr.L), ($kr.B - $kr.T), [PW]::Cls($k), $t)
    }
    # v2: 그림으로 그린 칸(일반 방식으로 글이 안 읽히는 칸)은 UI Automation 으로 이름·값을 한 번 더 — 큰 메인 창(자식 300개 이상)은 건너뜀
    if ($kids.Count -lt 300) {
      try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        $els = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        Say ("--- UIA 요소 {0}개 (종류 | 이름 | 값 | x,y)" -f $els.Count)
        foreach ($e in $els) { $c = $e.Current; $v = ''
          try { $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if ($vp) { $v = $vp.Current.Value } } catch {}
          $nm = [string]$c.Name; if (-not $nm -and -not $v) { continue }
          $b = $c.BoundingRectangle
          Say ("{0} | {1} | {2} | {3},{4}" -f $c.ControlType.ProgrammaticName.Replace('ControlType.', ''), ($nm -replace "`r?`n", ' / '), $v, [int]($b.X - $r.L), [int]($b.Y - $r.T)) }
      } catch { Say "UIA 오류: $($_.Exception.Message)" }
    }
  }
  if (-not $found) { Say "수납 창을 찾지 못했습니다 — 비트 수납 창(카드·현금 칸이 있는 창)을 연 채로 다시 실행해 주세요." }
} catch { Say "오류: $($_.Exception.Message)" }
finally { try { [IO.File]::WriteAllLines($out, $lines, (New-Object Text.UTF8Encoding $true)) } catch {}; Write-Host "`n결과 파일: $out" -ForegroundColor Green; Write-Host '창을 닫으려면 Enter'; try { [void](Read-Host) } catch {} }
