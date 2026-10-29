# Общие пути и порт Помощника. Подключение: . "$PSScriptRoot\pct-core.ps1". При подключении ничего не делает, только задаёт функции.
# Корень: $env:PCT_ROOT (для проверок) → папка выше helpers, если скрипт лежит в helpers → C:\PC-Tweaks-Laptop.
function PctRoot { if ($env:PCT_ROOT) { return $env:PCT_ROOT }
  if ((Split-Path $PSScriptRoot -Leaf) -eq 'helpers') { return (Split-Path $PSScriptRoot -Parent) }; 'C:\PC-Tweaks-Laptop' }
function PctDir([ValidateSet('helpers', 'guard', 'run', 'reports')][string]$Name) { Join-Path (PctRoot) $Name }
# SOCKS Happ: vpn.socks из профиля (только как JSON, только 127.0.0.1:<порт до 65535>), иначе 127.0.0.1:10808
function PctSocks { $s = ''; try { $s = "$(([IO.File]::ReadAllText("$env:LOCALAPPDATA\Pomoshnik\profile.json") | ConvertFrom-Json).vpn.socks)" } catch {}
  if ($s -match '^127\.0\.0\.1:(\d{2,5})$' -and [int]$Matches[1] -le 65535) { $s } else { '127.0.0.1:10808' } }
function PctSocksPort { [int](PctSocks).Split(':')[1] }
# Фоновое дело для окна: run\bg-<имя>.json — шаг, подсказка, номер шага n из of, время t, pid. -End — итог (окно покажет его в течение 10 мин). Сбой записи (файл занят чтением окна) — до 3 повторов через 50 мс, после них молча
function PctBg([string]$Name, [string]$Step, [string]$Hint = '', [int]$N = 0, [int]$Of = 0, [string]$End) { try { $d = PctDir 'run'; [void][IO.Directory]::CreateDirectory($d); $p = "$d\bg-$Name.json"; $t = "$p.$PID.tmp"
  $o = [ordered]@{ name = $Name; step = $Step; hint = $Hint; n = $N; of = $Of; t = (Get-Date -Format s); pid = $PID }; if ($PSBoundParameters.ContainsKey('End')) { $o.step = ''; $o.end = $End }
  $j = $o | ConvertTo-Json -Compress
  for ($i = 0; ; $i++) { try { [IO.File]::WriteAllText($t, $j, (New-Object Text.UTF8Encoding $false)); if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) }; break } catch { if ($i -ge 3) { throw }; [Threading.Thread]::Sleep(50) } } } catch { try { [IO.File]::Delete($t) } catch {} } }
# Одно изменение за раз между процессами и пользователями (SYSTEM, администратор, она): мьютекс Global\Pomoshnik.<имя>. PctLock — объект или $null (занято). Повторный захват тем же потоком проходит
# Брошенный мьютекс (процесс упал) — взят. Нет прав на Global\ — объект без мьютекса (работа без блокировки) и строка в reports\lock.log. Освобождать PctUnlock в finally
function PctLock([string]$Name, [int]$Wait = 0) { $n = "Global\Pomoshnik.$Name"; $m = $null; $rw = [Security.AccessControl.MutexRights]'Synchronize, Modify'
  try { for ($i = 0; -not $m -and $i -lt 3; $i++) { try { $m = [Threading.Mutex]::OpenExisting($n, $rw) } catch [Threading.WaitHandleCannotBeOpenedException] {
        $s = New-Object Security.AccessControl.MutexSecurity; foreach ($a in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-11', $rw))) { $s.AddAccessRule((New-Object Security.AccessControl.MutexAccessRule((New-Object Security.Principal.SecurityIdentifier $a[0]), $a[1], 'Allow'))) }
        $c = $false; try { $m = [Threading.Mutex]::new($false, $n, [ref]$c, $s) } catch [UnauthorizedAccessException] {} } }
    if (-not $m) { throw 'мьютекс не открылся' } }
  catch { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d); [IO.File]::AppendAllText("$d\lock.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $n нет прав, работаю без блокировки: $($_.Exception.Message)`n", (New-Object Text.UTF8Encoding $false)) } catch {}
    return [pscustomobject]@{ Name = $Name; M = $null } }
  $got = $false; try { $got = $m.WaitOne($Wait * 1000) } catch [Threading.AbandonedMutexException] { $got = $true }
  if (-not $got) { $m.Dispose(); return $null }; [pscustomobject]@{ Name = $Name; M = $m } }
