# «Почему тормозит»: ищу главное узкое место — диск, память, процессор под нагрузкой (5 с), драйвер видеокарты, «Целостность памяти», расширения браузеров, визуальные эффекты — и говорю, что сделать, с числами.
# Меняю только визуальные эффекты — с вопросом и бэкапом; остальное только читаю. Итоги — в %LOCALAPPDATA%\Pomoshnik\revive.json (для общей оценки 9al).
# -Undo — вернуть эффекты как было. -Lib — только задать функции (тесты). PCT_REVIVE_FAKE=<файл JSON> — подмена для проверки: laptop, ac; disk {media HDD|SSD, bus, sizeGB, freeGB, trim};
# ram {sticksMB [], slots, totalMB, freeMB}; cpu {name, base, perf}; gpu [{name, ven, date, basic}]; vbs {hvci, mbec — нет: по имени процессора}; browsers {Chrome: число, …}; fx [{P, N, K, V}] — реестр эффектов
param([switch]$Undo, [switch]$Lib)
if (-not $Lib) { $ErrorActionPreference = 'SilentlyContinue'; $Host.UI.RawUI.WindowTitle = 'Почему тормозит' }
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
. "$PSScriptRoot\pct-core.ps1"
$ru = [Globalization.CultureInfo]'ru-RU'
function Jr($t) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::AppendAllText("$d\revive.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $t`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
function Yes($q) { $a = "$(Read-Host "$q (д/н)")".Trim(); Jr "вопрос: $q — ответ: $a"; $a -match '^(?i)(д|да|y|yes|l)' }
# Вопрос: заголовок и что делает — одна строка, совет — вторая, потом (д/н). Окно показывает две последние строки
function Ask2($head, $what, $rec, $q) { Write-Host "`n$head — $what" -ForegroundColor White; Write-Host $rec; Yes $q }
function Up([string]$s) { if ($s) { $s.Substring(0, 1).ToUpper() + $s.Substring(1) } }
function Gb([double]$mb) { ($mb / 1024).ToString('0.#', $ru) }

# ---------- Факты: настоящие или из подмены ----------
function RvFake { if ($env:PCT_REVIVE_FAKE) { [IO.File]::ReadAllText($env:PCT_REVIVE_FAKE) | ConvertFrom-Json } }
function RvFakeSave($F) { [IO.File]::WriteAllText($env:PCT_REVIVE_FAKE, ($F | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false)) }
# Тип: есть батарея — ноутбук; AC — от сети (BatteryStatus 2 — сеть, 3 — заряжена, 6–9 — заряжается)
function RvDevice { $f = RvFake; if ($f) { return [pscustomobject]@{ Laptop = [bool]$f.laptop; AC = [bool]$f.ac } }
  $b = @(Get-CimInstance Win32_Battery); [pscustomobject]@{ Laptop = [bool]$b; AC = (-not $b) -or [bool]($b | Where-Object { $_.BatteryStatus -in 2, 3, 6, 7, 8, 9 }) } }
# Диск с Windows: тип (MediaType; неизвестен — NVMe это SSD, обороты есть — HDD), шина, место, TRIM (реестр DisableDeleteNotification: 0 — вкл; прав не нужно, в отличие от fsutil)
function RvDisk { $f = RvFake; if ($f) { $d = $f.disk; return [pscustomobject]@{ Media = "$($d.media)"; Bus = "$($d.bus)"; SizeGB = [double]$d.sizeGB; FreeGB = [double]$d.freeGB; Trim = $d.trim } }
  $l = "$env:SystemDrive".TrimEnd(':'); $n = (Get-Partition -DriveLetter $l).DiskNumber; $pd = @(Get-PhysicalDisk | Where-Object { $null -ne $n -and "$($_.DeviceId)" -eq "$n" })[0]
  $m = "$($pd.MediaType)"; $bus = "$($pd.BusType)"
  if ($m -notin 'HDD', 'SSD') { $m = $(if ($bus -eq 'NVMe' -or $m -eq 'SCM') { 'SSD' } elseif ($pd.SpindleSpeed -gt 0 -and $pd.SpindleSpeed -lt [uint32]::MaxValue) { 'HDD' } else { '' }) }
  $v = Get-Volume -DriveLetter $l; $t = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem').DisableDeleteNotification
  [pscustomobject]@{ Media = $m; Bus = $bus; SizeGB = [math]::Round($v.Size / 1GB, 1); FreeGB = [math]::Round($v.SizeRemaining / 1GB, 1); Trim = $(if ($null -ne $t) { $t -eq 0 }) } }
# Память: планки (МБ), слоты системной памяти, видимый объём и свободно (МБ)
function RvRam { $f = RvFake; if ($f) { $r = $f.ram; return [pscustomobject]@{ Sticks = @($r.sticksMB | ForEach-Object { [double]$_ }); Slots = [int]$r.slots; TotalMB = [double]$r.totalMB; FreeMB = [double]$r.freeMB } }
  $s = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object { [double]$_.Capacity / 1MB }); $sl = 0; foreach ($a in @(Get-CimInstance Win32_PhysicalMemoryArray | Where-Object { $_.Use -eq 3 })) { $sl += [int]$a.MemoryDevices }
  $o = Get-CimInstance Win32_OperatingSystem; [pscustomobject]@{ Sticks = $s; Slots = $sl; TotalMB = [double]$o.TotalVisibleMemorySize / 1KB; FreeMB = [double]$o.FreePhysicalMemory / 1KB } }
function RvCpu { $f = RvFake; if ($f) { return [pscustomobject]@{ Name = "$($f.cpu.name)"; Base = [int]$f.cpu.base; Perf = $null } }
  $c = @(Get-CimInstance Win32_Processor)[0]; [pscustomobject]@{ Name = "$($c.Name)".Trim(); Base = [int]$c.MaxClockSpeed; Perf = $null } }
