# Помощник: одна программа со всеми инструментами ноутбука, по категориям. Сверху — состояние и главная проверка.
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace PCT -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'; [void][PCT.Dpi]::SetProcessDPIAware()
[Windows.Forms.Application]::EnableVisualStyles()
. "$PSScriptRoot\pct-core.ps1"
$Hd = PctDir 'helpers'; $sys32 = [Environment]::GetFolderPath('System'); $ps = "$sys32\WindowsPowerShell\v1.0\powershell.exe"; $con = "$sys32\conhost.exe"
$Tools = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Мои инструменты'
$tabs = [ordered]@{
  'Интернет и блокировки' = @(
    @('Не работает YouTube или Discord', 'сам подберёт новый способ обхода (до 10 мин)', "$Hd\zapret-repick.ps1", 'admin'),
    @('Сайт не открывается', 'проверит любой сайт и откроет его через VPN', "$Hd\site-fix.ps1", 'user'),
    @('Заблокированные сайты', '', "$Hd\smart-proxy.ps1", 'toggle'),
    @('Не работает Telegram', 'переподключит Happ (прокси для Telegram)', "$Hd\happ-connect.ps1", 'gui'),
    @('Какие сайты открываются', 'YouTube, Discord, Telegram, Instagram...', "$Hd\check-sites.ps1", 'user'),
    @('Интернет совсем не работает', 'сбросит сеть и перезапустит Wi-Fi', "$Hd\fix-internet.ps1", 'admin'))
  'Скорость и порядок' = @(
    @('Что тормозит сейчас', 'покажет, что грузит ноутбук, и что делать', "$Hd\perf-now.ps1", 'user'),
    @('Почистить мусор', 'временные файлы; Корзину — только по слову', "$Hd\clean-junk.ps1", 'admin'),
    @('Что запускается с Windows', 'список и отключение лишнего', "$Hd\startup-all.ps1", 'admin'),
    @('Что занимает место на диске', 'самые большие папки, ничего не удаляет', "$Hd\disk-space.ps1", 'user'),
    @('Разобрать Загрузки по папкам', 'картинки, видео, документы — по местам', "$Hd\sort-downloads.ps1", 'user'),
    @('Вернуть Загрузки как было', 'отменяет разбор Загрузок', "$Hd\undo-sort-downloads.ps1", 'user'),
    @('Обновить программы', 'найдёт и поставит новые версии', "$Hd\update-apps.ps1", 'admin'),
    @('Не открываются файлы или меню', 'найдёт и исправит причину', "$Hd\file-repair.ps1", 'admin'))
  'Защита и копии' = @(
    @('Проверка безопасности', 'нет ли вирусов в автозапуске и Загрузках', "$Hd\check-now.ps1", 'user'),
    @('Резервная копия', 'документы и фото на флешку', "$Hd\backup.ps1", 'admin'),
    @('Кто включал камеру и микрофон', 'какие программы и когда снимали или слушали', "$Hd\privacy-check.ps1", 'user'),
    @('Отчёт о батарее', 'износ и состояние батареи', "$Hd\battery-report.ps1", 'user'),
    @('Найти файл (Everything)', 'мгновенный поиск любого файла по имени', 'C:\Program Files\Everything\Everything.exe', 'exe'))
  'Помощь' = @(
    @('Позвать помощь', 'покажет номер AnyDesk и скопирует его', "$Hd\call-help.ps1", 'gui'),
    @('Прочитать подсказки', 'что делает каждая кнопка', (Join-Path $Tools 'ПРОЧИТАЙ МЕНЯ.txt'), 'note'),
    @('Все инструменты', 'папка со всеми ярлыками', $Tools, 'folder'),
    @('Проверить обновления Помощника', 'скачает новую версию, если она вышла', "$Hd\updater.ps1", 'update')) }
function PacOn { Test-Path (PctData 'smart-proxy-on.txt' 'helpers') }
function ToggleText { if (PacOn) { "Заблокированные сайты: ВКЛ ✓`r`nInstagram, X, ChatGPT... идут через Happ сами" } else { "Заблокированные сайты: ВЫКЛ`r`nнажми, чтобы Instagram, X... открывались сами" } }
function StatusText { $z = [bool](Get-Process winws); $h = [bool](Get-NetTCPConnection -State Listen -LocalPort (PctSocksPort))
  $script:allOk = $z -and $h -and (PacOn)
  'YouTube/Discord: ' + $(if ($z) { 'обход работает ✓' } else { 'обход ВЫКЛЮЧЕН ✗' }) + '     Happ: ' + $(if ($h) { 'подключён ✓' } else { 'не подключён ✗' }) + '     Заблокированные сайты: ' + $(if (PacOn) { 'через VPN ✓' } else { 'выкл' }) }
