# ui_probe.ps1 - READ-ONLY check of the Bit outpatient order window on this PC (2026-11-24)
#
# Purpose: before building "approve, then save automatically", find out
#   (1) whether the Bit SAVE button can be found as a control (so it could later be pressed exactly, without mouse coordinates)
#   (2) whether the prescription grid can be read as text (so the doctor could get text instead of only a picture)
#
# It CLICKS NOTHING, TYPES NOTHING and CHANGES NOTHING in Bit. It only reads the window structure.
# No pattern is invoked (no Invoke / Toggle / SetValue / SetFocus). Patient text is masked (Hangul -> H, digits -> 9 in labels).
# Result: a text file on this PC's Desktop (bit_ui_probe_YYYYMMDD_HHMM.txt). Nothing is uploaded.
#
# Run (normal PowerShell, same Windows user that uses Bit, with the Bit outpatient window open):
#   [Net.ServicePointManager]::SecurityProtocol='Tls12'; iex (irm https://bonafide-portal.seoulgijibae.workers.dev/dongseon/bit/ui_probe.txt)
# ASCII only on purpose (PowerShell 5.1 reads BOM-less downloads as ANSI): Korean words are built from code points.
param([int]$MaxNodes = 4000, [int]$MaxSec = 60, [int]$MaxRows = 15, [string]$ProcName = 'BITDoctorOrder', [string]$OutDir = '')   # ProcName / OutDir: test only
$ErrorActionPreference = 'Continue'
function K([int[]]$c) { -join ($c | ForEach-Object { [char]$_ }) }
$W_OUT  = K 0xC678,0xB798,0xC9C4,0xB8CC,0xC2E4   # outpatient room window title
$W_SAVE = K 0xC800,0xC7A5                        # save

$out = New-Object System.Collections.Generic.List[string]
function P($s) { Write-Host $s; $out.Add([string]$s) }
function MaskAll($s) { ([string]$s) -replace '\p{IsHangulSyllables}', 'H' -replace '\d', '9' }   # labels / values that may hold patient data
function MaskHan($s) { ([string]$s) -replace '\p{IsHangulSyllables}', 'H' }                     # grid cells: keep codes and numbers, hide Korean words
function Short($s, $n = 60) { $s = ([string]$s) -replace '[\r\n\t]+', ' '; if ($s.Length -gt $n) { $s.Substring(0, $n) + '...' } else { $s } }

