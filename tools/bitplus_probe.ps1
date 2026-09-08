# ─────────────────────────────────────────────────────────────
#  비트플러스 화면 읽기 테스트 v3 (진단용)
#  실행 방법: 비트플러스 '접수' 창이 화면에 보이는 상태에서 실행 → 5초 카운트다운 동안
#             비트플러스 창을 한 번 클릭해서 맨 앞으로 가져오세요.
#  결과: 바탕화면\bitplus_probe\
#    fullscreen.png  전체 화면 / grid.png 진료대기 표(2배 확대) / pay.png 수납대기 표(2배 확대)
#    ocr.txt         표 OCR 결과(행 단위)   ← 핵심
#    msaa.txt        표 창(HWND)에 옛 접근성(MSAA) 방식으로 물어본 결과
#    uia.txt         UI Automation 요소 (v2와 동일)
#  ※ 결과 파일에는 환자 정보가 있습니다. 파일 전체를 보내지 말고 필요한 줄만, 이름·번호는 가리고 알려주세요.
# ─────────────────────────────────────────────────────────────
param([string]$Title = '')   # 예: -Title 예약  → 제목에 '예약'이 들어간 비트 창(예약관리)을 대상으로
$ErrorActionPreference = 'Continue'
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'bitplus_probe'
New-Item -ItemType Directory -Force $out | Out-Null
$uiaFile = Join-Path $out 'uia.txt'; $ocrFile = Join-Path $out 'ocr.txt'; $msaaFile = Join-Path $out 'msaa.txt'

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
$sig = @'
using System; using System.Text; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object ppv);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static object AccFromHwnd(IntPtr h) { Guid g = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71"); object o; int hr = AccessibleObjectFromWindow(h, 0xFFFFFFFC, ref g, out o); return hr == 0 ? o : null; }
}
'@
Add-Type -TypeDefinition $sig
[W]::SetProcessDPIAware() | Out-Null

# 0) 비트플러스 접수 창
$procs = $null
if ($Title) { $procs = Get-Process | Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle -match $Title } }
if (-not $procs) { $procs = Get-Process | Where-Object { $_.MainWindowTitle -and $_.ProcessName -eq 'BITRegistrations' } }
if (-not $procs) { $procs = Get-Process | Where-Object { $_.MainWindowTitle -and $_.ProcessName -match '^BIT' -and $_.ProcessName -ne 'BITMenu' } }
if (-not $procs) { Write-Host "비트플러스 접수 창을 못 찾았습니다."; Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { "  [$($_.ProcessName)] $($_.MainWindowTitle)" }; exit }
$p = $procs | Select-Object -First 1
$hwnd = $p.MainWindowHandle
Write-Host "대상 창: [$($p.ProcessName)] $($p.MainWindowTitle)  (PID $($p.Id))"
$elev = '확인불가'; try { $null = $p.MainModule.FileName; $elev = '아니오(일반 권한)' } catch { $elev = '예(관리자 권한일 가능성)' }
Write-Host "관리자 권한 실행 여부: $elev"

# 1) 카운트다운 — 사용자가 비트플러스 창을 클릭해 맨 앞으로
for ($i = 5; $i -ge 1; $i--) { Write-Host "  $i 초 안에 비트플러스 창을 클릭하세요..."; Start-Sleep 1 }
$fg = [W]::GetForegroundWindow()
Write-Host ("맨 앞 창이 비트플러스인가: " + $(if ($fg -eq $hwnd) { '예' } else { '아니오 (다른 창이 앞에 있음 → 캡처가 가려질 수 있음)' }))