function Paint { $s.Text = StatusText; $s.ForeColor = $(if ($script:allOk) { [Drawing.Color]::DarkGreen } else { [Drawing.Color]::Firebrick }) }
# сбой запуска: отказ от UAC (код 1223) — молча; иначе строка в helper-menu-error.txt и окно с подсказкой
function IsUacCancel($e) { for ($x = $e; $x; $x = $x.InnerException) { if (($x -is [ComponentModel.Win32Exception] -and $x.NativeErrorCode -eq 1223) -or $x.Message -match 'отмен|cancel') { return $true } }; $false }
function RunFail($it, $e) { if (IsUacCancel $e.Exception) { return }
  try { $rp = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($rp)
    [IO.File]::AppendAllText("$rp\helper-menu-error.txt", "$(Get-Date -f s) $($it[0]): $($e.Exception.Message -replace '\s+', ' ')`n", (New-Object Text.UTF8Encoding $false)) } catch {}
  [void][Windows.Forms.MessageBox]::Show($f, 'Не получилось запустить. Вкладка «Помощь» → «Позвать помощь».', 'Помощник') }
# итог updater.ps1 из update-status.json (msg длиннее 44 знаков не влезает в 2 строки кнопки — тогда общий текст, подробности в updates.log): учитываем, только если запись не старше щелчка (допуск 2 с); нет файла, битый или старый — «не получилось»
function UpdateResult($t0) { $fail = "Не получилось проверить обновления`r`nне вышло — позови помощь (вкладка «Помощь»)"; $j = $null; $d = [datetime]::MinValue
  try { $j = [IO.File]::ReadAllText("$(PctDir 'run')\update-status.json", [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop } catch {}
  if (-not $j -or -not [datetime]::TryParseExact("$($j.t)", 's', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d) -or $d -lt $t0.AddSeconds(-2)) { return $fail }
  $m = ("$($j.msg)" -replace '\s+', ' ').Trim(); if (-not $m) { return $fail }
  switch ("$($j.state)") {
    'done'     { "Обновлено до версии $($j.ver)`r`nзакрой меню и открой Помощник снова" }
    'uptodate' { "$m`r`nнажми, чтобы проверить ещё раз" }
    { $_ -in 'error', 'checking' } { $(if ($m.Length -gt 44) { 'Не получилось обновить' } else { $m }) + "`r`nне вышло — позови помощь (вкладка «Помощь»)" }
    default    { $fail } } }
# обновление без окна: кнопка недоступна, пока идёт updater.ps1; после выхода на ней итог из update-status.json (таймер, окно не блокируется)
# U1b: ставит задача с наивысшими правами (helpers\ — только для администраторов); её процесса не видно — конец по итогу в update-status.json не старше щелчка, самое позднее через 10 мин
function UpdateEnded($t0) { $j = $null; $d = [datetime]::MinValue; try { $j = [IO.File]::ReadAllText("$(PctDir 'run')\update-status.json", [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop } catch {}
  ((Get-Date) - $t0).TotalMinutes -ge 10 -or ($j -and "$($j.state)" -in 'done', 'uptodate', 'error' -and [datetime]::TryParseExact("$($j.t)", 's', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d) -and $d -ge $t0.AddSeconds(-2)) }
function UpdateRun($it, $btn) { $t0 = Get-Date; $u = $null; Remove-Item -LiteralPath "$(PctDir 'run')\update-status.json" -Force -ErrorAction SilentlyContinue; if (-not (PctUpdateTask)) { $u = Start-Process $con -ArgumentList "--headless $ps -NoProfile -ExecutionPolicy Bypass -File `"$($it[2])`" -Silent" -PassThru -ErrorAction Stop }
  $btn.Text = "Проверяю обновления…`r`nподожди, это до минуты"; $btn.Enabled = $false
  $tm = New-Object Windows.Forms.Timer; $tm.Interval = 500; $tm.Tag = @($u, $btn, $t0)
  $tm.Add_Tick({ param($t, $ea) $z = $t.Tag; if ($(if ($z[0]) { $z[0].HasExited } else { UpdateEnded $z[2] })) { $t.Stop(); $t.Dispose(); $z[1].Text = UpdateResult $z[2]; $z[1].Enabled = $true } }); $tm.Start() }
function Run($it, $btn) {
  $a = "-NoProfile -ExecutionPolicy Bypass -File `"$($it[2])`""
  try { switch ($it[3]) {
      'admin'  { Start-Process $ps -ArgumentList $a -Verb RunAs -ErrorAction Stop }
      'user'   { Start-Process $ps -ArgumentList $a -ErrorAction Stop }
      'gui'    { Start-Process $con -ArgumentList "--headless $ps $a" -ErrorAction Stop }
      'exe'    { Start-Process $it[2] -ErrorAction Stop }
      'note'   { Start-Process notepad.exe -ArgumentList "`"$($it[2])`"" -ErrorAction Stop }
      'folder' { Start-Process explorer.exe -ArgumentList "`"$($it[2])`"" -ErrorAction Stop }
      'update' { UpdateRun $it $btn }
      'toggle' { if (PacOn) { & $it[2] -Off } else { & $it[2] -On }; $btn.Text = ToggleText; Paint } } } catch { RunFail $it $_ } }
function Btn($it, $x, $y, $w, $h, $color, $parent) {
  $b = New-Object Windows.Forms.Button; $b.Text = $(if ($it[3] -eq 'toggle') { ToggleText } else { "$($it[0])`r`n$($it[1])" }); $b.TextAlign = 'MiddleLeft'
  $b.Padding = New-Object Windows.Forms.Padding([int](10 * $k), 0, 0, 0); $b.SetBounds([int]($x * $k), [int]($y * $k), [int]($w * $k), [int]($h * $k))
  $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = [Drawing.Color]::Silver; $b.BackColor = $color; $b.Tag = $it
  $b.Add_Click({ param($src, $e) Run $src.Tag $src }); $parent.Controls.Add($b) }
$f = New-Object Windows.Forms.Form; $f.Text = 'Помощник'; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false
$f.BackColor = [Drawing.Color]::White; $f.Font = New-Object Drawing.Font('Segoe UI', 11)
$k = $f.CreateGraphics().DpiX / 96; $bw = 384; $bh = 64; $gap = 10; $W = 2 * $bw + $gap; $rows = [int][math]::Ceiling(($tabs.Values | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum / 2)
$s = New-Object Windows.Forms.Label; $s.AutoSize = $false; $s.SetBounds([int](16 * $k), [int](10 * $k), [int]($W * $k), [int](28 * $k))
$s.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold); $f.Controls.Add($s); Paint
Btn @('Проверить ноутбук', 'найдёт, что не так, и скажет, что делать (начни отсюда)', "$Hd\system-health.ps1", 'admin') 16 42 $W 60 ([Drawing.Color]::FromArgb(210, 232, 255)) $f
$tc = New-Object Windows.Forms.TabControl; $tc.SetBounds([int](16 * $k), [int](114 * $k), [int](($W + 8) * $k), [int](($rows * ($bh + $gap) + 50) * $k)); $tc.Padding = New-Object Drawing.Point([int](12 * $k), [int](6 * $k))
foreach ($name in $tabs.Keys) { $tp = New-Object Windows.Forms.TabPage; $tp.Text = $name; $tp.BackColor = [Drawing.Color]::White; $list = $tabs[$name]
  for ($i = 0; $i -lt $list.Count; $i++) { $it = $list[$i]
    $c = $(if ($it[3] -eq 'toggle') { [Drawing.Color]::FromArgb(225, 240, 255) } elseif ($it[3] -eq 'gui' -and $it[0] -eq 'Позвать помощь') { [Drawing.Color]::FromArgb(255, 243, 220) } else { [Drawing.Color]::FromArgb(246, 246, 246) })
    Btn $it (($i % 2) * ($bw + $gap)) (8 + [math]::Floor($i / 2) * ($bh + $gap)) $bw $bh $c $tp }
  [void]$tc.TabPages.Add($tp) }
$f.Controls.Add($tc)
$n = New-Object Windows.Forms.Label; $n.AutoSize = $false; $n.ForeColor = [Drawing.Color]::DimGray
$n.Text = 'Windows спросит разрешение — нажми «Да». Не получается — вкладка «Помощь» → «Позвать помощь».'
$n.SetBounds([int](16 * $k), [int]((114 + $rows * ($bh + $gap) + 58) * $k), [int]($W * $k), [int](26 * $k)); $f.Controls.Add($n)
$f.ClientSize = New-Object Drawing.Size([int](($W + 40) * $k), [int]((114 + $rows * ($bh + $gap) + 92) * $k))
[void]$f.ShowDialog()