# Нагрузка на все логические процессоры, потоки ниже обычного приоритета — окно и мышь отвечают
$LoadCs = @'
using System; using System.Threading; using System.Diagnostics;
public static class PctLoad { static Thread[] T;
  public static void Start(int ms) { int n = Environment.ProcessorCount; T = new Thread[n]; var sw = Stopwatch.StartNew();
    for (int i = 0; i < n; i++) { T[i] = new Thread(() => { double x = 1; while (sw.ElapsedMilliseconds < ms) { for (int k = 0; k < 100000; k++) x = Math.Sqrt(x + k); } }); T[i].IsBackground = true; T[i].Priority = ThreadPriority.BelowNormal; T[i].Start(); } }
  public static void Wait() { if (T != null) foreach (var t in T) t.Join(); } }
'@
# Частота под нагрузкой 5 с: «% Processor Performance» (_Total) — доля базовой частоты, по сырым счётчикам WMI между 1,2 и 4,7 с нагрузки (Get-Counter не подходит: имена счётчиков переведены). → % или $null
function RvLoad { $f = RvFake; if ($f) { return $(if ($null -ne $f.cpu.perf) { [double]$f.cpu.perf }) }
  try { if (-not ('PctLoad' -as [type])) { Add-Type -TypeDefinition $LoadCs -ErrorAction Stop } } catch { Jr "нагрузка не запустилась: $($_.Exception.Message)"; return }
  $q = { Get-CimInstance Win32_PerfRawData_Counters_ProcessorInformation -Filter "Name='_Total'" }; $null = & $q
  [PctLoad]::Start(5000); try { Start-Sleep -Milliseconds 1200; $a = & $q; Start-Sleep -Milliseconds 3300; $b = & $q } finally { [PctLoad]::Wait() }
  if (-not $a -or -not $b) { Jr 'счётчик частоты не прочитал'; return }; $db = [double]$b.PercentProcessorPerformance_Base - [double]$a.PercentProcessorPerformance_Base
  if ($db -le 0) { Jr 'счётчик частоты не изменился'; return }; [math]::Round(([double]$b.PercentProcessorPerformance - [double]$a.PercentProcessorPerformance) / $db) }
# Видеокарты на шине PCI (без виртуальных): название, код производителя, дата драйвера, «Базовый видеоадаптер» — драйвера нет
function RvGpu { $f = RvFake; if ($f) { return @($f.gpu | ForEach-Object { [pscustomobject]@{ N = "$($_.name)"; Ven = "$($_.ven)"; Date = $(if ($_.date) { [datetime]"$($_.date)" }); Basic = [bool]$_.basic } }) }
  foreach ($v in @(Get-CimInstance Win32_VideoController | Where-Object { "$($_.PNPDeviceID)" -match '^PCI\\' })) {
    [pscustomobject]@{ N = "$($v.Name)"; Ven = $(if ("$($v.PNPDeviceID)" -match 'VEN_([0-9A-Fa-f]{4})') { $Matches[1].ToUpper() }); Date = $v.DriverDate; Basic = "$($v.Name)" -match '(?i)basic display|базовый видеоадаптер' -or "$($v.InfFilename)" -eq 'display.inf' } } }
# MBEC (ускорение «Целостности памяти») по имени процессора: Intel с 7-го поколения, AMD с Zen 2. Не знаю — $null
function RvMbec([string]$N) {
  if ($N -match '(?i)Core\(TM\)\s*Ultra|Core Ultra|Ryzen\s+AI') { return $true }
  if ($N -match '(?i)\bi[3579]\s+CPU\b') { return $false }
  if ($N -match '(?i)\bi[3579]-(\d{3,5})') { $d = $Matches[1]; $g = $(if ($d.Length -eq 5 -or ($d.Length -eq 4 -and $d[0] -eq '1')) { [int]$d.Substring(0, 2) } elseif ($d.Length -eq 4) { [int]"$($d[0])" } else { 1 }); return $g -ge 7 }
  if ($N -match '(?i)Ryzen\s+(?:\d|Threadripper)\s+(?:PRO\s+)?(\d)\d{3}([A-Z]*)') { $s = [int]$Matches[1]; if ($s -le 2) { return $false }; if ($s -eq 3) { return $Matches[2] -notmatch '[GUH]' }; return $true }
  if ($N -match '(?i)\b(FX|A\d{1,2})-\d') { return $false }; $null }
