# ─────────────────────────────────────────────────────────────
#  비트플러스 화면 읽기 테스트 v2 (진단용)
#  접수 PC에서 비트플러스 '접수' 창(진료 대기 목록)이 보이는 상태로 실행하세요.
#  결과: 바탕화면\bitplus_probe\ 폴더에
#    1) uia.txt      — UI Automation 전체 요소 (이름 없는 것 포함, 위치·패턴)
#    2) grid.txt     — 표(Grid/Table/Text/MSAA) 패턴으로 읽어본 결과  ← 진료 대기 목록이 여기 나오는지가 핵심
#    3) window.png   — 창 캡처 (화면에서 직접)
#    4) ocr.txt      — Windows 내장 OCR(한국어)
#  ※ 결과 파일에는 환자 정보가 있습니다. 파일 전체를 보내지 말고 필요한 줄만, 개인정보는 지우고 알려주세요.
# ─────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Continue'
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'bitplus_probe'
New-Item -ItemType Directory -Force $out | Out-Null
$uiaFile = Join-Path $out 'uia.txt'; $gridFile = Join-Path $out 'grid.txt'; $png = Join-Path $out 'window.png'; $ocrFile = Join-Path $out 'ocr.txt'

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
$sig = @'
using System; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
Add-Type -TypeDefinition $sig
[W]::SetProcessDPIAware() | Out-Null

# 1) 비트플러스 접수 창 찾기
"=== 창 목록 ===" | Out-File $uiaFile -Encoding utf8
Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { "  [$($_.ProcessName)] $($_.MainWindowTitle)" } | Out-File $uiaFile -Append -Encoding utf8
$procs = Get-Process | Where-Object { $_.MainWindowTitle -and $_.ProcessName -eq 'BITRegistrations' }
if (-not $procs) { $procs = Get-Process | Where-Object { $_.MainWindowTitle -and $_.ProcessName -match '^BIT' -and $_.ProcessName -ne 'BITMenu' } }
if (-not $procs) { Write-Host "비트플러스 접수 창을 못 찾았습니다. $uiaFile 의 창 목록을 확인하세요."; exit }
$p = $procs | Select-Object -First 1
$hwnd = $p.MainWindowHandle
Write-Host "대상 창: [$($p.ProcessName)] $($p.MainWindowTitle)"

# 2) UI Automation 전체 요소 덤프 (이름 없는 요소도 포함 — 표 컨트롤 찾기용)
"`n=== UI Automation 전체 요소 ([$($p.ProcessName)] $($p.MainWindowTitle)) ===" | Out-File $uiaFile -Append -Encoding utf8
"형식`t클래스`t위치(x,y,w,h)`t패턴`t이름`t값" | Out-File $uiaFile -Append -Encoding utf8
"=== 표/텍스트 패턴 읽기 ===" | Out-File $gridFile -Encoding utf8
$root = $null
try { $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd) } catch { "UIA 오류: $_" | Out-File $uiaFile -Append -Encoding utf8 }
if ($root) {
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $n = 0; $gridHits = 0
  foreach ($el in $all) {
    $n++
    $c = $el.Current
    $type = $c.ControlType.ProgrammaticName -replace 'ControlType\.',''
    $cls = $c.ClassName; $name = ($c.Name -replace "[\r\n\t]+",' ')
    $rc = $c.BoundingRectangle
    $pos = if ($rc.IsEmpty) { '-' } else { "$([int]$rc.X),$([int]$rc.Y),$([int]$rc.Width),$([int]$rc.Height)" }
    $pats = @()
    try { $pats = $el.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName -replace 'PatternIdentifiers\.Pattern','' } } catch {}
    $val = ''
    try { $vp = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if ($vp) { $val = ($vp.Current.Value -replace "[\r\n\t]+",' ') } } catch {}
    "$type`t$cls`t$pos`t$($pats -join ',')`t$name`t$val" | Out-File $uiaFile -Append -Encoding utf8

    # 2-a) 표(Grid/Table) 패턴 — 행/열 단위로 읽기
    try {
      $gp = $el.GetCurrentPattern([System.Windows.Automation.GridPattern]::Pattern)
      if ($gp) {
        $gridHits++
        "`n[Grid] $type $cls 위치=$pos 이름=$name  행=$($gp.Current.RowCount) 열=$($gp.Current.ColumnCount)" | Out-File $gridFile -Append -Encoding utf8
        $rows = [Math]::Min($gp.Current.RowCount, 30); $cols = [Math]::Min($gp.Current.ColumnCount, 20)
        for ($r = 0; $r -lt $rows; $r++) {
          $cells = @()
          for ($cc = 0; $cc -lt $cols; $cc++) {
            try { $it = $gp.GetItem($r, $cc); $t = $it.Current.Name
              try { $ivp = $it.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if ($ivp -and -not $t) { $t = $ivp.Current.Value } } catch {}
              $cells += $t } catch { $cells += '?' }
          }
          "  행$r`t$($cells -join ' | ')" | Out-File $gridFile -Append -Encoding utf8
        }
      }
    } catch {}
    # 2-b) 텍스트 패턴 — 문서 전체 글자
    try {
      $tp = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
      if ($tp) { $txt = $tp.DocumentRange.GetText(4000)
        if ($txt -and $txt.Trim()) { $gridHits++; "`n[Text] $type $cls 위치=$pos`n$txt" | Out-File $gridFile -Append -Encoding utf8 } }
    } catch {}
    # 2-c) MSAA(LegacyIAccessible) — 옛날 방식 접근성 정보
    try {
      $lp = $el.GetCurrentPattern([System.Windows.Automation.AutomationPattern]::LookupById(10018))   # LegacyIAccessiblePattern
      if ($lp) { $lc = $lp.Current
        $ln = "$($lc.Name)"; $lv = "$($lc.Value)"; $ld = "$($lc.Description)"
        if (($ln -or $lv -or $ld) -and ($ln -ne $name)) { "`n[MSAA] $type $cls 위치=$pos 이름=$ln 값=$lv 설명=$ld 역할=$($lc.Role)" | Out-File $gridFile -Append -Encoding utf8 }
        # 자식(행) 열거
        try { $kids = $lp.GetIAccessible(); $cnt = $kids.accChildCount
          if ($cnt -gt 0 -and $cnt -lt 400) { $lines = @()
            for ($k = 1; $k -le $cnt; $k++) { try { $kn = $kids.accName($k); $kv = $kids.accValue($k); if ($kn -or $kv) { $lines += "    자식$k`t$kn`t$kv" } } catch {} }
            if ($lines.Count) { "  [MSAA 자식 $cnt 개 — $type $cls 위치=$pos]" | Out-File $gridFile -Append -Encoding utf8; $lines | Out-File $gridFile -Append -Encoding utf8; $gridHits++ } }
        } catch {}
      }
    } catch {}
  }
  "`n총 요소 수: $n" | Out-File $uiaFile -Append -Encoding utf8
  Write-Host "UI Automation: 요소 $n 개 → uia.txt / 표·텍스트 패턴 발견 $gridHits 건 → grid.txt"
}

