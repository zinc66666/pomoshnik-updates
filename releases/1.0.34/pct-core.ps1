# Общие пути и порт Помощника. Подключение: . "$PSScriptRoot\pct-core.ps1" — до любого командлета. При подключении задаёт функции; с повышением ещё чистит окружение (ниже).
# U1b: с повышением (администратор при включённом UAC) окружение — от пользователя: HKCU\Environment пишет любой её процесс без прав. Убираю все PCT_* (корень, адрес обновления, подмены),
# в PSModulePath — только системные папки (иначе модуль из «Документов» загрузится раньше системного). Только .NET: командлет до очистки загрузил бы модуль по старому пути.
# UAC выключен — границы нет (любой её процесс — администратор), окружение как есть. Копия PctElevated и PctSafeEnv — в updater.ps1 (тест сверяет)
function PctElevated { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -and
  "$([Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'EnableLUA', 1))" -ne '0' }
function PctSafeEnv { foreach ($k in @([Environment]::GetEnvironmentVariables().Keys)) { if ("$k" -like 'PCT_*') { [Environment]::SetEnvironmentVariable("$k", $null) } }
  $env:PSModulePath = "$PSHOME\Modules;$([Environment]::GetFolderPath('ProgramFiles'))\WindowsPowerShell\Modules" }
if (PctElevated) { PctSafeEnv }
# Корень: $env:PCT_ROOT (для проверок, только без повышения) → папка выше helpers, если скрипт лежит в helpers → C:\PC-Tweaks-Laptop.
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
# Уведомления: выпуск кладёт notify.ps1 в helpers; старая установка — только guard\notify.ps1. Подключение: . (PctNotifyPath)
function PctNotifyPath { $n = "$(PctDir 'helpers')\notify.ps1"; if (Test-Path -LiteralPath $n) { $n } else { "$(PctDir 'guard')\notify.ps1" } }
# U1b: helpers\ и guard\ пишут только администраторы. Данные, которые пишут процессы без повышения, — reports\<имя>. Файл со старого места ($From) переношу при первом обращении:
# копия (новый файл берёт права reports\), затем удаление старого. Копия не вышла — путь старого места (там данные); её успел сделать другой процесс — новый
function PctData([string]$Name, [ValidateSet('helpers', 'guard')][string]$From) { $d = PctDir 'reports'; $p = "$d\$Name"; $o = "$(PctDir $From)\$Name"
  if (-not [IO.File]::Exists($p)) { try { [void][IO.Directory]::CreateDirectory($d) } catch {}; if ([IO.File]::Exists($o)) { try { [IO.File]::Copy($o, $p) } catch { if (-not [IO.File]::Exists($p)) { return $o } }; try { [IO.File]::Delete($o) } catch {} } }
  $p }