# «Целостность памяти»: работает ли (SecurityServicesRunning 2), MBEC — по Windows (AvailableSecurityProperties 7, если гипервизор доступен), иначе по имени процессора
function RvVbs([string]$Cpu) { $f = RvFake; if ($f) { return [pscustomobject]@{ Hvci = $f.vbs.hvci; Mbec = $(if ($null -ne $f.vbs.mbec) { [bool]$f.vbs.mbec } else { RvMbec $Cpu }) } }
  $g = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard Win32_DeviceGuard
  if (-not $g) { $h = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity').Enabled; return [pscustomobject]@{ Hvci = $(if ($null -ne $h) { $h -eq 1 }); Mbec = RvMbec $Cpu } }
  $ap = @($g.AvailableSecurityProperties); [pscustomobject]@{ Hvci = @($g.SecurityServicesRunning) -contains 2; Mbec = $(if ($ap -contains 1) { $ap -contains 7 } else { RvMbec $Cpu }) } }
# Расширения: по браузеру — больше всего в одном профиле (папки Extensions\<32 буквы a–p>). Только счёт, без имён
function RvBrowsers { $f = RvFake; $h = [ordered]@{}; if ($f) { foreach ($p in @($f.browsers.PSObject.Properties)) { $h[$p.Name] = [int]$p.Value }; return $h }
  foreach ($b in @(@('Chrome', 'Google\Chrome'), @('Edge', 'Microsoft\Edge'), @('Яндекс', 'Yandex\YandexBrowser'))) { $u = Join-Path $env:LOCALAPPDATA "$($b[1])\User Data"; if (-not (Test-Path -LiteralPath $u)) { continue }; $m = 0
    foreach ($p in @(Get-ChildItem -LiteralPath $u -Directory)) { $e = Join-Path $p.FullName 'Extensions'; if (Test-Path -LiteralPath $e) { $c = @(Get-ChildItem -LiteralPath $e -Directory | Where-Object { $_.Name -match '^[a-p]{32}$' }).Count; if ($c -gt $m) { $m = $c } } }; $h[$b[0]] = $m }; $h }

# ---------- Визуальные эффекты: «Наилучшее быстродействие» (Свойства системы → Быстродействие), сглаживание шрифтов оставляю ----------
# Значения HKCU и цель. UserPreferencesMask — снимаю только биты эффектов ($FxOff: анимация меню, списков, затухание, тени курсора и окон), остальные (подсказки клавиатуры, отслеживание окна) не трогаю
function RvFxKeys { $a = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; $d = 'HKCU:\Control Panel\Desktop'; $w = 'HKCU:\Software\Microsoft\Windows\DWM'; @(
  , @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects', 'VisualFXSetting', 'DWord', 3)   # 3 — «особые эффекты»
  , @($d, 'UserPreferencesMask', 'Binary', ''); , @($d, 'DragFullWindows', 'String', '0'); , @($d, 'FontSmoothing', 'String', '2')   # содержимое окна при перетаскивании — выкл, сглаживание шрифтов — вкл
  , @("$d\WindowMetrics", 'MinAnimate', 'String', '0'); , @($a, 'TaskbarAnimations', 'DWord', 0); , @($a, 'ListviewAlphaSelect', 'DWord', 0); , @($a, 'ListviewShadow', 'DWord', 0)
  , @($a, 'IconsOnly', 'DWord', 1); , @($w, 'EnableAeroPeek', 'DWord', 0); , @($w, 'AlwaysHibernateThumbnails', 'DWord', 0)) }   # IconsOnly 1 — значки вместо эскизов
$FxOff = [byte[]](0x0E, 0x2C, 0x04, 0, 0x02, 0, 0, 0); $FxAll = '9E-3E-07-80-12-00-00-00'
function RvHex([byte[]]$B) { (@($B) | ForEach-Object { $_.ToString('X2') }) -join '-' }
function RvBytes([string]$H) { [byte[]]@($H -split '-' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }) }
# Текущие значения: P — ключ, N — имя, K — тип (настоящий, если значение есть), V — значение (Binary — «XX-XX»), E — есть ли
function RvFxRead { $f = RvFake; foreach ($k in RvFxKeys) {
    if ($f) { $x = @($f.fx | Where-Object { $_.P -eq $k[0] -and $_.N -eq $k[1] })[0]; [pscustomobject]@{ P = $k[0]; N = $k[1]; K = $(if ($x) { "$($x.K)" } else { $k[2] }); V = $(if ($x) { $x.V }); E = [bool]$x }; continue }
    $rk = Get-Item -LiteralPath $k[0]; $e = $rk -and @($rk.GetValueNames()) -contains $k[1]; $kd = $k[2]; $v = $null
    if ($e) { $kd = "$($rk.GetValueKind($k[1]))"; $v = $rk.GetValue($k[1], $null, 'DoNotExpandEnvironmentNames'); $v = $(if ($kd -eq 'Binary') { RvHex $v } elseif ($kd -eq 'DWord') { [int]$v } else { "$v" }) }
    [pscustomobject]@{ P = $k[0]; N = $k[1]; K = $kd; V = $v; E = $e } } }
function RvFxTarget($Cur) { foreach ($c in $Cur) { $k = @(RvFxKeys | Where-Object { $_[1] -eq $c.N })[0]; $v = $k[3]
    if ($k[2] -eq 'Binary') { $b = RvBytes $(if ($c.E -and $c.V) { "$($c.V)" } else { $FxAll }); for ($i = 0; $i -lt [math]::Min($b.Count, $FxOff.Count); $i++) { $b[$i] = $b[$i] -band (0xFF -bxor $FxOff[$i]) }; $v = RvHex $b }
    [pscustomobject]@{ P = $c.P; N = $c.N; K = $k[2]; V = $v; E = $true } } }
function RvFxSame($A, $B) { $s = { param($x) (@($x | ForEach-Object { "$($_.N)=$([bool]$_.E):$($_.V)" }) -join '|') }; (& $s $A) -eq (& $s $B) }
# Уже быстро: Windows «наилучшее быстродействие» (2) или все значения как у цели
function RvFxPerf($Cur) { "$(@($Cur | Where-Object { $_.N -eq 'VisualFXSetting' -and $_.E })[0].V)" -eq '2' -or (RvFxSame $Cur @(RvFxTarget $Cur)) }
# Запись: значение есть — с его типом; нет (E false) — удалить. → $true, если всё записалось
function RvFxWrite($Items) { $f = RvFake
  if ($f) { $f.fx = @($Items | Where-Object { $_.E } | ForEach-Object { [pscustomobject]@{ P = $_.P; N = $_.N; K = $_.K; V = $_.V } }); RvFakeSave $f; return $true }
  $ok = $true; foreach ($x in $Items) { try {
      if (-not $x.E) { $rk = Get-Item -LiteralPath $x.P; if ($rk -and @($rk.GetValueNames()) -contains $x.N) { Remove-ItemProperty -LiteralPath $x.P -Name $x.N -ErrorAction Stop }; continue }
      if (-not (Test-Path -LiteralPath $x.P)) { [void](New-Item -Path $x.P -Force -ErrorAction Stop) }
      $v = $(if ($x.K -eq 'Binary') { RvBytes "$($x.V)" } elseif ($x.K -eq 'DWord') { [int]$x.V } else { "$($x.V)" })
      [void](New-ItemProperty -LiteralPath $x.P -Name $x.N -PropertyType $x.K -Value $v -Force -ErrorAction Stop) } catch { $ok = $false; Jr "эффекты: не записал $($x.N): $($_.Exception.Message)" } }; $ok }
