$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace PCT -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'; [void][PCT.Dpi]::SetProcessDPIAware()
$exe = Get-Content "$(PctDir 'helpers')\anydesk-path.txt" -Encoding UTF8 -TotalCount 1
if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
  $exe = @("${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe", "$env:ProgramFiles\AnyDesk\AnyDesk.exe") + @(Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Recurse -Depth 3 -Filter 'AnyDesk*.exe' | ForEach-Object FullName) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1 }
if ($exe -and -not (Get-Process AnyDesk)) { Start-Process -FilePath $exe }
$id = $null
foreach ($c in "$env:APPDATA\AnyDesk\system.conf", "$env:ProgramData\AnyDesk\system.conf") {
  $m = Select-String -LiteralPath $c -Pattern '^ad\.anynet\.id=(\d+)' | Select-Object -First 1; if ($m) { $id = $m.Matches[0].Groups[1].Value; break } }
# В system.conf нет — спрашиваю AnyDesk.exe --get-id, не дольше 5 с
if (-not $id -and $exe) { $f = Join-Path $env:TEMP ('pct-adid-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
  try { $p = Start-Process -FilePath $exe -ArgumentList '--get-id' -RedirectStandardOutput $f -WindowStyle Hidden -PassThru -ErrorAction Stop
    if ($p.WaitForExit(5000)) { $m = [regex]::Match("$(Get-Content -LiteralPath $f -Raw)", '\d{6,}'); if ($m.Success) { $id = $m.Value } } else { $p.Kill() } } catch {}
  Remove-Item -LiteralPath $f -Force }
if ($id) { Set-Clipboard -Value $id }
$f = New-Object Windows.Forms.Form; $f.Text = 'Позвать помощь'; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
$f.BackColor = [Drawing.Color]::White; $f.Font = New-Object Drawing.Font('Segoe UI', 12); $f.TopMost = $true
$k = $f.CreateGraphics().DpiX / 96
function Lbl($t, $y, $h, $size, $style, $color) { $l = New-Object Windows.Forms.Label; $l.Text = $t; $l.AutoSize = $false; $l.TextAlign = 'MiddleCenter'
  $l.Font = New-Object Drawing.Font('Segoe UI', ([single]$size), ([Drawing.FontStyle]$style)); $l.ForeColor = $color; $l.SetBounds([int](16 * $k), [int]($y * $k), [int](528 * $k), [int]($h * $k)); $f.Controls.Add($l) }
if ($id) {
  Lbl 'Скажи или отправь этот номер тому, кто помогает:' 12 40 12 'Regular' ([Drawing.Color]::Black)
  Lbl ($id -replace '(\d)(?=(\d{3})+$)', '$1 ') 54 80 30 'Bold' ([Drawing.Color]::FromArgb(0, 90, 170))
  Lbl 'Номер уже скопирован: вставь его в Telegram (Ctrl+V) и отправь.' 138 52 11 'Regular' ([Drawing.Color]::DarkGreen)
} else {
  Lbl 'Номер не нашёлся автоматически.' 12 40 12 'Bold' ([Drawing.Color]::Black)
  Lbl $(if ($exe) { 'Он написан в окне AnyDesk слева сверху (9–10 цифр).' } else { 'AnyDesk не найден на ноутбуке.' }) 54 80 12 'Regular' ([Drawing.Color]::Black) }
Lbl 'Когда AnyDesk спросит про подключение — нажми «Принять», только если сама звала помощь.' 192 52 10 'Regular' ([Drawing.Color]::DimGray)
$b1 = New-Object Windows.Forms.Button; $b1.Text = 'Скопировать ещё раз'; $b1.SetBounds([int](60 * $k), [int](256 * $k), [int](220 * $k), [int](44 * $k)); $b1.Enabled = [bool]$id
$b1.Add_Click({ Set-Clipboard -Value $id; $b1.Text = 'Скопировано ✓' }); $f.Controls.Add($b1)
$b2 = New-Object Windows.Forms.Button; $b2.Text = 'Закрыть'; $b2.SetBounds([int](300 * $k), [int](256 * $k), [int](200 * $k), [int](44 * $k)); $b2.Add_Click({ $f.Close() }); $f.Controls.Add($b2)
$f.ClientSize = New-Object Drawing.Size([int](560 * $k), [int](316 * $k)); $f.AcceptButton = $b2
[void]$f.ShowDialog()