# Обновление от окна: задача PCT-Helper-Update-Now (наивысшие права, ставит U1b) — без вопроса UAC. Нет задачи — $false, окно запускает updater.ps1 само. PCT_UPDTASK_FAKE=<файл> — строка «run» вместо запуска, none — задачи нет
function PctUpdateTask { if ($env:PCT_UPDTASK_FAKE) { if ($env:PCT_UPDTASK_FAKE -eq 'none') { return $false }; Add-Content -LiteralPath $env:PCT_UPDTASK_FAKE 'run'; return $true }
  try { $s = New-Object -ComObject Schedule.Service; $s.Connect(); [void]$s.GetFolder('\').GetTask('PCT-Helper-Update-Now').Run($null); $true } catch { $false } }
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
  $zc = "$Hd\zapret-cmd.txt"; $z = Test-Path -LiteralPath $zc; $pac = Test-Path -LiteralPath (PctData 'smart-proxy-on.txt' 'helpers')
  $ad = "$(Get-Content -LiteralPath "$Hd\anydesk-path.txt" -Encoding UTF8 -TotalCount 1 -ErrorAction SilentlyContinue)"
  $ad = [bool](@($ad, "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe", "$env:ProgramFiles\AnyDesk\AnyDesk.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) -or [bool](Get-Process AnyDesk -ErrorAction SilentlyContinue)
  $happ = (Test-Path -LiteralPath 'D:\Happ') -or [bool](Get-Process Happ -ErrorAction SilentlyContinue)
  $yn = { param($v) if ($v) { 'да' } else { 'нет' } }
  PctProfileLog "нашёл: обход=$(& $yn $z), прокси=$(& $yn $pac), Happ=$(& $yn $happ), AnyDesk=$(& $yn $ad)"
  try { PctProfileSave ([ordered]@{ schema = 1; created = (Get-Date).ToString('o'); source = 'migrate'; legacyRoot = $r
    modules = [ordered]@{ core = $true; pc = $true; ru = ($z -or $pac) }
    vpn = [ordered]@{ client = $(if ($happ) { 'Happ' } else { '' }); socks = (PctSocks); pac = $pac }
    sites = [ordered]@{ file = (PctData 'proxy-sites.txt' 'helpers') }; zapret = [ordered]@{ cmdFile = $(if ($z) { $zc } else { '' }) }
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

# ---------- Мышь и тачпад (mouse.ps1): что подключено, разбор замера, повышенная точность указателя, бэкап и откат ----------
# PCT_MOUSE_FAKE=<файл JSON> — подмена для проверки: laptop, ms, ac; pointers [{id, name, kind mouse|touchpad|tablet, bus usb|radio|bt|ps2|i2c|virtual, precision}]; accel [порог1, порог2, ускорение]; reg {MouseThreshold1, MouseThreshold2, MouseSpeed};
# devices — как в PCT_ENERGY_FAKE (mouse.ps1 с подменой ставит PCT_ENERGY_FAKE на тот же файл: запрет отключения — функциями PctEnDevices/PctEnDeviceSet); vendors
function PctMsFake { if ($env:PCT_MOUSE_FAKE) { [IO.File]::ReadAllText($env:PCT_MOUSE_FAKE) | ConvertFrom-Json } }
function PctMsFakeSave($F) { [IO.File]::WriteAllText($env:PCT_MOUSE_FAKE, ($F | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)) }
# Ключ устройства по коду: «VID&PID» (USB; Bluetooth — VID&0002xxxx_PID&xxxx) или «VEN&DEV» (I2C); нет — путь без \\?\ и {класса}. По нему сверяю мышь из Windows, замер и «Разрешить отключение»
function PctMsKey([string]$Id) { if ($Id -match '(?:VID|VEN)[_&](?:000[12])?([0-9A-Za-z]{4})[&_](?:PID|DEV)[_&]([0-9A-Za-z]{4})') { "$($Matches[1])&$($Matches[2])".ToUpper() } else { ($Id -replace '^\\\\\?\\' -replace '#\{[^}]*\}$' -replace '#', '\').ToUpper() } }
# Права администратора (PCT_ADMIN_FAKE=1/0 — подмена для проверки)
function PctIsAdmin { if ($env:PCT_ADMIN_FAKE) { return $env:PCT_ADMIN_FAKE -eq '1' }; ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
# Мышь и тачпад из Win32_PointingDevice. Kind: touchpad — Precision (у того же родителя коллекция HID 0x0D/0x05) или по имени и коду; Bus: virtual — не настоящее устройство (фирменная программа),
# bt — Bluetooth, radio — приёмник 2,4 ГГц (по названию от устройства: Receiver, Wireless, Lightspeed…), usb, i2c, ps2. N — название от устройства, без серийного номера
function PctMsDevices { $f = PctMsFake; if ($f) { return @($f.pointers | ForEach-Object { [pscustomobject]@{ Id = $_.id; N = $_.name; Kind = $_.kind; Bus = $_.bus; Ptp = [bool]$_.precision; Kbd = [bool]$_.kbd } }) }
  $pt = @(Get-CimInstance Win32_PointingDevice | Where-Object { $_.PNPDeviceID }); if (-not $pt) { return }
  # Get-PnpDeviceProperty со списком устройств повторяет ответ первого — по одному
  $pr = { param($i, $k) "$((Get-PnpDeviceProperty -InstanceId $i -KeyName $k -ErrorAction SilentlyContinue).Data)" }
  $ptp = @{}; foreach ($x in @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='HIDClass'" | Where-Object { "$($_.CompatibleID)" -match 'HID_DEVICE_UP:000D_U:0005' })) { $ptp[(& $pr $x.PNPDeviceID 'DEVPKEY_Device_Parent')] = $true }
  # Клавиатура с функциями мыши (Wooting и подобные): у мыши и клавиатуры один родитель
  $kbp = @{}; foreach ($x in @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Keyboard'")) { $kbp[(& $pr $x.PNPDeviceID 'DEVPKEY_Device_Parent')] = $true }
  $bat = [bool](Get-CimInstance Win32_Battery | Select-Object -First 1); $reg = Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
  foreach ($p in $pt) { $id = $p.PNPDeviceID; $pa = & $pr $id 'DEVPKEY_Device_Parent'; $n = $(if ($pa) { & $pr $pa 'DEVPKEY_Device_BusReportedDeviceDesc' }); if (-not $n) { $n = "$($p.Name)" }
    PctMsClassify $id $pa $n ([bool]$ptp[$pa]) $bat $reg ([bool]$kbp[$pa]) } }
# Вид и шина одного указателя по коду, родителю и названию (чистая функция — тест подаёт данные ноутбука). tablet — драйвер графического планшета (ROOT\HIDCLASS, PENTABLET/WACOM/XP-PEN): не мышь, не мерю.
# touchpad: Precision-коллекция, имя, код ACPI\SYN|ELAN|ETD|ALP|DLL|GXTP (у себя или у родителя) или родитель ACPI\ (I2C HID) на устройстве с батареей. Precision — коллекция HID 0x0D или ключ PrecisionTouchPad в HKCU
function PctMsClassify([string]$Id, [string]$Pa, [string]$N, [bool]$PtpHid, [bool]$Battery, [bool]$PtpReg, [bool]$KbdParent) { $all = "$Id $Pa"
  if ($Pa -match '^ROOT\\HIDCLASS' -and $all -match '(?i)PENTABLET|WACOM|XP-?PEN') { return [pscustomobject]@{ Id = $Id; N = 'графический планшет (драйвер)'; Kind = 'tablet'; Bus = 'driver'; Ptp = $false; Kbd = $false } }
  $tp = $PtpHid -or $N -match '(?i)touch ?pad|тачпад|сенсорн' -or $all -match '(?i)(^|\s)ACPI\\(SYN|ELAN|ETD|ALP|DLL|GXTP)' -or ($Pa -match '^ACPI\\' -and $Id -match '^HID\\' -and $Battery)
  $bus = $(if ($Pa -and $Pa -notmatch '^(USB|ACPI|HID|BTHENUM|BTHLEDEVICE|BTHLE)\\') { 'virtual' } elseif ($all -match '(?i)00001124-0000-1000-8000-00805F9B34FB|00001812-0000-1000-8000-00805F9B34FB|(^|\s)BTH') { 'bt' }
    elseif ($Id -match '^ACPI\\') { 'ps2' } elseif ($Pa -match '^ACPI\\') { 'i2c' } elseif ($N -match '(?i)receiver|wireless|dongle|2\.4|lightspeed|unifying|bolt|nano|приёмник|беспровод') { 'radio' } else { 'usb' })
  if ($tp -and $bus -ne 'virtual' -and (-not $N -or $N -match '(?i)^HID|совместим')) { $N = 'Тачпад' }
  [pscustomobject]@{ Id = $Id; N = $N; Kind = $(if ($tp) { 'touchpad' } else { 'mouse' }); Bus = $bus; Ptp = $($PtpHid -or ($tp -and $PtpReg)); Kbd = [bool]($KbdParent -and -not $tp) } }
# Название для человека: мышь — от устройства, клавиатура с мышью — так и называю, тачпад — «тачпад»; нет в списке Windows — вид
function PctMsName($X) { $p = $X.Ptr; if ($X.Kind -eq 'touchpad') { return 'тачпад' }
  if ($p -and $p.Kbd) { return $(if ($p.N) { "клавиатура с функциями мыши «$($p.N)»" } else { 'клавиатура с функциями мыши' }) }; if ($p -and $p.N) { "$($p.N)" } else { 'мышь' } }
# Что показать человеку: движение без имени устройства (синтетическое) — только в журнал
function PctMsShown($G) { @($G | Where-Object { $_.Key }) }
function PctMsSum($G) { if (-not $G) { return 'замер не получился' }; @($G | ForEach-Object { "$(PctMsName $_) — $($_.S.Hz) Гц" }) -join ', ' }
# Разбор замера одного устройства: времена событий движения, мкс по возрастанию → Hz — медиана частоты по окнам 100 мс (в окне ≥ 3 событий: (n − 1) / (последнее − первое)), Sp — разброс окон (10–90 %, Гц),
# Gap — пропуски: интервал длиннее 3 медианных, но короче 100 мс (дольше — рука остановилась), Win — окон, N — событий. Меньше 5 окон (полсекунды движения) — $null: замер не получился
function PctMsStats([double[]]$T) { if (-not $T -or $T.Count -lt 10) { return }; $r = New-Object Collections.ArrayList; $i = 0
  while ($i -lt $T.Count) { $w = [math]::Floor($T[$i] / 100000); $j = $i; while ($j + 1 -lt $T.Count -and [math]::Floor($T[$j + 1] / 100000) -eq $w) { $j++ }
    if ($j - $i -ge 2 -and $T[$j] -gt $T[$i]) { [void]$r.Add(($j - $i) * 1e6 / ($T[$j] - $T[$i])) }; $i = $j + 1 }
  if ($r.Count -lt 5) { return }; $s = @($r | Sort-Object); $hz = $s[[int][math]::Floor($s.Count / 2)]; $lim = 3e6 / $hz; $g = 0
  for ($k = 1; $k -lt $T.Count; $k++) { $d = $T[$k] - $T[$k - 1]; if ($d -gt $lim -and $d -lt 100000) { $g++ } }
  [pscustomobject]@{ Hz = [math]::Round($hz); Sp = [math]::Round($s[[int][math]::Floor(0.9 * ($s.Count - 1))] - $s[[int][math]::Floor(0.1 * ($s.Count - 1))]); Gap = $g; Win = $s.Count; N = $T.Count } }
# Замер по устройствам: события Raw Input (время, мкс; номер источника), источники (путь HID; вид 0 — мышь, 1 — тачпад HID 0x0D), мышь и тачпад из PctMsDevices → [{Key, Kind, Ptr, S — PctMsStats}] только с удачным разбором.
# Источники одного устройства (несколько коллекций) — вместе. Мышь без имени (синтетическое движение; тачпад Precision двигает указатель так же) не считаю, если в замере есть тачпад HID
function PctMsGroups([double[]]$Times, [int[]]$Devs, [string[]]$Names, [int[]]$Kinds, $Ptrs) { $g = [ordered]@{}; $tpHid = $false
  for ($i = 0; $i -lt $Names.Count; $i++) { if ($Kinds[$i] -eq 1 -and $Devs -contains $i) { $tpHid = $true } }
  for ($i = 0; $i -lt $Names.Count; $i++) { if ($Kinds[$i] -eq 0 -and -not $Names[$i] -and $tpHid) { continue }
    $k = $(if ($Names[$i]) { PctMsKey $Names[$i] } else { '' }); $p = @($Ptrs | Where-Object { $k -and (PctMsKey $_.Id) -eq $k })[0]; if ($p -and $p.Kind -eq 'tablet') { continue }
    $kd = $(if ($Kinds[$i] -eq 1 -or ($p -and $p.Kind -eq 'touchpad')) { 'touchpad' } else { 'mouse' }); $gk = "$kd|$k"
    if (-not $g.Contains($gk)) { $g[$gk] = [pscustomobject]@{ Key = $k; Kind = $kd; Ptr = $p; T = New-Object Collections.Generic.List[double] } }
    for ($j = 0; $j -lt $Devs.Count; $j++) { if ($Devs[$j] -eq $i) { $g[$gk].T.Add($Times[$j]) } } }
  foreach ($x in $g.Values) { $s = PctMsStats @($x.T | Sort-Object); if ($s) { [pscustomobject]@{ Key = $x.Key; Kind = $x.Kind; Ptr = $x.Ptr; S = $s } } } }
# Повышенная точность указателя: SPI_GETMOUSE → порог1, порог2, ускорение (брать через @()); включена — ускорение не 0 (Windows: вкл 6, 10, 1; выкл 0, 0, 0). Запись — SPI_SETMOUSE с записью в профиль и рассылкой,
# и те же значения в HKCU\Control Panel\Mouse (MouseThreshold1, MouseThreshold2, MouseSpeed). Скорость указателя не трогаю
function PctMsSpi { if (-not ('Pct.MsSpi' -as [type])) { Add-Type -Namespace Pct -Name MsSpi -MemberDefinition '[DllImport("user32.dll", SetLastError = true)] public static extern bool SystemParametersInfo(uint a, uint b, int[] c, uint d);' } }
function PctMsAccel { $f = PctMsFake; if ($f) { return @($f.accel | ForEach-Object { [int]$_ }) }; PctMsSpi; $m = New-Object int[] 3; if ([Pct.MsSpi]::SystemParametersInfo(3, 0, $m, 0)) { $m } }
function PctMsAccelReg { $f = PctMsFake; $r = $(if ($f) { $f.reg } else { Get-ItemProperty 'HKCU:\Control Panel\Mouse' }); if ($r) { [int]"$($r.MouseThreshold1)"; [int]"$($r.MouseThreshold2)"; [int]"$($r.MouseSpeed)" } }
function PctMsAccelSet([int[]]$V) { if ($V.Count -ne 3) { return $false }; $f = PctMsFake
  if ($f) { $f.accel = $V; $f.reg = [pscustomobject]@{ MouseThreshold1 = "$($V[0])"; MouseThreshold2 = "$($V[1])"; MouseSpeed = "$($V[2])" }; PctMsFakeSave $f; return $true }
  PctMsSpi; if (-not [Pct.MsSpi]::SystemParametersInfo(4, 0, $V, 3)) { return $false }
  try { $k = 'HKCU:\Control Panel\Mouse'; Set-ItemProperty $k MouseThreshold1 "$($V[0])" -ErrorAction Stop; Set-ItemProperty $k MouseThreshold2 "$($V[1])" -ErrorAction Stop; Set-ItemProperty $k MouseSpeed "$($V[2])" -ErrorAction Stop; $true } catch { $false } }
# Бэкап: %LOCALAPPDATA%\Pomoshnik\mouse-backup.json — точность указателя до (accel; пусто — не менял), запрет отключения (devices: id, name, old). Первое старое значение не перезаписываю
function PctMsBackupPath { Join-Path $env:LOCALAPPDATA 'Pomoshnik\mouse-backup.json' }
function PctMsBackup { try { $o = [IO.File]::ReadAllText((PctMsBackupPath)) | ConvertFrom-Json -ErrorAction Stop; if ($o -is [Management.Automation.PSCustomObject]) { $o } } catch {} }
function PctMsBackupSave($B) { $p = PctMsBackupPath; [void][IO.Directory]::CreateDirectory((Split-Path $p)); $t = "$p.tmp"
  [IO.File]::WriteAllText($t, ($B | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)); if ([IO.File]::Exists($p)) { [IO.File]::Replace($t, $p, [NullString]::Value) } else { [IO.File]::Move($t, $p) } }
function PctMsBackupStart { $b = PctMsBackup; if ($b) { return $b }; $b = [pscustomobject]@{ schema = 1; created = (Get-Date).ToString('s'); accel = @(); devices = @() }; PctMsBackupSave $b; $b }
function PctMsRemember($B, $Item) { if (@($B.devices | Where-Object { $_.id -eq $Item.id }).Count) { return }; $B.devices = @(@($B.devices) + $Item); PctMsBackupSave $B }
# Откат: точность указателя (с перечитыванием), запрет отключения. Всё вернул — бэкап в mouse-backup.<время>.done.json; нет — в бэкапе остаётся невозвращённое. → Ok, Bad; $null — бэкапа нет
function PctMsUndo { $b = PctMsBackup; if (-not $b) { return }; $bad = New-Object Collections.ArrayList; $ok = 0
  $a = [int[]]@($b.accel | ForEach-Object { [int]$_ }); if ($a.Count -eq 3) { if ((PctMsAccelSet $a) -and (@(PctMsAccel) -join ',') -eq ($a -join ',')) { $b.accel = @(); $ok++ } else { [void]$bad.Add('повышенная точность указателя') } }
  $k = @(); foreach ($x in @($b.devices)) { if (PctEnDeviceSet $x.id ([bool]$x.old)) { $ok++ } else { $k += $x; [void]$bad.Add("устройство: $($x.name)") } }; $b.devices = $k
  if ($bad.Count) { PctMsBackupSave $b } else { $p = PctMsBackupPath; $t = Get-Date -Format 'yyyyMMdd-HHmmss-fff'; $n = $p -replace '\.json$', ".$t.done.json"; for ($i = 1; [IO.File]::Exists($n); $i++) { $n = $p -replace '\.json$', ".$t-$i.done.json" }; [IO.File]::Move($p, $n) }
  [pscustomobject]@{ Ok = $ok; Bad = @($bad) } }
