# «Устройства → Драйверы» (DRIVERS-1): что нужно — только чтение, без прав администратора. Ничего не ставит и не меняет.
# Источники: каталог Windows Update (Microsoft.Update.Session, поиск IsInstalled=0 and Type='Driver' — только официальные драйверы), устройства Win32_PnPEntity, версия сейчас — Win32_PnPSignedDriver.
# «Нет драйвера» — ConfigManagerErrorCode 28 (драйвер не установлен), 1 (устройство не настроено) и 18 (переустановить драйвер); выключенные (22) и системные (ROOT\…, класс System) — не показываю, только считаю.
# Связь «нет драйвера» ↔ обновление — только по HardwareID (DriverHardwareID обновления есть среди HardwareID устройства), без догадок по имени.
# Итог — run\drivers.json (UTF-8 без BOM): время, длительность, ошибка (nonet — нет связи с Windows Update, fail — другой сбой), обновления, устройства без драйвера, сколько скрыто.
# Стенд (только тесты): PCT_DRIVERS_FAKE=<json> — каталог (upd), устройства (dev), установленные драйверы (drv) из файла; err — код ошибки поиска (0x8024402C — нет связи), deverr — устройства не прочитались, part — каталог ответил не полностью.
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Драйверы'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
$Sw = [Diagnostics.Stopwatch]::StartNew()
$Fake = $null; if ($env:PCT_DRIVERS_FAKE) { $Fake = [IO.File]::ReadAllText($env:PCT_DRIVERS_FAKE, [Text.Encoding]::UTF8) | ConvertFrom-Json }
$Miss = @(28, 1, 18)

# Устройство простыми словами: по классу драйвера и HardwareID
function Word([string]$Cls, [string]$Hw) { $h = $Hw.ToLower()
  if ($Cls -in 'Display', 'Video') { return 'Видеокарта' }
  if ($Cls -eq 'AudioProcessingObject' -or $h -match 'effectpack|audioprocessingobject') { return 'Звуковые эффекты' }
  if ($Cls -in 'MEDIA', 'AudioEndpoint' -or $h -match 'audio') { return 'Звук' }
  if ($Cls -eq 'Net') { return 'Сеть' }; if ($Cls -eq 'Bluetooth' -or $h -match '^bth') { return 'Bluetooth' }
  if ($Cls -in 'Camera', 'Image') { return 'Камера' }; if ($Cls -in 'Printer', 'PrintQueue') { return 'Принтер' }; if ($Cls -eq 'Monitor') { return 'Монитор' }
  if ($Cls -in 'Mouse', 'Keyboard') { return 'Мышь или клавиатура' }; if ($Cls -eq 'Biometric') { return 'Отпечаток пальца' }
  if ($Cls -eq 'USB' -or $h -match '^usb\\') { return 'USB-устройство' }
  'Устройство' }
# «Microsoft Corporation» → «Microsoft»
function Maker([string]$M) { $m = "$M".Trim() -replace '\s+(Corporation|Corp\.?|Inc\.?|Ltd\.?|Co\.,? Ltd\.?)$', ''; if ($m -match '^\(|^Стандарт|^Standard') { '' } else { $m } }
function Day($d) { if ($d) { try { ([datetime]$d).ToString('yyyy-MM-dd') } catch { '' } } else { '' } }
function Ids($d) { @($d.HardwareID | Where-Object { $_ } | ForEach-Object { "$_".ToLower() }) }
# Системное устройство: Windows создаёт его сама (ROOT\…) или класс System — не показываю
function Sys($d) { "$($d.PNPDeviceID)" -match '^ROOT\\' -or "$($d.PNPClass)" -in 'System', 'SoftwareDevice' }

# err — nonet (нет связи с Windows Update) или fail; src — что не прочиталось: dev (устройства) или wu (каталог); part — каталог ответил не полностью (ResultCode 3)
$Out = [ordered]@{ v = 1; at = (Get-Date).ToString('s'); sec = 0; err = $null; code = $null; src = $null; part = $false; upd = @(); miss = @(); hidden = 0 }
# Кэш: сначала во временный файл, потом замена — окно не прочтёт половину
function Save { $Out.sec = [math]::Round($Sw.Elapsed.TotalSeconds, 1); $dir = PctDir 'run'; [void][IO.Directory]::CreateDirectory($dir); $f = "$dir\drivers.json"
  [IO.File]::WriteAllText("$f.tmp", ($Out | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false)); Move-Item -LiteralPath "$f.tmp" -Destination $f -Force }
function Hr($e) { while ($e.InnerException) { $e = $e.InnerException }; '0x{0:X8}' -f $e.HResult }
Step -Plan 'Смотрю устройства без драйвера', 'Ищу драйверы в каталоге Windows Update', 'Сверяю, что к чему подходит'

Step 'Смотрю устройства без драйвера'
# Список устройств не прочитался — не пишу «все с драйвером»: итог — сбой, каталог не ищу
try { $Devs = @(if ($Fake) { if ($Fake.deverr) { throw 'подмена: устройства не прочитались' }; $Fake.dev } else { Get-CimInstance Win32_PnPEntity -Property Name, PNPClass, PNPDeviceID, HardwareID, CompatibleID, ConfigManagerErrorCode -ErrorAction Stop }) }
catch { $Out.err = 'fail'; $Out.src = 'dev'; $Out.code = Hr $_.Exception; Write-Host "Устройства не прочитались: $($Out.code) $($_.Exception.Message)" -ForegroundColor DarkGray; Step -Fail 'Windows не отдала список устройств'; Save; return }
$Bad = @($Devs | Where-Object { [int]$_.ConfigManagerErrorCode -ne 0 })
$MissD = @($Bad | Where-Object { [int]$_.ConfigManagerErrorCode -in $Miss -and -not (Sys $_) })
$Out.hidden = $Bad.Count - $MissD.Count
Step -Done $(if ($MissD.Count) { "без драйвера: $($MissD.Count)" } else { 'все с драйвером' })

