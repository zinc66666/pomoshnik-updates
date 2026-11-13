param([switch]$Quiet)
function Warn($n, $v, $why, $fix) { $script:wn++; L ("  [..] {0,-24} {1}" -f $n, $v) 'Yellow'; if ($why) { L "       Причина: $why" 'Yellow' }; if ($fix) { L "       Что сделать: $fix" 'Yellow' } }
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\pct-core.ps1"
if ($Quiet) { PctCpu 'PCT-Health-Weekly' $PSCommandPath }
# «Ждать конца игры» (GUARDS-GAME): задача (-Quiet) при игре на весь экран ждёт до 7 мин (задача — до 10 мин, проверка — около минуты); не дождалась — следующий запуск
if ($Quiet -and -not (PctGame 420)) { return }
$Host.UI.RawUI.WindowTitle = 'Состояние ноутбука'
try { $Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size(112, 3000); $Host.UI.RawUI.WindowSize = New-Object Management.Automation.Host.Size(112, 48) } catch {}
$log = New-Object Collections.Generic.List[string]; $script:bad = 0; $script:wn = 0
function L($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c; $log.Add($t) }
function Ok($n, $v) { L ("  [OK] {0,-24} {1}" -f $n, $v) 'Green' }
function Info($n, $v) { L ("  [..] {0,-24} {1}" -f $n, $v) 'Gray' }
# Находка — и в окно: «Стоит поправить» на главной (Step -Find); $sc — инструмент, который её чинит (имя файла), или пусто
function Bad($n, $v, $why, $fix, $sc) { $script:bad++; L ("  [!!] {0,-24} {1}" -f $n, $v) 'Red'; if ($why) { L "       Причина: $why" 'Yellow' }; if ($fix) { L "       Что сделать: $fix" 'Yellow' }; Step -Find "$n — $v", $why, $sc }
# Шаги для окна Помощника (Step из run.ps1); при прямом запуске — обычными строками
if (-not (Test-Path function:Step)) { function Step($t, $Hint, $Done, $Warn, $Fail, $Do, $Plan, $Find, [switch]$Safe, [switch]$Unsafe) { if ($Plan -or $Find -or $Safe -or $Unsafe) { return }; $x = "$Done$Warn$Fail"; if ($x) { Write-Host "  → $x" -ForegroundColor DarkGray } else { Write-Host "• $t" -ForegroundColor DarkCyan } } }
# Раздел проверки — шаг окна: без [!!] и жёлтых [..] в разделе — ✓, с ними — ✓ с замечанием
function Sec([string]$t, [string]$h = '') { SecEnd; Step $t -Hint $h; $script:sb = $script:bad; $script:sw = $script:wn; $script:so = $true }
function SecEnd { if ($script:so) { $script:so = $false; $n = $script:bad - $script:sb; $w = $script:wn - $script:sw
    if ($n) { Step -Warn "замечаний: $n" } elseif ($w) { Step -Warn "проверь: $w" } else { Step -Done 'в порядке' } } }
Step -Plan 'Проверяю систему', 'Проверяю диски', 'Проверяю батарею', 'Читаю сбои за 7 дней', 'Проверяю интернет', 'Проверяю защиту', 'Проверяю копию и мусор', 'Проверяю Помощника', 'Проверяю YouTube, Discord и обход'
L ("`nСОСТОЯНИЕ НОУТБУКА — {0:dd.MM.yyyy HH:mm}  (около 15 секунд)`n" -f (Get-Date)) 'Cyan'
$os = Get-CimInstance Win32_OperatingSystem; $since = (Get-Date).AddDays(-7)