# 2) UI Automation — 요소 덤프 + 표 영역 찾기
$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
"형식`t클래스`tHWND`t위치(x,y,w,h)`t이름" | Out-File $uiaFile -Encoding utf8
$els = @()
foreach ($el in $all) {
  $c = $el.Current; $rc = $c.BoundingRectangle
  $isEmpty = $rc.IsEmpty -or [double]::IsInfinity($rc.X) -or [double]::IsInfinity($rc.Width)
  $hw = [IntPtr]::Zero; try { if ($c.NativeWindowHandle) { $hw = [IntPtr][int64]$c.NativeWindowHandle } } catch {}
  $o = [pscustomobject]@{ type = ($c.ControlType.ProgrammaticName -replace 'ControlType\.',''); cls = $c.ClassName; hwnd = $hw; name = ($c.Name -replace "[\r\n\t]+",' '); x = $(if ($isEmpty) { 0 } else { [int]$rc.X }); y = $(if ($isEmpty) { 0 } else { [int]$rc.Y }); w = $(if ($isEmpty) { 0 } else { [int]$rc.Width }); h = $(if ($isEmpty) { 0 } else { [int]$rc.Height }); empty = $isEmpty }
  $els += $o
  "$($o.type)`t$($o.cls)`t$($o.hwnd)`t$($o.x),$($o.y),$($o.w),$($o.h)`t$($o.name)" | Out-File $uiaFile -Append -Encoding utf8
}
Write-Host "UI Automation: 요소 $($els.Count) 개 → uia.txt"
function FindEl($name) { $els | Where-Object { -not $_.empty -and $_.name.Trim() -eq $name } | Select-Object -First 1 }
$lblWait = FindEl '진료대기'; $btnSearch = FindEl '대기자 검색'; $lblPay = FindEl '수납대기'; $btnMisu = FindEl '미수납리스트'
$areas = @()
if ($lblWait -and $btnSearch) { $areas += [pscustomobject]@{ key = 'grid'; title = '진료 대기'; x = $lblWait.x; y = $lblWait.y + $lblWait.h; w = 835; h = $btnSearch.y - ($lblWait.y + $lblWait.h) } }
if ($lblPay -and $btnMisu)   { $areas += [pscustomobject]@{ key = 'pay';  title = '수납 대기'; x = $lblPay.x;  y = $lblPay.y + $lblPay.h;  w = 835; h = $btnMisu.y - ($lblPay.y + $lblPay.h) } }
if (-not $areas.Count) {   # 접수 화면이 아니면(예약관리 등) 창 전체를 하나의 영역으로 OCR
  $r0 = New-Object W+RECT; [W]::GetWindowRect($hwnd, [ref]$r0) | Out-Null
  $areas += [pscustomobject]@{ key = 'grid'; title = '창 전체'; x = $r0.L; y = $r0.T; w = ($r0.R - $r0.L); h = ($r0.B - $r0.T) }
  Write-Host "진료대기 라벨이 없어 창 전체를 OCR 합니다."
}
$areas | ForEach-Object { Write-Host "표 영역 [$($_.title)]: x=$($_.x) y=$($_.y) w=$($_.w) h=$($_.h)" }