# Сразу на экране (без подмены): те же значения через SystemParametersInfo без записи в профиль (реестр уже записан); панель задач и Проводник — после перезагрузки
function RvFxLive($Items) { if (RvFake) { return }
  try { if (-not ('Pct.RvSpi' -as [type])) { Add-Type -Namespace Pct -Name RvSpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint d); [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")] public static extern bool SpiA(uint a, uint b, int[] c, uint d);' -ErrorAction Stop }
    $g = @{}; foreach ($x in $Items) { if ($x.E) { $g[$x.N] = "$($x.V)" } }; $m = RvBytes $(if ($g['UserPreferencesMask']) { $g['UserPreferencesMask'] } else { $FxAll })
    # Биты маски → SPI_SETMENUANIMATION, COMBOBOX, LISTBOXSMOOTHSCROLLING, SELECTIONFADE, TOOLTIPANIMATION, CURSORSHADOW, DROPSHADOW (значение — в pvParam)
    foreach ($s in @(@(0x1003, 0, 2), @(0x1005, 0, 4), @(0x1007, 0, 8), @(0x1015, 1, 4), @(0x1017, 1, 8), @(0x101B, 1, 0x20), @(0x1025, 2, 4))) { [void][Pct.RvSpi]::SystemParametersInfo($s[0], 0, [IntPtr][int][bool]($m.Count -gt $s[1] -and ($m[$s[1]] -band $s[2])), 2) }
    $dv = { param($n, $d) if ($g.ContainsKey($n)) { $g[$n] } else { $d } }
    [void][Pct.RvSpi]::SystemParametersInfo(0x0025, [uint32]((& $dv 'DragFullWindows' '1') -eq '1'), [IntPtr]::Zero, 2)   # SPI_SETDRAGFULLWINDOWS
    [void][Pct.RvSpi]::SystemParametersInfo(0x004B, [uint32]((& $dv 'FontSmoothing' '2') -eq '2'), [IntPtr]::Zero, 2)     # SPI_SETFONTSMOOTHING
    [void][Pct.RvSpi]::SpiA(0x0049, 8, [int[]]@(8, [int]((& $dv 'MinAnimate' '1') -ne '0')), 2) } catch { Jr "эффекты сразу не применились: $($_.Exception.Message)" } }   # SPI_SETANIMATION
# Бэкап: %LOCALAPPDATA%\Pomoshnik\revive-backup.json — значения до (fx). Повторное изменение первое «до» не перезаписывает
function RvBackupPath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\revive-backup.json' }
function RvBackup { try { $o = [IO.File]::ReadAllText((RvBackupPath)) | ConvertFrom-Json -ErrorAction Stop; if ($o -is [Management.Automation.PSCustomObject]) { $o } } catch {} }
function RvBackupSave($B) { $p = RvBackupPath; [void][IO.Directory]::CreateDirectory((Split-Path $p)); $t = "$p.tmp"
  [IO.File]::WriteAllText($t, ($B | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)); if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) } }
function RvBackupStart($Cur) { $b = RvBackup; if ($b) { return $b }; $b = [pscustomobject]@{ schema = 1; created = (Get-Date).ToString('s'); fx = @($Cur) }; RvBackupSave $b; $b }
# Откат: записать значения до и перечитать. Совпало — бэкап в revive-backup.<время>.done.json, иначе остаётся. → Ok, Bad — что не вернулось, Items — что сейчас; $null — бэкапа нет
function RvFxUndo { $b = RvBackup; if (-not $b) { return }; [void](RvFxWrite @($b.fx)); $now = @(RvFxRead)
  $bad = @(foreach ($x in @($b.fx)) { $y = @($now | Where-Object { $_.P -eq $x.P -and $_.N -eq $x.N })[0]; if (-not $y -or "$([bool]$y.E):$($y.V)" -ne "$([bool]$x.E):$($x.V)") { $x.N } })
  if (-not $bad) { $p = RvBackupPath; $t = Get-Date -Format 'yyyyMMdd-HHmmss-fff'; $a = $p -replace '\.json$', ".$t.done.json"; for ($i = 1; [IO.File]::Exists($a); $i++) { $a = $p -replace '\.json$', ".$t-$i.done.json" }; [IO.File]::Move($p, $a) }
  [pscustomobject]@{ Ok = -not $bad; Bad = $bad; Items = $now } }