Sec 'Проверяю систему' 'Замеряю процессор 3 секунды'; L '— Система' 'Cyan'
$up = (Get-Date) - $os.LastBootUpTime; $ut = "{0} дн. {1} ч" -f [math]::Floor($up.TotalDays), $up.Hours
if ($up.TotalDays -ge 7) { Bad 'Без перезагрузки' $ut 'Windows долго не перезапускалась — копится мусор в памяти, может тормозить.' 'Пуск -> Выключение -> Перезагрузка (закрыть крышку — это не перезагрузка).' } else { Ok 'Без перезагрузки' $ut }
$p1 = @{}; Get-Process | ForEach-Object { $p1[$_.Id] = $_.CPU }; $t1 = Get-Date; Start-Sleep 3
$sec = ((Get-Date) - $t1).TotalSeconds; $cores = [Environment]::ProcessorCount
$pr = Get-Process | Where-Object { $_.Id -ne $PID } | ForEach-Object { [pscustomobject]@{ N = $_.ProcessName; C = $(if ($p1.ContainsKey($_.Id) -and $_.CPU) { ($_.CPU - $p1[$_.Id]) / $sec / $cores * 100 } else { 0 }); M = $_.WorkingSet64 } } |
  Group-Object N | ForEach-Object { [pscustomobject]@{ N = $_.Name; C = ($_.Group | Measure-Object C -Sum).Sum; M = ($_.Group | Measure-Object M -Sum).Sum } }
$cpu = ($pr | Where-Object N -ne 'Idle' | Measure-Object C -Sum).Sum
$topC = ($pr | Sort-Object C -Descending | Select-Object -First 3 | ForEach-Object { "{0} {1:N0}%" -f $_.N, $_.C }) -join ', '
if ($cpu -ge 70) { Bad 'Процессор' ("занят на {0:N0}%" -f $cpu) "Больше всего грузят: $topC." 'Закрой лишние программы. Если грузит незнакомая — запусти «1. Проверка безопасности».' } else { Ok 'Процессор' ("занят на {0:N0}%  (больше всего: $topC)" -f $cpu) }
$ram = 100 - $os.FreePhysicalMemory * 100 / $os.TotalVisibleMemorySize
$topM = ($pr | Sort-Object M -Descending | Select-Object -First 3 | ForEach-Object { "{0} {1:N0} МБ" -f $_.N, ($_.M / 1MB) }) -join ', '
$ramT = "занята на {0:N0}% из {1:N1} ГБ" -f $ram, ($os.TotalVisibleMemorySize / 1MB)
if ($ram -ge 85) { Bad 'Память' $ramT "Больше всего занимают: $topM." 'Закрой лишние вкладки браузера и программы, которые сейчас не нужны.' } else { Ok 'Память' "$ramT  (больше всего: $topM)" }
$tz = Get-CimInstance -Namespace root\wmi MSAcpi_ThermalZoneTemperature | ForEach-Object { $_.CurrentTemperature / 10 - 273.15 } | Measure-Object -Maximum
if ($tz.Count) { $tt = "{0:N0} °C (датчик системы, примерно)" -f $tz.Maximum
  if ($tz.Maximum -ge 90) { Bad 'Температура' $tt 'Ноутбук перегревается — от этого тормоза и внезапные выключения.' 'Ставь на твёрдую ровную поверхность (не на кровать). Раз в 1–2 года — чистка от пыли в сервисе.' } else { Ok 'Температура' $tt } }
else { Info 'Температура' 'датчик недоступен в этой сборке' }
$st = @(Get-CimInstance Win32_StartupCommand).Count
if ($st -gt 12) { Bad 'Автозагрузка' "$st программ" 'Слишком много программ запускается вместе с Windows — дольше включение и меньше памяти.' 'Ярлык «10. Автозагрузка» — отключи ненужное.' 'startup-all.ps1' } else { Ok 'Автозагрузка' "$st программ" }

Sec 'Проверяю диски'; L "`n— Диски" 'Cyan'
foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
  $fr = $d.FreeSpace / 1GB; $pc = $d.FreeSpace * 100 / $d.Size; $dt = "свободно {0:N1} ГБ из {1:N0} ГБ ({2:N0}%)" -f $fr, ($d.Size / 1GB), $pc
  if ($fr -lt 10 -or $pc -lt 10) { Bad "Диск $($d.DeviceID)" $dt 'Мало места — Windows и программы начинают тормозить, обновления не ставятся.' 'Ярлыки «9. Очистка мусора» и «6. Что занимает место на диске».' } else { Ok "Диск $($d.DeviceID)" $dt } }