# 3) 전체 화면 캡처(모든 모니터) → 표 영역 잘라 2배 확대
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$full = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height
$g = [System.Drawing.Graphics]::FromImage($full); $g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $full.Size); $g.Dispose()
$full.Save((Join-Path $out 'fullscreen.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "전체 화면 캡처: $($vs.Width) x $($vs.Height) (원점 $($vs.Left),$($vs.Top)) → fullscreen.png"
$crops = @{}
foreach ($a in $areas) {
  if ($a.w -le 0 -or $a.h -le 0) { continue }
  $src = New-Object System.Drawing.Rectangle ($a.x - $vs.Left), ($a.y - $vs.Top), $a.w, $a.h
  $big = New-Object System.Drawing.Bitmap ($a.w * 2), ($a.h * 2)
  $g = [System.Drawing.Graphics]::FromImage($big)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($full, (New-Object System.Drawing.Rectangle 0, 0, ($a.w * 2), ($a.h * 2)), $src, [System.Drawing.GraphicsUnit]::Pixel); $g.Dispose()
  $path = Join-Path $out "$($a.key).png"; $big.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $big.Dispose()
  $crops[$a.key] = $path
}
$full.Dispose()

# 4) OCR — 표 영역만 (행 단위로 묶어서 출력)
"=== 표 OCR (행 단위, ' | ' 로 칸 구분) ===" | Out-File $ocrFile -Encoding utf8
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
  [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
  [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null
  [Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime] | Out-Null
  [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime] | Out-Null
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  function Await($op, $t) { $m = $asTask.MakeGenericMethod($t); $task = $m.Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
  $eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language 'ko'))
  if (-not $eng) { $eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
  if (-not $eng) { throw '한국어 OCR 엔진이 없습니다 (설정 > 언어 > 한국어 언어팩)' }
  foreach ($a in $areas) {
    $path = $crops[$a.key]; if (-not $path) { continue }
    $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
    $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $sb = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res = Await ($eng.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
    # 단어를 y 좌표로 행 묶기 (같은 행 = y 차이 14px 이내, 2배 확대 기준)
    $words = @()
    foreach ($ln in $res.Lines) { foreach ($wd in $ln.Words) { $rc = $wd.BoundingRect; $words += [pscustomobject]@{ x = [int][double]$rc.X; y = [int][double]($rc.Y + $rc.Height / 2); t = $wd.Text } } }
    $words = $words | Sort-Object y, x
    $rows = @(); $cur = @(); $cy = -999
    foreach ($wd in $words) { if ([Math]::Abs($wd.y - $cy) -gt 14 -and $cur.Count) { $rows += ,$cur; $cur = @() }; if (-not $cur.Count) { $cy = $wd.y }; $cur += $wd }
    if ($cur.Count) { $rows += ,$cur }
    "`n[$($a.title)] 단어 $($words.Count) 개, 행 $($rows.Count) 개" | Out-File $ocrFile -Append -Encoding utf8
    foreach ($r in $rows) { $r = $r | Sort-Object x; $line = ''; $lx = -999
      foreach ($wd in $r) { if ($line -and ($wd.x - $lx) -gt 40) { $line += ' | ' } elseif ($line) { $line += ' ' }; $line += $wd.t; $lx = $wd.x }
      "  $line" | Out-File $ocrFile -Append -Encoding utf8 }
    Write-Host "OCR [$($a.title)]: 단어 $($words.Count) 개, 행 $($rows.Count) 개 → ocr.txt"
  }
} catch { "OCR 오류: $_" | Out-File $ocrFile -Append -Encoding utf8; Write-Host "OCR 오류: $_" }

# 5) MSAA — 표 영역 안의 창(HWND)들에 접근성 정보 요청 (행/셀 이름이 나오면 OCR 불필요)
"=== MSAA (표 영역 안 HWND) ===" | Out-File $msaaFile -Encoding utf8
$sbuf = New-Object System.Text.StringBuilder 256
function DumpAcc($acc, $depth, $max) {
  if ($null -eq $acc -or $depth -gt $max) { return }
  $n = 0; try { $n = [int]$acc.accChildCount } catch {}
  $pad = '  ' * $depth
  "$pad(자식 $n 개)" | Out-File $msaaFile -Append -Encoding utf8
  if ($n -le 0 -or $n -gt 500) { return }
  for ($i = 1; $i -le $n; $i++) {
    $nm = ''; $vl = ''; $rl = ''; $child = $null
    try { $nm = "$($acc.accName($i))" } catch {}
    try { $vl = "$($acc.accValue($i))" } catch {}
    try { $rl = "$($acc.accRole($i))" } catch {}
    if ($nm -or $vl) { "$pad  #$i 역할=$rl 이름=$nm 값=$vl" | Out-File $msaaFile -Append -Encoding utf8 }
    try { $child = $acc.accChild($i) } catch {}
    if ($child -is [System.__ComObject]) { DumpAcc $child ($depth + 1) $max }
  }
}
$hits = 0
foreach ($a in $areas) {
  $inside = $els | Where-Object { -not $_.empty -and $_.hwnd -ne [IntPtr]::Zero -and $_.x -ge $a.x -and $_.y -ge $a.y -and ($_.x + $_.w) -le ($a.x + $a.w + 5) -and ($_.y + $_.h) -le ($a.y + $a.h + 5) -and $_.w -gt 300 } | Sort-Object { $_.w * $_.h } -Descending | Select-Object -First 6
  foreach ($e in $inside) {
    $sbuf.Length = 0; [W]::GetClassName($e.hwnd, $sbuf, 256) | Out-Null
    "`n[$($a.title)] HWND=$($e.hwnd) 클래스=$($sbuf.ToString()) 위치=$($e.x),$($e.y),$($e.w),$($e.h)" | Out-File $msaaFile -Append -Encoding utf8
    $acc = $null; try { $acc = [W]::AccFromHwnd($e.hwnd) } catch { "  오류: $_" | Out-File $msaaFile -Append -Encoding utf8 }
    if ($acc) { try { "  이름=$($acc.accName(0)) 값=$($acc.accValue(0)) 역할=$($acc.accRole(0))" | Out-File $msaaFile -Append -Encoding utf8 } catch {}; DumpAcc $acc 0 2; $hits++ }
  }
}
Write-Host "MSAA: 표 영역 안 창 $hits 개 조회 → msaa.txt"
Write-Host "`n완료. 결과 폴더: $out"
Write-Host "→ grid.png 가 진료대기 표로 보이는지, ocr.txt 의 행이 맞는지 확인하세요."
