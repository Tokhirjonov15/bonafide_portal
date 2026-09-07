# ─────────────────────────────────────────────────────────────
#  비트플러스 화면 읽기 테스트 (1단계 진단용)
#  접수 PC에서 비트플러스를 띄운 상태로 실행하세요.
#  결과: 바탕화면\bitplus_probe\ 폴더에
#    1) uia.txt        — UI Automation으로 읽은 글자 목록
#    2) window.png     — 비트플러스 창 캡처
#    3) ocr.txt        — Windows 내장 OCR(한국어)로 읽은 글자
#  ※ 이 파일들에는 환자 정보가 들어 있으니 외부로 보내지 마세요.
#     "이름·차트번호가 uia.txt에 보이는지 / ocr.txt에 보이는지"만 알려주면 됩니다.
# ─────────────────────────────────────────────────────────────
$ErrorActionPreference = 'Continue'
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'bitplus_probe'
New-Item -ItemType Directory -Force $out | Out-Null

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms

# 1) 비트플러스 창 찾기 (제목에 '비트' 또는 'Bit' 가 들어간 창)
# 비트플러스 접수 창(BITRegistrations, 제목 '접수')을 우선, 없으면 BIT 로 시작하는 다른 창
$procs = Get-Process | Where-Object { $_.MainWindowTitle -and $_.ProcessName -eq 'BITRegistrations' }
if (-not $procs) { $procs = Get-Process | Where-Object { $_.MainWindowTitle -and $_.ProcessName -match '^BIT' -and $_.ProcessName -ne 'BITMenu' } }
"=== 창 목록 ===" | Out-File (Join-Path $out 'uia.txt') -Encoding utf8
Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { "  [$($_.ProcessName)] $($_.MainWindowTitle)" } | Out-File (Join-Path $out 'uia.txt') -Append -Encoding utf8
if (-not $procs) {
  "`n비트플러스 창을 못 찾았습니다. 위 목록에서 비트플러스 창 제목을 알려주세요." | Out-File (Join-Path $out 'uia.txt') -Append -Encoding utf8
  Write-Host "비트플러스 창을 못 찾았습니다. $out\uia.txt 의 창 목록을 확인하세요."
  exit
}
$p = $procs | Select-Object -First 1
$hwnd = $p.MainWindowHandle
Write-Host "대상 창: [$($p.ProcessName)] $($p.MainWindowTitle)"

# 2) UI Automation 트리 읽기 (글자가 나오면 OCR 없이 정확히 읽을 수 있음)
"`n=== UI Automation 요소 ([$($p.ProcessName)] $($p.MainWindowTitle)) ===" | Out-File (Join-Path $out 'uia.txt') -Append -Encoding utf8
try {
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $n = 0
  foreach ($el in $all) {
    $n++
    $name = $el.Current.Name
    $type = $el.Current.ControlType.ProgrammaticName -replace 'ControlType\.',''
    $cls  = $el.Current.ClassName
    $val = ''
    try { $vp = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern); if ($vp) { $val = $vp.Current.Value } } catch {}
    if ($name -or $val) { "$type`t$cls`t$name`t$val" | Out-File (Join-Path $out 'uia.txt') -Append -Encoding utf8 }
  }
  "`n총 요소 수: $n" | Out-File (Join-Path $out 'uia.txt') -Append -Encoding utf8
  Write-Host "UI Automation: 요소 $n 개 → uia.txt"
} catch { "UIA 오류: $_" | Out-File (Join-Path $out 'uia.txt') -Append -Encoding utf8 }

# 3) 창 캡처 (다른 창에 가려져 있어도 PrintWindow로 캡처)
$sig = @'
using System; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
Add-Type -TypeDefinition $sig
$r = New-Object W+RECT; [W]::GetWindowRect($hwnd, [ref]$r) | Out-Null
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc(); [W]::PrintWindow($hwnd, $dc, 2) | Out-Null; $g.ReleaseHdc($dc); $g.Dispose()
$png = Join-Path $out 'window.png'
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Host "창 캡처: $png ($w x $h)"

# 4) Windows 내장 OCR (한국어 언어팩 필요 — 설정 > 시간 및 언어 > 언어 > 한국어)
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
  "=== OCR (언어: $($eng.RecognizerLanguage.DisplayName)) — y x 글자 ===" | Out-File (Join-Path $out 'ocr.txt') -Encoding utf8
  $lines | Out-File (Join-Path $out 'ocr.txt') -Append -Encoding utf8
  Write-Host "OCR: 줄 $($lines.Count) 개 → ocr.txt"
} catch { "OCR 오류: $_" | Out-File (Join-Path $out 'ocr.txt') -Encoding utf8; Write-Host "OCR 오류: $_" }

Write-Host "`n완료. 결과 폴더: $out"
Write-Host "→ uia.txt 와 ocr.txt 를 열어 환자 이름·차트번호가 보이는지 확인하세요."