foreach ($x in PctDisks) {
  $pd = $x.Pd; $rc = $x.Rc; $nm = "$($pd.FriendlyName)"; if ($nm.Length -gt 22) { $nm = $nm.Substring(0, 22) }
  $dt = "$($pd.MediaType) $([math]::Round($pd.Size / 1GB)) ГБ" + $(if (-not $rc) { ', износ и температура: нет данных' } elseif ($rc.Wear -ne $null) { ", износ $($rc.Wear)%" }) + $(if ($rc.Temperature) { ", $($rc.Temperature) °C" })
  if ($pd.HealthStatus -ne 'Healthy' -and $pd.HealthStatus -ne 0) { Bad $nm "$dt, состояние: $($pd.HealthStatus)" 'Диск сообщает о неисправности — может скоро отказать.' 'Сразу скопируй важные файлы на флешку или в облако и покажи ноутбук мастеру.' }
  elseif ($rc.Wear -ge 70) { Bad $nm $dt 'Диск сильно изношен.' 'Сделай копию важных файлов; планируй замену диска.' }
  elseif ($rc.Temperature -ge 65) { Bad $nm $dt 'Диск горячий.' 'Проверь, не перекрыты ли решётки ноутбука.' }
  else { Ok $nm "$dt, исправен" } }

Sec 'Проверяю батарею'; L "`n— Батарея" 'Cyan'
# От сети — статусы 2, 3, 6–9 (PctBattery)
$bx = PctBattery; $b = $bx.B
if ($b) { $fc = $bx.Fc; $dc = $bx.Dc; $cy = $bx.Cy
  $bt = "заряд $($b.EstimatedChargeRemaining)%, " + $(if ($bx.Ac) { 'от сети' } else { 'от батареи' }) + $(if ($fc) { ", ёмкость {0:N1} Вт·ч" -f ($fc / 1000) }) + $(if ($cy) { ", циклов $cy" })
  if ($dc -and $fc -and (100 - $fc * 100 / $dc) -ge 40) { Bad 'Батарея' $bt ("Аккумулятор изношен на {0:N0}% — держит заметно меньше нового." -f (100 - $fc * 100 / $dc)) 'Замена аккумулятора в сервисе, если не хватает времени работы.' }
  elseif ($cy -ge 800) { Warn 'Батарея' $bt "Аккумулятор прошёл $cy циклов зарядки (обычно рассчитан на 500–1000) — ёмкость падает." 'Если ноутбук мало держит без зарядки — замена аккумулятора в сервисе.' }
  else { Ok 'Батарея' $bt } }
$plan = (powercfg /getactivescheme) -replace '^.*\((.*)\).*$', '$1'; Info 'Схема питания' $plan

Sec 'Читаю сбои за 7 дней' 'Журнал Windows и устройства'; L "`n— Сбои за 7 дней" 'Cyan'
$cr = PctCrash $since; $kp = $cr.Kp; $bs = $cr.Bsod
if ($bs) { Bad 'Синий экран' "$bs раз" 'Windows падала с ошибкой — чаще всего из-за драйвера или перегрева.' 'Запиши, что делала в тот момент, и сообщи тому, кто настраивал ноутбук.' } else { Ok 'Синий экран' 'не было' }
if ($kp) { Bad 'Аварийное выключение' "$kp раз" 'Ноутбук выключился неправильно: завис, сел в ноль или выключен долгим нажатием кнопки.' 'Выключай через Пуск. Если зависает сам — проверь температуру и сообщи.' } else { Ok 'Аварийное выключение' 'не было' }
# Вылеты без WLANExt и svchost-служб (PctCrash): падают в этой сборке с сентября 1–3 раза в день без последствий — не пугать ими.
$ae = $cr.Apps
$aeBad = @($ae | Where-Object Count -ge 3)
if ($aeBad) { Bad 'Вылеты программ' (($aeBad | Select-Object -First 3 | ForEach-Object { "$($_.Name) — $($_.Count) раз" }) -join ', ') 'Программа часто закрывается с ошибкой.' 'Обнови её (ярлык «8. Обновить программы») или переустанови.' }
else { Ok 'Вылеты программ' $(if ($ae) { "редкие ($(($ae | Measure-Object Count -Sum).Sum) за неделю)" } else { 'не было' }) }
$dv = $cr.Drv
if ($dv) { Bad 'Драйверы' (($dv | Select-Object -First 3 | ForEach-Object { "$(if ($_.Name) { $_.Name } else { $_.PNPDeviceID }) (код $($_.ConfigManagerErrorCode))" }) -join '; ') 'Устройство работает с ошибкой или без драйвера.' 'Сообщи тому, кто настраивал ноутбук (название устройства — выше).' } else { Ok 'Драйверы' 'все устройства работают' }