# ---------- Выводы: из фактов → пункты {Check, S — коротко для шага, Found, Value, Advice, W — вес, Level main|warn|ok|skip}; главная причина — мешает с наибольшим весом ----------
# Вес: HDD 100, застрявшая частота 90, нет драйвера видео 80, мало памяти 70, полный диск 60/50, одна планка 45, занятая память 40, «Целостность памяти» без MBEC 40, старый драйвер 35, TRIM 30, расширения 20, эффекты 15
function RvUrl([string]$V) { switch ($V) { '8086' { 'https://www.intel.com/content/www/us/en/support/detect.html' } '10DE' { 'https://www.nvidia.com/drivers' } '1002' { 'https://www.amd.com/en/support/download/drivers.html' } default { '' } } }
function RvYr([int]$Y) { if ($Y % 10 -eq 1 -and $Y % 100 -ne 11) { 'год' } elseif ($Y % 10 -in 2, 3, 4 -and $Y % 100 -notin 12, 13, 14) { 'года' } else { 'лет' } }
function RvCn([string]$N) { ($N -replace '\((R|TM)\)', '' -replace '\s+(CPU\s+)?@.*$', '' -replace '\s+\d+-Core Processor$', '' -replace '\s{2,}', ' ').Trim() }
function RvJudge($F) { $o = New-Object Collections.ArrayList; $dv = $(if ($F.Laptop) { 'ноутбук' } else { 'компьютер' }); $small = $false
  $add = { param($c, $s, $f, $v, $a, $w, $l) [void]$o.Add([pscustomobject]@{ Check = $c; S = $s; Found = $f; Value = $v; Advice = $a; W = $w; Level = $(if ($l) { $l } elseif ($w) { 'warn' } else { 'ok' }); Ord = $o.Count }) }
  # Диск
  $d = $F.Disk; $n0 = $o.Count
  if ($d -and $d.Media) { $u = $(if ($d.SizeGB -gt 0) { [int][math]::Round(100 - 100 * $d.FreeGB / $d.SizeGB) } else { 0 })
    if ($d.Media -eq 'HDD') { & $add 'disk' 'Windows на HDD' 'Windows стоит на жёстком диске (HDD)' $u "Поставь SSD вместо жёсткого диска и перенеси на него Windows: $dv будет включаться и открывать программы в несколько раз быстрее. Это главное, что его оживит." 100 }
    if ($u -ge 90) { & $add 'disk' "диск заполнен на $u %" "диск с Windows заполнен на $u %" $u "Освободи место: «Уборка» и «Что занимает место». Свободно $(([double]$d.FreeGB).ToString('0.#', $ru)) ГБ из $(([double]$d.SizeGB).ToString('0', $ru)): когда диск почти полон, Windows и обновления работают медленнее." $(if ($d.Media -eq 'SSD') { 60 } else { 50 }) }
    if ($d.Media -eq 'SSD' -and $d.Trim -eq $false) { & $add 'disk' 'TRIM выключен' 'TRIM для SSD выключен' 0 'Без TRIM SSD со временем замедляется. Позови помощь: TRIM включает одна команда от администратора.' 30 }
    if ($o.Count -eq $n0) { & $add 'disk' "$(if ($d.Media -eq 'HDD') { 'HDD' } else { 'SSD' }), занято $u %" "Windows на $(if ($d.Media -eq 'HDD') { 'HDD' } else { 'SSD' })$(if ($d.Bus) { " ($($d.Bus))" }), занято $u %" $u '' 0 } }
  else { & $add 'disk' 'тип диска не определил' 'тип диска с Windows не определил' $null '' 0 'skip' }
  # Память
  $r = $F.Ram; $n0 = $o.Count
  if ($r -and ($r.TotalMB -gt 0 -or @($r.Sticks).Count)) { $st = @($r.Sticks | Where-Object { $_ -gt 0 }); $tot = $(if ($st) { ($st | Measure-Object -Sum).Sum } else { $r.TotalMB }); $gb = Gb $tot; $n = $st.Count; $fs = [math]::Max(0, $r.Slots - $n)
    $u = $(if ($r.TotalMB -gt 0) { [int][math]::Round(100 - 100 * $r.FreeMB / $r.TotalMB) } else { 0 }); $small = $tot -le 4608
    if ($small) { $a = $(if ($n -eq 1 -and $fs) { "Поставь вторую такую же планку ($(Gb $st[0]) ГБ) в свободный слот: памяти станет вдвое больше, и включится двухканальный режим — память и встроенная графика станут заметно быстрее." } elseif ($fs) { 'Добавь планку в свободный слот, чтобы памяти стало хотя бы 8 ГБ.' } else { 'Свободного слота нет: чтобы памяти стало хотя бы 8 ГБ, замени планку на более ёмкую. Если память впаяна — держи открытыми меньше программ и вкладок.' })
      & $add 'ram' "памяти $gb ГБ — мало" "памяти $gb ГБ (занято $u %) — мало для Windows и браузера" ([double]$gb.Replace(',', '.')) $a 70 }
    elseif ($n -eq 1 -and $fs) { & $add 'ram' "одна планка из $($r.Slots) слотов" "одна планка памяти ($gb ГБ), свободных слотов: $fs" ([double]$gb.Replace(',', '.')) "Поставь вторую такую же планку ($gb ГБ) в свободный слот: включится двухканальный режим, и память со встроенной графикой станут заметно быстрее." 45 }
    if (-not $small -and $u -ge 80) { & $add 'ram' "памяти занято $u %" "занято $u % памяти ещё до проверки" $u 'Закрой программы, которыми не пользуешься, и посмотри «Что запускается с Windows».' 40 }
    if ($o.Count -eq $n0) { & $add 'ram' "$gb ГБ, занято $u %" "памяти $gb ГБ$(if ($n) { ", планок: $n$(if ($r.Slots -ge $n) { " из $($r.Slots)" })" }), занято $u %" ([double]$gb.Replace(',', '.')) '' 0 } }
  else { & $add 'ram' 'память не прочитал' 'память не прочитал' $null '' 0 'skip' }
  # Процессор под нагрузкой: ниже 60 % базовой частоты — «застрял»
  $c = $F.Cpu
  if ($c -and $null -ne $c.Perf) { $p = [int]$c.Perf; $mhz = $(if ($c.Base) { " ($([math]::Round($c.Base * $p / 100)) из $($c.Base) МГц)" })
    if ($p -lt 60) { $a = $(if ($F.Laptop) { 'Процессор «застрял» на низкой частоте. Проверь: пыль и перегрев — почистить вентилятор и заменить термопасту в сервисе; зарядку — родная ли она и нужной ли мощности; износ батареи — «Отчёт о батарее».' } else { 'Процессор «застрял» на низкой частоте. Проверь: пыль и перегрев — почистить кулер и заменить термопасту; блок питания.' })
      if ($F.Laptop -and -not $F.AC) { $a += " Сейчас $dv от батареи: подключи зарядку и запусти проверку ещё раз." }
      & $add 'cpu' "процессор застрял на $p %" "под нагрузкой процессор держит $p % базовой частоты$mhz" $p "$a Если включена экономия питания — нажми «Энергосбережение»." 90 }
    else { & $add 'cpu' "$p % базовой частоты" "под нагрузкой — $p % базовой частоты$mhz" $p '' 0 } }
  else { & $add 'cpu' 'частоту не замерил' 'частоту под нагрузкой не замерил' $null '' 0 'skip' }
  # Видеокарта: нет драйвера (Базовый видеоадаптер) или драйвер старше 3 лет
  $gs = @($F.Gpu | Where-Object { $_ }); $n0 = $o.Count
  foreach ($g in $gs) { $url = RvUrl $g.Ven; $site = "$(if ($F.Laptop) { 'на сайте производителя ноутбука (поддержка твоей модели) или видеокарты' } else { 'на сайте производителя видеокарты' })$(if ($url) { ": $url" })"
    if ($g.Basic) { & $add 'video' 'нет драйвера видео' 'нет драйвера видеокарты: стоит «Базовый видеоадаптер (Майкрософт)»' 0 "Поставь драйвер видеокарты — он $site. Без него всё рисуется без помощи видеокарты: окна, видео и браузер тормозят." 80; continue }
    if ($g.Date) { $y = [int][math]::Floor(((Get-Date) - [datetime]$g.Date).TotalDays / 365.25)
      if ($y -ge 3) { & $add 'video' "драйверу видео $y $(RvYr $y)" "драйвер видеокарты «$($g.N)» старый: от $(([datetime]$g.Date).ToString('d MMMM yyyy', $ru)), $y $(RvYr $y)" $y "Проверь, нет ли новее, $site. Для старой видеокарты новее может не быть — тогда всё в порядке." 35 } } }
  if (-not $gs) { & $add 'video' 'видеокарту не нашёл' 'видеокарту не нашёл' $null '' 0 'skip' }
  elseif ($o.Count -eq $n0) { & $add 'video' 'драйвер есть' "$(@($gs | ForEach-Object { "«$($_.N)»$(if ($_.Date) { ", драйвер от $(([datetime]$_.Date).ToString('d MMMM yyyy', $ru))" })" }) -join '; ')" $gs.Count '' 0 }
  # «Целостность памяти» на процессоре без MBEC: только объяснение
  $v = $F.Vbs
  if ($v -and $null -ne $v.Hvci) {
    if ($v.Hvci -and $v.Mbec -eq $false) { & $add 'vbs' 'защита памяти мешает' "включена «Целостность памяти», а процессор$(if ($c -and $c.Name) { " $(RvCn $c.Name)" }) её не ускоряет" 1 'Это защита Windows от вирусов в драйверах. На таком процессоре она заметно отнимает скорость. Выключить можно самому: «Безопасность Windows» → «Безопасность устройства» → «Изоляция ядра» → «Целостность памяти», потом перезагрузка. Риск: без неё вирусу проще закрепиться глубоко в Windows. По ситуации — решай сам, Помощник её не меняет.' 40 }
    else { & $add 'vbs' $(if ($v.Hvci) { 'защита памяти вкл' } else { 'защита памяти выкл' }) $(if ($v.Hvci) { "«Целостность памяти» включена$(if ($v.Mbec) { ', процессор её ускоряет' })" } else { '«Целостность памяти» выключена' }) ([int][bool]$v.Hvci) '' 0 } }
  else { & $add 'vbs' 'защиту не прочитал' '«Целостность памяти» не прочитал' $null '' 0 'skip' }
  # Расширения браузеров: 10 и больше, при малой памяти — 5 и больше
  $br = $F.Br
  if ($br -and $br.Count) { $mx = [int]($br.Values | Measure-Object -Maximum).Maximum; $t = @($br.Keys | ForEach-Object { "$_ — $($br[$_])" }) -join ', '
    if ($mx -ge 10 -or ($mx -ge 5 -and $small)) { & $add 'browser' "расширений: $mx — много" "много расширений в браузере: $t" $mx 'Убери расширения, которыми не пользуешься: каждое работает всё время и занимает память. И включи спящие вкладки в настройках браузера: Chrome — «Экономия памяти», Edge — «Спящие вкладки», Яндекс — «Выгружать из памяти неиспользуемые вкладки».' 20 }
    else { & $add 'browser' "расширений: $mx" "расширений в браузере: $t" $mx '' 0 } }
  else { & $add 'browser' 'браузеров не нашёл' 'Chrome, Edge и Яндекс Браузер не нашёл' $null '' 0 'skip' }
  # Эффекты: совет — только слабому (HDD, застрявшая частота, нет драйвера видео, мало памяти)
  $weak = $small -or [bool]@($o | Where-Object { $_.W -ge 80 }).Count
  if ($F.Fx -eq 'perf') { & $add 'effects' 'эффекты уже выключены' 'визуальные эффекты: уже «наилучшее быстродействие»' 0 '' 0 }
  elseif ($F.Fx -and $weak) { & $add 'effects' 'эффекты включены' 'включены анимации и тени Windows' 1 "Можно поставить «наилучшее быстродействие» и оставить сглаживание шрифтов: окна и меню откроются без анимации — слабому $(if ($F.Laptop) { 'ноутбуку' } else { 'компьютеру' }) легче." 15 }
  elseif ($F.Fx) { & $add 'effects' 'эффекты не мешают' "визуальные эффекты не мешают: $dv справляется" 1 '' 0 }
  else { & $add 'effects' 'эффекты не прочитал' 'визуальные эффекты не прочитал' $null '' 0 'skip' }
  $w = @($o | Where-Object { $_.Level -eq 'warn' } | Sort-Object @{ e = 'W'; Descending = $true }, Ord); if ($w) { $w[0].Level = 'main' }
  $rk = @{ main = 0; warn = 1; ok = 2; skip = 3 }; @($o | Sort-Object @{ e = { $rk[$_.Level] } }, @{ e = 'W'; Descending = $true }, Ord) }