# Сеть: один процесс за раз рвёт или проверяет сеть (энергосбережение сетевой карты и подбор обхода). Занято — $Busy (строка для человека), потом ждёт до $Wait с; $null — не дождался. Берут после замка своей задачи, освобождают PctUnlock
function PctNetLock([scriptblock]$Busy, [int]$Wait = 900) { $l = PctLock 'net'; if (-not $l) { if ($Busy) { & $Busy | Out-Null }; $l = PctLock 'net' $Wait }; $l }
function PctUnlock($L) { if ($L -and $L.M) { try { $L.M.ReleaseMutex() } catch {}; $L.M.Dispose(); $L.M = $null } }
# Профиль: %LOCALAPPDATA%\Pomoshnik\profile.json. PctProfile — объект или $null (нет файла, битый JSON)
function PctProfilePath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\profile.json' }
function PctProfile { try { $o = [IO.File]::ReadAllText((PctProfilePath)) | ConvertFrom-Json -ErrorAction Stop; if ($o -is [Management.Automation.PSCustomObject]) { $o } } catch {} }
function PctProfileLog([string]$Text) { try { $d = PctDir 'reports'; [void][IO.Directory]::CreateDirectory($d)
  [IO.File]::AppendAllText("$d\profile.log", "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Text`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
# Запись: временный файл → замена (прошлый → profile.prev.json), UTF-8 без BOM. Сбой — исключение
function PctProfileSave($Obj) { $p = PctProfilePath; $d = Split-Path $p; [void][IO.Directory]::CreateDirectory($d); $t = "$p.tmp"
  [IO.File]::WriteAllText($t, ($Obj | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
  if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, "$d\profile.prev.json") } else { [IO.File]::Move($t, $p) } }
# Прежняя установка без профиля: собрать его из файлов корня (только пути и флаги). Профиль есть, даже битый, — не трогать
function PctMigrate { $p = PctProfilePath
  if ([IO.File]::Exists($p)) { if (-not (PctProfile)) { PctProfileLog "профиль не читается, работаю без него: $p" }; return }
  $r = PctRoot; if (-not (Test-Path -LiteralPath $r)) { return }; $Hd = PctDir 'helpers'
  PctProfileLog "начинаю: собираю профиль из $r"
  $zc = "$Hd\zapret-cmd.txt"; $z = Test-Path -LiteralPath $zc; $pac = Test-Path -LiteralPath "$Hd\smart-proxy-on.txt"
  $ad = "$(Get-Content -LiteralPath "$Hd\anydesk-path.txt" -Encoding UTF8 -TotalCount 1 -ErrorAction SilentlyContinue)"
  $ad = [bool](@($ad, "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe", "$env:ProgramFiles\AnyDesk\AnyDesk.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) -or [bool](Get-Process AnyDesk -ErrorAction SilentlyContinue)
  $happ = (Test-Path -LiteralPath 'D:\Happ') -or [bool](Get-Process Happ -ErrorAction SilentlyContinue)
  $yn = { param($v) if ($v) { 'да' } else { 'нет' } }
  PctProfileLog "нашёл: обход=$(& $yn $z), прокси=$(& $yn $pac), Happ=$(& $yn $happ), AnyDesk=$(& $yn $ad)"
  try { PctProfileSave ([ordered]@{ schema = 1; created = (Get-Date).ToString('o'); source = 'migrate'; legacyRoot = $r
    modules = [ordered]@{ core = $true; pc = $true; ru = ($z -or $pac) }
    vpn = [ordered]@{ client = $(if ($happ) { 'Happ' } else { '' }); socks = (PctSocks); pac = $pac }
    sites = [ordered]@{ file = "$Hd\proxy-sites.txt" }; zapret = [ordered]@{ cmdFile = $(if ($z) { $zc } else { '' }) }
    help = [ordered]@{ kind = $(if ($ad) { 'anydesk' } else { '' }); enabled = $ad } }) } catch { PctProfileLog "не сохранил: $($_.Exception.Message)"; throw }
  PctProfileLog "сохранил профиль: $(PctProfilePath)"
  $f = @(if ($z) { 'обход' }; if ($pac) { 'прокси' }; if ($happ) { 'Happ' })
  if ($f) { 'Собрал профиль из твоих настроек: ' + ($f -join ', ') } else { 'Собрал профиль из твоих настроек' } }

# ---------- Питание (energy.ps1): тип устройства, настройки схем powercfg, устройства, бэкап и откат ----------
# PCT_ENERGY_FAKE=<файл JSON> — подмена для проверки: laptop, ms, ac; active — GUID копии схемы (не настоящей активной); balanced — копия в роли «Сбалансированной»; hp — схема вместо «Высокой производительности» (GUID, которого нет, — схемы нет);
# overlay; wifi; devices [{id, name, kind, enable, stuck — запись «удалась», но Windows не меняет}]; nics [{adapter, kw, name, val}]; vendors. С подменой схемы читаю и пишу по-настоящему (только копии), остальное — в этом файле
function PctEnFake { if ($env:PCT_ENERGY_FAKE) { [IO.File]::ReadAllText($env:PCT_ENERGY_FAKE) | ConvertFrom-Json } }
function PctEnFakeSave($F) { [IO.File]::WriteAllText($env:PCT_ENERGY_FAKE, ($F | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)) }
# Схемы Windows: сбалансированная, высокая производительность, экономия, максимальная производительность (и подменённая «Сбалансированная»). Их не удаляю никогда
function PctEnBuiltIn { $f = PctEnFake; @('381b4222-f694-41f0-9685-ff5bb260df2e', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'a1841308-3541-4fab-bc81-f71556f20b4a', 'e9a42b02-d5df-448d-aa00-03f14749eb61') + @(if ($f -and $f.balanced) { "$($f.balanced)" }) }
# Настройки: подгруппа, настройка, значение «без экономии» (сверено с powercfg /qh 29.10)
function PctEnKeys { [ordered]@{
  usb = @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0)      # выборочная приостановка USB: 0 — выкл
  aspm = @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 0)     # ASPM PCI Express: 0 — выкл
  disk = @('0012ee47-9041-4b5d-9b77-535fba8b1442', '6738e2c4-e8a5-4a42-b16a-e040e769756e', 0)     # отключать диск через, с: 0 — никогда
  wifi = @('19cbb8fa-5279-450e-9fac-8a3d5fedd0c1', '12bbebe6-58d6-4636-95bb-3217ef867c1a', 0)     # Wi-Fi: 0 — максимальная производительность
  sleep = @('238c9fa8-0aad-41ed-83f4-97be242c8f20', '29f6c1db-86da-48c5-9fdb-f2b67b1f44da', 0)    # сон через, с: 0 — никогда
  video = @('7516b95f-f776-4464-8c53-06167f40cc99', '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e', 0)    # отключать экран через, с: 0 — никогда
  cpumin = @('54533251-82be-4824-96c1-47b60b740d00', '893dee8e-2bef-41e0-89c6-b55d0929964c', 5) } } # минимум процессора, %: 5 — как в «Сбалансированной»
# Modern Standby по выводу powercfg /a: строка с S0 в отступе 4 пробела — состояние; под недоступным идёт причина с большим отступом (таб). Язык Windows не важен
function PctEnMS([string[]]$Lines) { for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^ {4}\S.*S0') { $n = $(if ($i + 1 -lt $Lines.Count) { $Lines[$i + 1] } else { '' }); if ($n -notmatch '^(\t| {5,})\S') { return $true } } }; $false }
# Тип: Laptop — есть батарея; MS — Modern Standby; AC — от сети (BatteryStatus 2 — сеть, 3 — заряжена, 6–9 — заряжается)
function PctEnDevice { $f = PctEnFake; if ($f) { return [pscustomobject]@{ Laptop = [bool]$f.laptop; MS = [bool]$f.ms; AC = [bool]$f.ac } }
  $b = @(Get-CimInstance Win32_Battery); [pscustomobject]@{ Laptop = [bool]$b; MS = (PctEnMS @(powercfg /a)); AC = (-not $b) -or [bool]($b | Where-Object { $_.BatteryStatus -in 2, 3, 6, 7, 8, 9 }) } }
function PctEnSchemes { @(powercfg /list) | ForEach-Object { if ($_ -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+\((.*)\)') { [pscustomobject]@{ G = $Matches[1]; N = $Matches[2] } } } }
function PctEnActive { $f = PctEnFake; if ($f) { return "$($f.active)" }; if ("$(powercfg /getactivescheme)" -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') { $Matches[0] } }
# Включить схему; та же схема — применить её изменённые настройки
function PctEnSetActive([string]$G) { $f = PctEnFake; if ($f) { $f.active = $G; PctEnFakeSave $f; return $true }; $null = powercfg /setactive $G 2>&1; -not $LASTEXITCODE }
# Значение настройки: AC (от сети) и DC (от батареи) — два последних 0x… в выводе /qh; нет настройки — $null
function PctEnGet([string]$Scheme, [string]$Key) { $k = (PctEnKeys)[$Key]; $o = @(powercfg /qh $Scheme $k[0] $k[1] 2>$null); if ($LASTEXITCODE) { return }
  $h = @($o | ForEach-Object { if ($_ -match ':\s*0x([0-9a-fA-F]+)\s*$') { [Convert]::ToInt64($Matches[1], 16) } }); if ($h.Count -ge 2) { [pscustomobject]@{ AC = $h[-2]; DC = $h[-1] } } }
function PctEnSet([string]$Scheme, [string]$Key, [ValidateSet('AC', 'DC')][string]$Src, [long]$V) { $k = (PctEnKeys)[$Key]; $c = $(if ($Src -eq 'AC') { '/setacvalueindex' } else { '/setdcvalueindex' })
  $null = powercfg $c $Scheme $k[0] $k[1] $V 2>&1; -not $LASTEXITCODE }
# Схема есть в Windows (её можно скопировать): powercfg /qh читает минимум процессора без ошибки. Прав не нужно
function PctEnHas([string]$G) { if (-not $G) { return $false }; $k = (PctEnKeys)['cpumin']; $null = powercfg /qh $G $k[0] $k[1] 2>&1; -not $LASTEXITCODE }
# Копия схемы с новым именем → GUID копии или $null (схемы нет в Windows)
function PctEnCopy([string]$Base, [string]$Name) { $o = "$(powercfg /duplicatescheme $Base 2>&1)"; if ($LASTEXITCODE -or $o -notmatch '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') { return }
  $g = $Matches[0]; $null = powercfg /changename $g $Name 2>&1; $g }
# Удалить только свою копию: схемы Windows и активную (настоящую и подменённую) — никогда
function PctEnDelete([string]$G) { if (-not $G -or $G -in (PctEnBuiltIn)) { return $false }
  $real = $(if ("$(powercfg /getactivescheme)" -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') { $Matches[0] }); if ($G -eq $real -or $G -eq (PctEnActive)) { return $false }
  $null = powercfg /delete $G 2>&1; -not $LASTEXITCODE }
# Ползунок режима питания (работает при сбалансированной схеме). Ставлю и читаю только от сети: powercfg /overlaysetactive меняет режим для текущего питания
function PctEnOverlay { $f = PctEnFake; if ($f) { return "$($f.overlay)" }
  $v = "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes').ActiveOverlayAcPowerScheme)"; if ($v) { $v } else { '00000000-0000-0000-0000-000000000000' } }
function PctEnOverlaySet([string]$G) { $f = PctEnFake; if ($f) { $f.overlay = $G; PctEnFakeSave $f; return $true }; $null = powercfg /overlaysetactive $G 2>&1; -not $LASTEXITCODE }
# «Разрешить отключение этого устройства» (MSPower_DeviceEnable): kind hub — USB-концентраторы, input — мышь, клавиатура, устройства ввода USB, net — сетевые карты
function PctEnDevices { $f = PctEnFake; if ($f) { return @($f.devices | ForEach-Object { [pscustomobject]@{ Id = $_.id; N = $_.name; K = $_.kind; On = [bool]$_.enable } }) }
  $pn = @{}; foreach ($p in @(Get-CimInstance Win32_PnPEntity -Property PNPDeviceID, Name, PNPClass, Service)) { if ($p.PNPDeviceID) { $pn[$p.PNPDeviceID] = $p } }
  foreach ($m in @(Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable)) { $id = $m.InstanceName -replace '_\d+$'; $p = $pn[$id]; if (-not $p) { continue }
    $k = $(if ($p.PNPClass -eq 'USB' -and $p.Service -match '^usbhub3?$') { 'hub' } elseif ($p.PNPClass -in 'Mouse', 'Keyboard' -or ($p.PNPClass -eq 'HIDClass' -and $p.Service -eq 'HidUsb')) { 'input' } elseif ($p.PNPClass -eq 'Net' -and $id -match '^(PCI|USB)\\') { 'net' })
    if ($k) { [pscustomobject]@{ Id = $m.InstanceName; N = $p.Name; K = $k; On = [bool]$m.Enable } } } }
function PctEnDeviceSet([string]$Id, [bool]$On) { $f = PctEnFake
  if ($f) { $d = @($f.devices | Where-Object { $_.id -eq $Id }); if (-not $d) { return $false }; if (-not $d[0].stuck) { $d[0].enable = $On; PctEnFakeSave $f }; return $true }
  try { $m = @(Get-CimInstance -Namespace root\wmi MSPower_DeviceEnable -ErrorAction Stop | Where-Object { $_.InstanceName -eq $Id }); if (-not $m) { return $false }; Set-CimInstance -InputObject $m[0] -Property @{ Enable = $On } -ErrorAction Stop; $true } catch { $false } }
# Энергосбережение проводной сетевой карты (EEE, Green Ethernet): свойство, где «0» — выкл
function PctEnNics { $f = PctEnFake; if ($f) { return @($f.nics | ForEach-Object { [pscustomobject]@{ A = $_.adapter; Kw = $_.kw; N = $_.name; V = "$($_.val)" } }) }
  foreach ($a in @(Get-NetAdapter -Physical | Where-Object { $_.NdisPhysicalMedium -eq 14 })) {
    foreach ($p in @(Get-NetAdapterAdvancedProperty -Name $a.Name -AllProperties | Where-Object { $_.RegistryKeyword -match '^(\*EEE|AdvancedEEE|EEELinkAdvertisement|EnableGreenEthernet|GreenEthernet)$' -and $_.DisplayName -and @($_.ValidRegistryValues) -contains '0' })) {
      [pscustomobject]@{ A = $a.Name; Kw = $p.RegistryKeyword; N = $p.DisplayName; V = "$(@($p.RegistryValue)[0])" } } } }
function PctEnNicSet([string]$A, [string]$Kw, [string]$V) { $f = PctEnFake
  if ($f) { $n = @($f.nics | Where-Object { $_.adapter -eq $A -and $_.kw -eq $Kw }); if (-not $n) { return $false }; $n[0].val = $V; PctEnFakeSave $f; return $true }
  try { Set-NetAdapterAdvancedProperty -Name $A -RegistryKeyword $Kw -RegistryValue $V -ErrorAction Stop; $true } catch { $false } }
# Бэкап: %LOCALAPPDATA%\Pomoshnik\energy-backup.json — схема до (active), копия Помощника (copy), ползунок до (overlay), старые значения (values, devices, nics).
# Повторный запуск дописывает, первое старое значение не перезаписывает. Файл схемы до — powercfg /export (export), для ручного возврата
function PctEnBackupPath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\energy-backup.json' }
function PctEnBackup { try { $o = [IO.File]::ReadAllText((PctEnBackupPath)) | ConvertFrom-Json -ErrorAction Stop; if ($o -is [Management.Automation.PSCustomObject]) { $o } } catch {} }
function PctEnBackupSave($B) { $p = PctEnBackupPath; [void][IO.Directory]::CreateDirectory((Split-Path $p)); $t = "$p.tmp"
  [IO.File]::WriteAllText($t, ($B | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)); if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) } }
# Начать или продолжить бэкап: новый — с экспортом активной схемы
function PctEnBackupStart([string]$Active, [string]$Name) { $b = PctEnBackup; if ($b) { return $b }; $d = Split-Path (PctEnBackupPath); [void][IO.Directory]::CreateDirectory($d)
  $x = "$d\energy-$(Get-Date -Format 'yyyyMMdd-HHmmss').pow"; $null = powercfg /export $x $Active 2>&1; if ($LASTEXITCODE) { $x = '' }
  $b = [pscustomobject]@{ schema = 1; created = (Get-Date).ToString('s'); active = $Active; activeName = $Name; export = $x; copy = ''; overlay = ''; values = @(); devices = @(); nics = @() }; PctEnBackupSave $b; $b }
# Запомнить старое значение, если такого ещё нет (ключ — поля Key), и сразу сохранить
function PctEnRemember($B, [string]$List, $Item, [string[]]$Key) { foreach ($x in @($B.$List)) { $same = $true; foreach ($k in $Key) { if ("$($x.$k)" -ne "$($Item.$k)") { $same = $false } }; if ($same) { return } }
  $B.$List = @(@($B.$List) + $Item); PctEnBackupSave $B }
# Откат по бэкапу: сеть, устройства, значения схем, ползунок, схема до, удаление копии. Всё вернул — бэкап в energy-backup.<время>.done.json; нет — в бэкапе остаётся невозвращённое.
# → Ok — сколько вернул, Bad — что не вернул; $null — бэкапа нет
function PctEnUndo { $b = PctEnBackup; if (-not $b) { return }; $bad = New-Object Collections.ArrayList; $ok = 0
  $k = @(); foreach ($x in @($b.nics)) { if (PctEnNicSet $x.adapter $x.kw $x.old) { $ok++ } else { $k += $x; [void]$bad.Add("сетевая карта $($x.adapter): $($x.name)") } }; $b.nics = $k
  $k = @(); foreach ($x in @($b.devices)) { if (PctEnDeviceSet $x.id ([bool]$x.old)) { $ok++ } else { $k += $x; [void]$bad.Add("устройство: $($x.name)") } }; $b.devices = $k
  $act = PctEnActive; $re = $false
  $k = @(); foreach ($x in @($b.values)) { if ($b.copy -and $x.scheme -eq $b.copy) { $ok++; continue }
    if (PctEnSet $x.scheme $x.key $x.src $x.old) { $ok++; if ($x.scheme -eq $act) { $re = $true } } else { $k += $x; [void]$bad.Add("настройка схемы: $($x.key)") } }; $b.values = $k
  if ($re) { [void](PctEnSetActive $act) }
  if ($b.overlay) { if ((PctEnDevice).AC -and (PctEnOverlaySet $b.overlay)) { $b.overlay = ''; $ok++ } else { [void]$bad.Add('режим питания: нужна зарядка') } }
  if ($b.copy) { $sw = $true; if ((PctEnActive) -eq $b.copy) { $sw = PctEnSetActive $b.active }
    if (-not $sw) { [void]$bad.Add('схема питания: не включилась прежняя') } elseif (PctEnDelete $b.copy) { $b.copy = ''; $ok++ } else { [void]$bad.Add('копия схемы: не удалилась') } }
  if ($bad.Count) { PctEnBackupSave $b } else { $p = PctEnBackupPath; $t = Get-Date -Format 'yyyyMMdd-HHmmss-fff'; $a = $p -replace '\.json$', ".$t.done.json"; for ($i = 1; [IO.File]::Exists($a); $i++) { $a = $p -replace '\.json$', ".$t-$i.done.json" }; [IO.File]::Move($p, $a) }
  [pscustomobject]@{ Ok = $ok; Bad = @($bad) } }