Sec 'Проверяю интернет' 'Жду ответ ya.ru, до 10 с'; L "`n— Интернет" 'Cyan'
$ms = PctPing
if ($null -eq $ms) { Bad 'Интернет' 'нет связи' 'Нет связи с интернетом (или с роутером).' 'Ярлык «2. Починить интернет». Не помогло — перезагрузи роутер (из розетки на 30 секунд).' 'fix-internet.ps1' }
else {
  if ($ms -ge 150) { Bad 'Интернет' ("есть, но медленный отклик {0:N0} мс" -f $ms) 'Слабый Wi-Fi или загружена сеть (кто-то качает).' 'Сядь ближе к роутеру, поставь на паузу закачки.' } else { Ok 'Интернет' ("работает, отклик {0:N0} мс" -f $ms) } }
if (Get-Process winws) { Ok 'Обход блокировок' 'zapret работает (YouTube, Discord)' } else { Bad 'Обход блокировок' 'zapret выключен' 'Без него YouTube и Discord в России грузятся плохо или не грузятся.' 'Ярлык «12. Перезапустить обход блокировок».' 'zapret-repick.ps1' }
Info 'Программа Happ' $(if (Get-Process happd, Happ) { 'открыта (VPN включается в ней самой)' } else { 'закрыта (нужна только для Instagram, X, Telegram-веб)' })

Sec 'Проверяю защиту'; L "`n— Защита" 'Cyan'
if (PctUac) { Ok 'Контроль UAC' 'включён' } else { Bad 'Контроль UAC' 'ВЫКЛЮЧЕН' 'Программы могут менять систему без спроса.' 'Сообщи тому, кто настраивал ноутбук.' }
# Запрос не прошёл (служба брандмауэра не отвечает) — не знаю, включён ли: не «включён»
$fw = @(PctFw); $fo = @($fw | Where-Object { -not $_.Enabled })
if (-not $fw) { Warn 'Брандмауэр' 'не удалось проверить' 'Windows не ответил на запрос о брандмауэре.' 'Открой «Безопасность Windows» → «Брандмауэр и защита сети» и посмотри там.' }
elseif ($fo) { Bad 'Брандмауэр' "выключен: $(($fo.Name) -join ', ')" 'Сетевая защита отключена.' 'Сообщи тому, кто настраивал ноутбук.' } else { Ok 'Брандмауэр' 'включён' }
$gt = @(Get-ScheduledTask -TaskName 'PCT-*' | Where-Object State -eq 'Disabled')
if ($gt) { Bad 'Сторожа' "отключены: $(($gt.TaskName) -join ', ')" 'Автоматические проверки не работают.' 'Сообщи тому, кто настраивал ноутбук.' } else { Ok 'Сторожа' 'работают' }
# Только строки сторожей (PctAlerts): подбор обхода, обновление и эта проверка пишут в тот же журнал
$al = @(PctAlerts $since (PctData 'alerts.log' 'guard'))
if ($al) { Bad 'Предупреждения сторожа' "$($al.Count) за неделю, последнее: $($al[-1].Substring(0, [math]::Min(70, $al[-1].Length)))" 'Сторож заметил подозрительный файл или новую программу в автозапуске.' 'Ярлык «1. Проверка безопасности».' } else { Ok 'Предупреждения сторожа' 'за неделю не было' }