# Итоги для общей оценки (9al): %LOCALAPPDATA%\Pomoshnik\revive.json — check (проверка), found (найдено), value (число), advice (совет), level (уровень: main — главная причина, warn — мешает, ok — в порядке, skip — не проверил)
function RvSave($Items, [string]$Dev, [double]$Sec) { try { $p = Join-Path $env:LOCALAPPDATA 'Pomoshnik\revive.json'; [void][IO.Directory]::CreateDirectory((Split-Path $p)); $t = "$p.tmp"
    $o = [ordered]@{ schema = 1; created = (Get-Date).ToString('s'); device = $Dev; seconds = $Sec; main = "$(@($Items | Where-Object { $_.Level -eq 'main' })[0].Check)"
      items = @($Items | ForEach-Object { [ordered]@{ check = $_.Check; found = $_.Found; value = $_.Value; advice = $_.Advice; level = $_.Level } }) }
    [IO.File]::WriteAllText($t, ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false)); if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) }; $true }
  catch { Jr "revive.json не записал: $($_.Exception.Message)"; $false } }
if ($Lib) { return }

# ---------- Ход ----------
# Закрыть шаг: мешает что-то — по каждой такой проверке самое важное, иначе — что в порядке. Итог шага короткий: длинный сжимает название шага в окне; всё — в итоге
function Close([string[]]$C, [string]$More = '', [switch]$Bad) { $J = @(RvJudge $F); $t = @(); $w = [bool]$Bad
  foreach ($k in $C) { $x = @($J | Where-Object { $_.Check -eq $k }); $b = @($x | Where-Object { $_.Level -in 'main', 'warn' }); if ($b) { $w = $true }
    foreach ($i in $x) { Jr "$($i.Check): $($i.Level) — $($i.Found)" }; $t += ,@($(if ($b) { $b[0].S } else { '' }), $x[0].S) }
  $t = (@($t | ForEach-Object { if ($w) { $_[0] } else { $_[1] } } | Where-Object { $_ }) + @(if ($More) { $More })) -join ' · '; if ($w) { Step -Warn $t } else { Step -Done $t } }
