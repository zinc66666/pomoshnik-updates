# «Устройства → Драйверы» (DRIVERS-2): поставить одно обновление драйвера из каталога Windows Update — только по кнопке. -Arg <UpdateID> (id строки из run\drivers.json, drivers-scan.ps1). Только с правами администратора.
# Шаги: (права) → это обновление в каталоге (поиск по UpdateID той же сессией Microsoft.Update.Session) → загрузка → точка восстановления (нет — вопрос, без «д» не ставлю) → копия нынешнего пакета
# (pnputil /export-driver <oem#.inf>; встроенный драйвер Windows и устройство без драйвера — копия не нужна; копия не вышла — вопрос) → установка (IUpdateInstaller, только это обновление) → что поставилось, нужна ли перезагрузка.
# Загрузка — до точки: сбой загрузки ничего не меняет и не тратит точку (Windows делает её не чаще раза в сутки).
# Чек: было → стало, где копия, точка. Журнал возврата (admin, запечатан): driver-del — убрать новый пакет (pnputil /delete-driver /uninstall), driver-add — поставить копию (/add-driver /install); «Вернуть прежний» — undo.ps1.
# После установки кэш поиска (run\drivers.json) удаляю: следующий вход в «Драйверы» ищет заново.
# Стенд (только тесты): PCT_DRVINST_FAKE=<json> — точка (restore ok|off|often|fail), загрузка (dl), установка (inst ok|fail), перезагрузка (reboot), pnputil (PctPnp в pct-core.ps1); каталог, устройства
# и драйверы (с InfName) — PCT_DRIVERS_FAKE. Действия — строками в <PCT_DRVINST_FAKE>.log. С повышением pct-core.ps1 убирает все PCT_*: подмена работает только без него
param([string]$Arg)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
$Host.UI.RawUI.WindowTitle = 'Установка драйвера'
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
function Enter { Write-Host "`nНажмите Enter, чтобы закрыть."; Read-Host | Out-Null }
$Fake = PctDrvFake; $Cat = $null; if ($env:PCT_DRIVERS_FAKE) { $Cat = [IO.File]::ReadAllText($env:PCT_DRIVERS_FAKE, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function FakeAct([string]$T) { if ($Fake) { PctDrvFakeLog $T } }
function Hr($e) { while ($e.InnerException) { $e = $e.InnerException }; '0x{0:X8}' -f $e.HResult }
function Yes($a) { "$a".Trim() -match '^(д|да|y|yes)$' }
function Dt($d) { if ($d) { try { ([datetime]$d).ToString('dd.MM.yyyy') } catch { '' } } }

Write-Host "`nУСТАНОВКА ДРАЙВЕРА`n" -ForegroundColor Cyan
Step -Safe
Step -Plan 'Нахожу драйвер в каталоге Windows Update', 'Скачиваю драйвер', 'Делаю точку восстановления', 'Сохраняю копию нынешнего драйвера', 'Ставлю драйвер'
# Права и номер — без своего шага (экран хода не прокручивается): шаг «Проверяю права» — только при отказе
# Стенд без подмены установки — не начинаю: тест иначе поставил бы драйвер по-настоящему
if (($env:PCT_ADMIN_FAKE -or $Cat) -and -not $Fake) { Step 'Проверяю права'; Step -Fail 'стенд без подмены установки'; Write-Host 'Стенд без PCT_DRVINST_FAKE — не начинаю.' -ForegroundColor Yellow; Enter; return }
if (-not (PctIsAdmin)) { Step 'Проверяю права'; Step -Fail 'нет разрешения Windows' -Do 'Нажми «Установить» ещё раз и выбери «Да» в окне Windows.'; Write-Host 'Ставить драйверы можно только с разрешения Windows. Ничего не менял.' -ForegroundColor Yellow; Enter; return }
if ($Arg -notmatch '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$') { Step 'Нахожу драйвер в каталоге Windows Update'; Step -Fail 'не знаю, какой драйвер ставить' -Do 'Нажми «Проверить» в «Драйверах» и выбери драйвер ещё раз.'; Write-Host "Неверный номер обновления: $Arg" -ForegroundColor DarkGray; Enter; return }

$lk = PctLock 'drivers-install'; if (-not $lk) { Step 'Нахожу драйвер в каталоге Windows Update'; Step -Fail 'уже ставлю другой драйвер' -Do 'Дождись, пока он встанет, и нажми «Установить» ещё раз.'; Enter; return }
try {
  Step 'Нахожу драйвер в каталоге Windows Update' -Hint 'Обычно около 10 секунд'
  $s = $null; $u = $null; $boot0 = $false
  try {
    if ($Fake) { FakeAct "search $Arg"; $u = @($Cat.upd | Where-Object { "$($_.id)" -eq $Arg })[0]; $boot0 = [bool]$Fake.boot0 }
    else { $s = New-Object -ComObject Microsoft.Update.Session; $s.ClientApplicationID = 'Pomoshnik'; $q = $s.CreateUpdateSearcher(); $q.Online = $true; $q.ServerSelection = 2 # 2 — сам Windows Update, как в поиске
      $r = $q.Search("IsInstalled=0 and Type='Driver' and UpdateID='$Arg'"); if ($r.ResultCode -notin 2, 3) { throw "ResultCode $($r.ResultCode)" }; if ($r.Updates.Count) { $u = $r.Updates.Item(0) }
      $boot0 = [bool]$s.CreateUpdateInstaller().RebootRequiredBeforeInstallation }
  } catch { $x = Hr $_.Exception; Write-Host "Поиск не прошёл: $x $($_.Exception.Message)" -ForegroundColor DarkGray
    Step -Fail $(if ($x -match '^0x(80244|80072|8019|8024001F)') { 'нет связи с Windows Update' } else { "Windows Update ответил ошибкой $x" }) -Do 'Проверь интернет и нажми «Установить» ещё раз.'; return }
  if (-not $u) { Step -Fail 'в каталоге его уже нет' -Do 'Нажми «Проверить» в «Драйверах»: список обновится.'; Write-Host 'Этого драйвера в каталоге больше нет или он уже стоит. Ничего не поставил.' -ForegroundColor Yellow; return }
  # Windows ждёт перезагрузку после прошлых обновлений — установка не пройдёт: не начинаю
  if ($boot0) { Step -Fail 'Windows ждёт перезагрузку' -Do 'Перезагрузи компьютер и нажми «Установить» ещё раз. Ничего не поставил.'; return }
  # Название простыми словами — из кэша поиска (только для текста); устройство — по HardwareID обновления, как в поиске
  $row = $null; try { $row = @(([IO.File]::ReadAllText("$(PctDir 'run')\drivers.json", [Text.Encoding]::UTF8) | ConvertFrom-Json).upd | Where-Object { "$($_.id)" -eq $Arg })[0] } catch { Write-Host "кэш поиска не прочитался: $($_.Exception.Message)" -ForegroundColor DarkGray }
  $Name = $(if ($row -and $row.t) { "$($row.t)" } else { "$($u.DriverModel)".Trim() }); if (-not $Name) { $Name = 'Драйвер' }
  $ver = $(if ("$($u.Title)" -match '\(([\d.]+)\)\s*$') { $Matches[1] } else { '' }); $mb = [double]$u.MaxDownloadSize / 1MB; $gpu = "$($u.DriverClass)" -in 'Display', 'Video'
  $hw = "$($u.DriverHardwareID)".ToLower(); $devs = @(if ($Cat) { $Cat.dev } else { Get-CimInstance Win32_PnPEntity -Property Name, PNPDeviceID, HardwareID, CompatibleID })
  $dev = @($devs | Where-Object { @($_.HardwareID | ForEach-Object { "$_".ToLower() }) -contains $hw })[0]; if (-not $dev) { $dev = @($devs | Where-Object { @($_.CompatibleID | ForEach-Object { "$_".ToLower() }) -contains $hw })[0] }
  function Cur { if (-not $dev) { return }; @($(if ($Cat) { $Cat.drv } else { Get-CimInstance Win32_PnPSignedDriver -Property DeviceID, DriverVersion, DriverDate, InfName }) | Where-Object { "$($_.DeviceID)" -eq "$($dev.PNPDeviceID)" })[0] }
  $cur = Cur; $old = "$($cur.InfName)"; $was = $(if ($cur -and $cur.DriverVersion) { "$($cur.DriverVersion)" } else { 'нет драйвера' })
  Step -Done "$Name$(if ($ver) { ", версия $ver" })"
  $rc = PctReceipt 'drivers-install' 'Установка драйвера'
  # Ничего не поставил: чек «не установил», возвращать нечего
  function NoInst([string]$Why) { [void](PctReceiptEnd $rc "Не установил: $Name" $null 'Ничего не поставил — возвращать нечего.' $Why) }

  Step 'Скачиваю драйвер' -Hint $(if ($gpu) { "$(($mb / 1024).ToString('0.#', [Globalization.CultureInfo]'ru-RU')) ГБ — это может занять несколько минут" } else { 'Обычно меньше минуты' })
  $c = $null
  try {
    if ($Fake) { FakeAct "download $Arg"; if ("$($Fake.dl)" -eq 'fail') { throw (New-Object Runtime.InteropServices.COMException 'подмена: загрузка не прошла', ([Convert]::ToInt32('80246008', 16))) } }
    else { if (-not $u.EulaAccepted) { throw 'обновление просит согласиться с условиями — без тебя не соглашаюсь' }
      $c = New-Object -ComObject Microsoft.Update.UpdateColl; [void]$c.Add($u); $d = $s.CreateUpdateDownloader(); $d.Updates = $c; $dr = $d.Download()
      if ($dr.ResultCode -ne 2) { throw "ResultCode $($dr.ResultCode), $('0x{0:X8}' -f $dr.GetUpdateResult(0).HResult)" } }
    Step -Done 'скачан'
  } catch { Write-Host "Загрузка не прошла: $(Hr $_.Exception) $($_.Exception.Message)" -ForegroundColor DarkGray; PctRcDo $rc $Name 'не скачался'
    Step -Fail 'не скачался' -Do 'Проверь интернет и нажми «Установить» ещё раз.'; NoInst 'Загрузка из каталога Windows Update не прошла. Прежний драйвер на месте.'; return }

  Step 'Делаю точку восстановления' -Hint 'Обычно до минуты'
  # → ok · off — защита системы выключена · often — Windows делает не больше одной точки в сутки · fail. Точка есть, только если число точек выросло
  $pt = 'fail'
  if ($Fake) { FakeAct 'restore'; $pt = $(if ($Fake.restore) { "$($Fake.restore)" } else { 'ok' }) }
  else { $n0 = -1; try { $n0 = @(Get-ComputerRestorePoint -ErrorAction Stop | ForEach-Object { [int]$_.SequenceNumber } | Measure-Object -Maximum).Maximum } catch { Write-Host "точки до не прочитались: $($_.Exception.Message)" -ForegroundColor DarkGray }; $w = $null; $er = ''
    try { Checkpoint-Computer -Description 'Помощник: перед установкой драйвера' -RestorePointType DEVICE_DRIVER_INSTALL -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable w } catch { $er = $_.Exception.Message }
    $n1 = -1; try { $n1 = @(Get-ComputerRestorePoint -ErrorAction Stop | ForEach-Object { [int]$_.SequenceNumber } | Measure-Object -Maximum).Maximum } catch { Write-Host "точки после не прочитались: $($_.Exception.Message)" -ForegroundColor DarkGray }
    $on = "$([Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore', 'RPSessionInterval', 1))" -ne '0'
    $pt = $(if ($n1 -gt $n0 -and $n1 -ge 0) { 'ok' } elseif (-not $on) { 'off' } elseif ($w) { 'often' } else { 'fail' }); Write-Host "Точка: $pt $er $w" -ForegroundColor DarkGray }
  if ($pt -eq 'ok') { Step -Done 'сделана'; PctRcDo $rc 'Точка восстановления' "сделана $((Get-Date).ToString('dd.MM.yyyy HH:mm'))" }
  else {
    $why = $(switch ($pt) { 'off' { 'защита системы выключена' } 'often' { 'Windows делает не больше одной точки в сутки' } default { 'Windows не смогла её сделать' } })
    Step -Warn "нет: $why"; PctRcDo $rc 'Точка восстановления' "нет: $why"
    Write-Host "Точку восстановления не сделал: $why."
    Write-Host 'Без неё вернуть всю Windows как было не выйдет. Прежний драйвер верну из копии.'
    if (-not (Yes (Read-Host 'Ставить драйвер без точки? (д/н)'))) { Step 'Не ставлю драйвер'; Step -Done 'ответ «Нет»'; PctRcDo $rc $Name 'не ставил'; NoInst 'Ответ «Нет»: без точки восстановления не ставил.'; return }
  }

  Step 'Сохраняю копию нынешнего драйвера'
  $bak = ''; $kept = ''
  if (-not $cur -or -not $cur.DriverVersion) { Step -Done 'не нужна: драйвера сейчас нет'; $kept = 'не нужна: драйвера не было' }
  elseif ($old -notmatch '^oem\d+\.inf$') { Step -Done 'не нужна: это встроенный драйвер Windows'; $kept = 'не нужна: встроенный драйвер Windows всегда в системе' }
  else {
    $dir = PctDrvBakDir "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$($old -replace '\.inf$')"; $r = PctPnp @('/export-driver', $old, $dir); $inf = @(try { [IO.Directory]::GetFiles($dir, '*.inf') } catch { Write-Host "копия не прочиталась: $($_.Exception.Message)" -ForegroundColor DarkGray })[0]
    if ((PctPnpOk $r) -and $inf -and (-not (PctElevated) -or (PctUndoTrusted $inf))) { $bak = $inf; Step -Done 'сохранена'; $kept = "reports\drivers-backup\$(Split-Path $dir -Leaf)" }
    else { Write-Host "Копия не вышла: код $($r.Code) $($r.Out -join ' ')" -ForegroundColor DarkGray; Step -Warn 'не сохранилась'; $kept = 'не сохранилась'
      Write-Host 'Копию нынешнего драйвера сохранить не вышло. Без неё «Вернуть прежний» только уберёт новый драйвер, а прежний Windows поставит, если он у неё остался.'
      if (-not (Yes (Read-Host 'Ставить драйвер без копии? (д/н)'))) { Step 'Не ставлю драйвер'; Step -Done 'ответ «Нет»'; PctRcDo $rc 'Копия прежнего драйвера' $kept; PctRcDo $rc $Name 'не ставил'; NoInst 'Ответ «Нет»: без копии прежнего драйвера не ставил.'; return } } }
  PctRcDo $rc 'Копия прежнего драйвера' $kept

  # Что лежит в хранилище драйверов до установки: новый пакет — тот, которого не было
  $e0 = PctPnp @('/enum-drivers'); $st0 = @($e0.Out | ForEach-Object { [regex]::Matches("$_", '(?i)\boem\d+\.inf\b') | ForEach-Object { $_.Value.ToLower() } })
  Step -Unsafe
  Step 'Ставлю драйвер' -Hint $(if ($gpu) { 'Экран мигнёт — так и должно быть' } else { 'Ничего не трогай' })
  $boot = $false; $part = $false # part — Windows ответила «с ошибками» (ResultCode 3): что-то могло встать — версию беру с устройства, возврат записываю
  try {
    if ($Fake) { FakeAct "install $Arg"; if ("$($Fake.inst)" -eq 'fail') { throw (New-Object Runtime.InteropServices.COMException 'подмена: установка не прошла', ([Convert]::ToInt32('80070643', 16))) }; $boot = [bool]$Fake.reboot; $part = "$($Fake.inst)" -eq 'part' }
    else { $i = $s.CreateUpdateInstaller(); $i.Updates = $c; $ir = $i.Install(); $ur = $ir.GetUpdateResult(0)
      if ($ur.ResultCode -notin 2, 3) { throw "ResultCode $($ir.ResultCode)/$($ur.ResultCode), $('0x{0:X8}' -f $ur.HResult)" }; $part = $ur.ResultCode -eq 3 -or $ir.ResultCode -eq 3; $boot = [bool]$ir.RebootRequired }
  } catch { Write-Host "Установка не прошла: $(Hr $_.Exception) $($_.Exception.Message)" -ForegroundColor DarkGray; PctRcDo $rc $Name 'не поставился'
    Step -Fail 'Windows не поставила драйвер' -Do 'Прежний драйвер на месте. Попробуй позже или позови помощь.'; NoInst 'Windows не поставила драйвер. Прежний драйвер на месте.'; return }

  # Что поставилось — в том же шаге «Ставлю драйвер»
  # Новый пакет: его не было в хранилище до установки И он подходит этому устройству (pnputil /enum-devices /drivers; команды нет — только пакет, который стоит устройству сейчас).
  # Пакет, который Windows в это же время поставила другому устройству, в возврат не попадает
  $now = Cur; $e1 = PctPnp @('/enum-drivers'); $mine = @(); if ($dev) { $ed = PctPnp @('/enum-devices', '/instanceid', "$($dev.PNPDeviceID)", '/drivers'); $mine = @(if (PctPnpOk $ed) { $ed.Out | ForEach-Object { [regex]::Matches("$_", '(?i)\boem\d+\.inf\b') | ForEach-Object { $_.Value.ToLower() } } }) }
  if (-not $mine.Count -and "$($now.InfName)" -match '^oem\d+\.inf$') { $mine = @("$($now.InfName)".ToLower()) }
  $new = @(); if ((PctPnpOk $e0) -and (PctPnpOk $e1)) { $new = @($e1.Out | ForEach-Object { [regex]::Matches("$_", '(?i)\boem\d+\.inf\b') | ForEach-Object { $_.Value.ToLower() } } | Where-Object { $st0 -notcontains $_ -and $mine -contains $_ } | Select-Object -Unique) }
  if (-not $new.Count -and "$($now.InfName)" -match '^oem\d+\.inf$' -and "$($now.InfName)" -ne $old) { $new = @("$($now.InfName)".ToLower()) } # пакет был в хранилище раньше — по устройству
  $nv = $(if ($part) { if ($now -and $now.DriverVersion) { "$($now.DriverVersion)" } else { 'не знаю' } } elseif ($boot -or -not $now -or -not $now.DriverVersion -or "$($now.DriverVersion)" -eq "$($cur.DriverVersion)") { $ver } else { "$($now.DriverVersion)" })
  PctRcDo $rc $Name "$was → $nv"
  # Журнал возврата: копия (driver-add), потом новый пакет (driver-del) — возврат идёт с последнего: сначала убрать новый, потом поставить копию
  # Журнал не записался — драйвер всё равно стоит: чек пишу, «Вернуть прежний» не обещаю
  $j = $null; $jerr = ''
  if ($new.Count) { try { $j = PctUndoNew 'drivers-install' 'Установка драйвера' -Admin; $tx = "прежний драйвер: $Name"
      if ($bak) { [void](PctUndoAdd $j @{ kind = 'driver-add'; bak = $bak; old = $old; oldver = "$($cur.DriverVersion)"; dev = "$($dev.PNPDeviceID)" } $tx) }
      foreach ($x in $new) { [void](PctUndoAdd $j @{ kind = 'driver-del'; new = $x; old = $old; dev = "$($dev.PNPDeviceID)" } $tx) }
      if (-not [IO.File]::Exists((PctUndoPath $j)) -or @($j.items).Count -lt $new.Count + [int][bool]$bak) { throw 'журнал записан не полностью' } }
    catch { Write-Host "Журнал возврата не записался: $($_.Exception.Message)" -ForegroundColor DarkGray; $j = $null; $jerr = 'Не записал, что вернуть: «Вернуть прежний» не сработает.' } }
  if ($part) { Step -Warn "поставлен с ошибками: $was → $nv" } else { Step -Done $(if ($boot) { 'поставлен, нужна перезагрузка' } else { "поставлен: $was → $nv" }) }
  $note = @(); if ($part) { $note += 'Windows сообщила об ошибках при установке. Если устройство работает плохо — верни прежний.' }; if ($boot) { $note += 'Нужна перезагрузка: драйвер заработает после неё.' }
  if ($j) { $note += 'Если вернёшь прежний, Windows Update может со временем снова поставить этот драйвер сам.' }
  $no = "$(if ($jerr) { $jerr } else { 'Не нашёл, какой пакет поставила Windows.' }) $(if ($pt -eq 'ok') { 'Вернуть — через точку восстановления.' } else { 'Если что-то не так — позови помощь.' })"
  [void](PctReceiptEnd $rc "Поставил драйвер: $Name" $j $no ($note -join ' '))
  # Кэш поиска устарел: следующий вход в «Драйверы» ищет заново
  try { [IO.File]::Delete("$(PctDir 'run')\drivers.json") } catch { Write-Host "кэш поиска не удалился: $($_.Exception.Message)" -ForegroundColor DarkGray }
  Write-Host "`nДрайвер поставлен.$(if ($boot) { ' Перезагрузи компьютер, когда будет удобно.' })" -ForegroundColor Green
} finally { PctUnlock $lk; Enter }