L ''
Sec 'Проверяю копию и мусор' 'Считаю временные файлы'; L "`n— Резервная копия и мусор" 'Cyan'
$bk = Get-Content "$(PctDir 'reports')\backup-last.txt" -Encoding UTF8 -TotalCount 1
if (-not $bk) { Bad 'Резервная копия' 'ни разу не делалась' 'Если диск сломается, фото и документы пропадут: копии нет.' 'Вставь флешку и нажми «14. Резервная копия».' 'backup.ps1' }
else { $bd = [datetime]::ParseExact($bk.Substring(0, 16), 'yyyy-MM-dd HH:mm', $null); $ba = [math]::Floor(((Get-Date) - $bd).TotalDays)
  if ($ba -gt 14) { Bad 'Резервная копия' "$ba дн. назад" 'Копия устарела — новые фото и документы в неё не попали.' 'Вставь флешку и нажми «14. Резервная копия».' 'backup.ps1' } else { Ok 'Резервная копия' "$ba дн. назад" } }
$jk = PctTreeBytes "$env:LOCALAPPDATA\Temp", "$env:windir\Temp", "$env:LOCALAPPDATA\CrashDumps", "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
if ($jk -gt 1GB) { Bad 'Мусор' ("{0:N1} ГБ временных файлов" -f ($jk / 1GB)) 'Накопились временные файлы.' 'Ярлык «9. Очистка мусора».' 'big-clean.ps1' } else { Ok 'Мусор' ("{0:N0} МБ — чистить не нужно" -f ($jk / 1MB)) }
if (@(Get-Process winws).Count -gt 1) { Bad 'Обход блокировок' 'запущен дважды' 'zapret запущен два раза — сайты могут грузиться хуже.' 'Ярлык «12. Перезапустить обход блокировок».' 'zapret-repick.ps1' }
# HOME-FACE-2c: свежий ли Помощник и работает ли его обновление. Без сети и без updater.ps1 — только его файлы (version.txt, run\update-status.json, reports\updates.log) и Планировщик.
# Подпись — только по журналу и итогу обновления, RSA не повторяю. PCT_UPDTASK_FAKE: none — задачи нет, off — выключена, иначе включена (как в pct-core.ps1)
function HelperCheck { $inv = [Globalization.CultureInfo]::InvariantCulture; $wk = (Get-Date).AddDays(-7); $man = 'Проверь вручную: «Помощь» → «Проверить обновления Помощника».'
  $hv = "$(Get-Content -LiteralPath "$(PctDir 'helpers')\version.txt" -TotalCount 1)".Trim(); if ($hv -notmatch '^\d+(\.\d+){1,3}$') { $hv = 'не известна' }
  $u = $null; try { $u = [IO.File]::ReadAllText("$(PctDir 'run')\update-status.json", [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop } catch {}
  $ut = [datetime]::MinValue; if ($u.t -is [datetime]) { $ut = $u.t } elseif ("$($u.t)" -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$') { $ut = [datetime]::ParseExact("$($u.t)", 's', $inv) }
  # итог обновления — в окно только без путей, почты и длинных строк: run\ пишут и без повышения
  $um = "$($u.msg)".Trim().TrimEnd('.', '…'); if ($um -match '[A-Za-z]:\\|\\\\|@' -or $um.Length -gt 120) { $um = '' }
  $okT = if ("$($u.state)" -in 'uptodate', 'done') { $ut } else { [datetime]::MinValue }
  $ue = "$env:PCT_UPDTASK_FAKE"; $ts = if ($ue -in 'none', 'off') { $ue } elseif ($ue) { 'on' } else { try { $s = New-Object -ComObject Schedule.Service; $s.Connect(); if ($s.GetFolder('\').GetTask('PCT-Helper-Update').Enabled) { 'on' } else { 'off' } } catch { 'none' } }
  $sg = [datetime]::MinValue; foreach ($x in @(Get-Content -LiteralPath "$(PctDir 'reports')\updates.log" -Encoding UTF8 -Tail 200)) { if ($x -match '^(\d{4}-\d\d-\d\d \d\d:\d\d) ПОДПИСЬ НЕ СОВПАЛА') { $sg = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm', $inv) } }
  $sig = ("$($u.state)" -eq 'error' -and $um -match '^Подпись') -or ($sg -ge $wk.AddMinutes(-1) -and ($okT -eq [datetime]::MinValue -or $sg -gt $okT.AddMinutes(-1))) # MinValue.AddMinutes(-1) — исключение
  if ($ts -ne 'on') { Bad 'Помощник' 'не обновляется сам' "Задача обновления $(if ($ts -eq 'off') { 'выключена' } else { 'не найдена' }) — исправления не придут сами." 'Включи «Обновление Помощника» в разделе «Сторожа».' }
  if ("$($u.state)" -eq 'error' -and $um -match 'Не скачался|не прошёл проверку|не установилась|не запустилась|дополнить') { Bad 'Помощник' 'новая версия не встала' "$um." $man }
  elseif ($sig) { Bad 'Помощник' 'обновление отклонено' 'Подпись обновления не совпала — Помощник его не поставил.' 'Сообщи тому, кто настраивал ноутбук.' }
  elseif ($okT -lt $wk) {
    if ("$($u.state)" -in 'checking', 'downloading', 'installing' -and $ut -ge (Get-Date).AddHours(-1)) { if ($ts -eq 'on') { Ok 'Помощник' "версия $hv — обновление идёт сейчас" } }
    elseif ($ut -ge $wk -and $um) { Warn 'Помощник' 'обновления не проверились' "$um." 'Проверь интернет — Помощник попробует сам.' }
    elseif ($ut -eq [datetime]::MinValue) { Bad 'Помощник' 'обновления не проверялись' 'Помощник ни разу не спрашивал о новой версии — исправления не приходят.' $man }
    else { Bad 'Помощник' ('обновления не проверялись {0} дн.' -f [math]::Floor(((Get-Date) - $ut).TotalDays)) $(if ($um -and "$($u.state)" -eq 'error') { "$um." } else { 'Помощник давно не спрашивал о новой версии — исправления не приходят.' }) $man } }
  elseif ($ts -eq 'on') { Ok 'Помощник' "версия $hv — обновления проверяются" } }
Sec 'Проверяю Помощника' 'Читаю версию и журнал обновлений'; L "`n— Помощник" 'Cyan'; HelperCheck
Sec 'Проверяю YouTube, Discord и обход' 'Жду ответ сайтов и github.com, до 30 с'; L "`n— YouTube, Discord и версия обхода блокировок" 'Cyan'
function UpH($u) { $r = & curl.exe -s -o NUL -w '%{http_code}' --max-time 8 $u 2>$null; [bool]($r -and $r -ne '000') }
$ytdc = @(foreach ($x in @(@('YouTube', 'https://www.youtube.com'), @('Discord', 'https://discord.com'))) { if (-not (UpH $x[1])) { $x[0] } })
if (-not ((UpH 'https://ya.ru') -or (UpH 'https://vk.com'))) { Warn 'YouTube и Discord' 'не проверено — нет интернета' '' '' }
elseif ($ytdc) { Bad 'YouTube и Discord' "не открываются: $($ytdc -join ', ')" 'Провайдер изменил блокировку — прежний способ обхода перестал работать.' 'Помощник → «Не работает YouTube или Discord» (подберёт новый способ сам).' 'zapret-repick.ps1'
  if (-not $Quiet) { Write-Host '       Подобрать новый способ прямо сейчас (до 10 минут)? Напиши д и Enter.' -ForegroundColor Cyan; if ((Read-Host) -match '^\s*[дДyY]') { & "$(PctDir 'helpers')\zapret-repick.ps1" } } }
else { Ok 'YouTube и Discord' 'открываются' }
$zc = Get-Content "$(PctDir 'helpers')\zapret-cmd.txt" -Encoding UTF8 -TotalCount 1
$zd = if ($zc) { Split-Path (Split-Path $zc) } else { Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Recurse -Depth 3 -Filter 'winws.exe' | Select-Object -First 1 | ForEach-Object { Split-Path (Split-Path $_.FullName) } }
$zm = Select-String -LiteralPath "$zd\service.bat" -Pattern 'LOCAL_VERSION=([\d.]+)' | Select-Object -First 1; $lv = if ($zm) { $zm.Matches[0].Groups[1].Value }
$rv = "$(& curl.exe -s --max-time 8 https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/version.txt 2>$null)".Trim(); if ($rv -notmatch '^\d+(\.\d+)+$') { $rv = $null }
if (-not $lv -or -not $rv) { Warn 'Версия zapret' 'проверить не удалось' '' '' }
elseif ([version]$rv -gt [version]$lv) { Bad 'Версия zapret' "вышла $rv, стоит $lv" 'В новых версиях есть способы обхода против новых блокировок.' "Напиши тому, кто настраивал ноутбук: «вышел zapret $rv»." }
else { Ok 'Версия zapret' "$lv — последняя" }
$hf = Get-HotFix | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($hf) { $ha = [int]((Get-Date) - $hf.InstalledOn).TotalDays
  if ($ha -gt 60) { Bad 'Обновления Windows' "последнее $ha дн. назад" 'Без обновлений защиты Windows уязвима, а антивируса на этой сборке нет.' 'Напиши тому, кто настраивал ноутбук: «обновления Windows давно не ставились».' } else { Ok 'Обновления Windows' "последнее $ha дн. назад" } }
$pacF = Test-Path (PctData 'smart-proxy-on.txt' 'helpers'); $pacR = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').AutoConfigURL -like 'data:application/x-ns-proxy-autoconfig*'
if ($pacF -and -not $pacR) { & "$(PctDir 'helpers')\smart-proxy.ps1" -Apply; Warn 'Заблокированные сайты' 'обход выключился — включил обратно' 'Его могла сбросить другая программа.' '' }
elseif ($pacF) { Ok 'Заблокированные сайты' 'открываются через Happ сами' } else { Warn 'Заблокированные сайты' 'обход выключен' '' 'Помощник → «Заблокированные сайты», чтобы Instagram, X и другие открывались сами.' }
if (-not (Get-NetTCPConnection -State Listen -LocalPort (PctSocksPort) -ErrorAction SilentlyContinue)) { Bad 'Happ' 'не подключён' 'Без него не работают Telegram и заблокированные сайты.' 'Открой Happ и нажми большую кнопку подключения.' 'happ-connect.ps1' }
SecEnd
if ($script:bad) { L "ИТОГ: требует внимания — $($script:bad). Смотри строки [!!] и «Что сделать»." 'Yellow' } else { L 'ИТОГ: всё в порядке.' 'Green' }
$R = PctDir 'reports'; New-Item -ItemType Directory -Force $R | Out-Null
[IO.File]::WriteAllLines(("$R\состояние-{0:yyyy-MM-dd_HH-mm}.txt" -f (Get-Date)), $log, (New-Object Text.UTF8Encoding $true))
Get-ChildItem $R -Filter 'состояние-*.txt' | Sort-Object Name -Descending | Select-Object -Skip 20 | Remove-Item -Force
L "Отчёт сохранён в $R"
if ($Quiet) { if ($script:bad) { $global:PctCpuR = 'warn'; . (PctNotifyPath); Send-Notify "$(if ($b) { 'Ноутбуку' } else { 'Компьютеру' }) нужно внимание" "Замечаний: $($script:bad). Открой «Помощник» на рабочем столе → «Проверить $(if ($b) { 'ноутбук' } else { 'компьютер' })»." } } else { Write-Host "`nНажми Enter, чтобы закрыть."; Read-Host | Out-Null }