function DoUndo { Step -Plan 'Возвращаю эффекты как было'; Step 'Возвращаю эффекты как было' -Hint 'Пара секунд'
  if (-not (RvBackup)) { Step -Done 'возвращать нечего'; Write-Host 'Помощник не менял визуальные эффекты — возвращать нечего.' -ForegroundColor Green; return }
  Step -Unsafe; $r = RvFxUndo; RvFxLive $r.Items; Jr "откат эффектов: $(if ($r.Ok) { 'вернул всё' } else { "не вернул: $($r.Bad -join ', ')" })"
  if ($r.Ok) { Step -Done 'вернул как было'; Write-Host 'Вернул визуальные эффекты как было. Часть вернётся после перезагрузки.' -ForegroundColor Green }
  else { Step -Warn "не вернул: $($r.Bad.Count)"; Write-Host "Не вернул: $($r.Bad -join ', '). Позови помощь." -ForegroundColor Yellow } }

Write-Host "`nПОЧЕМУ ТОРМОЗИТ`n" -ForegroundColor Cyan
Step -Safe
$lk = PctLock 'revive'; if (-not $lk) { Step 'Проверяю, не идёт ли проверка'; Step -Fail 'проверка уже идёт' -Do 'Дождись, пока она закончится.'; Write-Host 'Проверка уже идёт. Дождись, пока она закончится.' -ForegroundColor Yellow; Enter; return }
try {
  $sw = [Diagnostics.Stopwatch]::StartNew(); Jr "начал: $(if ($Undo) { 'вернуть эффекты' } else { 'проверка' })$(if (RvFake) { ", подмена $env:PCT_REVIVE_FAKE" })"
  if ($Undo) { DoUndo; return }
  $D = RvDevice; $dv = $(if ($D.Laptop) { 'ноутбук' } else { 'компьютер' }); $bk = RvBackup
  $F = [pscustomobject]@{ Laptop = $D.Laptop; AC = $D.AC; Disk = $null; Ram = $null; Cpu = $null; Gpu = @(); Vbs = $null; Br = $null; Fx = '' }
  # Шагов мало: под списком помещается вопрос с кнопками и при 150 %
  Step -Plan (@(if ($bk) { 'Спрашиваю, вернуть ли эффекты' }) + @('Смотрю диск и память', 'Нагружаю процессор на 5 секунд', 'Смотрю видеокарту и защиту', 'Смотрю браузеры и эффекты', 'Готовлю итог'))
  if ($bk) { Step 'Спрашиваю, вернуть ли эффекты' -Hint 'Ответь на вопрос ниже'
    if (Ask2 "Помощник уже менял визуальные эффекты ($(([datetime]$bk.created).ToString('d MMMM, HH:mm', $ru)))" 'могу вернуть всё как было.' 'Если нет — продолжу проверку.' 'Вернуть эффекты как было?') { Step -Done 'вернуть'; DoUndo; return }
    Step -Done 'продолжаю проверку' }
  Step 'Смотрю диск и память' -Hint 'Ничего не меняю'; $F.Disk = RvDisk; Jr "диск: $($F.Disk.Media) $($F.Disk.Bus), $($F.Disk.FreeGB) из $($F.Disk.SizeGB) ГБ свободно, TRIM $($F.Disk.Trim)"
  $F.Ram = RvRam; Jr "память: планки $(@($F.Ram.Sticks) -join ', ') МБ, слотов $($F.Ram.Slots), свободно $([int]$F.Ram.FreeMB) из $([int]$F.Ram.TotalMB) МБ"; Close 'disk', 'ram'
  Step 'Нагружаю процессор на 5 секунд' -Hint 'Ничего не запускай 5 секунд'
  Write-Host 'Нагружаю процессор на 5 секунд и смотрю, на какой частоте он работает. Ничего не меняю.' -ForegroundColor DarkGray
  $F.Cpu = RvCpu; $F.Cpu.Perf = RvLoad; Jr "процессор: $($F.Cpu.Name), база $($F.Cpu.Base) МГц, под нагрузкой $($F.Cpu.Perf) %"; Close 'cpu'
  Step 'Смотрю видеокарту и защиту' -Hint 'Ничего не меняю'; $F.Gpu = @(RvGpu); $F.Vbs = RvVbs $F.Cpu.Name
  Jr "видео: $(@($F.Gpu | ForEach-Object { "$($_.N) [$($_.Ven)] $(if ($_.Date) { ([datetime]$_.Date).ToString('yyyy-MM-dd') })$(if ($_.Basic) { ' базовый' })" }) -join '; '); «Целостность памяти»: $($F.Vbs.Hvci), MBEC: $($F.Vbs.Mbec)"; Close 'video', 'vbs'
  # Браузеры и эффекты: вопрос про эффекты только слабому компьютеру, перед изменением — бэкап, после — перечитываю
  Step 'Смотрю браузеры и эффекты' -Hint 'Ничего не меняю без вопроса'; $F.Br = RvBrowsers; Jr "расширения: $(@($F.Br.Keys | ForEach-Object { "$_ $($F.Br[$_])" }) -join ', ')"
  $fx = @(RvFxRead); $F.Fx = $(if (RvFxPerf $fx) { 'perf' } else { 'full' }); $fxDo = ''
  Jr "эффекты: $(@($fx | ForEach-Object { "$($_.N)=$(if ($_.E) { $_.V } else { '—' })" }) -join ' ')"
  $e = @(RvJudge $F | Where-Object { $_.Check -eq 'effects' })[0]
  if ($e.Level -in 'main', 'warn') {
    if (Ask2 'Визуальные эффекты' "Windows рисует анимации окон и меню, тени и эскизы картинок. Слабому $(if ($D.Laptop) { 'ноутбуку' } else { 'компьютеру' }) они мешают." 'Рекомендую «наилучшее быстродействие»: сглаживание шрифтов оставлю, эскизы картинок в папках станут значками. Вернуть — нажми «Почему тормозит» ещё раз.' 'Поставить «наилучшее быстродействие»?') {
      $b = RvBackupStart $fx; Jr "бэкап эффектов: $(RvBackupPath)"; Step -Unsafe; $tg = @(RvFxTarget $fx); $ok = RvFxWrite $tg; $now = @(RvFxRead); RvFxLive $now
      if ($ok -and (RvFxSame $now $tg)) { $fxDo = 'yes'; Jr 'эффекты: поставил «наилучшее быстродействие»'; Write-Host 'Поставил «наилучшее быстродействие». Часть эффектов поменяется сразу, остальное — после перезагрузки.' -ForegroundColor Green; Close 'browser' 'эффекты выключил' }
      else { $fxDo = 'bad'; Jr "эффекты: записалось не всё: $(@($now | Where-Object { $x = $_; -not (RvFxSame @($x) @($tg | Where-Object { $_.N -eq $x.N })) } | ForEach-Object { $_.N }) -join ', ')"; Write-Host 'Записалось не всё. Вернуть как было: нажми «Почему тормозит» ещё раз.' -ForegroundColor Yellow; Close 'browser' 'эффекты: записалось не всё' -Bad } }
    else { $fxDo = 'no'; Close 'browser' 'эффекты оставил' -Bad } }
  else { Close 'browser', 'effects' }
  # ---------- Итог: главная причина сверху, дальше — по важности ----------
  Step 'Готовлю итог'; $J = @(RvJudge $F); $e = @($J | Where-Object { $_.Check -eq 'effects' })[0]
  if ($fxDo -eq 'yes') { $e.Found = 'поставил «наилучшее быстродействие», сглаживание шрифтов оставил'; $e.Level = 'ok'; $e.W = 0; $e.Advice = 'Вернуть как было: нажми «Почему тормозит» ещё раз и ответь «да» на первый вопрос.' }
  elseif ($fxDo -eq 'no') { $e.Advice += ' Поставить: нажми «Почему тормозит» ещё раз и ответь «да».' }
  elseif ($fxDo -eq 'bad') { $e.Found += ' — записалось не всё'; $e.Advice = 'Вернуть как было: нажми «Почему тормозит» ещё раз и ответь «да» на первый вопрос.' }
  $m = @($J | Where-Object { $_.Level -eq 'main' })[0]; $ws = @($J | Where-Object { $_.Level -eq 'warn' }); $oks = @($J | Where-Object { $_.Level -eq 'ok' }); $sk = @($J | Where-Object { $_.Level -eq 'skip' })
  Write-Host "`nИТОГ" -ForegroundColor Cyan
  if ($m) { Write-Host "Главная причина: $($m.Found)." -ForegroundColor Yellow; Write-Host "Что сделать: $($m.Advice.Substring(0, 1).ToLower() + $m.Advice.Substring(1))" -ForegroundColor White }
  else { Write-Host "Главной причины не нашёл: $dv в порядке. Если тормозит одна программа — нажми «Что тормозит сейчас», пока она открыта." -ForegroundColor Green }
  if ($ws) { Write-Host "`nЕщё мешает — по важности:" -ForegroundColor Cyan; foreach ($x in $ws) { Write-Host "  • $(Up $x.Found). $($x.Advice)" -ForegroundColor White } }
  if ($oks) { Write-Host "`nВ порядке:" -ForegroundColor Cyan; foreach ($x in $oks) { Write-Host "  • $(Up $x.Found).$(if ($x.Advice) { " $($x.Advice)" })" -ForegroundColor DarkGray } }
  if ($sk) { Write-Host "`nНе проверил: $(@($sk | ForEach-Object { $_.Found }) -join '; ')." -ForegroundColor DarkGray }
  Write-Host "`nЖелезо — только совет: покупать или нет, решай сам." -ForegroundColor DarkGray
  $sec = [math]::Round($sw.Elapsed.TotalSeconds, 1); $sv = RvSave $J $dv $sec
  Jr "готово за $sec с: главная причина — $(if ($m) { "$($m.Check): $($m.Found)" } else { 'нет' }); мешает: $(@($ws | ForEach-Object { $_.Check }) -join ', '); revive.json: $(if ($sv) { 'записан' } else { 'не записан' })"
  if ($m) { Step -Warn "главная причина: $($m.S)" } else { Step -Done "$dv в порядке" }
} finally { PctUnlock $lk; Enter }