# 3) 창 캡처 — PrintWindow 가 흰 화면이면 화면에서 직접 복사(창을 앞으로 가져옴)
if ([W]::IsIconic($hwnd)) { [W]::ShowWindow($hwnd, 9) | Out-Null; Start-Sleep -Milliseconds 400 }
$r = New-Object W+RECT; [W]::GetWindowRect($hwnd, [ref]$r) | Out-Null
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc(); [W]::PrintWindow($hwnd, $dc, 2) | Out-Null; $g.ReleaseHdc($dc); $g.Dispose()
# 흰 화면 검사: 대각선 픽셀 표본
$blank = $true
for ($i = 0; $i -lt 40; $i++) { $px = $bmp.GetPixel([int]($w * $i / 40), [int]($h * $i / 40)); if ($px.R -lt 250 -or $px.G -lt 250 -or $px.B -lt 250) { $blank = $false; break } }
if ($blank) {
  Write-Host "PrintWindow 결과가 흰 화면 → 창을 앞으로 가져와 화면에서 직접 캡처합니다."
  [W]::SetForegroundWindow($hwnd) | Out-Null; Start-Sleep -Milliseconds 700
  $bmp.Dispose(); $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h)); $g.Dispose()
}
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Host "창 캡처: $png ($w x $h)$(if($blank){' [화면 복사]'}else{' [PrintWindow]'})"

# 4) Windows 내장 OCR (한국어)
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
  [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
  [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null
  [Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime] | Out-Null
  [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime] | Out-Null
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  function Await($op, $t) { $m = $asTask.MakeGenericMethod($t); $task = $m.Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
  $lang = New-Object Windows.Globalization.Language 'ko'
  $eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
  if (-not $eng) { $eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
  if (-not $eng) { throw '한국어 OCR 엔진이 없습니다 (한국어 언어팩 설치 필요)' }
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($png)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $sb = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $res = Await ($eng.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
  $lines = @()
  foreach ($ln in $res.Lines) {
    $x = 0; $y = 0; try { $w0 = @($ln.Words)[0]; $rc = $w0.BoundingRect; $x = [int][double]$rc.X; $y = [int][double]$rc.Y } catch {}
    $lines += ("{0,5} {1,5}  {2}" -f $y, $x, $ln.Text)
  }
  "=== OCR (언어: $($eng.RecognizerLanguage.DisplayName)) — y x 글자 ===" | Out-File $ocrFile -Encoding utf8
  $lines | Out-File $ocrFile -Append -Encoding utf8
  Write-Host "OCR: 줄 $($lines.Count) 개 → ocr.txt"
} catch { "OCR 오류: $_" | Out-File $ocrFile -Encoding utf8; Write-Host "OCR 오류: $_" }

Write-Host "`n완료. 결과 폴더: $out"
Write-Host "→ grid.txt 에 진료 대기 목록(차트번호·이름·시간)이 나오는지 먼저 확인하세요."