Add-Type -Namespace BitP -Name U32 -UsingNamespace System.Collections.Generic, System.Text -MemberDefinition @'
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, StringBuilder s, uint flags, uint timeout, out IntPtr res);
[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr res);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
public static List<IntPtr> Tops() { var l = new List<IntPtr>(); EnumWindows((h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
public static List<IntPtr> Children(IntPtr p) { var l = new List<IntPtr>(); EnumChildWindows(p, (h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
public static string Text(IntPtr h) {
  IntPtr res;
  if (SendMessageTimeout(h, 0x000E, IntPtr.Zero, IntPtr.Zero, 0x0002, 500, out res) == IntPtr.Zero) return "";
  int n = (int)res; if (n <= 0) return "";
  var sb = new StringBuilder(n + 2);
  if (SendMessageTimeout(h, 0x000D, (IntPtr)(n + 1), sb, 0x0002, 500, out res) == IntPtr.Zero) return "";
  return sb.ToString();
}
public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
public static int Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return (int)p; }
'@

P "Bit UI probe (read-only)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  PC=$env:COMPUTERNAME  user=$env:USERNAME"
if (-not $OutDir) { $OutDir = [Environment]::GetFolderPath('Desktop') }
$procs = @(Get-Process -Name $ProcName -ErrorAction SilentlyContinue)
if (-not $procs.Count) { P "[STOP] $ProcName.exe is not running on this PC. Open the Bit outpatient window first, then run again."; return }
$pids = @($procs | ForEach-Object { $_.Id })
$hwnd = $null; $proc = $null
foreach ($h in [BitP.U32]::Tops()) { $hp = [BitP.U32]::Pid($h); if ($pids -notcontains $hp) { continue }
  if ((([BitP.U32]::Text($h)) -replace '\s', '') -like "$W_OUT*") { $hwnd = $h; $proc = $procs | Where-Object { $_.Id -eq $hp } | Select-Object -First 1; break } }
if (-not $hwnd) { P "[STOP] Bit is running but the outpatient window was not found."; return }
P "$ProcName.exe pid=$($proc.Id) path=$($proc.Path) ver=$(try { $proc.MainModule.FileVersionInfo.FileVersion } catch { '?' })"
P "Outpatient window found: hwnd=$hwnd title(masked)='$(Short (MaskAll ([BitP.U32]::Text($hwnd))))'"

# ---------- Part A: Win32 child windows ----------
P ""; P "== A. Win32 child windows =="
$kids = [BitP.U32]::Children($hwnd); $byType = @{}; $buttons = @(); $saveHits = @()
foreach ($c in $kids) {
  $cls = [BitP.U32]::Cls($c); $typ = if ($cls -match '^WindowsForms10\.([^.]+)\.') { $Matches[1] } else { $cls }
  $byType[$typ] = 1 + [int]$byType[$typ]
  $txt = [BitP.U32]::Text($c)
  if ($typ -match 'BUTTON') { $r = New-Object BitP.U32+RECT; [void][BitP.U32]::GetWindowRect($c, [ref]$r)
    $buttons += "  button '$(Short $txt 30)' visible=$([BitP.U32]::IsWindowVisible($c)) enabled=$([BitP.U32]::IsWindowEnabled($c)) at=($($r.L),$($r.T)) size=$($r.R-$r.L)x$($r.B-$r.T) class=$cls" }
  if ($txt -like "*$W_SAVE*") { $saveHits += "  '$(Short $txt 30)' type=$typ visible=$([BitP.U32]::IsWindowVisible($c)) enabled=$([BitP.U32]::IsWindowEnabled($c)) class=$cls" }
}
P "child windows: $($kids.Count)"
foreach ($k in ($byType.Keys | Sort-Object)) { P "  $k : $($byType[$k])" }
P "-- BUTTON windows ($($buttons.Count)) --"; $buttons | Select-Object -First 80 | ForEach-Object { P $_ }
P "-- windows whose text contains SAVE ($($saveHits.Count)) --"; $saveHits | ForEach-Object { P $_ }

# ---------- Part B: accessibility tree (MSAA / IAccessible, read-only) ----------
# Every WinForms control (buttons, tool-bar items, grids, rows, cells) is visible here. Only names / values / roles / states are read;
# accDoDefaultAction / accSelect are never called.
P ""; P "== B. Accessibility tree (MSAA) =="
Add-Type -ReferencedAssemblies Accessibility -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text; using Accessibility;
public static class MsaaP {
  [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out object obj);
  [DllImport("oleacc.dll")] static extern int AccessibleChildren(IAccessible acc, int start, int count, [Out] object[] children, out int obtained);
  [DllImport("oleacc.dll", CharSet=CharSet.Unicode)] static extern uint GetRoleText(uint role, StringBuilder sb, uint max);
  static string S(Func<string> f) { try { return f() ?? ""; } catch { return ""; } }
  static string Role(object r) { try { if (r is int) { var sb = new StringBuilder(64); GetRoleText((uint)(int)r, sb, 64); return sb.ToString(); } return r == null ? "" : r.ToString(); } catch { return ""; } }
  // row: depth, role text (localized), name, value, defaultAction, state, x, y, w, h, role id
  public static List<string[]> Walk(IntPtr hwnd, int maxNodes, int maxDepth, int maxMs) {
    var list = new List<string[]>(); var t0 = DateTime.Now;
    Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71"); object o;
    if (AccessibleObjectFromWindow(hwnd, 0, ref iid, out o) != 0 || o == null) return list;   // OBJID_WINDOW
    Visit((IAccessible)o, 0, 0, list, maxNodes, maxDepth, t0, maxMs); return list;
  }
  static void Add(IAccessible a, object id, int d, List<string[]> list) {
    string role = Role(SafeRole(a, id));
    int x=0,y=0,w=0,h=0; try { a.accLocation(out x, out y, out w, out h, id); } catch {}
    string st = ""; try { var s = a.get_accState(id); st = s == null ? "" : s.ToString(); } catch {}
    object ro = SafeRole(a, id); string rid = (ro is int) ? ((int)ro).ToString() : "0";
    list.Add(new string[] { d.ToString(), role, S(() => a.get_accName(id)), S(() => a.get_accValue(id)), S(() => a.get_accDefaultAction(id)), st, x.ToString(), y.ToString(), w.ToString(), h.ToString(), rid });
  }
  static object SafeRole(IAccessible a, object id) { try { return a.get_accRole(id); } catch { return null; } }
  static void Visit(IAccessible a, int d, int unused, List<string[]> list, int maxNodes, int maxDepth, DateTime t0, int maxMs) {
    if (list.Count >= maxNodes || (DateTime.Now - t0).TotalMilliseconds > maxMs) return;
    Add(a, 0, d, list);
    if (d >= maxDepth) return;
    int n = 0; try { n = a.accChildCount; } catch { return; }
    if (n <= 0) return; if (n > 2000) n = 2000;
    var kids = new object[n]; int got = 0;
    try { if (AccessibleChildren(a, 0, n, kids, out got) != 0) return; } catch { return; }
    for (int i = 0; i < got; i++) {
      if (list.Count >= maxNodes || (DateTime.Now - t0).TotalMilliseconds > maxMs) return;
      var k = kids[i];
      if (k is IAccessible) Visit((IAccessible)k, d + 1, 0, list, maxNodes, maxDepth, t0, maxMs);
      else if (k is int) Add(a, k, d + 1, list);
    }
  }
}
'@
$t0 = Get-Date
$nodes = @(); try { $nodes = [MsaaP]::Walk($hwnd, $MaxNodes, 30, $MaxSec * 1000) } catch { P "[FAIL] MSAA walk: $($_.Exception.Message)" }
P "MSAA nodes: $($nodes.Count) in $([int]((Get-Date) - $t0).TotalSeconds)s$(if ($nodes.Count -ge $MaxNodes) { " (stopped at cap $MaxNodes)" })"
$byRole = @{}; foreach ($x in $nodes) { $kr = "$($x[1]) ($($x[10]))"; $byRole[$kr] = 1 + [int]$byRole[$kr] }
foreach ($k in ($byRole.Keys | Sort-Object)) { P "  $k : $($byRole[$k])" }
# MSAA role ids: 43 push button, 12 menu item, 57 button menu, 62 split button, 37 page tab, 25 column header, 22 tool bar, 44 check, 45 radio,
#  24 table, 33 list, 35 outline, 28 row, 34 list item, 36 outline item, 29 cell, 41 static text, 42 editable text, 9 window
$UI_IDS = @('43', '12', '57', '62', '37', '25', '22', '44', '45')
$SYS_NAMES = '^(IME|System|Restore|Move|Size|Minimi[sz]e|Maximi[sz]e|Close(\s+Alt\+F4)?|Context help|Line (up|down)|Page (up|down|left|right)|Column (left|right)|Top Left Header Cell)$'
P "-- SAVE controls (name contains SAVE, not text boxes) --"
foreach ($x in $nodes) { if ($x[2] -like "*$W_SAVE*" -and $x[10] -notin @('41', '42')) {
  P "  [$($x[1])] '$(Short $x[2] 30)' action='$($x[4])' state=$($x[5]) at=($($x[6]),$($x[7])) size=$($x[8])x$($x[9]) depth=$($x[0])" } }
P "-- named UI controls (buttons, menus, tabs, headers; first 150) --"
$nmd = 0; foreach ($x in $nodes) { if ($UI_IDS -contains $x[10] -and $x[2] -and $x[2] -notmatch $SYS_NAMES -and $nmd -lt 150) { $nmd++; P "  [$($x[1])] '$(Short $x[2] 30)' action='$($x[4])'" } }

# ---------- Part C: tables (prescription list?) ----------
$tabIdx = @(); for ($i = 0; $i -lt $nodes.Count; $i++) { if (@('24', '33', '35') -contains $nodes[$i][10]) { $tabIdx += $i } }
P ""; P "== C. Tables / lists ($($tabIdx.Count)) =="
$ti = 0
foreach ($i in $tabIdx) {
  $ti++; $t = $nodes[$i]; $d0 = [int]$t[0]
  P "-- table #$ti [$($t[1])] name(masked)='$(Short (MaskAll $t[2]) 30)' at=($($t[6]),$($t[7])) size=$($t[8])x$($t[9])"
  $rows = 0; $hdr = @()
  for ($j = $i + 1; $j -lt $nodes.Count -and [int]$nodes[$j][0] -gt $d0; $j++) {
    $x = $nodes[$j]
    if ($x[10] -eq '25' -and $x[2] -and $x[2] -notmatch $SYS_NAMES) { $hdr += $x[2] }
    if (@('28', '34', '36') -contains $x[10]) {
      if ($rows -ge $MaxRows) { continue }
      $cells = @(); for ($k = $j + 1; $k -lt $nodes.Count -and [int]$nodes[$k][0] -gt [int]$x[0]; $k++) { $c = $nodes[$k]; if ($c[10] -eq '29') { $v = if ($c[3]) { $c[3] } else { $c[2] }; $cells += (Short (MaskHan $v) 18) } }
      if (-not $cells.Count) { $cells = @(Short (MaskHan $(if ($x[3]) { $x[3] } else { $x[2] })) 60) }
      P "   row $rows : $($cells -join ' | ')"; $rows++
    }
  }
  if ($hdr.Count) { P "   column headers: $(($hdr | Select-Object -First 30) -join ' | ')" }
  if (-not $rows) { P "   (no rows readable)" }
}

$file = Join-Path $OutDir "bit_ui_probe_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
$out | Set-Content -Encoding UTF8 -Path $file
P ""; P "Saved: $file  (send this file to the developer; nothing was clicked or changed in Bit)"