Step 'Ищу драйверы в каталоге Windows Update' -Hint 'Обычно около 10 секунд'
$Ups = @()
try {
  if ($Fake) { if ($Fake.err) { throw (New-Object Runtime.InteropServices.COMException 'подмена: поиск не прошёл', ([Convert]::ToInt32(("$($Fake.err)" -replace '^0x', ''), 16))) }; $Ups = @($Fake.upd) }
  else { $s = New-Object -ComObject Microsoft.Update.Session; $s.ClientApplicationID = 'Pomoshnik'; $q = $s.CreateUpdateSearcher(); $q.Online = $true; $q.ServerSelection = 2 # 2 — сам Windows Update, не сервер обновлений организации
    $r = $q.Search("IsInstalled=0 and Type='Driver'"); if ($r.ResultCode -notin 2, 3) { throw "ResultCode $($r.ResultCode)" }; $Out.part = $r.ResultCode -eq 3; $Ups = @($r.Updates) }
  if ($Fake -and $Fake.part) { $Out.part = $true }
  Step -Done "найдено: $($Ups.Count)"
} catch {
  $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; $x = Hr $e; $Out.src = 'wu'
  # Нет связи: ошибки передачи Windows Update (0x80244…), WinHTTP (0x80072…), HTTP-ответы (0x8019…), нет подключения (0x8024001F)
  $Out.err = $(if ($x -match '^0x(80244|80072|8019|8024001F)') { 'nonet' } else { 'fail' }); $Out.code = $x
  Write-Host "Поиск не прошёл: $x $($e.Message)" -ForegroundColor DarkGray
  Step -Warn $(if ($Out.err -eq 'nonet') { 'нет связи с Windows Update' } else { "Windows Update ответил ошибкой $x" })
}

Step 'Сверяю, что к чему подходит'
# Устройство по HardwareID: первое, у которого он есть среди HardwareID. Для версии «сейчас» — ещё и среди CompatibleID (так Windows подбирает драйвер видеокарте: pcien_…&dev_…)
function DevOf([string]$Hw, [switch]$Compat) { $h = $Hw.ToLower(); foreach ($d in $Devs) { if ((Ids $d) -contains $h -or ($Compat -and @($d.CompatibleID | ForEach-Object { "$_".ToLower() }) -contains $h)) { return $d } }; $null }
# Установленные драйверы — одним запросом (по одному устройству — секунды на каждое)
$Signed = @{}; foreach ($x in @(if ($Fake) { $Fake.drv } else { Get-CimInstance Win32_PnPSignedDriver -Property DeviceID, DriverVersion, DriverDate })) { if ($x.DeviceID -and $x.DriverVersion) { $Signed["$($x.DeviceID)".ToUpper()] = $x } }
foreach ($u in $Ups) {
  $hw = "$($u.DriverHardwareID)"; $d = DevOf $hw; $dc = $(if ($d) { $d } else { DevOf $hw -Compat }); $cls = "$($u.DriverClass)"; $w = Word $cls $hw; $mk = Maker $u.DriverManufacturer
  $ver = $(if ("$($u.Title)" -match '\(([\d.]+)\)\s*$') { $Matches[1] } else { '' })
  $isMiss = $d -and @($MissD | Where-Object { $_.PNPDeviceID -eq $d.PNPDeviceID }).Count -gt 0
  $cv = $(if ($dc -and -not $isMiss) { $Signed["$($dc.PNPDeviceID)".ToUpper()] })
  $Out.upd += [ordered]@{ t = ("$w $mk").Trim(); m = "$($u.DriverModel)"; cls = $cls; hw = $hw; ver = $ver; date = (Day $u.DriverVerDate); mb = [math]::Round([double]$u.MaxDownloadSize / 1MB, 1)
    gpu = $w -eq 'Видеокарта'; miss = [bool]$isMiss; cur = $(if ($cv) { [ordered]@{ ver = "$($cv.DriverVersion)"; date = (Day $cv.DriverDate) } } else { $null }); dev = "$(if ($dc) { $dc.PNPDeviceID })" } }
foreach ($d in $MissD) {
  $ids = Ids $d; $fix = -1; for ($k = 0; $k -lt $Out.upd.Count; $k++) { if ($ids -contains $Out.upd[$k].hw.ToLower()) { $fix = $k; break } }
  $w = Word "$($d.PNPClass)" "$(@($ids)[0])"; $m = "$($d.Name)".Trim(); if (-not $m -and $fix -ge 0) { $m = $Out.upd[$fix].m }; if (-not $m) { $m = "$(@($ids)[0])" }
  $Out.miss += [ordered]@{ t = $(if ($fix -ge 0) { $Out.upd[$fix].t } else { $w }); m = $m; code = [int]$d.ConfigManagerErrorCode; hw = @($ids); fix = $fix } }
Save
$n = $Out.upd.Count; $nm = @($Out.miss | Where-Object { $_.fix -lt 0 }).Count
Step -Done $(if ($Out.err) { 'без каталога' } elseif ($n + $nm -eq 0) { 'всё на месте' } else { "обновлений: $n, без драйвера: $($Out.miss.Count)" })
